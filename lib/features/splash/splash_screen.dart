import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/stage_colors.dart';
import '../auth/user_viewmodel.dart';
import '../auth/onboarding_screen.dart';
import '../auth/profile_setup_screen.dart';
import '../auth/completion_screen.dart';
import '../home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _textFade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOut),
      ),
    );

    _controller.forward();

    Timer(const Duration(seconds: 3), () {
      if (mounted) _navigateNext();
    });
  }

  void _navigateNext() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AuthGate(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: StageColors.brandGradient,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated Logo
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _logoFade.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: child,
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/images/image copy.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Animated "Stage" text
              AnimatedBuilder(
                animation: _textFade,
                builder: (context, child) {
                  return Opacity(
                    opacity: _textFade.value,
                    child: child,
                  );
                },
                child: Text(
                  'Stage',
                  style: GoogleFonts.outfit(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrapper to handle auth state: logged in → Home, logged out → Onboarding
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading && viewModel.user == null) {
          // Brief loading state while checking auth
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: StageColors.brandGradient,
              ),
            ),
          );
        }

        if (viewModel.isLoggedIn) {
          // Roteamento centralizado pós-login. Ordem importa:
          // 1. needsProfileSetup → ProfileSetupScreen (cobre o caso Apple/Google
          //    que pula EmailSignup — coleta nome, idade, telefone, curso,
          //    semestre, universidade). Inclui o caso "Apple sem nome".
          // 2. !hasCampaign → CompletionScreen (escolher upload CV / trilha).
          // 3. tudo certo → HomeScreen.
          //
          // Esse Consumer re-roteia automaticamente quando o state muda
          // (ex: user salva profile → needsProfileSetup vira false → rebuild →
          // CompletionScreen). Telas filhas NÃO devem fazer push manual —
          // gera GlobalKey duplicada com a HomeScreen que esse Consumer monta.
          if (viewModel.needsProfileSetup) {
            return const ProfileSetupScreen();
          }
          if (!viewModel.hasCampaign) {
            return const CompletionScreen();
          }
          return const HomeScreen();
        } else {
          return const OnboardingScreen();
        }
      },
    );
  }
}
