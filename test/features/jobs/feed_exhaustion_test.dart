import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/jobs/utils/feed_exhaustion.dart';

/// FASE 2 fixes (R3): decisão A/B do estado de exaustão.
/// Bug 15/06: depois de swipar todas as relevantes, o app mostrava "filtros
/// muito restritivos" (B) em vez de "você viu as relevantes" (A).
void main() {
  group('feedFiltersTooRestrictive', () {
    test('esgotou as relevantes (havia matches, todos swipados) → A (false)', () {
      // 218 ativas não-swipadas (de outras áreas), mas 12 batiam com os
      // filtros no catálogo (agora swipadas). NÃO é filtro restritivo.
      expect(
        feedFiltersTooRestrictive(
          prefsActive: true,
          totalAvailable: 218,
          totalMatchingCatalog: 12,
        ),
        isFalse,
      );
    });

    test('filtros zeram o catálogo inteiro → B (true)', () {
      expect(
        feedFiltersTooRestrictive(
          prefsActive: true,
          totalAvailable: 300,
          totalMatchingCatalog: 0,
        ),
        isTrue,
      );
    });

    test('sem prefs ativas → nunca B', () {
      expect(
        feedFiltersTooRestrictive(
          prefsActive: false,
          totalAvailable: 300,
          totalMatchingCatalog: 0,
        ),
        isFalse,
      );
    });

    test('desconhecido (-1, caminho RPC) → degrada pra A (false)', () {
      expect(
        feedFiltersTooRestrictive(
          prefsActive: true,
          totalAvailable: 218,
          totalMatchingCatalog: -1,
        ),
        isFalse,
      );
    });

    test('catálogo vazio (0 ativas) → não afirma B', () {
      expect(
        feedFiltersTooRestrictive(
          prefsActive: true,
          totalAvailable: 0,
          totalMatchingCatalog: 0,
        ),
        isFalse,
      );
    });
  });
}
