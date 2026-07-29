import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/onboarding/presentation/widgets/onboarding_choice_tile.dart';

/// Revisão UX 28/07, achado P3-41: nas telas de origem e gênero o único sinal
/// de "isso é escolhível, e só uma" era um check que aparecia DEPOIS do toque.
/// Antes de tocar, nada. O ladrilho unificado mostra o rádio nos DOIS estados.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool selected,
    required VoidCallback onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnboardingChoiceTile(
            label: 'Instagram',
            selected: selected,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  testWidgets('não selecionado JÁ mostra o rádio (afordância antes do toque)',
      (tester) async {
    await pump(tester, selected: false, onTap: () {});
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked_rounded), findsNothing);
  });

  testWidgets('selecionado troca o rádio para marcado', (tester) async {
    await pump(tester, selected: true, onTap: () {});
    expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsNothing);
  });

  testWidgets('toque dispara onTap', (tester) async {
    var taps = 0;
    await pump(tester, selected: false, onTap: () => taps++);
    await tester.tap(find.text('Instagram'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('anuncia escolha única para o leitor de tela', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, selected: true, onTap: () {});

    final node = tester.getSemantics(find.byType(OnboardingChoiceTile).first);
    expect(node.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
    expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);

    handle.dispose();
  });
}
