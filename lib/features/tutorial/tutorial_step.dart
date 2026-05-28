import 'package:flutter/widgets.dart';

/// Where the tooltip card should be placed relative to the spotlight.
enum TutorialTooltipAnchor {
  /// Decide automatically: above target if target is in the bottom half
  /// of the screen, below otherwise. Defaults for most steps.
  auto,

  /// Force the tooltip to be vertically centered (no spotlight needed —
  /// used for intro/outro steps without a target).
  center,
}

/// CTA branch on the final step. The overlay renders one button per
/// choice in place of the default "Bora começar" — used to fork users
/// into measurable starting paths (ver vagas vs cuidar do CV) for
/// post-onboarding analytics.
class TutorialFinalChoice {
  final String label;
  final IconData icon;

  /// Invoked AFTER the controller marks the tutorial as finished. Use
  /// it to navigate + track analytics. Don't call `controller.finish()`
  /// from here — the overlay already does it.
  final Future<void> Function() onTap;

  const TutorialFinalChoice({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

/// One step of the tutorial. The overlay renders these one at a time,
/// advancing via the "Próximo" button.
class TutorialStep {
  /// Title shown bold at the top of the tooltip card.
  final String title;

  /// Body text below the title. Plain string; supports `\n`.
  final String description;

  /// The widget to spotlight. Resolved via `targetKey.currentContext` at
  /// render time. If null, the overlay shows a centered tooltip with the
  /// whole screen dimmed (used for intro/outro steps).
  final GlobalKey? targetKey;

  /// Side effects to run BEFORE this step shows: switching tabs,
  /// scrolling something into view, opening a sheet, etc. The controller
  /// awaits a short delay after this so layout settles before measuring.
  final Future<void> Function()? onEnter;

  /// Extra space added around the target rect for the spotlight hole.
  final double padding;

  /// Corner radius of the spotlight hole.
  final double radius;

  /// Forces a specific tooltip placement. Default `auto`.
  final TutorialTooltipAnchor anchor;

  /// Multi-CTA outro: if this step is the LAST one and the list is
  /// non-empty, the tooltip swaps "Bora começar" for one button per
  /// choice. Empty list (default) preserves the legacy single-button
  /// behavior.
  final List<TutorialFinalChoice> finalChoices;

  const TutorialStep({
    required this.title,
    required this.description,
    this.targetKey,
    this.onEnter,
    this.padding = 8,
    this.radius = 12,
    this.anchor = TutorialTooltipAnchor.auto,
    this.finalChoices = const [],
  });
}
