// Regressão do review dos "Médios": assistReversibleRemove precisa remover o
// item EXATO que o resolver identificou — não o primeiro parecido. Antes, o
// match bidirecional (value.contains(name)) fazia "Java" ser removido quando o
// usuário pediu "Java SE 8".

import 'package:career_gamification/features/profile/domain/entities/education.dart';
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
}
