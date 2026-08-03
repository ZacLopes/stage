import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:career_gamification/features/auth/auth_failure_code.dart';

/// `auth_signup_failed` estava no catálogo de eventos desde sempre e **nunca
/// era emitido** — catálogo morto, que a R7 proíbe. Consequência prática: se o
/// cadastro começasse a falhar, isso não apareceria em painel nenhum, só na
/// queda de contas criadas semanas depois.
///
/// O gatilho concreto é a política de senha do servidor: apertá-la sem este
/// evento é mexer no funil de entrada às cegas.
void main() {
  group('authFailureCode — rótulo fechado, nunca a mensagem do servidor', () {
    AuthWeakPasswordException fraca(List<String> reasons) =>
        AuthWeakPasswordException(
          message: 'Password should contain at least one character of each: '
              'abcdefghijklmnopqrstuvwxyz, 0123456789.',
          statusCode: '422',
          reasons: reasons,
        );

    test('senha fraca vem com o MOTIVO — é o que responde "qual aperto"', () {
      expect(authFailureCode(fraca(['length'])), 'weak_password_length');
      expect(authFailureCode(fraca(['characters'])), 'weak_password_characters');
      expect(authFailureCode(fraca(['pwned'])), 'weak_password_pwned');
    });

    test('razão desconhecida ainda diz que foi senha fraca', () {
      expect(authFailureCode(fraca(['nova_razao'])), 'weak_password');
    });

    test('AuthWeakPasswordException vem ANTES de AuthException', () {
      // É subclasse: se a ordem inverter, toda senha fraca vira 'auth_error'
      // e a métrica perde justamente o que ela existe para medir.
      final e = fraca(['pwned']);
      expect(e, isA<AuthException>());
      expect(authFailureCode(e), startsWith('weak_password'));
    });

    test('os casos de credencial e conta', () {
      expect(
        authFailureCode(const AuthException('User already registered',
            statusCode: '400')),
        'already_registered',
      );
      expect(
        authFailureCode(const AuthException('Invalid login credentials',
            statusCode: '400', code: 'invalid_credentials')),
        'invalid_credentials',
      );
      expect(
        authFailureCode(
            const AuthException('User not found', statusCode: '400')),
        'user_not_found',
      );
    });

    test('rate limit é reconhecido pelo status, não só pela frase', () {
      expect(
        authFailureCode(const AuthException('too many requests',
            statusCode: '429')),
        'rate_limited',
      );
    });

    test('rede e timeout', () {
      expect(
        authFailureCode(Exception('SocketException: Failed host lookup')),
        'network',
      );
      expect(authFailureCode(Exception('TimeoutException after 8s')), 'timeout');
      expect(authFailureCode(Exception('coisa qualquer')), 'unknown');
    });

    test('NUNCA devolve a mensagem do servidor', () {
      // A frase muda entre versões do GoTrue (série temporal quebra sem
      // aviso), tem cardinalidade alta demais para agrupar, e pode carregar
      // dado de quem tentou entrar.
      final entradas = <Object>[
        fraca(['length']),
        const AuthException('Password should be at least 10 characters.',
            statusCode: '422'),
        Exception('ClientException: Connection closed uri=https://x.supabase.co'),
      ];
      for (final e in entradas) {
        final code = authFailureCode(e);
        expect(code, isNot(contains(' ')), reason: code);
        expect(code, isNot(contains('http')), reason: code);
        expect(code.length, lessThan(40), reason: code);
      }
    });
  });

  group('o evento tem emissor de verdade', () {
    test('a constante saiu do catálogo morto', () {
      // R7: evento novo = constante + emissor no MESMO PR. Este teste existe
      // porque a constante ficou anos sem emissor e ninguém notou.
      final service =
          File('lib/services/analytics_service.dart').readAsStringSync();
      expect(service, contains('evAuthSignupFailed'));
      expect(service, contains('Future<void> authSignupFailed('));
    });

    test('os três métodos de entrada emitem falha', () {
      final vm =
          File('lib/features/auth/user_viewmodel.dart').readAsStringSync();
      expect(vm, contains("method: 'phone'"));
      expect(vm, contains("method: 'apple'"));
      // Google entra por `signInWithOAuth`, que usa `provider.name`.
      expect(vm, contains('method: provider.name'));
    });

    test('o signUp de dentro do fluxo NÃO usa o fallback de login', () {
      // Bug pego ao vivo em 01/08, invisível para todo teste de código-fonte
      // anterior: o fallback histórico dentro de `signUp` intercepta
      // "já cadastrado", tenta entrar, falha e relança o erro do LOGIN. Com
      // isso, `signInOrSignUp` nunca via "já cadastrado" e classificava senha
      // errada em conta existente como falha de CADASTRO —
      // `auth_signup_failed / invalid_credentials` no PostHog, exatamente a
      // poluição de métrica que o evento separado existe para evitar.
      final vm =
          File('lib/features/auth/user_viewmodel.dart').readAsStringSync();
      final inicio = vm.indexOf('Future<void> signInOrSignUp(');
      expect(inicio, greaterThan(-1));
      final corpo = vm.substring(inicio, vm.indexOf('\n  // Sign in existing user', inicio));
      expect(
        corpo,
        contains('fallbackToSignIn: false'),
        reason: 'o fluxo voltou a usar o fallback e vai mascarar a causa',
      );
    });

    test('cadastro e login são eventos SEPARADOS', () {
      // Na tela de telefone, que é login e cadastro na mesma porta, misturar
      // os dois tornaria a métrica de cadastro ilegível: toda senha errada
      // contaria como falha de signup.
      final vm =
          File('lib/features/auth/user_viewmodel.dart').readAsStringSync();
      expect(vm, contains('authLoginFailed('));
      expect(vm, contains('authSignupFailed('));
    });
  });
}
