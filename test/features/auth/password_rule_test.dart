import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/auth/password_rule.dart';

/// Revisão UX 28/07, achado P2-14 — e a decisão do fundador em 31/07.
///
/// O achado era "a regra é anunciada na tela e não é aplicada em lugar nenhum".
/// A primeira correção aplicou a regra ANUNCIADA (8 + letra + número) — e uma
/// revisão adversarial mostrou que isso trancava, em silêncio, quem já tinha
/// conta com senha só de letras ou só de dígitos.
///
/// A decisão foi tirar a composição em vez de administrá-la:
///
/// - o NIST desaconselha regras de composição desde 2017 (SP 800-63B);
/// - `senha123` passa em letra+número e está em toda lista de vazamento,
///   enquanto uma frase longa sem dígito seria recusada;
/// - com app e servidor exigindo a MESMA coisa, a divergência que produziu o
///   lockout deixa de existir.
///
/// A proteção real virá da checagem contra senhas vazadas, no painel.
void main() {
  group('passwordRuleError — só comprimento', () {
    test('aceita 8 caracteres, seja lá quais forem', () {
      expect(passwordRuleError('senha123'), isNull);
      expect(passwordRuleError('abcdefgh'), isNull);
      expect(passwordRuleError('12345678'), isNull);
      expect(passwordRuleError('        '), isNull);
    });

    test('rejeita curta demais', () {
      expect(passwordRuleError('abc123'), contains('8 caracteres'));
      expect(passwordRuleError(''), contains('8 caracteres'));
      expect(passwordRuleError('1234567'), contains('8 caracteres'));
    });

    test('não exige letra, número, maiúscula nem símbolo', () {
      // Este teste EXISTE para travar a decisão. Se alguém reintroduzir
      // composição aqui, ele cai — e é isso que deve acontecer, porque a
      // conversa precisa ser refeita antes, não depois.
      expect(passwordRuleError('abcdefgh'), isNull);
      expect(passwordRuleError('12345678'), isNull);
      expect(passwordRuleError('meucachorrocomeuosofa'), isNull);
    });

    test('o piso é 8 — subir tranca quem tem exatamente 8', () {
      expect(kMinPasswordLength, 8);
      expect(passwordRuleError('abcdefg1'), isNull);
    });
  });

  group('a regra do app não pode ser mais estrita que a que criou as contas',
      () {
    test('nenhuma senha que já existe pode ser recusada', () {
      // ESTE é o guarda do lockout, e ele é do formato certo: a build
      // publicada exigia só comprimento, então qualquer senha de 8+ pode
      // existir por aí. Se `passwordRuleError` recusar alguma delas, essa
      // pessoa digita a senha CERTA e vê um botão cinza sem mensagem — não há
      // recuperação de senha no app e o e-mail é sintético.
      const senhasQuePodemExistir = [
        'abcdefgh',
        '12345678',
        'senha123',
        'ABCDEFGH',
        'josé2024',
        '!@#\$%^&*',
      ];
      for (final s in senhasQuePodemExistir) {
        expect(passwordRuleError(s), isNull, reason: s);
      }
    });
  });

  group('a tela não pode anunciar uma regra e aplicar outra', () {
    test('o texto de ajuda cita o mesmo mínimo que a validação usa', () {
      expect(kPasswordRuleHint, contains('$kMinPasswordLength'));
      // E não promete mais o que não é exigido — era essa a mentira do P2-14,
      // só que ao contrário: a tela anunciava letra+número e não cobrava.
      expect(kPasswordRuleHint.toLowerCase(), isNot(contains('letra')));
      expect(kPasswordRuleHint.toLowerCase(), isNot(contains('número')));
    });

    test('a tela usa as constantes, não strings próprias', () {
      final src = File('lib/features/auth/phone_signup_screen.dart')
          .readAsStringSync();
      final codigo = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codigo, contains('kPasswordRuleHint'));
      expect(codigo, contains('passwordRuleError'));
      expect(
        codigo.contains("'Mínimo 8 caracteres"),
        isFalse,
        reason: 'o texto voltou a ser um literal solto na tela',
      );
    });

    test('o login continua tentando ENTRAR antes de criar', () {
      // A ordem é o que torna seguro apertar a política no SERVIDOR um dia:
      // quem já tem conta entra antes de qualquer checagem de força. Se a tela
      // voltar a chamar `signUp` direto, apertar o servidor vira lockout.
      final src = File('lib/features/auth/phone_signup_screen.dart')
          .readAsStringSync();
      expect(src, contains('signInOrSignUp('));
      expect(
        src.contains('vm.signUp('),
        isFalse,
        reason: 'a tela voltou a chamar signUp direto, pulando o login',
      );
    });
  });
}
