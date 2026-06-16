import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/application.dart';
import 'package:career_gamification/features/jobs/widgets/application_status_control.dart';

/// FASE 3 T3.1 (R3): chip/menu de status da aba Candidaturas. Mostra o status
/// atual em pt-BR e, ao tocar, oferece as transições válidas; seleção chama o
/// callback. Sem opções → chip estático (sem menu).
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

  testWidgets('toca → menu com transições válidas → onSelected', (tester) async {
    ApplicationStatus? picked;
    await pump(
      tester,
      status: ApplicationStatus.submitted,
      options: const [
        ApplicationStatus.inReview,
        ApplicationStatus.interview,
      ],
      onSelected: (s) => picked = s,
    );

    await tester.tap(find.byType(ApplicationStatusControl));
    await tester.pumpAndSettle();

    expect(find.text('Em análise'), findsOneWidget);
    expect(find.text('Entrevista'), findsOneWidget);

    await tester.tap(find.text('Em análise'));
    await tester.pumpAndSettle();
    expect(picked, ApplicationStatus.inReview);
  });

  testWidgets('sem opções → chip estático (sem PopupMenuButton)', (tester) async {
    await pump(
      tester,
      status: ApplicationStatus.hired,
      options: const [],
      onSelected: (_) {},
    );
    expect(find.text('Contratado'), findsOneWidget);
    expect(find.byType(PopupMenuButton<ApplicationStatus>), findsNothing);
  });
}
