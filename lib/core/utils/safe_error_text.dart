/// Defesa de última linha para TEXTO DE ERRO exibido ao usuário.
///
/// ## Por que existe
///
/// O device-test de 24/07 (§9, A3) flagrou a tela mostrando um
/// `ClientException` de conexão fechada seguido de `uri=https://` + o host do
/// projeto Supabase — jargão em inglês para usuário pt-BR **e** a URL/ref do
/// projeto vazando na UI.
///
/// A primeira correção tratou só o caminho da adaptação. O code-review de
/// 27/07 mostrou que a mesma classe continuava viva em outro lugar
/// (`Text('Erro ao gerar PDF: $e')` no export do Currículo geral). Consertar
/// caso a caso não fecha a classe — por isso a política mora aqui, num lugar
/// só, e quem exibe erro passa por ela.
///
/// Mesmo espírito de [ContactEmail], que protege o e-mail impresso no CV.
class SafeErrorText {
  SafeErrorText._();

  /// Marcadores de que um texto é técnico e não pode ir para a tela:
  /// URL, query de URI, nome de exceção, stack, host do Supabase, JSON.
  static final RegExp _technical = RegExp(
    r'(https?://|uri=|Exception|Error:|stack|\.supabase\.co|\{|\})',
    caseSensitive: false,
  );

  /// True quando o texto é seguro para renderizar direto ao usuário.
  static bool isPresentable(String? text) {
    final trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) return false;
    return !_technical.hasMatch(trimmed);
  }

  /// Devolve [fallback] sempre que [error] não for apresentável.
  ///
  /// Nunca interpole um `Object error` direto numa `Text()`: use isto. O
  /// detalhe técnico continua útil no log — só não na tela.
  static String orFallback(Object? error, String fallback) {
    if (error == null) return fallback;
    final text = error is String ? error : error.toString();
    return isPresentable(text) ? text.trim() : fallback;
  }
}
