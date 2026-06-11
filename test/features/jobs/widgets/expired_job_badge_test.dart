import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/widgets/expired_job_badge.dart';

void main() {
  testWidgets('ExpiredJobBadge renderiza o rótulo e o ícone', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExpiredJobBadge()),
      ),
    );

    expect(find.text('Expirada'), findsOneWidget);
    expect(find.byIcon(Icons.event_busy_outlined), findsOneWidget);
  });
}
