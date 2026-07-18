import 'package:career_gamification/features/trilha/data/guided_skills_writer_supabase.dart';
import 'package:career_gamification/features/trilha/domain/guided_skills_write.dart';
import 'package:flutter_test/flutter_test.dart';

const _userId = '11111111-1111-4111-8111-111111111111';

void main() {
  group('GuidedSkillsWriterSupabase.mergeSkills', () {
    test('chama merge_guided_profile_list com section=skills e payload '
        'normalizado; aceita recibo applied', () async {
      String? calledFunction;
      Map<String, dynamic>? calledParams;
      var calls = 0;
      final writer = GuidedSkillsWriterSupabase(
        rpcCall: (function, params) async {
          calls++;
          calledFunction = function;
          calledParams = params;
          return {
            'status': 'applied',
            'inserted': 2,
            'updated': 0,
            'changed': 2,
          };
        },
      );

      final receipt = await writer.mergeSkills(
        userId: _userId,
        names: const [' Excel ', 'Python'],
      );

      expect(calls, 1); // exatamente uma RPC por operação lógica
      expect(calledFunction, 'merge_guided_profile_list');
      expect(calledParams, {
        'p_user_id': _userId,
        'p_section': 'skills',
        'p_items': ['Excel', 'Python'],
      });
      expect(receipt.outcome, GuidedSkillsMergeOutcome.applied);
      expect(receipt.inserted, 2);
      expect(receipt.changed, isTrue);
    });

    test(
      'retry idempotente: recibo noop é aceito e não é sucesso "aplicado"',
      () async {
        final writer = GuidedSkillsWriterSupabase(
          rpcCall: (function, params) async => {
            'status': 'noop',
            'inserted': 0,
            'updated': 0,
            'changed': 0,
          },
        );

        final receipt = await writer.mergeSkills(
          userId: _userId,
          names: const ['Excel'],
        );

        expect(receipt.outcome, GuidedSkillsMergeOutcome.noop);
        expect(receipt.inserted, 0);
        expect(receipt.changed, isFalse);
      },
    );

    test(
      'normaliza e dedup grafias equivalentes no payload antes do envio',
      () async {
        Map<String, dynamic>? calledParams;
        final writer = GuidedSkillsWriterSupabase(
          rpcCall: (function, params) async {
            calledParams = params;
            return {
              'status': 'applied',
              'inserted': 1,
              'updated': 0,
              'changed': 1,
            };
          },
        );

        await writer.mergeSkills(
          userId: _userId,
          names: const ['Excel', 'excel', ' EXCEL ', 'Gestão', 'Gestao'],
        );

        // Grafias equivalentes (caixa/acento/whitespace) colapsam, preservando a
        // primeira grafia e a ordem.
        expect(calledParams?['p_items'], ['Excel', 'Gestão']);
      },
    );

    test('userId vazio → ArgumentError, sem round-trip', () async {
      var calls = 0;
      final writer = GuidedSkillsWriterSupabase(
        rpcCall: (function, params) async {
          calls++;
          return {'status': 'noop', 'inserted': 0, 'updated': 0, 'changed': 0};
        },
      );

      await expectLater(
        writer.mergeSkills(userId: '  ', names: const ['Excel']),
        throwsArgumentError,
      );
      expect(calls, 0);
    });

    test(
      'payload só de vazios/whitespace → ArgumentError, sem round-trip',
      () async {
        var calls = 0;
        final writer = GuidedSkillsWriterSupabase(
          rpcCall: (function, params) async {
            calls++;
            return {
              'status': 'noop',
              'inserted': 0,
              'updated': 0,
              'changed': 0,
            };
          },
        );

        await expectLater(
          writer.mergeSkills(userId: _userId, names: const ['', '   ']),
          throwsArgumentError,
        );
        expect(calls, 0);
      },
    );

    test('payload > 50 itens → ArgumentError, sem round-trip', () async {
      var calls = 0;
      final writer = GuidedSkillsWriterSupabase(
        rpcCall: (function, params) async {
          calls++;
          return {
            'status': 'applied',
            'inserted': 1,
            'updated': 0,
            'changed': 1,
          };
        },
      );
      final many = List<String>.generate(51, (i) => 'Skill $i');

      await expectLater(
        writer.mergeSkills(userId: _userId, names: many),
        throwsArgumentError,
      );
      expect(calls, 0);
    });

    test(
      'erro do RPC (ex.: limite de 12) propaga fail-closed, não vira sucesso',
      () async {
        final writer = GuidedSkillsWriterSupabase(
          rpcCall: (function, params) async =>
              throw StateError('too_many_items'),
        );

        await expectLater(
          writer.mergeSkills(userId: _userId, names: const ['Excel']),
          throwsStateError,
        );
      },
    );
  });

  group('GuidedSkillsMergeReceipt.fromRpc — fail-closed', () {
    test('resposta não-objeto falha fechado', () {
      expect(
        () => GuidedSkillsMergeReceipt.fromRpc('applied'),
        throwsA(isA<GuidedProfileMergeContractException>()),
      );
    });

    test('status desconhecido falha fechado', () {
      expect(
        () => GuidedSkillsMergeReceipt.fromRpc({
          'status': 'stale',
          'inserted': 0,
          'updated': 0,
          'changed': 0,
        }),
        throwsA(isA<GuidedProfileMergeContractException>()),
      );
    });

    test('updated != 0 falha fechado (skills é aditivo puro)', () {
      expect(
        () => GuidedSkillsMergeReceipt.fromRpc({
          'status': 'applied',
          'inserted': 1,
          'updated': 1,
          'changed': 2,
        }),
        throwsA(isA<GuidedProfileMergeContractException>()),
      );
    });

    test('changed incoerente com inserted+updated falha fechado', () {
      expect(
        () => GuidedSkillsMergeReceipt.fromRpc({
          'status': 'applied',
          'inserted': 1,
          'updated': 0,
          'changed': 5,
        }),
        throwsA(isA<GuidedProfileMergeContractException>()),
      );
    });

    test('status applied com changed 0 (contradição) falha fechado', () {
      expect(
        () => GuidedSkillsMergeReceipt.fromRpc({
          'status': 'applied',
          'inserted': 0,
          'updated': 0,
          'changed': 0,
        }),
        throwsA(isA<GuidedProfileMergeContractException>()),
      );
    });

    test('status noop com changed > 0 (contradição) falha fechado', () {
      expect(
        () => GuidedSkillsMergeReceipt.fromRpc({
          'status': 'noop',
          'inserted': 1,
          'updated': 0,
          'changed': 1,
        }),
        throwsA(isA<GuidedProfileMergeContractException>()),
      );
    });

    test('contadores de tipo errado falham fechado', () {
      expect(
        () => GuidedSkillsMergeReceipt.fromRpc({
          'status': 'applied',
          'inserted': '2',
          'updated': 0,
          'changed': 2,
        }),
        throwsA(isA<GuidedProfileMergeContractException>()),
      );
    });

    test('contadores negativos falham fechado', () {
      expect(
        () => GuidedSkillsMergeReceipt.fromRpc({
          'status': 'applied',
          'inserted': -1,
          'updated': 0,
          'changed': -1,
        }),
        throwsA(isA<GuidedProfileMergeContractException>()),
      );
    });
  });
}
