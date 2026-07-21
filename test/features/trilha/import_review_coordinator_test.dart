import 'dart:math';

import 'package:career_gamification/features/trilha/application/import_review_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('importClientId — uuid v4 (Gate 3.0I)', () {
    final re = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

    test('formato uuid v4 válido (versão 4 + variante 10xx)', () {
      for (var i = 0; i < 200; i++) {
        expect(re.hasMatch(importClientId()), isTrue,
            reason: 'uuid inválido na iteração $i');
      }
    });

    test('determinístico com rng semeado; distinto entre sementes', () {
      final a = importClientId(Random(42));
      final b = importClientId(Random(42));
      final c = importClientId(Random(43));
      expect(a, b); // mesma semente → mesmo id
      expect(a, isNot(c));
      expect(re.hasMatch(a), isTrue);
    });
  });

  group('importCanonicalPath', () {
    test('bate com o path que begin_import_source valida', () {
      expect(importCanonicalPath('user-1', 'abc-123'),
          'user-1/imports/abc-123.pdf');
    });
  });

  group('parseBeginImportResult', () {
    test('extrai candidate_id + attempt_id (com trim)', () {
      final r = parseBeginImportResult({
        'candidate_id': ' cand-1 ',
        'attempt_id': 'att-1',
        'file_path': 'x',
        'replayed': false,
      });
      expect(r?.candidateId, 'cand-1');
      expect(r?.attemptId, 'att-1');
    });

    test('fail-closed: faltando qualquer id → null', () {
      expect(parseBeginImportResult({'candidate_id': 'c'}), isNull);
      expect(parseBeginImportResult({'attempt_id': 'a'}), isNull);
      expect(parseBeginImportResult({'candidate_id': '', 'attempt_id': 'a'}),
          isNull);
      expect(parseBeginImportResult(null), isNull);
      expect(parseBeginImportResult('nope'), isNull);
    });
  });
}
