import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/utils/adaptation_error_copy.dart';
import 'package:career_gamification/services/ai_service.dart'
    show ResumeAdaptationException;

/// F5 — defeitos A1/A2/A3 da §9 do device-test de 24/07.
void main() {
  group('A3 — nada técnico chega à tela', () {
    test('a URL do projeto Supabase NUNCA aparece na mensagem', () {
      // Exatamente o texto que a tela exibiu no device-test.
      const cru =
          'ClientException: Connection closed before full header was received, '
          'uri=https://abcdefgh.supabase.co/functions/v1/adapt-resume-to-job';
      final copy = resolveAdaptationErrorCopy(
        const ResumeAdaptationException('network', cru),
      );
      expect(copy.message.contains('supabase.co'), isFalse);
      expect(copy.message.contains('uri='), isFalse);
      expect(copy.message.contains('ClientException'), isFalse);
      expect(copy.message.contains('http'), isFalse);
    });

    test('detail com stack/exception é descartado no caminho genérico', () {
      final copy = resolveAdaptationErrorCopy(
        const ResumeAdaptationException(
          'algum_codigo_novo',
          'Error: something blew up\nstack: #0 main',
        ),
      );
      expect(copy.message.contains('Error:'), isFalse);
      expect(copy.message.contains('stack'), isFalse);
      expect(copy.message, contains('Tente de novo'));
    });

    test('erro que não é ResumeAdaptationException não vaza toString', () {
      final copy = resolveAdaptationErrorCopy(
        StateError('Bad state: internal https://x.supabase.co'),
      );
      expect(copy.message.contains('supabase.co'), isFalse);
      expect(copy.message.contains('Bad state'), isFalse);
    });

    test('isPresentableDetail reprova os marcadores técnicos', () {
      expect(isPresentableDetail(null), isFalse);
      expect(isPresentableDetail(''), isFalse);
      expect(isPresentableDetail('   '), isFalse);
      expect(isPresentableDetail('https://x.supabase.co'), isFalse);
      expect(isPresentableDetail('uri=abc'), isFalse);
      expect(isPresentableDetail('FooException: bar'), isFalse);
      expect(isPresentableDetail('{"error":"x"}'), isFalse);
      // Texto humano do servidor continua podendo passar.
      expect(
        isPresentableDetail('Você atingiu o limite diário de adaptações.'),
        isTrue,
      );
    });

    test('nenhum código conhecido produz mensagem com jargão', () {
      const codigos = [
        'profile_incomplete',
        'missing_skills',
        'rate_limited',
        'adaptation_rejected',
        'job_not_found',
        'unauthorized',
        'network',
        'timeout',
        'unknown',
      ];
      for (final code in codigos) {
        final copy = resolveAdaptationErrorCopy(
          ResumeAdaptationException(code, 'uri=https://x.supabase.co/y'),
        );
        expect(isPresentableDetail(copy.message), isTrue, reason: code);
        expect(copy.title.trim().isNotEmpty, isTrue, reason: code);
      }
    });
  });

  group('A1 — retry só onde retry resolve', () {
    test('profile_incomplete NÃO oferece retry (determinístico)', () {
      final copy = resolveAdaptationErrorCopy(
        const ResumeAdaptationException('profile_incomplete', 'x'),
      );
      expect(copy.canRetry, isFalse);
      expect(copy.showImportCv, isTrue);
    });

    test('missing_skills NÃO oferece retry (determinístico)', () {
      final copy = resolveAdaptationErrorCopy(
        const ResumeAdaptationException('missing_skills', 'x'),
      );
      expect(copy.canRetry, isFalse);
      expect(copy.showAddSkills, isTrue);
    });

    test('rate_limited NÃO oferece retry', () {
      final copy = resolveAdaptationErrorCopy(
        const ResumeAdaptationException('rate_limited', 'x'),
      );
      expect(copy.canRetry, isFalse);
    });

    test('network e timeout OFERECEM retry (é transitório de verdade)', () {
      for (final code in ['network', 'timeout']) {
        expect(
          resolveAdaptationErrorCopy(ResumeAdaptationException(code, '')).canRetry,
          isTrue,
          reason: code,
        );
      }
    });

    test('adaptation_rejected oferece retry E a saída durável', () {
      // Depois da F6 o gate garante >=3 habilidades, então aqui a falha é
      // variância real do modelo — retry é honesto. Mas a saída que resolve
      // de vez (completar o perfil) fica oferecida junto.
      final copy = resolveAdaptationErrorCopy(
        const ResumeAdaptationException('adaptation_rejected', 'x'),
      );
      expect(copy.canRetry, isTrue);
      expect(copy.showAddSkills, isTrue);
    });
  });

  group('A2 — a mensagem diz o que fazer', () {
    test('adaptation_rejected usa a copy do CLIENT, não o jargão da Edge', () {
      // A Edge manda: "A adaptação não passou na verificação de integridade."
      final copy = resolveAdaptationErrorCopy(
        const ResumeAdaptationException(
          'adaptation_rejected',
          'A adaptação não passou na verificação de integridade. Tente novamente.',
        ),
      );
      expect(copy.message.contains('verificação de integridade'), isFalse);
      expect(copy.message, contains('habilidades'));
      expect(copy.message, contains('perfil'));
    });

    test('missing_skills explica e aponta o caminho', () {
      final copy = resolveAdaptationErrorCopy(
        const ResumeAdaptationException('missing_skills', ''),
      );
      expect(copy.message, contains('habilidades'));
      expect(copy.showAddSkills, isTrue);
      expect(copy.showImportCv, isFalse);
    });

    test('cada erro tem exatamente uma saída principal coerente', () {
      // profile_incomplete → importar CV; missing_skills → habilidades.
      final incompleto = resolveAdaptationErrorCopy(
        const ResumeAdaptationException('profile_incomplete', ''),
      );
      expect(incompleto.showImportCv && !incompleto.showAddSkills, isTrue);
    });
  });
}
