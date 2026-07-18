import 'package:career_gamification/features/trilha/application/trilha_session.dart';
import 'package:career_gamification/features/trilha/domain/assist_skills_write.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spy do writer CAS 3.0B. Constrói recibos válidos via `fromRpc` e registra as
/// chamadas para provar a semântica CAS/undo da remoção reversível de skill.
class _SpySkillsWriter implements AssistSkillsWriter {
  _SpySkillsWriter({required this.baseline, this.applyOutcome = 'applied'});

  final List<String> baseline;
  final String applyOutcome; // 'applied' | 'noop' | 'stale'
  int opens = 0;
  int applies = 0;
  int undos = 0;
  List<String>? appliedExpected;
  List<String>? appliedDesired;
  List<String>? undoRestored;

  @override
  Future<AssistSkillsOpenReceipt> open({
    required String userId,
    required String operationId,
  }) async {
    opens++;
    return AssistSkillsOpenReceipt.fromRpc(<String, dynamic>{
      'status': 'opened',
      'operation_id': operationId,
      'baseline': baseline,
      'count': baseline.length,
    });
  }

  @override
  Future<AssistSkillsApplyReceipt> apply({
    required String userId,
    required String operationId,
    required List<String> expected,
    required List<String> desired,
  }) async {
    applies++;
    appliedExpected = List.of(expected);
    appliedDesired = List.of(desired);
    final applied = applyOutcome == 'applied';
    final live = applied ? desired : baseline;
    return AssistSkillsApplyReceipt.fromRpc(<String, dynamic>{
      'status': applyOutcome,
      'outcome': applyOutcome,
      'operation_id': operationId,
      'live': live,
      'resulting': live,
      'count': live.length,
      'can_undo': applied,
    });
  }

  @override
  Future<AssistSkillsUndoReceipt> undo({
    required String userId,
    required String operationId,
    required List<String> expectedRestored,
  }) async {
    undos++;
    undoRestored = List.of(expectedRestored);
    return AssistSkillsUndoReceipt.fromRpc(<String, dynamic>{
      'status': 'undone',
      'outcome': 'undone',
      'operation_id': operationId,
      'live': expectedRestored,
      'resulting': expectedRestored,
      'count': expectedRestored.length,
    });
  }
}

void main() {
  group('assistReversibleRemove(skill) — Gate 3.0E CAS/recibo/undo', () {
    test('applied → devolve undo; apply usa a lista reduzida (CAS vs baseline)',
        () async {
      final w = _SpySkillsWriter(baseline: const ['Excel', 'Python', 'SQL']);
      final restore = await assistReversibleRemove(
        'u1',
        'skill',
        'python',
        skillsWriter: w,
      );
      expect(restore, isNotNull);
      expect(w.opens, 1);
      expect(w.applies, 1);
      expect(w.appliedExpected, ['Excel', 'Python', 'SQL']); // CAS vs baseline
      expect(w.appliedDesired, ['Excel', 'SQL']); // Python removido (fold)

      await restore!();
      expect(w.undos, 1);
      expect(w.undoRestored, ['Excel', 'Python', 'SQL']); // restaura o baseline
    });

    test('casa por fold (caixa/acento): "gestao" remove "Gestão"', () async {
      final w = _SpySkillsWriter(baseline: const ['Gestão', 'Excel']);
      final restore = await assistReversibleRemove(
        'u1',
        'skill',
        'gestao',
        skillsWriter: w,
      );
      expect(restore, isNotNull);
      expect(w.appliedDesired, ['Excel']);
    });

    test('skill ausente no baseline → null, sem apply', () async {
      final w = _SpySkillsWriter(baseline: const ['Excel', 'SQL']);
      final restore = await assistReversibleRemove(
        'u1',
        'skill',
        'Python',
        skillsWriter: w,
      );
      expect(restore, isNull);
      expect(w.applies, 0);
    });

    test('apply stale → null (sem falso sucesso), sem undo', () async {
      final w = _SpySkillsWriter(
        baseline: const ['Excel', 'Python'],
        applyOutcome: 'stale',
      );
      final restore = await assistReversibleRemove(
        'u1',
        'skill',
        'Python',
        skillsWriter: w,
      );
      expect(restore, isNull);
      expect(w.applies, 1);
      expect(w.undos, 0);
    });

    test('apply noop → null (sem falso sucesso)', () async {
      final w = _SpySkillsWriter(
        baseline: const ['Excel', 'Python'],
        applyOutcome: 'noop',
      );
      final restore = await assistReversibleRemove(
        'u1',
        'skill',
        'Python',
        skillsWriter: w,
      );
      expect(restore, isNull);
    });

    test('sem writer (flag OFF) → null (nunca remove por nome)', () async {
      final restore = await assistReversibleRemove(
        'u1',
        'skill',
        'Python',
        skillsWriter: null,
      );
      expect(restore, isNull);
    });

    test('value vazio → null, sem open', () async {
      final w = _SpySkillsWriter(baseline: const ['Excel']);
      final restore = await assistReversibleRemove(
        'u1',
        'skill',
        '   ',
        skillsWriter: w,
      );
      expect(restore, isNull);
      expect(w.opens, 0);
    });
  });
}
