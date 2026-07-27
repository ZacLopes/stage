import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/resume/services/general_resume_status.dart';

// F4.4 — status do Currículo geral: última versão + staleness (perfil mudou
// desde a versão). Best-effort: falhas nunca afirmam "desatualizado".
void main() {
  Map<String, dynamic> row({
    String id = 'row-1',
    int version = 2,
    String template = 'harvard_ats',
    String fp = 'abc',
    String? createdAt = '2026-07-22T10:00:00Z',
  }) =>
      {
        'id': id,
        'version': version,
        'template_id': template,
        'profile_fingerprint': fp,
        'created_at': createdAt,
      };

  GeneralResumeStatusLoader buildLoader({
    Map<String, dynamic>? lastRow,
    Object? fetchThrows,
  }) {
    return GeneralResumeStatusLoader(
      fetchLastVersion: (_) async {
        if (fetchThrows != null) throw fetchThrows;
        return lastRow;
      },
    );
  }

  group('StoredGeneralResumeVersion.fromRow', () {
    test('parseia row completa', () {
      final v = StoredGeneralResumeVersion.fromRow(row());
      expect(v, isNotNull);
      expect(v!.id, 'row-1');
      expect(v.version, 2);
      expect(v.templateId, 'harvard_ats');
      expect(v.fingerprint, 'abc');
      expect(v.createdAt, isNotNull);
    });

    test('row null ou campo essencial ausente → null', () {
      expect(StoredGeneralResumeVersion.fromRow(null), isNull);
      expect(
          StoredGeneralResumeVersion.fromRow(
              row()..remove('profile_fingerprint')),
          isNull);
      expect(StoredGeneralResumeVersion.fromRow(row()..remove('version')),
          isNull);
    });

    test('created_at inválido → createdAt null (não quebra)', () {
      final v = StoredGeneralResumeVersion.fromRow(row(createdAt: 'lixo'));
      expect(v, isNotNull);
      expect(v!.createdAt, isNull);
    });
  });

  group('GeneralResumeStatusLoader.load', () {
    test('sem versão persistida → status neutro', () async {
      final s = await buildLoader(lastRow: null).load('u');
      expect(s.hasVersion, isFalse);
      expect(s.lastVersion, isNull);
    });

    test('com versão persistida → devolve os metadados', () async {
      final s = await buildLoader(lastRow: row(fp: 'abc')).load('u');
      expect(s.hasVersion, isTrue);
      expect(s.lastVersion!.version, 2);
      expect(s.lastVersion!.fingerprint, 'abc');
    });

    test('falha ao ler a última versão → status neutro', () async {
      final s = await buildLoader(fetchThrows: Exception('select down'))
          .load('u');
      expect(s.hasVersion, isFalse);
    });

    // O selo "Perfil mudou" saiu em 27/07 (decisão do fundador): ele mentia na
    // virada do mês, porque o fingerprint era tirado do texto formatado — que
    // inclui o sufixo "(previsto)" derivado do relógio. O loader não computa
    // mais fingerprint nenhum; ele só lê a última versão.
    test('o loader NÃO computa fingerprint do perfil atual', () async {
      // Se voltasse a computar, precisaria de uma dependência a mais — e o
      // construtor de um argumento só é a garantia disso.
      final loader = GeneralResumeStatusLoader(
        fetchLastVersion: (_) async => row(fp: 'x'),
      );
      final s = await loader.load('u');
      expect(s.lastVersion!.fingerprint, 'x');
    });
  });
}
