// =============================================================================
// resume_preview_screen.dart — leitura em tela cheia, com folheio entre os
// currículos da biblioteca.
//
// É AQUI que "passar de um currículo para o outro" acontece, com o maior número
// de pixels possível. Na lista, folhear é secundário; escolher é o que importa.
//
// Dois gotchas que não são opinião:
//
// 1. `PdfPreview` precisa de uma `Key` que mude com o documento. Sem ela ele
//    cacheia o PDF anterior internamente e trocar de currículo mostra o antigo
//    (o mesmo bug já registrado em `resume_detail_screen.dart:812-814`).
//
// 2. `dpi` explícito. O default rasteriza em ~136 dpi × TODAS as páginas
//    (~7 MB RGBA por página) e já produziu `RangeError` neste repo. 110 dpi é
//    nítido no iPhone e cabe na memória.
// =============================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/pii_mask.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';

class ResumePreviewScreen extends StatefulWidget {
  const ResumePreviewScreen({
    super.key,
    required this.resumes,
    this.initialIndex = 0,
  });

  final List<SavedResume> resumes;
  final int initialIndex;

  @override
  State<ResumePreviewScreen> createState() => _ResumePreviewScreenState();
}

class _ResumePreviewScreenState extends State<ResumePreviewScreen> {
  final _repo = SupabaseRepository();
  final Map<String, Uint8List> _bytes = {};
  final Set<String> _falhou = {};

  late int _index;
  bool _baixando = false;

  SavedResume get _atual => widget.resumes[_index];
  bool get _temAnterior => _index > 0;
  bool get _temProximo => _index < widget.resumes.length - 1;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.resumes.length - 1);
    _garantirBytes(_atual);
  }

  Future<void> _garantirBytes(SavedResume r) async {
    if (_bytes.containsKey(r.id)) return;
    setState(() {
      _baixando = true;
      _falhou.remove(r.id);
    });
    try {
      final b = await _repo.downloadResume(r.filePath);
      if (!mounted) return;
      setState(() {
        _bytes[r.id] = b;
        _baixando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _falhou.add(r.id);
        _baixando = false;
      });
    }
  }

  void _ir(int delta) {
    final novo = _index + delta;
    if (novo < 0 || novo >= widget.resumes.length) return;
    setState(() => _index = novo);
    _garantirBytes(_atual);
  }

  @override
  Widget build(BuildContext context) {
    final varios = widget.resumes.length > 1;

    return PiiMask(
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _atual.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: AppColors.textPrimary,
                ),
              ),
              if (varios)
                Text(
                  '${_index + 1} de ${widget.resumes.length}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.share_rounded, size: 22),
              tooltip: 'Compartilhar',
              onPressed: _bytes[_atual.id] == null
                  ? null
                  : () => Printing.sharePdf(
                        bytes: _bytes[_atual.id]!,
                        filename:
                            '${_atual.title.replaceAll(' ', '_')}.pdf',
                      ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _corpo()),
            if (varios) _barraDeFolheio(),
          ],
        ),
      ),
    );
  }

  Widget _corpo() {
    if (_falhou.contains(_atual.id)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 32,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Não consegui baixar este arquivo agora.',
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            TextButton(
              onPressed: () => _garantirBytes(_atual),
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      );
    }

    final bytes = _bytes[_atual.id];
    if (bytes == null || _baixando) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: PdfPreview(
        // Sem esta Key, trocar de currículo mostra o PDF anterior.
        key: ValueKey('${_atual.id}_${bytes.length}'),
        build: (_) => bytes,
        useActions: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        dpi: 110,
        maxPageWidth: 600,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg,
          horizontal: AppSpacing.base,
        ),
        scrollViewDecoration: const BoxDecoration(
          color: AppColors.background,
        ),
        pdfPreviewPageDecoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        loadingWidget: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _barraDeFolheio() {
    return SafeArea(
      top: false,
      child: Container(
        height: 56,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _temAnterior ? () => _ir(-1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Anterior'),
            ),
            TextButton.icon(
              onPressed: _temProximo ? () => _ir(1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text('Próximo'),
              iconAlignment: IconAlignment.end,
            ),
          ],
        ),
      ),
    );
  }
}
