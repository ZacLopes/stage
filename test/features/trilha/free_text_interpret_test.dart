// F4 — texto livre interpretado por IA no chat da trilha. Cobre o roteamento
// por tipo de input, o mapeamento texto→opção, o fallback failure-safe, o cap
// de multisseleção, a trava de reentrância (_busy) e a restauração do input ao
// editar um card por texto livre. Sem rede: o StepInterpreter é injetado.

import 'dart:async';

import 'package:career_gamification/features/trilha/application/conversation_controller.dart';
import 'package:career_gamification/features/trilha/application/trilha_session.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';
import 'package:career_gamification/features/trilha/presentation/trilha_chat_controller.dart';
import 'package:career_gamification/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Recorder das respostas gravadas (forward via onAnswer + edição via saveAnswer).
  late List<StepAnswer> saved;
  // Resposta canned da "IA" — reconfigurável por teste.
  StepInterpretation? Function(List<Map<String, String>> options)? responder;
  // Pra testar a trava de reentrância: gateia a resposta da IA.
  Completer<StepInterpretation?>? gate;

  Future<StepInterpretation?> fakeInterpret({
    required String stepId,
    required String question,
    required String freeText,
    required List<Map<String, String>> options,
    bool multi = false,
  }) async {
    if (gate != null) return gate!.future;
    return responder?.call(options);
  }

  setUp(() {
    saved = [];
    responder = null;
    gate = null;
  });

  ChoiceInput choice(List<(String, String)> opts,
          {bool multi = false, int? max}) =>
      ChoiceInput(
        options: [for (final o in opts) StepOption(id: o.$1, label: o.$2)],
        multi: multi,
        maxSelections: max,
      );

  // Constrói o controller já em `converse` com o 1º passo revelado.
  Future<TrilhaChatController> setup(List<ConversationStep> steps) async {
    Future<void> save(StepAnswer a) async => saved.add(a);
    final session = TrilhaSession(
      controller: ConversationController(steps, onAnswer: save),
      saveAnswer: save,
    );
    final c = TrilhaChatController(
      userId: 'u1',
      sessionBuilder: (_) async => session,
      interpret: fakeInterpret,
    );
    await c.start(); // gate
    await c.chooseZero(); // → converse + revela o 1º passo
    return c;
  }

  test('GuidedText: texto livre responde direto, sem IA', () async {
    final c = await setup([
      ConversationStep.single(
        id: 'gap.summary',
        aiMessage: 'Fala de você',
        input: const GuidedTextInput(example: 'ex'),
      ),
    ]);
    addTearDown(c.dispose);

    await c.submitFreeText('  sou dev júnior  ');

    expect(saved, hasLength(1));
    expect(saved.single.stepId, 'gap.summary');
    expect(saved.single.value, 'sou dev júnior'); // trimado
  });

  test('Choice (multi): mapeia texto → ids reais e despacha', () async {
    responder = (_) =>
        const StepInterpretation(matchedIds: ['py', 'sql'], confidence: 'high');
    final c = await setup([
      ConversationStep.single(
        id: 'gap.skills',
        aiMessage: 'Quais skills?',
        input: choice([('py', 'Python'), ('sql', 'SQL'), ('go', 'Go')],
            multi: true),
      ),
    ]);
    addTearDown(c.dispose);

    await c.submitFreeText('mexo com python e sql');

    expect(saved, hasLength(1));
    expect(saved.single.value, ['py', 'sql']);
  });

  test('Choice (multi): ids alucinados são filtrados pelas options', () async {
    // 'rust' não existe nas opções → cai fora; sobra 'py'.
    responder = (_) =>
        const StepInterpretation(matchedIds: ['py', 'rust'], confidence: 'high');
    final c = await setup([
      ConversationStep.single(
        id: 'gap.skills',
        aiMessage: 'Quais skills?',
        input: choice([('py', 'Python'), ('sql', 'SQL')], multi: true),
      ),
    ]);
    addTearDown(c.dispose);

    await c.submitFreeText('python e rust');

    expect(saved.single.value, ['py']);
  });

  test('Choice (multi): respeita maxSelections (cap preservando ordem)',
      () async {
    responder = (_) => const StepInterpretation(
        matchedIds: ['a', 'b', 'c'], confidence: 'high');
    final c = await setup([
      ConversationStep.single(
        id: 'gap.areas',
        aiMessage: 'Áreas?',
        input: choice([('a', 'A'), ('b', 'B'), ('c', 'C')], multi: true, max: 2),
      ),
    ]);
    addTearDown(c.dispose);

    await c.submitFreeText('a, b e c');

    expect(saved.single.value, ['a', 'b']); // cortou em 2
  });

  test('Choice (single): pega só a 1ª opção mesmo se a IA devolve várias',
      () async {
    responder = (_) =>
        const StepInterpretation(matchedIds: ['b', 'c'], confidence: 'high');
    final c = await setup([
      ConversationStep.single(
        id: 'lang.level.en',
        aiMessage: 'Seu inglês?',
        input: choice([('basic', 'Básico'), ('b', 'Bom'), ('c', 'Fluente')]),
      ),
    ]);
    addTearDown(c.dispose);

    await c.submitFreeText('falo bem');

    expect(saved.single.value, ['b']);
  });

  test('Fallback: confiança baixa NÃO submete, mantém input e avisa', () async {
    responder = (_) => const StepInterpretation(matchedIds: [], confidence: 'low');
    final c = await setup([
      ConversationStep.single(
        id: 'gap.skills',
        aiMessage: 'Quais skills?',
        input: choice([('py', 'Python')], multi: true),
      ),
    ]);
    addTearDown(c.dispose);

    await c.submitFreeText('sei lá');

    expect(saved, isEmpty); // não avançou
    expect(c.inputVisible, isTrue); // widget continua pra tocar
    expect(c.thread.whereType<AiMsgItem>().last.text, contains('certeza'));
  });

  test('Fallback: interpret==null (erro/timeout) também cai no widget',
      () async {
    responder = (_) => null;
    final c = await setup([
      ConversationStep.single(
        id: 'gap.skills',
        aiMessage: 'Quais skills?',
        input: choice([('py', 'Python')], multi: true),
      ),
    ]);
    addTearDown(c.dispose);

    await c.submitFreeText('???');

    expect(saved, isEmpty);
    expect(c.inputVisible, isTrue);
  });

  test('Tipo sem texto livre (MonthYear): convida a tocar, não submete',
      () async {
    final c = await setup([
      ConversationStep.single(
        id: 'exp.start',
        aiMessage: 'Quando começou?',
        input: const MonthYearInput(),
      ),
    ]);
    addTearDown(c.dispose);

    await c.submitFreeText('janeiro de 2020');

    expect(saved, isEmpty);
    expect(c.thread.whereType<AiMsgItem>().last.text, contains('opções'));
  });

  test('Reentrância: 2º envio é ignorado enquanto a IA do 1º está em voo',
      () async {
    final g = Completer<StepInterpretation?>();
    gate = g; // fakeInterpret devolve g.future enquanto não resolve
    final c = await setup([
      ConversationStep.single(
        id: 'gap.skills',
        aiMessage: 'Quais skills?',
        input: choice([('py', 'Python')], multi: true),
      ),
      ConversationStep.single(
        id: 'gap.next',
        aiMessage: 'E aí?',
        input: choice([('x', 'X')], multi: true),
      ),
    ]);
    addTearDown(c.dispose);

    final f1 = c.submitFreeText('primeiro'); // trava _busy, espera o gate
    await c.submitFreeText('segundo'); // _busy → ignorado na hora

    // libera a 1ª interpretação → ela submete e avança.
    g.complete(const StepInterpretation(matchedIds: ['py'], confidence: 'high'));
    await f1;

    expect(saved, hasLength(1)); // só o 1º submeteu
    expect(saved.single.stepId, 'gap.skills');
  });

  test('Editar card de escolha por texto livre restaura o input (regressão #1)',
      () async {
    responder = (_) =>
        const StepInterpretation(matchedIds: ['a'], confidence: 'high');
    final c = await setup([
      ConversationStep.single(
        id: 'gap.areas',
        aiMessage: 'Áreas?',
        input: choice([('a', 'A'), ('b', 'B')], multi: true),
      ),
      ConversationStep.single(
        id: 'gap.skills',
        aiMessage: 'Skills?',
        input: choice([('x', 'X')], multi: true),
      ),
    ]);
    addTearDown(c.dispose);

    // responde o 1º passo → vira card; avança pro 2º.
    await c.submitFreeText('área a');
    expect(c.isEditing, isFalse);
    final card = c.thread.whereType<AnsweredItem>().first;

    // edita o card por TEXTO LIVRE.
    c.beginEdit(card);
    expect(c.isEditing, isTrue);
    await c.submitFreeText('na verdade, a e b');

    // o bug: inputVisible ficava false e o passo atual sumia.
    expect(c.isEditing, isFalse);
    expect(c.inputVisible, isTrue);
    expect(c.currentStep?.id, 'gap.skills'); // passo atual preservado
    expect(saved.last.stepId, 'gap.areas'); // a edição regravou o 1º
  });

  test('editar gate de ramificação (sim→não) re-avalia o ramo e revela o '
      'follow-up novo', () async {
    final end = ConversationStep.single(
        id: 'exp.0.end', aiMessage: 'Quando saiu?', input: const MonthYearInput());
    final tail = ConversationStep.single(
        id: 'exp.0.ofazia',
        aiMessage: 'O que fazia?',
        input: const GuidedTextInput(example: 'x'));
    final gate = ConversationStep.single(
      id: 'exp.0.current',
      aiMessage: 'Ainda está nessa experiência?',
      input: choice([('yes', 'Sim, ainda estou'), ('no', 'Não, já saí')]),
      expand: (a) =>
          (a.value as List).contains('yes') ? [tail] : [end, tail],
    );
    final c = await setup([gate]);
    addTearDown(c.dispose);

    // "Sim, ainda estou" → revela só o tail (ofazia), SEM a data de saída.
    await c.submit(StepAnswer.choice(
        'exp.0.current', [const StepOption(id: 'yes', label: 'Sim, ainda estou')]));
    expect(c.currentStep?.id, 'exp.0.ofazia');

    // edita o card do gate → "Não, já saí".
    final card = c.thread
        .whereType<AnsweredItem>()
        .firstWhere((i) => i.exchange.step.id == 'exp.0.current');
    c.beginEdit(card);
    await c.submit(StepAnswer.choice(
        'exp.0.current', [const StepOption(id: 'no', label: 'Não, já saí')]));

    // agora PERGUNTA a data de saída (end) — o ramo foi re-avaliado.
    expect(c.currentStep?.id, 'exp.0.end');
  });
}
