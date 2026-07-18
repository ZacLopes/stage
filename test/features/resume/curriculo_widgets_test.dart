import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/resume/widgets/curriculo_toggle.dart';
import 'package:career_gamification/features/resume/widgets/curriculo_section_stepper.dart';
import 'package:career_gamification/features/resume/widgets/fortalecer_perfil_disclosure.dart';
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
      expect(find.text('Prévia do currículo'), findsOneWidget);

      await tester.tap(find.text('Prévia do currículo'));
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

  group('FortalecerPerfilDisclosure', () {
    testWidgets('nasce recolhido e mostra um resumo compacto do progresso', (
      tester,
    ) async {
      final statuses = <TrilhaSection, SectionStatus>{
        TrilhaSection.formacao: SectionStatus.done,
        TrilhaSection.experiencia: SectionStatus.current,
        TrilhaSection.skills: SectionStatus.pending,
        TrilhaSection.idiomas: SectionStatus.pending,
        TrilhaSection.interesses: SectionStatus.pending,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FortalecerPerfilDisclosure(
              completedCount: 1,
              totalCount: 5,
              child: CurriculoSectionStepper(statuses: statuses),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fortalecer perfil'), findsOneWidget);
      expect(find.text('1 de 5 etapas concluídas'), findsOneWidget);
      for (final section in kStepperSections) {
        expect(find.text(trilhaSectionLabel(section)), findsNothing);
      }
    });

    testWidgets('expande, mantém as seções tocáveis e recolhe novamente', (
      tester,
    ) async {
      TrilhaSection? tapped;
      final statuses = {
        for (final section in kStepperSections) section: SectionStatus.pending,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FortalecerPerfilDisclosure(
              completedCount: 0,
              totalCount: 5,
              child: CurriculoSectionStepper(
                statuses: statuses,
                onSectionTap: (section) => tapped = section,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Fortalecer perfil'));
      await tester.pumpAndSettle();
      for (final section in kStepperSections) {
        expect(find.text(trilhaSectionLabel(section)), findsOneWidget);
      }

      await tester.tap(find.text('Skills'));
      expect(tapped, TrilhaSection.skills);

      await tester.tap(find.text('Fortalecer perfil'));
      await tester.pumpAndSettle();
      for (final section in kStepperSections) {
        expect(find.text(trilhaSectionLabel(section)), findsNothing);
      }
    });

    testWidgets('expõe uma ação semântica para leitores de tela', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final statuses = {
        for (final section in kStepperSections) section: SectionStatus.pending,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FortalecerPerfilDisclosure(
              completedCount: 0,
              totalCount: 5,
              child: CurriculoSectionStepper(statuses: statuses),
            ),
          ),
        ),
      );

      final disclosure = find.bySemanticsLabel(RegExp(r'Fortalecer perfil'));
      expect(disclosure, findsOneWidget);
      final data = tester.getSemantics(disclosure).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isExpanded.toBoolOrNull(), isFalse);
      semantics.dispose();
    });
  });
}
