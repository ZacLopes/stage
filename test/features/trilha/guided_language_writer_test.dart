import 'package:career_gamification/features/trilha/data/guided_language_writer_supabase.dart';
import 'package:career_gamification/features/trilha/domain/guided_language_write.dart';
import 'package:flutter_test/flutter_test.dart';

const _userId = '11111111-1111-4111-8111-111111111111';

void main() {
  group('GuidedLanguageWriterSupabase.mergeLanguages', () {
    test('chama merge_guided_profile_list section=languages, normalizado', () async {
      String? fn;
      Map<String, dynamic>? params;
      final w = GuidedLanguageWriterSupabase(
        rpcCall: (function, p) async {
          fn = function;
          params = p;
          return {'status': 'applied', 'inserted': 2, 'updated': 0, 'changed': 2};
        },
      );
      final r = await w.mergeLanguages(
        userId: _userId,
        names: const [' Inglês ', 'Espanhol', 'inglês'],
      );
      expect(fn, 'merge_guided_profile_list');
      expect(params, {
        'p_user_id': _userId,
        'p_section': 'languages',
        'p_items': ['Inglês', 'Espanhol'], // dedup case-insensitive
      });
      expect(r.outcome, GuidedLanguageMergeOutcome.applied);
    });

    test('updated != 0 falha fechado', () {
      expect(
        () => GuidedLanguageMergeReceipt.fromRpc(
          {'status': 'applied', 'inserted': 1, 'updated': 1, 'changed': 2},
        ),
        throwsA(isA<GuidedLanguageWriteException>()),
      );
    });

    test('payload vazio → ArgumentError sem round-trip', () async {
      var calls = 0;
      final w = GuidedLanguageWriterSupabase(
        rpcCall: (f, p) async {
          calls++;
          return {'status': 'noop', 'inserted': 0, 'updated': 0, 'changed': 0};
        },
      );
      await expectLater(
        w.mergeLanguages(userId: _userId, names: const ['  ']),
        throwsArgumentError,
      );
      expect(calls, 0);
    });
  });

  group('GuidedLanguageWriterSupabase.setLevel', () {
    test('chama set_guided_language_level_cas com expected/new', () async {
      String? fn;
      Map<String, dynamic>? params;
      final w = GuidedLanguageWriterSupabase(
        rpcCall: (function, p) async {
          fn = function;
          params = p;
          return {'status': 'applied'};
        },
      );
      final r = await w.setLevel(
        userId: _userId,
        name: ' Inglês ',
        expectedLevel: null,
        newLevel: 'advanced',
      );
      expect(fn, 'set_guided_language_level_cas');
      expect(params, {
        'p_user_id': _userId,
        'p_name': 'Inglês',
        'p_expected_level': null,
        'p_new_level': 'advanced',
      });
      expect(r.outcome, GuidedLanguageLevelOutcome.applied);
    });

    test('stale devolve live_level', () async {
      final w = GuidedLanguageWriterSupabase(
        rpcCall: (f, p) async => {'status': 'stale', 'live_level': 'fluent'},
      );
      final r = await w.setLevel(
        userId: _userId,
        name: 'Inglês',
        expectedLevel: 'basic',
        newLevel: 'advanced',
      );
      expect(r.outcome, GuidedLanguageLevelOutcome.stale);
      expect(r.liveLevel, 'fluent');
    });

    test('nível novo inválido → ArgumentError sem round-trip', () async {
      var calls = 0;
      final w = GuidedLanguageWriterSupabase(
        rpcCall: (f, p) async {
          calls++;
          return {'status': 'applied'};
        },
      );
      await expectLater(
        w.setLevel(
          userId: _userId,
          name: 'Inglês',
          expectedLevel: null,
          newLevel: 'ninja',
        ),
        throwsArgumentError,
      );
      expect(calls, 0);
    });

    test('status desconhecido falha fechado', () {
      expect(
        () => GuidedLanguageLevelReceipt.fromRpc({'status': 'weird'}),
        throwsA(isA<GuidedLanguageWriteException>()),
      );
    });
  });

  group('GuidedLanguageWriterSupabase.removeLanguage', () {
    test('chama remove_guided_language_cas; applied devolve nível removido', () async {
      String? fn;
      Map<String, dynamic>? params;
      final w = GuidedLanguageWriterSupabase(
        rpcCall: (function, p) async {
          fn = function;
          params = p;
          return {'status': 'applied', 'level': 'advanced'};
        },
      );
      final r = await w.removeLanguage(
        userId: _userId,
        name: 'Inglês',
        expectedLevel: 'advanced',
      );
      expect(fn, 'remove_guided_language_cas');
      expect(params, {
        'p_user_id': _userId,
        'p_name': 'Inglês',
        'p_expected_level': 'advanced',
      });
      expect(r.outcome, GuidedLanguageRemoveOutcome.applied);
      expect(r.removedLevel, 'advanced');
    });

    test('applied sem nível (level null)', () async {
      final w = GuidedLanguageWriterSupabase(
        rpcCall: (f, p) async => {'status': 'applied', 'level': null},
      );
      final r = await w.removeLanguage(
        userId: _userId,
        name: 'Inglês',
        expectedLevel: null,
      );
      expect(r.outcome, GuidedLanguageRemoveOutcome.applied);
      expect(r.removedLevel, isNull);
    });

    test('stale devolve live_level; not_found', () async {
      final stale = await GuidedLanguageWriterSupabase(
        rpcCall: (f, p) async => {'status': 'stale', 'live_level': 'basic'},
      ).removeLanguage(userId: _userId, name: 'Inglês', expectedLevel: 'advanced');
      expect(stale.outcome, GuidedLanguageRemoveOutcome.stale);
      expect(stale.liveLevel, 'basic');

      final nf = await GuidedLanguageWriterSupabase(
        rpcCall: (f, p) async => {'status': 'not_found'},
      ).removeLanguage(userId: _userId, name: 'Inglês', expectedLevel: null);
      expect(nf.outcome, GuidedLanguageRemoveOutcome.notFound);
    });

    test('applied com live_level presente (contraditório) falha fechado', () {
      expect(
        () => GuidedLanguageRemoveReceipt.fromRpc(
          {'status': 'applied', 'level': 'basic', 'live_level': 'fluent'},
        ),
        throwsA(isA<GuidedLanguageWriteException>()),
      );
    });

    test('nível inválido no recibo falha fechado', () {
      expect(
        () => GuidedLanguageRemoveReceipt.fromRpc(
          {'status': 'applied', 'level': 'ninja'},
        ),
        throwsA(isA<GuidedLanguageWriteException>()),
      );
    });
  });
}
