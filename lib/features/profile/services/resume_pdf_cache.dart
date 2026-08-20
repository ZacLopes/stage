// =============================================================================
// resume_pdf_cache.dart — baixa, rasteriza e mede os PDFs da biblioteca.
//
// Três regras que não são estilo:
//
// 1. FILA SERIAL DE 1. Rasterizar PDF no iOS passa por `DispatchQueue.main.sync`
//    por página (PrintJob.swift). Disparar N rasters em paralelo pra uma lista
//    de currículos trava a UI thread. Um de cada vez, sempre.
//
// 2. `PdfPreview` (do pacote `printing`) NUNCA monta no corpo da lista. Ele
//    rasteriza TODAS as páginas em ~136 dpi (~7 MB RGBA por página) e já
//    produziu `RangeError` neste repo quando a State morre no meio
//    (`adapted_resume_preview_screen.dart:418-427`). Na lista usamos
//    `Printing.raster` só da PÁGINA 1, e o `PdfPreview` fica exclusivo da tela
//    cheia, uma instância por vez.
//
// 3. UM RASTER POR ARQUIVO. O herói pede 326pt e a miniatura da linha pede
//    48pt — mas é o MESMO PNG, reescalado por `cacheWidth` no `Image.memory`.
//    Rasterizar duas vezes o mesmo arquivo é o erro caro aqui.
// =============================================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../../data/models/models.dart';
import '../utils/resume_meta.dart';

/// Acima disto não rasterizamos. Existe um arquivo de 34 MB em produção;
/// tentar rasterizá-lo derruba o app antes de mostrar qualquer coisa.
const int kMaxPreviewBytes = 8 * 1024 * 1024;

/// Largura em pixels do raster da página 1.
///
/// 326pt de card × 3 (retina) = 978. Em A4 (595,28pt de largura) isso dá
/// `978 ÷ 595,28 × 72 ≈ 118 dpi` — nítido no herói e ainda barato.
const int kRasterWidthPx = 978;

/// Estado de preview de UM currículo. Imutável; a tela escuta as trocas.
@immutable
class ResumePreview {
  const ResumePreview({
    this.png,
    this.facts = const ResumeFileFacts(),
    this.loading = false,
  });

  /// PNG da página 1. Null enquanto não chegou (ou se falhou).
  final Uint8List? png;
  final ResumeFileFacts facts;
  final bool loading;

  ResumePreview copyWith({
    Uint8List? png,
    ResumeFileFacts? facts,
    bool? loading,
  }) =>
      ResumePreview(
        png: png ?? this.png,
        facts: facts ?? this.facts,
        loading: loading ?? this.loading,
      );
}

/// Assinatura do download — injetável pra teste não precisar de Supabase.
typedef ResumeBytesLoader = Future<Uint8List> Function(String filePath);

class ResumePdfCache {
  ResumePdfCache({required ResumeBytesLoader loader}) : _loader = loader;

  final ResumeBytesLoader _loader;

  final Map<String, ValueNotifier<ResumePreview>> _slots = {};
  final List<_Job> _fila = [];
  bool _rodando = false;
  bool _disposed = false;

  /// Fatos já conhecidos, na forma que `findLikelyDuplicates` espera.
  Map<String, ResumeFileFacts> get facts =>
      _slots.map((id, n) => MapEntry(id, n.value.facts));

  /// Escuta o preview de [resume], agendando o carregamento na primeira vez.
  ///
  /// Idempotente: chamar em todo rebuild não re-agenda nada.
  ValueListenable<ResumePreview> watch(SavedResume resume) {
    final existente = _slots[resume.id];
    if (existente != null) return existente;

    final slot = ValueNotifier(const ResumePreview(loading: true));
    _slots[resume.id] = slot;
    _enfileirar(_Job(resume.id, resume.filePath, slot));
    return slot;
  }

  /// Reenfileira um item que falhou (o usuário tocou em "tentar de novo").
  void retry(SavedResume resume) {
    final slot = _slots[resume.id];
    if (slot == null) {
      watch(resume);
      return;
    }
    if (slot.value.loading) return;
    slot.value = slot.value.copyWith(
      loading: true,
      facts: slot.value.facts.copyWith(failed: false),
    );
    _enfileirar(_Job(resume.id, resume.filePath, slot));
  }

  void _enfileirar(_Job job) {
    _fila.add(job);
    unawaited(_drenar());
  }

  Future<void> _drenar() async {
    if (_rodando || _disposed) return;
    _rodando = true;

    while (_fila.isNotEmpty && !_disposed) {
      final job = _fila.removeAt(0);
      await _processar(job);
    }

    _rodando = false;
  }

  Future<void> _processar(_Job job) async {
    Uint8List bytes;
    try {
      bytes = await _loader(job.filePath);
    } catch (_) {
      _emitir(job, const ResumePreview(facts: ResumeFileFacts(failed: true)));
      return;
    }
    if (_disposed) return;

    // O tamanho vem do próprio download — não precisa de `storage.list`.
    var fatos = ResumeFileFacts(bytes: bytes.length);

    // Contagem de páginas é barata (parse de estrutura, não render) e é o que
    // permite `findLikelyDuplicates` discriminar dois arquivos de mesmo peso.
    try {
      final doc = PdfDocument(inputBytes: bytes);
      fatos = fatos.copyWith(pages: doc.pages.count);
      doc.dispose();
    } catch (_) {
      // PDF ilegível pro parser: seguimos sem contagem. O raster pode até
      // funcionar; e se não funcionar, cai no `failed` abaixo.
    }
    if (_disposed) return;

    if (bytes.length > kMaxPreviewBytes) {
      _emitir(
        job,
        ResumePreview(facts: fatos.copyWith(tooLargeToPreview: true)),
      );
      return;
    }

    // Emite os fatos ANTES do raster: a linha já mostra "2 páginas · 240 KB"
    // enquanto a imagem ainda vem. Sem isso o metadado espera o render.
    _emitir(job, ResumePreview(facts: fatos, loading: true));

    try {
      final pagina = await Printing.raster(
        bytes,
        pages: const [0],
        dpi: kRasterWidthPx / 595.28 * 72,
      ).first;
      if (_disposed) return;
      final png = await pagina.toPng();
      if (_disposed) return;
      _emitir(job, ResumePreview(png: png, facts: fatos));
    } catch (_) {
      _emitir(job, ResumePreview(facts: fatos.copyWith(failed: true)));
    }
  }

  void _emitir(_Job job, ResumePreview valor) {
    if (_disposed) return;
    job.slot.value = valor;
  }

  /// Cancela o que está na fila e solta os notifiers.
  ///
  /// O job em voo não é interrompível (é await de plugin), mas `_disposed`
  /// impede que ele escreva num notifier já morto — que é o crash real.
  void dispose() {
    _disposed = true;
    _fila.clear();
    for (final slot in _slots.values) {
      slot.dispose();
    }
    _slots.clear();
  }
}

class _Job {
  _Job(this.id, this.filePath, this.slot);
  final String id;
  final String filePath;
  final ValueNotifier<ResumePreview> slot;
}
