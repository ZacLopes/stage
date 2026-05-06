import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// Extrai texto de PDFs enviados pelo usuário (currículos importados).
///
/// Retorna string vazia se o PDF for somente imagem (scan sem camada de
/// texto). Use [isUsable] pra validar se o resultado tem conteúdo suficiente
/// pra alimentar o cálculo de match — abaixo de 200 caracteres provavelmente
/// é scan e precisaria de OCR (não suportado).
class ResumePdfExtractor {
  static String extract(Uint8List bytes) {
    final document = sf.PdfDocument(inputBytes: bytes);
    try {
      final extractor = sf.PdfTextExtractor(document);
      return _normalize(extractor.extractText());
    } finally {
      document.dispose();
    }
  }

  static bool isUsable(String text) => text.trim().length >= 200;

  static String _normalize(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.join('\n');
  }
}
