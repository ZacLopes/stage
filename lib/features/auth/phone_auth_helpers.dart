// PhoneAuthHelpers — utilitário compartilhado entre PhoneSignupScreen e o
// login bottom sheet pra sintetizar email determinístico a partir do
// telefone enquanto Twilio/SMS OTP ainda não está habilitado.
//
// Quando Twilio for configurado, substituir o uso desta classe por chamadas
// nativas `signUp(phone: ...)` / `signInWithOtp(phone: ...)` do Supabase.

class PhoneAuthHelpers {
  /// Sintetiza um email no formato 'phone_<digits>@stage.app' a partir do
  /// country code + número. Determinístico — mesmo número sempre gera o
  /// mesmo email, então signup e signIn batem.
  ///
  /// Mantém só dígitos do country code (remove '+') e do número (remove
  /// máscara/espaços/hífens). Ex: '+55', '(11) 98765-4321' → email
  /// 'phone_5511987654321@stage.app'.
  static String syntheticEmail({
    required String countryCode,
    required String phone,
  }) {
    final ccDigits = countryCode.replaceAll(RegExp(r'[^0-9]'), '');
    final phoneDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return 'phone_$ccDigits$phoneDigits@stage.app';
  }

  /// True quando o email é sintético (gerado por phone signup), formato
  /// `phone_<digits>@stage.app`. Usado pra:
  /// - Esconder "Trocar senha" nas configs (esses users entram via OTP
  ///   SMS, senha não tem uso prático — confunde o user).
  /// - Outras heurísticas que diferenciam email-real vs phone-only.
  static bool isSyntheticEmail(String? email) {
    if (email == null || email.isEmpty) return false;
    return email.startsWith('phone_') && email.endsWith('@stage.app');
  }

  /// Reverte um synthetic email pro par (countryCode, phoneNumber).
  /// Ex: 'phone_5543991260202@stage.app' → ('+55', '43991260202').
  ///
  /// Tenta match com os country codes suportados pelo app (mais longos
  /// primeiro pra evitar ambiguidade — '351' antes de '1'). Retorna null
  /// se o email não é sintético ou se nenhum code bate.
  static ({String countryCode, String phone})? parseSyntheticEmail(String? email) {
    if (!isSyntheticEmail(email)) return null;
    const prefix = 'phone_';
    const suffix = '@stage.app';
    final digits = email!.substring(prefix.length, email.length - suffix.length);
    // Ordem importa: '351' tem que vir antes de '1', '44' antes de '4'.
    const codes = ['351', '55', '44', '1'];
    for (final code in codes) {
      if (digits.startsWith(code)) {
        return (countryCode: '+$code', phone: digits.substring(code.length));
      }
    }
    return null;
  }
}
