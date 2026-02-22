import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../auth/auth_screen.dart';
import '../auth/user_viewmodel.dart';
import '../auth/onboarding_screen.dart';
import '../home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();

    // Navigate to the next screen after the animation
    Timer(const Duration(seconds: 3), () {
      _checkAuthAndNavigate();
    });
  }

  void _checkAuthAndNavigate() {
    final userViewModel = Provider.of<UserViewModel>(context, listen: false);
    
    // Check authentication state (assuming UserViewModel handles this on init or we check here)
    // For now, simpler matching main.dart logic: logic is inside Consumer there, 
    // but here we might just want to replace this screen with the Auth wrapper 
    // or navigate based on state.
    
    // Actually, looking at main.dart, it uses a Consumer to decide what to show using conditional return.
    // So simpler approach: Just finish this splash and let the main app structure take over?
    // OR: We can navigate to a 'MainWrapper' that handles the switching.
    // Since main.dart logic `if (viewModel.isLoggedIn) ...` is inside `home:`, 
    // we can't easily just "navigate" to one or the other without replicating the logic.
    
    // Better approach: 
    // Make SplashScreen separate, then navigate to 'AuthGate' (a new wrapper) that 
    // currently is the body of the `home` in `main.dart`.
    
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const AuthGate(),
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
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Logo/Text
            ScaleTransition(
              scale: _scaleAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    // You can replace this Icon with your actual logo asset if you decide to use it later
                    // Image.asset('assets/images/image copy.png', width: 120, height: 120),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C27A).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded, // Example icon relevant to career
                        size: 80,
                        color: Color(0xFF00C27A),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Stage',
                      style: GoogleFonts.outfit(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Suba de nível na sua carreira',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
            // Loading Indicator
            FadeTransition(
              opacity: _fadeAnimation,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00C27A)),
                  strokeWidth: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Wrapper to handle the auth logic check that was previously in main.dart
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading && viewModel.user == null) {
           // While checking auth, we could show a loading, 
           // but since we just came from Splash, it might be fast enough.
           // Or we can just show an empty Scaffold to prevent "flash".
          return const Scaffold(backgroundColor: Colors.white); 
        }
        
        if (viewModel.isLoggedIn) {
          return const HomeScreen();
        } else {
          return const OnboardingScreen();
        }
      },
    );
  }
}
