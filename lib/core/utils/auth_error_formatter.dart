import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/password_rule.dart';
import 'safe_error_text.dart';

/// Por qual identificador a pessoa está tentando entrar.
///
/// Existe porque o texto de erro precisa nomear o que ela DIGITOU. Antes o
/// formatador dizia "E-mail ou senha incorretos" em todo caminho — e o app não
/// tem login por e-mail: são Google, Apple e telefone. Quem errava a senha na
/// tela "Continuar com telefone", depois de digitar (11) 98765-0143, lia uma
/// frase sobre e-mail e ficava sem saber o que corrigir.
///
/// A origem do engano é técnica e vaza justamente aqui: o login por telefone
/// grava um e-mail SINTÉTICO (`phone_55…@stage.app`) porque o Twilio não está
/// configurado, então o servidor responde "invalid login credentials" sobre um
/// e-mail que a pessoa nunca viu nem digitou.
enum AuthIdentifier {
  /// Tela "Continuar com telefone".
  phone,

  /// Google e Apple. Aqui não existe "usuário e senha" para corrigir.
  social,
}

class AuthErrorFormatter {
  /// Traduz um erro de autenticação para uma frase que a pessoa entende.
  ///
  /// [identifier] decide COMO chamar o que ela digitou. Sem valor default de
  /// propósito: cada tela sabe o seu, e um default silencioso foi o que
  /// permitiu "e-mail" vazar para os três caminhos.
  static String format(Object e, {required AuthIdentifier identifier}) {
    final naoExiste = switch (identifier) {
      AuthIdentifier.phone => 'Não existe conta com esse telefone.',
      AuthIdentifier.social => 'Não existe conta ligada a esse login.',
    };
    final credenciaisErradas = switch (identifier) {
      AuthIdentifier.phone => 'Telefone ou senha incorretos.',
      // Em OAuth não há o que a pessoa possa corrigir digitando — mandá-la
      // conferir "usuário e senha" seria pedir uma ação impossível.
      AuthIdentifier.social => 'Não foi possível entrar com essa conta. '
          'Tente de novo.',
    };
    final jaCadastrado = switch (identifier) {
      AuthIdentifier.phone => 'Este telefone já está cadastrado.',
      AuthIdentifier.social => 'Já existe conta com esse login.',
    };
    const generico = 'Ocorreu um problema. Tente novamente.';

    // Senha recusada pela política do servidor. Vem ANTES do switch porque o
    // que importa não é o código (`weak_password`), é o MOTIVO — e o SDK já
    // entrega isso pronto em `.reasons` ('length', 'characters', 'pwned').
    //
    // Sem este ramo, senha fraca cai no `default` e termina em
    // `SafeErrorText.orFallback`: em quase todos os casos a pessoa lê a frase
    // do servidor em inglês num app pt-BR, e no caso de símbolos obrigatórios
    // lê "Ocorreu um problema. Tente novamente." — sem sequer saber que o
    // problema é a senha. Recusar sem dizer o que corrigir é um beco.
    //
    // Casamos pelo TIPO e pelas razões, nunca pela redação da mensagem: a
    // frase do GoTrue muda entre versões, `.reasons` é contrato.
    if (e is AuthWeakPasswordException) {
      final razoes = e.reasons;
      if (razoes.contains('pwned')) {
        return 'Essa senha é muito comum e já apareceu em vazamentos '
            'conhecidos. Escolha outra.';
      }
      if (razoes.contains('characters')) {
        return 'A senha precisa misturar letras e números.';
      }
      if (razoes.contains('length')) {
        // O número sai da MESMA constante que a tela valida. Cravar "8" aqui
        // faria a frase virar mentira no dia em que o mínimo subir no painel
        // — que é exatamente o que este ramo existe para viabilizar.
        return 'A senha está curta demais. Use pelo menos '
            '$kMinPasswordLength caracteres.';
      }
      // Razão nova que o servidor passou a mandar e este código ainda não
      // conhece: dizer o que é o problema já é melhor que a frase genérica.
      return 'Essa senha não atende aos requisitos. Tente uma mais forte.';
    }

    if (e is AuthException) {
      final msg = e.message.toLowerCase();
      bool diz(String trecho) => msg.contains(trecho);

      switch (e.code) {
        case 'invalid_credentials':
        case 'invalid_grant':
          if (diz('user not found') || diz('email not found')) return naoExiste;
          return credenciaisErradas;
        case 'user_not_found':
          return naoExiste;
        case 'unexpected_failure':
          return 'Ocorreu um erro inesperado. Tente novamente em instantes.';
        default:
          if (diz('user not found') || diz('email not found')) return naoExiste;
          if (diz('invalid login credentials')) return credenciaisErradas;
          if (diz('already registered') || diz('already exists')) {
            return jaCadastrado;
          }
      }
      // Antes: `return e.message` — a mensagem CRUA do servidor, em inglês e
      // com jargão, direto na tela. É a classe que `SafeErrorText` existe pra
      // fechar (device-test 24/07 §9 A3: a UI chegou a mostrar a URL do
      // projeto Supabase). O detalhe continua no log, só não na tela.
      return SafeErrorText.orFallback(e.message, generico);
    }

    final errorStr = e.toString().toLowerCase();

    if (errorStr.contains('socketexception') ||
        errorStr.contains('handshakeexception')) {
      return 'Sem conexão com a internet. Verifique seu sinal e tente novamente.';
    }
    if (errorStr.contains('network_error')) {
      return 'Erro de rede. Verifique sua conexão.';
    }
    if (errorStr.contains('invalid login credentials') ||
        errorStr.contains('invalid_credentials')) {
      return credenciaisErradas;
    }
    if (errorStr.contains('user not found') ||
        errorStr.contains('email not found') ||
        errorStr.contains('user_not_found')) {
      return naoExiste;
    }

    return generico;
  }
}
