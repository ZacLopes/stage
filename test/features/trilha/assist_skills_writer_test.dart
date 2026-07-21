import 'package:career_gamification/features/trilha/data/assist_skills_writer_supabase.dart';
import 'package:career_gamification/features/trilha/domain/assist_skills_write.dart';
import 'package:flutter_test/flutter_test.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _operationId = '22222222-2222-4222-8222-222222222222';

void main() {
  test(
    'open reserva o baseline autoritativo com o mesmo operation id',
    () async {
      String? calledFunction;
      Map<String, dynamic>? calledParams;
      final writer = AssistSkillsWriterSupabase(
        rpcCall: (function, params) async {
          calledFunction = function;
          calledParams = params;
          return {
            'status': 'opened',
            'operation_id': _operationId,
            'baseline': ['Excel', 'Gestão'],
            'count': 2,
          };
        },
      );

      final receipt = await writer.open(
        userId: _userId,
        operationId: _operationId,
      );

      expect(calledFunction, 'open_assist_skills_edit_v1');
      expect(calledParams, {
        'p_user_id': _userId,
        'p_operation_id': _operationId,
      });
      expect(receipt.baseline, ['Excel', 'Gestão']);
      expect(receipt.replayed, isFalse);
    },
  );

  test(
    'apply chama a RPC CAS com payload normalizado e aceita recibo',
    () async {
      String? calledFunction;
      Map<String, dynamic>? calledParams;
      final writer = AssistSkillsWriterSupabase(
        rpcCall: (function, params) async {
          calledFunction = function;
          calledParams = params;
          return {
            'status': 'applied',
            'outcome': 'applied',
            'operation_id': _operationId,
            'live': ['Gestão', 'SQL'],
            'resulting': ['Gestão', 'SQL'],
            'count': 2,
            'can_undo': true,
          };
        },
      );

      final receipt = await writer.apply(
        userId: _userId,
        operationId: _operationId,
        expected: const [' Gestão ', 'GESTAO'],
        desired: const ['Gestão', ' SQL ', 'sql'],
      );

      expect(calledFunction, 'apply_assist_skills_edit_v1');
      expect(calledParams, {
        'p_user_id': _userId,
        'p_operation_id': _operationId,
        'p_expected_names': ['Gestão'],
        'p_names': ['Gestão', 'SQL'],
      });
      expect(receipt.outcome, AssistSkillsApplyOutcome.applied);
      expect(receipt.canUndo, isTrue);
    },
  );

  test(
    'replay aplicado separa estado resultante do live editado depois',
    () async {
      final writer = AssistSkillsWriterSupabase(
        rpcCall: (function, params) async => {
          'status': 'replay',
          'outcome': 'applied',
          'operation_id': _operationId,
          'live': ['Excel', 'SQL', 'Go'],
          'resulting': ['Excel', 'SQL'],
          'count': 3,
          'can_undo': false,
        },
      );

      final receipt = await writer.apply(
        userId: _userId,
        operationId: _operationId,
        expected: const ['Excel'],
        desired: const ['Excel', 'SQL'],
      );

      expect(receipt.replayed, isTrue);
      expect(receipt.outcome, AssistSkillsApplyOutcome.applied);
      expect(receipt.live, ['Excel', 'SQL', 'Go']);
      expect(receipt.resulting, ['Excel', 'SQL']);
      expect(receipt.canUndo, isFalse);
    },
  );

  test('stale aceita live com duplicata semântica de writer legado', () async {
    final writer = AssistSkillsWriterSupabase(
      rpcCall: (function, params) async => {
        'status': 'stale',
        'outcome': 'stale',
        'operation_id': _operationId,
        'live': [' Gestão ', '', 'Gestao'],
        'resulting': ['Excel'],
        'count': 3,
        'can_undo': false,
      },
    );

    final receipt = await writer.apply(
      userId: _userId,
      operationId: _operationId,
      expected: const ['Excel'],
      desired: const ['Excel', 'SQL'],
    );

    expect(receipt.outcome, AssistSkillsApplyOutcome.stale);
    expect(receipt.confirmed, isFalse);
    expect(receipt.live, [' Gestão ', '', 'Gestao']);
  });

  test('undo stale aceita live com duplicata semântica', () async {
    final writer = AssistSkillsWriterSupabase(
      rpcCall: (function, params) async => {
        'status': 'stale',
        'outcome': 'stale',
        'operation_id': _operationId,
        'live': ['Gestão', 'Gestao'],
        'resulting': ['Excel'],
        'count': 2,
      },
    );

    final receipt = await writer.undo(
      userId: _userId,
      operationId: _operationId,
      expectedRestored: const ['Excel'],
    );

    expect(receipt.outcome, AssistSkillsUndoOutcome.stale);
    expect(receipt.live, ['Gestão', 'Gestao']);
  });

  test('undo chama RPC própria e valida o estado restaurado', () async {
    String? calledFunction;
    Map<String, dynamic>? calledParams;
    final writer = AssistSkillsWriterSupabase(
      rpcCall: (function, params) async {
        calledFunction = function;
        calledParams = params;
        return {
          'status': 'undone',
          'outcome': 'undone',
          'operation_id': _operationId,
          'live': ['Excel'],
          'resulting': ['Excel'],
          'count': 1,
        };
      },
    );

    final receipt = await writer.undo(
      userId: _userId,
      operationId: _operationId,
      expectedRestored: const ['Excel'],
    );

    expect(calledFunction, 'undo_assist_skills_edit_v1');
    expect(calledParams, {
      'p_user_id': _userId,
      'p_operation_id': _operationId,
    });
    expect(receipt.outcome, AssistSkillsUndoOutcome.undone);
  });

  test('replay de undo aceita live alterado depois', () async {
    final writer = AssistSkillsWriterSupabase(
      rpcCall: (function, params) async => {
        'status': 'replay',
        'outcome': 'undone',
        'operation_id': _operationId,
        'live': ['Excel', 'Go'],
        'resulting': ['Excel'],
        'count': 2,
      },
    );

    final receipt = await writer.undo(
      userId: _userId,
      operationId: _operationId,
      expectedRestored: const ['Excel'],
    );

    expect(receipt.replayed, isTrue);
    expect(receipt.live, ['Excel', 'Go']);
    expect(receipt.resulting, ['Excel']);
  });

  test('parsers falham fechados para recibos contraditórios', () async {
    final malformed = <Object?>[
      null,
      const [],
      {
        'status': 'applied',
        'outcome': 'applied',
        'operation_id': _operationId,
        'live': ['Excel'],
        'resulting': ['Excel'],
        'count': 2,
        'can_undo': true,
      },
      {
        'status': 'noop',
        'outcome': 'noop',
        'operation_id': _operationId,
        'live': ['Excel'],
        'resulting': ['Excel'],
        'count': 1,
        'can_undo': true,
      },
      {
        'status': 'mystery',
        'outcome': 'noop',
        'operation_id': _operationId,
        'live': ['Excel'],
        'resulting': ['Excel'],
        'count': 1,
        'can_undo': false,
      },
    ];

    for (final raw in malformed) {
      expect(
        () => AssistSkillsApplyReceipt.fromRpc(raw),
        throwsA(isA<AssistSkillsWriteContractException>()),
      );
    }
  });

  test(
    'fresh success com resulting diferente do desired falha fechado',
    () async {
      final writer = AssistSkillsWriterSupabase(
        rpcCall: (function, params) async => {
          'status': 'applied',
          'outcome': 'applied',
          'operation_id': _operationId,
          'live': ['Excel', 'SQL'],
          'resulting': ['Excel', 'Go'],
          'count': 2,
          'can_undo': true,
        },
      );

      await expectLater(
        writer.apply(
          userId: _userId,
          operationId: _operationId,
          expected: const ['Excel'],
          desired: const ['Excel', 'SQL'],
        ),
        throwsA(isA<AssistSkillsWriteContractException>()),
      );
    },
  );

  test('replay não oferece undo quando live diverge do resulting', () async {
    final writer = AssistSkillsWriterSupabase(
      rpcCall: (function, params) async => {
        'status': 'replay',
        'outcome': 'applied',
        'operation_id': _operationId,
        'live': ['Excel', 'SQL', 'Go'],
        'resulting': ['Excel', 'SQL'],
        'count': 3,
        'can_undo': true,
      },
    );

    await expectLater(
      writer.apply(
        userId: _userId,
        operationId: _operationId,
        expected: const ['Excel'],
        desired: const ['Excel', 'SQL'],
      ),
      throwsA(isA<AssistSkillsWriteContractException>()),
    );
  });

  test('erro de rede propaga e nunca é reinterpretado como noop', () async {
    final writer = AssistSkillsWriterSupabase(
      rpcCall: (function, params) =>
          Future<Object?>.error(StateError('network')),
    );

    await expectLater(
      writer.apply(
        userId: _userId,
        operationId: _operationId,
        expected: const ['Excel'],
        desired: const ['Excel', 'SQL'],
      ),
      throwsStateError,
    );
  });

  test('gerador cria UUIDs v4 distintos', () {
    final a = newAssistSkillsOperationId();
    final b = newAssistSkillsOperationId();
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
      r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(a, matches(pattern));
    expect(b, matches(pattern));
    expect(a, isNot(b));
  });
}
