import 'package:career_gamification/features/profile/domain/entities/personal_info.dart';
import 'package:career_gamification/features/profile/domain/repositories/profile_repository.dart';
import 'package:career_gamification/features/trilha/application/trilha_session.dart';
import 'package:flutter_test/flutter_test.dart';

// Fake que registra as chamadas CAS (Gate 3.0H app-side). getPersonal serve pro
// DDI do phone. Demais métodos caem no noSuchMethod (não usados aqui).
class _CasRepo implements ProfileRepository {
  final List<List<String?>> personalCalls = [];
  final List<List<String>> itemCalls = [];
  String result = 'applied';
  String? currentCc;

  @override
  Future<String> casWritePersonalField(
    String userId,
    String field,
    String expected,
    String value, {
    String? expectedCountryCode,
    String? newCountryCode,
  }) async {
    personalCalls.add([userId, field, expected, value, expectedCountryCode, newCountryCode]);
    return result;
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
    itemCalls.add([userId, kind, refId, field, expected, value]);
    return result;
  }

  final List<List<String>> jobPrefCalls = [];

  @override
  Future<String> casWriteJobPrefField(
    String userId,
    String field,
    String expected,
    String value,
  ) async {
    jobPrefCalls.add([userId, field, expected, value]);
    return result;
  }

  @override
  Future<PersonalInfo?> getPersonal(String userId) async =>
      PersonalInfo(userId: userId, phoneCountryCode: currentCc);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('Gate 3.0H app-side — roteamento pro CAS quando há expected', () {
    test('escalar simples (summary): chama casWritePersonalField(expected, value)',
        () async {
      final repo = _CasRepo();
      await assistWriteFieldValue('u', 'summary', 'resumo novo',
          expected: 'resumo antigo', repository: repo);
      expect(repo.personalCalls.single,
          ['u', 'summary', 'resumo antigo', 'resumo novo', null, null]);
    });

    test('phone: lê o DDI atual e passa como esperado/novo', () async {
      final repo = _CasRepo()..currentCc = '55';
      await assistWriteFieldValue('u', 'phone', '11999',
          expected: '11888', repository: repo);
      expect(repo.personalCalls.single,
          ['u', 'phone', '11888', '11999', '55', '55']);
    });

    test('name/city/linkedin/website também roteiam pro CAS', () async {
      for (final f in ['name', 'city', 'linkedin', 'website']) {
        final repo = _CasRepo();
        await assistWriteFieldValue('u', f, 'v', expected: 'obs', repository: repo);
        expect(repo.personalCalls.single[1], f);
      }
    });

    test('SEM expected: NÃO chama o CAS (caminho legado)', () async {
      final repo = _CasRepo();
      // summary sem expected → legado (o fake não implementa upsertPersonal →
      // cai no noSuchMethod; o que importa é NÃO ter chamado o CAS).
      try {
        await assistWriteFieldValue('u', 'summary', 'x', repository: repo);
      } catch (_) {/* legado usa outros métodos (noSuchMethod) */}
      expect(repo.personalCalls, isEmpty);
    });

    test('desired_position + work_mode roteiam pro CAS de Objetivos (não personal)',
        () async {
      final repo = _CasRepo();
      await assistWriteFieldValue('u', 'desired_position', 'Senior Dev',
          expected: 'Dev', repository: repo);
      await assistWriteFieldValue('u', 'work_mode', 'remote',
          expected: 'remote,hybrid', repository: repo);
      expect(repo.personalCalls, isEmpty);
      expect(repo.jobPrefCalls, [
        ['u', 'desired_position', 'Dev', 'Senior Dev'],
        ['u', 'work_mode', 'remote,hybrid', 'remote'],
      ]);
    });

    test('item-field: chama casWriteItemField com ref_id/field/expected', () async {
      final repo = _CasRepo();
      await assistWriteItemField('u', 'experience', 'e1', 'title', 'Senior',
          expected: 'Dev', repository: repo);
      expect(repo.itemCalls.single,
          ['u', 'experience', 'e1', 'title', 'Dev', 'Senior']);
    });

    test('bullet: chama casWriteItemField(kind=bullet, field=text)', () async {
      final repo = _CasRepo();
      await assistBulletWrite('u', 'b1', 'texto novo',
          expected: 'texto velho', repository: repo);
      expect(repo.itemCalls.single,
          ['u', 'bullet', 'b1', 'text', 'texto velho', 'texto novo']);
    });

    test('item-field SEM expected: NÃO usa o CAS (legado)', () async {
      final repo = _CasRepo();
      try {
        await assistWriteItemField('u', 'experience', 'e1', 'title', 'X',
            repository: repo);
      } catch (_) {/* legado (noSuchMethod) */}
      expect(repo.itemCalls, isEmpty);
    });
  });
}
