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

    test('intro (e desconhecidos): no-op, nada gravado', () async {
      await wb.save(choice('intro', ['go']));
      expect(repo.replacedSkills, isNull);
      expect(repo.upsertedPrefs, isNull);
      expect(repo.upsertedPersonal, isNull);
      expect(repo.addedLangs, isEmpty);
    });
  });
}
