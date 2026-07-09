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

  testWidgets('ChoiceInput única de 1 opção vira CTA e submete ao tocar',
      (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'intro',
      aiMessage: 'Pode ser?',
      input: const ChoiceInput(options: [StepOption(id: 'go', label: 'Bora começar')]),
    );
    await tester.pumpWidget(host(step, (a) => answer = a));
    // Renderiza como CTA de destaque (seta), não como chip miúdo.
    expect(find.text('Bora começar'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    await tester.tap(find.text('Bora começar'));
    expect(answer, isNotNull);
    expect(answer!.value, ['go']);
  });

  testWidgets('ExperienceTypeInput: multi + contador emite kinds ordenados',
      (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'exp.gate',
      aiMessage: 'q',
      input: const ExperienceTypeInput(types: [
        ExperienceTypeOption(
            id: 'estagio', label: 'Estágio', subtitle: '', icon: 'school'),
        ExperienceTypeOption(
            id: 'voluntariado',
            label: 'Voluntariado',
            subtitle: '',
            icon: 'volunteer'),
      ]),
    );
    await tester.pumpWidget(host(step, (a) => answer = a));
    await tester.tap(find.text('Estágio')); // +1
    await tester.pump();
    await tester.tap(find.text('Estágio')); // +1 → x2
    await tester.pump();
    await tester.tap(find.text('Voluntariado')); // +1
    await tester.pump();
    await tester.tap(find.text('Continuar (3)'));
    // Ordem preservada, repetição = contagem.
    expect(answer!.value, ['estagio', 'estagio', 'voluntariado']);
  });

  testWidgets('ExperienceTypeInput: "ainda não tenho" submete vazio',
      (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'exp.gate',
      aiMessage: 'q',
      input: const ExperienceTypeInput(types: [
        ExperienceTypeOption(
            id: 'estagio', label: 'Estágio', subtitle: '', icon: 'school'),
      ]),
    );
    await tester.pumpWidget(host(step, (a) => answer = a));
    await tester.tap(find.text('Ainda não tenho experiência'));
    expect(answer, isNotNull);
    expect(answer!.value, isEmpty);
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

  // ── Edição: reabre PRÉ-PREENCHIDO com a resposta anterior (todos widgets) ──

  testWidgets('edição: GuidedText reabre com o texto que já estava',
      (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'gap.desired_position',
      aiMessage: 'q',
      input: const GuidedTextInput(example: 'x'),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InlineStepInput(
          step: step,
          initialAnswer:
              StepAnswer.text('gap.desired_position', 'Desenvolvedor Front-end'),
          onSubmit: (a) => answer = a,
        ),
      ),
    ));
    // Não sumiu: o texto anterior está no campo.
    expect(find.text('Desenvolvedor Front-end'), findsOneWidget);
    await tester.tap(find.text('Enviar'));
    expect(answer!.value, 'Desenvolvedor Front-end');
  });

  testWidgets('edição: ChoiceInput múltipla reabre com o que estava marcado',
      (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'gap.workmode',
      aiMessage: 'q',
      input: const ChoiceInput(multi: true, options: [
        StepOption(id: 'a', label: 'Remoto'),
        StepOption(id: 'b', label: 'Híbrido'),
      ]),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InlineStepInput(
          step: step,
          initialAnswer: StepAnswer.choice(
              'gap.workmode', const [StepOption(id: 'a', label: 'Remoto')]),
          onSubmit: (a) => answer = a,
        ),
      ),
    ));
    // Já vem com 'a' marcado → confirmar sem tocar em nada devolve ['a'].
    await tester.tap(find.textContaining('Confirmar'));
    expect(answer!.value, ['a']);
  });

  testWidgets('edição: MonthYear reabre no mês/ano gravado', (tester) async {
    StepAnswer? answer;
    final step = ConversationStep.single(
      id: 'exp.0.start',
      aiMessage: 'q',
      input: const MonthYearInput(),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InlineStepInput(
          step: step,
          initialAnswer: StepAnswer.monthYear('exp.0.start', 2021, 3),
          onSubmit: (a) => answer = a,
        ),
      ),
    ));
    await tester.tap(find.text('Confirmar'));
    expect(answer!.value, '2021-03');
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
