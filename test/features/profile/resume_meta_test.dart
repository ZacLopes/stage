// Testes das funções puras da biblioteca de currículos.
//
// O alvo principal é `resolveActiveResume`: ela decide o que aparece no herói
// e NUNCA pode devolver null quando existe pelo menos um currículo elegível —
// "nenhum em uso" é um estado que a tela não sabe explicar.
//
// ⚠️ Quando a fatia 3 criar o backfill SQL de `is_active_for_apply`, a regra do
// SQL tem que bater com estes testes. Cliente e servidor discordando faz o
// herói piscar de um currículo pro outro no primeiro refresh.

import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/data/models/models.dart';
import 'package:career_gamification/features/profile/utils/resume_meta.dart';

SavedResume _cv(
  String id, {
  SavedResumeSource source = SavedResumeSource.manual,
  DateTime? createdAt,
  bool legacy = false,
  String title = 'Currículo',
}) {
  return SavedResume(
    id: id,
    title: title,
    filePath: 'user/$id.pdf',
    createdAt: createdAt ?? DateTime(2026, 8, 1),
    source: source,
    isLatestLegacySource: legacy,
  );
}

void main() {
  group('resolveActiveResume', () {
    test('lista vazia devolve null', () {
      expect(resolveActiveResume([]), isNull);
    });

    test('com um único elegível, devolve ele — o caso de 89% da base', () {
      final a = _cv('a');
      expect(resolveActiveResume([a])?.id, 'a');
    });

    test('prefere a linha legada que alimentou o perfil, mesmo sendo antiga',
        () {
      final novo = _cv('novo', createdAt: DateTime(2026, 8, 15));
      final legado = _cv(
        'legado',
        source: SavedResumeSource.imported,
        createdAt: DateTime(2026, 5, 2),
        legacy: true,
      );
      expect(resolveActiveResume([novo, legado])?.id, 'legado');
    });

    test('sem linha legada, cai no mais recente', () {
      final velho = _cv('velho', createdAt: DateTime(2026, 6, 1));
      final novo = _cv('novo', createdAt: DateTime(2026, 8, 10));
      expect(resolveActiveResume([velho, novo])?.id, 'novo');
    });

    test('nunca elege um adaptado — ele pertence a uma vaga', () {
      final adaptado = _cv(
        'adaptado',
        source: SavedResumeSource.adapted,
        createdAt: DateTime(2026, 8, 20),
      );
      final manual = _cv('manual', createdAt: DateTime(2026, 6, 1));
      expect(resolveActiveResume([adaptado, manual])?.id, 'manual');
    });

    test('só adaptados devolve null em vez de eleger um inelegível', () {
      final a = _cv('a', source: SavedResumeSource.adapted);
      expect(resolveActiveResume([a]), isNull);
    });

    test('empate de data desempata por id — ordem TOTAL, sem piscar', () {
      final mesmaData = DateTime(2026, 8, 14, 10, 30);
      final a = _cv('aaa', createdAt: mesmaData);
      final b = _cv('bbb', createdAt: mesmaData);
      final r1 = resolveActiveResume([a, b])?.id;
      final r2 = resolveActiveResume([b, a])?.id;
      expect(r1, r2, reason: 'a ordem de entrada não pode mudar o resultado');
    });

    test('não muta a lista recebida', () {
      final lista = [
        _cv('velho', createdAt: DateTime(2026, 6, 1)),
        _cv('novo', createdAt: DateTime(2026, 8, 1)),
      ];
      resolveActiveResume(lista);
      expect(lista.first.id, 'velho');
    });
  });

  group('formatBytes', () {
    test('usa vírgula decimal — o público é brasileiro', () {
      expect(formatBytes(1024 * 1024 * 3 ~/ 2), contains(','));
      expect(formatBytes(1024 * 1024 * 3 ~/ 2), endsWith('MB'));
    });

    test('KB para arquivos típicos de currículo', () {
      expect(formatBytes(180 * 1024), '180 KB');
    });

    test('bytes crus abaixo de 1 KB', () {
      expect(formatBytes(512), '512 B');
    });
  });

  group('formatShortDate', () {
    test('omite o ano corrente pra caber na linha de metadado', () {
      final d = DateTime(2026, 8, 14);
      expect(formatShortDate(d, now: DateTime(2026, 8, 20)), '14 de agosto');
    });

    test('mostra o ano quando é outro', () {
      final d = DateTime(2025, 3, 2);
      expect(
        formatShortDate(d, now: DateTime(2026, 8, 20)),
        '2 de março de 2025',
      );
    });
  });

  group('buildMetaLine', () {
    test('omite campos ausentes sem deixar separador órfão', () {
      final linha = buildMetaLine(
        source: SavedResumeSource.imported,
        createdAt: DateTime(2026, 8, 14),
        now: DateTime(2026, 8, 20),
      );
      expect(linha, 'Importado · 14 de agosto');
      expect(linha, isNot(contains('· ·')));
      expect(linha.endsWith('·'), isFalse);
    });

    test('completa conforme os fatos assíncronos chegam', () {
      final linha = buildMetaLine(
        source: SavedResumeSource.imported,
        createdAt: DateTime(2026, 8, 14),
        pages: 2,
        bytes: 240 * 1024,
        now: DateTime(2026, 8, 20),
      );
      expect(linha, 'Importado · 14 de agosto · 2 páginas · 240 KB');
    });

    test('singular de página', () {
      expect(formatPages(1), '1 página');
      expect(formatPages(3), '3 páginas');
    });
  });

  group('findLikelyDuplicates', () {
    test('agrupa por tamanho E páginas — 54% dos multi-CV têm cópia', () {
      final a = _cv('a');
      final b = _cv('b');
      final c = _cv('c');
      final dups = findLikelyDuplicates([a, b, c], {
        'a': const ResumeFileFacts(bytes: 1000, pages: 2),
        'b': const ResumeFileFacts(bytes: 1000, pages: 2),
        'c': const ResumeFileFacts(bytes: 2000, pages: 1),
      });
      expect(dups, {'a', 'b'});
    });

    test('mesmo tamanho mas páginas diferentes NÃO é cópia', () {
      final a = _cv('a');
      final b = _cv('b');
      final dups = findLikelyDuplicates([a, b], {
        'a': const ResumeFileFacts(bytes: 1000, pages: 2),
        'b': const ResumeFileFacts(bytes: 1000, pages: 4),
      });
      expect(dups, isEmpty);
    });

    test('fatos incompletos nunca viram acusação de cópia', () {
      final a = _cv('a');
      final b = _cv('b');
      final dups = findLikelyDuplicates([a, b], {
        'a': const ResumeFileFacts(bytes: 1000),
        'b': const ResumeFileFacts(bytes: 1000),
      });
      expect(dups, isEmpty, reason: 'sem contagem de páginas, não afirma nada');
    });
  });

  group('resolveUniqueTitle', () {
    test('resolve a colisão de "Meu Currículo" — 687 linhas em prod', () {
      expect(
        resolveUniqueTitle('Meu Currículo', ['Meu Currículo']),
        'Meu Currículo (2)',
      );
    });

    test('pula sufixos já usados', () {
      expect(
        resolveUniqueTitle(
          'Meu Currículo',
          ['Meu Currículo', 'Meu Currículo (2)'],
        ),
        'Meu Currículo (3)',
      );
    });

    test('sem colisão devolve o próprio título', () {
      expect(resolveUniqueTitle('Currículo Tech', ['Outro']), 'Currículo Tech');
    });

    test('colisão é case-insensitive', () {
      expect(
        resolveUniqueTitle('meu currículo', ['MEU CURRÍCULO']),
        'meu currículo (2)',
      );
    });
  });

  group('describeSource', () {
    test('fala como estudante, não como banco de dados', () {
      expect(describeSource(SavedResumeSource.imported), 'Importado');
      expect(describeSource(SavedResumeSource.manual), 'Feito no Stage');
      expect(describeSource(SavedResumeSource.adapted), 'Adaptado');
    });
  });
}
