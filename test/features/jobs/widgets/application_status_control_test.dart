import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/application.dart';
import 'package:career_gamification/features/jobs/widgets/application_status_control.dart';

/// Chip/seletor de status da aba Candidaturas. Mostra o status atual em pt-BR
/// e, ao tocar, oferece as transições válidas; seleção chama o callback. Sem
/// opções, permanece um indicador estático.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required ApplicationStatus status,
    required List<ApplicationStatus> options,
    required void Function(ApplicationStatus) onSelected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ApplicationStatusControl(
              status: status,
              options: options,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('mostra o status atual em pt-BR', (tester) async {
    await pump(
      tester,
      status: ApplicationStatus.submitted,
      options: const [ApplicationStatus.inReview],
      onSelected: (_) {},
    );
    expect(find.text('Enviada'), findsOneWidget);
  });

  testWidgets('toca → menu com transições válidas → onSelected', (
    tester,
  ) async {
    ApplicationStatus? picked;
    await pump(
      tester,
      status: ApplicationStatus.submitted,
      options: const [ApplicationStatus.inReview, ApplicationStatus.interview],
      onSelected: (s) => picked = s,
    );

    await tester.tap(find.byKey(const ValueKey('application-status-trigger')));
    await tester.pumpAndSettle();

    expect(find.text('Atualizar etapa'), findsOneWidget);
    expect(find.text('Está em análise'), findsOneWidget);
    expect(find.text('A empresa está avaliando seu perfil.'), findsOneWidget);
    expect(find.text('Entrevista agendada'), findsOneWidget);

    await tester.tap(find.text('Está em análise'));
    await tester.pumpAndSettle();
    expect(picked, ApplicationStatus.inReview);
    expect(find.text('Atualizar etapa'), findsNothing);
  });

  testWidgets('sem opções → chip estático (sem gatilho)', (
    tester,
  ) async {
    await pump(
      tester,
      status: ApplicationStatus.hired,
      options: const [],
      onSelected: (_) {},
    );
    // Rótulos concordam com A CANDIDATURA (feminino), não com o candidato —
    // `hired` virou "Aprovada". Revisão UX 28/07, achado P2-21.
    expect(find.text('Aprovada'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('application-status-trigger')),
      findsNothing,
    );
  });
}
