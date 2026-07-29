import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../models/application.dart';
import '../models/job.dart';
import 'application_status_control.dart';
import 'expired_job_badge.dart';

/// Cor do status (FASE 3 redesign): badge por estado.
Color statusColor(ApplicationStatus s) => switch (s) {
      ApplicationStatus.submitted => AppColors.brandBlue,
      ApplicationStatus.inReview ||
      ApplicationStatus.shortlisted =>
        AppColors.brandCyan,
      ApplicationStatus.interview || ApplicationStatus.offer => AppColors.primary,
      ApplicationStatus.hired => AppColors.success,
      ApplicationStatus.rejected ||
      ApplicationStatus.withdrawn ||
      ApplicationStatus.expired =>
        AppColors.textDisabled,
    };

String _fmtDate(DateTime d) {
  const m = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez'
  ];
  return '${d.day} ${m[d.month - 1]}';
}

/// FASE 3 (T3.1 redesign): card unificado da aba Candidaturas para entradas com
/// vaga. Dois modos: **Salvas** (sem application → CTA Aplicar) e **acompanhamento**
/// (com application → badge de status + ver vaga). Ações secundárias num "···".
class TrackerJobCard extends StatelessWidget {
  final Job job;
  final Application? application; // null = Salvas
  final bool isExpired;

  /// Salvas: CTA de aplicar (null se a vaga não tem como aplicar pelo app).
  final String? applyLabel;
  final IconData? applyIcon;
  final VoidCallback? onApply;

  /// Acompanhamento: abrir o link da vaga (null se não houver).
  final VoidCallback? onOpenLink;

  /// Acompanhamento editável: transições válidas.
  final List<ApplicationStatus> statusOptions;
  final ValueChanged<ApplicationStatus>? onStatusChange;

  final VoidCallback onTap;

  /// Remover (unsave). Só em Salvas — em acompanhamento removeria o like sem
  /// apagar a application (vira órfã na UI), então fica null.
  final VoidCallback? onRemove;

  /// Salvas: marcar manualmente como aplicada (aplicou por fora).
  final VoidCallback? onMarkApplied;

  const TrackerJobCard({
    super.key,
    required this.job,
    required this.application,
    required this.isExpired,
    required this.onTap,
    this.onRemove,
    this.applyLabel,
    this.applyIcon,
    this.onApply,
    this.onOpenLink,
    this.statusOptions = const [],
    this.onStatusChange,
    this.onMarkApplied,
  });

  bool get _isSaved => application == null;

  @override
  Widget build(BuildContext context) {
    final app = application;
    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: app != null && !isExpired
                  ? statusColor(app.status).withValues(alpha: 0.35)
                  : AppColors.border,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 3)),
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
                          style: TextStyle(
                            fontFamily: 'Outfit',
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
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  if (onMarkApplied != null || onRemove != null)
                    _OverflowMenu(
                      onDetails: onTap,
                      onMarkApplied:
                          _isSaved ? onMarkApplied : null,
                      onRemove: onRemove,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isSaved)
                _buildSavedActions()
              else
                _buildTrackingFooter(app!),
            ],
          ),
        ),
      ),
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isExpired ? 0.62 : 1,
      child: card,
    );
  }

  Widget _buildSavedActions() {
    if (onApply == null) {
      return Text(
        'Sem link de candidatura — toque para ver detalhes',
        style: TextStyle(
            fontFamily: 'Inter', fontSize: 12, color: AppColors.textTertiary),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onApply,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(applyIcon ?? Icons.open_in_new_rounded, size: 18),
        label: Text(applyLabel ?? 'Aplicar',
            style: const TextStyle(
                fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildTrackingFooter(Application app) {
    return Row(
      children: [
        if (onStatusChange != null)
          ApplicationStatusControl(
            status: app.status,
            options: statusOptions,
            onSelected: onStatusChange!,
          )
        else
          _StatusBadge(status: app.status),
        const SizedBox(width: 8),
        Text(
          _fmtDate(app.createdAt),
          style: TextStyle(
              fontFamily: 'Inter', fontSize: 12, color: AppColors.textTertiary),
        ),
        const Spacer(),
        if (onOpenLink != null)
          TextButton(
            onPressed: onOpenLink,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('ver vaga',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ApplicationStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c),
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  final VoidCallback onDetails;
  final VoidCallback? onMarkApplied;
  final VoidCallback? onRemove;

  const _OverflowMenu({
    required this.onDetails,
    required this.onMarkApplied,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz_rounded, color: AppColors.textTertiary),
      tooltip: 'Mais',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) {
        switch (v) {
          case 'details':
            onDetails();
          case 'mark':
            onMarkApplied?.call();
          case 'remove':
            onRemove?.call();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'details', child: Text('Ver detalhes')),
        if (onMarkApplied != null)
          const PopupMenuItem(
              value: 'mark', child: Text('Marcar como enviada')),
        if (onRemove != null)
          PopupMenuItem(
            value: 'remove',
            child: Text('Remover', style: TextStyle(color: AppColors.error)),
          ),
      ],
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
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? _fallback()
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, _) => _fallback(),
              errorWidget: (_, _, _) => _fallback(),
            ),
    );
  }

  Widget _fallback() => Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary),
        ),
      );
}
