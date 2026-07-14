import 'package:career_gamification/features/resume/pdf_service.dart';
import 'package:career_gamification/features/resume/resume_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Harvard ATS — cabeçalho de contato', () {
    test('localiza o telefone em português e preserva Mobile em inglês', () {
      final pt = PdfService.buildResumeHtmlForTest(
        null,
        ResumeData(phone: '(11) 99999-0000', language: 'pt'),
        'harvard_ats',
      );
      final en = PdfService.buildResumeHtmlForTest(
        null,
        ResumeData(phone: '(11) 99999-0000', language: 'en'),
        'harvard_ats',
      );

      expect(pt, contains('Telefone: (11) 99999-0000'));
      expect(pt, isNot(contains('Mobile:')));
      expect(en, contains('Mobile: (11) 99999-0000'));
    });

    test('agrupa email e LinkedIn para evitar link isolado na quebra', () {
      final html = PdfService.buildResumeHtmlForTest(
        null,
        ResumeData(
          fullName: 'Zack Ouri Lopes',
          location: 'São Paulo, SP',
          phone: '(11) 99999-0000',
          email: 'zackourilopes@outlook.com',
          linkedin: 'https://www.linkedin.com/in/zack-ouri-lopes',
          language: 'pt',
        ),
        'harvard_ats',
      );

      expect(
        html,
        contains(
          '.contact-group { display: inline-flex; flex: 0 0 auto; white-space: nowrap; }',
        ),
      );
      expect(
        html,
        contains(
          '<span class="contact-group">'
          '<span class="contact-item">zackourilopes@<wbr>outlook.<wbr>com</span>'
          '<span class="contact-separator"> | </span>'
          '<span class="contact-item">linkedin.com/<wbr>in/<wbr>zack‑ouri‑lopes</span>'
          '</span>',
        ),
      );
    });

    test('separadores existem apenas dentro de grupos sem quebra', () {
      final html = PdfService.buildResumeHtmlForTest(
        null,
        ResumeData(
          location: 'São Paulo, SP',
          phone: '(11) 99999-0000',
          email: 'contato@example.com',
          linkedin: 'linkedin.com/in/pessoa',
        ),
        'harvard_ats',
      );

      expect(
        RegExp(
          r'<span class="contact-separator"> \| </span>',
        ).allMatches(html).length,
        2,
      );
      expect(html, isNot(contains(' | </span></div>')));
    });
  });
}
