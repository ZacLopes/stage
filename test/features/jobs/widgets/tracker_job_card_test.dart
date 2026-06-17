import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/application.dart';
import 'package:career_gamification/features/jobs/models/job.dart';
import 'package:career_gamification/features/jobs/widgets/tracker_job_card.dart';

/// FASE 3 (T3.1 redesign, R3): card unificado da aba Candidaturas.
/// Salvas (sem application) → CTA Aplicar; acompanhamento (com application) →
/// badge de status, sem CTA de aplicar.
void main() {
  Job job() => Job.fromJson({
        'id': 'j1',
        'title': 'Estágio em Dados',
        'company_name': 'ACME',
        'description': 'desc',
        'work_model': 'remoto',
        'job_type': 'estagio',
        'area': 'Tecnologia',
        'published_at': DateTime.now().toIso8601String(),
      });

  Application app(ApplicationStatus s) => Application(
        id: 'a1',
        userId: 'u1',
        jobId: 'j1',
        type: ApplicationType.externalConfirmed,
        status: s,
        createdAt: DateTime(2026, 6, 12),
        updatedAt: DateTime(2026, 6, 12),
      );

  testWidgets('Salvas: mostra CTA Aplicar e o título', (tester) async {
    var applied = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TrackerJobCard(
          job: job(),
          application: null,
          isExpired: false,
          onTap: () {},
          applyLabel: 'Aplicar no site',
          applyIcon: Icons.open_in_new_rounded,
          onApply: () => applied = true,
        ),
      ),
    ));
    expect(find.text('Estágio em Dados'), findsOneWidget);
    expect(find.text('Aplicar no site'), findsOneWidget);
    await tester.tap(find.text('Aplicar no site'));
    expect(applied, isTrue);
  });

  testWidgets('Acompanhamento: badge de status, sem CTA Aplicar', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TrackerJobCard(
          job: job(),
          application: app(ApplicationStatus.submitted),
          isExpired: false,
          onTap: () {},
          // sem onStatusChange → badge estático
        ),
      ),
    ));
    expect(find.text('Enviada'), findsOneWidget); // label do status submitted
    expect(find.text('Aplicar no site'), findsNothing);
  });
}
