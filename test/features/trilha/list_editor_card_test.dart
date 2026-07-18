import 'package:career_gamification/features/trilha/presentation/trilha_chat_controller.dart';
import 'package:career_gamification/features/trilha/presentation/widgets/list_editor_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ListEditorItem _item({
  required AssistEditStatus status,
  String resultMessage = '',
  List<String> suggestions = const [],
}) {
  return ListEditorItem(
    id: 'card-1',
    operationId: '22222222-2222-4222-8222-222222222222',
    kind: 'skill',
    title: 'Suas habilidades',
    initial: const ['Excel'],
    suggestions: suggestions,
    status: status,
  )..resultMessage = resultMessage;
}

Widget _app(ListEditorItem item) {
  return MaterialApp(
    home: Scaffold(
      body: ListEditorCard(
        item: item,
        onApply: (added, removed) async {},
        onCancel: () {},
        onUndo: () {},
      ),
    ),
  );
}

void main() {
  testWidgets('noop não mostra resumo falso de skills alteradas', (
    tester,
  ) async {
    final item = _item(
      status: AssistEditStatus.applied,
      resultMessage: 'Esse estado já estava salvo; nada foi regravado.',
    );

    await tester.pumpWidget(_app(item));

    expect(find.text('Skills já estavam assim'), findsOneWidget);
    expect(find.text('Skills atualizadas'), findsNothing);
    expect(find.text('Adicionei'), findsNothing);
    expect(find.text('Tirei'), findsNothing);
  });

  testWidgets('undo usa copy temporal sem afirmar o estado vivo atual', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_item(status: AssistEditStatus.undone)));

    expect(find.text('A alteração deste card foi desfeita.'), findsOneWidget);
    expect(find.textContaining('voltaram como estavam'), findsNothing);
  });

  testWidgets('tentativa sem confirmação congela delta e bloqueia cancel', (
    tester,
  ) async {
    final item = _item(
      status: AssistEditStatus.pending,
      suggestions: const ['SQL', 'Power BI'],
    );
    var cancelCalls = 0;
    final applied = <({List<String> added, List<String> removed})>[];
    Widget buildCard() => MaterialApp(
      home: Scaffold(
        body: ListEditorCard(
          item: item,
          onApply: (added, removed) async {
            applied.add((added: added, removed: removed));
          },
          onCancel: () => cancelCalls++,
          onUndo: () {},
        ),
      ),
    );
    await tester.pumpWidget(buildCard());

    await tester.tap(find.text('Excel'));
    await tester.pump();
    await tester.tap(find.text('SQL'));
    await tester.pump();
    item.hasUnconfirmedChanges = true;
    await tester.pumpWidget(buildCard());

    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Sem confirmação'), findsOneWidget);

    // Nenhum controle de edição altera o delta depois do envio ambíguo.
    await tester.tap(find.text('Excel'));
    await tester.tap(find.text('SQL'));
    await tester.tap(find.text('Power BI'));
    await tester.tap(find.text('Sem confirmação'));
    await tester.pump();
    expect(cancelCalls, 0);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(applied, hasLength(1));
    expect(applied.single.added, ['SQL']);
    expect(applied.single.removed, ['Excel']);
  });
}
