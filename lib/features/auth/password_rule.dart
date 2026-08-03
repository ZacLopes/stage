/// A regra de senha do Stage — a única, e deliberadamente simples.
///
/// **Só comprimento. Sem exigir mistura de letras, números ou símbolos.**
///
/// ## Por que não exigir composição
///
/// O NIST desaconselha regras de composição desde 2017 (SP 800-63B), e o
/// motivo é que elas não fazem o que prometem: `senha123` passa numa regra de
/// letra+número e está em toda lista de vazamento; `meucachorrocomeuosofa`
/// seria recusada e é ordens de magnitude mais forte. A regra empurra as
/// pessoas para o padrão previsível (palavra + `123`), que é o primeiro que
/// um ataque testa.
///
/// O que protege de verdade é o comprimento mais a checagem contra senhas
/// vazadas (HaveIBeenPwned), que vive no painel do Supabase e é a próxima
/// coisa a ligar.
///
/// ## Por que isso também elimina uma classe de defeito
///
/// Esta regra é IGUAL à do servidor (mínimo 8, definido no painel em 31/07) e
/// igual à que a build publicada já exigia. Sem divergência entre app e
/// servidor não existe o caso "a tela aceita e o servidor recusa" — nem o
/// inverso, que chegou a ser um lockout: a regra forte governava o botão
/// "Continuar", e quem tinha senha antiga sem número digitava a senha CERTA e
/// via um botão cinza, sem mensagem nenhuma.
///
/// ## Se um dia subir a régua
///
/// Aperte pelo SERVIDOR (Authentication → Providers → Email), não por aqui. O
/// fluxo [UserViewModel.signInOrSignUp] tenta entrar antes de criar, então
/// quem já tem conta nunca esbarra na regra nova — e a recusa do servidor
/// chega tipada, com o motivo, e é traduzida em `AuthErrorFormatter`.
library;

/// Piso de comprimento. 8 porque é o que a build publicada já exigia e o que o
/// servidor exige hoje — subir disso trancaria quem tem senha de exatamente 8,
/// e a doc do Supabase desaconselha menos que 8.
const int kMinPasswordLength = 8;

/// O que a tela anuncia embaixo do campo. Deriva da mesma constante que valida.
const String kPasswordRuleHint = 'Mínimo $kMinPasswordLength caracteres';

/// Null quando a senha serve; a frase do que falta quando não serve.
String? passwordRuleError(String value) {
  if (value.length < kMinPasswordLength) {
    return 'A senha precisa ter no mínimo $kMinPasswordLength caracteres';
  }
  return null;
}
