import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/data/models/models.dart' show SavedResume;
import 'package:career_gamification/features/profile/profile_screen.dart'
    show filterLibraryResumes;

// F5.3 — a biblioteca de Currículos é só de SAÍDAS. general sempre fora (F4.5);
// imported fora só com o Assistente ON (F5.3) — flag OFF preserva o legado.
void main() {
  SavedResume r(String id, String source) => SavedResume.fromMap({
        'id': id,
        'title': id,
        'file_path': 'u/$id.pdf',
        'created_at': '2026-07-22T10:00:00Z',
        'source': source,
      });

  final all = [
    r('m', 'manual'),
    r('a', 'adapted'),
    r('t', 'trail'),
    r('i', 'imported'),
    r('g', 'general'),
  ];

  List<String> ids(List<SavedResume> l) => l.map((e) => e.source.dbValue).toList();

  test('flag OFF: exclui só general (legado — importado FICA na lista)', () {
    final out = filterLibraryResumes(all, outputsOnly: false);
    expect(ids(out), containsAll(['manual', 'adapted', 'trail', 'imported']));
    expect(ids(out), isNot(contains('general')));
  });

  test('flag ON (outputs-only): exclui general E imported', () {
    final out = filterLibraryResumes(all, outputsOnly: true);
    expect(ids(out), containsAll(['manual', 'adapted', 'trail']));
    expect(ids(out), isNot(contains('imported')));
    expect(ids(out), isNot(contains('general')));
  });

  test('lista só com importados: vazia sob flag ON, cheia sob OFF', () {
    final onlyImported = [r('i1', 'imported'), r('i2', 'imported')];
    expect(filterLibraryResumes(onlyImported, outputsOnly: true), isEmpty);
    expect(filterLibraryResumes(onlyImported, outputsOnly: false), hasLength(2));
  });
}
