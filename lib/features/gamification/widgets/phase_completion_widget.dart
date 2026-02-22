import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:career_gamification/features/gamification/gamification_viewmodel.dart';
import 'package:career_gamification/features/home/home_viewmodel.dart';
import 'package:career_gamification/features/auth/user_viewmodel.dart';
import 'package:career_gamification/data/models/models.dart';

class PhaseCompletionWidget extends StatefulWidget {
  final Phase phase;
  final GamificationViewModel viewModel;

  const PhaseCompletionWidget({
    super.key, 
    required this.phase, 
    required this.viewModel
  });

  @override
  State<PhaseCompletionWidget> createState() => _PhaseCompletionWidgetState();
}

class _PhaseCompletionWidgetState extends State<PhaseCompletionWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    );

    _slideAnimation = Tween<double>(begin: 50, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOut),
      )
    );

     _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      )
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    if (!mounted) return;
    setState(() => _isSaving = true);
    
    try {
      await widget.viewModel.saveProgress(widget.phase.id);
      
      if (!mounted) return;
      await context.read<UserViewModel>().refreshUser();
      
      if (!mounted) return;
      if (context.mounted) {
        await context.read<HomeViewModel>().refresh();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Gradient decoration
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [  Colors.white, Color(0xFFE5F9E0) ], // Subtle green
                )
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                
                // Animated Icon
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: const Color(0xFF58CC02),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF58CC02).withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 5,
                          offset: const Offset(0, 8),
                        )
                      ]
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 80),
                  ),
                ),
                
                const SizedBox(height: 48),

                // Animated Text
                FadeTransition(
                  opacity: _opacityAnimation,
                  child: Transform.translate(
                    offset: Offset(0, _slideAnimation.value),
                    child: Column(
                      children: [
                        const Text(
                          'Fase Concluída!',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF4B4B4B), // Dark text text
                            letterSpacing: 0.5,
                          ),
                        ),

                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 3),
                
                // Continue Button
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: FadeTransition(
                     opacity: _opacityAnimation,
                     child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _handleContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF58CC02),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFE5E7EB),
                          elevation: 4, // Drop shadow
                          shadowColor: const Color(0xFF46A302), // Darker green shadow (3D effect)
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ).copyWith(
                          elevation: WidgetStateProperty.resolveWith((states) {
                             if (states.contains(WidgetState.pressed)) return 0;
                             return 4;
                          }),
                        ),
                        child: _isSaving 
                            ? const SizedBox(
                                width: 24, 
                                height: 24, 
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                              )
                            : const Text(
                                'CONTINUAR',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
