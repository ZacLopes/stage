// UploadSelectorScreen — escolhe origem do PDF: arquivo do dispositivo ou Drive.
//
// Implementação MVP: só "Arquivo do dispositivo" via file_picker. Google Drive
// é tech debt (depende de integração específica que pode não estar habilitada).

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/analytics_service.dart';
import 'onboarding_scaffold.dart';
import 'upload_confirm_screen.dart';

class UploadSelectorScreen extends StatefulWidget {
  const UploadSelectorScreen({super.key});

  @override
  State<UploadSelectorScreen> createState() => _UploadSelectorScreenState();
}

class _UploadSelectorScreenState extends State<UploadSelectorScreen> {
  bool _picking = false;

  Future<void> _pickFromDevice() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      AnalyticsService.shared.track('onboarding_upload_started');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) {
        setState(() => _picking = false);
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _picking = false);
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UploadConfirmScreen(
            pdfBytes: bytes,
            fileName: file.name,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Selecione seu currículo',
      subtitle: 'Aceita apenas PDF',
      progress: 0.1,
      onContinue: null,
      child: Column(
        children: [
          _option(
            icon: Icons.folder_open_outlined,
            title: 'Arquivo do dispositivo',
            description: 'PDF salvo no celular',
            onTap: _picking ? null : _pickFromDevice,
          ),
          // Google Drive: integração futura
        ],
      ),
    );
  }

  Widget _option({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C27A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF00C27A), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(description, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}
