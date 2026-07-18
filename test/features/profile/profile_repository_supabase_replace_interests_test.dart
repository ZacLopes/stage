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
  group('ProfileRepositorySupabase.replaceInterests (Gate 3.0G — RPC atômico)', () {
    test('chama replace_profile_interests_atomic_v1 com p_names', () async {
      http.Request? captured;
      final repo = _repo(MockClient((request) async {
        captured = request;
        return _json({'status': 'applied', 'count': 2}, request);
      }));

      await repo.replaceInterests('user-1', const ['Xadrez', 'Cinema']);

      expect(captured?.method, 'POST');
      expect(
        captured?.url.path,
        '/rest/v1/rpc/replace_profile_interests_atomic_v1',
      );
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['p_user_id'], 'user-1');
      expect(body['p_names'], ['Xadrez', 'Cinema']);
    });

    test('não faz mais delete/insert — apenas o RPC', () async {
      final paths = <String>[];
      final repo = _repo(MockClient((request) async {
        paths.add(request.url.path);
        return _json({'status': 'applied', 'count': 1}, request);
      }));

      await repo.replaceInterests('user-1', const ['Cinema']);

      expect(paths, ['/rest/v1/rpc/replace_profile_interests_atomic_v1']);
      expect(paths.contains('/rest/v1/profile_interests'), isFalse);
    });

    test('limpar todos (lista vazia) → applied count 0, aceito', () async {
      final repo = _repo(
        MockClient((request) async => _json({'status': 'applied', 'count': 0}, request)),
      );
      await repo.replaceInterests('user-1', const []);
    });

    test('noop aceito (idempotente)', () async {
      final repo = _repo(
        MockClient((request) async => _json({'status': 'noop', 'count': 1}, request)),
      );
      await repo.replaceInterests('user-1', const ['Cinema']);
    });

    test('resposta malformada falha fechado', () async {
      final repo = _repo(
        MockClient((request) async => _json({'status': 'weird', 'count': 1}, request)),
      );
      await expectLater(
        repo.replaceInterests('user-1', const ['Cinema']),
        throwsA(isA<ManualSkillsReplaceContractException>()),
      );
    });

    test('count acima do enviado falha fechado', () async {
      final repo = _repo(
        MockClient((request) async => _json({'status': 'applied', 'count': 9}, request)),
      );
      await expectLater(
        repo.replaceInterests('user-1', const ['Cinema']),
        throwsA(isA<ManualSkillsReplaceContractException>()),
      );
    });

    test('erro do RPC (limite/ACL) propaga como PostgrestException', () async {
      final repo = _repo(MockClient((request) async => _json(
            {
              'code': '22023',
              'message': 'too_many_items',
              'details': null,
              'hint': null,
            },
            request,
            status: 400,
          )));
      await expectLater(
        repo.replaceInterests('user-1', const ['Cinema']),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
