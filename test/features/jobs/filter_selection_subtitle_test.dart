import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/utils/filter_selection_subtitle.dart';
import 'package:career_gamification/features/jobs/utils/match_band.dart';

/// Revisão UX 28/07 — os dois achados de vocabulário inconsistente que
/// sobreviveram à primeira rodada.
void main() {
  group('P3-39 · um formato só para as quatro seções de filtro', () {
    test('com escolha feita, sempre "N de M"', () {
      expect(
        filterSelectionSubtitle(selected: 2, max: 5, emptyLabel: 'x'),
        '2 de 5',
      );
      expect(
        filterSelectionSubtitle(selected: 1, max: 3, emptyLabel: 'x'),
        '1 de 3',
      );
      // O singular não muda o formato: era daqui que saía o
      // "3 selecionado(s)" convivendo com "2/5 selecionadas".
      expect(
        filterSelectionSubtitle(selected: 3, max: 3, emptyLabel: 'x'),
        '3 de 3',
      );
    });

    test('zero não é "0 de 5" — é a frase de estado vazio', () {
      // "Não estou filtrando nada" é informação diferente (e mais útil) de
      // "escolhi zero de cinco".
      expect(
        filterSelectionSubtitle(
          selected: 0,
          max: 5,
          emptyLabel: 'Todas as áreas',
        ),
        'Todas as áreas',
      );
    });

    test('nunca imprime "selecionado(s)" — o formato antigo morreu', () {
      for (var i = 0; i <= 5; i++) {
        final s = filterSelectionSubtitle(
          selected: i,
          max: 5,
          emptyLabel: 'Todos os tipos',
        );
        expect(s.contains('selecionad'), isFalse, reason: 'selected=$i → $s');
        expect(s.contains('/'), isFalse, reason: 'selected=$i → $s');
      }
    });
  });

  group('P2-13 · card e detalhe falam do mesmo match', () {
    test('o rótulo do anel concorda com "match" (masculino)', () {
      // O anel escreve o rótulo EM CIMA da palavra "match": lia "Alta match".
      expect(matchBandFor(80).label, 'Alto');
      expect(matchBandFor(50).label, 'Médio');
      expect(matchBandFor(10).label, 'Baixo');
    });

    test('o detalhe usa o adjetivo da BANDA, não um vocabulário paralelo', () {
      // Era aqui que 75 virava "Bom match" enquanto o card dizia "Alta".
      expect(matchDetailCopy(75).label, 'Match alto');
      expect(matchBandFor(75), MatchBand.alta);

      expect(matchDetailCopy(50).label, 'Match médio');
      expect(matchDetailCopy(10).label, 'Match baixo');
    });

    test('85+ é superlativo da banda alta, não uma quinta categoria', () {
      expect(matchDetailCopy(90).label, 'Match excelente');
      // O card continua dizendo "Alto" para 90, e agora os dois encaixam:
      // "excelente" lê como um caso forte de alto, não como outra escala.
      expect(matchBandFor(90), MatchBand.alta);
    });

    test('os limiares do detalhe SÃO os da banda, nas bordas', () {
      expect(matchDetailCopy(70).label, 'Match alto');
      expect(matchDetailCopy(69).label, 'Match médio');
      expect(matchDetailCopy(40).label, 'Match médio');
      expect(matchDetailCopy(39).label, 'Match baixo');
      expect(matchDetailCopy(85).label, 'Match excelente');
      expect(matchDetailCopy(84).label, 'Match alto');
    });

    test('toda banda tem descrição própria e não-vazia', () {
      for (final score in [0, 39, 40, 69, 70, 84, 85, 100]) {
        expect(matchDetailCopy(score).description, isNotEmpty);
      }
    });
  });
}
