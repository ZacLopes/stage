import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/data/models/models.dart'
    show SavedResume, SavedResumeSource;
import 'package:career_gamification/features/jobs/utils/original_source.dart';

// Fase 6 F6.0 — escolha do documento "Original" no toggle da preview do CV
// adaptado. Antes: `inFilter(['imported','manual']) + limit(1)` por recência.
// Agora: precedência explícita (fonte atual → importada recente → saída
// recente), com `adapted` fora.

SavedResume _r(
  String id, {
  required SavedResumeSource source,
  required String createdAt,
  bool isCurrentSource = false,
  String? filePath,
}) =>
    SavedResume(
      id: id,
      title: 'CV $id',
      filePath: filePath ?? 'uid/$id.pdf',
      createdAt: DateTime.parse(createdAt),
      source: source,
      isCurrentSource: isCurrentSource,
    );

void main() {
  group('resolveOriginalSource', () {
    test('lista vazia → null (tela mantém o fallback de ResumeData)', () {
      expect(resolveOriginalSource([]), isNull);
    });

    test('candidato único importado é escolhido', () {
      final only = _r('a',
          source: SavedResumeSource.imported, createdAt: '2026-05-01T10:00:00Z');
      expect(resolveOriginalSource([only])?.id, 'a');
    });

    test('importado vence documento de saída mais recente', () {
      // Regressão medida: quem importou em maio e mexeu no editor em junho
      // via o CV do editor como "original".
      final imported = _r('imp',
          source: SavedResumeSource.imported, createdAt: '2026-05-01T10:00:00Z');
      final manual = _r('man',
          source: SavedResumeSource.manual, createdAt: '2026-06-01T10:00:00Z');
      expect(resolveOriginalSource([manual, imported])?.id, 'imp');
    });

    test('is_current_source vence a importada mais recente', () {
      final current = _r('cur',
          source: SavedResumeSource.imported,
          createdAt: '2026-05-01T10:00:00Z',
          isCurrentSource: true);
      final newer = _r('new',
          source: SavedResumeSource.imported, createdAt: '2026-07-01T10:00:00Z');
      expect(resolveOriginalSource([newer, current])?.id, 'cur');
    });

    test('entre importadas sem marca, a mais recente vence', () {
      final older = _r('old',
          source: SavedResumeSource.imported, createdAt: '2026-05-01T10:00:00Z');
      final newer = _r('new',
          source: SavedResumeSource.imported, createdAt: '2026-07-01T10:00:00Z');
      expect(resolveOriginalSource([older, newer])?.id, 'new');
    });

    test('REGRESSÃO F4.5: só trail continua sendo candidato', () {
      // O backfill 20260722120000 reclassifica manual+"Currículo Stage%" →
      // trail. Com a lista literal antiga, estes 50 usuários ficavam SEM
      // nenhum original.
      final trail = _r('t',
          source: SavedResumeSource.trail, createdAt: '2026-06-01T10:00:00Z');
      expect(resolveOriginalSource([trail])?.id, 't');
    });

    test('só general (Currículo geral da F4) é candidato', () {
      final general = _r('g',
          source: SavedResumeSource.general, createdAt: '2026-07-01T10:00:00Z');
      expect(resolveOriginalSource([general])?.id, 'g');
    });

    test('adapted NUNCA é escolhido — sozinho devolve null', () {
      final adapted = _r('ad',
          source: SavedResumeSource.adapted, createdAt: '2026-07-20T10:00:00Z');
      expect(resolveOriginalSource([adapted]), isNull);
    });

    test('adapted mais recente não rouba de um documento de saída', () {
      final adapted = _r('ad',
          source: SavedResumeSource.adapted, createdAt: '2026-07-20T10:00:00Z');
      final trail = _r('t',
          source: SavedResumeSource.trail, createdAt: '2026-06-01T10:00:00Z');
      expect(resolveOriginalSource([adapted, trail])?.id, 't');
    });

    test('entre saídas, a mais recente vence independente do tipo', () {
      final manual = _r('m',
          source: SavedResumeSource.manual, createdAt: '2026-05-01T10:00:00Z');
      final trail = _r('t',
          source: SavedResumeSource.trail, createdAt: '2026-06-01T10:00:00Z');
      final general = _r('g',
          source: SavedResumeSource.general, createdAt: '2026-07-01T10:00:00Z');
      expect(resolveOriginalSource([manual, general, trail])?.id, 'g');
    });

    test('timestamps iguais: desempate por id DESC (contrato do banco)', () {
      final a = _r('aaa',
          source: SavedResumeSource.imported, createdAt: '2026-06-01T10:00:00Z');
      final z = _r('zzz',
          source: SavedResumeSource.imported, createdAt: '2026-06-01T10:00:00Z');
      expect(resolveOriginalSource([a, z])?.id, 'zzz');
      expect(resolveOriginalSource([z, a])?.id, 'zzz');
    });

    test('duas marcadas como atuais: a mais recente vence (não assume o CHECK)',
        () {
      final older = _r('old',
          source: SavedResumeSource.imported,
          createdAt: '2026-05-01T10:00:00Z',
          isCurrentSource: true);
      final newer = _r('new',
          source: SavedResumeSource.imported,
          createdAt: '2026-07-01T10:00:00Z',
          isCurrentSource: true);
      expect(resolveOriginalSource([older, newer])?.id, 'new');
    });

    test('ordem de entrada não altera o resultado', () {
      final rows = [
        _r('imp',
            source: SavedResumeSource.imported,
            createdAt: '2026-05-01T10:00:00Z'),
        _r('ad',
            source: SavedResumeSource.adapted,
            createdAt: '2026-07-20T10:00:00Z'),
        _r('g',
            source: SavedResumeSource.general,
            createdAt: '2026-07-01T10:00:00Z'),
      ];
      expect(resolveOriginalSource(rows)?.id, 'imp');
      expect(resolveOriginalSource(rows.reversed.toList())?.id, 'imp');
    });

    test('cenário real do usuário com 3 documentos (d5a5323f em prod)', () {
      // 2 imported + 1 manual + 1 adapted. Nenhum marcado como atual (0/738
      // linhas em prod têm is_current_source) → importada mais recente.
      final rows = [
        _r('imp1',
            source: SavedResumeSource.imported,
            createdAt: '2026-05-13T10:00:00Z'),
        _r('imp2',
            source: SavedResumeSource.imported,
            createdAt: '2026-05-28T10:00:00Z'),
        _r('man',
            source: SavedResumeSource.manual,
            createdAt: '2026-05-29T10:00:00Z'),
        _r('ad',
            source: SavedResumeSource.adapted,
            createdAt: '2026-05-30T10:40:12Z'),
      ];
      expect(resolveOriginalSource(rows)?.id, 'imp2');
    });
  });
}
