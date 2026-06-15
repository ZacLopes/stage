import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme.dart';
import '../../../services/analytics_service.dart';
import '../../../services/facebook_events_service.dart';
import '../../../services/notifications_service.dart';
import '../data/feed_pager.dart';
import '../jobs_viewmodel.dart';
import '../models/job.dart';
import '../widgets/company_request_sheet.dart';
import 'job_details_sheet.dart';

/// FASE 2 (T2.2): modo LISTA do feed — atrás de `feed_list_v1`, opt-in via
/// toggle (D-6: swipe segue padrão). Embutido no body da aba Vagas pelo
/// JobsSwipeScreen quando `vm.feedMode == 'list'`.
///
/// - Scroll infinito por cursor keyset (vm.loadMoreFeedPage).
/// - Célula compacta: empresa, título, chips de razão (reason_* do RPC),
///   bolsa ("A combinar" quando null — 83% não têm, B10) e frescor.
/// - Gesto: direita salva / esquerda descarta → MESMA swipe_actions do
///   swiper + job_swiped com feed_mode:'list'.
/// - Fim da lista: footer simples (T2.3/PR3 troca pelos estados de
///   exaustão honestos + "Pedir uma empresa").
class JobsListView extends StatefulWidget {
  const JobsListView({super.key});

  @override
  State<JobsListView> createState() => _JobsListViewState();
}

class _JobsListViewState extends State<JobsListView> {
  final ScrollController _scroll = ScrollController();

  /// Dedupe do job_card_shown da lista (exposição 1x por vaga/sessão).
  final Set<String> _shownIds = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >
        _scroll.position.maxScrollExtent - 400) {
      context.read<JobsViewModel>().loadMoreFeedPage();
    }
  }

  void _trackCellShown(
      Job job, FeedPageRow? row, int index, bool scoreVisible) {
    if (!_shownIds.add(job.id)) return;
    final vm = context.read<JobsViewModel>();
    // match_score aqui é o score determinístico do RANKING server-side
    // (sem skills — D-2); o card do swipe continua usando IA+fallback.
    // ignore: unawaited_futures
    Analytics.shared.jobCardShown(
      jobId: job.id,
      matchScore: row?.score ?? 0,
      positionInFeed: index,
      companyId: job.companyId,
      area: job.area,
      modality: job.workModelRaw ?? job.workModel,
      salaryBucket: bucketSalary(job.salaryMin, job.salaryMax),
      locationBucket: bucketLocation(job.locationCity, job.locationState),
      feedMode: 'list',
      scoreVisible: scoreVisible, // T2.4 — o que a célula mostrou de fato
      holdoutVariant: vm.holdoutVariant,
    );
  }

  Future<void> _onCellSwipe(Job job, String action, int index) async {
    final vm = context.read<JobsViewModel>();
    if (action == 'liked') {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    final row = vm.feedRowFor(job.id);
    unawaited(vm.swipeJobFromList(job, action));
    // ignore: unawaited_futures
    Analytics.shared.jobSwiped(
      jobId: job.id,
      action: action == 'liked' ? 'like' : 'reject',
      matchScore: (row?.score ?? 0) > 0 ? row!.score : null,
      matchSource: 'feed_rank_v1',
      applicationMethod: job.applicationMethod,
      positionInFeed: index,
      companyId: job.companyId,
      companyName: job.companyName,
      modality: job.workModelRaw ?? job.workModel,
      salaryBucket: bucketSalary(job.salaryMin, job.salaryMax),
      locationBucket: bucketLocation(job.locationCity, job.locationState),
      feedMode: 'list',
      // T2.4 — holdout: célula mostra banda/chips só com score visível e
      // alguma dimensão de ranking declarada.
      scoreVisible: vm.matchScoreVisible && vm.profilePrefs != null,
      holdoutVariant: vm.holdoutVariant,
    );
  }

  /// T2.3 — CTA de alerta do estado A (espelho do _enableNewJobsAlert do
  /// swipe): garante permissão de push pro digest diário avisar.
  Future<void> _enableNewJobsAlert() async {
    HapticFeedback.lightImpact();
    final granted = await NotificationsService.shared
        .requestPermission(fallbackToSettings: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'Boa! Te avisamos quando entrarem vagas novas. 🔔'
              : 'Ative as notificações nos Ajustes pra receber o alerta.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openDetails(Job job) {
    HapticFeedback.lightImpact();
    Analytics.shared.jobDetailsOpened(
      jobId: job.id,
      matchScore: job.matchScore,
    );
    // Facebook ViewContent — espelho do _openJobDetails do swipe.
    // ignore: unawaited_futures
    FacebookEventsService.shared.logViewContent(
      jobId: job.id,
      jobTitle: job.title,
      company: job.company?.name,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => JobDetailsSheet(job: job),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<JobsViewModel>();
    final jobs = vm.listJobs;

    if (vm.isLoading && jobs.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () {
        // ignore: unawaited_futures
        Analytics.shared.feedRefreshPulled(subTab: 'para_voce');
        return vm.reloadJobs();
      },
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: jobs.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= jobs.length) {
            return _ListFooter(
              isLoadingMore: vm.isLoadingMore,
              hasMore: vm.hasMorePages,
              isEmpty: jobs.isEmpty,
              filtersTooStrict: vm.filtersAreTooRestrictive,
              canExpandToRemote: vm.canExpandToRemote,
              onClearFilters: () => vm.clearPreferences(),
              onExpandRemote: () => vm.expandFiltersWithRemote(),
              onEnableAlert: _enableNewJobsAlert,
              onRequestCompany: () => CompanyRequestSheet.show(context),
            );
          }
          final job = jobs[index];
          final row = vm.feedRowFor(job.id);
          // T2.4 — banda/chips pré-swipe: escondidos na variante 'hidden'
          // do holdout; banda só faz sentido com alguma dimensão de
          // ranking declarada (senão score=0 viraria "Baixa" pra tudo).
          final scoreVisible =
              vm.matchScoreVisible && vm.profilePrefs != null;
          _trackCellShown(job, row, index, scoreVisible);
          return Dismissible(
            key: ValueKey('feed_cell_${job.id}'),
            background: const _SwipeBackground(
              alignment: Alignment.centerLeft,
              color: AppColors.success,
              icon: Icons.favorite_rounded,
              label: 'Salvar',
            ),
            secondaryBackground: const _SwipeBackground(
              alignment: Alignment.centerRight,
              color: AppColors.error,
              icon: Icons.close_rounded,
              label: 'Descartar',
            ),
            confirmDismiss: (direction) async {
              final action = direction == DismissDirection.startToEnd
                  ? 'liked'
                  : 'rejected';
              await _onCellSwipe(job, action, index);
              return true;
            },
            child: JobsListCell(
              job: job,
              // FASE 2 fixes (#1): célula mostra SÓ razões — a banda saiu
              // (vinha do score do RANKING server e divergia do match do
              // detalhe, que é IA/determinístico; espec 3.3). Ordenação do
              // feed segue pelo rank_score; muda só o que se exibe.
              reasonLabels: scoreVisible
                  ? (row?.matchedReasonLabels ?? const [])
                  : const [],
              onTap: () => _openDetails(job),
            ),
          );
        },
      ),
    );
  }
}

/// Célula compacta do feed em lista. PURA (só recebe dados + callback) —
/// é o alvo do widget test do T2.2 (R3).
class JobsListCell extends StatelessWidget {
  const JobsListCell({
    super.key,
    required this.job,
    required this.reasonLabels,
    this.onTap,
  });

  final Job job;
  final List<String> reasonLabels;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          job.companyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FreshnessBadge(postedDaysAgo: job.postedDaysAgo),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${job.salaryRange} · ${job.location}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              if (reasonLabels.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in reasonLabels)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FreshnessBadge extends StatelessWidget {
  const _FreshnessBadge({required this.postedDaysAgo});

  final String postedDaysAgo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        postedDaysAgo,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// T2.3 — fim da lista com exaustão HONESTA. Estado B (filtros zeraram:
/// total_after_filters=0 com total_available>0, via sentinela do RPC) →
/// "limpar filtros". Estado A (catálogo relevante esgotado) → alerta
/// (digest) + expansão honesta + "Pedir uma empresa".
class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.isLoadingMore,
    required this.hasMore,
    required this.isEmpty,
    required this.filtersTooStrict,
    required this.canExpandToRemote,
    required this.onClearFilters,
    required this.onExpandRemote,
    required this.onEnableAlert,
    required this.onRequestCompany,
  });

  final bool isLoadingMore;
  final bool hasMore;
  final bool isEmpty;
  final bool filtersTooStrict;
  final bool canExpandToRemote;
  final VoidCallback onClearFilters;
  final VoidCallback onExpandRemote;
  final VoidCallback onEnableAlert;
  final VoidCallback onRequestCompany;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
          ),
        ),
      );
    }
    if (hasMore && !isEmpty) return const SizedBox(height: 24);

    if (isEmpty && filtersTooStrict) {
      // Estado B — filtros zeraram tudo
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            const Icon(Icons.filter_alt_off_rounded,
                color: AppColors.textTertiary, size: 28),
            const SizedBox(height: 8),
            const Text(
              'Existem vagas ativas, mas seus filtros\nestão muito restritivos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Limpar filtros'),
            ),
          ],
        ),
      );
    }

    // Estado A — fim das relevantes
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          const Icon(Icons.task_alt_rounded,
              color: AppColors.textTertiary, size: 28),
          const SizedBox(height: 8),
          const Text(
            'Você viu as vagas relevantes por agora.\nVagas novas entram toda semana.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onEnableAlert,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.notifications_active_rounded, size: 18),
            label: const Text('Me avisar de vagas novas'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            alignment: WrapAlignment.center,
            children: [
              if (canExpandToRemote)
                OutlinedButton.icon(
                  onPressed: onExpandRemote,
                  icon: const Icon(Icons.public_rounded, size: 18),
                  label: const Text('Incluir remotas'),
                ),
              OutlinedButton.icon(
                onPressed: onRequestCompany,
                icon: const Icon(Icons.add_business_rounded, size: 18),
                label: const Text('Pedir uma empresa'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Buckets de analytics — ESPELHO dos privados de jobs_swipe_screen.dart
/// (mudou lá → muda aqui; candidatos a util compartilhado no fechamento
/// da fase, sem refactor oportunista agora — R6).
String? bucketSalary(int? min, int? max) {
  final v = min ?? max;
  if (v == null || v <= 0) return null;
  if (v < 2000) return 'lt_2k';
  if (v < 4000) return '2k_4k';
  if (v < 6000) return '4k_6k';
  if (v < 10000) return '6k_10k';
  return 'gte_10k';
}

String? bucketLocation(String? city, String? state) {
  final c = city?.toLowerCase().trim() ?? '';
  final s = state?.toLowerCase().trim() ?? '';
  if (c.contains('são paulo') || c == 'sao paulo' || c == 'sp') {
    return 'sp_capital';
  }
  if (c.contains('rio de janeiro') || c == 'rj') return 'rj_capital';
  if (c.contains('belo horizonte') || c == 'bh') return 'bh_capital';
  if (c.contains('porto alegre') || c == 'poa') return 'poa_capital';
  if (s == 'sp') return 'sp_interior';
  if (s == 'rj') return 'rj_interior';
  if (s == 'mg') return 'mg_other';
  if (s == 'rs') return 'rs_other';
  if (s.isNotEmpty) return 'br_other_$s';
  return null;
}
