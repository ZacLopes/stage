// Fase 7 · +10 Tarefa 4: o painel de progresso para de mentir. A força vem das
// lacunas REAIS; nunca declara "forte/completo" com lacuna aberta; e aponta o
// próximo ganho de maior valor.
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/profile/application/profile_gaps.dart';
import 'package:career_gamification/features/trilha/application/trilha_hub_status.dart';

/// Perfil só com os Tier 1 (filtros duros) — ainda sem experiência/idiomas etc.
ProfileGaps _tier1Only() => analyzeProfileGaps(
      hasArea: true,
      hasWorkMode: true,
      hasJobType: true,
      hasCity: true,
      hasEducationStatus: true,
      skillsCount: 3,
      experienceCount: 0, // ← lacuna Tier 2
      languagesCount: 0,
      hasSummary: false,
    );

/// Faltando um essencial (área) — NÃO pronto pra shortlist.
ProfileGaps _missingArea() => analyzeProfileGaps(
      hasArea: false, // ← lacuna Tier 1
      hasWorkMode: true,
      hasJobType: true,
      hasCity: true,
      hasEducationStatus: true,
      skillsCount: 3,
      experienceCount: 1,
      languagesCount: 1,
      hasSummary: true,
    );

/// Tudo preenchido.
ProfileGaps _everything() => analyzeProfileGaps(
      hasArea: true,
      hasWorkMode: true,
      hasJobType: true,
      hasCity: true,
      hasEducationStatus: true,
      skillsCount: 5,
      experienceCount: 2,
      languagesCount: 2,
      hasSummary: true,
      hasLinkedin: true,
      hasDesiredPosition: true,
      hasCertifications: true,
      hasAwards: true,
      hasProjects: true,
      hasAvailability: true,
      hasInterests: true,
    );

void main() {
  group('hub honesto', () {
    test('faltando essencial (Tier 1) → building, sem "forte", com % e ganho',
        () {
      final hs = trilhaHubStatusFromGaps(_missingArea());
      expect(hs.level, HubLevel.building);
      // Não pode declarar "forte/completo" com lacuna aberta.
      expect(hs.title.toLowerCase(), isNot(contains('completo')));
      // Mostra a força real (crua) no título.
      expect(hs.title, contains('${hs.strengthPercent}%'));
      // Aponta o próximo ganho — a primeira lacuna é a área.
      expect(hs.nextStepLabel, 'Áreas de interesse');
      expect(hs.message.toLowerCase(), contains('área'));
    });

    test('Tier 1 completo mas sem substância → shortlistReady + próximo ganho',
        () {
      final hs = trilhaHubStatusFromGaps(_tier1Only());
      expect(hs.level, HubLevel.shortlistReady);
      // A próxima lacuna de maior valor é experiência (Tier 2, primeira).
      expect(hs.nextStepLabel, 'Experiências');
      expect(hs.message.toLowerCase(), contains('experiência'));
      // Honesto: comemora o marco real (aparece pras empresas), sem dizer "completo".
      expect(hs.title.toLowerCase(), isNot(contains('completo')));
    });

    test('nada falta → complete, comemora de verdade, sem próximo passo', () {
      final hs = trilhaHubStatusFromGaps(_everything());
      expect(hs.level, HubLevel.complete);
      expect(hs.strengthPercent, 100);
      expect(hs.nextStepLabel, isNull);
      expect(hs.title.toLowerCase(), contains('completo'));
    });

    test('strengthPercent == completionPercent das lacunas', () {
      final gaps = _tier1Only();
      expect(trilhaHubStatusFromGaps(gaps).strengthPercent,
          gaps.completionPercent);
    });
  });
}
