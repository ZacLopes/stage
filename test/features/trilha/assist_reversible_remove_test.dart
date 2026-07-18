// Regressão do review dos "Médios": assistReversibleRemove precisa remover o
// item EXATO que o resolver identificou — não o primeiro parecido. Antes, o
// match bidirecional (value.contains(name)) fazia "Java" ser removido quando o
// usuário pediu "Java SE 8".

import 'package:career_gamification/features/profile/domain/entities/education.dart';
import 'package:career_gamification/features/profile/domain/entities/experiences.dart';
import 'package:career_gamification/features/profile/domain/entities/job_preferences.dart';
import 'package:career_gamification/features/profile/domain/entities/personal_info.dart';
import 'package:career_gamification/features/profile/domain/entities/simple_lists.dart';
import 'package:career_gamification/features/profile/domain/repositories/profile_repository.dart';
import 'package:career_gamification/features/trilha/application/trilha_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _EduRepo implements ProfileRepository {
  final List<Education> edu;
  Education? updated;
  _EduRepo(this.edu);

  @override
  Future<List<Education>> getEducation(String userId) async => edu;
  @override
  Future<Education> updateEducation(Education e) async {
    updated = e;
    return e;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _CertRepo implements ProfileRepository {
  final List<Certification> certs;
  final List<String> deleted = [];
  _CertRepo(List<Certification> certs) : certs = List.of(certs);

  @override
  Future<List<Certification>> getCertifications(String userId) async => certs;
  @override
  Future<void> deleteCertification(String id) async {
    deleted.add(id);
    certs.removeWhere((certification) => certification.id == id);
  }
  @override
  Future<Certification> addCertification(Certification c) async {
    certs.add(c);
    return c;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _PersonalRepo implements ProfileRepository {
  PersonalInfo? personal;
  Set<String> lastNullColumns = const {};
  _PersonalRepo(this.personal);

  @override
  Future<PersonalInfo?> getPersonal(String userId) async => personal;
  @override
  Future<PersonalInfo> upsertPersonal(PersonalInfo p,
      {Set<String> nullColumns = const {}}) async {
    lastNullColumns = nullColumns;
    personal = p;
    return p;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _PrefsRepo implements ProfileRepository {
  JobPreferences? prefs;
  _PrefsRepo(this.prefs);

  @override
  Future<JobPreferences?> getJobPreferences(String userId) async => prefs;
  @override
  Future<JobPreferences> upsertJobPreferences(JobPreferences p) async {
    prefs = p;
    return p;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _ReversibleCompositeRepo implements ProfileRepository {
  final List<Experience> experiences;
  final List<Project> projects;
  final List<Bullet> restoredExperienceBullets = [];
  final List<ProjectBullet> restoredProjectBullets = [];
  int addExperienceCalls = 0;
  int addBulletCalls = 0;
  int addProjectCalls = 0;
  bool throwAfterExperienceDelete = false;
  bool noOpExperienceDelete = false;

  _ReversibleCompositeRepo({
    this.experiences = const [],
    this.projects = const [],
  });

  @override
  Future<List<Experience>> getExperiences(String userId) async => experiences;

  @override
  Future<void> deleteExperience(String id) async {
    if (!noOpExperienceDelete) {
      experiences.removeWhere((experience) => experience.id == id);
    }
    if (throwAfterExperienceDelete) {
      throw StateError('timeout depois do commit');
    }
  }

  @override
  Future<Experience> addExperience(Experience experience) async {
    addExperienceCalls++;
    final saved = experience.copyWith(
      id: 'restored-experience',
      bullets: experience.bullets
          .map((bullet) => bullet.copyWith(
                id: 'restored-${bullet.id}',
                experienceId: 'restored-experience',
              ))
          .toList(),
    );
    restoredExperienceBullets.addAll(saved.bullets);
    experiences.add(saved);
    return saved;
  }

  @override
  Future<Bullet> addBullet(Bullet bullet) async {
    addBulletCalls++;
    final saved = bullet.copyWith(id: 'extra-${bullet.id}');
    restoredExperienceBullets.add(saved);
    return saved;
  }

  @override
  Future<List<Project>> getProjects(String userId) async => projects;

  @override
  Future<void> deleteProject(String id) async {
    projects.removeWhere((project) => project.id == id);
  }

  @override
  Future<Project> addProject(Project project) async {
    addProjectCalls++;
    final saved = project.copyWith(
      id: 'restored-project',
      bullets: project.bullets
          .map((bullet) => bullet.copyWith(
                id: 'restored-${bullet.id}',
                projectId: 'restored-project',
              ))
          .toList(),
    );
    restoredProjectBullets.addAll(saved.bullets);
    projects.add(saved);
    return saved;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test(
      'assistReversibleRemove experience: undo restaura parent e bullets uma vez',
      () async {
    final original = Experience(
      id: 'experience-1',
      userId: 'u',
      title: 'Estagiária',
      company: 'Stage',
      startDate: DateTime(2025),
      bullets: const [
        Bullet(
          id: 'bullet-1',
          experienceId: 'experience-1',
          text: 'Criei o produto',
          angle: BulletAngle.leadership,
          strengthScore: 91,
          verb: 'Criei',
          orderIndex: 0,
        ),
        Bullet(
          id: 'bullet-2',
          experienceId: 'experience-1',
          text: 'Validei com usuários',
          angle: BulletAngle.impact,
          strengthScore: 88,
          verb: 'Validei',
          orderIndex: 1,
        ),
      ],
    );
    final repo = _ReversibleCompositeRepo(experiences: [original]);

    final restore = await assistReversibleRemove(
      'u',
      'experience',
      'Estagiária · Stage',
      repository: repo,
    );
    expect(repo.experiences, isEmpty);

    await restore!();

    expect(repo.addExperienceCalls, 1);
    expect(repo.addBulletCalls, 0,
        reason: 'addExperience já persiste os bullets recebidos');
    expect(repo.experiences.single.title, 'Estagiária');
    expect(repo.experiences.single.company, 'Stage');
    expect(repo.restoredExperienceBullets, hasLength(2));
    expect(
      repo.restoredExperienceBullets
          .map((bullet) => (
                bullet.text,
                bullet.angle,
                bullet.strengthScore,
                bullet.verb,
                bullet.orderIndex,
                bullet.experienceId,
              ))
          .toList(),
      [
        ('Criei o produto', BulletAngle.leadership, 91, 'Criei', 0,
          'restored-experience'),
        ('Validei com usuários', BulletAngle.impact, 88, 'Validei', 1,
          'restored-experience'),
      ],
    );
  });

  test(
      'assistReversibleRemove experience: delete ambíguo confirmado preserva undo',
      () async {
    final repo = _ReversibleCompositeRepo(
      experiences: [
        Experience(
          id: 'experience-1',
          userId: 'u',
          title: 'Fundador',
          company: 'Stage',
          startDate: DateTime(2024),
          bullets: const [
            Bullet(
              id: 'bullet-1',
              experienceId: 'experience-1',
              text: 'Lancei o MVP',
            ),
          ],
        ),
      ],
    )..throwAfterExperienceDelete = true;

    final restore = await assistReversibleRemove(
      'u',
      'experience',
      'Fundador · Stage',
      repository: repo,
    );

    expect(repo.experiences, isEmpty,
        reason: 'a releitura confirma que o delete foi persistido');
    expect(restore, isNotNull,
        reason: 'timeout pós-commit não pode perder a ação de desfazer');
    await restore!();
    expect(repo.experiences.single.bullets.single.text, 'Lancei o MVP');
    expect(repo.restoredExperienceBullets, hasLength(1));
    expect(repo.addBulletCalls, 0);
  });

  test('assistReversibleRemove: delete sem erro mas sem efeito falha fechado',
      () async {
    final original = Experience(
      id: 'experience-1',
      userId: 'u',
      title: 'Fundador',
      company: 'Stage',
      startDate: DateTime(2024),
    );
    final repo = _ReversibleCompositeRepo(experiences: [original])
      ..noOpExperienceDelete = true;

    await expectLater(
      assistReversibleRemove(
        'u',
        'experience',
        'Fundador · Stage',
        repository: repo,
      ),
      throwsStateError,
    );
    expect(repo.experiences, [original]);
  });

  test('assistReversibleRemove project: undo preserva cada bullet uma vez',
      () async {
    const original = Project(
      id: 'project-1',
      userId: 'u',
      name: 'Stage',
      role: 'Fundador',
      bullets: [
        ProjectBullet(
          id: 'project-bullet-1',
          projectId: 'project-1',
          text: 'Lancei o MVP',
          orderIndex: 0,
        ),
        ProjectBullet(
          id: 'project-bullet-2',
          projectId: 'project-1',
          text: 'Entrevistei estudantes',
          orderIndex: 1,
        ),
      ],
    );
    final repo = _ReversibleCompositeRepo(projects: [original]);

    final restore = await assistReversibleRemove(
      'u',
      'project',
      'Stage',
      repository: repo,
    );
    expect(repo.projects, isEmpty);

    await restore!();

    expect(repo.addProjectCalls, 1);
    expect(repo.projects.single.name, 'Stage');
    expect(repo.projects.single.role, 'Fundador');
    expect(repo.restoredProjectBullets, hasLength(2));
    expect(
      repo.restoredProjectBullets
          .map((bullet) =>
              (bullet.text, bullet.orderIndex, bullet.projectId))
          .toList(),
      [
        ('Lancei o MVP', 0, 'restored-project'),
        ('Entrevistei estudantes', 1, 'restored-project'),
      ],
    );
  });

  test('assistReversibleRemove certification: remove o EXATO, não o parecido',
      () async {
    final repo = _CertRepo(const [
      Certification(id: 'c0', userId: 'u', name: 'Java'),
      Certification(id: 'c1', userId: 'u', name: 'Java SE 8'),
    ]);
    final restore = await assistReversibleRemove('u', 'certification', 'Java SE 8',
        repository: repo);
    expect(repo.deleted, ['c1']); // tirou o "Java SE 8", NÃO o "Java"
    expect(restore, isNotNull);
  });

  test('assistReversibleRemove certification: query que não casa → null', () async {
    final repo = _CertRepo(const [
      Certification(id: 'c0', userId: 'u', name: 'AWS'),
    ]);
    final restore =
        await assistReversibleRemove('u', 'certification', 'Kotlin', repository: repo);
    expect(restore, isNull);
    expect(repo.deleted, isEmpty);
  });

  test('assistWriteItemField education institution: limpa o institution_id stale',
      () async {
    final repo = _EduRepo([
      const Education(
          id: 'e1', userId: 'u', institution: 'UFPE', institutionId: 'ies-ufpe'),
    ]);
    await assistWriteItemField('u', 'education', 'e1', 'institution', 'USP',
        repository: repo);
    expect(repo.updated?.institution, 'USP');
    // Trocar o nome quebra o vínculo canônico antigo (senão fica sob a IES errada).
    expect(repo.updated?.institutionId, isNull);
  });

  // Regressão do review dos "Médios": a UF vem do value da cidade — sem UF no
  // texto o estado é LIMPO, não herda o antigo (senão o undo pra uma cidade sem
  // UF deixaria par cidade/UF impossível, mislocando o candidato).
  test('assistWriteFieldValue city: value sem UF limpa o estado antigo', () async {
    final repo = _PersonalRepo(
        const PersonalInfo(userId: 'u', locationCity: 'São Paulo', locationState: 'SP'));
    await assistWriteFieldValue('u', 'city', 'Salvador', repository: repo);
    expect(repo.personal?.locationCity, 'Salvador');
    expect(repo.personal?.locationState, isNull); // não herda 'SP'
  });

  test('assistWriteFieldValue city: value com UF grava cidade + estado', () async {
    final repo = _PersonalRepo(
        const PersonalInfo(userId: 'u', locationCity: 'Salvador', locationState: null));
    await assistWriteFieldValue('u', 'city', 'Recife, PE', repository: repo);
    expect(repo.personal?.locationCity, 'Recife');
    expect(repo.personal?.locationState, 'PE');
  });

  test('assistWriteFieldValue city: troca de cidade LIMPA o CEP antigo', () async {
    final repo = _PersonalRepo(const PersonalInfo(
        userId: 'u',
        locationCity: 'Londrina',
        locationState: 'PR',
        locationPostalCode: '86015-620'));
    await assistWriteFieldValue('u', 'city', 'Recife, PE', repository: repo);
    expect(repo.personal?.locationCity, 'Recife');
    // CEP de Londrina não pode ficar com a cidade Recife (par impossível). O
    // clear tem que ir como nullColumn (o upsert parcial descarta nulls soltos).
    expect(repo.lastNullColumns, contains('location_postal_code'));
  });

  // Regressão do review: um value não-vazio que não casa nenhum id NÃO pode
  // zerar a modalidade (o card mostraria label bonito e apagaria o campo).
  test('assistWriteFieldValue work_mode: value inválido NÃO zera a modalidade',
      () async {
    final repo = _PrefsRepo(const JobPreferences(
        userId: 'u', workMode: [WorkMode.remote, WorkMode.hybrid]));
    await assistWriteFieldValue('u', 'work_mode', 'flexível', repository: repo);
    expect(repo.prefs?.workMode, [WorkMode.remote, WorkMode.hybrid]);
  });

  test('assistWriteFieldValue work_mode: value vazio (undo) zera', () async {
    final repo =
        _PrefsRepo(const JobPreferences(userId: 'u', workMode: [WorkMode.remote]));
    await assistWriteFieldValue('u', 'work_mode', '', repository: repo);
    expect(repo.prefs?.workMode, isEmpty);
  });
}
