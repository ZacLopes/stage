import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/home/app_guide_screen.dart';

class TutorialService {
  static const String _kHasSeenTutorialPrefix = 'has_seen_tutorial_';
  static final ValueNotifier<bool> tutorialTrigger = ValueNotifier(false);

  static void triggerTutorial() {
    tutorialTrigger.value = !tutorialTrigger.value;
  }

  static final Map<String, bool> _hasSeenCache = {};
  static bool _isShowing = false;

  String _getKey(String userId) => '$_kHasSeenTutorialPrefix$userId';

  Future<void> showTutorialIfNeeded(BuildContext context, {Function(int)? onTabChange}) async {
    if (_isShowing) return;
    
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Check cache first for instant response
    if (_hasSeenCache[userId] == true) return;

    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_getKey(userId)) ?? false;
    
    // Update cache
    _hasSeenCache[userId] = hasSeen;

    if (!hasSeen) {
      if (!context.mounted) return;
      showTutorial(context, onTabChange: onTabChange);
    }
  }

  Future<void> resetTutorial() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _hasSeenCache[userId] = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_getKey(userId), false);
  }

  void showTutorial(BuildContext context, {Function(int)? onTabChange}) {
    if (_isShowing) return;
    _isShowing = true;

    // Show the new Full-Screen Onboarding Guide instead of coach marks
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return AppGuideScreen(
            onFinish: () async {
              // Await markAsSeen so the state is actually updated
              await markAsSeen();
              _isShowing = false;
              
              if (onTabChange != null) {
                onTabChange(1); // Navigate to Trilha tab immediately
              }
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    ).then((_) {
      // Ensure guard is reset if they pop the screen without onFinish (e.g. back button if enabled)
      _isShowing = false;
    });
  }

  Future<void> markAsSeen() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _hasSeenCache[userId] = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_getKey(userId), true);
  }
}
