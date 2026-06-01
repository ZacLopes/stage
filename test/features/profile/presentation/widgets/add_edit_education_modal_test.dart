import 'package:career_gamification/features/profile/domain/entities/education.dart';
import 'package:career_gamification/features/profile/presentation/widgets/add_edit_education_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AddEditEducationModal', () {
    testWidgets('shows college fields and current semester slider', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestHost(
          initial: const Education(
            id: 'education-1',
            userId: 'user-1',
            institution: 'Link School',
            educationLevel: 'college',
            educationStatus: 'studying',
            degree: 'Graduação',
            currentSemester: 6,
            majors: [
              EducationMajor(
                id: 'major-1',
                educationId: 'education-1',
                name: 'Administração',
              ),
            ],
          ),
        ),
      );

      expect(_richTextContaining('Tipo de formação'), findsOneWidget);
      expect(_richTextContaining('Nome da faculdade'), findsOneWidget);
      expect(_richTextContaining('Situação'), findsOneWidget);
      expect(_richTextContaining('Tipo de diploma'), findsOneWidget);
      expect(_richTextContaining('Cursos principais'), findsOneWidget);
      expect(_richTextContaining('Semestre atual'), findsOneWidget);
      expect(find.text('6º semestre'), findsOneWidget);
      expect(_richTextContaining('Ano da escola'), findsNothing);
    });

    testWidgets('shows paused college with last semester label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestHost(
          initial: const Education(
            id: 'education-2',
            userId: 'user-1',
            institution: 'Insper',
            educationLevel: 'college',
            educationStatus: 'paused',
            degree: 'Graduação',
            currentSemester: 4,
            majors: [
              EducationMajor(
                id: 'major-1',
                educationId: 'education-2',
                name: 'Economia',
              ),
            ],
          ),
        ),
      );

      expect(_richTextContaining('Nome da faculdade'), findsOneWidget);
      expect(_richTextContaining('Último semestre cursado'), findsOneWidget);
      expect(find.text('4º semestre'), findsOneWidget);
    });

    testWidgets('shows school fields and hides college-only fields', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestHost(
          initial: const Education(
            id: 'education-3',
            userId: 'user-1',
            institution: 'Colégio Bandeirantes',
            educationLevel: 'school',
            educationStatus: 'studying',
            degree: 'Ensino médio',
            currentSchoolYear: 2,
          ),
        ),
      );

      expect(_richTextContaining('Tipo de formação'), findsOneWidget);
      expect(_richTextContaining('Nome da escola'), findsOneWidget);
      expect(_richTextContaining('Ano da escola'), findsOneWidget);
      expect(find.text('2º ano'), findsOneWidget);
      expect(_richTextContaining('Tipo de diploma'), findsNothing);
      expect(_richTextContaining('Semestre atual'), findsNothing);
      expect(_richTextContaining('Último semestre cursado'), findsNothing);
    });
  });
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
    description: 'RichText containing "$text"',
  );
}

class _TestHost extends StatelessWidget {
  final Education initial;

  const _TestHost({required this.initial});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: AddEditEducationModal(initial: initial, onSave: (_, _, _, _) {}),
      ),
    );
  }
}
