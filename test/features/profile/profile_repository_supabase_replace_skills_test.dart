import 'dart:convert';

import 'package:career_gamification/features/profile/data/repositories/profile_repository_supabase.dart';
import 'package:career_gamification/features/profile/domain/manual_skills_replace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

ProfileRepositorySupabase _repo(MockClient httpClient) =>
    ProfileRepositorySupabase(
      client: SupabaseClient(
        'http://localhost:54321',
        'test-key',
        httpClient: httpClient,
      ),
    );

http.Response _json(Object body, http.BaseRequest request, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

void main() {
  group('ProfileRepositorySupabase.replaceSkills (Gate 3.0D — RPC atômico)', () {
    test('chama replace_profile_skills_atomic_v1 com p_names normalizado', () async {
      http.Request? captured;
      final repo = _repo(MockClient((request) async {
        captured = request;
        return _json({'status': 'applied', 'count': 2}, request);
      }));

      await repo.replaceSkills('user-1', const [' Excel ', 'Python', 'excel']);

      expect(captured?.method, 'POST');
      expect(
        captured?.url.path,
        '/rest/v1/rpc/replace_profile_skills_atomic_v1',
      );
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['p_user_id'], 'user-1');
      // normalizado + dedup por chave (case/acento/whitespace).
      expect(body['p_names'], ['Excel', 'Python']);
    });

    test('recibo noop é aceito (idempotente), sem lançar', () async {
      final repo = _repo(
        MockClient((request) async => _json({'status': 'noop', 'count': 1}, request)),
      );
      await repo.replaceSkills('user-1', const ['Excel']);
    });

    test('não faz mais get/insert/update/delete — apenas o RPC', () async {
      final paths = <String>[];
      final repo = _repo(MockClient((request) async {
        paths.add(request.url.path);
        return _json({'status': 'applied', 'count': 1}, request);
      }));

      await repo.replaceSkills('user-1', const ['Excel']);

      expect(paths, ['/rest/v1/rpc/replace_profile_skills_atomic_v1']);
      expect(paths.contains('/rest/v1/profile_skills'), isFalse);
    });

    test('> 12 skills → ArgumentError, sem round-trip', () async {
      var requests = 0;
      final repo = _repo(MockClient((request) async {
        requests++;
        return _json({'status': 'applied', 'count': 1}, request);
      }));
      final many = List<String>.generate(13, (i) => 'Skill $i');

      await expectLater(repo.replaceSkills('user-1', many), throwsArgumentError);
      expect(requests, 0);
    });

    test('resposta malformada (status desconhecido) falha fechado', () async {
      final repo = _repo(
        MockClient((request) async => _json({'status': 'weird', 'count': 1}, request)),
      );
      await expectLater(
        repo.replaceSkills('user-1', const ['Excel']),
        throwsA(isA<ManualSkillsReplaceContractException>()),
      );
    });

    test('count incoerente (maior que o enviado) falha fechado', () async {
      final repo = _repo(
        MockClient((request) async => _json({'status': 'applied', 'count': 9}, request)),
      );
      await expectLater(
        repo.replaceSkills('user-1', const ['Excel']),
        throwsA(isA<ManualSkillsReplaceContractException>()),
      );
    });

    test('erro do RPC (duplicata legada) propaga como PostgrestException', () async {
      final repo = _repo(MockClient((request) async => _json(
            {
              'code': '23505',
              'message': 'duplicate_profile_skills_require_review',
              'details': null,
              'hint': null,
            },
            request,
            status: 400,
          )));
      await expectLater(
        repo.replaceSkills('user-1', const ['Excel']),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('ManualSkillsReplaceReceipt.fromRpc — fail-closed', () {
    test('não-objeto falha fechado', () {
      expect(
        () => ManualSkillsReplaceReceipt.fromRpc('applied', expectedMax: 1),
        throwsA(isA<ManualSkillsReplaceContractException>()),
      );
    });

    test('status desconhecido falha fechado', () {
      expect(
        () => ManualSkillsReplaceReceipt.fromRpc(
          {'status': 'stale', 'count': 0},
          expectedMax: 1,
        ),
        throwsA(isA<ManualSkillsReplaceContractException>()),
      );
    });

    test('count de tipo errado falha fechado', () {
      expect(
        () => ManualSkillsReplaceReceipt.fromRpc(
          {'status': 'applied', 'count': '2'},
          expectedMax: 2,
        ),
        throwsA(isA<ManualSkillsReplaceContractException>()),
      );
    });

    test('count negativo ou acima do enviado falha fechado', () {
      expect(
        () => ManualSkillsReplaceReceipt.fromRpc(
          {'status': 'applied', 'count': -1},
          expectedMax: 2,
        ),
        throwsA(isA<ManualSkillsReplaceContractException>()),
      );
      expect(
        () => ManualSkillsReplaceReceipt.fromRpc(
          {'status': 'applied', 'count': 3},
          expectedMax: 2,
        ),
        throwsA(isA<ManualSkillsReplaceContractException>()),
      );
    });

    test('applied/noop válidos são aceitos', () {
      final applied = ManualSkillsReplaceReceipt.fromRpc(
        {'status': 'applied', 'count': 2},
        expectedMax: 2,
      );
      expect(applied.outcome, ManualSkillsReplaceOutcome.applied);
      expect(applied.count, 2);
      final noop = ManualSkillsReplaceReceipt.fromRpc(
        {'status': 'noop', 'count': 0},
        expectedMax: 2,
      );
      expect(noop.outcome, ManualSkillsReplaceOutcome.noop);
    });
  });
}
