import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/trilha/application/conversation_controller.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';
import 'package:career_gamification/features/trilha/presentation/widgets/inline/inline_step_input.dart';
import 'package:career_gamification/features/trilha/presentation/widgets/inline/trilha_answer_card.dart';

/// Widget tests dos widgets inline novos (chat v2 — F1). Verificam que cada um
/// coleta o dado e submete no formato certo do domínio.
void main() {
  Widget host(ConversationStep step, void Function(StepAnswer) onSubmit) =>
      MaterialApp(
        home: Scaffold(body: InlineStepInput(step: step, onSubmit: onSubmit)),
      );

  testWidgets('ChoiceInput única submete o id ao tocar', (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'gap.area',
      aiMessage: 'q',
      input: const ChoiceInput(options: [
        StepOption(id: 'tech', label: 'Tecnologia'),
        StepOption(id: 'mkt', label: 'Marketing'),
      ]),
    );
    await tester.pumpWidget(host(step, (a) => answer = a));
    await tester.tap(find.text('Tecnologia'));
    expect(answer, isNotNull);
    expect(answer!.value, ['tech']);
  });

  testWidgets('ChoiceInput múltipla: seleciona e confirma', (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'gap.workmode',
      aiMessage: 'q',
      input: const ChoiceInput(multi: true, options: [
        StepOption(id: 'a', label: 'Remoto'),
        StepOption(id: 'b', label: 'Híbrido'),
      ]),
    );
    await tester.pumpWidget(host(step, (a) => answer = a));
    await tester.tap(find.text('Remoto'));
    await tester.pump();
    await tester.tap(find.text('Híbrido'));
    await tester.pump();
    await tester.tap(find.textContaining('Confirmar'));
    expect(answer!.value, ['a', 'b']);
  });

  testWidgets('slider de idioma submete o id do nível (default Avançado)',
      (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'lang.level.Inglês',
      aiMessage: 'q',
      input: const ChoiceInput(compact: true, options: [
        StepOption(id: 'basic', label: 'Básico'),
        StepOption(id: 'intermediate', label: 'Intermediário'),
        StepOption(id: 'advanced', label: 'Avançado'),
        StepOption(id: 'fluent', label: 'Fluente'),
        StepOption(id: 'native', label: 'Nativo'),
      ]),
    );
    await tester.pumpWidget(host(step, (a) => answer = a));
    // índice default = floor(5/2) = 2 → 'advanced'
    await tester.tap(find.text('Confirmar'));
    expect(answer!.value, ['advanced']);
  });

  testWidgets('mês/ano (roda): Confirmar usa o mês+ano atuais por padrão',
      (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'exp.0.start',
      aiMessage: 'q',
      input: const MonthYearInput(),
    );
    await tester.pumpWidget(host(step, (a) => answer = a));
    await tester.tap(find.text('Confirmar'));
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    expect(answer!.value, '${now.year}-$mm');
  });

  testWidgets('slider de PORTUGUÊS começa em Nativo por padrão',
      (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'lang.level.Português',
      aiMessage: 'q',
      input: const ChoiceInput(compact: true, options: [
        StepOption(id: 'basic', label: 'Básico'),
        StepOption(id: 'intermediate', label: 'Intermediário'),
        StepOption(id: 'advanced', label: 'Avançado'),
        StepOption(id: 'fluent', label: 'Fluente'),
        StepOption(id: 'native', label: 'Nativo'),
      ]),
    );
    await tester.pumpWidget(host(step, (a) => answer = a));
    // Português → default no último (native), não no meio.
    await tester.tap(find.text('Confirmar'));
    expect(answer!.value, ['native']);
  });

  testWidgets('GuidedText: Enviar desabilitado vazio, habilita com texto',
      (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'exp.0.ofazia',
      aiMessage: 'q',
      input: const GuidedTextInput(example: 'organizei eventos'),
    );
    await tester.pumpWidget(host(step, (a) => answer = a));
    await tester.tap(find.text('Enviar'));
    expect(answer, isNull); // vazio não submete
    await tester.enterText(find.byType(TextField), 'Monitor de cálculo');
    await tester.pump();
    await tester.tap(find.text('Enviar'));
    expect(answer!.value, 'Monitor de cálculo');
  });

  testWidgets('TrilhaAnswerCard mostra resposta em chips + ✎ chama onEdit',
      (tester) async {
    var edited = false;
    final ex = ConversationExchange(
      step: ConversationStep.single(
        id: 'gap.skills',
        aiMessage: 'q',
        input: const ChoiceInput(options: [StepOption(id: 'p', label: 'Python')]),
      ),
      answer: StepAnswer.choice('gap.skills', const [
        StepOption(id: 'Python', label: 'Python'),
        StepOption(id: 'SQL', label: 'SQL'),
      ]),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TrilhaAnswerCard(exchange: ex, onEdit: () => edited = true),
      ),
    ));
    expect(find.text('Python'), findsOneWidget);
    expect(find.text('SQL'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_rounded));
    expect(edited, true);
  });

  testWidgets('TrilhaAnswerCard sem onEdit não mostra ✎', (tester) async {
    final ex = ConversationExchange(
      step: ConversationStep.single(
        id: 'exp.0.ofazia',
        aiMessage: 'q',
        input: const GuidedTextInput(example: 'x'),
        reversible: false,
      ),
      answer: StepAnswer.text('exp.0.ofazia', 'Fiz coisas'),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TrilhaAnswerCard(exchange: ex)),
    ));
    expect(find.text('Fiz coisas'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsNothing);
  });
}
