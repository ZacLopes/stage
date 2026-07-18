import 'dart:convert';

import 'package:career_gamification/features/profile/data/repositories/profile_repository_supabase.dart';
import 'package:career_gamification/features/profile/domain/entities/entities.dart';
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

DesiredTitle _t(String title, DesiredTitleSource? source, int order) =>
    DesiredTitle(
      id: '',
      userId: 'user-1',
      title: title,
      source: source,
      orderIndex: order,
    );

void main() {
  group('ProfileRepositorySupabase.replaceDesiredTitles (Gate 3.0G-áreas)', () {
    test('chama replace_profile_desired_titles_atomic_v1 com {title,source}',
        () async {
      http.Request? captured;
      final repo = _repo(MockClient((request) async {
        captured = request;
        return _json({'status': 'applied', 'count': 3}, request);
      }));

      await repo.replaceDesiredTitles('user-1', [
        _t('Tecnologia', DesiredTitleSource.userAdded, 0),
        _t('Dados', DesiredTitleSource.inferred, 1),
        _t('Produto', null, 2),
      ]);

      expect(
        captured?.url.path,
        '/rest/v1/rpc/replace_profile_desired_titles_atomic_v1',
      );
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['p_user_id'], 'user-1');
      // Preserva a fonte de cada área (para o servidor aplicar a precedência).
      expect(body['p_titles'], [
        {'title': 'Tecnologia', 'source': 'user_added'},
        {'title': 'Dados', 'source': 'inferred'},
        {'title': 'Produto', 'source': null},
      ]);
    });

    test('não faz mais delete/insert — apenas o RPC', () async {
      final paths = <String>[];
      final repo = _repo(MockClient((request) async {
        paths.add(request.url.path);
        return _json({'status': 'applied', 'count': 1}, request);
      }));

      await repo.replaceDesiredTitles('user-1', [
        _t('Tecnologia', DesiredTitleSource.userAdded, 0),
      ]);

      expect(paths, ['/rest/v1/rpc/replace_profile_desired_titles_atomic_v1']);
      expect(paths.contains('/rest/v1/profile_desired_titles'), isFalse);
    });

    test('limpar todas (lista vazia) → applied count 0', () async {
      final repo = _repo(
        MockClient((request) async => _json({'status': 'applied', 'count': 0}, request)),
      );
      await repo.replaceDesiredTitles('user-1', const []);
    });

    test('resposta malformada falha fechado', () async {
      final repo = _repo(
        MockClient((request) async => _json({'status': 'weird', 'count': 1}, request)),
      );
      await expectLater(
        repo.replaceDesiredTitles('user-1', [
          _t('Tecnologia', DesiredTitleSource.userAdded, 0),
        ]),
        throwsA(isA<ManualSkillsReplaceContractException>()),
      );
    });

    test('erro do RPC (source inválida/limite/ACL) propaga', () async {
      final repo = _repo(MockClient((request) async => _json(
            {
              'code': '22023',
              'message': 'invalid_title_source',
              'details': null,
              'hint': null,
            },
            request,
            status: 400,
          )));
      await expectLater(
        repo.replaceDesiredTitles('user-1', [
          _t('Tecnologia', DesiredTitleSource.userAdded, 0),
        ]),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
