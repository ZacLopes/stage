import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/profile/domain/entities/entities.dart';
import 'package:career_gamification/features/profile/domain/repositories/profile_repository.dart';
import 'package:career_gamification/features/trilha/application/trilha_writeback.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';

/// Repositório falso: registra o que foi gravado; lança em métodos não usados.
class _FakeRepo implements ProfileRepository {
  List<Skill> skills = [];
  List<Language> languages = [];
  List<DesiredTitle> desired = [];
  JobPreferences? prefs;
  PersonalInfo? personal;

  List<String>? replacedSkills;
  List<DesiredTitle>? replacedDesired;
  JobPreferences? upsertedPrefs;
  PersonalInfo? upsertedPersonal;
  final List<Language> addedLangs = [];

  @override
  Future<List<Skill>> getSkills(String userId) async => skills;
  @override
  Future<void> replaceSkills(String userId, List<String> names) async {
    replacedSkills = names;
  }

  @override
  Future<List<Language>> getLanguages(String userId) async => languages;
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
    languages =
        languages.map((x) => x.name == l.name ? l : x).toList();
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
    return p;
  }

  @override
  Future<PersonalInfo?> getPersonal(String userId) async => personal;
  @override
  Future<PersonalInfo> upsertPersonal(PersonalInfo p) async {
    upsertedPersonal = p;
    return p;
  }

  final List<Experience> addedExps = [];
  final List<Bullet> addedBullets = [];
  int _expSeq = 0;
  @override
  Future<Experience> addExperience(Experience e) async {
    final saved = Experience(
      id: 'exp${_expSeq++}',
      userId: e.userId,
      title: e.title,
      company: e.company,
      startDate: e.startDate,
      endDate: e.endDate,
      isCurrent: e.isCurrent,
      needsReview: e.needsReview,
    );
    addedExps.add(saved);
    return saved;
  }

  @override
  Future<Bullet> addBullet(Bullet b) async {
    addedBullets.add(b);
    return b;
  }

  final List<Certification> addedCerts = [];
  @override
  Future<Certification> addCertification(Certification c) async {
    addedCerts.add(c);
    return c;
  }

  final List<Project> addedProjects = [];
  final List<ProjectBullet> addedProjectBullets = [];
  Project? updatedProject;
  int _projSeq = 0;
  @override
  Future<Project> addProject(Project p) async {
    final saved = p.copyWith(id: 'proj${_projSeq++}');
    addedProjects.add(saved);
    return saved;
  }

  @override
  Future<ProjectBullet> addProjectBullet(ProjectBullet b) async {
    addedProjectBullets.add(b);
    return b;
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

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} não deveria ser chamado');
}

void main() {
  late _FakeRepo repo;
  late TrilhaWriteback wb;

  setUp(() {
    repo = _FakeRepo();
    wb = TrilhaWriteback(repo, 'u1');
  });

  StepAnswer choice(String stepId, List<String> ids) => StepAnswer.choice(
        stepId,
        ids.map((id) => StepOption(id: id, label: id)).toList(),
      );

  group('TrilhaWriteback', () {
    test('skills: grava as escolhidas (sem existentes)', () async {
      await wb.save(choice('gap.skills', ['Excel', 'Python']));
      expect(repo.replacedSkills, ['Excel', 'Python']);
    });

    test('skills: faz merge dedup com as existentes', () async {
      repo.skills = [const Skill(id: '1', userId: 'u1', name: 'Excel')];
      await wb.save(choice('gap.skills', ['Excel', 'Python']));
      expect(repo.replacedSkills, ['Excel', 'Python']); // Excel não duplica
    });

    test('gap.skills.more (sugestão da IA) também grava skills', () async {
      await wb.save(choice('gap.skills.more', ['Power BI', 'SQL']));
      expect(repo.replacedSkills, ['Power BI', 'SQL']);
    });

    test('modalidade: mapeia ids → WorkMode', () async {
      await wb.save(choice('gap.workmode', ['remote', 'hybrid']));
      expect(repo.upsertedPrefs?.workMode, [WorkMode.remote, WorkMode.hybrid]);
    });

    test('tipo de vaga: mapeia ids → JobType', () async {
      await wb.save(choice('gap.jobtype', ['internship']));
      expect(repo.upsertedPrefs?.jobTypes, [JobType.internship]);
    });

    test('áreas: grava como desired titles (userAdded)', () async {
      await wb.save(choice('gap.area', ['Tecnologia', 'Produto']));
      expect(repo.replacedDesired?.map((t) => t.title),
          containsAll(['Tecnologia', 'Produto']));
      expect(repo.replacedDesired?.every((t) => t.source == DesiredTitleSource.userAdded), true);
    });

    test('cidade: separa "Cidade, UF" em city + state', () async {
      await wb.save(StepAnswer.text('gap.city', 'São Paulo, SP'));
      expect(repo.upsertedPersonal?.locationCity, 'São Paulo');
      expect(repo.upsertedPersonal?.locationState, 'SP');
    });

    test('idiomas: insere os novos e pula "none"', () async {
      await wb.save(choice('gap.languages', ['none', 'Inglês']));
      expect(repo.addedLangs.map((l) => l.name), ['Inglês']);
    });

    test('idiomas: português entra como nativo (auto); demais sem nível', () async {
      await wb.save(choice('gap.languages', ['Português', 'Inglês']));
      expect(repo.addedLangs.firstWhere((l) => l.name == 'Português').proficiency,
          LanguageProficiency.native);
      expect(repo.addedLangs.firstWhere((l) => l.name == 'Inglês').proficiency,
          isNull); // nível vem no passo seguinte
    });

    test('nível de idioma: atualiza a proficiência do idioma existente', () async {
      repo.languages = [const Language(id: '1', userId: 'u1', name: 'Inglês')];
      await wb.save(choice('lang.level.Inglês', ['advanced']));
      expect(repo.updatedLanguage?.name, 'Inglês');
      expect(repo.updatedLanguage?.proficiency, LanguageProficiency.advanced);
    });

    test('intro (e desconhecidos): no-op, nada gravado', () async {
      await wb.save(choice('intro', ['go']));
      expect(repo.replacedSkills, isNull);
      expect(repo.upsertedPrefs, isNull);
      expect(repo.upsertedPersonal, isNull);
      expect(repo.addedLangs, isEmpty);
    });

    test('experiência: acumula os campos e grava experiência + bullet', () async {
      await wb.save(StepAnswer.text('exp.0.company', 'Magalu'));
      await wb.save(StepAnswer.text('exp.0.role', 'Estagiário'));
      await wb.save(StepAnswer.monthYear('exp.0.start', 2024, 3));
      await wb.save(choice('exp.0.current', ['no']));
      await wb.save(StepAnswer.monthYear('exp.0.end', 2024, 12));
      // Ainda não gravou — falta o "o que fazia".
      expect(repo.addedExps, isEmpty);

      await wb.save(StepAnswer.text('exp.0.ofazia', 'Cuidava das redes sociais'));
      expect(repo.addedExps, hasLength(1));
      final e = repo.addedExps.first;
      expect(e.company, 'Magalu');
      expect(e.title, 'Estagiário');
      expect(e.startDate, DateTime(2024, 3, 1));
      expect(e.endDate, DateTime(2024, 12, 1));
      expect(e.isCurrent, false);
      expect(repo.addedBullets, hasLength(1));
      expect(repo.addedBullets.first.text, 'Cuidava das redes sociais');
      expect(repo.addedBullets.first.experienceId, e.id);
    });

    test('experiência atual: sem data de fim, isCurrent true', () async {
      await wb.save(StepAnswer.text('exp.0.company', 'Stage'));
      await wb.save(StepAnswer.text('exp.0.role', 'Dev'));
      await wb.save(StepAnswer.monthYear('exp.0.start', 2025, 1));
      await wb.save(choice('exp.0.current', ['yes']));
      await wb.save(StepAnswer.text('exp.0.ofazia', 'Codo bastante'));
      final e = repo.addedExps.single;
      expect(e.isCurrent, true);
      expect(e.endDate, isNull);
    });

    test('exp.gate e exp.N.more: no-op (controle de fluxo)', () async {
      await wb.save(choice('exp.gate', ['yes']));
      await wb.save(choice('exp.0.more', ['no']));
      expect(repo.addedExps, isEmpty);
      expect(repo.addedBullets, isEmpty);
    });

    test('experiência incompleta (sem cargo): não grava', () async {
      await wb.save(StepAnswer.text('exp.0.company', 'Magalu'));
      await wb.save(StepAnswer.monthYear('exp.0.start', 2024, 3));
      await wb.save(StepAnswer.text('exp.0.ofazia', 'algo'));
      expect(repo.addedExps, isEmpty); // faltou role
    });

    test('linkedin: grava o link em profile_personal', () async {
      await wb.save(StepAnswer.text('linkedin.url', 'linkedin.com/in/zac'));
      expect(repo.upsertedPersonal?.linkedinUrl, 'linkedin.com/in/zac');
    });

    test('certificação: grava o nome', () async {
      await wb.save(StepAnswer.text('cert.0.name', 'TOEFL'));
      await wb.save(StepAnswer.text('cert.1.name', 'Google Ads'));
      expect(repo.addedCerts.map((c) => c.name), ['TOEFL', 'Google Ads']);
    });

    test('gates (cert/linkedin) e .more: no-op de controle', () async {
      await wb.save(choice('cert.gate', ['yes']));
      await wb.save(choice('linkedin.gate', ['yes']));
      await wb.save(choice('cert.0.more', ['no']));
      expect(repo.addedCerts, isEmpty);
      expect(repo.upsertedPersonal, isNull);
    });

    test('projeto: grava ATÔMICO no fim (link) — nome+contexto+data+link+bullet',
        () async {
      await wb.save(StepAnswer.text('project.0.name', 'App de finanças'));
      await wb.save(StepAnswer.text('project.0.what', 'App pra controlar gastos'));
      await wb.save(StepAnswer.text('project.0.did', 'Programei em Flutter sozinho'));
      await wb.save(StepAnswer.monthYear('project.0.when', 2024, 6));
      expect(repo.addedProjects, isEmpty); // ainda NÃO salvou (só no último passo)

      await wb.save(StepAnswer.text('project.0.link', 'github.com/x/app'));
      // Agora grava tudo de uma vez:
      expect(repo.addedProjects.map((p) => p.name), ['App de finanças']);
      expect(repo.addedProjects.first.context, 'App pra controlar gastos');
      expect(repo.addedProjects.first.website, 'github.com/x/app');
      expect(repo.addedProjects.first.endDate, DateTime(2024, 6, 1));
      expect(repo.addedProjectBullets.map((b) => b.text),
          ['Programei em Flutter sozinho']);
    });

    test('projeto: sair ANTES do link NÃO salva (re-pergunta na volta)', () async {
      await wb.save(StepAnswer.text('project.0.name', 'App'));
      await wb.save(StepAnswer.text('project.0.what', 'algo'));
      await wb.save(StepAnswer.text('project.0.did', 'fiz X'));
      // Usuário fecha aqui (na data) — nada foi gravado ainda.
      expect(repo.addedProjects, isEmpty);
      expect(repo.addedProjectBullets, isEmpty);
    });

    test('projeto: pular data e link grava mesmo assim (sem data/website)', () async {
      await wb.save(StepAnswer.text('project.0.name', 'TCC'));
      await wb.save(StepAnswer.text('project.0.what', 'Pesquisa sobre X'));
      await wb.save(StepAnswer.text('project.0.did', 'Escrevi e apresentei'));
      await wb.save(const StepAnswer(stepId: 'project.0.when', value: '', displayText: 'Pular'));
      await wb.save(const StepAnswer(stepId: 'project.0.link', value: '', displayText: 'Pular'));
      expect(repo.addedProjects, hasLength(1));
      expect(repo.addedProjects.first.website, isNull);
      expect(repo.addedProjects.first.endDate, isNull);
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
      repo.interests = [const Interest(id: '1', userId: 'u1', name: 'Tecnologia')];
      await wb.save(choice('gap.interests', ['Tecnologia', 'Sustentabilidade']));
      // Tecnologia já existe → não duplica; só adiciona Sustentabilidade.
      expect(repo.replacedInterests, ['Tecnologia', 'Sustentabilidade']);
    });

    test('interests.gate: no-op de controle', () async {
      await wb.save(choice('interests.gate', ['yes']));
      expect(repo.replacedInterests, isNull);
    });
  });
}
