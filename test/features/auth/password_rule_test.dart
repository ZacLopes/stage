import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/auth/password_rule.dart';

/// Revisão UX 28/07, achado P2-14: a regra de senha era ANUNCIADA na tela e
/// não era aplicada em lugar nenhum — nem no cliente, nem no servidor. Dava
/// para criar conta com "abcdefgh". Regra anunciada e não cumprida é pior que
/// regra nenhuma: ensina algo falso.
///
/// Não existia UM teste de senha em todo o repositório antes deste arquivo.
void main() {
  group('passwordRuleError', () {
    test('aceita o que a tela promete', () {
      expect(passwordRuleError('senha123'), isNull);
      expect(passwordRuleError('abcdefg1'), isNull);
    });

    test('rejeita curta demais', () {
      expect(passwordRuleError('abc123'), contains('8 caracteres'));
      expect(passwordRuleError(''), contains('8 caracteres'));
    });

    test('rejeita só letras — era o caso do achado', () {
      // "abcdefgh" criava conta antes desta regra existir.
      expect(passwordRuleError('abcdefgh'), contains('número'));
    });

    test('rejeita só números', () {
      // "12345678" ainda cria conta na build publicada hoje.
      expect(passwordRuleError('12345678'), contains('letra'));
    });

    test('aceita letra acentuada como letra', () {
      // Recusar "josé2024" seria uma regra sobre teclado, não sobre força.
      expect(passwordRuleError('josé2024'), isNull);
      expect(passwordRuleError('çãoçao12'), isNull);
    });

    test('não exige maiúscula nem símbolo', () {
      // A regra do app tem que ser IGUAL à que o servidor vai aplicar
      // ('letras e dígitos'). Se o app for mais frouxo, a pessoa passa aqui e
      // é recusada lá; se for mais estrito, ela é barrada por uma regra que o
      // servidor nem tem.
      expect(passwordRuleError('senha123'), isNull);
      expect(passwordRuleError('SENHA123'), isNull);
    });

    test('o piso é 8 — não subir sem migrar quem já tem senha', () {
      expect(kMinPasswordLength, 8);
      expect(passwordRuleError('abcdefg1'), isNull); // exatamente 8
    });
  });

  group('a tela não pode anunciar uma regra e aplicar outra', () {
    test('o texto de ajuda cita o mesmo mínimo que a validação usa', () {
      expect(kPasswordRuleHint, contains('$kMinPasswordLength'));
      expect(kPasswordRuleHint, contains('letra'));
      expect(kPasswordRuleHint, contains('número'));
    });

    test('a tela usa a constante, não uma string própria', () {
      // Eram duas strings independentes: o validador checava uma coisa e o
      // texto embaixo do campo anunciava outra. Este assert impede a volta.
      final src = File('lib/features/auth/phone_signup_screen.dart')
          .readAsStringSync();
      final codigo = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codigo, contains('kPasswordRuleHint'));
      expect(
        codigo.contains("'Mínimo 8 caracteres"),
        isFalse,
        reason: 'o texto voltou a ser um literal solto na tela',
      );
    });
  });
}
