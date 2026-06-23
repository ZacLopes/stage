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
}
