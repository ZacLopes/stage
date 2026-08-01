/// A regra de senha do Stage — a única.
///
/// Revisão UX 28/07, achado P2-14: a regra era anunciada na tela e não era
/// aplicada em lugar nenhum. Dava para criar conta com "abcdefgh". Regra
/// anunciada e não cumprida é pior que regra nenhuma: ensina algo falso.
///
/// Vive fora da tela por dois motivos concretos:
///
/// 1. **O texto de ajuda e a validação não podem divergir.** Eram duas coisas
///    separadas: o `validator` checava uma regra e o texto embaixo do campo
///    anunciava outra. [kPasswordRuleHint] e [passwordRuleError] agora saem
///    do mesmo lugar — mudar uma sem a outra fica impossível.
/// 2. **A política do servidor precisa espelhar isto.** Quando o Supabase Auth
///    passar a exigir letras+dígitos, é ESTA a regra que ele tem que refletir.
///    Se o servidor ficar mais estrito que o app, a pessoa passa pela tela e
///    leva um erro que a tela não previu.
library;

/// Piso de comprimento. 8 porque é o que a build publicada já exigia — subir
/// disso trancaria quem tem senha de exatamente 8 caracteres, e a doc do
/// Supabase desaconselha menos que 8.
const int kMinPasswordLength = 8;

/// ⚠️ A regra forte (letra + número) vale SÓ PARA CONTA NOVA. Nunca use
/// [passwordRuleError] para decidir se a pessoa pode TENTAR ENTRAR.
///
/// A build publicada exigia apenas comprimento ≥ 8 enquanto a tela já
/// anunciava letra e número (`origin/main:phone_signup_screen.dart:71` vs
/// `:285`). Existem, portanto, contas reais com senha "abcdefgh" ou
/// "12345678". Se a regra forte governar o botão "Continuar", essas pessoas
/// digitam a senha CERTA, o botão fica cinza e inerte, e nenhuma mensagem
/// aparece — não há recuperação de senha no app e o e-mail delas é sintético.
/// É lockout mudo. Foi assim que este arquivo nasceu errado.
///
/// Quem já tem conta entra no passo 1 do fluxo (`signInOrSignUp`), antes de
/// qualquer checagem de força — exatamente como o servidor faz, que valida
/// força no cadastro e não no login.
bool canAttemptSignIn(String password) => password.length >= kMinPasswordLength;

/// Recusa de senha ao CRIAR conta. Tipada para a tela distinguir isso de
/// "credenciais erradas" sem ler a redação da mensagem.
class NewAccountPasswordException implements Exception {
  final String message;
  const NewAccountPasswordException(this.message);
  @override
  String toString() => message;
}

/// O que a tela ANUNCIA embaixo do campo. Deriva da mesma regra que valida.
const String kPasswordRuleHint =
    'Mínimo $kMinPasswordLength caracteres, uma letra e um número';

/// Null quando a senha serve; a frase do que falta quando não serve.
///
/// A ordem das checagens é a ordem em que a pessoa costuma errar, para a
/// mensagem apontar o próximo passo e não o problema mais raro.
String? passwordRuleError(String value) {
  if (value.length < kMinPasswordLength) {
    return 'A senha precisa ter no mínimo $kMinPasswordLength caracteres';
  }
  // Aceita acentuadas: "josé2024" é senha legítima de gente que digita em
  // português, e recusá-la seria uma regra sobre teclado, não sobre força.
  if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(value)) {
    return 'A senha precisa ter pelo menos uma letra';
  }
  if (!RegExp(r'\d').hasMatch(value)) {
    return 'A senha precisa ter pelo menos um número';
  }
  return null;
}
