// F3 — import na ABERTURA do chat da trilha. Cobre o gate (zero vs importar),
// o poll da extração (counts sobem do baseline → card-resumo), a confirmação
// → conversa, e o failure-safe (extração não rende → cai na conversa cheia).
// Sem rede: ProfileSnapshotService e sessionBuilder são fakes.

import 'package:career_gamification/features/profile/domain/entities/personal_info.dart';
import 'package:career_gamification/features/profile/domain/entities/simple_lists.dart';
import 'package:career_gamification/features/trilha/application/conversation_controller.dart';
import 'package:career_gamification/features/trilha/application/trilha_session.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';
import 'package:career_gamification/features/trilha/presentation/trilha_chat_controller.dart';
import 'package:career_gamification/services/profile_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Devolve uma fila de snapshots (1 por chamada; depois repete o último).
class _FakeSnap implements ProfileSnapshotService {
  _FakeSnap(this._snaps);
  final List<ProfileSnapshot> _snaps;
  int _i = 0;

  @override
  Future<ProfileSnapshot> loadSnapshot(String userId) async {
    final s = _snaps[_i < _snaps.length ? _i : _snaps.length - 1];
    _i++;
    return s;
  }

  @override
  Future<ProfileSnapshot?> loadCurrent() async => null;
}

void main() {
  final empty = const ProfileSnapshot();
  final populated = ProfileSnapshot(
    skills: const [Skill(id: 's1', userId: 'u1', name: 'Dart')],
  );

  TrilhaChatController build({
    required ProfileSnapshotService snap,
    int steps = 1,
    void Function(int)? onStarted,
  }) {
    Future<void> save(StepAnswer a) async {}
    final plan = [
      for (var i = 0; i < steps; i++)
        ConversationStep.single(
          id: 'gap.$i',
          aiMessage: 'P$i',
          input: const GuidedTextInput(example: 'ex'),
        ),
    ];
    final session = TrilhaSession(
      controller: ConversationController(plan, onAnswer: save),
      saveAnswer: save,
    );
    return TrilhaChatController(
      userId: 'u1',
      sessionBuilder: (_) async => session,
      snapshotService: snap,
      onStarted: onStarted,
      pollInterval: const Duration(milliseconds: 1),
      maxPolls: 5,
    );
  }

  test('abre no gate (start empurra 2 bolhas, fase gate)', () async {
    final c = build(snap: _FakeSnap([empty]));
    addTearDown(c.dispose);

    await c.start();

    expect(c.phase, ChatPhase.gate);
    expect(c.thread.whereType<AiMsgItem>().length, 2);
  });

  test('"Começar do zero" entra direto na conversa', () async {
    var startedWith = -1;
    final c = build(snap: _FakeSnap([empty]), onStarted: (n) => startedWith = n);
    addTearDown(c.dispose);

    await c.start();
    await c.chooseZero();

    expect(c.phase, ChatPhase.converse);
    expect(c.currentStep?.id, 'gap.0');
    expect(startedWith, 1); // onStarted recebe o nº de passos
  });

  test('import: poll vê counts subirem → card-resumo + aguarda confirmação',
      () async {
    // baseline vazio, depois populado (skills=1).
    final c = build(snap: _FakeSnap([empty, populated]));
    addTearDown(c.dispose);

    await c.onCvUploaded('curriculo.pdf');

    expect(c.thread.whereType<FileBubbleItem>().single.name, 'curriculo.pdf');
    final summary = c.thread.whereType<ImportSummaryItem>().single.summary;
    expect(summary.skills, 1);
    expect(summary.total, 1);
    expect(c.awaitingImportConfirm, isTrue);
    expect(c.phase, ChatPhase.importing); // ainda não confirmou

    await c.confirmImport();

    expect(c.phase, ChatPhase.converse);
    expect(c.currentStep?.id, 'gap.0');
    expect(c.awaitingImportConfirm, isFalse);
  });

  test('import failure-safe: extração não rende → conversa cheia, sem resumo',
      () async {
    // Sempre vazio → nunca cresce → timeout após maxPolls.
    final c = build(snap: _FakeSnap([empty]));
    addTearDown(c.dispose);

    await c.onCvUploaded('curriculo.pdf');

    expect(c.thread.whereType<ImportSummaryItem>(), isEmpty);
    // O aviso de fallback aparece (e depois a conversa revela o 1º passo).
    expect(
      c.thread
          .whereType<AiMsgItem>()
          .any((m) => m.text.contains('conversa')),
      isTrue, // "...vamos completando pela conversa."
    );
    expect(c.phase, ChatPhase.converse); // caiu na conversa, não travou
    expect(c.awaitingImportConfirm, isFalse);
  });

  test('onCvUploaded reentrante é ignorado (já lendo)', () async {
    final c = build(snap: _FakeSnap([empty, populated]));
    addTearDown(c.dispose);

    final first = c.onCvUploaded('a.pdf');
    await c.onCvUploaded('b.pdf'); // phase!=gate (importing) → retorna na hora
    await first;

    // Só uma bolha de arquivo (o 2º envio não entrou).
    expect(c.thread.whereType<FileBubbleItem>().length, 1);
    expect(c.thread.whereType<FileBubbleItem>().single.name, 'a.pdf');
  });

  test('perfil pré-existente: counts NÃO crescem mas lastExtractedAt avança '
      '→ detecta conclusão (regressão do falso timeout)', () async {
    // A RPC pula INSERT em tabela já populada → counts ficam iguais; o sinal
    // é o last_extracted_at avançar.
    final t0 = DateTime(2026, 1, 1);
    final t1 = DateTime(2026, 1, 2);
    final base = ProfileSnapshot(
      personal: PersonalInfo(userId: 'u1', lastExtractedAt: t0),
      skills: const [
        Skill(id: 's1', userId: 'u1', name: 'A'),
        Skill(id: 's2', userId: 'u1', name: 'B'),
      ],
    );
    final after = ProfileSnapshot(
      personal: PersonalInfo(userId: 'u1', lastExtractedAt: t1), // avançou
      skills: const [
        Skill(id: 's1', userId: 'u1', name: 'A'),
        Skill(id: 's2', userId: 'u1', name: 'B'),
      ], // mesmos 2 (não cresceu)
    );
    final c = build(snap: _FakeSnap([base, after]));
    addTearDown(c.dispose);

    await c.onCvUploaded('curriculo.pdf');

    final summary = c.thread.whereType<ImportSummaryItem>().single.summary;
    expect(summary.skills, 2); // mostra o que tem, mesmo sem crescer
    expect(c.awaitingImportConfirm, isTrue); // NÃO caiu em falso timeout
  });

  test('PDF salvo mas texto inutilizável (extractionExpected=false) → pula o '
      'poll e cai na conversa, sem no-op silencioso', () async {
    final c = build(snap: _FakeSnap([empty]));
    addTearDown(c.dispose);

    await c.onCvUploaded('scan.pdf', extractionExpected: false);

    expect(c.thread.whereType<FileBubbleItem>().single.name, 'scan.pdf');
    expect(c.thread.whereType<ImportSummaryItem>(), isEmpty);
    expect(c.phase, ChatPhase.converse); // não trava no gate
  });
}
