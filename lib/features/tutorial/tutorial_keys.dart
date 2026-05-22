import 'package:flutter/widgets.dart';

/// Registry of [GlobalKey]s used by the tutorial overlay to locate widgets
/// it needs to spotlight. Keys are stable across rebuilds because they
/// live as static fields here — attach the same key in build() of the
/// target widget and the tutorial can ask it for its global rect.
class TutorialKeys {
  // Bottom-nav items (registered in HomeScreen)
  static final GlobalKey jobsTab = GlobalKey(debugLabel: 'tutorial.jobsTab');
  static final GlobalKey savedTab = GlobalKey(debugLabel: 'tutorial.savedTab');
  static final GlobalKey resumeTab = GlobalKey(debugLabel: 'tutorial.resumeTab');
  static final GlobalKey profileTab = GlobalKey(debugLabel: 'tutorial.profileTab');

  // JobsSwipeScreen
  static final GlobalKey swipeArea = GlobalKey(debugLabel: 'tutorial.swipeArea');
  static final GlobalKey aiButton = GlobalKey(debugLabel: 'tutorial.aiButton');

  // ResumeTab (entry-point cards)
  static final GlobalKey trailCard = GlobalKey(debugLabel: 'tutorial.trailCard');
  static final GlobalKey importCard = GlobalKey(debugLabel: 'tutorial.importCard');

  // Profile-first (Semana 2): botão "Editar Perfil" no header da aba Perfil.
  // Spotlight aponta aqui na primeira abertura pós-update.
  static final GlobalKey editProfileButton = GlobalKey(debugLabel: 'tutorial.editProfileButton');
}
