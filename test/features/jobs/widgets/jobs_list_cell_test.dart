import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/job.dart';
import 'package:career_gamification/features/jobs/screens/jobs_list_screen.dart';

/// FASE 2 (T2.2, R3): widget test da célula do feed em lista.
void main() {
  Job job({int? salaryMin}) => Job.fromJson({
        'id': 'j1',
        'title': 'Estágio em Dados',
        'company_name': 'Stage Tech',
        'description': 'desc',
        'work_model': 'hibrido',
        'job_type': 'estagio',
        'area': 'Tecnologia',
        'location_city': 'São Paulo',
        'location_state': 'SP',
        'salary_min': salaryMin,
        'published_at': DateTime.now()
            .subtract(const Duration(days: 3))
            .toIso8601String(),
      });

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('renderiza título, empresa, chips de razão e bolsa',
      (tester) async {
    await pump(
      tester,
      JobsListCell(
        job: job(salaryMin: 150000),
        reasonLabels: const ['Área', 'Tipo'],
      ),
    );

    expect(find.text('Estágio em Dados'), findsOneWidget);
    expect(find.text('Stage Tech'), findsOneWidget);
    expect(find.text('Área'), findsOneWidget);
    expect(find.text('Tipo'), findsOneWidget);
    // salary_min em centavos → "R$ 1500" (formato do Job.salaryRange)
    expect(find.textContaining('R\$ 1500'), findsOneWidget);
  });

  testWidgets('sem salário mostra "A combinar" (83% das vagas — B10)',
      (tester) async {
    await pump(
      tester,
      JobsListCell(job: job(), reasonLabels: const []),
    );
    expect(find.textContaining('A combinar'), findsOneWidget);
    // sem razões casadas → nenhum chip
    expect(find.text('Área'), findsNothing);
  });

  testWidgets('tap na célula chama onTap (abre detalhe da vaga)',
      (tester) async {
    var tapped = 0;
    await pump(
      tester,
      JobsListCell(
        job: job(),
        reasonLabels: const ['Área'],
        onTap: () => tapped++,
      ),
    );
    await tester.tap(find.byType(JobsListCell));
    expect(tapped, 1);
  });
}
