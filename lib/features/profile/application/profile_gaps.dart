// ProfileGaps — "cérebro de lacunas": dado o perfil do usuário, diz quais
// campos MONETIZÁVEIS faltam (o que o match e a shortlist do admin precisam).
//
// Alimenta: a trilha de IA (plano adaptativo de perguntas — só pergunta o que
// falta), o hub de completude (cartões de lacuna + progresso) e os nudges
// ("faltam 2 skills pra esse match subir"). PLANO-FASE-6 (cérebro de lacunas).
//
// O núcleo [analyzeProfileGaps] é PURO (primitivos, sem Supabase) → testável
// (R3). [profileGapsFromData] é o adaptador que monta a entrada a partir do
// ProfileSnapshot + JobPreferences + DesiredTitles reais.

import '../../../services/profile_snapshot_service.dart' show ProfileSnapshot;
import '../domain/entities/entities.dart' show JobPreferences, DesiredTitle;

/// Quão crítico o campo é pra monetização.
///   tier1 = filtro duro do admin + maior peso no match (sem isso o candidato
///           é invisível ou some no match)
///   tier2 = substância que diferencia (experiência, idiomas)
///   tier3 = acabamento (resumo)
enum LacunaTier { tier1, tier2, tier3 }

/// Cada campo monetizável rastreado pelo cérebro de lacunas.
enum LacunaKey {
  area,
  workMode,
  jobType,
  city,
  educationStatus,
  skills,
  experience,
  languages,
  summary,
  // Tier 3 — extras (PLANO-FASE-6: certs/projetos/LinkedIn).
  linkedin,
  certifications,
  projects,
}

/// Skills mínimas pra um perfil contar como "tem habilidades" — abaixo disso o
/// match trata como ruído e o filtro de skills do admin fica fraco.
const int kMinSkillsForComplete = 3;

/// Uma lacuna (campo monetizável) com seu estado de preenchimento.
class Lacuna {
  final LacunaKey key;
  final LacunaTier tier;

  /// Rótulo curto em PT-BR pra UI (cartão do hub / nudge).
  final String label;
  final bool filled;

  const Lacuna({
    required this.key,
    required this.tier,
    required this.label,
    required this.filled,
  });
}

/// Resultado da análise: a lista completa (preenchidos + faltando), já em ordem
/// de prioridade de coleta (Tier 1 primeiro), mais métricas derivadas.
class ProfileGaps {
  /// Todos os campos rastreados, em ordem de prioridade de coleta.
  final List<Lacuna> all;

  const ProfileGaps(this.all);

  /// O que falta, na ordem em que a trilha/nudge deve cobrar.
  List<Lacuna> get missing =>
      all.where((l) => !l.filled).toList(growable: false);

  /// Faltando só do Tier 1 (filtros duros).
  List<Lacuna> get missingTier1 => missing
      .where((l) => l.tier == LacunaTier.tier1)
      .toList(growable: false);

  /// Próxima lacuna a coletar (nula se nada falta).
  Lacuna? get nextGap => missing.isEmpty ? null : missing.first;

  /// Pronto pra shortlist = todos os campos Tier 1 preenchidos (área, tipo,
  /// cidade, modalidade, momento de estudo e skills >= mínimo).
  bool get isShortlistReady => missingTier1.isEmpty;

  /// Completude ponderada por monetização (0..100). Difere do
  /// `completeness_score` do banco — aqui o Tier 1 pesa mais, refletindo o que
  /// destrava match + shortlist. (T6.6 revisita a fórmula do banco pra alinhar.)
  int get completionPercent {
    double score = 0;
    double total = 0;
    for (final l in all) {
      final w = _tierWeight(l.tier);
      total += w;
      if (l.filled) score += w;
    }
    if (total == 0) return 0;
    return ((score / total) * 100).round();
  }

  static double _tierWeight(LacunaTier t) {
    switch (t) {
      case LacunaTier.tier1:
        return 3;
      case LacunaTier.tier2:
        return 2;
      case LacunaTier.tier3:
        return 1;
    }
  }
}

/// Núcleo PURO. Recebe presença/contagens e devolve as lacunas já em ordem de
/// prioridade de coleta. Sem dependência de Supabase/entidades → testável.
ProfileGaps analyzeProfileGaps({
  required bool hasArea,
  required bool hasWorkMode,
  required bool hasJobType,
  required bool hasCity,
  required bool hasEducationStatus,
  required int skillsCount,
  required int experienceCount,
  required int languagesCount,
  required bool hasSummary,
  bool hasLinkedin = false,
  bool hasCertifications = false,
  bool hasProjects = false,
}) {
  final list = <Lacuna>[
    // Tier 1 — filtros duros, ordem do mais barato (clique) ao mais "rico".
    Lacuna(
      key: LacunaKey.area,
      tier: LacunaTier.tier1,
      label: 'Áreas de interesse',
      filled: hasArea,
    ),
    Lacuna(
      key: LacunaKey.workMode,
      tier: LacunaTier.tier1,
      label: 'Modalidade de trabalho',
      filled: hasWorkMode,
    ),
    Lacuna(
      key: LacunaKey.jobType,
      tier: LacunaTier.tier1,
      label: 'Tipo de vaga',
      filled: hasJobType,
    ),
    Lacuna(
      key: LacunaKey.city,
      tier: LacunaTier.tier1,
      label: 'Cidade',
      filled: hasCity,
    ),
    Lacuna(
      key: LacunaKey.educationStatus,
      tier: LacunaTier.tier1,
      label: 'Momento de estudo',
      filled: hasEducationStatus,
    ),
    Lacuna(
      key: LacunaKey.skills,
      tier: LacunaTier.tier1,
      label: 'Habilidades (mín. $kMinSkillsForComplete)',
      filled: skillsCount >= kMinSkillsForComplete,
    ),
    // Tier 2 — substância.
    Lacuna(
      key: LacunaKey.experience,
      tier: LacunaTier.tier2,
      label: 'Experiências',
      filled: experienceCount >= 1,
    ),
    Lacuna(
      key: LacunaKey.languages,
      tier: LacunaTier.tier2,
      label: 'Idiomas',
      filled: languagesCount >= 1,
    ),
    // Tier 3 — acabamento.
    Lacuna(
      key: LacunaKey.summary,
      tier: LacunaTier.tier3,
      label: 'Resumo profissional',
      filled: hasSummary,
    ),
    Lacuna(
      key: LacunaKey.linkedin,
      tier: LacunaTier.tier3,
      label: 'Link do LinkedIn',
      filled: hasLinkedin,
    ),
    Lacuna(
      key: LacunaKey.certifications,
      tier: LacunaTier.tier3,
      label: 'Certificações',
      filled: hasCertifications,
    ),
    Lacuna(
      key: LacunaKey.projects,
      tier: LacunaTier.tier3,
      label: 'Projetos',
      filled: hasProjects,
    ),
  ];
  return ProfileGaps(list);
}

/// Adaptador: monta a entrada do núcleo puro a partir dos dados reais.
///
/// Cidade conta tanto a cidade-casa (`profile_personal.location_city`) quanto a
/// cidade-preferência (`profile_job_preferences.primary_location_city`).
/// Momento de estudo conta qualquer formação com status OU semestre setado.
ProfileGaps profileGapsFromData({
  required ProfileSnapshot snapshot,
  required JobPreferences? prefs,
  required List<DesiredTitle> desiredTitles,
}) {
  final personal = snapshot.personal;

  final hasCity = (personal?.locationCity?.trim().isNotEmpty ?? false) ||
      ((prefs?.primaryLocationCity?.trim().isNotEmpty) ?? false);

  final hasEducationStatus = snapshot.education.any(
    (e) => e.educationStatus != null || e.currentSemester != null,
  );

  return analyzeProfileGaps(
    hasArea: desiredTitles.isNotEmpty,
    hasWorkMode: prefs?.workMode.isNotEmpty ?? false,
    hasJobType: prefs?.jobTypes.isNotEmpty ?? false,
    hasCity: hasCity,
    hasEducationStatus: hasEducationStatus,
    skillsCount: snapshot.skills.length,
    experienceCount: snapshot.experiences.length,
    languagesCount: snapshot.languages.length,
    hasSummary: personal?.summary?.trim().isNotEmpty ?? false,
    hasLinkedin: personal?.linkedinUrl?.trim().isNotEmpty ?? false,
    hasCertifications: snapshot.certifications.isNotEmpty,
    hasProjects: snapshot.projects.isNotEmpty,
  );
}
