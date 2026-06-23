import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/profile/application/profile_gaps.dart';
import 'package:career_gamification/features/trilha/application/conversation_plan.dart';

/// Cobre o construtor adaptativo do plano: só pergunta o que falta, e nunca
/// inclui o que está fora do escopo desta fase (experiência/resumo).
/// PLANO-FASE-6 T6.3 Increment 2.
void main() {
  ProfileGaps gaps({
    bool hasArea = false,
    bool hasWorkMode = false,
    bool hasJobType = false,
    bool hasCity = false,
    bool hasEducationStatus = false,
    int skillsCount = 0,
    int experienceCount = 0,
    int languagesCount = 0,
    bool hasSummary = false,
  }) =>
      analyzeProfileGaps(
        hasArea: hasArea,
        hasWorkMode: hasWorkMode,
        hasJobType: hasJobType,
        hasCity: hasCity,
        hasEducationStatus: hasEducationStatus,
        skillsCount: skillsCount,
        experienceCount: experienceCount,
        languagesCount: languagesCount,
        hasSummary: hasSummary,
      );

  group('buildConversationPlan', () {
    test('perfil oco: pergunta tudo o que esta fase cobre (intro + 6)', () {
      final plan = buildConversationPlan(gaps());
      final ids = plan.map((s) => s.id).toList();
      expect(ids.first, 'intro');
      expect(
        ids,
        containsAll([
          'gap.area',
          'gap.workmode',
          'gap.jobtype',
          'gap.city',
          'gap.skills',
          'gap.languages',
        ]),
      );
      // Educação NÃO é coletada aqui (já vem do onboarding).
      expect(ids, isNot(contains('gap.education')));
      expect(plan, hasLength(7)); // intro + 6
    });

    test('perfil completo (só faltam experiência/resumo): plano vazio', () {
      final plan = buildConversationPlan(gaps(
        hasArea: true,
        hasWorkMode: true,
        hasJobType: true,
        hasCity: true,
        hasEducationStatus: true,
        skillsCount: 5,
        languagesCount: 1,
        // experienceCount: 0 e hasSummary: false → faltam, mas não são desta fase
      ));
      expect(plan, isEmpty);
    });

    test('adaptativo: só skills faltando → intro + skills', () {
      final plan = buildConversationPlan(gaps(
        hasArea: true,
        hasWorkMode: true,
        hasJobType: true,
        hasCity: true,
        hasEducationStatus: true,
        skillsCount: 0, // só isso falta
        experienceCount: 1,
        languagesCount: 1,
      ));
      expect(plan.map((s) => s.id), ['intro', 'gap.skills']);
    });

    test('nunca inclui passos de experiência ou resumo', () {
      final plan = buildConversationPlan(gaps());
      final ids = plan.map((s) => s.id);
      expect(ids.any((id) => id.contains('experience')), false);
      expect(ids.any((id) => id.contains('summary')), false);
    });

    test('todo passo do plano tem uma fala e uma entrada', () {
      final plan = buildConversationPlan(gaps());
      for (final step in plan) {
        expect(step.aiMessages, isNotEmpty);
        expect(step.aiMessages.first.trim(), isNotEmpty);
      }
    });
  });
}
