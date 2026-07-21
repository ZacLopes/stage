import 'package:career_gamification/features/trilha/application/import_apply_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImportApplyOutcome.fromRpc — agregado honesto (Gate 3.0I)', () {
    test('sucesso limpo: tudo aplicado, promoveu', () {
      final o = ImportApplyOutcome.fromRpc({
        'applied': ['skill:Docker', 'summary'],
        'stale': [],
        'rejected': [],
        'failed': [],
        'promoted': true,
      });
      expect(o.appliedCount, 2);
      expect(o.isCleanSuccess, isTrue);
      expect(o.isPartial, isFalse);
      expect(o.isHardFailure, isFalse);
    });

    test('parcial: promoveu, mas parte manteve manual (stale) e rejeitou', () {
      final o = ImportApplyOutcome.fromRpc({
        'applied': ['skill:Go'],
        'stale': ['language:Inglês'],
        'rejected': ['experience+:Dev'],
        'failed': [],
        'promoted': true,
      });
      expect(o.appliedCount, 1);
      expect(o.staleCount, 1);
      expect(o.rejectedCount, 1);
      expect(o.isPartial, isTrue);
      expect(o.isCleanSuccess, isFalse);
      expect(o.isHardFailure, isFalse);
    });

    test('falha dura: rollback global, não promoveu', () {
      final o = ImportApplyOutcome.fromRpc({
        'applied': [],
        'stale': [],
        'rejected': [],
        'failed': ['apply_failed:XX000'],
        'promoted': false,
      });
      expect(o.isHardFailure, isTrue);
      expect(o.isCleanSuccess, isFalse);
      expect(o.isPartial, isFalse);
    });

    test('fail-closed: retorno não-mapa vira falha dura, nunca sucesso', () {
      for (final bad in [null, 'oops', 42, <dynamic>[]]) {
        final o = ImportApplyOutcome.fromRpc(bad);
        expect(o.promoted, isFalse);
        expect(o.isHardFailure, isTrue,
            reason: 'entrada inválida $bad devia ser falha dura');
      }
    });

    test('coerção robusta de tipos nas listas (ignora null, stringifica)', () {
      final o = ImportApplyOutcome.fromRpc({
        'applied': ['a', null, 2],
        'promoted': true,
      });
      expect(o.applied, ['a', '2']);
      expect(o.stale, isEmpty);
      expect(o.failed, isEmpty);
    });
  });
}
