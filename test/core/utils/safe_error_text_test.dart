import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/core/utils/safe_error_text.dart';

/// Defeito A3 do device-test (24/07), reaberto pelo code-review (27/07): a
/// primeira correção fechou só o caminho da adaptação; o export do Currículo
/// geral continuava interpolando `$e` num SnackBar. A política agora é única.
void main() {
  group('rejeita texto técnico', () {
    test('a URL/host do projeto Supabase nunca passa', () {
      const cru =
          'ClientException: Connection closed before full header was received, '
          'uri=https://abcdefgh.supabase.co/functions/v1/adapt-resume-to-job';
      expect(SafeErrorText.isPresentable(cru), isFalse);
      final safe = SafeErrorText.orFallback(cru, 'Tente de novo.');
      expect(safe, 'Tente de novo.');
      expect(safe.contains('supabase.co'), isFalse);
      expect(safe.contains('uri='), isFalse);
    });

    test('nome de exceção, stack e JSON são reprovados', () {
      for (final t in [
        'FooException: bar',
        'Error: algo explodiu',
        'stack: #0 main',
        '{"error":"x"}',
        'https://exemplo.com',
        'uri=abc',
      ]) {
        expect(SafeErrorText.isPresentable(t), isFalse, reason: t);
      }
    });

    test('vazio e só-espaços são reprovados', () {
      expect(SafeErrorText.isPresentable(null), isFalse);
      expect(SafeErrorText.isPresentable(''), isFalse);
      expect(SafeErrorText.isPresentable('   '), isFalse);
    });
  });

  group('deixa passar texto humano', () {
    test('mensagem em pt-BR sem jargão passa', () {
      const msg = 'Você atingiu o limite diário de adaptações. Tente amanhã.';
      expect(SafeErrorText.isPresentable(msg), isTrue);
      expect(SafeErrorText.orFallback(msg, 'fallback'), msg);
    });

    test('orFallback devolve o fallback para erro nulo', () {
      expect(SafeErrorText.orFallback(null, 'fallback'), 'fallback');
    });

    test('orFallback aceita Object e usa toString', () {
      final err = StateError('https://x.supabase.co vazou');
      expect(SafeErrorText.orFallback(err, 'fallback'), 'fallback');
    });

    test('faz trim do texto aprovado', () {
      expect(SafeErrorText.orFallback('  ok  ', 'fallback'), 'ok');
    });
  });
}
