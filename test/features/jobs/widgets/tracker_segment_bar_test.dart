import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/application.dart';
import 'package:career_gamification/features/jobs/widgets/tracker_segment_bar.dart';

/// FASE 3 (T3.1 redesign, R3): barra de segmentos da aba Candidaturas.
void main() {
  Future<ApplicationSegment?> pump(WidgetTester tester) async {
    ApplicationSegment? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackerSegmentBar(
            selected: ApplicationSegment.salvas,
            counts: const {
              ApplicationSegment.salvas: 3,
              ApplicationSegment.enviadas: 2,
              ApplicationSegment.emProcesso: 0,
              ApplicationSegment.finalizadas: 1,
            },
            onSelected: (s) => picked = s,
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('mostra os 4 segmentos com contagem (>0)', (tester) async {
    await pump(tester);
    expect(find.text('Salvas'), findsOneWidget);
    expect(find.text('Enviadas'), findsOneWidget);
    expect(find.text('Em processo'), findsOneWidget);
    expect(find.text('Finalizadas'), findsOneWidget);
    // contagens > 0 aparecem; zero não.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('tocar num segmento chama onSelected', (tester) async {
    ApplicationSegment? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackerSegmentBar(
            selected: ApplicationSegment.salvas,
            counts: const {ApplicationSegment.enviadas: 2},
            onSelected: (s) => picked = s,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Enviadas'));
    await tester.pump();
    expect(picked, ApplicationSegment.enviadas);
  });
}
