import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/core/widgets/country_code_field.dart';

/// Revisão UX 28/07, achado P3-42: o DDI era caixa de texto livre no cadastro
/// e seletor com bandeira de 4 opções no onboarding — mesmo dado, dois
/// controles. Unificado no `CountryCodeField`.
///
/// O caso que mais importa é o legado: contas criadas quando o campo aceitava
/// qualquer número podem ter um DDI fora das 4 opções. Um
/// `DropdownButtonFormField` cujo `initialValue` não existe entre os `items`
/// falha o assert em debug e renderiza vazio em release — a pessoa perderia o
/// próprio DDI ao passar pela tela.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required String value,
    required ValueChanged<String> onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CountryCodeField(value: value, onChanged: onChanged),
          ),
        ),
      ),
    );
  }

  testWidgets('mostra o código selecionado com bandeira', (tester) async {
    await pump(tester, value: '+55', onChanged: (_) {});
    expect(find.text('🇧🇷 +55'), findsOneWidget);
  });

  testWidgets('abre a lista e seleciona outro país', (tester) async {
    String? picked;
    await pump(tester, value: '+55', onChanged: (v) => picked = v);

    await tester.tap(find.byType(CountryCodeField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🇵🇹 +351').last);
    await tester.pumpAndSettle();

    expect(picked, '+351');
  });

  testWidgets('DDI legado fora da lista continua visível e selecionado',
      (tester) async {
    await pump(tester, value: '+34', onChanged: (_) {});
    // Sem o item extra, o dropdown renderizaria vazio (ou estouraria o assert)
    // e a pessoa veria o próprio país sumir.
    expect(find.text('+34'), findsOneWidget);
  });

  testWidgets('DDI legado não duplica as opções conhecidas', (tester) async {
    await pump(tester, value: '+34', onChanged: (_) {});

    await tester.tap(find.byType(CountryCodeField));
    await tester.pumpAndSettle();

    // 4 conhecidos + o legado; '+55' aparece uma vez só no menu.
    expect(find.text('🇧🇷 +55'), findsOneWidget);
    expect(find.text('+34'), findsNWidgets(2)); // botão fechado + item do menu
  });
}
