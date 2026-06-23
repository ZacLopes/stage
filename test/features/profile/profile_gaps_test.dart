import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/profile/application/profile_gaps.dart';

/// Cobre o núcleo puro do "cérebro de lacunas" — a base que alimenta a trilha
/// de IA, o hub de completude e os nudges (PLANO-FASE-6).
void main() {
  // Helper: tudo Tier 1 preenchido, sem Tier 2/3.
  ProfileGaps tier1Complete({int skills = 3}) => analyzeProfileGaps(
        hasArea: true,
        hasWorkMode: true,
        hasJobType: true,
        hasCity: true,
        hasEducationStatus: true,
        skillsCount: skills,
        experienceCount: 0,
        languagesCount: 0,
        hasSummary: false,
      );

  ProfileGaps empty() => analyzeProfileGaps(
        hasArea: false,
        hasWorkMode: false,
        hasJobType: false,
        hasCity: false,
        hasEducationStatus: false,
        skillsCount: 0,
        experienceCount: 0,
        languagesCount: 0,
        hasSummary: false,
      );

  group('analyzeProfileGaps', () {
    test('perfil vazio: tudo faltando, 0%, não shortlist-ready', () {
      final g = empty();
      expect(g.missing.length, g.all.length);
      expect(g.completionPercent, 0);
      expect(g.isShortlistReady, false);
      expect(g.nextGap?.key, LacunaKey.area, reason: 'área é a 1ª prioridade');
    });

    test('Tier 1 completo (skills>=3): shortlist-ready, sem faltas Tier 1', () {
      final g = tier1Complete();
      expect(g.isShortlistReady, true);
      expect(g.missingTier1, isEmpty);
      // Ainda faltam Tier 2/3 (experiência, idiomas, resumo).
      expect(g.missing.map((l) => l.key),
          containsAll([LacunaKey.experience, LacunaKey.languages, LacunaKey.summary]));
    });

    test('skills abaixo do mínimo NÃO conta como preenchido', () {
      final g = tier1Complete(skills: kMinSkillsForComplete - 1);
      expect(g.isShortlistReady, false);
      expect(g.missing.map((l) => l.key), contains(LacunaKey.skills));
    });

    test('skills exatamente no mínimo conta como preenchido', () {
      final g = tier1Complete(skills: kMinSkillsForComplete);
      expect(g.missing.map((l) => l.key), isNot(contains(LacunaKey.skills)));
    });

    test('estado típico do perfil oco (prefs ok, sem skills/experiência)', () {
      // Espelha o não-importador: área/modalidade/cidade/momento ok via
      // onboarding, mas sem a substância de carreira.
      final g = analyzeProfileGaps(
        hasArea: true,
        hasWorkMode: true,
        hasJobType: true,
        hasCity: true,
        hasEducationStatus: true,
        skillsCount: 0,
        experienceCount: 0,
        languagesCount: 0,
        hasSummary: false,
      );
      expect(g.isShortlistReady, false, reason: 'sem skills não está pronto');
      expect(g.missing.map((l) => l.key),
          containsAll([LacunaKey.skills, LacunaKey.experience, LacunaKey.summary]));
      // A próxima lacuna prioriza Tier 1 (skills) sobre Tier 2/3.
      expect(g.nextGap?.key, LacunaKey.skills);
    });

    test('completionPercent sobe ao preencher mais campos', () {
      expect(empty().completionPercent, lessThan(tier1Complete().completionPercent));
      // Perfil 100% completo = 100%.
      final full = analyzeProfileGaps(
        hasArea: true,
        hasWorkMode: true,
        hasJobType: true,
        hasCity: true,
        hasEducationStatus: true,
        skillsCount: 5,
        experienceCount: 2,
        languagesCount: 1,
        hasSummary: true,
        hasLinkedin: true,
        hasCertifications: true,
        hasProjects: true,
      );
      expect(full.completionPercent, 100);
      expect(full.missing, isEmpty);
      expect(full.nextGap, isNull);
    });

    test('Tier 1 pesa mais que Tier 3 na completude', () {
      // Só área (Tier 1) preenchida vs só resumo (Tier 3) preenchido.
      final soArea = analyzeProfileGaps(
        hasArea: true, hasWorkMode: false, hasJobType: false, hasCity: false,
        hasEducationStatus: false, skillsCount: 0, experienceCount: 0,
        languagesCount: 0, hasSummary: false,
      );
      final soResumo = analyzeProfileGaps(
        hasArea: false, hasWorkMode: false, hasJobType: false, hasCity: false,
        hasEducationStatus: false, skillsCount: 0, experienceCount: 0,
        languagesCount: 0, hasSummary: true,
      );
      expect(soArea.completionPercent, greaterThan(soResumo.completionPercent));
    });
  });
}
