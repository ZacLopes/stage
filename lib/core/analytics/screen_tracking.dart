import 'package:flutter/widgets.dart';

import '../../services/analytics_service.dart';

/// Mixin que dispara `$screen` com `screen_name` real no `initState` de
/// telas Stateful. Use em vez de chamar `Analytics.shared.screen(...)`
/// manualmente em cada tela — assim o nome fica colocado UMA vez e não
/// vaza pra `build()`.
///
/// Uso:
/// ```dart
/// class _JobsSwipeScreenState extends State<JobsSwipeScreen>
///     with ScreenTrackingMixin {
///   @override
///   String get screenName => 'jobs_swipe';
/// }
/// ```
///
/// Por que não usar só o `PosthogObserver`? A navegação do Stage é 100%
/// imperativa (`Navigator.push` sem `RouteSettings.name`), então o observer
/// vê todas as rotas como anônimas e reporta `screen_name = "root ('/')"`.
/// Esse mixin contorna o problema sem exigir refator pra rotas nomeadas.
mixin ScreenTrackingMixin<T extends StatefulWidget> on State<T> {
  /// Nome da tela em snake_case. Esse valor vira `screen_name` no PostHog.
  /// Padrão: `<feature>_<intent>`, ex.: `jobs_swipe`, `cv_template_picker`.
  String get screenName;

  /// Propriedades extras opcionais. Override pra anexar contexto da tela
  /// (ex.: `phase_id`, `job_id`) ao evento.
  Map<String, Object>? get screenProperties => null;

  @override
  void initState() {
    super.initState();
    // Dispara após o frame inicial pra não competir com a inicialização da
    // tela. fire-and-forget — analytics nunca pode bloquear UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Analytics.shared.screen(screenName, properties: screenProperties);
    });
  }
}
