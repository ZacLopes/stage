import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/data/models/models.dart'
    show SavedResume, SavedResumeSource;

// F5.1 — SavedResume carrega os metadados de FONTE importada (colunas de
// integridade lidas do banco; escritas só server-side). Aditivo e
// retrocompatível: rows legadas (sem os campos) parseiam sem perda.
void main() {
  group('SavedResume.fromMap — metadados de import', () {
    test('row do fluxo NOVO: carrega filename/status/current/clientId', () {
      final r = SavedResume.fromMap({
        'id': 'r1',
        'title': 'Currículo importado',
        'file_path': 'u1/imports/abc.pdf',
        'created_at': '2026-07-22T10:00:00Z',
        'source': 'imported',
        'original_filename': 'meu_cv_2026.pdf',
        'extraction_status': 'ready',
        'is_current_source': true,
        'client_import_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      });
      expect(r.source, SavedResumeSource.imported);
      expect(r.originalFilename, 'meu_cv_2026.pdf');
      expect(r.extractionStatus, 'ready');
      expect(r.isCurrentSource, isTrue);
      expect(r.clientImportId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    });

    test('row LEGADA (sem os campos novos): nulls e current=false, sem perda',
        () {
      final r = SavedResume.fromMap({
        'id': 'r2',
        'title': 'Meu Currículo',
        'file_path': 'u1/2.pdf',
        'created_at': '2026-05-01T10:00:00Z',
        'source': 'imported',
      });
      expect(r.originalFilename, isNull);
      expect(r.extractionStatus, isNull);
      expect(r.isCurrentSource, isFalse);
      expect(r.clientImportId, isNull);
      // Campos que já existiam continuam.
      expect(r.title, 'Meu Currículo');
      expect(r.source, SavedResumeSource.imported);
    });

    test('is_current_source null → false (default do banco)', () {
      final r = SavedResume.fromMap({
        'id': 'r3',
        'title': 't',
        'file_path': 'u1/3.pdf',
        'created_at': '2026-07-01T10:00:00Z',
        'source': 'imported',
        'is_current_source': null,
      });
      expect(r.isCurrentSource, isFalse);
    });

    test('copyWith preserva os metadados de import', () {
      final r = SavedResume.fromMap({
        'id': 'r4',
        'title': 't',
        'file_path': 'u1/imports/x.pdf',
        'created_at': '2026-07-22T10:00:00Z',
        'source': 'imported',
        'original_filename': 'orig.pdf',
        'extraction_status': 'ready',
        'is_current_source': true,
        'client_import_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      });
      final c = r.copyWith(title: 'Novo título');
      expect(c.title, 'Novo título');
      expect(c.originalFilename, 'orig.pdf');
      expect(c.extractionStatus, 'ready');
      expect(c.isCurrentSource, isTrue);
      expect(c.clientImportId, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    });
  });
}
