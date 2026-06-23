import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/services/feature_flags_service.dart';
import 'package:career_gamification/features/trilha/presentation/trilha_entry_card.dart';

/// Cobre o gate do card de entrada da trilha (R3 — comportamento atrás de flag).
void main() {
  setUp(() => FeatureFlagsService.instance.resetForTesting());

  testWidgets('flag OFF (default): card escondido', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TrilhaEntryCard())),
    );
    expect(find.text('Completar com a IA'), findsNothing);
  });

  testWidgets('flag ON (100%): card aparece', (tester) async {
    FeatureFlagsService.instance
        .setFlagForTesting('trilha_coleta_v1', enabled: true, rolloutPct: 100);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TrilhaEntryCard())),
    );
    expect(find.text('Completar com a IA'), findsOneWidget);
  });
}
