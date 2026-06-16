import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/utils/pending_apply.dart';
import 'package:career_gamification/features/jobs/widgets/apply_return_prompt_sheet.dart';

/// FASE 3 T3.2 (R3): prompt de retorno. Sim → ApplyConfirmed; Não → chips de
/// motivo → ApplyAbandoned(reason); Depois → ApplyLater.
void main() {
  PendingApply pendingFor() => PendingApply(
        jobId: 'j1',
        title: 'Estágio em Dados',
        company: 'ACME',
        source: 'gupy',
        tsMs: DateTime.now().millisecondsSinceEpoch,
      );

  Future<ApplyPromptOutcome?> openAndAct(
    WidgetTester tester,
    Future<void> Function(WidgetTester) act,
  ) async {
    ApplyPromptOutcome? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showApplyReturnPrompt(context,
                      pending: pendingFor());
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await act(tester);
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('mostra título da vaga e as 3 opções', (tester) async {
    await openAndAct(tester, (t) async {});
    expect(find.text('Você se candidatou?'), findsOneWidget);
    expect(find.textContaining('Estágio em Dados'), findsOneWidget);
    expect(find.text('Sim, me candidatei'), findsOneWidget);
    expect(find.text('Não'), findsOneWidget);
    expect(find.text('Depois'), findsOneWidget);
  });

  testWidgets('Sim → ApplyConfirmed', (tester) async {
    final r = await openAndAct(tester, (t) async {
      await t.tap(find.text('Sim, me candidatei'));
    });
    expect(r, isA<ApplyConfirmed>());
  });

  testWidgets('Depois → ApplyLater', (tester) async {
    final r = await openAndAct(tester, (t) async {
      await t.tap(find.text('Depois'));
    });
    expect(r, isA<ApplyLater>());
  });

  testWidgets('Não → motivos → ApplyAbandoned(processo_longo)', (tester) async {
    final r = await openAndAct(tester, (t) async {
      await t.tap(find.text('Não'));
      await t.pumpAndSettle();
      expect(find.text('O que te fez desistir?'), findsOneWidget);
      await t.tap(find.text('Processo longo demais'));
    });
    expect(r, isA<ApplyAbandoned>());
    expect((r as ApplyAbandoned).reason, ApplyAbandonReason.processoLongo);
  });
}
