/// Política única para o e-mail público de contato do perfil.
///
/// O e-mail usado para autenticação pode ser um alias privado da Apple ou
/// um endereço sintético do login por telefone. Esses endereços continuam
/// válidos para login, mas não devem ser publicados em currículos nem usados
/// como contato por recrutadores.
class ContactEmail {
  ContactEmail._();

  static const Set<String> _applePrivateRelayDomains = {
    'privaterelay.appleid.com',
    'private.icloud.com',
  };

  static final RegExp _validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String normalize(String? value) => value?.trim().toLowerCase() ?? '';

  static String _domain(String? value) {
    final normalized = normalize(value);
    final separator = normalized.lastIndexOf('@');
    return separator < 0 ? '' : normalized.substring(separator + 1);
  }

  static bool isValid(String? value) {
    final normalized = normalize(value);
    return normalized.isNotEmpty && _validEmail.hasMatch(normalized);
  }

  static bool isApplePrivateRelay(String? value) =>
      _applePrivateRelayDomains.contains(_domain(value));

  static bool isSyntheticAuthEmail(String? value) {
    final normalized = normalize(value);
    final separator = normalized.indexOf('@');
    if (separator <= 0 || _domain(normalized) != 'stage.app') return false;
    final localPart = normalized.substring(0, separator);
    return localPart.startsWith('phone_') && localPart.length > 'phone_'.length;
  }

  static bool isPrivateOrSynthetic(String? value) =>
      isApplePrivateRelay(value) || isSyntheticAuthEmail(value);

  /// Um e-mail publicável precisa ter formato válido e não pode ser um
  /// identificador privado/sintético de autenticação.
  static bool isUsable(String? value) =>
      isValid(value) && !isPrivateOrSynthetic(value);

  /// Defesa de última linha para saídas públicas, como currículos.
  static String resumeValueOrEmpty(String? value) =>
      isUsable(value) ? normalize(value) : '';

  /// Resolve o valor inicial sem misturar identidade de login com contato.
  /// Um valor inseguro é ignorado e a próxima fonte é considerada.
  static String resolveInitial({
    String? profileEmail,
    String? extractedEmail,
    String? authEmail,
  }) {
    for (final candidate in [profileEmail, extractedEmail, authEmail]) {
      if (isUsable(candidate)) return normalize(candidate);
    }
    return '';
  }
}
