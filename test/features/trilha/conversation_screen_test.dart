import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/trilha/application/conversation_controller.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';
import 'package:career_gamification/features/trilha/presentation/conversation_screen.dart';

/// Widget test da tela conversacional (R3: 1 widget test por tela crítica nova).
/// Verifica o fluxo de ponta a ponta: revelação da fala da IA → entrada inline
/// → eco da resposta → próximo passo → conclusão. Usa relógio falso — pumps
/// pequenos e repetidos drenam os Future.delayed encadeados (typing/revelação)
/// de forma determinística.
void main() {
  // Drena os delays encadeados (digitando + revelação) com pumps pequenos.
  Future<void> advance(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  List<ConversationStep> script() => [
        ConversationStep.single(
          id: 's1',
          aiMessage: 'Pergunta um',
          input: const ChoiceInput(options: [StepOption(id: 'a', label: 'Opção A')]),
        ),
        ConversationStep.single(
          id: 's2',
          aiMessage: 'Pergunta dois',
          input: const ChoiceInput(options: [StepOption(id: 'b', label: 'Opção B')]),
        ),
      ];

  testWidgets('conduz a conversa do 1º passo até a conclusão', (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(
      home: ConversationScreen(
        controller: ConversationController(script()),
        onCompleted: () => completed = true,
      ),
    ));

    await tester.pump(); // dispara o postFrame que inicia a revelação
    await advance(tester);

    // 1º passo revelado: fala da IA + chip de entrada.
    expect(find.text('Pergunta um'), findsOneWidget);
    expect(find.text('Opção A'), findsOneWidget);

    // Responde tocando no chip (escolha única avança no toque).
    await tester.tap(find.text('Opção A'));
    await advance(tester);

    // A resposta virou bolha do usuário e o 2º passo revelou.
    expect(find.text('Opção A'), findsWidgets);
    expect(find.text('Pergunta dois'), findsOneWidget);
    expect(find.text('Opção B'), findsOneWidget);

    // Responde o 2º → trilha termina.
    await tester.tap(find.text('Opção B'));
    await advance(tester);

    // Tela de conclusão + botão Concluir.
    expect(find.textContaining('Perfil mais forte'), findsOneWidget);
    expect(find.text('Concluir'), findsOneWidget);

    // Concluir dispara o callback.
    await tester.tap(find.text('Concluir'));
    await tester.pump();
    expect(completed, true);
  });

  testWidgets('onFinalize: mostra "montando o resumo" e depois a prévia',
      (tester) async {
    final completer = Completer<String?>();
    await tester.pumpWidget(MaterialApp(
      home: ConversationScreen(
        controller: ConversationController(script()),
        onFinalize: () => completer.future,
      ),
    ));

    await tester.pump();
    await advance(tester);
    await tester.tap(find.text('Opção A'));
    await advance(tester);
    await tester.tap(find.text('Opção B'));
    await advance(tester);

    // Enquanto a IA monta o resumo: estado "montando" (card + label do botão).
    expect(find.textContaining('Montando seu resumo'), findsWidgets);

    // IA retorna o resumo.
    completer.complete('Estudante de ADM buscando estágio em Marketing.');
    await tester.pump();
    await tester.pump();

    // Prévia do resumo + botão Concluir habilitado de volta.
    expect(find.textContaining('A IA criou um resumo'), findsOneWidget);
    expect(find.textContaining('Estudante de ADM'), findsOneWidget);
    expect(find.text('Concluir'), findsOneWidget);
  });

  testWidgets('voltar (undo) refaz o passo anterior sem duplicar o fio',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ConversationScreen(controller: ConversationController(script())),
    ));
    await tester.pump();
    await advance(tester);

    // Responde s1 → vai pro s2.
    await tester.tap(find.text('Opção A'));
    await advance(tester);
    expect(find.text('Pergunta dois'), findsOneWidget);

    // Toca em "Voltar" → volta pro s1.
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Pergunta um'), findsOneWidget);
    expect(find.text('Opção A'), findsWidgets); // entrada do s1 de volta
    expect(find.text('Pergunta dois'), findsNothing); // s2 saiu do fio
  });

  testWidgets('sair com progresso pede confirmação (X não descarta direto)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                builder: (_) =>
                    ConversationScreen(controller: ConversationController(script())),
              )),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await advance(tester);

    // Responde 1 passo → answeredCount = 1 → saída protegida.
    await tester.tap(find.text('Opção A'));
    await advance(tester);

    // Toca no X → diálogo de confirmação (não sai direto).
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sair da trilha?'), findsOneWidget);

    // "Continuar" fecha o diálogo e mantém na trilha.
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sair da trilha?'), findsNothing);
    expect(find.text('Pergunta dois'), findsOneWidget); // ainda na trilha
  });
}
