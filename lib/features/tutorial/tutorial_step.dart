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

  const TutorialStep({
    required this.title,
    required this.description,
    this.targetKey,
    this.onEnter,
    this.padding = 8,
    this.radius = 12,
    this.anchor = TutorialTooltipAnchor.auto,
  });
}
