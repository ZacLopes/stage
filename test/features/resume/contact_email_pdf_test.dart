import 'package:career_gamification/features/resume/pdf_service.dart';
import 'package:career_gamification/features/resume/resume_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

const _templates = <String>[
  'harvard_ats',
  'jakes_resume',
  'forte_foundation',
  'one_page_compact',
  'cobalt_modern',
];

void main() {
  group('e-mail público nos templates de currículo', () {
    for (final unsafeEmail in [
      'alias@privaterelay.appleid.com',
      'alias@private.icloud.com',
      'phone_5511987654321@stage.app',
      'email-invalido',
    ]) {
      test('suprime $unsafeEmail em todos os templates', () {
        final resume = ResumeData(
          fullName: 'Pessoa Candidata',
          email: unsafeEmail,
        );

        for (final template in _templates) {
          final html = PdfService.buildResumeHtmlForTest(
            null,
            resume,
            template,
          );
          final visibleText = html.replaceAll('<wbr>', '');
          expect(
            visibleText,
            isNot(contains(unsafeEmail)),
            reason: '$template publicou um e-mail reservado ou inválido',
          );
        }
      });
    }

    test('preserva e normaliza um contato comum em todos os templates', () {
      final resume = ResumeData(
        fullName: 'Pessoa Candidata',
        email: '  Profissional@Example.COM ',
      );

      for (final template in _templates) {
        final html = PdfService.buildResumeHtmlForTest(null, resume, template);
        final visibleText = html.replaceAll('<wbr>', '');
        expect(
          visibleText,
          contains('profissional@example.com'),
          reason: '$template removeu um contato público válido',
        );
      }
    });

    test('preserva um endereço iCloud comum', () {
      final resume = ResumeData(
        fullName: 'Pessoa Candidata',
        email: 'pessoa@icloud.com',
      );

      for (final template in _templates) {
        final html = PdfService.buildResumeHtmlForTest(null, resume, template);
        final visibleText = html.replaceAll('<wbr>', '');
        expect(visibleText, contains('pessoa@icloud.com'));
      }
    });
  });
}
