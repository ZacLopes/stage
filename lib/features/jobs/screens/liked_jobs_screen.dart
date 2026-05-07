import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/stage_colors.dart';
import '../data/swipe_repository.dart';
import '../jobs_viewmodel.dart';
import 'job_details_sheet.dart';

class LikedJobsScreen extends StatefulWidget {
  const LikedJobsScreen({super.key});

  @override
  State<LikedJobsScreen> createState() => _LikedJobsScreenState();
}

class _LikedJobsScreenState extends State<LikedJobsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JobsViewModel>().loadLikedJobs();
    });
  }

  Future<void> _refresh() async {
    await context.read<JobsViewModel>().loadLikedJobs(silent: true);
  }

  void _openJobDetails(LikedJob liked) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JobDetailsSheet(job: liked.job),
    );
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    HapticFeedback.lightImpact();
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não consegui abrir o link da vaga.')),
      );
    }
  }

  void _toggleApplied(LikedJob liked) {
    HapticFeedback.mediumImpact();
    context.read<JobsViewModel>().setApplied(liked.job.id, !liked.applied);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StageColors.scaffoldGray,
      body: SafeArea(
        child: Consumer<JobsViewModel>(
          builder: (context, vm, _) {
            return Column(
              children: [
                _Header(
                  liked: vm.likedCount,
                  applied: vm.appliedCount,
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: StageColors.brandBlue,
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
        child: CircularProgressIndicator(color: StageColors.brandBlue),
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: vm.likedJobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final liked = vm.likedJobs[index];
        final url = _resolveExternalUrl(liked);
        return _LikedJobCard(
          liked: liked,
          onTap: () => _openJobDetails(liked),
          onToggleApplied: () => _toggleApplied(liked),
          onOpenLink: url != null ? () => _openExternalUrl(url) : null,
          externalUrl: url,
        );
      },
    );
  }

  /// Preferência: URL específica da vaga (external_url do ATS) → fallback no
  /// site da empresa. Se ambos vazios, botão de link some.
  String? _resolveExternalUrl(LikedJob liked) {
    final ext = liked.job.externalUrl;
    if (ext != null && ext.isNotEmpty) return ext;
    final web = liked.job.company?.website;
    if (web != null && web.isNotEmpty) return web;
    return null;
  }
}

class _Header extends StatelessWidget {
  final int liked;
  final int applied;
  const _Header({required this.liked, required this.applied});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vagas Salvas',
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: StageColors.titleText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  liked == 0
                      ? 'Acompanhe aqui suas candidaturas'
                      : '$applied aplicada${applied == 1 ? '' : 's'} de $liked salva${liked == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: StageColors.subtitleGray,
                  ),
                ),
              ],
            ),
          ),
          if (liked > 0)
            _StatChip(
              label: 'Pendentes',
              value: '${liked - applied}',
              color: StageColors.brandBlue,
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
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
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
              color: StageColors.brandCyan.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bookmark_outline,
              size: 44,
              color: StageColors.brandBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma vaga salva ainda',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: StageColors.titleText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vá para a aba Vagas e arraste pra direita as que te interessam — elas ficam salvas aqui.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: StageColors.subtitleGray,
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
  final String? externalUrl;

  const _LikedJobCard({
    required this.liked,
    required this.onTap,
    required this.onToggleApplied,
    required this.onOpenLink,
    required this.externalUrl,
  });

  @override
  Widget build(BuildContext context) {
    final job = liked.job;
    final applied = liked.applied;
    final hasUrl = externalUrl != null && externalUrl!.isNotEmpty;

    return Material(
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
              color: applied
                  ? StageColors.ctaGreen.withValues(alpha: 0.4)
                  : const Color(0xFFE5E7EB),
              width: applied ? 1.5 : 1,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: StageColors.titleText,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          job.companyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: StageColors.subtitleGray,
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
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (hasUrl)
                    Expanded(
                      child: _ActionBtn(
                        icon: Icons.open_in_new_rounded,
                        label: 'Aplicar no site',
                        onTap: onOpenLink,
                        primary: true,
                      ),
                    ),
                  if (hasUrl) const SizedBox(width: 8),
                  Expanded(
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
        color: const Color(0xFFF3F4F6),
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
        style: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: StageColors.brandBlue,
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
        Icon(icon, size: 12, color: StageColors.subtitleGray),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: StageColors.subtitleGray,
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
      bg = StageColors.brandBlue;
      fg = Colors.white;
      border = StageColors.brandBlue;
    } else if (active) {
      bg = StageColors.ctaGreen.withValues(alpha: 0.12);
      fg = StageColors.ctaGreen;
      border = StageColors.ctaGreen.withValues(alpha: 0.4);
    } else {
      bg = Colors.white;
      fg = StageColors.bodyGray;
      border = const Color(0xFFD1D5DB);
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
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
