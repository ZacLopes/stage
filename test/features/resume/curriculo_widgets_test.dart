import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/resume/widgets/curriculo_toggle.dart';
import 'package:career_gamification/features/resume/widgets/curriculo_section_stepper.dart';
import 'package:career_gamification/features/trilha/application/trilha_section.dart';

/// Widget tests dos componentes novos da aba Currículo (R3): o toggle
/// [Conversa | Currículo] e o stepper de seções.
void main() {
  group('CurriculoToggle', () {
    testWidgets('mostra os dois rótulos e troca de aba ao tocar',
        (tester) async {
      int? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CurriculoToggle(index: 0, onChanged: (i) => changed = i),
        ),
      ));

      expect(find.text('Conversa'), findsOneWidget);
      expect(find.text('Currículo'), findsOneWidget);

      await tester.tap(find.text('Currículo'));
      expect(changed, 1);
    });

    testWidgets('não dispara onChanged ao tocar na aba já selecionada',
        (tester) async {
      int calls = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CurriculoToggle(index: 0, onChanged: (_) => calls++),
        ),
      ));
      await tester.tap(find.text('Conversa'));
      expect(calls, 0);
    });
  });

  group('CurriculoSectionStepper', () {
    testWidgets('renderiza as 5 seções e um check pra seção concluída',
        (tester) async {
      final statuses = <TrilhaSection, SectionStatus>{
        TrilhaSection.formacao: SectionStatus.done,
        TrilhaSection.experiencia: SectionStatus.current,
        TrilhaSection.skills: SectionStatus.pending,
        TrilhaSection.idiomas: SectionStatus.pending,
        TrilhaSection.interesses: SectionStatus.pending,
      };
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CurriculoSectionStepper(statuses: statuses)),
      ));

      for (final sec in kStepperSections) {
        expect(find.text(trilhaSectionLabel(sec)), findsOneWidget,
            reason: sec.name);
      }
      // A seção concluída mostra um check.
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('tocar numa seção dispara onSectionTap com a seção certa',
        (tester) async {
      TrilhaSection? tapped;
      final statuses = {
        for (final s in kStepperSections) s: SectionStatus.pending,
      };
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CurriculoSectionStepper(
            statuses: statuses,
            onSectionTap: (s) => tapped = s,
          ),
        ),
      ));

      await tester.tap(find.text('Skills'));
      expect(tapped, TrilhaSection.skills);

      await tester.tap(find.text('Idiomas'));
      expect(tapped, TrilhaSection.idiomas);
    });

    testWidgets('sem onSectionTap não há InkWell (não-tocável)',
        (tester) async {
      final statuses = {
        for (final s in kStepperSections) s: SectionStatus.pending,
      };
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CurriculoSectionStepper(statuses: statuses)),
      ));
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
