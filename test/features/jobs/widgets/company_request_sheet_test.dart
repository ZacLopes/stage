import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/widgets/company_request_sheet.dart';

/// FASE 2 (T2.3, R3): widget test do sheet "Pedir uma empresa".
/// (O caminho de submit real depende de Supabase/Provider — coberto no
/// device; aqui validamos render + validação local de campo vazio, que
/// roda ANTES de qualquer acesso a provider.)
void main() {
  testWidgets('renderiza campos e valida empresa vazia sem enviar',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CompanyRequestSheet())),
    );

    expect(find.text('Pedir uma empresa'), findsOneWidget);
    expect(find.text('Empresa'), findsOneWidget);
    expect(find.text('Por quê? (opcional)'), findsOneWidget);

    await tester.tap(find.text('Enviar pedido'));
    await tester.pump();

    expect(
      find.text('Conta pra gente qual empresa você quer ver aqui.'),
      findsOneWidget,
    );
  });
}
