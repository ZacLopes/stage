import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/utils/job_content_sanitizer.dart';

/// Revisão UX 28/07, achado P2-17 — o que sobrou depois do marcador duplo.
void main() {
  group('isClosingPleasantry · despedida não é requisito', () {
    test('pega a frase literal do relatório', () {
      expect(
        isClosingPleasantry('Desejamos uma ótima seleção para você!'),
        isTrue,
      );
      expect(
        isClosingPleasantry(
          'Lembre-se que também podemos te fazer uma ligação',
        ),
        isTrue,
      );
    });

    test('pega as outras fórmulas de encerramento comuns do ATS', () {
      for (final s in [
        'Boa sorte!',
        'Boa seleção a todos',
        'Sucesso na sua jornada',
        'Agradecemos o seu interesse',
        'Obrigado por se candidatar',
        'Conte conosco',
        'Esperamos te conhecer em breve',
        'Aguardamos sua candidatura',
        'Até breve!',
      ]) {
        expect(isClosingPleasantry(s), isTrue, reason: s);
      }
    });

    test('NÃO derruba requisito de verdade — o risco da regra', () {
      // Derrubar um requisito real é pior que deixar passar uma despedida.
      // Por isso o casamento é por fórmula, não por palavra: "boa" e
      // "sucesso" aparecem em requisito legítimo.
      for (final s in [
        'Boa comunicação escrita e verbal',
        'Boa capacidade analítica',
        'Histórico de sucesso em projetos acadêmicos',
        'Cursando a partir do 5º semestre',
        'Inglês intermediário',
        'Desejável conhecimento em Excel',
        'Desejável Python',
      ]) {
        expect(isClosingPleasantry(s), isFalse, reason: s);
      }
    });

    test('só casa no COMEÇO da linha', () {
      // "Vamos avaliar seu perfil e desejamos sorte" é uma frase que começa
      // com conteúdo — não é o item de despedida que a lista empilha no fim.
      expect(
        isClosingPleasantry('Vamos avaliar seu perfil e desejamos sorte'),
        isFalse,
      );
    });

    test('linha vazia não é despedida (o filtro de vazio é outro)', () {
      expect(isClosingPleasantry(''), isFalse);
      expect(isClosingPleasantry('   '), isFalse);
    });
  });

  group('collapseEmptyHtmlBlocks · o vão de centenas de pixels', () {
    test('mata o <p> que só tem &nbsp; — o caso real do editor do ATS', () {
      expect(
        collapseEmptyHtmlBlocks('<p>Requisitos</p><p>&nbsp;</p><p>Python</p>'),
        '<p>Requisitos</p><p>Python</p>',
      );
    });

    test('mata as variantes que a regra antiga (<p></p>) não pegava', () {
      for (final vazio in [
        '<p><span>&nbsp;</span></p>',
        '<p><br></p>',
        '<p><br/></p>',
        '<p>   </p>',
        '<p><strong>&nbsp;</strong></p>',
        '<div>&nbsp;</div>',
      ]) {
        expect(
          collapseEmptyHtmlBlocks('<p>A</p>$vazio<p>B</p>'),
          '<p>A</p><p>B</p>',
          reason: vazio,
        );
      }
    });

    test('seis parágrafos vazios seguidos somem todos', () {
      final html = '<p>A</p>${'<p>&nbsp;</p>' * 6}<p>B</p>';
      expect(collapseEmptyHtmlBlocks(html), '<p>A</p><p>B</p>');
    });

    test('<br> em série vira UM só', () {
      expect(
        collapseEmptyHtmlBlocks('<p>A<br><br><br>B</p>'),
        '<p>A<br>B</p>',
      );
    });

    test('<br> colado na borda do parágrafo some (a margem já separa)', () {
      expect(collapseEmptyHtmlBlocks('<p><br>Texto</p>'), '<p>Texto</p>');
      expect(collapseEmptyHtmlBlocks('<p>Texto<br></p>'), '<p>Texto</p>');
    });

    test('NÃO come conteúdo', () {
      const html = '<p>Cursando a partir do 5º semestre</p>'
          '<ul><li>Excel</li><li>Inglês</li></ul>';
      expect(collapseEmptyHtmlBlocks(html), html);
    });

    test('um <br> isolado no meio do texto continua quebrando linha', () {
      expect(
        collapseEmptyHtmlBlocks('<p>Linha 1<br>Linha 2</p>'),
        '<p>Linha 1<br>Linha 2</p>',
      );
    });

    test('vazio e sem-HTML passam intactos', () {
      expect(collapseEmptyHtmlBlocks(''), '');
      expect(collapseEmptyHtmlBlocks('texto puro'), 'texto puro');
    });
  });
}
