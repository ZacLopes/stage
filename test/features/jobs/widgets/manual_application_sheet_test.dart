import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/application.dart';
import 'package:career_gamification/features/jobs/widgets/manual_application_sheet.dart';

/// FASE 3 T3.3 (R3): sheet de adição manual. Empresa+vaga obrigatórios; link e
/// status opcionais; retorna ManualApplicationInput.
void main() {
  Future<ManualApplicationInput?> open(WidgetTester tester) async {
    ManualApplicationInput? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showManualApplicationSheet(context);
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
    return result;
  }

  testWidgets('valida empresa/vaga vazias (não fecha sem preencher)', (tester) async {
    await open(tester);
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    // sheet continua aberto, mostra erros
    expect(find.text('Informe a empresa'), findsOneWidget);
    expect(find.text('Informe a vaga'), findsOneWidget);
    expect(find.text('Adicionar candidatura'), findsOneWidget);
  });

  testWidgets('preenche e adiciona → ManualApplicationInput', (tester) async {
    ManualApplicationInput? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showManualApplicationSheet(context);
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

    await tester.enterText(find.widgetWithText(TextField, 'Empresa *'), 'ACME');
    await tester.enterText(
        find.widgetWithText(TextField, 'Vaga / cargo *'), 'Estágio Dados');
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.company, 'ACME');
    expect(captured!.title, 'Estágio Dados');
    expect(captured!.status, ApplicationStatus.submitted);
    expect(captured!.url, isNull);
  });
}
