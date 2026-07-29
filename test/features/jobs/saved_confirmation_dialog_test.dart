import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/widgets/adapted_resume_preview_screen.dart';

/// Revisão UX 28/07, achado P3-44: o diálogo "CV salvo!" saía com um duplo
/// sublinhado AMARELO por baixo de cada linha, cortando os descendentes
/// (g, p, ç). Não era decoração de design — é o estilo de diagnóstico que o
/// Flutter aplica a texto sem nenhum `Material` acima na árvore, e `showDialog`
/// entrega o builder direto no overlay.
///
/// O teste ancora no widget REAL (não numa reprodução), lendo o estilo herdado
/// no ponto exato onde o título é pintado.
void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const SavedConfirmationDialog(
                    jobTitle: 'Estagiário de Suprimentos',
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump(); // abre a rota
    await tester.pump(const Duration(milliseconds: 800)); // roda a animação
  }

  testWidgets('o texto do diálogo NÃO herda sublinhado', (tester) async {
    await openDialog(tester);

    final titleContext = tester.element(find.text('CV salvo!'));
    final inherited = DefaultTextStyle.of(titleContext).style;

    expect(inherited.decoration, isNot(TextDecoration.underline));
    expect(inherited.decorationColor, isNot(const Color(0xFFFFFF00)));
  });

  testWidgets('o card tem um Material acima do texto', (tester) async {
    await openDialog(tester);

    // É o Material que remove o estilo de diagnóstico — se alguém tirar o
    // wrapper, o sublinhado amarelo volta.
    expect(
      find.ancestor(
        of: find.text('CV salvo!'),
        matching: find.byType(Material),
      ),
      findsWidgets,
    );
  });

  testWidgets('mostra o título da vaga e o botão de saída', (tester) async {
    await openDialog(tester);
    expect(find.textContaining('Estagiário de Suprimentos'), findsOneWidget);
    expect(find.text('Entendi'), findsOneWidget);
  });
}
