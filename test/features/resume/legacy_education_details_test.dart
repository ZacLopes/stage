import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/resume/data/legacy_education_details.dart';

/// Revisão UX 28/07, achado P1-11 — "Major"/"Minor" em currículo português.
///
/// O mapper canônico já escrevia em PT. O que sobrava era o caminho legado do
/// `ResumeViewModel`, que repassa o `detalhes` cru do conteúdo em cache — e
/// esse conteúdo veio de um prompt que pedia "Major/Minor" mesmo no ramo PT.
/// Como o cache é local e não expira, a troca de template re-emitia o inglês
/// indefinidamente.
void main() {
  String pt(String s) => sanitizeLegacyEducationDetails(s, language: 'pt');

  group('troca o RÓTULO, não o conteúdo', () {
    test('Major in X vira Ênfase em X', () {
      expect(pt('Major in Finance'), 'Ênfase em Finance');
    });

    test('Minor in X vira Formação complementar em X', () {
      expect(
        pt('Minor in Entrepreneurship'),
        'Formação complementar em Entrepreneurship',
      );
    });

    test('a linha real do prompt, com os dois na mesma frase', () {
      // Exemplo literal de generate-resume/index.ts:434.
      expect(
        pt('5th semester — Major in Finance, Minor in Entrepreneurship'),
        '5th semester — Ênfase em Finance, '
            'Formação complementar em Entrepreneurship',
      );
    });

    test('aceita a forma com dois-pontos e o plural', () {
      expect(pt('Major: Finance'), 'Ênfase em Finance');
      expect(pt('Minors: Design'), 'Formação complementar em Design');
    });

    test('NÃO traduz o nome da ênfase', () {
      // Traduzir "Finance" para "Finanças" seria inventar dado sobre a
      // formação de alguém. O achado é sobre o rótulo artificial, só.
      expect(pt('Major in Business Administration'),
          'Ênfase em Business Administration');
    });
  });

  group('não mexe no que não é o defeito', () {
    test('detalhe já em português passa intacto', () {
      const ja = 'Ênfase em Finanças · Formação complementar em Design';
      expect(pt(ja), ja);
    });

    test('semestre e turno passam intactos', () {
      const s = 'Cursando 3º semestre, turno da manhã';
      expect(pt(s), s);
    });

    test('vazio continua vazio', () {
      expect(pt(''), '');
    });

    test('palavra que só CONTÉM "major" não casa', () {
      // \b evita estragar "Majorada", "Minoria" e afins.
      expect(pt('Minoria em dados'), 'Minoria em dados');
      expect(pt('Majoritariamente remoto'), 'Majoritariamente remoto');
    });
  });

  test('em currículo EN o rótulo inglês está CERTO e fica', () {
    const en = '5th semester — Major in Finance, Minor in Entrepreneurship';
    expect(sanitizeLegacyEducationDetails(en, language: 'en'), en);
  });
}
