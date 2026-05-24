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
    final sanitized = _sanitizeSyncfusionArtifacts(text);
    final lines = sanitized
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.join('\n');
  }

  /// Remove artifacts "C" que Syncfusion insere ANTES de 'i' ou 'm' quando
  /// o PDF usa font subsetting/ligatures. Casos reais observados:
  ///   "Business"       → "BusCiness"          (C antes do 'i')
  ///   "Administration" → "AdCmCinCistratCion" (C antes de cada 'm' e 'i')
  ///   "Joaquim"        → "JoaquCiCm"          (C antes de 'i' e 'm')
  ///   "Floriano"       → "FlorCiano"
  ///   "Itaim Bibi"     → "ItaCiCm BCibCi"
  ///   "Mobile"         → "MobCile"
  ///   "linkedin.com"   → "lCinkedCin.coCm"
  ///
  /// Versão 1 (buggy) removia "Ci" inteiro — perdia o 'i' legítimo
  /// ("lCinkedCin" virava "lnkedn" em vez de "linkedin").
  /// Versão 2 (correta) remove só o 'C' que precede 'i'/'m', preservando
  /// o caractere alvo.
  ///
  /// Whitelist evita falso-positivo em palavras legítimas (cidade, cinema,
  /// ciência, círculo) — onde "Ci" é genuíno.
  ///
  /// Tier 3.2 do plano "1000x melhor". Band-aid pra `raw_text_fallback`
  /// (UI já não usa raw_text — Tier 2.6 mostra PDF binário direto).
  static String _sanitizeSyncfusionArtifacts(String text) {
    if (text.isEmpty) return text;
    if (!text.contains('C')) return text;
    const legit = <String>{
      'cidade', 'cidades', 'cinema', 'cinemas', 'ciência', 'ciências',
      'circuito', 'circuitos', 'círculo', 'círculos', 'cifra', 'cifras',
      'cidadão', 'cidadã', 'cidadania',
      'cipreste', 'cisco', 'cisne', 'citação', 'citações', 'cisão',
      'cinco', 'cinto', 'cinza', 'cirurgia', 'cirurgião',
      'city', 'cities', 'circle', 'circles', 'cipher',
      'circuit', 'circuits', 'citizen', 'cite', 'cited',
    };

    final tokens = text.split(RegExp(r'(\s+)'));
    final out = StringBuffer();
    for (final t in tokens) {
      if (t.isEmpty || RegExp(r'^\s+$').hasMatch(t)) {
        out.write(t);
        continue;
      }
      final clean = t.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
      if (legit.contains(clean.toLowerCase())) {
        out.write(t);
        continue;
      }
      // Remove 'C' inserido antes de 'i' ou 'm' (preserva 'i'/'m').
      // Lookbehind `(?<![A-Z])` evita comer C de palavras CAPITALIZADAS
      // legítimas ("Cm" no início de uma sigla tipo "CMS" ficaria errado;
      // mas a inserção Syncfusion sempre vem em palavras com letras
      // minúsculas adjacentes). Loop até estabilizar.
      var cur = t;
      for (var i = 0; i < 8; i++) {
        final next = cur.replaceAll(
          RegExp(r'(?<![A-Z])C(?=[im])'),
          '',
        );
        if (next == cur) break;
        cur = next;
      }
      out.write(cur);
    }
    return out.toString();
  }
}
