import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/data/models/models.dart'
    show SavedResumeSource;

// F4/F4.5 — tipo estrutural do CV por `source` (não mais por prefixo de título).
void main() {
  group('SavedResumeSource', () {
    test('dbValue = name (casa com o CHECK do banco)', () {
      expect(SavedResumeSource.general.dbValue, 'general');
      expect(SavedResumeSource.trail.dbValue, 'trail');
      expect(SavedResumeSource.manual.dbValue, 'manual');
      expect(SavedResumeSource.imported.dbValue, 'imported');
      expect(SavedResumeSource.adapted.dbValue, 'adapted');
    });

    test('fromDb reconhece general e trail (novos valores)', () {
      expect(SavedResumeSource.fromDb('general'), SavedResumeSource.general);
      expect(SavedResumeSource.fromDb('trail'), SavedResumeSource.trail);
    });

    test('fromDb: null/desconhecido → manual (fallback do build antigo)', () {
      expect(SavedResumeSource.fromDb(null), SavedResumeSource.manual);
      expect(SavedResumeSource.fromDb('weird'), SavedResumeSource.manual);
    });

    test('round-trip dbValue → fromDb para todos os valores', () {
      for (final s in SavedResumeSource.values) {
        expect(SavedResumeSource.fromDb(s.dbValue), s);
      }
    });
  });
}
