// ProfileRepository — interface única pra todas as operações de perfil estruturado.
//
// Implementação default em data/repositories/profile_repository_supabase.dart usa
// supabase_flutter direto. RLS no banco garante que o user só lê/escreve o
// próprio perfil (auth.uid() = user_id).
//
// 2 padrões de escrita:
//   - CRUD direto por entidade (add/update/delete*) pra edições granulares
//   - replaceProfile(profileData) pra trilhas completas (RPC save_profile_from_json)

import '../entities/entities.dart';

abstract class ProfileRepository {
  // ──────────────────────────────────────────────────────────────────────
  // PersonalInfo (1:1)
  // ──────────────────────────────────────────────────────────────────────
  Future<PersonalInfo?> getPersonal(String userId);
  /// [nullColumns] força NULL nessas colunas (o upsert parcial normal ignora
  /// nulls) — ex.: trocar de cidade limpa o CEP/UF antigos.
  Future<PersonalInfo> upsertPersonal(PersonalInfo info,
      {Set<String> nullColumns});

  // ──────────────────────────────────────────────────────────────────────
  // Experiences + Bullets
  // ──────────────────────────────────────────────────────────────────────
  Future<List<Experience>> getExperiences(String userId);
  Future<Experience> addExperience(Experience exp);
  Future<Experience> updateExperience(Experience exp);
  Future<void> deleteExperience(String experienceId);
  Future<void> reorderExperiences(String userId, List<String> orderedIds);

  Future<Bullet> addBullet(Bullet bullet);
  Future<Bullet> updateBullet(Bullet bullet);
  Future<void> deleteBullet(String bulletId);
  Future<void> reorderBullets(String experienceId, List<String> orderedIds);

  // ──────────────────────────────────────────────────────────────────────
  // Education + filhas
  // ──────────────────────────────────────────────────────────────────────
  Future<List<Education>> getEducation(String userId);
  Future<Education> addEducation(Education edu);
  Future<Education> updateEducation(Education edu);
  Future<void> deleteEducation(String educationId);

  // ──────────────────────────────────────────────────────────────────────
  // Languages, Skills, Certifications, Projects, Interests, Awards, Coursework
  // ──────────────────────────────────────────────────────────────────────
  Future<List<Language>> getLanguages(String userId);
  Future<Language> addLanguage(Language lang);
  Future<Language> updateLanguage(Language lang);
  Future<void> deleteLanguage(String id);

  Future<List<Skill>> getSkills(String userId);
  Future<Skill> addSkill(Skill skill);
  Future<Skill> updateSkill(Skill skill);
  Future<void> deleteSkill(String id);
  Future<void> replaceSkills(String userId, List<String> names);

  /// Nomes canônicos do `skills_catalog` (taxonomia P5) — sugestões do typeahead
  /// no editor de skills. Vocabulário pequeno (~165); carregado uma vez.
  Future<List<String>> getSkillCatalogNames();

  Future<List<Certification>> getCertifications(String userId);
  Future<Certification> addCertification(Certification cert);
  Future<Certification> updateCertification(Certification cert);
  Future<void> deleteCertification(String id);

  Future<List<Project>> getProjects(String userId);
  Future<Project> addProject(Project project);
  Future<Project> updateProject(Project project);
  Future<void> deleteProject(String id);
  Future<ProjectBullet> addProjectBullet(ProjectBullet bullet);
  Future<ProjectBullet> updateProjectBullet(ProjectBullet bullet);
  Future<void> deleteProjectBullet(String bulletId);
  Future<void> reorderProjectBullets(String projectId, List<String> orderedIds);

  Future<List<Interest>> getInterests(String userId);
  Future<void> replaceInterests(String userId, List<String> names);

  /// Gate 3.0H app-side — CAS de escalar de `profile_personal` (manual-recente-
  /// vence). Retorna 'applied' ou 'stale'. name/city/phone são compostos;
  /// [expected] é o valor OBSERVADO (display) no propose. Fail-closed → 'stale'.
  Future<String> casWritePersonalField(
    String userId,
    String field,
    String expected,
    String value, {
    String? expectedCountryCode,
    String? newCountryCode,
  });

  /// Gate 3.0H app-side — CAS de campo de item por ref_id (experience/education/
  /// certification/bullet). Retorna 'applied' ou 'stale'.
  Future<String> casWriteItemField(
    String userId,
    String kind,
    String refId,
    String field,
    String expected,
    String value,
  );

  Future<List<Award>> getAwards(String userId);
  Future<Award> addAward(Award award);
  Future<Award> updateAward(Award award);
  Future<void> deleteAward(String id);

  Future<List<Coursework>> getCoursework(String userId);
  Future<void> replaceCoursework(String userId, List<String> names);

  // ──────────────────────────────────────────────────────────────────────
  // Job Preferences + filhas
  // ──────────────────────────────────────────────────────────────────────
  Future<JobPreferences?> getJobPreferences(String userId);
  Future<JobPreferences> upsertJobPreferences(JobPreferences prefs);

  Future<List<DesiredTitle>> getDesiredTitles(String userId);
  Future<void> replaceDesiredTitles(String userId, List<DesiredTitle> titles);

  Future<List<ApplicationCountry>> getApplicationCountries(String userId);
  Future<void> replaceApplicationCountries(String userId, List<ApplicationCountry> countries);

  Future<List<OtherLocation>> getOtherLocations(String userId);
  Future<void> replaceOtherLocations(String userId, List<OtherLocation> locations);

  // ──────────────────────────────────────────────────────────────────────
  // Replace em massa (trilha gamificada inteira ou re-extração de CV)
  // RPC save_profile_from_json — DESTRUTIVO, deleta tudo do user e re-insere.
  // ──────────────────────────────────────────────────────────────────────
  Future<void> replaceProfile(String userId, Map<String, dynamic> profileData);

  // ──────────────────────────────────────────────────────────────────────
  // Completeness
  // ──────────────────────────────────────────────────────────────────────
  Future<int> getCompletenessScore(String userId);

  // ──────────────────────────────────────────────────────────────────────
  // Progresso da trilha de coleta (retomada entre devices) — profile_guided_progress
  // ──────────────────────────────────────────────────────────────────────
  /// Segmentos da trilha já abordados por [userId] (server-side).
  Future<Set<String>> getGuidedProgress(String userId);

  /// Marca [segment] como abordado. Idempotente (ON CONFLICT DO NOTHING).
  Future<void> markGuidedProgress(String userId, String segment);

  /// Reseta o progresso da trilha no servidor (apaga os segmentos abordados de
  /// [userId]). NÃO toca nos dados coletados em profile_*.
  Future<void> clearGuidedProgress(String userId);
}
