import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/tutorial_keys.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class TutorialService {
  static const String _kHasSeenTutorialPrefix = 'has_seen_tutorial_';
  static final ValueNotifier<bool> tutorialTrigger = ValueNotifier(false);

  static void triggerTutorial() {
    tutorialTrigger.value = !tutorialTrigger.value; // Toggle to trigger
  }

  String _getKey(String userId) => '$_kHasSeenTutorialPrefix$userId';

  Future<void> showTutorialIfNeeded(BuildContext context, {Function(int)? onTabChange}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_getKey(userId)) ?? false;

    if (!hasSeen) {
      // Show dialog asking if user wants to see the tutorial
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(
             'Bem-vindo!',
             style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Gostaria de fazer um tour rápido para conhecer as principais funcionalidades do app?',
            style: GoogleFonts.inter(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                _markAsSeen();
                _showSkipFeedback(context);
              },
              child: Text(
                'Agora não',
                style: GoogleFonts.poppins(color: Colors.grey),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                showTutorial(context, onTabChange: onTabChange);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
              ),
              child: Text(
                'Começar Tour',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _showSkipFeedback(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Você pode ver o tutorial a qualquer momento nas Configurações.',
          style: GoogleFonts.inter(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF4F46E5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> resetTutorial() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_getKey(userId), false);
  }

  void showTutorial(BuildContext context, {Function(int)? onTabChange}) {
    TutorialCoachMark(
      targets: _createTargets(onTabChange),
      colorShadow: const Color(0xFF4F46E5),
      textSkip: "PULAR",
      textStyleSkip: GoogleFonts.poppins(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
      paddingFocus: 10,
      opacityShadow: 0.85,
      onFinish: () => _markAsSeen(),
      onSkip: () {
        _markAsSeen();
        _showSkipFeedback(context);
        return true;
      },
    ).show(context: context);
  }

  Future<void> _markAsSeen() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_getKey(userId), true);
  }

  Widget _buildContent({
    required String title,
    required String description,
    required IconData icon,
    bool isBottom = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: GoogleFonts.inter(
            color: Colors.white.withOpacity(0.9),
            fontSize: 16,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  List<TargetFocus> _createTargets(Function(int)? onTabChange) {
    return [
      TargetFocus(
        identify: "tracks_tab",
        keyTarget: TutorialKeys.tracksTabKey,
        alignSkip: Alignment.topRight,
        shape: ShapeLightFocus.Circle,
        radius: 35,
        enableOverlayTab: true,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return _buildContent(
                title: "Sua Jornada",
                description: "Aqui começa a sua trilha! Explore diferentes mundos e responda às perguntas para construir sua carreira passo a passo.",
                icon: Icons.map_outlined,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "xp_header",
        keyTarget: TutorialKeys.xpHeaderKey,
        alignSkip: Alignment.bottomRight,
        shape: ShapeLightFocus.RRect,
        radius: 16,
        paddingFocus: 8,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return _buildContent(
                title: "Seu Progresso",
                description: "Acompanhe aqui o quanto do seu currículo já está pronto. Complete 100% para garantir o melhor resultado profissional!",
                icon: Icons.check_circle_outline, // Changed icon to match UI
                isBottom: true,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "resume_tab",
        keyTarget: TutorialKeys.resumeTabKey,
        alignSkip: Alignment.topRight,
        shape: ShapeLightFocus.Circle,
        radius: 35,
        enableOverlayTab: true,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return _buildContent(
                title: "Currículo Mágico",
                description: "A IA transforma suas respostas em um currículo incrível. Escolha entre modelos modernos e baixe em PDF num instante.",
                icon: Icons.description_outlined,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "profile_tab",
        keyTarget: TutorialKeys.profileTabKey,
        alignSkip: Alignment.topRight,
        shape: ShapeLightFocus.Circle,
        radius: 35,
        enableOverlayTab: true,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return _buildContent(
                title: "Seu Perfil Profissional",
                description: "Aqui vive a sua identidade. Veja como a IA descreve suas habilidades e experiências com base no que você contou.",
                icon: Icons.person_outline,
              );
            },
          ),
        ],
      ),
    ];
  }
}
