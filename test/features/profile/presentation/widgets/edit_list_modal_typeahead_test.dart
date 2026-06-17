import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/profile/presentation/widgets/edit_list_modal.dart';

// P5 Fase C: typeahead canônico no EditListModal. Suggestions vêm do
// skills_catalog (vazio quando a flag skills_typeahead_v1 está OFF).
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('typeahead: digitar filtra sugestões; tocar adiciona e limpa', (tester) async {
    var saved = <String>[];
    await tester.pumpWidget(host(EditListModal(
      title: 'Editar Skills',
      inputLabel: 'Skill',
      initialItems: const [],
      suggestions: const ['Python', 'JavaScript', 'Java', 'Comunicação'],
      onSave: (l) => saved = l,
    )));

    // Sem texto digitado → nenhuma sugestão renderizada.
    expect(find.text('JavaScript'), findsNothing);

    // 'jav' casa JavaScript e Java (contains, case-insensível); Python fora.
    await tester.enterText(find.byType(TextField), 'jav');
    await tester.pump();
    expect(find.text('JavaScript'), findsOneWidget);
    expect(find.text('Java'), findsOneWidget);
    expect(find.text('Python'), findsNothing);

    // Tocar na sugestão adiciona como chip e limpa o input (some o resto).
    await tester.tap(find.text('JavaScript'));
    await tester.pump();
    expect(find.text('JavaScript'), findsOneWidget); // agora chip
    expect(find.text('Java'), findsNothing); // input limpo → sem sugestões

    // Acento-insensível: 'comunica' casa 'Comunicação'.
    await tester.enterText(find.byType(TextField), 'comunica');
    await tester.pump();
    expect(find.text('Comunicação'), findsOneWidget);

    // Salvar entrega a lista com o item adicionado pela sugestão.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(saved, contains('JavaScript'));
  });

  testWidgets('sem suggestions (flag OFF) → nenhum typeahead', (tester) async {
    await tester.pumpWidget(host(EditListModal(
      title: 'Editar Skills',
      inputLabel: 'Skill',
      initialItems: const [],
      suggestions: const [],
      onSave: (_) {},
    )));
    await tester.enterText(find.byType(TextField), 'jav');
    await tester.pump();
    // Sem catálogo, nada de sugestão (comportamento texto-livre atual).
    expect(find.text('JavaScript'), findsNothing);
    expect(find.text('Java'), findsNothing);
  });
}
