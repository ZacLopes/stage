import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';
import 'package:career_gamification/features/trilha/presentation/widgets/chat_bubbles.dart';
import 'package:career_gamification/features/trilha/presentation/widgets/step_input_view.dart';

/// Cobre o SuggestPickInput — o "meio-termo" de skills: chips sugeridos +
/// busca no catálogo (typeahead) + adicionar livre. PLANO-FASE-6.
void main() {
  Future<StepAnswer?> pumpPicker(WidgetTester tester) async {
    StepAnswer? answer;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepInputView(
          step: const ConversationStep(
            id: 'gap.skills',
            aiMessages: ['x'],
            input: SuggestPickInput(
              suggestions: ['Excel', 'Python'],
              catalog: ['JavaScript', 'SQL', 'Power BI'],
            ),
          ),
          onSubmit: (a) => answer = a,
        ),
      ),
    ));
    await tester.pump();
    return answer;
  }

  testWidgets('mostra sugestões, adiciona por toque, busca no catálogo e texto livre',
      (tester) async {
    await pumpPicker(tester);

    // Chips sugeridos aparecem.
    expect(find.text('Excel'), findsOneWidget);
    expect(find.text('Python'), findsOneWidget);

    // Toca numa sugestão → vira selecionada + botão "Continuar (1)".
    await tester.tap(find.text('Excel'));
    await tester.pump();
    expect(find.text('Continuar (1)'), findsOneWidget);

    // Busca no catálogo: digita "sq" → aparece "SQL" (typeahead local).
    await tester.enterText(find.byType(TextField), 'sq');
    await tester.pump();
    expect(find.text('SQL'), findsOneWidget);
    await tester.tap(find.text('SQL'));
    await tester.pump();
    expect(find.text('Continuar (2)'), findsOneWidget);

    // Texto livre: digita algo fora do catálogo → "+ Adicionar".
    await tester.enterText(find.byType(TextField), 'Bitrix24');
    await tester.pump();
    expect(find.textContaining('Adicionar'), findsOneWidget);
    await tester.tap(find.textContaining('Adicionar'));
    await tester.pump();
    expect(find.text('Continuar (3)'), findsOneWidget);
  });

  testWidgets('Continuar submete a lista escolhida (nomes)', (tester) async {
    StepAnswer? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepInputView(
          step: const ConversationStep(
            id: 'gap.skills',
            aiMessages: ['x'],
            input: SuggestPickInput(suggestions: ['Excel', 'Python']),
          ),
          onSubmit: (a) => captured = a,
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Excel'));
    await tester.pump();
    await tester.tap(find.text('Python'));
    await tester.pump();
    await tester.tap(find.text('Continuar (2)'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.stepId, 'gap.skills');
    expect(captured!.value, ['Excel', 'Python']); // value = nomes
  });

  testWidgets('AsyncSuggestInput: carrega sugestões da IA e deixa adicionar',
      (tester) async {
    final completer = Completer<List<String>>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepInputView(
          step: ConversationStep(
            id: 'gap.skills.more',
            aiMessages: const ['x'],
            input: AsyncSuggestInput(load: () => completer.future),
          ),
          onSubmit: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(TypingDots), findsOneWidget);

    completer.complete(['Power BI', 'SQL']);
    await tester.pump();
    await tester.pump();

    expect(find.text('Power BI'), findsOneWidget);
    await tester.tap(find.text('Power BI'));
    await tester.pump();
    expect(find.text('Continuar (1)'), findsOneWidget);
  });

  testWidgets('AsyncSuggestInput: sem sugestões → "Pular" submete vazio',
      (tester) async {
    StepAnswer? captured;
    final completer = Completer<List<String>>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepInputView(
          step: ConversationStep(
            id: 'gap.skills.more',
            aiMessages: const ['x'],
            input: AsyncSuggestInput(load: () => completer.future),
          ),
          onSubmit: (a) => captured = a,
        ),
      ),
    ));
    await tester.pump();
    completer.complete(const []);
    await tester.pump();
    await tester.pump();

    expect(find.text('Pular'), findsOneWidget);
    await tester.tap(find.text('Pular'));
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.value, isEmpty);
  });

  testWidgets('suggestionsLoader substitui o placeholder estático (pela área)',
      (tester) async {
    final completer = Completer<List<String>>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepInputView(
          step: ConversationStep(
            id: 'gap.skills',
            aiMessages: const ['x'],
            input: SuggestPickInput(
              suggestions: const ['Excel', 'Pacote Office'], // placeholder
              suggestionsLoader: () => completer.future,
            ),
          ),
          onSubmit: (_) {},
        ),
      ),
    ));
    await tester.pump();
    // Placeholder estático aparece antes do loader resolver.
    expect(find.text('Excel'), findsOneWidget);

    // Loader resolve com sugestões pela área (ex.: Tecnologia).
    completer.complete(['Python', 'SQL']);
    await tester.pump();
    await tester.pump();

    expect(find.text('Python'), findsOneWidget);
    expect(find.text('SQL'), findsOneWidget);
    expect(find.text('Excel'), findsNothing); // substituiu o placeholder
  });

  testWidgets('minSelections: "Continuar" só libera ao atingir o mínimo (3)',
      (tester) async {
    StepAnswer? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepInputView(
          step: const ConversationStep(
            id: 'gap.skills',
            aiMessages: ['x'],
            input: SuggestPickInput(
              suggestions: ['Python', 'SQL', 'Git', 'CSS'],
              minSelections: 3,
            ),
          ),
          onSubmit: (a) => captured = a,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Escolha pelo menos 3'), findsOneWidget);
    await tester.tap(find.text('Python'));
    await tester.pump();
    expect(find.text('Faltam 2'), findsOneWidget);
    await tester.tap(find.text('SQL'));
    await tester.pump();
    expect(find.text('Faltam 1'), findsOneWidget);
    await tester.tap(find.text('Git'));
    await tester.pump();
    expect(find.text('Continuar (3)'), findsOneWidget);

    await tester.tap(find.text('Continuar (3)'));
    await tester.pump();
    expect(captured, isNotNull);
    expect((captured!.value as List).length, 3);
  });

  testWidgets('MonthYear vira chips: escolhe mês + ano e confirma',
      (tester) async {
    StepAnswer? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepInputView(
          step: const ConversationStep(
            id: 'exp.0.start',
            aiMessages: ['x'],
            input: MonthYearInput(),
          ),
          onSubmit: (a) => captured = a,
        ),
      ),
    ));
    await tester.pump();

    final year = DateTime.now().year;
    await tester.tap(find.text('Mar'));
    await tester.pump();
    await tester.tap(find.text('$year'));
    await tester.pump();
    await tester.tap(find.text('Confirmar'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.value, '$year-03'); // 'YYYY-MM' (março = 03)
  });

  testWidgets('remover chip selecionado: anima saída e some da contagem',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepInputView(
          step: const ConversationStep(
            id: 'gap.skills',
            aiMessages: ['x'],
            input: SuggestPickInput(suggestions: ['Python', 'SQL']),
          ),
          onSubmit: (_) {},
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Python'));
    await tester.pump();
    expect(find.text('Continuar (1)'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250)); // entrada assenta

    // Toca no chip selecionado pra remover → após a animação (~200ms), some.
    await tester.tap(find.text('Python'));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();
    expect(find.text('Continuar (1)'), findsNothing);
  });

  testWidgets('escolha única, 1 opção: vira CTA (botão) e submete', (tester) async {
    StepAnswer? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepInputView(
          step: const ConversationStep(
            id: 'intro',
            aiMessages: ['x'],
            input: ChoiceInput(options: [StepOption(id: 'go', label: 'Pode!')]),
          ),
          onSubmit: (a) => captured = a,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Pode!'), findsOneWidget);
    await tester.tap(find.text('Pode!'));
    await tester.pump();
    expect(captured!.value, ['go']);
  });

  testWidgets('escolha única, 2+ opções: tiles, toque submete', (tester) async {
    StepAnswer? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepInputView(
          step: const ConversationStep(
            id: 'exp.gate',
            aiMessages: ['x'],
            input: ChoiceInput(options: [
              StepOption(id: 'yes', label: 'Tenho'),
              StepOption(id: 'no', label: 'Não tenho'),
            ]),
          ),
          onSubmit: (a) => captured = a,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Tenho'), findsOneWidget);
    expect(find.text('Não tenho'), findsOneWidget);
    await tester.tap(find.text('Tenho'));
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.value, ['yes']);
  });
}
