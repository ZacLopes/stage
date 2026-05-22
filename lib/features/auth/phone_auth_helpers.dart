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
}
