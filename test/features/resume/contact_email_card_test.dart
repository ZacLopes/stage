import 'package:career_gamification/features/resume/widgets/general_resume_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('avisa sem bloquear export e leva para adicionar e-mail', (
    tester,
  ) async {
    var openedProfile = false;
    var exported = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GeneralResumeCardView(
              hasContent: true,
              hasUsableContactEmail: false,
              onCompleteProfile: () => openedProfile = true,
              onExport: () => exported = true,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Adicione um e-mail de contato antes de enviar o currículo. Seu e-mail de login não será exibido.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Adicionar e-mail'));
    expect(openedProfile, isTrue);

    await tester.tap(find.text('Exportar PDF'));
    expect(exported, isTrue);
  });
}
