import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/utils/holdout_gate.dart';
import 'package:career_gamification/features/jobs/utils/match_band.dart';
import 'package:career_gamification/features/jobs/utils/match_score.dart';

/// FASE 2 (T2.4, R3): limiares das bandas + gate de elegibilidade do
/// holdout (low → flag NÃO é avaliada).
void main() {
  group('matchBandFor — limiares do plano-mãe F2', () {
    test('Alta ≥70', () {
      expect(matchBandFor(70), MatchBand.alta);
      expect(matchBandFor(100), MatchBand.alta);
    });
    test('Média 40-69', () {
      expect(matchBandFor(40), MatchBand.media);
      expect(matchBandFor(69), MatchBand.media);
    });
    test('Baixa <40', () {
      expect(matchBandFor(0), MatchBand.baixa);
      expect(matchBandFor(39), MatchBand.baixa);
    });
    test('labels pt-BR', () {
      expect(MatchBand.alta.label, 'Alta');
      expect(MatchBand.media.label, 'Média');
      expect(MatchBand.baixa.label, 'Baixa');
    });
  });

  group('resolveHoldoutVariant — gate de elegibilidade (§5/D3)', () {
    test('confidence low → NÃO avalia a flag e retorna null (não-elegível)',
        () async {
      var flagCalls = 0;
      final variant = await resolveHoldoutVariant(
        confidence: MatchConfidence.low,
        getFlag: (_) async {
          flagCalls++;
          return 'hidden';
        },
      );
      expect(variant, isNull);
      expect(flagCalls, 0, reason: 'low não pode contaminar o experimento');
    });

    test('medium/high → avalia a flag e retorna a variante', () async {
      for (final conf in [MatchConfidence.medium, MatchConfidence.high]) {
        final variant = await resolveHoldoutVariant(
          confidence: conf,
          getFlag: (key) async {
            expect(key, kMatchVisibilityFlag);
            return 'hidden';
          },
        );
        expect(variant, 'hidden');
      }
    });

    test('flag null/erro → controle (failure-safe = percent)', () async {
      expect(
        await resolveHoldoutVariant(
          confidence: MatchConfidence.high,
          getFlag: (_) async => null,
        ),
        'percent',
      );
      expect(
        await resolveHoldoutVariant(
          confidence: MatchConfidence.high,
          getFlag: (_) async => throw Exception('rede'),
        ),
        'percent',
      );
    });

    test('scoreVisibleFor: só hidden esconde', () {
      expect(scoreVisibleFor('hidden'), isFalse);
      expect(scoreVisibleFor('percent'), isTrue);
      expect(scoreVisibleFor(null), isTrue);
    });
  });
}
