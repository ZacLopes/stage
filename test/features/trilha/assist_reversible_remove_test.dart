// Regressão do review dos "Médios": assistReversibleRemove precisa remover o
// item EXATO que o resolver identificou — não o primeiro parecido. Antes, o
// match bidirecional (value.contains(name)) fazia "Java" ser removido quando o
// usuário pediu "Java SE 8".

import 'package:career_gamification/features/profile/domain/entities/education.dart';
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
  _CertRepo(this.certs);

  @override
  Future<List<Certification>> getCertifications(String userId) async => certs;
  @override
  Future<void> deleteCertification(String id) async => deleted.add(id);
  @override
  Future<Certification> addCertification(Certification c) async => c;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _PersonalRepo implements ProfileRepository {
  PersonalInfo? personal;
  _PersonalRepo(this.personal);

  @override
  Future<PersonalInfo?> getPersonal(String userId) async => personal;
  @override
  Future<PersonalInfo> upsertPersonal(PersonalInfo p) async {
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

void main() {
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
