import 'dart:convert';

import 'package:career_gamification/features/profile/data/repositories/profile_repository_supabase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'getSkills pede o mesmo desempate order_index,id usado pelo CAS',
    () async {
      Uri? requestUri;
      final httpClient = MockClient((request) async {
        requestUri = request.url;
        return http.Response(
          jsonEncode([
            {
              'id': '00000000-0000-4000-8000-000000000001',
              'user_id': 'user-1',
              'name': 'Excel',
              'category': null,
              'order_index': 0,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-key',
        httpClient: httpClient,
      );
      final repository = ProfileRepositorySupabase(client: client);

      final skills = await repository.getSkills('user-1');

      expect(skills.single.name, 'Excel');
      expect(requestUri?.path, '/rest/v1/profile_skills');
      expect(requestUri?.queryParameters['user_id'], 'eq.user-1');
      expect(
        requestUri?.queryParameters['order'],
        'order_index.asc.nullslast,id.asc.nullslast',
      );
    },
  );
}
