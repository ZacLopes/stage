import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../models/application.dart';
import 'application_status_control.dart';

/// Card de candidatura MANUAL na aba Candidaturas (FASE 3 T3.3). Sem vaga
/// atrelada — renderiza de external_company/title/url. Chip de status editável.
class ManualApplicationCard extends StatelessWidget {
  final Application application;
  final List<ApplicationStatus> statusOptions;
  final ValueChanged<ApplicationStatus> onStatusSelected;
  final VoidCallback? onOpenLink;

  const ManualApplicationCard({
    super.key,
    required this.application,
    required this.statusOptions,
    required this.onStatusSelected,
    this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final title = application.externalTitle ?? 'Candidatura';
    final company = application.externalCompany ?? '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.edit_note_rounded,
                    size: 22, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
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
                    if (company.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        company,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              // selo "manual"
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('manual',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ApplicationStatusControl(
                status: application.status,
                options: statusOptions,
                onSelected: onStatusSelected,
              ),
              const Spacer(),
              if (onOpenLink != null)
                TextButton.icon(
                  onPressed: onOpenLink,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Abrir vaga',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
