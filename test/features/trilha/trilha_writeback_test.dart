import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_gamification/features/profile/domain/entities/entities.dart';
import 'package:career_gamification/features/profile/domain/repositories/profile_repository.dart';
import 'package:career_gamification/features/trilha/application/trilha_draft.dart';
import 'package:career_gamification/features/trilha/application/trilha_session.dart';
import 'package:career_gamification/features/trilha/application/trilha_writeback.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';
import 'package:career_gamification/features/trilha/domain/guided_skills_write.dart';

/// Repositório falso: registra o que foi gravado; lança em métodos não usados.
class _FakeRepo implements ProfileRepository {
  List<Skill> skills = [];
  List<Language> languages = [];
  List<DesiredTitle> desired = [];
  JobPreferences? prefs;
  PersonalInfo? personal;
  bool failGetSkills = false;
  bool failGetLanguages = false;

  List<String>? replacedSkills;
  List<DesiredTitle>? replacedDesired;
  JobPreferences? upsertedPrefs;
  PersonalInfo? upsertedPersonal;
  final List<Language> addedLangs = [];

  @override
  Future<List<Skill>> getSkills(String userId) async {
    if (failGetSkills) throw StateError('skills_read_failed');
    return skills;
  }

  @override
  Future<void> replaceSkills(String userId, List<String> names) async {
    replacedSkills = names;
  }

  @override
  Future<List<Language>> getLanguages(String userId) async {
    if (failGetLanguages) throw StateError('languages_read_failed');
    return languages;
  }

  @override
  Future<Language> addLanguage(Language l) async {
    addedLangs.add(l);
    languages = [...languages, l];
    return l;
  }

  Language? updatedLanguage;
  @override
  Future<Language> updateLanguage(Language l) async {
    updatedLanguage = l;
    languages = languages.map((x) => x.name == l.name ? l : x).toList();
    return l;
  }

  @override
  Future<List<DesiredTitle>> getDesiredTitles(String userId) async => desired;
  @override
  Future<void> replaceDesiredTitles(String userId, List<DesiredTitle> t) async {
    replacedDesired = t;
  }

  @override
  Future<JobPreferences?> getJobPreferences(String userId) async => prefs;
  @override
  Future<JobPreferences> upsertJobPreferences(JobPreferences p) async {
    upsertedPrefs = p;
    prefs = p; // persiste: a próxima leitura vê o upsert (merge de campos)
    return p;
  }

  @override
  Future<PersonalInfo?> getPersonal(String userId) async => personal;
  @override
  Future<PersonalInfo> upsertPersonal(
    PersonalInfo p, {
    Set<String> nullColumns = const {},
  }) async {
    upsertedPersonal = p;
    return p;
  }

  final List<Experience> addedExps = [];
  final List<Bullet> addedBullets = [];
  int _expSeq = 0;
  int experienceInsertCalls = 0;
  bool failExperienceAfterPersistOnce = false;
  bool failBulletAfterPersistOnce = false;
  @override
  Future<List<Experience>> getExperiences(String userId) async => addedExps;

  @override
  Future<Experience> addExperience(Experience e) async {
    experienceInsertCalls++;
    final experienceId = 'exp${_expSeq++}';
    final bullets = e.bullets
        .asMap()
        .entries
        .map(
          (entry) => entry.value.copyWith(
            id: 'bullet${addedBullets.length + entry.key}',
            experienceId: experienceId,
            orderIndex: entry.key,
          ),
        )
        .toList();
    final saved = Experience(
      id: experienceId,
      userId: e.userId,
      title: e.title,
      company: e.company,
      kind: e.kind,
      startDate: e.startDate,
      endDate: e.endDate,
      isCurrent: e.isCurrent,
      needsReview: e.needsReview,
      bullets: bullets,
    );
    addedExps.add(saved);
    addedBullets.addAll(bullets);
    if (failExperienceAfterPersistOnce) {
      failExperienceAfterPersistOnce = false;
      throw StateError('ambiguous_experience_write');
    }
    return saved;
  }

  @override
  Future<Bullet> addBullet(Bullet b) async {
    final saved = b.copyWith(id: 'bullet${addedBullets.length}');
    addedBullets.add(saved);
    final index = addedExps.indexWhere((exp) => exp.id == b.experienceId);
    if (index >= 0) {
      addedExps[index] = addedExps[index].copyWith(
        bullets: [...addedExps[index].bullets, saved],
      );
    }
    if (failBulletAfterPersistOnce) {
      failBulletAfterPersistOnce = false;
      throw StateError('ambiguous_bullet_write');
    }
    return saved;
  }

  final List<Certification> addedCerts = [];
  int certificationInsertCalls = 0;
  bool failCertificationAfterPersistOnce = false;
  @override
  Future<List<Certification>> getCertifications(String userId) async =>
      addedCerts;

  @override
  Future<Certification> addCertification(Certification c) async {
    addedCerts.add(c);
    certificationInsertCalls++;
    if (failCertificationAfterPersistOnce) {
      failCertificationAfterPersistOnce = false;
      throw StateError('ambiguous_certification_write');
    }
    return c;
  }

  final List<Award> addedAwards = [];
  int awardInsertCalls = 0;
  bool failAwardAfterPersistOnce = false;
  @override
  Future<List<Award>> getAwards(String userId) async => addedAwards;

  @override
  Future<Award> addAward(Award a) async {
    addedAwards.add(a);
    awardInsertCalls++;
    if (failAwardAfterPersistOnce) {
      failAwardAfterPersistOnce = false;
      throw StateError('ambiguous_award_write');
    }
    return a;
  }

  final List<Project> addedProjects = [];
  final List<ProjectBullet> addedProjectBullets = [];
  Project? updatedProject;
  int _projSeq = 0;
  int projectInsertCalls = 0;
  bool failProjectAfterPersistOnce = false;
  bool failProjectBulletAfterPersistOnce = false;
  @override
  Future<List<Project>> getProjects(String userId) async => addedProjects;

  @override
  Future<Project> addProject(Project p) async {
    projectInsertCalls++;
    final projectId = 'proj${_projSeq++}';
    final bullets = p.bullets
        .asMap()
        .entries
        .map(
          (entry) => entry.value.copyWith(
            id: 'projectBullet${addedProjectBullets.length + entry.key}',
            projectId: projectId,
            orderIndex: entry.key,
          ),
        )
        .toList();
    final saved = p.copyWith(id: projectId, bullets: bullets);
    addedProjects.add(saved);
    addedProjectBullets.addAll(bullets);
    if (failProjectAfterPersistOnce) {
      failProjectAfterPersistOnce = false;
      throw StateError('ambiguous_project_write');
    }
    return saved;
  }

  @override
  Future<ProjectBullet> addProjectBullet(ProjectBullet b) async {
    final saved = b.copyWith(id: 'projectBullet${addedProjectBullets.length}');
    addedProjectBullets.add(saved);
    final index = addedProjects.indexWhere((p) => p.id == b.projectId);
    if (index >= 0) {
      addedProjects[index] = addedProjects[index].copyWith(
        bullets: [...addedProjects[index].bullets, saved],
      );
    }
    if (failProjectBulletAfterPersistOnce) {
      failProjectBulletAfterPersistOnce = false;
      throw StateError('ambiguous_project_bullet_write');
    }
    return saved;
  }

  @override
  Future<Project> updateProject(Project p) async {
    updatedProject = p;
    return p;
  }

  List<Interest> interests = [];
  List<String>? replacedInterests;
  @override
  Future<List<Interest>> getInterests(String userId) async => interests;
  @override
  Future<void> replaceInterests(String userId, List<String> names) async {
    replacedInterests = names;
  }

  List<Education> educations = [];
  Education? addedEducation;
  Education? updatedEducation;
  int educationInsertCalls = 0;
  int educationUpdateCalls = 0;
  bool failEducationAfterPersistOnce = false;
  @override
  Future<List<Education>> getEducation(String userId) async => educations;
  @override
  Future<Education> addEducation(Education e) async {
    educationInsertCalls++;
    final saved = e.id.isEmpty ? e.copyWith(id: 'edu${educations.length}') : e;
    addedEducation = saved;
    educations = [...educations, saved];
    if (failEducationAfterPersistOnce) {
      failEducationAfterPersistOnce = false;
      throw StateError('ambiguous_education_write');
    }
    return saved;
  }

  @override
  Future<Education> updateEducation(Education e) async {
    educationUpdateCalls++;
    updatedEducation = e;
    educations = educations.map((x) => x.id == e.id ? e : x).toList();
    return e;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} não deveria ser chamado');
}

/// Spy do writer aditivo de skills (Gate 3.0C): registra cada `mergeSkills` e
/// devolve um recibo válido por default. `throwOnMerge` simula falha do RPC
/// (ex.: limite de 12) para provar o comportamento fail-closed.
class _SpyGuidedSkillsWriter implements GuidedSkillsWriter {
  final List<List<String>> mergedNames = [];
  final List<String> mergedUserIds = [];
  Object? throwOnMerge;
  int calls = 0;

  @override
  Future<GuidedSkillsMergeReceipt> mergeSkills({
    required String userId,
    required List<String> names,
  }) async {
    calls++;
    mergedUserIds.add(userId);
    mergedNames.add(List<String>.from(names));
    if (throwOnMerge != null) throw throwOnMerge!;
    return GuidedSkillsMergeReceipt.fromRpc(<String, dynamic>{
      'status': names.isEmpty ? 'noop' : 'applied',
      'inserted': names.length,
      'updated': 0,
      'changed': names.length,
    });
  }
}

void main() {
  late _FakeRepo repo;
  late _SpyGuidedSkillsWriter guided;
  late TrilhaWriteback wb;

  setUp(() {
    repo = _FakeRepo();
    guided = _SpyGuidedSkillsWriter();
    wb = TrilhaWriteback(repo, 'u1', guidedSkillsWriter: guided);
  });

  StepAnswer choice(String stepId, List<String> ids) => StepAnswer.choice(
    stepId,
    ids.map((id) => StepOption(id: id, label: id)).toList(),
  );

  group('leituras estritas dos editores do Assistente', () {
    test('skills propaga falha em vez de fingir lista vazia', () async {
      repo.failGetSkills = true;
      await expectLater(
        loadAssistSkills('u1', repository: repo),
        throwsStateError,
      );
    });

    test('idiomas propaga falha em vez de fingir lista vazia', () async {
      repo.failGetLanguages = true;
      await expectLater(
        loadAssistLanguages('u1', repository: repo),
        throwsStateError,
      );
    });
  });

  group('TrilhaWriteback', () {
    // Gate 3.0C — skills da coleta guiada usam o contrato aditivo
    // `merge_guided_profile_list`, não mais `replaceSkills`.
    test(
      'skills: manda a seleção ao merge aditivo (sem replaceSkills)',
      () async {
        await wb.save(choice('gap.skills', ['Excel', 'Python']));
        expect(guided.mergedNames, [
          ['Excel', 'Python'],
        ]);
        expect(guided.mergedUserIds, ['u1']);
        expect(repo.replacedSkills, isNull); // TOCTOU removido
      },
    );

    test('skills: não faz pré-leitura — dedup é server-side sob lock', () async {
      // Mesmo com 'Excel' já existente, o cliente NÃO pré-lê nem filtra: manda a
      // seleção guiada e o merge aditivo dedup contra o estado vivo no servidor.
      repo.skills = [const Skill(id: '1', userId: 'u1', name: 'Excel')];
      await wb.save(choice('gap.skills', ['Excel', 'Python']));
      expect(guided.mergedNames, [
        ['Excel', 'Python'],
      ]);
      expect(repo.replacedSkills, isNull);
    });

    test('gap.skills.more (sugestão da IA) usa o mesmo adapter', () async {
      await wb.save(choice('gap.skills.more', ['Power BI', 'SQL']));
      expect(guided.mergedNames, [
        ['Power BI', 'SQL'],
      ]);
      expect(repo.replacedSkills, isNull);
    });

    test('gap.skills.more.1 (lote numerado) usa o mesmo adapter', () async {
      await wb.save(choice('gap.skills.more.1', ['Go']));
      expect(guided.mergedNames, [
        ['Go'],
      ]);
    });

    test('skills: seleção só de vazios → não chama o writer', () async {
      await wb.save(choice('gap.skills', ['', '   ']));
      expect(guided.calls, 0);
      expect(repo.replacedSkills, isNull);
    });

    test(
      'skills: falha do RPC propaga (fail-closed, não vira sucesso)',
      () async {
        guided.throwOnMerge = StateError('too_many_items');
        await expectLater(
          wb.save(choice('gap.skills', ['Excel'])),
          throwsStateError,
        );
      },
    );

    test('modalidade: mapeia ids → WorkMode', () async {
      await wb.save(choice('gap.workmode', ['remote', 'hybrid']));
      expect(repo.upsertedPrefs?.workMode, [WorkMode.remote, WorkMode.hybrid]);
    });

    test('tipo de vaga: mapeia ids → JobType', () async {
      await wb.save(choice('gap.jobtype', ['internship']));
      expect(repo.upsertedPrefs?.jobTypes, [JobType.internship]);
    });

    test('cargo desejado: grava em desired_position', () async {
      await wb.save(
        StepAnswer.text('gap.desired_position', 'Desenvolvedor Front-end'),
      );
      expect(repo.upsertedPrefs?.desiredPosition, 'Desenvolvedor Front-end');
    });

    test('cargo desejado: pulado (vazio) → não grava', () async {
      await wb.save(StepAnswer.text('gap.desired_position', ''));
      expect(repo.upsertedPrefs, isNull);
    });

    test('fit cultural: grava o id da opção em company_stage/work_environment/'
        'work_style (escolha única)', () async {
      await wb.save(choice('gap.company_stage', ['startup']));
      expect(repo.upsertedPrefs?.companyStage, 'startup');
      await wb.save(choice('gap.work_environment', ['dynamic']));
      expect(repo.upsertedPrefs?.workEnvironment, 'dynamic');
      await wb.save(choice('gap.work_style', ['autonomy']));
      final p = repo.upsertedPrefs;
      expect(p?.workStyle, 'autonomy');
      // Os anteriores não se perderam (copyWith preserva).
      expect(p?.companyStage, 'startup');
      expect(p?.workEnvironment, 'dynamic');
    });

    test('áreas: grava como desired titles (userAdded)', () async {
      await wb.save(choice('gap.area', ['Tecnologia', 'Produto']));
      expect(
        repo.replacedDesired?.map((t) => t.title),
        containsAll(['Tecnologia', 'Produto']),
      );
      expect(
        repo.replacedDesired?.every(
          (t) => t.source == DesiredTitleSource.userAdded,
        ),
        true,
      );
    });

    test('cidade: separa "Cidade, UF" em city + state (retrocompat)', () async {
      await wb.save(StepAnswer.text('gap.city', 'São Paulo, SP'));
      expect(repo.upsertedPersonal?.locationCity, 'São Paulo');
      expect(repo.upsertedPersonal?.locationState, 'SP');
    });

    test('cidade canônica: decodifica "Cidade|UF" do typeahead IBGE', () async {
      await wb.save(
        StepAnswer.pick(
          'gap.city',
          label: 'São Paulo - SP',
          value: 'São Paulo|SP',
        ),
      );
      expect(repo.upsertedPersonal?.locationCity, 'São Paulo');
      expect(repo.upsertedPersonal?.locationState, 'SP');
    });

    test('idiomas: insere os novos e pula "none"', () async {
      await wb.save(choice('gap.languages', ['none', 'Inglês']));
      expect(repo.addedLangs.map((l) => l.name), ['Inglês']);
    });

    test(
      'idiomas: TODOS entram sem nível (preenchido no passo seguinte)',
      () async {
        await wb.save(choice('gap.languages', ['Português', 'Inglês']));
        // Inclusive português — o usuário informa o nível de cada um no lang.level.
        expect(
          repo.addedLangs.firstWhere((l) => l.name == 'Português').proficiency,
          isNull,
        );
        expect(
          repo.addedLangs.firstWhere((l) => l.name == 'Inglês').proficiency,
          isNull,
        );
      },
    );

    test(
      'nível de idioma: atualiza a proficiência do idioma existente',
      () async {
        repo.languages = [
          const Language(id: '1', userId: 'u1', name: 'Inglês'),
        ];
        await wb.save(choice('lang.level.Inglês', ['advanced']));
        expect(repo.updatedLanguage?.name, 'Inglês');
        expect(repo.updatedLanguage?.proficiency, LanguageProficiency.advanced);
      },
    );

    test('intro (e desconhecidos): no-op, nada gravado', () async {
      await wb.save(choice('intro', ['go']));
      expect(guided.calls, 0);
      expect(repo.replacedSkills, isNull);
      expect(repo.upsertedPrefs, isNull);
      expect(repo.upsertedPersonal, isNull);
      expect(repo.addedLangs, isEmpty);
    });

    test(
      'experiência (por tipo): acumula campos, grava com kind + bullet',
      () async {
        await wb.save(StepAnswer.text('exp.0.estagio.company', 'Magalu'));
        await wb.save(StepAnswer.text('exp.0.estagio.role', 'Estagiário'));
        await wb.save(StepAnswer.monthYear('exp.0.estagio.start', 2024, 3));
        await wb.save(choice('exp.0.estagio.current', ['no']));
        await wb.save(StepAnswer.monthYear('exp.0.estagio.end', 2024, 12));
        // Ainda não gravou — falta o "o que fazia".
        expect(repo.addedExps, isEmpty);

        await wb.save(
          StepAnswer.text('exp.0.estagio.ofazia', 'Cuidava das redes sociais'),
        );
        expect(repo.addedExps, hasLength(1));
        final e = repo.addedExps.first;
        expect(e.company, 'Magalu');
        expect(e.title, 'Estagiário');
        expect(e.kind, 'estagio'); // tipo veio do id
        expect(e.startDate, DateTime(2024, 3, 1));
        expect(e.endDate, DateTime(2024, 12, 1));
        expect(e.isCurrent, false);
        expect(repo.addedBullets, hasLength(1));
        expect(repo.addedBullets.first.text, 'Cuidava das redes sociais');
        expect(repo.addedBullets.first.experienceId, e.id);
      },
    );

    test('experiência "outro": o nome do tipo (label) vira o kind', () async {
      await wb.save(StepAnswer.text('exp.0.outro.label', 'Intercâmbio'));
      await wb.save(StepAnswer.text('exp.0.outro.company', 'Univ. de Toronto'));
      await wb.save(StepAnswer.text('exp.0.outro.role', 'Pesquisador'));
      await wb.save(StepAnswer.monthYear('exp.0.outro.start', 2023, 8));
      await wb.save(choice('exp.0.outro.current', ['yes']));
      await wb.save(StepAnswer.text('exp.0.outro.ofazia', 'Fiz pesquisa'));
      final e = repo.addedExps.single;
      expect(e.kind, 'Intercâmbio'); // NÃO 'outro' — o nome livre é o kind
      expect(e.company, 'Univ. de Toronto');
      expect(e.title, 'Pesquisador');
    });

    test('experiência atual: sem data de fim, isCurrent true', () async {
      await wb.save(StepAnswer.text('exp.0.emprego.company', 'Stage'));
      await wb.save(StepAnswer.text('exp.0.emprego.role', 'Dev'));
      await wb.save(StepAnswer.monthYear('exp.0.emprego.start', 2025, 1));
      await wb.save(choice('exp.0.emprego.current', ['yes']));
      await wb.save(StepAnswer.text('exp.0.emprego.ofazia', 'Codo bastante'));
      final e = repo.addedExps.single;
      expect(e.isCurrent, true);
      expect(e.endDate, isNull);
      expect(e.kind, 'emprego');
    });

    test(
      'exp.gate e exp.more (seletor de tipos): no-op (controle de fluxo)',
      () async {
        await wb.save(choice('exp.gate', ['estagio', 'voluntariado']));
        await wb.save(choice('exp.more', const <String>[]));
        expect(repo.addedExps, isEmpty);
        expect(repo.addedBullets, isEmpty);
      },
    );

    test(
      'experiência incompleta (sem cargo): terminal falha explicitamente',
      () async {
        await wb.save(StepAnswer.text('exp.0.estagio.company', 'Magalu'));
        await wb.save(StepAnswer.monthYear('exp.0.estagio.start', 2024, 3));
        await expectLater(
          wb.save(StepAnswer.text('exp.0.estagio.ofazia', 'algo')),
          throwsA(isA<StateError>()),
        );
        expect(repo.addedExps, isEmpty);
      },
    );

    test('experiência: falha após persistir + retry não duplica', () async {
      await wb.save(StepAnswer.text('exp.0.estagio.company', 'Stage'));
      await wb.save(StepAnswer.text('exp.0.estagio.role', 'Produto'));
      await wb.save(StepAnswer.monthYear('exp.0.estagio.start', 2025, 1));
      await wb.save(choice('exp.0.estagio.current', ['yes']));
      repo.failExperienceAfterPersistOnce = true;
      final terminal = StepAnswer.text(
        'exp.0.estagio.ofazia',
        'Conduzi entrevistas',
      );

      await expectLater(wb.save(terminal), throwsA(isA<StateError>()));
      await wb.save(terminal);

      expect(repo.experienceInsertCalls, 1);
      expect(repo.addedExps, hasLength(1));
      expect(repo.addedBullets, hasLength(1));
    });

    test('experiência: pai parcial recebe somente o bullet faltante', () async {
      repo.addedExps.add(
        Experience(
          id: 'partial-exp',
          userId: 'u1',
          title: 'Produto',
          company: 'Stage',
          kind: 'estagio',
          startDate: DateTime(2025, 1, 1),
          isCurrent: true,
        ),
      );
      await wb.save(StepAnswer.text('exp.0.estagio.company', ' stage '));
      await wb.save(StepAnswer.text('exp.0.estagio.role', 'PRODUTO'));
      await wb.save(StepAnswer.monthYear('exp.0.estagio.start', 2025, 1));
      await wb.save(choice('exp.0.estagio.current', ['yes']));
      repo.failBulletAfterPersistOnce = true;
      final terminal = StepAnswer.text(
        'exp.0.estagio.ofazia',
        'Conduzi entrevistas',
      );
      await expectLater(wb.save(terminal), throwsA(isA<StateError>()));
      await wb.save(terminal);

      expect(repo.experienceInsertCalls, 0);
      expect(repo.addedExps, hasLength(1));
      expect(repo.addedBullets, hasLength(1));
      expect(repo.addedExps.single.bullets.single.text, 'Conduzi entrevistas');
    });

    test('linkedin: normaliza (prefixa https) e não descarta', () async {
      await wb.save(StepAnswer.text('linkedin.url', 'linkedin.com/in/zac'));
      expect(repo.upsertedPersonal?.linkedinUrl, 'https://linkedin.com/in/zac');
    });

    test(
      'certificação: grava nome + emissor + data no passo terminal (date)',
      () async {
        await wb.save(StepAnswer.text('cert.0.name', 'TOEFL'));
        await wb.save(StepAnswer.text('cert.0.issuer', 'ETS'));
        expect(repo.addedCerts, isEmpty); // só grava no último passo (date)
        await wb.save(StepAnswer.monthYear('cert.0.date', 2024, 6));
        final c = repo.addedCerts.single;
        expect(c.name, 'TOEFL');
        expect(c.issuer, 'ETS');
        expect(c.date, DateTime(2024, 6, 1));
      },
    );

    test(
      'certificação: emissor/data opcionais (pulados) → grava só o nome',
      () async {
        await wb.save(StepAnswer.text('cert.0.name', 'Google Ads'));
        await wb.save(StepAnswer.text('cert.0.issuer', '')); // pulou
        await wb.save(StepAnswer.text('cert.0.date', '')); // pulou
        final c = repo.addedCerts.single;
        expect(c.name, 'Google Ads');
        expect(c.issuer, isNull);
        expect(c.date, isNull);
      },
    );

    test('certificação: falha após persistir + retry não duplica', () async {
      await wb.save(StepAnswer.text('cert.0.name', 'TOEFL'));
      await wb.save(StepAnswer.text('cert.0.issuer', 'ETS'));
      repo.failCertificationAfterPersistOnce = true;
      final terminal = StepAnswer.monthYear('cert.0.date', 2024, 6);

      await expectLater(wb.save(terminal), throwsA(isA<StateError>()));
      await wb.save(terminal);
      expect(repo.certificationInsertCalls, 1);
      expect(repo.addedCerts, hasLength(1));
    });

    test('certificação sem nome: terminal falha explicitamente', () async {
      await expectLater(
        wb.save(StepAnswer.text('cert.0.date', '')),
        throwsA(isA<StateError>()),
      );
      expect(repo.addedCerts, isEmpty);
    });

    test('conquista: grava nome + data no passo terminal (date)', () async {
      await wb.save(StepAnswer.text('award.0.name', '1º lugar Hackathon USP'));
      expect(repo.addedAwards, isEmpty); // só grava no terminal (date)
      await wb.save(StepAnswer.monthYear('award.0.date', 2025, 3));
      final a = repo.addedAwards.single;
      expect(a.name, '1º lugar Hackathon USP');
      expect(a.date, DateTime(2025, 3, 1));
    });

    test('conquista: data opcional (pulada) → grava só o nome', () async {
      await wb.save(StepAnswer.text('award.0.name', 'Bolsa de mérito'));
      await wb.save(StepAnswer.text('award.0.date', '')); // pulou
      final a = repo.addedAwards.single;
      expect(a.name, 'Bolsa de mérito');
      expect(a.date, isNull);
    });

    test('conquista: falha após persistir + retry não duplica', () async {
      await wb.save(StepAnswer.text('award.0.name', 'Bolsa de mérito'));
      repo.failAwardAfterPersistOnce = true;
      final terminal = StepAnswer.text('award.0.date', '');

      await expectLater(wb.save(terminal), throwsA(isA<StateError>()));
      await wb.save(terminal);
      expect(repo.awardInsertCalls, 1);
      expect(repo.addedAwards, hasLength(1));
    });

    test('conquista sem nome: terminal falha explicitamente', () async {
      await expectLater(
        wb.save(StepAnswer.text('award.0.date', '')),
        throwsA(isA<StateError>()),
      );
      expect(repo.addedAwards, isEmpty);
    });

    test('conquista: gate "não" e .more são no-op', () async {
      await wb.save(choice('award.gate', ['no']));
      await wb.save(choice('award.0.more', ['no']));
      expect(repo.addedAwards, isEmpty);
    });

    test('gates (cert/linkedin) e .more: no-op de controle', () async {
      await wb.save(choice('cert.gate', ['yes']));
      await wb.save(choice('linkedin.gate', ['yes']));
      await wb.save(choice('cert.0.more', ['no']));
      expect(repo.addedCerts, isEmpty);
      expect(repo.upsertedPersonal, isNull);
    });

    test(
      'projeto: grava ATÔMICO no fim (link) — início + encerrado (data fim)',
      () async {
        await wb.save(StepAnswer.text('project.0.name', 'App de finanças'));
        await wb.save(
          StepAnswer.text('project.0.what', 'App pra controlar gastos'),
        );
        await wb.save(
          StepAnswer.text('project.0.did', 'Programei em Flutter sozinho'),
        );
        await wb.save(
          StepAnswer.monthYear('project.0.when', 2024, 6),
        ); // início
        await wb.save(
          StepAnswer.choice('project.0.current', [
            const StepOption(id: 'no', label: 'Não, encerrei'),
          ]),
        );
        await wb.save(StepAnswer.monthYear('project.0.end', 2024, 12)); // fim
        expect(repo.addedProjects, isEmpty); // ainda NÃO salvou (só no link)

        await wb.save(StepAnswer.text('project.0.link', 'github.com/x/app'));
        // Agora grava tudo de uma vez:
        expect(repo.addedProjects.map((p) => p.name), ['App de finanças']);
        expect(repo.addedProjects.first.context, 'App pra controlar gastos');
        expect(repo.addedProjects.first.website, 'github.com/x/app');
        expect(repo.addedProjects.first.startDate, DateTime(2024, 6, 1));
        expect(repo.addedProjects.first.endDate, DateTime(2024, 12, 1));
        expect(repo.addedProjects.first.isCurrent, isFalse);
        expect(repo.addedProjectBullets.map((b) => b.text), [
          'Programei em Flutter sozinho',
        ]);
      },
    );

    test(
      'projeto: ainda em andamento → isCurrent=true, sem data de fim',
      () async {
        await wb.save(StepAnswer.text('project.0.name', 'Side project'));
        await wb.save(StepAnswer.text('project.0.what', 'Um app pessoal'));
        await wb.save(
          StepAnswer.text('project.0.did', 'Desenvolvi o aplicativo'),
        );
        await wb.save(StepAnswer.monthYear('project.0.when', 2025, 1));
        await wb.save(
          StepAnswer.choice('project.0.current', [
            const StepOption(id: 'yes', label: 'Sim, ainda'),
          ]),
        );
        await wb.save(StepAnswer.text('project.0.link', ''));
        expect(repo.addedProjects.first.startDate, DateTime(2025, 1, 1));
        expect(repo.addedProjects.first.isCurrent, isTrue);
        expect(repo.addedProjects.first.endDate, isNull);
      },
    );

    test(
      'projeto: sair ANTES do link NÃO salva (re-pergunta na volta)',
      () async {
        await wb.save(StepAnswer.text('project.0.name', 'App'));
        await wb.save(StepAnswer.text('project.0.what', 'algo'));
        await wb.save(StepAnswer.text('project.0.did', 'fiz X'));
        // Usuário fecha aqui (na data) — nada foi gravado ainda.
        expect(repo.addedProjects, isEmpty);
        expect(repo.addedProjectBullets, isEmpty);
      },
    );

    test(
      'projeto: pular data e link grava mesmo assim (sem data/website)',
      () async {
        await wb.save(StepAnswer.text('project.0.name', 'TCC'));
        await wb.save(StepAnswer.text('project.0.what', 'Pesquisa sobre X'));
        await wb.save(StepAnswer.text('project.0.did', 'Escrevi e apresentei'));
        await wb.save(
          const StepAnswer(
            stepId: 'project.0.when',
            value: '',
            displayText: 'Pular',
          ),
        );
        await wb.save(choice('project.0.current', ['yes']));
        await wb.save(
          const StepAnswer(
            stepId: 'project.0.link',
            value: '',
            displayText: 'Pular',
          ),
        );
        expect(repo.addedProjects, hasLength(1));
        expect(repo.addedProjects.first.website, isNull);
        expect(repo.addedProjects.first.endDate, isNull);
      },
    );

    test('projeto: falha após persistir + retry não duplica', () async {
      await wb.save(StepAnswer.text('project.0.name', 'Portal Stage'));
      await wb.save(StepAnswer.text('project.0.what', 'Produto interno'));
      await wb.save(StepAnswer.text('project.0.did', 'Implementei o feed'));
      await wb.save(choice('project.0.current', ['yes']));
      repo.failProjectAfterPersistOnce = true;
      final terminal = StepAnswer.text('project.0.link', 'stage.app');

      await expectLater(wb.save(terminal), throwsA(isA<StateError>()));
      await wb.save(terminal);
      expect(repo.projectInsertCalls, 1);
      expect(repo.addedProjects, hasLength(1));
      expect(repo.addedProjectBullets, hasLength(1));
    });

    test('projeto: pai parcial recebe somente o bullet faltante', () async {
      repo.addedProjects.add(
        const Project(
          id: 'partial-project',
          userId: 'u1',
          name: 'Portal Stage',
          context: 'Produto interno',
          website: 'stage.app',
          isCurrent: true,
        ),
      );
      await wb.save(StepAnswer.text('project.0.name', 'portal stage'));
      await wb.save(StepAnswer.text('project.0.what', ' Produto interno '));
      await wb.save(StepAnswer.text('project.0.did', 'Implementei o feed'));
      await wb.save(choice('project.0.current', ['yes']));
      repo.failProjectBulletAfterPersistOnce = true;
      final terminal = StepAnswer.text('project.0.link', 'STAGE.APP');
      await expectLater(wb.save(terminal), throwsA(isA<StateError>()));
      await wb.save(terminal);

      expect(repo.projectInsertCalls, 0);
      expect(repo.addedProjects, hasLength(1));
      expect(repo.addedProjectBullets, hasLength(1));
      expect(
        repo.addedProjects.single.bullets.single.text,
        'Implementei o feed',
      );
    });

    test('projeto sem nome: terminal falha explicitamente', () async {
      await expectLater(
        wb.save(StepAnswer.text('project.0.link', '')),
        throwsA(isA<StateError>()),
      );
      expect(repo.addedProjects, isEmpty);
    });

    test('project.gate e .more: no-op de controle', () async {
      await wb.save(choice('project.gate', ['yes']));
      await wb.save(choice('project.0.more', ['no']));
      expect(repo.addedProjects, isEmpty);
    });

    test('disponibilidade: grava o id da opção em profile_personal', () async {
      await wb.save(choice('gap.availability', ['within_month']));
      expect(repo.upsertedPersonal?.availability, 'within_month');
    });

    test('interesses: grava os temas escolhidos (merge dedup)', () async {
      repo.interests = [
        const Interest(id: '1', userId: 'u1', name: 'Tecnologia'),
      ];
      await wb.save(
        choice('gap.interests', ['Tecnologia', 'Sustentabilidade']),
      );
      // Tecnologia já existe → não duplica; só adiciona Sustentabilidade.
      expect(repo.replacedInterests, ['Tecnologia', 'Sustentabilidade']);
    });

    test('interests.gate: no-op de controle', () async {
      await wb.save(choice('interests.gate', ['yes']));
      expect(repo.replacedInterests, isNull);
    });

    test(
      'educação faculdade: …→semestre→formatura grava college (endDate)',
      () async {
        await wb.save(choice('gap.edu.moment', ['in_college']));
        await wb.save(StepAnswer.text('gap.edu.institution', 'USP'));
        await wb.save(StepAnswer.text('gap.edu.course', 'Administração'));
        await wb.save(choice('gap.edu.semester', ['5']));
        expect(
          repo.addedEducation,
          isNull,
        ); // só grava no último passo (formatura)

        await wb.save(choice('gap.edu.graduation', ['2027']));
        final e = repo.addedEducation!;
        expect(e.educationLevel, 'college');
        expect(e.educationStatus, 'studying');
        expect(e.institution, 'USP');
        expect(e.currentSemester, 5);
        expect(e.endDate, DateTime(2027, 12, 1)); // previsão de formatura
        expect(e.majors.map((m) => m.name), ['Administração']);
      },
    );

    test('educação: "ainda não sei" a formatura → grava sem endDate', () async {
      await wb.save(choice('gap.edu.moment', ['in_college']));
      await wb.save(StepAnswer.text('gap.edu.institution', 'USP'));
      await wb.save(StepAnswer.text('gap.edu.course', 'Adm'));
      await wb.save(choice('gap.edu.semester', ['5']));
      await wb.save(choice('gap.edu.graduation', ['unsure']));
      expect(repo.addedEducation, isNotNull);
      expect(repo.addedEducation!.endDate, isNull);
    });

    test('educação ensino médio: momento→escola→ano grava school', () async {
      await wb.save(choice('gap.edu.moment', ['in_school']));
      await wb.save(StepAnswer.text('gap.edu.school', 'Colégio X'));
      await wb.save(choice('gap.edu.schoolyear', ['2']));
      final e = repo.addedEducation!;
      expect(e.educationLevel, 'school');
      expect(e.currentSchoolYear, 2);
      expect(e.institution, 'Colégio X');
    });

    test('educação trancada: status paused', () async {
      await wb.save(choice('gap.edu.moment', ['college_paused']));
      await wb.save(StepAnswer.text('gap.edu.institution', 'PUC'));
      await wb.save(StepAnswer.text('gap.edu.course', 'Direito'));
      await wb.save(choice('gap.edu.semester', ['3']));
      await wb.save(choice('gap.edu.graduation', ['2026']));
      expect(repo.addedEducation!.educationStatus, 'paused');
    });

    test(
      'educação UPSERT: atualiza college existente (rasa do import) sem duplicar',
      () async {
        repo.educations = [
          const Education(
            id: 'e1',
            userId: 'u1',
            institution: 'USP',
            educationLevel: 'college',
          ),
        ];
        await wb.save(choice('gap.edu.moment', ['in_college']));
        await wb.save(StepAnswer.text('gap.edu.institution', 'USP'));
        await wb.save(StepAnswer.text('gap.edu.course', 'Engenharia'));
        await wb.save(choice('gap.edu.semester', ['7']));
        await wb.save(choice('gap.edu.graduation', ['2026']));
        expect(repo.addedEducation, isNull); // não criou nova
        expect(repo.updatedEducation?.id, 'e1'); // atualizou a existente
        expect(repo.updatedEducation?.currentSemester, 7);
        expect(repo.updatedEducation?.majors.map((m) => m.name), [
          'Engenharia',
        ]);
      },
    );

    test('educação: falha após persistir + retry não duplica', () async {
      await wb.save(choice('gap.edu.moment', ['in_college']));
      await wb.save(StepAnswer.text('gap.edu.institution', 'USP'));
      await wb.save(StepAnswer.text('gap.edu.course', 'Administração'));
      await wb.save(choice('gap.edu.semester', ['5']));
      repo.failEducationAfterPersistOnce = true;
      final terminal = choice('gap.edu.graduation', ['2027']);

      await expectLater(wb.save(terminal), throwsA(isA<StateError>()));
      await wb.save(terminal);
      expect(repo.educationInsertCalls, 1);
      expect(repo.educationUpdateCalls, 0);
      expect(repo.educations, hasLength(1));
    });

    test('educação parcial é reparada sem criar outra', () async {
      repo.educations = [
        const Education(
          id: 'partial-education',
          userId: 'u1',
          institution: 'USP',
          educationLevel: 'college',
          educationStatus: 'studying',
          degree: 'Graduação',
          currentSemester: 5,
        ),
      ];
      await wb.save(choice('gap.edu.moment', ['in_college']));
      await wb.save(StepAnswer.text('gap.edu.institution', 'USP'));
      await wb.save(StepAnswer.text('gap.edu.course', 'Administração'));
      await wb.save(choice('gap.edu.semester', ['5']));
      await wb.save(choice('gap.edu.graduation', ['unsure']));

      expect(repo.educationInsertCalls, 0);
      expect(repo.educationUpdateCalls, 1);
      expect(repo.educations, hasLength(1));
      expect(repo.educations.single.majors.single.name, 'Administração');
    });

    test('educação sem instituição: terminal falha explicitamente', () async {
      await wb.save(choice('gap.edu.moment', ['in_college']));
      await expectLater(
        wb.save(choice('gap.edu.graduation', ['2027'])),
        throwsA(isA<StateError>()),
      );
      expect(repo.educations, isEmpty);
    });

    test('educação "outro": no-op (não cria formação)', () async {
      await wb.save(choice('gap.edu.moment', ['outro']));
      expect(repo.addedEducation, isNull);
      expect(repo.updatedEducation, isNull);
    });

    test(
      'instituição canônica: "id|Nome" do typeahead fixa o institution_id',
      () async {
        const uuid = '11111111-2222-3333-4444-555555555555';
        await wb.save(choice('gap.edu.moment', ['in_college']));
        await wb.save(
          StepAnswer.pick(
            'gap.edu.institution',
            label: 'USP',
            value: '$uuid|USP',
          ),
        );
        await wb.save(StepAnswer.text('gap.edu.course', 'Engenharia'));
        await wb.save(choice('gap.edu.semester', ['5']));
        await wb.save(choice('gap.edu.graduation', ['2027']));
        expect(repo.addedEducation?.institution, 'USP');
        expect(repo.addedEducation?.institutionId, uuid);
      },
    );

    test('instituição texto livre: sem id (institution_id null)', () async {
      await wb.save(choice('gap.edu.moment', ['in_college']));
      await wb.save(
        StepAnswer.pick(
          'gap.edu.institution',
          label: 'Faculdade Local',
          value: 'Faculdade Local',
        ),
      );
      await wb.save(StepAnswer.text('gap.edu.course', 'Adm'));
      await wb.save(choice('gap.edu.semester', ['2']));
      await wb.save(choice('gap.edu.graduation', ['2028']));
      expect(repo.addedEducation?.institution, 'Faculdade Local');
      expect(repo.addedEducation?.institutionId, isNull);
    });
  });

  group('resumabilidade (rascunho de item)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'experiência: persiste rascunho nos passos intermediários, apaga no fim',
      () async {
        final store = TrilhaDraftStore();
        final wb2 = TrilhaWriteback(repo, 'u1', draftStore: store);

        await wb2.save(StepAnswer.text('exp.0.estagio.company', 'Magalu'));
        await wb2.save(StepAnswer.text('exp.0.estagio.role', 'Estágio'));
        var drafts = await store.load('u1');
        expect(drafts, hasLength(1));
        expect(drafts.first.kind, 'experience');
        expect(drafts.first.fields['company'], 'Magalu');
        expect(
          drafts.first.fields['kind'],
          'estagio',
        ); // tipo persistido no draft
        expect(repo.addedExps, isEmpty); // ainda não gravou a experiência

        await wb2.save(StepAnswer.monthYear('exp.0.estagio.start', 2024, 1));
        await wb2.save(choice('exp.0.estagio.current', ['yes']));
        await wb2.save(
          StepAnswer.text('exp.0.estagio.ofazia', 'organizava o estoque'),
        );
        expect(repo.addedExps, hasLength(1)); // gravou no terminal
        expect(repo.addedExps.first.kind, 'estagio');
        expect(await store.load('u1'), isEmpty); // rascunho apagado
      },
    );

    test(
      'experiência: falha terminal preserva buffer e rascunho para retry',
      () async {
        final store = TrilhaDraftStore();
        final wb2 = TrilhaWriteback(repo, 'u1', draftStore: store);
        await wb2.save(StepAnswer.text('exp.0.estagio.company', 'Stage'));
        await wb2.save(StepAnswer.monthYear('exp.0.estagio.start', 2025, 1));
        await wb2.save(choice('exp.0.estagio.current', ['yes']));
        final terminal = StepAnswer.text(
          'exp.0.estagio.ofazia',
          'Criei o feed',
        );

        await expectLater(wb2.save(terminal), throwsA(isA<StateError>()));
        expect((await store.load('u1')).single.fields['company'], 'Stage');
        await wb2.save(StepAnswer.text('exp.0.estagio.role', 'Produto'));
        await wb2.save(terminal);

        expect(repo.addedExps, hasLength(1));
        expect(await store.load('u1'), isEmpty);
      },
    );

    test('experiência: falha ambígua mantém rascunho até retry', () async {
      final store = TrilhaDraftStore();
      final wb2 = TrilhaWriteback(repo, 'u1', draftStore: store);
      await wb2.save(StepAnswer.text('exp.0.estagio.company', 'Stage'));
      await wb2.save(StepAnswer.text('exp.0.estagio.role', 'Produto'));
      await wb2.save(StepAnswer.monthYear('exp.0.estagio.start', 2025, 1));
      await wb2.save(choice('exp.0.estagio.current', ['yes']));
      repo.failExperienceAfterPersistOnce = true;
      final terminal = StepAnswer.text('exp.0.estagio.ofazia', 'Criei o feed');

      await expectLater(wb2.save(terminal), throwsA(isA<StateError>()));
      expect(await store.load('u1'), isNotEmpty);
      await wb2.save(terminal);

      expect(repo.addedExps, hasLength(1));
      expect(await store.load('u1'), isEmpty);
    });

    test(
      'seedFromDrafts reidrata o buffer → save terminal vê os campos de antes',
      () async {
        final store = TrilhaDraftStore();
        final wb2 = TrilhaWriteback(repo, 'u1', draftStore: store);
        wb2.seedFromDrafts([
          const TrilhaItemDraft(
            kind: 'experience',
            itemIndex: 0,
            lastStepId: 'exp.0.estagio.current',
            fields: {
              'kind': 'estagio',
              'company': 'Magalu',
              'role': 'Estágio',
              'start': '2024-01-01T00:00:00.000',
              'isCurrent': true,
            },
          ),
        ]);
        // Retoma: só responde o passo terminal (ofazia).
        await wb2.save(
          StepAnswer.text('exp.0.estagio.ofazia', 'cuidava do estoque'),
        );
        expect(repo.addedExps, hasLength(1));
        expect(repo.addedExps.first.company, 'Magalu');
        expect(repo.addedExps.first.title, 'Estágio');
        expect(
          repo.addedExps.first.kind,
          'estagio',
        ); // kind sobreviveu ao resume
      },
    );

    test(
      'projeto: rascunho nos intermediários, some no link (terminal)',
      () async {
        final store = TrilhaDraftStore();
        final wb2 = TrilhaWriteback(repo, 'u1', draftStore: store);
        await wb2.save(StepAnswer.text('project.0.name', 'App'));
        await wb2.save(StepAnswer.text('project.0.what', 'algo'));
        await wb2.save(StepAnswer.text('project.0.did', 'fiz'));
        expect((await store.load('u1')).first.fields['did'], 'fiz');
        await wb2.save(
          const StepAnswer(
            stepId: 'project.0.when',
            value: '',
            displayText: 'Pular',
          ),
        );
        await wb2.save(choice('project.0.current', ['yes']));
        await wb2.save(
          const StepAnswer(
            stepId: 'project.0.link',
            value: '',
            displayText: 'Pular',
          ),
        );
        expect(await store.load('u1'), isEmpty);
      },
    );

    test('educação "outro": não cria rascunho (nada a retomar)', () async {
      final store = TrilhaDraftStore();
      final wb2 = TrilhaWriteback(repo, 'u1', draftStore: store);
      await wb2.save(choice('gap.edu.moment', ['outro']));
      expect(await store.load('u1'), isEmpty);
    });
  });
}
