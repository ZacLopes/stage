import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Wrapper sobre `PostHogMaskWidget` com nome semântico — usado em telas com
/// PII (CV, perfil, auth). Tudo dentro de `PiiMask` vira preto no session
/// replay do PostHog. Telas neutras (Vagas, Trilha, Home) não precisam.
///
/// Uso:
/// ```dart
/// return Scaffold(
///   body: PiiMask(child: SafeArea(child: ...)),
/// );
/// ```
class PiiMask extends StatelessWidget {
  final Widget child;
  const PiiMask({super.key, required this.child});

  @override
  Widget build(BuildContext context) => PostHogMaskWidget(child: child);
}
