import 'package:career_gamification/features/profile/domain/entities/job_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JobPreferences.copyWith — flags de LIMPAR (Fase 3)', () {
    const base = JobPreferences(
      userId: 'u',
      desiredPosition: 'Dev',
      companyStage: 'startup',
      workEnvironment: 'dynamic',
      workStyle: 'autonomy',
      experienceLevel: [ExperienceLevel.mid],
    );

    test('null mantém o valor antigo (comportamento padrão)', () {
      final r = base.copyWith();
      expect(r.desiredPosition, 'Dev');
      expect(r.companyStage, 'startup');
      expect(r.experienceLevel, [ExperienceLevel.mid]);
    });

    test('setar substitui', () {
      expect(base.copyWith(desiredPosition: 'Senior').desiredPosition, 'Senior');
      expect(base.copyWith(companyStage: 'open').companyStage, 'open');
      expect(
        base.copyWith(experienceLevel: [ExperienceLevel.senior]).experienceLevel,
        [ExperienceLevel.senior],
      );
    });

    test('clearDesiredPosition/CompanyStage/WorkEnvironment/WorkStyle zeram', () {
      expect(base.copyWith(clearDesiredPosition: true).desiredPosition, isNull);
      expect(base.copyWith(clearCompanyStage: true).companyStage, isNull);
      expect(base.copyWith(clearWorkEnvironment: true).workEnvironment, isNull);
      expect(base.copyWith(clearWorkStyle: true).workStyle, isNull);
      // limpar um NÃO afeta os outros.
      final r = base.copyWith(clearDesiredPosition: true);
      expect(r.companyStage, 'startup');
      expect(r.workStyle, 'autonomy');
    });

    test('experienceLevel vazio limpa (lista)', () {
      expect(base.copyWith(experienceLevel: const []).experienceLevel, isEmpty);
    });
  });
}
