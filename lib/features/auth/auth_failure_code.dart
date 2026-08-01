import 'package:supabase_flutter/supabase_flutter.dart';

/// Motivo de uma falha de autenticação, em forma estável para telemetria.
///
/// Existe porque `auth_signup_failed` estava no catálogo de eventos
/// (`analytics_events.dart:40`) e **nunca era emitido**: se o cadastro
/// começasse a falhar, isso não apareceria em painel nenhum — só na queda de
/// contas criadas, semanas depois. O gatilho concreto é a política de senha do
/// servidor: apertá-la sem este evento é mexer no funil de entrada às cegas.
///
/// ## Por que uma função, e não `e.toString()`
///
/// A mensagem do servidor é imprópria como propriedade de evento por três
/// motivos: muda entre versões do GoTrue (a série temporal quebra sem aviso),
/// tem cardinalidade alta demais para agrupar, e pode carregar dado de quem
/// tentou entrar. O que vai para o PostHog é sempre um destes rótulos fechados.
///
/// A ordem das checagens importa: `AuthWeakPasswordException` é subclasse de
/// `AuthException`, então precisa vir antes.
String authFailureCode(Object error) {
  if (error is AuthWeakPasswordException) {
    // A razão exata ('length' | 'characters' | 'pwned') é o que responde
    // "qual aperto de política está barrando gente".
    final r = error.reasons;
    if (r.contains('pwned')) return 'weak_password_pwned';
    if (r.contains('characters')) return 'weak_password_characters';
    if (r.contains('length')) return 'weak_password_length';
    return 'weak_password';
  }

  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('already registered') || msg.contains('already exists')) {
      return 'already_registered';
    }
    if (msg.contains('invalid login credentials')) return 'invalid_credentials';
    if (msg.contains('user not found')) return 'user_not_found';
    if (msg.contains('rate limit') || error.statusCode == '429') {
      return 'rate_limited';
    }
    // `code` do SDK quando existe: já é um rótulo curto e estável.
    final code = error.code;
    if (code != null && code.isNotEmpty) return code;
    return 'auth_error';
  }

  final s = error.toString().toLowerCase();
  if (s.contains('socketexception') ||
      s.contains('handshakeexception') ||
      s.contains('network')) {
    return 'network';
  }
  if (s.contains('timeout')) return 'timeout';
  return 'unknown';
}
