// ignore_for_file: avoid_print
//
// Tela de DEV TOOL pra regenerar as miniaturas dos templates de currículo
// usadas no `ResumeTemplateSelector`.
//
// Como usar:
//   1. Em debug mode, abre Settings → "[DEV] Gerar thumbnails dos templates"
//   2. Toca em "Gerar 5 PNGs"
//   3. App gera os 5 PNGs em <Documents>/template_thumbnails/
//   4. A tela mostra o caminho completo da pasta — copia ela e cola no Finder
//   5. Move os 5 PNGs pra `assets/images/templates/` no projeto
//   6. Roda `flutter pub get` e commita
//
// Quando rodar de novo: sempre que o HTML de um dos templates em
// `pdf_service.dart` mudar visualmente.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../pdf_service.dart';
import 'template_thumbnail_mock_data.dart';
import '../../../core/theme/theme.dart';

const _kTemplateIds = [
  'harvard_ats',
  'jakes_resume',
  'forte_foundation',
  'one_page_compact',
  'cobalt_modern',
];

class TemplateThumbnailGeneratorScreen extends StatefulWidget {
  const TemplateThumbnailGeneratorScreen({super.key});

  @override
  State<TemplateThumbnailGeneratorScreen> createState() =>
      _TemplateThumbnailGeneratorScreenState();
}

class _TemplateThumbnailGeneratorScreenState
    extends State<TemplateThumbnailGeneratorScreen> {
  final Map<String, _Result> _results = {};
  bool _running = false;
  String? _outputDirPath;

  Future<void> _generateAll() async {
    setState(() {
      _running = true;
      _results.clear();
      _outputDirPath = null;
    });

    try {
      final docs = await getApplicationDocumentsDirectory();
      final outDir = Directory('${docs.path}/template_thumbnails');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      for (final id in _kTemplateIds) {
        setState(() {
          _results[id] = _Result.running();
        });

        try {
          final pdfBytes = await PdfService.generateResumeBytes(
            kThumbnailMockProfile,
            kThumbnailMockResume,
            id,
          );

          Uint8List? pngBytes;
          await for (final page in Printing.raster(
            pdfBytes,
            pages: const [0],
            dpi: 144,
          )) {
            pngBytes = await page.toPng();
            break;
          }

          if (pngBytes == null) {
            throw StateError('Printing.raster retornou stream vazia');
          }

          final outFile = File('${outDir.path}/$id.png');
          await outFile.writeAsBytes(pngBytes);

          setState(() {
            _results[id] = _Result.ok(outFile.path, pngBytes!.lengthInBytes);
          });
        } catch (e, st) {
          print('Falha em $id: $e\n$st');
          setState(() {
            _results[id] = _Result.error(e.toString());
          });
        }
      }

      setState(() {
        _outputDirPath = outDir.path;
      });
    } finally {
      setState(() {
        _running = false;
      });
    }
  }

  Future<void> _copyPath() async {
    if (_outputDirPath == null) return;
    await Clipboard.setData(ClipboardData(text: _outputDirPath!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Caminho copiado pra área de transferência'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Abre o share sheet nativo com os PNGs gerados. No iPhone permite
  /// AirDrop pro Mac, save no Files app, envio por iMessage etc — mais
  /// rápido que tentar achar o diretório sandboxado do app.
  Future<void> _sharePngs() async {
    if (_outputDirPath == null) return;
    final dir = Directory(_outputDirPath!);
    if (!dir.existsSync()) return;
    final pngs = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .map((f) => XFile(f.path))
        .toList();
    if (pngs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum PNG encontrado pra compartilhar'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: pngs,
          subject: 'Thumbnails dos templates do Stage',
          text: 'PNGs gerados pra assets/images/templates/',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao compartilhar: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '[DEV] Gerar thumbnails',
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Regenera os PNGs de preview dos 5 templates de currículo. '
                'Use sempre que o HTML de algum template mudar.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _running ? null : _generateAll,
                icon: _running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.image_outlined),
                label: Text(_running ? 'Gerando...' : 'Gerar 5 PNGs'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    for (final id in _kTemplateIds)
                      _resultTile(id, _results[id]),
                    if (_outputDirPath != null) ...[
                      const SizedBox(height: 24),
                      _outputDirCard(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultTile(String id, _Result? result) {
    final IconData icon;
    final Color color;
    final String trailing;

    if (result == null) {
      icon = Icons.radio_button_unchecked;
      color = AppColors.textTertiary;
      trailing = 'pendente';
    } else if (result.running) {
      icon = Icons.hourglass_top;
      color = Colors.orange;
      trailing = 'gerando...';
    } else if (result.error != null) {
      icon = Icons.error_outline;
      color = AppColors.error;
      trailing = result.error!;
    } else {
      icon = Icons.check_circle;
      color = Colors.green;
      trailing = '${result.sizeBytes! ~/ 1024} KB';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              id,
              style: TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            trailing,
            style: TextStyle(fontFamily: 'Inter', 
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _outputDirCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PNGs salvos em:',
            style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SelectableText(
            _outputDirPath!,
            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: _copyPath,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copiar caminho'),
                style: TextButton.styleFrom(foregroundColor: AppColors.success),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _sharePngs,
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('Compartilhar PNGs'),
                style: TextButton.styleFrom(foregroundColor: AppColors.success),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No iPhone: toque em "Compartilhar PNGs" → AirDrop pro seu Mac '
            '(ou Salvar em Arquivos). Depois move os PNGs pra '
            'assets/images/templates/ e commita.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textPrimary, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Result {
  final bool running;
  final String? path;
  final int? sizeBytes;
  final String? error;

  _Result.running()
      : running = true,
        path = null,
        sizeBytes = null,
        error = null;

  _Result.ok(this.path, this.sizeBytes)
      : running = false,
        error = null;

  _Result.error(this.error)
      : running = false,
        path = null,
        sizeBytes = null;
}
