import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/job.dart';
import 'package:career_gamification/features/jobs/screens/job_details_sheet.dart';
import 'package:career_gamification/features/jobs/utils/match_score.dart';

/// FASE 2 fixes (#2, R3): mapa faixa→texto do detalhe com balde honesto pra
/// score baixo/zero (antes tudo <70 caía em "Match razoável — vale tentar!").
/// Limiares alinhados ao match_band.dart (70/40).
///
/// Revisão UX 28/07, achado P2-13: os RÓTULOS mudaram de propósito. Eram um
/// vocabulário paralelo ao do card ("Bom match" aqui × "Alta" lá, para o
/// MESMO score de 75), e agora derivam do adjetivo da banda. Os limiares e a
/// quantidade de baldes seguem os mesmos — a decisão da Fase 2 continua de pé.
void main() {
  Job job() => Job.fromJson({
        'id': 'j1',
        'title': 'Estágio X',
        'company_name': 'Empresa Y',
        'description': 'desc',
        'work_model': 'remoto',
        'job_type': 'estagio',
        'area': 'Tecnologia',
        'published_at': DateTime.now().toIso8601String(),
      });

  MatchResult matchOf(int score) =>
      MatchResult(score: score, reasons: const []);

  // Passa match NÃO-nulo → JobDetailsSheet não chama resolveMatchForJob
  // (sem necessidade de Providers no teste).
  Future<void> pumpWithScore(WidgetTester tester, int score) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobDetailsSheet(job: job(), match: matchOf(score)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('score < 40 → "Match baixo" (não "razoável")', (tester) async {
    await pumpWithScore(tester, 30);
    expect(find.text('Match baixo'), findsOneWidget);
    expect(find.text('Match razoável'), findsNothing);
  });

  testWidgets('40–69 → "Match médio" (banda média)', (tester) async {
    await pumpWithScore(tester, 50);
    expect(find.text('Match médio'), findsOneWidget);
  });

  testWidgets('70–84 → "Match alto" — o card diz "Alto" p/ o mesmo score',
      (tester) async {
    await pumpWithScore(tester, 75);
    expect(find.text('Match alto'), findsOneWidget);
    // O rótulo antigo era o defeito: nada dizia que "Bom" e "Alta" eram a
    // mesma medida.
    expect(find.text('Bom match'), findsNothing);
  });

  testWidgets('>= 85 → "Match excelente" (superlativo da banda alta)',
      (tester) async {
    await pumpWithScore(tester, 90);
    expect(find.text('Match excelente'), findsOneWidget);
  });
}
