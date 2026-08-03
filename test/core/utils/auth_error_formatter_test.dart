import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:career_gamification/core/utils/auth_error_formatter.dart';

/// Achado do device-test de 31/07: errar a senha na tela "Continuar com
/// telefone", depois de digitar (11) 98765-0143, mostrava
/// **"E-mail ou senha incorretos."**
///
/// A origem é técnica e vaza exatamente aí: o login por telefone grava um
/// e-mail SINTÉTICO (`phone_55…@stage.app`) porque o Twilio não está
/// configurado, então o servidor responde sobre um e-mail que a pessoa nunca
/// viu. E o app **não tem login por e-mail** — são Google, Apple e telefone —,
/// então a frase estava errada nos TRÊS caminhos, não só no do telefone.
void main() {
  AuthException credenciaisInvalidas() => const AuthException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );

  AuthException usuarioNaoEncontrado() => const AuthException(
        'User not found',
        statusCode: '400',
        code: 'user_not_found',
      );

  group('telefone — nomeia o que a pessoa DIGITOU', () {
    test('senha errada fala de TELEFONE, nunca de e-mail', () {
      final msg = AuthErrorFormatter.format(
        credenciaisInvalidas(),
        identifier: AuthIdentifier.phone,
      );
      expect(msg, 'Telefone ou senha incorretos.');
      expect(msg.toLowerCase(), isNot(contains('mail')));
    });

    test('conta inexistente fala de telefone', () {
      final msg = AuthErrorFormatter.format(
        usuarioNaoEncontrado(),
        identifier: AuthIdentifier.phone,
      );
      expect(msg, contains('telefone'));
      expect(msg.toLowerCase(), isNot(contains('mail')));
    });

    test('já cadastrado fala de telefone', () {
      final msg = AuthErrorFormatter.format(
        const AuthException('User already registered', statusCode: '400'),
        identifier: AuthIdentifier.phone,
      );
      expect(msg, 'Este telefone já está cadastrado.');
    });
  });

  group('social (Google/Apple) — não manda conferir o que não existe', () {
    test('não pede para conferir usuário e senha', () {
      // Em OAuth não há campo que a pessoa possa corrigir digitando. Mandá-la
      // "verificar seus dados" é pedir uma ação impossível.
      final msg = AuthErrorFormatter.format(
        credenciaisInvalidas(),
        identifier: AuthIdentifier.social,
      );
      expect(msg.toLowerCase(), isNot(contains('mail')));
      expect(msg.toLowerCase(), isNot(contains('senha')));
    });
  });

  group('senha fraca — o motivo, não o código', () {
    AuthWeakPasswordException fraca(List<String> reasons) =>
        AuthWeakPasswordException(
          // A frase do servidor vem em inglês e muda entre versões do GoTrue.
          // O app NÃO pode depender dela — por isso casamos pelo tipo e por
          // `.reasons`, que é contrato do SDK.
          message: 'Password should contain at least one character of each: '
              'abcdefghijklmnopqrstuvwxyz, 0123456789.',
          statusCode: '422',
          reasons: reasons,
        );

    test('curta demais → diz o tamanho', () {
      final msg = AuthErrorFormatter.format(
        fraca(['length']),
        identifier: AuthIdentifier.phone,
      );
      expect(msg, contains('8 caracteres'));
    });

    test('sem letra ou sem número → diz o que misturar', () {
      final msg = AuthErrorFormatter.format(
        fraca(['characters']),
        identifier: AuthIdentifier.phone,
      );
      expect(msg, contains('letras e números'));
    });

    test('senha vazada → explica por que, sem culpar a pessoa', () {
      final msg = AuthErrorFormatter.format(
        fraca(['pwned']),
        identifier: AuthIdentifier.phone,
      );
      expect(msg, contains('vazamentos'));
    });

    test('razão desconhecida ainda diz que o problema É a senha', () {
      // Se o servidor mandar uma razão nova, a saída não pode virar
      // "Ocorreu um problema" — a pessoa precisa saber o que corrigir.
      final msg = AuthErrorFormatter.format(
        fraca(['algo_que_ainda_nao_existe']),
        identifier: AuthIdentifier.phone,
      );
      expect(msg.toLowerCase(), contains('senha'));
    });

    test('NUNCA devolve a frase do servidor nem a genérica', () {
      // Antes deste ramo, senha fraca caía no `default` → SafeErrorText.
      // A mensagem com os símbolos permitidos contém `{` e `}`, que o filtro
      // trata como texto técnico: a pessoa lia "Ocorreu um problema. Tente
      // novamente." sem saber que o problema era a senha.
      for (final r in ['length', 'characters', 'pwned']) {
        final msg = AuthErrorFormatter.format(
          fraca([r]),
          identifier: AuthIdentifier.phone,
        );
        expect(msg, isNot(contains('Password')));
        expect(msg, isNot('Ocorreu um problema. Tente novamente.'));
      }
    });

    test('vale igual no login social', () {
      final msg = AuthErrorFormatter.format(
        fraca(['pwned']),
        identifier: AuthIdentifier.social,
      );
      expect(msg, contains('vazamentos'));
    });
  });

  group('nenhum texto técnico chega à tela', () {
    test('mensagem crua do servidor com URL vira frase genérica', () {
      // Antes o `default` terminava em `return e.message` — inglês e jargão
      // direto na UI. O device-test de 24/07 (§9 A3) chegou a ver a URL do
      // projeto Supabase na tela.
      final msg = AuthErrorFormatter.format(
        const AuthException(
          'ClientException: Connection closed uri=https://abc.supabase.co/auth/v1/token',
          statusCode: '500',
          code: 'some_new_code_da_lib',
        ),
        identifier: AuthIdentifier.phone,
      );
      expect(msg, 'Ocorreu um problema. Tente novamente.');
      expect(msg, isNot(contains('supabase')));
      expect(msg, isNot(contains('http')));
    });

    test('erro de rede continua sendo dito com clareza', () {
      final msg = AuthErrorFormatter.format(
        Exception('SocketException: Failed host lookup'),
        identifier: AuthIdentifier.phone,
      );
      expect(msg, contains('Sem conexão'));
    });
  });

  test('o literal "E-mail ou senha" não existe mais em lib/', () {
    // Guarda da CLASSE, não da instância: a lição desta revisão é que corrigir
    // a tela da foto deixa as outras vivas.
    final ofensas = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final linhas = f.readAsLinesSync();
      for (var i = 0; i < linhas.length; i++) {
        final l = linhas[i];
        if (l.trimLeft().startsWith('//')) continue;
        if (l.contains('E-mail ou senha') || l.contains('Email ou senha')) {
          ofensas.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(ofensas, isEmpty,
        reason: 'o app não tem login por e-mail:\n${ofensas.join('\n')}');
  });
}
