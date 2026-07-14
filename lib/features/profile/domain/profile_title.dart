/// Normaliza um título curto digitado pelo usuário sem destruir marcas ou
/// siglas que já tenham capitalização intencional.
///
/// A regra é deliberadamente conservadora:
/// - sempre aplica `trim`;
/// - se já houver alguma letra maiúscula, preserva o texto (`iFood`, `TCC`);
/// - se todas as letras estiverem minúsculas, capitaliza somente a primeira
///   letra com caixa (`aplicativo...` → `Aplicativo...`).
///
/// Não é Title Case: preposições, nomes de marca e acrônimos não devem ser
/// "adivinhados" pelo app.
String normalizeProfileTitle(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';

  var hasUppercase = false;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final upper = char.toUpperCase();
    final lower = char.toLowerCase();
    if (upper != lower && char == upper) {
      hasUppercase = true;
      break;
    }
  }
  if (hasUppercase) return text;

  final out = StringBuffer();
  var capitalized = false;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final upper = char.toUpperCase();
    final lower = char.toLowerCase();
    if (!capitalized && upper != lower) {
      out.write(upper);
      capitalized = true;
    } else {
      out.write(char);
    }
  }
  return out.toString();
}
