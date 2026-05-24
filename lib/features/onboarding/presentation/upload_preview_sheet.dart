// UploadPreviewSheet — bottom sheet exibido após o usuário escolher um PDF
// no file picker do iOS. Mostra preview da primeira página renderizado via
// Printing.raster + nome do arquivo + tamanho. Botão "Confirmar" dispara
// extração e navega pra ExtractionInProgressScreen.
//
// Substitui o fluxo antigo UploadSelectorScreen → UploadConfirmScreen (duas
// telas full-screen) por: tap em "Importar currículo" → picker iOS direto →
// este sheet sliding from bottom.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../../data/models/models.dart' show SavedResumeSource;
import '../../../services/analytics_service.dart';
import '../../profile/application/extraction_status_view_model.dart';
import '../../profile/profile_viewmodel.dart';
import 'extraction_in_progress_screen.dart';

class UploadPreviewSheet extends StatefulWidget {
  final Uint8List pdfBytes;
  final String fileName;
  final VoidCallback onReplace;

  const UploadPreviewSheet({
    super.key,
    required this.pdfBytes,
    required this.fileName,
    required this.onReplace,
  });

  @override
  State<UploadPreviewSheet> createState() => _UploadPreviewSheetState();
}

class _UploadPreviewSheetState extends State<UploadPreviewSheet> {
  Uint8List? _previewPng;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _renderPreview();
  }

  Future<void> _renderPreview() async {
    try {
      await for (final page in Printing.raster(widget.pdfBytes, pages: const [0], dpi: 96)) {
        final png = await page.toPng();
        if (!mounted) return;
        setState(() => _previewPng = png);
        break;
      }
    } catch (e) {
      debugPrint('[UploadPreviewSheet] raster failed: $e');
      // Sem preview — UI mostra placeholder de PDF
    }
  }

  void _confirm() {
    if (_confirming) return;
    setState(() => _confirming = true);
    HapticFeedback.lightImpact();
    AnalyticsService.shared.track('onboarding_upload_confirmed', props: {
      'file_size_kb': (widget.pdfBytes.length / 1024).round(),
    });

    // Captura ViewModels ANTES da navegação (context fica inválido após pop).
    final extractionVM = context.read<ExtractionStatusViewModel>();
    final profileVM = context.read<ProfileViewModel>();

    // Dispara extract-profile em background
    extractionVM.start(widget.pdfBytes);

    // Salva o PDF na biblioteca em paralelo (Supabase Storage + tabela
    // saved_resumes). Sem isso, user importa CV no onboarding mas a aba
    // Perfil mostra biblioteca vazia + a feature de CV adaptado por vaga
    // não consegue baixar o PDF original pra adaptar.
    //
    // Fire-and-forget: falha de upload não bloqueia o fluxo de extração
    // (user continua pras 7 perguntas). Erro só vai pro debugPrint.
    _saveResumeInBackground(profileVM);

    Navigator.pop(context); // fecha o sheet
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ExtractionInProgressScreen()),
    );
  }

  Future<void> _saveResumeInBackground(ProfileViewModel profileVM) async {
    try {
      final title = await profileVM.resolveUniqueTitle('Meu Currículo');
      await profileVM.saveResume(
        title,
        widget.pdfBytes,
        source: SavedResumeSource.imported,
      );
      debugPrint('[UploadPreviewSheet] PDF salvo em saved_resumes: $title');
    } catch (e) {
      debugPrint('[UploadPreviewSheet] saveResume falhou (não bloqueia): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeKb = (widget.pdfBytes.length / 1024).round();
    final sizeLabel = sizeKb >= 1024 ? '${(sizeKb / 1024).toStringAsFixed(1)} MB' : '$sizeKb KB';

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF9FAFB),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Confirme',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: _confirming ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _FileInfoCard(
                      fileName: widget.fileName,
                      sizeLabel: sizeLabel,
                      onDelete: _confirming
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(context);
                              widget.onReplace();
                            },
                    ),
                    const SizedBox(height: 12),
                    _PreviewCard(
                      previewPng: _previewPng,
                      onExpand: _previewPng == null
                          ? null
                          : () => _openFullPreview(context, _previewPng!),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirming ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF29B6D2),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD1D5DB),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    _confirming ? 'Carregando…' : 'Continuar',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullPreview(BuildContext context, Uint8List png) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => _FullPreviewPage(png: png),
      ),
    );
  }
}

class _FullPreviewPage extends StatelessWidget {
  final Uint8List png;
  const _FullPreviewPage({required this.png});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.memory(png, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final Uint8List? previewPng;
  final VoidCallback? onExpand;
  const _PreviewCard({this.previewPng, this.onExpand});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 0.77, // proporção A4 retrato
          child: Stack(
            children: [
              Positioned.fill(
                child: previewPng == null
                    ? Container(
                        color: const Color(0xFFF3F4F6),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF29B6D2)),
                        ),
                      )
                    : Image.memory(
                        previewPng!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
              ),
              if (onExpand != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onExpand,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.open_in_full, color: Colors.white, size: 18),
                      ),
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

class _FileInfoCard extends StatelessWidget {
  final String fileName;
  final String sizeLabel;
  final VoidCallback? onDelete;
  const _FileInfoCard({
    required this.fileName,
    required this.sizeLabel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.attach_file_rounded, color: Color(0xFF6B7280), size: 22),
          const SizedBox(width: 10),
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
                Text(sizeLabel, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 24),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: Color(0xFF6B7280)),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}
