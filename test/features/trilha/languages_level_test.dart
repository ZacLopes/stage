// Fase 7 · gate-list +10 (Tarefa 3): a trilha não marca idiomas como "pronto"
// no picker (antes dos níveis). A lacuna só fecha quando TODOS têm nível, e na
// volta a trilha pergunta SÓ o nível que faltou — sem re-rodar o picker.
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/profile/application/profile_gaps.dart';
import 'package:career_gamification/features/trilha/application/conversation_plan.dart';

ProfileGaps _gaps({
  required int languagesCount,
  required int languagesMissingLevel,
}) =>
    analyzeProfileGaps(
      hasArea: true,
      hasWorkMode: true,
      hasJobType: true,
      hasCity: true,
      hasEducationStatus: true,
      skillsCount: 3,
      experienceCount: 1,
      languagesCount: languagesCount,
      languagesMissingLevel: languagesMissingLevel,
      hasSummary: true,
    );

bool _hasLacuna(ProfileGaps g, LacunaKey k) => g.missing.any((l) => l.key == k);

void main() {
  group('lacuna de idiomas ciente de nível', () {
    test('idioma sem nível mantém a lacuna ABERTA', () {
      final g = _gaps(languagesCount: 1, languagesMissingLevel: 1);
      expect(_hasLacuna(g, LacunaKey.languages), isTrue);
    });
    test('todos com nível → lacuna FECHADA', () {
      final g = _gaps(languagesCount: 2, languagesMissingLevel: 0);
      expect(_hasLacuna(g, LacunaKey.languages), isFalse);
    });
    test('nenhum idioma → lacuna aberta', () {
      final g = _gaps(languagesCount: 0, languagesMissingLevel: 0);
      expect(_hasLacuna(g, LacunaKey.languages), isTrue);
    });
  });

  group('plano pergunta só os níveis que faltam', () {
    test('idiomas sem nível → passos de nível, SEM re-rodar o picker', () {
      final plan = buildConversationPlan(
        _gaps(languagesCount: 2, languagesMissingLevel: 2),
        languagesNeedingLevel: ['Inglês', 'Espanhol'],
      );
      final ids = plan.map((s) => s.id);
      expect(ids, contains('lang.level.Inglês'));
      expect(ids, contains('lang.level.Espanhol'));
      expect(ids, isNot(contains('gap.languages')));
    });
    test('nenhum idioma → mostra o picker', () {
      final plan = buildConversationPlan(
        _gaps(languagesCount: 0, languagesMissingLevel: 0),
      );
      expect(plan.map((s) => s.id), contains('gap.languages'));
    });
  });
}
