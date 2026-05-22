// UploadConfirmScreen — preview do PDF antes de enviar pra extração.
//
// Mostra nome do arquivo + ícone de check + opção de trocar. Quando user
// toca Continue, dispara ExtractionStatusViewModel.start(pdfBytes) e navega
// pra ExtractionInProgressScreen.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../services/analytics_service.dart';
import '../../profile/application/extraction_status_view_model.dart';
import 'onboarding_scaffold.dart';
import 'extraction_in_progress_screen.dart';

class UploadConfirmScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String fileName;

  const UploadConfirmScreen({
    super.key,
    required this.pdfBytes,
    required this.fileName,
  });

  void _continue(BuildContext context) {
    AnalyticsService.shared.track('onboarding_upload_confirmed', props: {
      'file_size_kb': (pdfBytes.length / 1024).round(),
    });
    // Dispara extract-profile em background
    context.read<ExtractionStatusViewModel>().start(pdfBytes);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ExtractionInProgressScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sizeKb = (pdfBytes.length / 1024).round();
    return OnboardingScaffold(
      title: 'Confirme seu currículo',
      subtitle: 'Confira se é esse mesmo o CV que você quer importar',
      progress: 0.15,
      continueLabel: 'Continuar',
      onContinue: () => _continue(context),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf, color: Color(0xFFEF4444)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text('$sizeKb KB', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            icon: const Icon(Icons.refresh, color: Color(0xFF6B7280), size: 18),
            label: const Text(
              'Trocar arquivo',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
