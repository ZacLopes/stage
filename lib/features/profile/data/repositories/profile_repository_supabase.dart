// ProfileRepositorySupabase — implementação usando supabase_flutter direto.
//
// RLS no banco garante que o user só vê/edita o próprio perfil
// (auth.uid() = user_id em todas as 18 tabelas).
//
// Nested reads usam PostgREST foreign tables (select('*, profile_bullets(*)')).

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/entities.dart';
import '../../domain/manual_skills_replace.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/skill_name_normalizer.dart';

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
  Future<PersonalInfo> upsertPersonal(
    PersonalInfo info, {
    Set<String> nullColumns = const {},
  }) async {
    final map = info.toMap()
      ..removeWhere((k, v) => v == null && k != 'user_id');
    // Colunas a LIMPAR de propósito (ex.: trocar de cidade zera o CEP antigo):
    // re-injeta o null DEPOIS do strip, senão o upsert parcial preservaria o
    // valor velho no banco.
    for (final c in nullColumns) {
      map[c] = null;
    }
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
    final saved = Experience.fromMap(row);
    try {
      await _reconcileExperienceBullets(saved.id, exp.bullets);
      return await _getExperience(exp.userId, saved.id);
    } catch (error, stackTrace) {
      try {
        await _client
            .from('profile_experiences')
            .delete()
            .eq('id', saved.id)
            .eq('user_id', exp.userId);
      } catch (_) {
        // Mantém o erro original; um load posterior revela o estado efetivo.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<Experience> updateExperience(Experience exp) async {
    final previous = await _getExperience(exp.userId, exp.id);
    try {
      await _client
          .from('profile_experiences')
          .update(exp.toMap()..remove('id'))
          .eq('id', exp.id)
          .eq('user_id', exp.userId);
      await _reconcileExperienceBullets(exp.id, exp.bullets);
      return await _getExperience(exp.userId, exp.id);
    } catch (_) {
      try {
        await _client
            .from('profile_experiences')
            .update(previous.toMap()..remove('id'))
            .eq('id', previous.id)
            .eq('user_id', previous.userId);
        await _reconcileExperienceBullets(previous.id, previous.bullets);
      } catch (_) {
        // Rollback best-effort; o erro original continua sendo reportado.
      }
      rethrow;
    }
  }

  Future<Experience> _getExperience(String userId, String experienceId) async {
    final row = await _client
        .from('profile_experiences')
        .select('*, profile_bullets(*)')
        .eq('id', experienceId)
        .eq('user_id', userId)
        .single();
    return Experience.fromMap(row);
  }

  /// Atualiza/insere primeiro e remove por último, preservando os UUIDs dos
  /// bullets que continuam na experiência.
  Future<void> _reconcileExperienceBullets(
    String experienceId,
    List<Bullet> desired,
  ) async {
    final rows = await _client
        .from('profile_bullets')
        .select()
        .eq('experience_id', experienceId)
        .order('order_index');
    final existing = <String, Bullet>{};
    for (final raw in rows as List) {
      final bullet = Bullet.fromMap(raw as Map<String, dynamic>);
      existing[bullet.id] = bullet;
    }
    final keptIds = <String>{};

    for (var index = 0; index < desired.length; index++) {
      final draft = desired[index];
      final text = draft.text.trim();
      if (text.isEmpty) continue;
      final current = existing[draft.id];
      if (current == null || keptIds.contains(current.id)) {
        final inserted = await addBullet(
          Bullet(
            id: '',
            experienceId: experienceId,
            text: text,
            angle: draft.angle,
            strengthScore: draft.strengthScore,
            verb: draft.verb,
            orderIndex: index,
          ),
        );
        keptIds.add(inserted.id);
        continue;
      }

      final merged = Bullet(
        id: current.id,
        experienceId: experienceId,
        text: text,
        angle: draft.angle ?? current.angle,
        strengthScore: draft.strengthScore ?? current.strengthScore,
        verb: draft.verb ?? current.verb,
        orderIndex: index,
      );
      await _client
          .from('profile_bullets')
          .update(merged.toMap()..remove('id'))
          .eq('id', current.id)
          .eq('experience_id', experienceId);
      keptIds.add(current.id);
    }

    final removedIds = existing.keys
        .where((id) => !keptIds.contains(id))
        .toList(growable: false);
    if (removedIds.isNotEmpty) {
      await _client
          .from('profile_bullets')
          .delete()
          .eq('experience_id', experienceId)
          .inFilter('id', removedIds);
    }
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
        // O editor CAS usa exatamente `order_index, id` no servidor. O
        // desempate é obrigatório porque dados legados podem compartilhar o
        // mesmo order_index; sem ele, o baseline do card pode variar e gerar
        // um `stale` falso mesmo sem escrita concorrente.
        .order('order_index', ascending: true)
        .order('id', ascending: true);
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
    final desired = normalizeSkillNames(names);
    if (desired.length > kMaxProfileSkills) {
      throw ArgumentError.value(
        desired.length,
        'names',
        'Escolha no máximo $kMaxProfileSkills habilidades.',
      );
    }
    // Gate 3.0D — replace ATÔMICO server-side: uma transação sob o advisory
    // lock por usuário, preservando IDs/metadados (category/canonical_skill_id)
    // dos itens retidos. Substitui o antigo get -> insert/update/delete
    // multi-request (janela de falha parcial). O recibo tipado falha fechado em
    // resposta malformada; erros do RPC (limite 12, duplicata legada, ACL)
    // propagam como PostgrestException e o ViewModel os trata sem falso sucesso.
    final raw = await _client.rpc(
      'replace_profile_skills_atomic_v1',
      params: {'p_user_id': userId, 'p_names': desired},
    );
    ManualSkillsReplaceReceipt.fromRpc(raw, expectedMax: desired.length);
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
    // Gate 3.0G — replace ATÔMICO server-side de interesses
    // (replace_profile_interests_atomic_v1): transação única sob o advisory
    // lock, preservando IDs dos itens retidos e autoritativo sobre a grafia.
    // Substitui o DELETE-all + INSERT-all (destrutivo, perdia IDs). O recibo
    // (genérico de replace atômico {status,count}) falha fechado em resposta
    // malformada; erros do RPC (limite 50, duplicata legada, ACL) propagam.
    final raw = await _client.rpc(
      'replace_profile_interests_atomic_v1',
      params: {'p_user_id': userId, 'p_names': names},
    );
    ManualSkillsReplaceReceipt.fromRpc(raw, expectedMax: names.length);
  }

  @override
  Future<String> casWritePersonalField(
    String userId,
    String field,
    String expected,
    String value, {
    String? expectedCountryCode,
    String? newCountryCode,
  }) async {
    // Gate 3.0H app-side — CAS server-side sob o advisory lock. 'stale' quando o
    // vivo diverge do observado (manual-recente-vence). Fail-closed: resposta
    // inesperada → 'stale' (nunca finge 'applied').
    final raw = await _client.rpc(
      'cas_write_personal_field_v1',
      params: {
        'p_user_id': userId,
        'p_field': field,
        'p_expected': expected,
        'p_value': value,
        'p_expected_country_code': expectedCountryCode,
        'p_new_country_code': newCountryCode,
      },
    );
    return raw == 'applied' ? 'applied' : 'stale';
  }

  @override
  Future<String> casWriteItemField(
    String userId,
    String kind,
    String refId,
    String field,
    String expected,
    String value,
  ) async {
    final raw = await _client.rpc(
      'cas_write_item_field_v1',
      params: {
        'p_user_id': userId,
        'p_kind': kind,
        'p_ref_id': refId,
        'p_field': field,
        'p_expected': expected,
        'p_value': value,
      },
    );
    return raw == 'applied' ? 'applied' : 'stale';
  }

  @override
  Future<String> casWriteJobPrefField(
    String userId,
    String field,
    String expected,
    String value,
  ) async {
    final raw = await _client.rpc(
      'cas_write_job_pref_field_v1',
      params: {
        'p_user_id': userId,
        'p_field': field,
        'p_expected': expected,
        'p_value': value,
      },
    );
    return raw == 'applied' ? 'applied' : 'stale';
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

  /// Substitui as disciplinas relevantes numa transação só.
  ///
  /// Era DELETE-all seguido de INSERT-all em DUAS requisições HTTP, sem
  /// transação: se a segunda falhasse (rede caindo, sessão expirando, 4xx do
  /// PostgREST) a pessoa terminava com a lista VAZIA — o apagar já tinha
  /// acontecido e não havia rollback. A janela é pequena, mas o custo dela é
  /// perder dado que a pessoa digitou.
  ///
  /// `replace_profile_coursework` já existia em produção desde a migration
  /// 20260714130000, com GRANT para `authenticated` e delegando para
  /// `_replace_simple_list`, que roda sob `pg_advisory_xact_lock` — ou seja,
  /// atômica E serializada contra as outras escritas do mesmo perfil. Não
  /// precisou de migration nova: o contrato estava lá, sem caller.
  ///
  /// Diferença de comportamento assumida: o servidor faz trim, descarta
  /// strings vazias e deduplica sem diferenciar maiúsculas — o caminho antigo
  /// gravava tudo cru. É a mesma normalização que skills, interesses e áreas
  /// já recebem pelos respectivos RPCs.
  @override
  Future<void> replaceCoursework(String userId, List<String> names) async {
    await _client.rpc(
      'replace_profile_coursework',
      params: {'p_user_id': userId, 'p_names': names},
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
    // Gate 3.0G-áreas — replace ATÔMICO com precedência de source
    // (replace_profile_desired_titles_atomic_v1): transação única sob o
    // advisory lock, preserva IDs dos itens retidos e mantém a fonte mais forte
    // por chave normalizada (nunca rebaixa uma área escolhida 'user_added' para
    // inferida). Substitui o DELETE-all + INSERT-all (destrutivo). A inferência
    // canônica (linhas 'inferred' ocultas) segue montada no domínio ANTES
    // daqui — a lista recebida já é o estado final. Recibo fail-closed; erros
    // do RPC (source inválida, duplicata legada, limite, ACL) propagam.
    final raw = await _client.rpc(
      'replace_profile_desired_titles_atomic_v1',
      params: {
        'p_user_id': userId,
        'p_titles': [
          for (final t in titles)
            {'title': t.title, 'source': t.toMap()['source']},
        ],
      },
    );
    ManualSkillsReplaceReceipt.fromRpc(raw, expectedMax: titles.length);
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

  @override
  Future<Set<String>> getGuidedProgress(String userId) async {
    final rows = await _client
        .from('profile_guided_progress')
        .select('segment')
        .eq('user_id', userId);
    return (rows as List)
        .map((r) => (r as Map<String, dynamic>)['segment'] as String)
        .toSet();
  }

  @override
  Future<void> markGuidedProgress(String userId, String segment) async {
    // ON CONFLICT (user_id, segment) DO NOTHING — idempotente.
    await _client
        .from('profile_guided_progress')
        .upsert(
          {'user_id': userId, 'segment': segment},
          onConflict: 'user_id,segment',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> clearGuidedProgress(String userId) async {
    // RLS (own rows) garante que só apaga o progresso do próprio usuário.
    await _client
        .from('profile_guided_progress')
        .delete()
        .eq('user_id', userId);
  }
}
