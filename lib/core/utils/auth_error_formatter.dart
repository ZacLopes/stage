import 'package:supabase_flutter/supabase_flutter.dart';

class AuthErrorFormatter {
  static String format(Object e) {
    if (e is AuthException) {
      switch (e.code) {
        case 'invalid_credentials':
          final message = e.message.toLowerCase();
          if (message.contains('user not found') || message.contains('email not found')) {
            return 'Não existe nenhuma conta com o e-mail informado.';
          }
          if (message.contains('invalid login credentials')) {
            return 'E-mail ou senha incorretos.';
          }
          return 'Credenciais inválidas. Verifique seus dados.';
        case 'user_not_found':
          return 'Não existe nenhuma conta com o e-mail informado.';
        case 'invalid_grant':
          final messageGrant = e.message.toLowerCase();
          if (messageGrant.contains('user not found') || messageGrant.contains('email not found')) {
            return 'Não existe nenhuma conta com o e-mail informado.';
          }
          return 'E-mail ou senha incorretos.';
        case 'unexpected_failure':
          return 'Ocorreu um erro inesperado. Tente novamente em instantes.';
        default:
          final messageDefault = e.message.toLowerCase();
          if (messageDefault.contains('user not found') || messageDefault.contains('email not found')) {
            return 'Não existe nenhuma conta com o e-mail informado.';
          }
          if (messageDefault.contains('invalid login credentials')) {
            return 'E-mail ou senha incorretos.';
          }
          if (messageDefault.contains('already registered') || messageDefault.contains('already exists')) {
            return 'Este e-mail já está cadastrado.';
          }
      }
      return e.message;
    }

    final errorStr = e.toString().toLowerCase();
    
    if (errorStr.contains('socketexception') || errorStr.contains('handshakeexception')) {
      return 'Sem conexão com a internet. Verifique seu sinal e tente novamente.';
    }
    
    if (errorStr.contains('network_error')) {
      return 'Erro de rede. Verifique sua conexão.';
    }

    if (errorStr.contains('invalid login credentials') || errorStr.contains('invalid_credentials')) {
      return 'E-mail ou senha incorretos.';
    }

    if (errorStr.contains('user not found') || errorStr.contains('email not found') || errorStr.contains('user_not_found')) {
      return 'Não existe nenhuma conta com o e-mail informado.';
    }
    
    return 'Ocorreu um problema. Tente novamente.';
  }
}
