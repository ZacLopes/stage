import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/analytics/screen_tracking.dart';
import '../../../core/utils/display_name.dart';
import '../../../services/analytics_events.dart';
import '../../../services/analytics_service.dart';
import '../../../services/facebook_events_service.dart';
import '../../../services/feature_flags_service.dart';
import '../models/application.dart';
import '../../auth/user_viewmodel.dart';
import '../../profile/application/profile_editor_view_model.dart';
import '../data/swipe_repository.dart';
import '../job_swipe_context.dart';
import '../utils/url_utils.dart';
import '../widgets/application_status_control.dart';
import '../widgets/expired_job_badge.dart';
import '../jobs_viewmodel.dart';
import 'job_details_sheet.dart';
import '../../../core/theme/theme.dart';

class LikedJobsScreen extends StatefulWidget {
  const LikedJobsScreen({super.key});

  @override
  State<LikedJobsScreen> createState() => _LikedJobsScreenState();
}

class _LikedJobsScreenState extends State<LikedJobsScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'jobs_liked';

  /// Mostra banner explicativo de "como aplicar" na primeira visita pós-
  /// celebração de "primeira vaga salva". Persiste o estado em
  /// SharedPreferences (`first_save_banner_dismissed_<userId>`).
  bool _showFirstSaveBanner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JobsViewModel>().loadLikedJobs();
    });
    _maybeLoadFirstSaveBanner();
  }

  Future<void> _maybeLoadFirstSaveBanner() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final celebratedKey = 'first_save_celebrated_$userId';
    final dismissedKey = 'first_save_banner_dismissed_$userId';
    final celebrated = prefs.getBool(celebratedKey) == true;
    final dismissed = prefs.getBool(dismissedKey) == true;
    if (celebrated && !dismissed && mounted) {
      setState(() => _showFirstSaveBanner = true);
    }
  }

  Future<void> _dismissFirstSaveBanner() async {
    HapticFeedback.lightImpact();
    setState(() => _showFirstSaveBanner = false);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_save_banner_dismissed_$userId', true);
    Analytics.shared.track(evFirstSaveBannerDismissed);
  }

  Future<void> _refresh() async {
    await context.read<JobsViewModel>().loadLikedJobs(silent: true);
  }

  Future<void> _openJobDetails(LikedJob liked) async {
    HapticFeedback.lightImpact();
    // Fix QA Dia 8 (Bug 3): a tabela `jobs` no Supabase não persiste
    // `match_score` (é per user×job), então `liked.job.matchScore` chega 0/null
    // na Curtidas. Lê do JobSwipeContext, que persistiu o score real no
    // momento do swipe. Fallback pro Job.matchScore se nada salvo (improvável,
    // só se a vaga foi curtida em build antiga).
    final cachedScore = await JobSwipeContext.shared.getMatchScore(liked.job.id);
    final matchScore = cachedScore ?? liked.job.matchScore;
    Analytics.shared.jobDetailsOpened(
      jobId: liked.job.id,
      matchScore: matchScore,
    );
    // Facebook ViewContent — intent forte. Sem dedupe (cada view é sinal).
    // ignore: unawaited_futures
    FacebookEventsService.shared.logViewContent(
      jobId: liked.job.id,
      jobTitle: liked.job.title,
      company: liked.job.company?.name,
    );
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JobDetailsSheet(job: liked.job),
    );
  }

  Future<void> _openApplication(_ApplyAction action, LikedJob liked) async {
    HapticFeedback.lightImpact();
    // Activation milestone — idempotente.
    // ignore: unawaited_futures
    Analytics.shared.activationMilestoneHit(milestone: 'first_apply');
    // Fix QA Dia 8 (Bugs 1 + 3): lê o `matchScore` real do JobSwipeContext
    // (persistido no swipe) E checa se o user já adaptou CV pra essa vaga
    // (marcado no adapt_pdf_downloaded). Sem isso o `used_adapted_cv` vinha
    // null no apply, quebrando a tese B2B do pitch ("CV adaptado fecha o
    // loop"). Resolução: ambos derivados do contexto persistente.
    final cachedScore = await JobSwipeContext.shared.getMatchScore(liked.job.id);
    final matchScore = cachedScore ?? liked.job.matchScore;
    final usedAdaptedCv = await JobSwipeContext.shared.wasAdapted(liked.job.id);
    Analytics.shared.jobApplyClicked(
      jobId: liked.job.id,
      matchScore: matchScore,
      usedAdaptedCv: usedAdaptedCv,
      // 'email' quando a candidatura é por mailto (Polifinance) — alimenta o
      // funil swipe-right(email) → apply(email).
      applicationMethod: liked.job.applicationMethod,
    );
    // T2.3 — fecha o loop adapt→apply: quando o apply usa CV adaptado, emite
    // adapt_apply_used com o tempo entre baixar o PDF e aplicar. adapt_apply_used
    // não tinha emissor no app (bottom do funil B.15 / insight 9dK2XFpq).
    if (usedAdaptedCv) {
      final adaptedAt = await JobSwipeContext.shared.adaptedAtMs(liked.job.id);
      // ignore: unawaited_futures
      Analytics.shared.adaptApplyUsed(
        jobId: liked.job.id,
        timeFromDownloadToApplyMs: adaptedAt != null
            ? DateTime.now().millisecondsSinceEpoch - adaptedAt
            : 0,
      );
    }
    // T3.4 — UTM na saída: decora SÓ http(s) (mailto passa intacto); preserva
    // query/UTM da fonte.
    final launchUri = decorateOutboundUrl(action.uri);
    final ok = await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action.failureMessage)),
      );
      return;
    }
    // T3.4 — outbound rastreável (http/https): grava o clique no banco
    // (outbound_clicks, own-insert) e emite o evento de saída. mailto fica de
    // fora (sem link externo a rastrear). Fire-and-forget: não bloqueia o apply.
    if (isTrackableOutbound(launchUri)) {
      // ignore: unawaited_futures
      _recordOutboundClick(liked.job.id);
      // ignore: unawaited_futures
      Analytics.shared.jobApplyExternalOpened(
        jobId: liked.job.id,
        jobSource: liked.job.source,
      );
    }
    // Facebook SubmittedApplication — dispara APENAS quando o launchUrl
    // retornou true (cliente externo abriu de fato, intent confirmada). Vale
    // tanto pra site quanto pra cliente de email — em ambos houve ação real.
    // ignore: unawaited_futures
    FacebookEventsService.shared.logSubmittedApplication(jobId: liked.job.id);
  }

  /// T3.4 — own-insert em `outbound_clicks` (RLS exige user_id = auth.uid).
  /// Best-effort: falha de rede não pode atrapalhar a candidatura.
  Future<void> _recordOutboundClick(String jobId) async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      await client.from('outbound_clicks').insert({
        'user_id': uid,
        'job_id': jobId,
      });
    } catch (_) {
      // silencioso — outbound_clicks é telemetria, não bloqueia o fluxo.
    }
  }

  void _toggleApplied(LikedJob liked) {
    HapticFeedback.mediumImpact();
    context.read<JobsViewModel>().setApplied(liked.job.id, !liked.applied);
  }

  Future<void> _confirmAndRemove(LikedJob liked) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          liked.job.isActive ? 'Remover das salvas?' : 'Arquivar vaga expirada?',
          style: TextStyle(fontFamily: 'Outfit',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          // Vaga inativa NÃO volta ao feed (o fetch só traz is_active=true) —
          // copy diferente pra não prometer o que não acontece (Fase 1 T1.4).
          liked.job.isActive
              ? '"${liked.job.title}" sai daqui e volta a aparecer no feed de vagas.'
              : '"${liked.job.title}" não está mais ativa — sai das salvas e não volta ao feed.',
          style: TextStyle(fontFamily: 'Inter', 
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: TextStyle(fontFamily: 'Inter', 
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remover',
              style: TextStyle(fontFamily: 'Inter', 
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final vm = context.read<JobsViewModel>();
    final ok = await vm.removeLikedJob(liked.job.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não consegui remover. Tente de novo.')),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Vaga removida das salvas'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Desfazer',
            textColor: AppColors.brandCyan,
            onPressed: () => vm.restoreLikedJob(liked),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Consumer<JobsViewModel>(
          builder: (context, vm, _) {
            return Column(
              children: [
                _Header(
                  liked: vm.likedCount,
                  applied: vm.appliedCount,
                ),
                if (_showFirstSaveBanner && vm.likedJobs.isNotEmpty)
                  _FirstSaveBanner(onDismiss: _dismissFirstSaveBanner),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.brandBlue,
                    onRefresh: _refresh,
                    child: _buildBody(vm),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(JobsViewModel vm) {
    if (vm.likedJobsLoading && vm.likedJobs.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandBlue),
      );
    }
    if (vm.likedJobs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          _EmptyState(),
        ],
      );
    }

    // FASE 3 (T3.1): com applications_tracker_v1 ON, agrupa em 4 segmentos
    // (Salvas/Enviadas/Em processo/Finalizadas) sobre applications; OFF = os 3
    // buckets legacy (pending/applied/expired) intocados.
    final trackerOn = FeatureFlagsService.instance
        .isEnabledForUser(FeatureFlagKeys.applicationsTrackerV1, vm.userId);
    final items =
        trackerOn ? _buildTrackerItems(vm) : _buildLegacyItems(vm);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, index) {
        // Espaçamento maior antes de section header (separação visual de bucket)
        final next = index + 1 < items.length ? items[index + 1] : null;
        if (next is _SectionHeaderItem) return const SizedBox(height: 20);
        return const SizedBox(height: 10);
      },
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is _SectionHeaderItem) {
          return _SectionHeader(
            title: item.title,
            count: item.count,
            color: item.color,
            icon: item.icon,
          );
        }
        if (item is _JobCardItem) {
          final liked = item.liked;
          final action = _resolveApplyAction(liked);
          final app = item.application;
          // T3.1: chip/menu de status só pra application editável pelo user
          // (manual/external_confirmed; stage é read-only).
          final statusControl = (app != null && app.type.userEditableStatus)
              ? ApplicationStatusControl(
                  status: app.status,
                  options: ApplicationStatus.values
                      .where((s) =>
                          s != app.status &&
                          canTransition(app.type, app.status, s))
                      .toList(),
                  onSelected: (s) => _changeStatus(liked, s),
                )
              : null;
          return _LikedJobCard(
            liked: liked,
            isExpired: item.isExpired,
            onTap: () => _openJobDetails(liked),
            onToggleApplied: () => _toggleApplied(liked),
            onOpenLink: action != null
                ? () => _openApplication(action, liked)
                : null,
            applyAction: action,
            onRemove: () => _confirmAndRemove(liked),
            statusControl: statusControl,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// Legacy (flag OFF): 3 buckets pending/applied/expired (E5 / Fase 1 T1.4).
  List<_ListItem> _buildLegacyItems(JobsViewModel vm) {
    final now = DateTime.now();
    final pending = <LikedJob>[];
    final applied = <LikedJob>[];
    final expired = <LikedJob>[];
    for (final liked in vm.likedJobs) {
      final deadlineAt = liked.job.deadlineAt;
      final isExpired = !liked.job.isActive ||
          (deadlineAt != null && deadlineAt.isBefore(now));
      if (isExpired) {
        expired.add(liked);
      } else if (liked.applied) {
        applied.add(liked);
      } else {
        pending.add(liked);
      }
    }
    final items = <_ListItem>[];
    void section(String title, List<LikedJob> list, Color color, IconData icon,
        {bool exp = false}) {
      if (list.isEmpty) return;
      items.add(_SectionHeaderItem(
          title: title, count: list.length, color: color, icon: icon));
      for (final l in list) {
        items.add(_JobCardItem(l, isExpired: exp));
      }
    }

    section('Ainda não apliquei', pending, AppColors.brandBlue,
        Icons.pending_outlined);
    section('Já apliquei', applied, AppColors.primary,
        Icons.check_circle_outline_rounded);
    section('Expiradas', expired, AppColors.textDisabled,
        Icons.event_busy_outlined, exp: true);
    return items;
  }

  /// FASE 3 (T3.1): 4 segmentos sobre `applications`. Salvas = liked SEM
  /// application; os outros 3 via [segmentForStatus]. Badge "Expirada" segue
  /// preservado dentro do segmento (vaga morta ≠ status da candidatura).
  List<_ListItem> _buildTrackerItems(JobsViewModel vm) {
    final now = DateTime.now();
    final salvas = <_JobCardItem>[];
    final enviadas = <_JobCardItem>[];
    final emProcesso = <_JobCardItem>[];
    final finalizadas = <_JobCardItem>[];
    for (final liked in vm.likedJobs) {
      final app = vm.applicationForJob(liked.job.id);
      final deadlineAt = liked.job.deadlineAt;
      final isExpired = !liked.job.isActive ||
          (deadlineAt != null && deadlineAt.isBefore(now));
      final item =
          _JobCardItem(liked, isExpired: isExpired, application: app);
      if (app == null) {
        salvas.add(item);
      } else {
        switch (segmentForStatus(app.status)) {
          case ApplicationSegment.salvas:
          case ApplicationSegment.enviadas:
            enviadas.add(item);
          case ApplicationSegment.emProcesso:
            emProcesso.add(item);
          case ApplicationSegment.finalizadas:
            finalizadas.add(item);
        }
      }
    }
    final items = <_ListItem>[];
    void section(ApplicationSegment seg, List<_JobCardItem> list, Color color,
        IconData icon) {
      if (list.isEmpty) return;
      items.add(_SectionHeaderItem(
          title: seg.label, count: list.length, color: color, icon: icon));
      items.addAll(list);
    }

    section(ApplicationSegment.salvas, salvas, AppColors.brandBlue,
        Icons.bookmark_outline_rounded);
    section(ApplicationSegment.enviadas, enviadas, AppColors.primary,
        Icons.send_outlined);
    section(ApplicationSegment.emProcesso, emProcesso, AppColors.brandCyan,
        Icons.timelapse_outlined);
    section(ApplicationSegment.finalizadas, finalizadas,
        AppColors.textDisabled, Icons.flag_outlined);
    return items;
  }

  /// T3.1: aplica a transição de status escolhida no chip/menu da aba.
  Future<void> _changeStatus(LikedJob liked, ApplicationStatus newStatus) async {
    HapticFeedback.selectionClick();
    final ok = await context
        .read<JobsViewModel>()
        .updateApplicationStatus(jobId: liked.job.id, newStatus: newStatus);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não consegui atualizar o status.')),
      );
    }
  }

  /// Resolve como o user vai aplicar pra essa vaga:
  ///   • application_method='email' → abre mailto com assunto pré-preenchido
  ///   • application_method='url' (default) → URL específica do ATS, ou
  ///     fallback no site da empresa
  /// Retorna null se não há ação possível (botão "Aplicar" some do card).
  _ApplyAction? _resolveApplyAction(LikedJob liked) {
    final job = liked.job;
    if (job.applicationMethod == 'email') {
      final email = job.applicationEmail;
      if (email == null || email.isEmpty) return null;
      // Polifinance e similares usam placeholders tipo "[SEU NOME]" no
      // assunto sugerido. Substituímos pelo nome real do user (mesma fonte
      // canônica das outras telas — profile_personal com fallback no legacy).
      final user = context.read<UserViewModel>().user;
      final editorVM = context.read<ProfileEditorViewModel>();
      final userName = resolveDisplayName(editorVM, user?.name);
      return _ApplyAction.email(
        email: email,
        subject: job.applicationSubject,
        userName: userName,
      );
    }
    final ext = job.externalUrl;
    if (ext != null && ext.isNotEmpty) return _ApplyAction.url(ext);
    final web = job.company?.website;
    if (web != null && web.isNotEmpty) return _ApplyAction.url(web);
    return null;
  }
}

/// Como o usuário aplica numa vaga. Encapsula URL (Greenhouse/Lever/etc) e
/// candidatura por email (Polifinance) num único tipo pra simplificar a UI.
class _ApplyAction {
  final Uri uri;
  final String label;
  final IconData icon;
  final String failureMessage;

  const _ApplyAction._({
    required this.uri,
    required this.label,
    required this.icon,
    required this.failureMessage,
  });

  factory _ApplyAction.url(String url) {
    return _ApplyAction._(
      uri: Uri.parse(url),
      label: 'Aplicar no site',
      icon: Icons.open_in_new_rounded,
      failureMessage: 'Não consegui abrir o link da vaga.',
    );
  }

  factory _ApplyAction.email({
    required String email,
    String? subject,
    String? userName,
  }) {
    // RFC 6068 (mailto): parâmetros devem usar percent-encoding (%20 pra
    // espaço). Uri(queryParameters: ...) aplica form-urlencoded (+ pra
    // espaço), que clientes de email iOS/Android interpretam literalmente
    // como "+" — saída fica "Vaga+Investimentos+...". Montamos a string
    // manualmente com Uri.encodeComponent pra garantir %20.
    var subj = subject?.trim() ?? '';
    // Substitui placeholders típicos dos templates Polifinance/etc se o
    // user tem nome configurado. Casos cobertos: "[SEU NOME]", "(SEU NOME)",
    // "[Seu Nome]" — todas variações case-insensitive de colchete ou
    // parênteses ao redor de "seu nome".
    final name = userName?.trim() ?? '';
    if (name.isNotEmpty && name.toLowerCase() != 'usuário') {
      subj = subj.replaceAll(
        RegExp(r'[\[\(]\s*seu\s+nome\s*[\]\)]', caseSensitive: false),
        name,
      );
    }
    final query = subj.isEmpty ? '' : '?subject=${Uri.encodeComponent(subj)}';
    return _ApplyAction._(
      uri: Uri.parse('mailto:$email$query'),
      label: 'Enviar CV por email',
      icon: Icons.mail_outline_rounded,
      failureMessage: 'Não consegui abrir o app de email.',
    );
  }
}

class _Header extends StatelessWidget {
  final int liked;
  final int applied;
  const _Header({required this.liked, required this.applied});

  @override
  Widget build(BuildContext context) {
    // Header transparente — fica sobre o background do Scaffold sem faixa
    // branca chapada (mesma padronização da aba Vagas).
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vagas Salvas',
                  style: TextStyle(fontFamily: 'Outfit', 
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  liked == 0
                      ? 'Acompanhe aqui suas candidaturas'
                      : '$applied aplicada${applied == 1 ? '' : 's'} de $liked salva${liked == 1 ? '' : 's'}',
                  style: TextStyle(fontFamily: 'Inter', 
                    fontSize: 13,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (liked > 0)
            _StatChip(
              label: 'Pendentes',
              value: '${liked - applied}',
              color: AppColors.brandBlue,
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontFamily: 'Outfit', 
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontFamily: 'Inter', 
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.brandCyan.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bookmark_outline,
              size: 44,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma vaga salva ainda',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Outfit', 
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vá para a aba Vagas e arraste pra direita as que te interessam — elas ficam salvas aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Inter', 
              fontSize: 14,
              color: AppColors.textTertiary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LikedJobCard extends StatelessWidget {
  final LikedJob liked;
  final VoidCallback onTap;
  final VoidCallback onToggleApplied;
  final VoidCallback? onOpenLink;
  final VoidCallback onRemove;
  /// Ação de candidatura (URL externa ou mailto). null = vaga sem aplicação
  /// possível pelo app → botão "Aplicar" some.
  final _ApplyAction? applyAction;
  /// True quando a vaga já passou do prazo. Card renderiza com style sutil
  /// (opacity reduzida, borda neutra, badge "Prazo expirado") indicando que
  /// é histórico, não ação possível.
  final bool isExpired;

  /// FASE 3 (T3.1): chip/menu de status da candidatura (aba Candidaturas). null
  /// no modo legacy e em vagas só salvas / type stage.
  final Widget? statusControl;

  const _LikedJobCard({
    required this.liked,
    required this.onTap,
    required this.onToggleApplied,
    required this.onOpenLink,
    required this.applyAction,
    required this.onRemove,
    this.isExpired = false,
    this.statusControl,
  });

  @override
  Widget build(BuildContext context) {
    final job = liked.job;
    final applied = liked.applied;
    final hasApply = applyAction != null;

    // Expired = card desbotado, sem hover effects fortes. Continua clicável
    // (user pode ver detalhes do que perdeu / marcar como aplicada manualmente
    // caso tenha aplicado mesmo no prazo).
    final Color borderColor;
    if (isExpired) {
      borderColor = AppColors.border;
    } else if (applied) {
      borderColor = AppColors.primary.withValues(alpha: 0.4);
    } else {
      borderColor = AppColors.border;
    }

    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: applied && !isExpired ? 1.5 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x05000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isExpired) ...[
                const ExpiredJobBadge(),
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Logo(url: job.companyLogoUrl, name: job.companyName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          job.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Outfit', 
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          job.companyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Inter', 
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Flexible(
                              child: _MetaChip(
                                icon: Icons.location_on_outlined,
                                label: job.location,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (job.salaryRange.isNotEmpty &&
                                job.salaryRange != 'A combinar')
                              Flexible(
                                child: _MetaChip(
                                  icon: Icons.attach_money,
                                  label: job.salaryRange,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _CardMenu(onRemove: onRemove),
                ],
              ),
              if (statusControl != null) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: statusControl!),
              ],
              const SizedBox(height: 12),
              // Botões empilhados — labels longos ("Enviar CV por email",
              // "Marcar como aplicada") não cabiam em Row 50/50, ellipsis
              // cortava em "Enviar CV por e..." e "Marcar como apl...".
              // Full-width preserva o texto completo, dá área de toque maior
              // e mantém hierarquia clara (CTA primário em cima).
              Column(
                children: [
                  if (hasApply) ...[
                    SizedBox(
                      width: double.infinity,
                      child: _ActionBtn(
                        icon: applyAction!.icon,
                        label: applyAction!.label,
                        onTap: onOpenLink,
                        primary: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: _ActionBtn(
                      icon: applied
                          ? Icons.check_circle_rounded
                          : Icons.check_circle_outline_rounded,
                      label: applied ? 'Já apliquei' : 'Marcar como aplicada',
                      onTap: onToggleApplied,
                      primary: false,
                      active: applied,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // Card expirado fica visualmente desbotado (opacity 0.6) — comunica
    // "histórico" sem esconder informação. User ainda pode tap pra ver detalhe
    // ou marcar como aplicada caso tenha conseguido no prazo.
    if (isExpired) {
      return Opacity(opacity: 0.55, child: card);
    }
    return card;
  }
}

class _Logo extends StatelessWidget {
  final String url;
  final String name;
  const _Logo({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? _LogoFallback(name: name)
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => _LogoFallback(name: name),
              errorWidget: (_, __, ___) => _LogoFallback(name: name),
            ),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  final String name;
  const _LogoFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: TextStyle(fontFamily: 'Outfit', 
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.brandBlue,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textTertiary),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Inter', 
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Botão pill com ícone+texto. Dois estilos:
/// - primary=true: fundo cheio na cor da marca (CTA "Aplicar no site")
/// - primary=false + active=false: outlined cinza (CTA "Marcar como aplicada")
/// - primary=false + active=true: outlined verde com ícone preenchido
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool active;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.primary,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    if (primary) {
      bg = AppColors.brandBlue;
      fg = Colors.white;
      border = AppColors.brandBlue;
    } else if (active) {
      bg = AppColors.primary.withValues(alpha: 0.12);
      fg = AppColors.primary;
      border = AppColors.primary.withValues(alpha: 0.4);
    } else {
      bg = Colors.white;
      fg = AppColors.textSecondary;
      border = AppColors.borderStrong;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Menu compacto (3-dots) no canto do card. Hoje só tem a ação de remover
/// a vaga das salvas — fica num popup pra não competir visualmente com os
/// CTAs principais (Aplicar / Marcar como aplicada).
class _CardMenu extends StatelessWidget {
  final VoidCallback onRemove;
  const _CardMenu({required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<String>(
        tooltip: 'Mais opções',
        padding: EdgeInsets.zero,
        icon: const Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: AppColors.textTertiary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (value) {
          if (value == 'remove') onRemove();
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'remove',
            child: Row(
              children: [
                const Icon(
                  Icons.bookmark_remove_outlined,
                  size: 18,
                  color: AppColors.error,
                ),
                const SizedBox(width: 10),
                Text(
                  'Remover de salvas',
                  style: TextStyle(fontFamily: 'Inter', 
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Section: agrupamento da lista em 3 buckets — pending / applied / expired
// ─────────────────────────────────────────────────────────────────────────

/// Item base da lista achatada. Sealed-style com `is _SectionHeaderItem` /
/// `is _JobCardItem` no builder. Mantém `ListView.separated` simples sem
/// recorrer a `CustomScrollView`.
sealed class _ListItem {
  const _ListItem();
}

class _SectionHeaderItem extends _ListItem {
  final String title;
  final int count;
  final Color color;
  final IconData icon;
  const _SectionHeaderItem({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });
}

class _JobCardItem extends _ListItem {
  final LikedJob liked;
  final bool isExpired;

  /// Fase 3 (T3.1): a application atrelada (tracker) — alimenta o chip/menu de
  /// status. null no modo legacy (flag OFF) e nas Salvas (liked sem application).
  final Application? application;
  const _JobCardItem(this.liked, {this.isExpired = false, this.application});
}

/// Header de seção (sticky-like — não é sticky de verdade, mas visualmente
/// claro). Ícone + título + badge de contagem.
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(fontFamily: 'Outfit', 
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontFamily: 'Inter', 
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner explicativo exibido na primeira visita à aba Salvas após a
/// celebração de "primeira vaga salva". Mostra como aplicar passo a passo,
/// com botão X pra dismiss permanente.
class _FirstSaveBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _FirstSaveBanner({required this.onDismiss});

  static const _indigo = AppColors.primary;
  static const _purple = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Transform.translate(
          offset: Offset(0, (1 - t) * -20),
          child: Opacity(opacity: t, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_indigo, _purple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _indigo.withOpacity(0.32),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.lightbulb_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Como aplicar?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toque numa vaga abaixo pra ver os detalhes. Use "Aplicar no site" pra ir direto pro recrutador, ou "Enviar CV por email" quando a vaga aceitar candidatura por email — vai abrir seu app de email com o destinatário já preenchido. Depois, marque como "Já apliquei" pra organizar.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onDismiss,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withOpacity(0.8),
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

