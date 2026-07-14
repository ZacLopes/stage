import 'package:career_gamification/features/profile/domain/entities/entities.dart';
import 'package:career_gamification/features/profile/presentation/widgets/personal_info_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('avisa sobre relay e só emite um contato público válido', (
    tester,
  ) async {
    PersonalInfo? latest;
    var changes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PersonalInfoForm(
              initial: const PersonalInfo(
                userId: 'user-1',
                firstName: 'Pessoa',
                lastName: 'Candidata',
                email: 'alias@privaterelay.appleid.com',
              ),
              onChanged: (draft) {
                changes++;
                latest = draft;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('E-mail no currículo'), findsOneWidget);
    expect(
      find.text(
        'Este e-mail privado da Apple serve para login. Troque por um contato para o currículo.',
      ),
      findsOneWidget,
    );

    final emailField = find.byType(TextField).at(2);
    await tester.enterText(emailField, 'ainda-invalido');
    await tester.pump();
    expect(changes, 0);

    await tester.enterText(emailField, '  Profissional@Example.COM ');
    await tester.pump();

    expect(changes, 1);
    expect(latest?.email, 'profissional@example.com');
    expect(
      find.text(
        'Aparece no currículo e pode ser usado por recrutadores. Não altera seu login.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('reporta texto inválido mesmo preservando o último salvo', (
    tester,
  ) async {
    final validity = <bool>[];
    const initial = PersonalInfo(
      userId: 'user-2',
      firstName: 'Pessoa',
      lastName: 'Candidata',
      email: 'contato@example.com',
    );
    PersonalInfo latest = initial;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PersonalInfoForm(
              initial: initial,
              onChanged: (draft) => latest = draft,
              onEmailValidityChanged: validity.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(validity.last, isTrue);

    await tester.enterText(find.byType(TextField).at(2), 'invalido');
    await tester.pump();

    expect(validity.last, isFalse);
    expect(
      latest.email,
      'contato@example.com',
      reason: 'autosave deve preservar o último contato válido',
    );
  });
}
