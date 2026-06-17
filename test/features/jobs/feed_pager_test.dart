import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/data/feed_pager.dart';

/// FASE 2 (T2.2, R3): cursor/paginação do feed RPC com transporte MOCKADO.
/// O FeedPager é a lógica de paginação que o JobsViewModel delega — estes
/// testes cobrem o contrato do RPC sem Supabase.
void main() {
  Map<String, dynamic> row(
    String id,
    double rank, {
    int score = 0,
    int? taf,
    int? tav,
    int? tmc,
    bool area = false,
    bool loc = false,
  }) =>
      {
        'job_id': id,
        'score': score,
        'rank_score': rank,
        'reason_area': area,
        'reason_location': loc,
        'reason_work_model': false,
        'reason_job_type': false,
        'total_after_filters': taf,
        'total_available': tav,
        'total_matching_catalog': tmc,
      };

  group('FeedPager', () {
    test('1ª página sem cursor; 2ª envia cursor da ÚLTIMA row; frozen_at estável',
        () async {
      final calls = <Map<String, dynamic>>[];
      final pager = FeedPager((params) async {
        calls.add(params);
        if (calls.length == 1) {
          return [
            row('a1', 90.5, taf: 25, tav: 100),
            row('a2', 80.25, taf: 25, tav: 100),
          ];
        }
        return [row('a3', 70.125)];
      }, pageSize: 2);

      final p1 = await pager.fetchNext();
      expect(p1.map((r) => r.jobId), ['a1', 'a2']);
      expect(calls[0].containsKey('p_cursor_rank'), isFalse);
      expect(calls[0].containsKey('p_cursor_id'), isFalse);
      expect(calls[0]['p_limit'], 2);
      expect(pager.hasMore, isTrue); // página cheia → talvez tenha mais
      expect(pager.totalAfterFilters, 25);
      expect(pager.totalAvailable, 100);

      final p2 = await pager.fetchNext();
      expect(p2.map((r) => r.jobId), ['a3']);
      expect(calls[1]['p_cursor_rank'], 80.25);
      expect(calls[1]['p_cursor_id'], 'a2');
      // D-7: o MESMO p_frozen_at em todas as páginas da sessão
      expect(calls[1]['p_frozen_at'], calls[0]['p_frozen_at']);
      expect(pager.hasMore, isFalse); // página curta → acabou
    });

    test('listas vazias de filtro NÃO viram args (null = sem filtro)', () async {
      late Map<String, dynamic> sent;
      final pager = FeedPager((params) async {
        sent = params;
        return const [];
      });
      await pager.fetchNext(
        areas: const [],
        locations: const [],
        workModels: const [],
        jobTypes: const [],
      );
      expect(sent.containsKey('p_filter_areas'), isFalse);
      expect(sent.containsKey('p_filter_locations'), isFalse);
      expect(sent.containsKey('p_filter_work_models'), isFalse);
      expect(sent.containsKey('p_filter_job_types'), isFalse);
    });

    test('filtros preenchidos viajam como args (resolução D-8 é do caller)',
        () async {
      late Map<String, dynamic> sent;
      final pager = FeedPager((params) async {
        sent = params;
        return const [];
      });
      await pager.fetchNext(
        areas: const ['Tecnologia'],
        locations: const ['São Paulo'],
        workModels: const ['remoto'],
        jobTypes: const ['estagio'],
      );
      expect(sent['p_filter_areas'], ['Tecnologia']);
      expect(sent['p_filter_locations'], ['São Paulo']);
      expect(sent['p_filter_work_models'], ['remoto']);
      expect(sent['p_filter_job_types'], ['estagio']);
    });

    test('sentinela do estado B: 1 row job_id null → só totais, sem mais páginas',
        () async {
      final pager = FeedPager((params) async => [
            {
              'job_id': null,
              'score': null,
              'rank_score': null,
              'reason_area': null,
              'reason_location': null,
              'reason_work_model': null,
              'reason_job_type': null,
              'total_after_filters': 0,
              'total_available': 322,
              'total_matching_catalog': 0, // #5: 0 = filtros restritivos (B)
            }
          ]);
      final rows = await pager.fetchNext();
      expect(rows, isEmpty);
      expect(pager.totalAfterFilters, 0); // "filtros zeraram"
      expect(pager.totalAvailable, 322); // mas o catálogo tem vagas
      expect(pager.totalMatchingCatalog, 0); // #5: nenhuma vaga bate → B
      expect(pager.hasMore, isFalse);
    });

    test('#5: total_matching_catalog > 0 com feed vazio = esgotou (A), não B',
        () async {
      // sentinela com matching_catalog>0 (havia relevantes, todas swipadas).
      final pager = FeedPager((params) async => [
            {
              'job_id': null,
              'score': null,
              'rank_score': null,
              'reason_area': null,
              'reason_location': null,
              'reason_work_model': null,
              'reason_job_type': null,
              'total_after_filters': 0,
              'total_available': 322,
              'total_matching_catalog': 12,
            }
          ]);
      await pager.fetchNext();
      expect(pager.totalMatchingCatalog, 12); // >0 → esgotou (A)
    });

    test('paginação completa: união das páginas sem overlap (espelho do all-ties)',
        () async {
      // 45 ids em páginas de 20 → 20+20+5
      final ids = List.generate(45, (i) => 'job_$i');
      var cursor = 0;
      final pager = FeedPager((params) async {
        expect(params['p_limit'], 20);
        final page = ids.skip(cursor).take(20).toList();
        cursor += page.length;
        var rank = 1000.0 - cursor;
        return [for (final id in page) row(id, rank -= 0.001)];
      });

      final seen = <String>{};
      while (pager.hasMore) {
        final rows = await pager.fetchNext();
        for (final r in rows) {
          expect(seen.add(r.jobId), isTrue,
              reason: 'overlap entre páginas: ${r.jobId}');
        }
      }
      expect(seen.length, 45); // zero gap
      expect(await pager.fetchNext(), isEmpty); // esgotado = no-op
    });

    test('row repetida (borda de cursor) é deduplicada, nunca duplica célula',
        () async {
      var call = 0;
      final pager = FeedPager((params) async {
        call++;
        if (call == 1) return [row('x1', 9.0), row('x2', 8.0)];
        return [row('x2', 8.0), row('x3', 7.0)]; // x2 repetida na borda
      }, pageSize: 2);
      final p1 = await pager.fetchNext();
      final p2 = await pager.fetchNext();
      expect([...p1, ...p2].map((r) => r.jobId), ['x1', 'x2', 'x3']);
    });

    test('reset reinicia sessão: cursor some e frozen_at é NOVO', () async {
      final frozens = <String>[];
      final pager = FeedPager((params) async {
        frozens.add(params['p_frozen_at'] as String);
        expect(params.containsKey('p_cursor_id'), isFalse);
        return [row('r1', 5.0)];
      }, pageSize: 2);
      await pager.fetchNext();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      pager.reset();
      expect(pager.hasMore, isTrue);
      expect(pager.totalAfterFilters, isNull);
      await pager.fetchNext();
      expect(frozens.length, 2);
      expect(frozens[0] == frozens[1], isFalse);
    });

    test('matchedReasonLabels: chips só das dimensões que casaram', () {
      final r = FeedPageRow.fromMap(row('z', 1.0, area: true, loc: true));
      expect(r.matchedReasonLabels, ['Área', 'Local']);
    });
  });
}
