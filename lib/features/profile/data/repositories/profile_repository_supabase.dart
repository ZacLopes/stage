// ProfileRepositorySupabase — implementação usando supabase_flutter direto.
//
// RLS no banco garante que o user só vê/edita o próprio perfil
// (auth.uid() = user_id em todas as 18 tabelas).
//
// Nested reads usam PostgREST foreign tables (select('*, profile_bullets(*)')).

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/profile_repository.dart';

class ProfileRepositorySupabase implements ProfileRepository {
  final SupabaseClient _client;

  ProfileRepositorySupabase({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  // ──────────────────────────────────────────────────────────────────────
  // PersonalInfo
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<PersonalInfo?> getPersonal(String userId) async {
    final row = await _client
        .from('profile_personal')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return PersonalInfo.fromMap(row);
  }

  @override
  Future<PersonalInfo> upsertPersonal(PersonalInfo info) async {
    final map = info.toMap()
      ..removeWhere((k, v) => v == null && k != 'user_id');
    final row = await _client
        .from('profile_personal')
        .upsert(map, onConflict: 'user_id')
        .select()
        .single();
    return PersonalInfo.fromMap(row);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Experiences + Bullets (nested read)
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<List<Experience>> getExperiences(String userId) async {
    final rows = await _client
        .from('profile_experiences')
        .select('*, profile_bullets(*)')
        .eq('user_id', userId)
        .order('order_index');
    return (rows as List)
        .map((r) => Experience.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Experience> addExperience(Experience exp) async {
    final map = exp.toMap()..remove('id'); // deixa DB gerar
    final row = await _client
        .from('profile_experiences')
        .insert(map)
        .select()
        .single();
    return Experience.fromMap(row);
  }

  @override
  Future<Experience> updateExperience(Experience exp) async {
    final row = await _client
        .from('profile_experiences')
        .update(exp.toMap()..remove('id'))
        .eq('id', exp.id)
        .select()
        .single();
    return Experience.fromMap(row);
  }

  @override
  Future<void> deleteExperience(String experienceId) async {
    await _client.from('profile_experiences').delete().eq('id', experienceId);
  }

  @override
  Future<void> reorderExperiences(
    String userId,
    List<String> orderedIds,
  ) async {
    // Batch update — Postgres não tem batch nativo via PostgREST, então fazemos
    // N UPDATEs paralelos com Future.wait.
    final futures = <Future>[];
    for (var i = 0; i < orderedIds.length; i++) {
      futures.add(
        _client
            .from('profile_experiences')
            .update({'order_index': i})
            .eq('id', orderedIds[i])
            .eq('user_id', userId),
      );
    }
    await Future.wait(futures);
  }

  @override
  Future<Bullet> addBullet(Bullet bullet) async {
    final map = bullet.toMap()..remove('id');
    final row = await _client
        .from('profile_bullets')
        .insert(map)
        .select()
        .single();
    return Bullet.fromMap(row);
  }

  @override
  Future<Bullet> updateBullet(Bullet bullet) async {
    final row = await _client
        .from('profile_bullets')
        .update(bullet.toMap()..remove('id'))
        .eq('id', bullet.id)
        .select()
        .single();
    return Bullet.fromMap(row);
  }

  @override
  Future<void> deleteBullet(String bulletId) async {
    await _client.from('profile_bullets').delete().eq('id', bulletId);
  }

  @override
  Future<void> reorderBullets(
    String experienceId,
    List<String> orderedIds,
  ) async {
    final futures = <Future>[];
    for (var i = 0; i < orderedIds.length; i++) {
      futures.add(
        _client
            .from('profile_bullets')
            .update({'order_index': i})
            .eq('id', orderedIds[i])
            .eq('experience_id', experienceId),
      );
    }
    await Future.wait(futures);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Education + filhas
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<List<Education>> getEducation(String userId) async {
    final rows = await _client
        .from('profile_education')
        .select(
          '*, profile_education_majors(*), profile_education_minors(*), profile_education_activities(*)',
        )
        .eq('user_id', userId)
        .order('order_index');
    return (rows as List)
        .map((r) => Education.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Education> addEducation(Education edu) async {
    final row = await _insertEducationRow(edu);
    final newEdu = Education.fromMap(row);

    // Insere filhas (majors, minors, activities)
    await _insertEducationChildren(newEdu.id, edu);

    // Re-fetch pra retornar com filhas
    return (await getEducation(
      edu.userId,
    )).firstWhere((e) => e.id == newEdu.id);
  }

  @override
  Future<Education> updateEducation(Education edu) async {
    await _updateEducationRow(edu);

    // Estratégia: delete + re-insert filhas (cascade limpa via FK)
    await _client
        .from('profile_education_majors')
        .delete()
        .eq('education_id', edu.id);
    await _client
        .from('profile_education_minors')
        .delete()
        .eq('education_id', edu.id);
    await _client
        .from('profile_education_activities')
        .delete()
        .eq('education_id', edu.id);
    await _insertEducationChildren(edu.id, edu);

    return (await getEducation(edu.userId)).firstWhere((e) => e.id == edu.id);
  }

  Future<Map<String, dynamic>> _insertEducationRow(Education edu) async {
    try {
      return await _client
          .from('profile_education')
          .insert(_educationMap(edu))
          .select()
          .single();
    } catch (e) {
      if (!_isEducationSchemaMismatch(e)) rethrow;
      return await _client
          .from('profile_education')
          .insert(_educationMap(edu, includeOnboardingFields: false))
          .select()
          .single();
    }
  }

  Future<void> _updateEducationRow(Education edu) async {
    try {
      await _client
          .from('profile_education')
          .update(_educationMap(edu))
          .eq('id', edu.id);
    } catch (e) {
      if (!_isEducationSchemaMismatch(e)) rethrow;
      await _client
          .from('profile_education')
          .update(_educationMap(edu, includeOnboardingFields: false))
          .eq('id', edu.id);
    }
  }

  Map<String, dynamic> _educationMap(
    Education edu, {
    bool includeOnboardingFields = true,
  }) {
    final map = edu.toMap()..remove('id');
    if (!includeOnboardingFields) {
      map.remove('education_level');
      map.remove('education_status');
      map.remove('current_semester');
      map.remove('current_school_year');
    }
    return map;
  }

  bool _isEducationSchemaMismatch(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('profile_education') &&
        (text.contains('schema cache') ||
            text.contains('could not find') ||
            text.contains('pgrst204')) &&
        (text.contains('education_level') ||
            text.contains('education_status') ||
            text.contains('current_semester') ||
            text.contains('current_school_year'));
  }

  Future<void> _insertEducationChildren(
    String educationId,
    Education edu,
  ) async {
    if (edu.majors.isNotEmpty) {
      await _client
          .from('profile_education_majors')
          .insert(
            edu.majors
                .asMap()
                .entries
                .map(
                  (e) => {
                    'education_id': educationId,
                    'name': e.value.name,
                    'order_index': e.key,
                  },
                )
                .toList(),
          );
    }
    if (edu.minors.isNotEmpty) {
      await _client
          .from('profile_education_minors')
          .insert(
            edu.minors
                .asMap()
                .entries
                .map(
                  (e) => {
                    'education_id': educationId,
                    'name': e.value.name,
                    'order_index': e.key,
                  },
                )
                .toList(),
          );
    }
    if (edu.activities.isNotEmpty) {
      await _client
          .from('profile_education_activities')
          .insert(
            edu.activities
                .asMap()
                .entries
                .map(
                  (e) => {
                    'education_id': educationId,
                    'text': e.value.text,
                    'order_index': e.key,
                  },
                )
                .toList(),
          );
    }
  }

  @override
  Future<void> deleteEducation(String educationId) async {
    await _client.from('profile_education').delete().eq('id', educationId);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Languages
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<List<Language>> getLanguages(String userId) async {
    final rows = await _client
        .from('profile_languages')
        .select()
        .eq('user_id', userId)
        .order('order_index');
    return (rows as List)
        .map((r) => Language.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Language> addLanguage(Language lang) async {
    final row = await _client
        .from('profile_languages')
        .insert(lang.toMap()..remove('id'))
        .select()
        .single();
    return Language.fromMap(row);
  }

  @override
  Future<Language> updateLanguage(Language lang) async {
    final row = await _client
        .from('profile_languages')
        .update(lang.toMap()..remove('id'))
        .eq('id', lang.id)
        .select()
        .single();
    return Language.fromMap(row);
  }

  @override
  Future<void> deleteLanguage(String id) async {
    await _client.from('profile_languages').delete().eq('id', id);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Skills
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<List<Skill>> getSkills(String userId) async {
    final rows = await _client
        .from('profile_skills')
        .select()
        .eq('user_id', userId)
        .order('order_index');
    return (rows as List)
        .map((r) => Skill.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<String>> getSkillCatalogNames() async {
    final rows = await _client
        .from('skills_catalog')
        .select('canonical_name')
        .order('canonical_name');
    return (rows as List)
        .map((r) => (r as Map<String, dynamic>)['canonical_name'] as String)
        .toList();
  }

  @override
  Future<Skill> addSkill(Skill skill) async {
    final row = await _client
        .from('profile_skills')
        .insert(skill.toMap()..remove('id'))
        .select()
        .single();
    return Skill.fromMap(row);
  }

  @override
  Future<Skill> updateSkill(Skill skill) async {
    final row = await _client
        .from('profile_skills')
        .update(skill.toMap()..remove('id'))
        .eq('id', skill.id)
        .select()
        .single();
    return Skill.fromMap(row);
  }

  @override
  Future<void> deleteSkill(String id) async {
    await _client.from('profile_skills').delete().eq('id', id);
  }

  @override
  Future<void> replaceSkills(String userId, List<String> names) async {
    await _client.from('profile_skills').delete().eq('user_id', userId);
    if (names.isEmpty) return;
    await _client
        .from('profile_skills')
        .insert(
          names
              .asMap()
              .entries
              .map(
                (e) => {
                  'user_id': userId,
                  'name': e.value,
                  'order_index': e.key,
                },
              )
              .toList(),
        );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Certifications
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<List<Certification>> getCertifications(String userId) async {
    final rows = await _client
        .from('profile_certifications')
        .select()
        .eq('user_id', userId)
        .order('order_index');
    return (rows as List)
        .map((r) => Certification.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Certification> addCertification(Certification cert) async {
    final row = await _client
        .from('profile_certifications')
        .insert(cert.toMap()..remove('id'))
        .select()
        .single();
    return Certification.fromMap(row);
  }

  @override
  Future<Certification> updateCertification(Certification cert) async {
    final row = await _client
        .from('profile_certifications')
        .update(cert.toMap()..remove('id'))
        .eq('id', cert.id)
        .select()
        .single();
    return Certification.fromMap(row);
  }

  @override
  Future<void> deleteCertification(String id) async {
    await _client.from('profile_certifications').delete().eq('id', id);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Projects
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<List<Project>> getProjects(String userId) async {
    final rows = await _client
        .from('profile_projects')
        .select('*, profile_project_bullets(*)')
        .eq('user_id', userId)
        .order('order_index');
    return (rows as List)
        .map((r) => Project.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Project> addProject(Project project) async {
    final row = await _client
        .from('profile_projects')
        .insert(project.toMap()..remove('id'))
        .select()
        .single();
    final newProject = Project.fromMap(row);
    if (project.bullets.isNotEmpty) {
      await _insertProjectBullets(newProject.id, project.bullets);
    }
    return (await getProjects(
      project.userId,
    )).firstWhere((p) => p.id == newProject.id);
  }

  @override
  Future<Project> updateProject(Project project) async {
    await _client
        .from('profile_projects')
        .update(project.toMap()..remove('id'))
        .eq('id', project.id);

    // Estratégia: delete + re-insert bullets (cascade limpa via FK quando deleta)
    await _client
        .from('profile_project_bullets')
        .delete()
        .eq('project_id', project.id);
    if (project.bullets.isNotEmpty) {
      await _insertProjectBullets(project.id, project.bullets);
    }
    return (await getProjects(
      project.userId,
    )).firstWhere((p) => p.id == project.id);
  }

  Future<void> _insertProjectBullets(
    String projectId,
    List<ProjectBullet> bullets,
  ) async {
    final rows = bullets.asMap().entries.map((entry) {
      final b = entry.value;
      return {
        'project_id': projectId,
        'text': b.text,
        'order_index': entry.key,
      };
    }).toList();
    await _client.from('profile_project_bullets').insert(rows);
  }

  @override
  Future<void> deleteProject(String id) async {
    await _client.from('profile_projects').delete().eq('id', id);
  }

  @override
  Future<ProjectBullet> addProjectBullet(ProjectBullet bullet) async {
    final map = bullet.toMap()..remove('id');
    final row = await _client
        .from('profile_project_bullets')
        .insert(map)
        .select()
        .single();
    return ProjectBullet.fromMap(row);
  }

  @override
  Future<ProjectBullet> updateProjectBullet(ProjectBullet bullet) async {
    final row = await _client
        .from('profile_project_bullets')
        .update(bullet.toMap()..remove('id'))
        .eq('id', bullet.id)
        .select()
        .single();
    return ProjectBullet.fromMap(row);
  }

  @override
  Future<void> deleteProjectBullet(String bulletId) async {
    await _client.from('profile_project_bullets').delete().eq('id', bulletId);
  }

  @override
  Future<void> reorderProjectBullets(
    String projectId,
    List<String> orderedIds,
  ) async {
    final futures = <Future>[];
    for (var i = 0; i < orderedIds.length; i++) {
      futures.add(
        _client
            .from('profile_project_bullets')
            .update({'order_index': i})
            .eq('id', orderedIds[i])
            .eq('project_id', projectId),
      );
    }
    await Future.wait(futures);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Interests, Awards, Coursework
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<List<Interest>> getInterests(String userId) async {
    final rows = await _client
        .from('profile_interests')
        .select()
        .eq('user_id', userId)
        .order('order_index');
    return (rows as List)
        .map((r) => Interest.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> replaceInterests(String userId, List<String> names) async {
    await _client.from('profile_interests').delete().eq('user_id', userId);
    if (names.isEmpty) return;
    await _client
        .from('profile_interests')
        .insert(
          names
              .asMap()
              .entries
              .map(
                (e) => {
                  'user_id': userId,
                  'name': e.value,
                  'order_index': e.key,
                },
              )
              .toList(),
        );
  }

  @override
  Future<List<Award>> getAwards(String userId) async {
    final rows = await _client
        .from('profile_awards')
        .select()
        .eq('user_id', userId)
        .order('order_index');
    return (rows as List)
        .map((r) => Award.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Award> addAward(Award award) async {
    final row = await _client
        .from('profile_awards')
        .insert(award.toMap()..remove('id'))
        .select()
        .single();
    return Award.fromMap(row);
  }

  @override
  Future<Award> updateAward(Award award) async {
    final row = await _client
        .from('profile_awards')
        .update(award.toMap()..remove('id'))
        .eq('id', award.id)
        .select()
        .single();
    return Award.fromMap(row);
  }

  @override
  Future<void> deleteAward(String id) async {
    await _client.from('profile_awards').delete().eq('id', id);
  }

  @override
  Future<List<Coursework>> getCoursework(String userId) async {
    final rows = await _client
        .from('profile_coursework')
        .select()
        .eq('user_id', userId)
        .order('order_index');
    return (rows as List)
        .map((r) => Coursework.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> replaceCoursework(String userId, List<String> names) async {
    await _client.from('profile_coursework').delete().eq('user_id', userId);
    if (names.isEmpty) return;
    await _client
        .from('profile_coursework')
        .insert(
          names
              .asMap()
              .entries
              .map(
                (e) => {
                  'user_id': userId,
                  'name': e.value,
                  'order_index': e.key,
                },
              )
              .toList(),
        );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Job Preferences + filhas
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<JobPreferences?> getJobPreferences(String userId) async {
    final row = await _client
        .from('profile_job_preferences')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return JobPreferences.fromMap(row);
  }

  @override
  Future<JobPreferences> upsertJobPreferences(JobPreferences prefs) async {
    final row = await _client
        .from('profile_job_preferences')
        .upsert(prefs.toMap(), onConflict: 'user_id')
        .select()
        .single();
    return JobPreferences.fromMap(row);
  }

  @override
  Future<List<DesiredTitle>> getDesiredTitles(String userId) async {
    final rows = await _client
        .from('profile_desired_titles')
        .select()
        .eq('user_id', userId)
        .order('order_index');
    return (rows as List)
        .map((r) => DesiredTitle.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> replaceDesiredTitles(
    String userId,
    List<DesiredTitle> titles,
  ) async {
    await _client.from('profile_desired_titles').delete().eq('user_id', userId);
    if (titles.isEmpty) return;
    await _client
        .from('profile_desired_titles')
        .insert(
          titles.asMap().entries.map((e) {
            final m = e.value.toMap()..remove('id');
            m['order_index'] = e.key;
            m['user_id'] = userId;
            return m;
          }).toList(),
        );
  }

  @override
  Future<List<ApplicationCountry>> getApplicationCountries(
    String userId,
  ) async {
    final rows = await _client
        .from('profile_application_countries')
        .select()
        .eq('user_id', userId);
    return (rows as List)
        .map((r) => ApplicationCountry.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> replaceApplicationCountries(
    String userId,
    List<ApplicationCountry> countries,
  ) async {
    await _client
        .from('profile_application_countries')
        .delete()
        .eq('user_id', userId);
    if (countries.isEmpty) return;
    await _client
        .from('profile_application_countries')
        .insert(
          countries.map((c) {
            final m = c.toMap()..remove('id');
            m['user_id'] = userId;
            return m;
          }).toList(),
        );
  }

  @override
  Future<List<OtherLocation>> getOtherLocations(String userId) async {
    final rows = await _client
        .from('profile_other_locations')
        .select()
        .eq('user_id', userId);
    return (rows as List)
        .map((r) => OtherLocation.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> replaceOtherLocations(
    String userId,
    List<OtherLocation> locations,
  ) async {
    await _client
        .from('profile_other_locations')
        .delete()
        .eq('user_id', userId);
    if (locations.isEmpty) return;
    await _client
        .from('profile_other_locations')
        .insert(
          locations.map((l) {
            final m = l.toMap()..remove('id');
            m['user_id'] = userId;
            return m;
          }).toList(),
        );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Replace em massa
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<void> replaceProfile(
    String userId,
    Map<String, dynamic> profileData,
  ) async {
    await _client.rpc(
      'save_profile_from_json',
      params: {'p_user_id': userId, 'p_data': profileData},
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Completeness
  // ──────────────────────────────────────────────────────────────────────

  @override
  Future<int> getCompletenessScore(String userId) async {
    final row = await _client
        .from('profile_personal')
        .select('completeness_score')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return 0;
    return (row['completeness_score'] as num?)?.toInt() ?? 0;
  }
}
