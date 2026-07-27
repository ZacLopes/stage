import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/data/models/models.dart' show SavedResume;
import 'package:career_gamification/features/profile/presentation/widgets/imported_source_card.dart';

// F5.2 — card "Fonte importada" em Perfil → Dados: escolha da fonte, status
// honesto e a view pura (nome/data/status/ações).
void main() {
  SavedResume res({
    required String id,
    required String source,
    required String created,
    String title = 't',
    String? originalFilename,
    String? extractionStatus,
    bool isCurrent = false,
  }) =>
      SavedResume.fromMap({
        'id': id,
        'title': title,
        'file_path': 'u/$id.pdf',
        'created_at': created,
        'source': source,
        if (originalFilename != null) 'original_filename': originalFilename,
        if (extractionStatus != null) 'extraction_status': extractionStatus,
        'is_current_source': isCurrent,
      });

  // 27/07 (decisão do fundador): com a flag ON a F5.3 tira `imported` da lista
  // de Currículos, então este card vira a ÚNICA porta desses arquivos. Expor só
  // a fonte atual deixava os demais inalcançáveis — medido em prod: 41 usuários
  // com mais de um importado, 54 arquivos órfãos.
  group('pickImportedSources — todas as fontes, atual primeiro', () {
    test('sem importados → lista vazia', () {
      expect(
        pickImportedSources([
          res(id: 'a', source: 'manual', created: '2026-07-01T00:00:00Z'),
        ]),
        isEmpty,
      );
    });

    test('devolve TODAS as fontes importadas, não só uma', () {
      final list = [
        res(id: 'a', source: 'imported', created: '2026-07-01T00:00:00Z'),
        res(id: 'b', source: 'imported', created: '2026-07-05T00:00:00Z'),
        res(id: 'c', source: 'imported', created: '2026-07-03T00:00:00Z'),
        res(id: 'x', source: 'manual', created: '2026-07-09T00:00:00Z'),
      ];
      final all = pickImportedSources(list);
      expect(all.length, 3);
      expect(all.map((r) => r.id), containsAll(<String>['a', 'b', 'c']));
      // Não vaza documento de outro tipo.
      expect(all.any((r) => r.id == 'x'), isFalse);
    });

    test('a fonte ATUAL vem primeiro, mesmo sendo a mais antiga', () {
      final list = [
        res(id: 'novo', source: 'imported', created: '2026-07-09T00:00:00Z'),
        res(
          id: 'atual',
          source: 'imported',
          created: '2026-07-01T00:00:00Z',
          isCurrent: true,
        ),
      ];
      expect(pickImportedSources(list).map((r) => r.id).toList(),
          <String>['atual', 'novo']);
    });

    test('sem fonte atual: ordena por recência, desempate por id', () {
      final list = [
        res(id: 'aaa', source: 'imported', created: '2026-07-01T00:00:00Z'),
        res(id: 'zzz', source: 'imported', created: '2026-07-01T00:00:00Z'),
        res(id: 'mid', source: 'imported', created: '2026-07-05T00:00:00Z'),
      ];
      expect(pickImportedSources(list).map((r) => r.id).toList(),
          <String>['mid', 'zzz', 'aaa']);
    });

    test('pickImportedSource continua sendo a primeira da lista', () {
      final list = [
        res(id: 'novo', source: 'imported', created: '2026-07-09T00:00:00Z'),
        res(
          id: 'atual',
          source: 'imported',
          created: '2026-07-01T00:00:00Z',
          isCurrent: true,
        ),
      ];
      expect(pickImportedSource(list)!.id, pickImportedSources(list).first.id);
    });
  });

  group('pickImportedSource', () {
    test('sem importado → null', () {
      final list = [
        res(id: 'a', source: 'manual', created: '2026-07-01T00:00:00Z'),
        res(id: 'b', source: 'adapted', created: '2026-07-02T00:00:00Z'),
      ];
      expect(pickImportedSource(list), isNull);
    });

    test('prefere a fonte ATUAL sobre a mais recente', () {
      final list = [
        res(id: 'novo', source: 'imported', created: '2026-07-10T00:00:00Z'),
        res(
            id: 'atual',
            source: 'imported',
            created: '2026-07-01T00:00:00Z',
            isCurrent: true),
      ];
      expect(pickImportedSource(list)!.id, 'atual');
    });

    test('sem "atual" → a mais recente importada', () {
      final list = [
        res(id: 'velho', source: 'imported', created: '2026-07-01T00:00:00Z'),
        res(id: 'novo', source: 'imported', created: '2026-07-10T00:00:00Z'),
        res(id: 'manual', source: 'manual', created: '2026-07-20T00:00:00Z'),
      ];
      expect(pickImportedSource(list)!.id, 'novo');
    });

    test('empate de created_at → desempata por id DESC (determinístico)', () {
      final list = [
        res(id: 'aaa', source: 'imported', created: '2026-07-10T00:00:00Z'),
        res(id: 'zzz', source: 'imported', created: '2026-07-10T00:00:00Z'),
      ];
      // Rodar 2x garante estabilidade (independe da ordem de entrada).
      expect(pickImportedSource(list)!.id, 'zzz');
      expect(pickImportedSource(list.reversed.toList())!.id, 'zzz');
    });
  });

  group('importedStatusLabel', () {
    test('ready → arquivo lido; failed → erro; pending/extracting → processando',
        () {
      expect(importedStatusLabel('ready'), 'Arquivo lido');
      expect(importedStatusLabel('failed'), 'Não consegui ler este arquivo');
      expect(importedStatusLabel('pending'), 'Processando…');
      expect(importedStatusLabel('extracting'), 'Processando…');
    });

    test('null/desconhecido (legado) → sem afirmação', () {
      expect(importedStatusLabel(null), isNull);
      expect(importedStatusLabel('weird'), isNull);
    });
  });

  group('importedRemovalMessage — honesto nos dois casos', () {
    test('perfil COM conteúdo: tranquiliza (os fatos ficam no perfil)', () {
      final msg = importedRemovalMessage(profileHasContent: true);
      expect(msg, contains('NÃO apaga'));
      expect(msg, contains('continuam salvos'));
      // Não pode assustar quem não corre risco.
      expect(msg, isNot(contains('se perdem')));
    });

    test('perfil VAZIO: AVISA que a informação se perde (não promete nada)', () {
      final msg = importedRemovalMessage(profileHasContent: false);
      expect(msg, contains('ainda não foram para o seu perfil'));
      expect(msg, contains('se perdem'));
      // A promessa falsa NÃO pode aparecer neste caso.
      expect(msg, isNot(contains('continuam salvos')));
    });

    test('as duas mensagens são diferentes', () {
      expect(
        importedRemovalMessage(profileHasContent: true),
        isNot(importedRemovalMessage(profileHasContent: false)),
      );
    });
  });

  group('ImportedSourceCardView', () {
    testWidgets('mostra nome, data, status e as ações; tap dispara callbacks', (
      tester,
    ) async {
      var viewed = false;
      var removed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportedSourceCardView(
              name: 'meu_cv_2026.pdf',
              dateLabel: '22/07/2026',
              statusLabel: 'Dados extraídos para o seu perfil',
              onView: () => viewed = true,
              onRemove: () => removed = true,
            ),
          ),
        ),
      );
      expect(find.text('Fonte importada'), findsOneWidget);
      expect(find.text('meu_cv_2026.pdf'), findsOneWidget);
      expect(find.text('Importado em 22/07/2026'), findsOneWidget);
      expect(find.text('Dados extraídos para o seu perfil'), findsOneWidget);
      expect(find.text('Ver'), findsOneWidget);
      expect(find.text('Remover'), findsOneWidget);

      await tester.tap(find.text('Ver'));
      await tester.tap(find.text('Remover'));
      expect(viewed, isTrue);
      expect(removed, isTrue);
    });

    testWidgets('sem statusLabel: não mostra linha de status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ImportedSourceCardView(
              name: 'Meu Currículo',
              dateLabel: '01/05/2026',
            ),
          ),
        ),
      );
      expect(find.text('Meu Currículo'), findsOneWidget);
      expect(find.text('Importado em 01/05/2026'), findsOneWidget);
      // Ações presentes mesmo sem status.
      expect(find.text('Ver'), findsOneWidget);
      expect(find.text('Remover'), findsOneWidget);
    });

    // F5.4 — Substituir (com fonte) e a variante VAZIA (sem fonte).
    testWidgets('com fonte: mostra Substituir e dispara o callback', (
      tester,
    ) async {
      var replaced = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportedSourceCardView(
              name: 'cv.pdf',
              dateLabel: '22/07/2026',
              onReplace: () => replaced = true,
            ),
          ),
        ),
      );
      expect(find.text('Substituir'), findsOneWidget);
      await tester.tap(find.text('Substituir'));
      expect(replaced, isTrue);
    });

    testWidgets('SEM fonte: card não some — oferece importar (mata o beco)', (
      tester,
    ) async {
      var imported = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportedSourceCardView.empty(
              onImport: () => imported = true,
            ),
          ),
        ),
      );
      expect(find.text('Fonte importada'), findsOneWidget);
      expect(find.text('Nenhum currículo importado'), findsOneWidget);
      expect(find.text('Importar currículo'), findsOneWidget);
      // Sem fonte não há o que ver/substituir/remover.
      expect(find.text('Ver'), findsNothing);
      expect(find.text('Substituir'), findsNothing);
      expect(find.text('Remover'), findsNothing);
      await tester.tap(find.text('Importar currículo'));
      expect(imported, isTrue);
    });

    testWidgets('isRemoving: ações desabilitadas + spinner', (tester) async {
      var removed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportedSourceCardView(
              name: 'x.pdf',
              dateLabel: '22/07/2026',
              isRemoving: true,
              onRemove: () => removed = true,
              onView: () {},
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Remover'));
      expect(removed, isFalse); // desabilitado enquanto remove
    });
  });
}
