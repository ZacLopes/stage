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

  testWidgets('Fase 3: headline/LinkedIn/site/disponibilidade populam e emitem',
      (tester) async {
    PersonalInfo? latest;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PersonalInfoForm(
              initial: const PersonalInfo(
                userId: 'u',
                firstName: 'A',
                lastName: 'B',
                headline: 'Head inicial',
                linkedinUrl: 'lk/inicial',
                website: 'site.inicial',
                availability: 'Imediata',
              ),
              onChanged: (draft) => latest = draft,
            ),
          ),
        ),
      ),
    );

    // Populam a partir do initial.
    expect(find.text('Head inicial'), findsOneWidget);
    expect(find.text('lk/inicial'), findsOneWidget);
    expect(find.text('site.inicial'), findsOneWidget);
    expect(find.text('Imediata'), findsOneWidget);
    expect(find.text('Título profissional'), findsOneWidget);
    expect(find.text('Disponibilidade'), findsOneWidget);

    // Editar cada um emite o valor no draft (via o label, robusto à ordem).
    await tester.enterText(
        find.widgetWithText(TextField, 'Head inicial'), 'Novo título');
    await tester.pump();
    expect(latest?.headline, 'Novo título');

    await tester.enterText(
        find.widgetWithText(TextField, 'lk/inicial'), 'lk/novo');
    await tester.pump();
    expect(latest?.linkedinUrl, 'lk/novo');

    await tester.enterText(
        find.widgetWithText(TextField, 'site.inicial'), 'novo.site');
    await tester.pump();
    expect(latest?.website, 'novo.site');

    await tester.enterText(
        find.widgetWithText(TextField, 'Imediata'), 'Em março');
    await tester.pump();
    expect(latest?.availability, 'Em março');
  });
}
