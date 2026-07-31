/// Limpeza do conteúdo que vem do ATS da empresa.
///
/// Revisão UX 28/07, achado P2-17. O texto de vaga não é escrito para o Stage:
/// é copiado de um formulário do Gupy, do InHire ou do site da empresa, e
/// chega com as marcas disso. Duas dessas marcas sobreviveram à primeira
/// rodada de correção — o marcador duplo e o `;` já tinham dono
/// (`Job._stripListItemMarker`), estes dois não tinham.
library;

/// Frases de encerramento que o ATS empilha no MESMO array de requisitos.
///
/// Na tela isso virava `✓ Desejamos uma ótima seleção para você!` numerado
/// junto com "Cursando a partir do 5º semestre" — uma despedida apresentada
/// como exigência da vaga. Quem lê rápido conta um requisito a mais do que a
/// vaga tem, e o item mais visível da lista não é um requisito.
///
/// A lista é conservadora de propósito: derrubar um requisito real é pior que
/// deixar passar uma despedida. Por isso o casamento é por FÓRMULA de
/// encerramento (verbo de votos + destinatário), não por palavra solta —
/// "sucesso" e "boa" aparecem em requisito legítimo ("Boa comunicação").
final List<RegExp> _formulasDeEncerramento = [
  RegExp(r'^\s*desejamos\b', caseSensitive: false),
  RegExp(r'^\s*boa\s+(sorte|seleção|prova)\b', caseSensitive: false),
  RegExp(r'^\s*sucesso\s+(a|na|no|pra|para)\b', caseSensitive: false),
  RegExp(r'^\s*(nos\s+vemos|até\s+(breve|logo|mais))\b', caseSensitive: false),
  RegExp(r'^\s*(obrigad[oa]|agradecemos)\b', caseSensitive: false),
  RegExp(r'^\s*conte\s+conosco\b', caseSensitive: false),
  RegExp(r'^\s*(esperamos|aguardamos)\s+(te|voc[êe]|sua|seu)\b',
      caseSensitive: false),
  RegExp(r'^\s*lembre[\-\s]se\s+(que|de)\b', caseSensitive: false),
];

/// True quando a linha é uma despedida do recrutador, não um requisito.
bool isClosingPleasantry(String line) {
  final s = line.trim();
  if (s.isEmpty) return false;
  return _formulasDeEncerramento.any((re) => re.hasMatch(s));
}

// ── Vãos gigantes na descrição ───────────────────────────────────────────

/// Parágrafo que só contém espaço, `&nbsp;`, `<br>` ou tag inline vazia.
///
/// Esta é a origem dos vãos de várias centenas de pixels na descrição. O
/// saneamento anterior colapsava `<p>\s*</p>`, que quase nunca é o que o ATS
/// manda: o editor de texto do recrutador produz `<p>&nbsp;</p>`,
/// `<p><span>&nbsp;</span></p>` e `<p><br></p>` — todos com conteúdo, todos
/// invisíveis, todos ocupando a altura de linha MAIS a margem de parágrafo.
/// Seis deles seguidos são um buraco de tela inteira.
final RegExp _paragrafoVazio = RegExp(
  r'<p[^>]*>(?:\s|&nbsp;|<br\s*/?>|<span[^>]*>|</span>|<strong>|</strong>|<em>|</em>|<b>|</b>|<i>|</i>)*</p>',
  caseSensitive: false,
);

/// `<div>` no mesmo estado — o InHire usa div onde o Gupy usa p.
final RegExp _divVazia = RegExp(
  r'<div[^>]*>(?:\s|&nbsp;|<br\s*/?>|<span[^>]*>|</span>)*</div>',
  caseSensitive: false,
);

/// Dois ou mais `<br>` seguidos. Um `<br>` já quebra a linha; o segundo em
/// diante só empilha vão. Separação real de bloco vem do `<p>`.
final RegExp _brEmSerie = RegExp(
  r'(?:\s*<br\s*/?>\s*){2,}',
  caseSensitive: false,
);

/// `<br>` colado na abertura ou no fechamento do parágrafo — some, porque a
/// margem do `<p>` já faz esse trabalho.
final RegExp _brNaBorda = RegExp(
  r'(<p[^>]*>)(?:\s*<br\s*/?>\s*)+|(?:\s*<br\s*/?>\s*)+(</p>)',
  caseSensitive: false,
);

/// Tira os blocos invisíveis que viram vão na descrição da vaga.
///
/// Roda em laço porque remover um `<p>` vazio pode expor outro que estava
/// aninhado — `<div><p>&nbsp;</p></div>` só vira `<div></div>` depois da
/// primeira passada. Três voltas cobrem os casos reais e limitam entrada
/// patológica.
String collapseEmptyHtmlBlocks(String html) {
  if (html.isEmpty) return html;
  var s = html;
  for (var i = 0; i < 3; i++) {
    final antes = s;
    s = s
        .replaceAll(_paragrafoVazio, '')
        .replaceAll(_divVazia, '')
        .replaceAllMapped(
            _brNaBorda, (m) => m.group(1) ?? m.group(2) ?? '')
        .replaceAll(_brEmSerie, '<br>');
    if (s == antes) break;
  }
  return s.trim();
}
