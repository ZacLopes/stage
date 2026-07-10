// Orquestração do assistente de IA na barra (PLANO-ASSISTENTE, Fase A): o
// roteador do submitFreeText (atalho local vs IA), execução das ferramentas
// de leitura/navegação, e o parquear/retomar do passo aberto. Sem rede: a
// função do assistente (AssistantTurnFn) é injetada.

import 'package:career_gamification/features/trilha/application/conversation_controller.dart';
import 'package:career_gamification/features/trilha/application/trilha_session.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';
import 'package:career_gamification/features/trilha/presentation/trilha_chat_controller.dart';
import 'package:career_gamification/services/ai_service.dart';
import 'package:career_gamification/services/profile_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSnap implements ProfileSnapshotService {
  @override
  Future<ProfileSnapshot> loadSnapshot(String userId) async =>
      const ProfileSnapshot();
  @override
  Future<ProfileSnapshot?> loadCurrent() async => null;
}

/// Plano fake: 1 passo de TEXTO + 1 passo de ESCOLHA.
List<ConversationStep> _plan() => [
      ConversationStep.single(
        id: 'q.text',
        aiMessage: 'Qual empresa?',
        input: const GuidedTextInput(example: 'x'),
      ),
      ConversationStep.single(
        id: 'q.choice',
        aiMessage: 'Modalidade?',
        input: const ChoiceInput(options: [
          StepOption(id: 'remote', label: 'Remoto'),
          StepOption(id: 'onsite', label: 'Presencial'),
        ]),
      ),
    ];

AssistantTurnFn _fixed(AssistantTurn turn) => ({
      required String message,
      Map<String, dynamic>? openStep,
      Map<String, dynamic> context = const {},
      List<Map<String, dynamic>> history = const [],
    }) async =>
        turn;

AssistantTurnFn _nullTurn({void Function()? onCall}) => ({
      required String message,
      Map<String, dynamic>? openStep,
      Map<String, dynamic> context = const {},
      List<Map<String, dynamic>> history = const [],
    }) async {
      onCall?.call();
      return null;
    };

void main() {
  TrilhaChatController build({
    required AssistantTurnFn assistantTurn,
    bool assistEnabled = true,
    List<ConversationStep> Function(String)? sectionSteps,
    AssistFieldReader? readField,
    AssistFieldWriter? writeField,
    AssistFieldWriter? itemAdder,
    AssistFieldWriter? itemRemover,
    Future<List<String>> Function(String, String)? itemResolver,
    AssistFieldReader? bulletReader,
    AssistFieldWriter? bulletWriter,
    Future<Future<void> Function()?> Function(String, String)?
        reversibleRemover,
    Future<Map<String, String>?> Function()? proactiveLoader,
    Future<List<String>> Function()? skillsLoader,
    Future<List<String>> Function()? skillSuggester,
    Future<List<String>> Function()? interestsLoader,
    Future<void> Function(List<String>)? interestsReplacer,
    Future<List<(String, String?)>> Function()? languagesLoader,
    Future<void> Function(String, String?)? languageUpserter,
    List<ConversationStep>? plan,
  }) {
    Future<void> save(StepAnswer a) async {}
    final session = TrilhaSession(
      controller: ConversationController(plan ?? _plan(), onAnswer: save),
      saveAnswer: save,
    );
    return TrilhaChatController(
      userId: 'u1',
      sessionBuilder: (_) async => session,
      snapshotService: _FakeSnap(),
      // Abertura adaptativa (perfil com algo) → entra direto na conversa.
      preFilledLoader: () async => const ['skills'],
      assistEnabled: assistEnabled,
      assistantTurn: assistantTurn,
      assistSectionSteps: sectionSteps,
      assistReadField: readField,
      assistWriteField: writeField,
      assistItemAdder: itemAdder,
      assistItemRemover: itemRemover,
      assistItemResolver: itemResolver,
      assistBulletReader: bulletReader,
      assistBulletWriter: bulletWriter,
      assistReversibleRemover: reversibleRemover,
      assistProactiveLoader: proactiveLoader,
      assistSkillsLoader: skillsLoader,
      assistSkillSuggester: skillSuggester,
      assistInterestsLoader: interestsLoader,
      assistInterestsReplacer: interestsReplacer,
      assistLanguagesLoader: languagesLoader,
      assistLanguageUpserter: languageUpserter,
      pollInterval: const Duration(milliseconds: 1),
      maxPolls: 2,
    );
  }

  test('flag OFF: comportamento de hoje (texto responde o passo, sem IA)',
      () async {
    var called = false;
    final c = build(
        assistEnabled: false, assistantTurn: _nullTurn(onCall: () => called = true));
    addTearDown(c.dispose);
    await c.start();
    expect(c.currentStep?.id, 'q.text');
    await c.submitFreeText('Magalu');
    expect(called, isFalse); // assistente nunca chamado com a flag OFF
    expect(c.currentStep?.id, 'q.choice'); // texto virou resposta e avançou
  });

  test('flag OFF + sem passo aberto: não engole a mensagem — bolha + dica',
      () async {
    // Regressão: com o assistente OFF e a trilha concluída (sem passo aberto),
    // apertar enviar sumia com o texto em silêncio (botão "morto"). Agora mostra
    // a fala e ensina a editar pela seção.
    final c = build(
      assistEnabled: false,
      assistantTurn: _nullTurn(),
      plan: [
        ConversationStep.single(
            id: 'q.only',
            aiMessage: 'Alguma coisa?',
            input: const GuidedTextInput(example: 'x')),
      ],
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('Empresa X'); // responde o único passo → conclui
    expect(c.currentStep, isNull); // sem passo aberto

    await c.submitFreeText('edita minhas habilidades');
    expect(
        c.thread
            .whereType<UserMsgItem>()
            .any((m) => m.text == 'edita minhas habilidades'),
        isTrue); // a fala não sumiu
    expect(
        c.thread
            .whereType<AiMsgItem>()
            .any((m) => m.text.contains('tocar na seção')),
        isTrue); // recebeu uma dica em vez de silêncio
  });

  test('fast-lane: texto sem cara de comando responde o passo SEM chamar a IA',
      () async {
    var called = false;
    final c = build(assistantTurn: _nullTurn(onCall: () => called = true));
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('Magazine Luiza'); // sem '?', sem verbo de comando
    expect(called, isFalse); // atalho local
    expect(c.currentStep?.id, 'q.choice');
  });

  test('answer_current_step (escolha): mapeia option_ids e responde', () async {
    final c = build(
        assistantTurn: _fixed(const AssistantTurn(
      tool: 'answer_current_step',
      args: {'option_ids': ['remote']},
      reply: 'Anotei!',
      promptVersion: 'assistant_v1',
    )));
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('Magalu'); // fast-lane no passo de texto
    expect(c.currentStep?.id, 'q.choice');
    await c.submitFreeText('trabalho de casa'); // passo de escolha → IA
    expect(c.currentStep, isNull); // respondeu 'remote' → trilha acabou
  });

  test('answer_question: mostra a resposta e MANTÉM o passo aberto', () async {
    final c = build(
        assistantTurn: _fixed(const AssistantTurn(
      tool: 'answer_question',
      args: {},
      reply: 'Estágio é enquanto você cursa 👍',
      promptVersion: 'assistant_v1',
    )));
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('qual a diferença de estágio e trainee?'); // '?' → IA
    expect(
        c.thread
            .whereType<AiMsgItem>()
            .any((m) => m.text.contains('Estágio é')),
        isTrue);
    expect(c.currentStep?.id, 'q.text'); // não avançou
  });

  test('start_section: injeta a seção e o passo aberto RETOMA depois', () async {
    final injected = [
      ConversationStep.single(
          id: 'gap.skills',
          aiMessage: 'Suas skills?',
          input: const GuidedTextInput(example: 'x')),
    ];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'start_section',
        args: {'section': 'skills'},
        reply: 'Bora completar suas skills!',
        promptVersion: 'assistant_v1',
      )),
      sectionSteps: (s) => s == 'skills' ? injected : const [],
    );
    addTearDown(c.dispose);
    await c.start();
    expect(c.currentStep?.id, 'q.text');
    await c.submitFreeText('quero preencher minhas skills'); // 'quero' → IA
    expect(c.currentStep?.id, 'gap.skills'); // seção injetada virou o atual
    await c.submitFreeText('Python'); // responde a skill (fast-lane)
    expect(c.currentStep?.id, 'q.text'); // RETOMOU o passo original
  });

  test('falha do assistente (null): failure-safe, mantém o passo e avisa',
      () async {
    final c = build(assistantTurn: _nullTurn());
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('o que falta no meu perfil?'); // '?' → IA → null
    expect(c.currentStep?.id, 'q.text'); // não avançou
    expect(
        c.thread.whereType<AiMsgItem>().any((m) =>
            m.text.contains('Não peguei bem') ||
            m.text.contains('Não consegui')),
        isTrue);
  });

  // ── Fase B: mutação (propõe → confirma → aplica → desfaz) ──────────────────

  test('update_field: propõe (não grava) → confirma (grava) → desfaz (regrava)',
      () async {
    final writes = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'update_field',
        args: {
          'field': 'desired_position',
          'value': 'Analista de Dados',
          'value_label': 'Analista de Dados',
        },
        reply: 'Beleza!',
        promptVersion: 'assistant_v1',
      )),
      readField: (field) async => field == 'desired_position'
          ? const AssistFieldValue(
              raw: 'Dev', text: 'Dev', label: 'Cargo desejado')
          : null,
      writeField: (field, value) async => writes.add([field, value]),
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('muda meu cargo pra Analista de Dados'); // 'muda' → IA

    // PROPÔS: 1 card pending, e NÃO gravou ainda.
    final pending = c.thread
        .whereType<AssistEditItem>()
        .where((e) => e.status == AssistEditStatus.pending)
        .toList();
    expect(pending, hasLength(1));
    expect(writes, isEmpty);
    expect(pending.first.beforeText, 'Dev');
    expect(pending.first.afterText, 'Analista de Dados');
    final id = pending.first.id;

    // CONFIRMA → grava o novo valor.
    await c.confirmAssistEdit(id);
    expect(writes, [
      ['desired_position', 'Analista de Dados']
    ]);
    final applied =
        c.thread.whereType<AssistEditItem>().firstWhere((e) => e.id == id);
    expect(applied.status, AssistEditStatus.applied);

    // DESFAZ → regrava o valor anterior ('Dev').
    await c.undoAssistEdit(id);
    expect(writes.last, ['desired_position', 'Dev']);
    expect(applied.status, AssistEditStatus.undone);
  });

  test('update_field: cancelar NÃO grava', () async {
    final writes = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'update_field',
        args: {'field': 'desired_position', 'value': 'X'},
        reply: '',
        promptVersion: 'assistant_v1',
      )),
      readField: (field) async => const AssistFieldValue(
          raw: '', text: '—', label: 'Cargo desejado'),
      writeField: (field, value) async => writes.add([field, value]),
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('quero mudar meu cargo'); // 'quero' → IA
    final pending = c.thread
        .whereType<AssistEditItem>()
        .singleWhere((e) => e.status == AssistEditStatus.pending);
    c.cancelAssistEdit(pending.id);
    expect(writes, isEmpty); // nunca gravou
    expect(pending.status, AssistEditStatus.cancelled);
  });

  // ── Fase B-2: add_item / remove_item ───────────────────────────────────────

  test('add_item: propõe (op=add) → confirma (add) → desfaz (remove)', () async {
    final adds = <List<String>>[];
    final removes = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'add_item',
        args: {'kind': 'skill', 'value': 'Python'},
        reply: 'Boa!',
        promptVersion: 'assistant_v1',
      )),
      itemAdder: (kind, value) async => adds.add([kind, value]),
      itemRemover: (kind, value) async => removes.add([kind, value]),
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('adiciona Python nas minhas skills'); // 'adiciona' → IA
    final pending = c.thread
        .whereType<AssistEditItem>()
        .singleWhere((e) => e.status == AssistEditStatus.pending);
    expect(pending.op, AssistEditOp.add);
    expect(adds, isEmpty); // não gravou ainda
    await c.confirmAssistEdit(pending.id);
    expect(adds, [
      ['skill', 'Python']
    ]);
    await c.undoAssistEdit(pending.id); // desfaz add = remove
    expect(removes, [
      ['skill', 'Python']
    ]);
  });

  test('remove_item: resolve 1 → confirma (remove) → desfaz (add)', () async {
    final adds = <List<String>>[];
    final removes = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'remove_item',
        args: {'kind': 'skill', 'query': 'python'},
        reply: '',
        promptVersion: 'assistant_v1',
      )),
      itemAdder: (kind, value) async => adds.add([kind, value]),
      itemRemover: (kind, value) async => removes.add([kind, value]),
      itemResolver: (kind, query) async => ['Python'], // 1 match
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('tira python das skills'); // 'tira' → IA
    final pending = c.thread
        .whereType<AssistEditItem>()
        .singleWhere((e) => e.status == AssistEditStatus.pending);
    expect(pending.op, AssistEditOp.remove);
    expect(pending.value, 'Python'); // resolveu pro nome real
    await c.confirmAssistEdit(pending.id);
    expect(removes, [
      ['skill', 'Python']
    ]);
    await c.undoAssistEdit(pending.id); // desfaz remove = add
    expect(adds, [
      ['skill', 'Python']
    ]);
  });

  test('remove_item: 0 matches → esclarece, sem card', () async {
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'remove_item',
        args: {'kind': 'skill', 'query': 'cobol'},
        reply: '',
        promptVersion: 'assistant_v1',
      )),
      itemRemover: (kind, value) async {},
      itemResolver: (kind, query) async => const [], // não achou
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('tira cobol das skills');
    expect(c.thread.whereType<AssistEditItem>(), isEmpty); // nenhum card
    expect(
        c.thread.whereType<AiMsgItem>().any((m) => m.text.contains('Não achei')),
        isTrue);
  });

  test('rewrite_summary: propõe antes→depois → confirma (grava) → desfaz',
      () async {
    final writes = <List<String>>[];
    const novo = 'Estudante de ADM focado em dados, buscando estágio.';
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'rewrite_summary',
        args: {'new_summary': novo},
        reply: 'Deixei mais objetivo!',
        promptVersion: 'assistant_v1',
      )),
      readField: (field) async => field == 'summary'
          ? const AssistFieldValue(
              raw: 'Resumo antigo bem longo aqui',
              text: 'Resumo antigo bem longo aqui',
              label: 'Resumo')
          : null,
      writeField: (field, value) async => writes.add([field, value]),
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('reescreve meu resumo mais objetivo'); // 'reescreve' → IA
    final pending = c.thread
        .whereType<AssistEditItem>()
        .singleWhere((e) => e.status == AssistEditStatus.pending);
    expect(pending.field, 'summary');
    expect(pending.op, AssistEditOp.update);
    expect(pending.afterText, novo);
    expect(writes, isEmpty); // não gravou ainda
    await c.confirmAssistEdit(pending.id);
    expect(writes, [
      ['summary', novo]
    ]);
    await c.undoAssistEdit(pending.id); // regrava o resumo anterior
    expect(writes.last, ['summary', 'Resumo antigo bem longo aqui']);
  });

  test('improve_bullet: propõe antes→depois → confirma (grava) → desfaz',
      () async {
    final writes = <List<String>>[];
    const novo = 'Estruturei uma planilha que agilizou o atendimento.';
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'improve_bullet',
        args: {'bullet_id': 'b1', 'new_bullet': novo},
        reply: 'Ficou mais forte!',
        promptVersion: 'assistant_v1',
      )),
      bulletReader: (id) async => id == 'b1'
          ? const AssistFieldValue(
              raw: 'fazia planilha', text: 'fazia planilha', label: 'Ambev')
          : null,
      bulletWriter: (id, text) async => writes.add([id, text]),
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('melhora o bullet da Ambev'); // 'melhora' → IA
    final pending = c.thread
        .whereType<AssistEditItem>()
        .singleWhere((e) => e.status == AssistEditStatus.pending);
    expect(pending.op, AssistEditOp.bullet);
    expect(pending.refId, 'b1');
    expect(pending.beforeText, 'fazia planilha');
    expect(pending.afterText, novo);
    expect(writes, isEmpty); // não gravou ainda
    await c.confirmAssistEdit(pending.id);
    expect(writes, [
      ['b1', novo]
    ]);
    await c.undoAssistEdit(pending.id); // regrava o bullet antigo
    expect(writes.last, ['b1', 'fazia planilha']);
  });

  test('remove_item (experiência): reversível — confirma deleta, desfaz restaura',
      () async {
    var deleted = false;
    var restored = false;
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'remove_item',
        args: {'kind': 'experience', 'query': 'ambev'},
        reply: '',
        promptVersion: 'assistant_v1',
      )),
      itemResolver: (kind, query) async => ['Estagiário · Ambev'], // 1 match
      reversibleRemover: (kind, value) async {
        deleted = true; // "deletou" e devolve o restore
        return () async => restored = true;
      },
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('apaga minha experiência na Ambev'); // 'apaga' → IA
    final pending = c.thread
        .whereType<AssistEditItem>()
        .singleWhere((e) => e.status == AssistEditStatus.pending);
    expect(pending.op, AssistEditOp.remove);
    expect(pending.value, 'Estagiário · Ambev');
    expect(deleted, isFalse); // ainda não deletou
    await c.confirmAssistEdit(pending.id);
    expect(deleted, isTrue); // deletou (reversível capturou o restore)
    await c.undoAssistEdit(pending.id);
    expect(restored, isTrue); // undo chamou o restore (re-inseriu)
  });

  // ── Fase C: sugestão proativa do próximo ganho ────────────────────────────

  test('proativo: ao concluir, sugere a lacuna e "quero" entra direto na seção',
      () async {
    final injected = [
      ConversationStep.single(
          id: 'gap.skills',
          aiMessage: 'Suas skills?',
          input: const GuidedTextInput(example: 'x')),
    ];
    final c = build(
      // Plano de 1 passo → responder já CONCLUI (dispara a sugestão proativa).
      plan: [
        ConversationStep.single(
            id: 'q.only',
            aiMessage: 'Alguma coisa?',
            input: const GuidedTextInput(example: 'x')),
      ],
      assistantTurn: _nullTurn(), // não deve ser chamado (atalho local)
      sectionSteps: (s) => s == 'skills' ? injected : const [],
      proactiveLoader: () async =>
          {'section': 'skills', 'label': '3 skills'},
    );
    addTearDown(c.dispose);
    await c.start();
    // Responde o único passo (fast-lane) → conclui → sugestão proativa aparece.
    await c.submitFreeText('Empresa X');
    expect(c.finished, isTrue);
    expect(
        c.thread
            .whereType<AiMsgItem>()
            .any((m) => m.text.contains('3 skills')),
        isTrue);
    // "quero" → atalho: entra DIRETO na seção sugerida (sem chamar a IA).
    await c.submitFreeText('quero');
    expect(c.currentStep?.id, 'gap.skills');
    expect(c.thread.whereType<UserMsgItem>().any((m) => m.text == 'quero'),
        isTrue);
  });

  test('proativo: "quero editar minhas habilidades" NÃO cai no atalho (regressão)',
      () async {
    // Bug: a frase começa com "quero" e sequestrava a seção sugerida (experiência)
    // em vez de ir pro assistente abrir o editor de skills.
    final injectedExp = [
      ConversationStep.single(
          id: 'gap.experience',
          aiMessage: 'Suas experiências?',
          input: const GuidedTextInput(example: 'x')),
    ];
    final c = build(
      plan: [
        ConversationStep.single(
            id: 'q.only',
            aiMessage: 'Alguma coisa?',
            input: const GuidedTextInput(example: 'x')),
      ],
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'edit_skills',
        args: {},
        reply: 'Bora editar 👇',
        promptVersion: 'assistant_v4',
      )),
      sectionSteps: (s) => s == 'experience' ? injectedExp : const [],
      proactiveLoader: () async =>
          {'section': 'experience', 'label': '1 experiência'},
      skillsLoader: () async => ['Excel', 'Python'],
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('Empresa X'); // conclui → sugere experiência
    expect(c.finished, isTrue);

    await c.submitFreeText('quero editar minhas habilidades');
    // NÃO entrou na seção sugerida (experiência)…
    expect(c.currentStep?.id, isNot('gap.experience'));
    // …abriu o editor de SKILLS pelo assistente.
    expect(c.thread.whereType<ListEditorItem>().any((e) => e.kind == 'skill'),
        isTrue);
  });

  test('remove_item: 2+ matches → desambigua, sem card', () async {
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'remove_item',
        args: {'kind': 'skill', 'query': 'java'},
        reply: '',
        promptVersion: 'assistant_v1',
      )),
      itemRemover: (kind, value) async {},
      itemResolver: (kind, query) async => ['Java', 'JavaScript'],
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('remove java das skills');
    expect(c.thread.whereType<AssistEditItem>(), isEmpty);
    expect(
        c.thread.whereType<AiMsgItem>().any((m) =>
            m.text.contains('Qual') &&
            m.text.contains('Java') &&
            m.text.contains('JavaScript')),
        isTrue);
  });

  // ── Fase C: extração de textão colado ─────────────────────────────────────

  test('extract_profile: textão colado → card lista os campos, SEM gravar',
      () async {
    final adds = <List<String>>[];
    final writes = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'extract_profile',
        args: {
          'items': [
            {'kind': 'language', 'value': 'Inglês'},
            {'kind': 'skill', 'value': 'Excel'},
            {'kind': 'skill', 'value': 'Python'},
            {'kind': 'desired_position', 'value': 'Analista de dados'},
          ],
        },
        reply: 'Peguei alguns pontos 👇',
        promptVersion: 'assistant_v1',
      )),
      itemAdder: (kind, value) async => adds.add([kind, value]),
      itemRemover: (kind, value) async {},
      readField: (field) async => field == 'desired_position'
          ? const AssistFieldValue(raw: '', text: '', label: 'Cargo desejado')
          : null,
      writeField: (field, value) async => writes.add([field, value]),
    );
    addTearDown(c.dispose);
    await c.start();
    // Blob multi-linha → NÃO é resposta do passo aberto, vai pra IA extrair.
    await c.submitFreeText(
        'Falo inglês fluente\nSei Excel e Python\nQuero ser analista de dados');

    final card = c.thread
        .whereType<AssistExtractItem>()
        .singleWhere((e) => e.status == AssistEditStatus.pending);
    expect(card.entries, hasLength(4)); // idioma + 2 skills + cargo
    expect(card.entries.map((e) => e.label).toList(), [
      'Idioma: Inglês',
      'Skill: Excel',
      'Skill: Python',
      'Cargo: Analista de dados',
    ]);
    expect(adds, isEmpty); // nada gravado até confirmar
    expect(writes, isEmpty);
  });

  test('extract_profile: "Aplicar tudo" grava cada campo; Desfazer reverte tudo',
      () async {
    final adds = <List<String>>[];
    final removes = <List<String>>[];
    final writes = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'extract_profile',
        args: {
          'items': [
            {'kind': 'skill', 'value': 'Excel'},
            {'kind': 'language', 'value': 'Inglês'},
            {'kind': 'desired_position', 'value': 'Analista de dados'},
          ],
        },
        reply: '',
        promptVersion: 'assistant_v1',
      )),
      itemAdder: (kind, value) async => adds.add([kind, value]),
      itemRemover: (kind, value) async => removes.add([kind, value]),
      readField: (field) async => field == 'desired_position'
          ? const AssistFieldValue(
              raw: 'Estagiário', text: 'Estagiário', label: 'Cargo desejado')
          : null,
      writeField: (field, value) async => writes.add([field, value]),
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText(
        'Sei Excel\nFalo inglês\nQuero ser analista de dados');
    final card = c.thread
        .whereType<AssistExtractItem>()
        .singleWhere((e) => e.status == AssistEditStatus.pending);

    // APLICAR TUDO → skill/idioma via adder; cargo via writer.
    await c.confirmExtract(card.id);
    expect(adds, [
      ['skill', 'Excel'],
      ['language', 'Inglês'],
    ]);
    expect(writes, [
      ['desired_position', 'Analista de dados'],
    ]);
    expect(card.status, AssistEditStatus.applied);

    // DESFAZER → reverte o lote (ordem inversa): cargo volta pro anterior,
    // idioma e skill são removidos.
    await c.undoExtract(card.id);
    expect(writes.last, ['desired_position', 'Estagiário']); // cargo restaurado
    expect(removes, [
      ['language', 'Inglês'],
      ['skill', 'Excel'],
    ]);
    expect(card.status, AssistEditStatus.undone);
  });

  test('extract_profile: Cancelar NÃO grava nada', () async {
    final adds = <List<String>>[];
    final writes = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'extract_profile',
        args: {
          'items': [
            {'kind': 'skill', 'value': 'Excel'},
            {'kind': 'desired_position', 'value': 'Analista'},
          ],
        },
        reply: '',
        promptVersion: 'assistant_v1',
      )),
      itemAdder: (kind, value) async => adds.add([kind, value]),
      writeField: (field, value) async => writes.add([field, value]),
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('Sei Excel\nQuero ser analista');
    final card = c.thread.whereType<AssistExtractItem>().single;
    c.cancelExtract(card.id);
    expect(card.status, AssistEditStatus.cancelled);
    expect(adds, isEmpty);
    expect(writes, isEmpty);
  });

  // ── Fase C: editor visual de skills ───────────────────────────────────────

  test('edit_skills: abre editor com skills atuais + sugestões (sem gravar)',
      () async {
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'edit_skills',
        args: {},
        reply: 'Bora editar 👇',
        promptVersion: 'assistant_v3',
      )),
      itemAdder: (kind, value) async {},
      itemRemover: (kind, value) async {},
      skillsLoader: () async => ['Excel', 'Python', 'Canva'],
      skillSuggester: () async => ['SQL', 'Power BI', 'Python'], // Python já tem
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('quero editar minhas habilidades');
    final card = c.thread.whereType<ListEditorItem>().single;
    expect(card.initial, ['Excel', 'Python', 'Canva']);
    expect(card.suggestions, ['SQL', 'Power BI']); // tira o que já tem (Python)
    expect(card.status, AssistEditStatus.pending);
  });

  test('edit_skills: "Salvar" aplica adds+removes; Desfazer reverte o lote',
      () async {
    final adds = <List<String>>[];
    final removes = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'edit_skills',
        args: {},
        reply: '',
        promptVersion: 'assistant_v3',
      )),
      itemAdder: (kind, value) async => adds.add([kind, value]),
      itemRemover: (kind, value) async => removes.add([kind, value]),
      skillsLoader: () async => ['Excel', 'Python'],
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('quero mexer nas minhas habilidades');
    final card = c.thread.whereType<ListEditorItem>().single;

    await c.applyListEditor(card.id, added: ['SQL'], removed: ['Python']);
    expect(adds, [
      ['skill', 'SQL']
    ]);
    expect(removes, [
      ['skill', 'Python']
    ]);
    expect(card.status, AssistEditStatus.applied);

    // Desfazer (ordem inversa): re-adiciona Python e remove SQL.
    await c.undoListEditor(card.id);
    expect(adds.last, ['skill', 'Python']); // desfaz a remoção
    expect(removes.last, ['skill', 'SQL']); // desfaz a adição
    expect(card.status, AssistEditStatus.undone);
  });

  test('edit_skills: sem mudança → Salvar fecha sem gravar', () async {
    final adds = <List<String>>[];
    final removes = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'edit_skills',
        args: {},
        reply: '',
        promptVersion: 'assistant_v3',
      )),
      itemAdder: (kind, value) async => adds.add([kind, value]),
      itemRemover: (kind, value) async => removes.add([kind, value]),
      skillsLoader: () async => ['Excel'],
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('quero editar minhas habilidades');
    final card = c.thread.whereType<ListEditorItem>().single;
    await c.applyListEditor(card.id, added: const [], removed: const []);
    expect(adds, isEmpty);
    expect(removes, isEmpty);
    expect(card.status, AssistEditStatus.cancelled); // fechou sem aplicar
  });

  test('edit_skills sem skills ainda: cai na coleta (injeta a seção)', () async {
    final injected = [
      ConversationStep.single(
          id: 'gap.skills',
          aiMessage: 'Suas skills?',
          input: const GuidedTextInput(example: 'x')),
    ];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'edit_skills',
        args: {},
        reply: '',
        promptVersion: 'assistant_v3',
      )),
      sectionSteps: (s) => s == 'skills' ? injected : const [],
      skillsLoader: () async => const [], // ainda sem skills
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('quero editar minhas habilidades');
    expect(c.thread.whereType<ListEditorItem>(), isEmpty);
    expect(c.currentStep?.id, 'gap.skills'); // caiu na coleta
  });

  // ── Fase C: editor de interesses (replace-all) ────────────────────────────

  test('edit_interests: Salvar grava a lista FINAL (replace); Desfazer reverte',
      () async {
    final replaced = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'edit_interests',
        args: {},
        reply: '',
        promptVersion: 'assistant_v4',
      )),
      interestsLoader: () async => ['Xadrez', 'Corrida'],
      interestsReplacer: (names) async => replaced.add(List.of(names)),
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('quero editar meus interesses');
    final card = c.thread.whereType<ListEditorItem>().single;
    expect(card.kind, 'interest');
    expect(card.initial, ['Xadrez', 'Corrida']);

    // Adiciona Leitura, tira Corrida → lista final [Xadrez, Leitura].
    await c.applyListEditor(card.id, added: ['Leitura'], removed: ['Corrida']);
    expect(replaced, [
      ['Xadrez', 'Leitura']
    ]);
    expect(card.status, AssistEditStatus.applied);

    // Desfazer → replace de volta pra lista original.
    await c.undoListEditor(card.id);
    expect(replaced.last, ['Xadrez', 'Corrida']);
    expect(card.status, AssistEditStatus.undone);
  });

  test('edit_interests: tirar "Music" NÃO apaga a variante "music" (regressão)',
      () async {
    final replaced = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'edit_interests',
        args: {},
        reply: '',
        promptVersion: 'assistant_v4',
      )),
      interestsLoader: () async => ['Music', 'music', 'Cinema'],
      interestsReplacer: (names) async => replaced.add(List.of(names)),
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('quero editar meus interesses');
    final card = c.thread.whereType<ListEditorItem>().single;
    // Tira SÓ 'Music' (string exata) — 'music' e 'Cinema' têm que ficar.
    await c.applyListEditor(card.id, added: const [], removed: ['Music']);
    expect(replaced, [
      ['music', 'Cinema']
    ]);
  });

  // ── Fase C: editor de idiomas (nome + nível) ──────────────────────────────

  test('edit_languages: abre com idiomas+nível; opções = canônicos que faltam',
      () async {
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'edit_languages',
        args: {},
        reply: '',
        promptVersion: 'assistant_v4',
      )),
      languagesLoader: () async => [('Português', 'native'), ('Inglês', 'basic')],
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('quero editar meus idiomas');
    final card = c.thread.whereType<LanguagesEditorItem>().single;
    expect(card.initial.map((e) => e.name).toList(), ['Português', 'Inglês']);
    expect(card.initial.first.level, 'native');
    expect(card.options.contains('Português'), isFalse); // já tem
    expect(card.options.contains('Espanhol'), isTrue); // dá pra adicionar
  });

  test('edit_languages: adiciona + muda nível + remove; Desfazer reverte o lote',
      () async {
    final upserts = <List<String?>>[];
    final removes = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'edit_languages',
        args: {},
        reply: '',
        promptVersion: 'assistant_v4',
      )),
      itemRemover: (kind, value) async => removes.add([kind, value]),
      languagesLoader: () async => [('Português', 'native'), ('Inglês', 'basic')],
      languageUpserter: (name, level) async => upserts.add([name, level]),
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('quero editar meus idiomas');
    final card = c.thread.whereType<LanguagesEditorItem>().single;

    await c.applyLanguagesEditor(
      card.id,
      added: [const LangEntry('Espanhol', 'advanced')],
      changed: [const LangEntry('Inglês', 'fluent')],
      removed: ['Português'],
    );
    expect(upserts, [
      ['Espanhol', 'advanced'], // adicionado
      ['Inglês', 'fluent'], // nível alterado
    ]);
    expect(removes, [
      ['language', 'Português']
    ]);
    expect(card.status, AssistEditStatus.applied);

    // Desfazer (ordem inversa): re-upsert Português(native) + Inglês(basic),
    // e remove Espanhol.
    await c.undoLanguagesEditor(card.id);
    expect(
        upserts,
        containsAll([
          ['Português', 'native'],
          ['Inglês', 'basic'],
        ]));
    expect(
        removes,
        containsAll([
          ['language', 'Espanhol'],
        ]));
    expect(card.status, AssistEditStatus.undone);
  });

  // ── Rápidos: add de interesse, duplicado, lista, não-resposta ─────────────

  test('add_item interest: comando direto → card → aplica', () async {
    final adds = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'add_item',
        args: {'kind': 'interest', 'value': 'Sustentabilidade'},
        reply: 'Boa!',
        promptVersion: 'assistant_v6',
      )),
      itemAdder: (kind, value) async => adds.add([kind, value]),
      itemResolver: (kind, query) async => const [], // ainda não tem
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('adiciona sustentabilidade nos interesses');
    final pending = c.thread
        .whereType<AssistEditItem>()
        .singleWhere((e) => e.status == AssistEditStatus.pending);
    expect(pending.op, AssistEditOp.add);
    await c.confirmAssistEdit(pending.id);
    expect(adds, [
      ['interest', 'Sustentabilidade']
    ]);
  });

  test('add_item duplicado: NÃO cria card (não mente nem apaga o existente)',
      () async {
    final adds = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'add_item',
        args: {'kind': 'skill', 'value': 'Python'},
        reply: '',
        promptVersion: 'assistant_v6',
      )),
      itemAdder: (kind, value) async => adds.add([kind, value]),
      itemResolver: (kind, query) async => ['Python'], // já tem
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('adiciona Python nas skills');
    expect(c.thread.whereType<AssistEditItem>(), isEmpty); // sem card
    expect(
        c.thread.whereType<AiMsgItem>().any((m) => m.text.contains('já tá')),
        isTrue);
    expect(adds, isEmpty);
  });

  test('add_item lista: "SQL, Power BI e Excel" → card em lote', () async {
    final adds = <List<String>>[];
    final c = build(
      assistantTurn: _fixed(const AssistantTurn(
        tool: 'add_item',
        args: {'kind': 'skill', 'value': 'SQL, Power BI e Excel'},
        reply: '',
        promptVersion: 'assistant_v6',
      )),
      itemAdder: (kind, value) async => adds.add([kind, value]),
      itemResolver: (kind, query) async => const [],
    );
    addTearDown(c.dispose);
    await c.start();
    await c.submitFreeText('adiciona 3 skills: SQL, Power BI e Excel');
    final card = c.thread.whereType<AssistExtractItem>().single;
    expect(card.entries.map((e) => e.value).toList(),
        ['SQL', 'Power BI', 'Excel']);
    await c.confirmExtract(card.id);
    expect(adds, [
      ['skill', 'SQL'],
      ['skill', 'Power BI'],
      ['skill', 'Excel'],
    ]);
  });

  test('"não sei" num passo de texto: não grava literal, repergunta', () async {
    final c = build(assistantTurn: _nullTurn());
    addTearDown(c.dispose);
    await c.start();
    expect(c.currentStep?.id, 'q.text');
    await c.submitFreeText('não sei');
    expect(c.currentStep?.id, 'q.text'); // NÃO avançou (não gravou 'não sei')
    expect(
        c.thread
            .whereType<AiMsgItem>()
            .any((m) => m.text.contains('Tranquilo não saber')),
        isTrue);
  });
}
