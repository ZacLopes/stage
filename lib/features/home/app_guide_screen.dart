import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/stage_colors.dart';

/// Tutorial replay (3 slides) acionado pelo Settings → Tutorial.
/// Mostra apresentação do app e termina com botão "Começar do zero" que
/// fecha a tela e libera o usuário pra usar o app normalmente.
class AppGuideScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const AppGuideScreen({super.key, required this.onFinish});

  @override
  State<AppGuideScreen> createState() => _AppGuideScreenState();
}

class _AppGuideScreenState extends State<AppGuideScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutQuart,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentPage = index),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildSlide(
                  title: 'A sua Jornada',
                  description:
                      'Siga a trilha interativa e construa sua carreira passo a passo.',
                  icon: Icons.map_rounded,
                  color: StageColors.brandBlue,
                ),
                _buildSlide(
                  title: 'Currículo Mágico',
                  description:
                      'Nossa IA transforma suas conquistas em um currículo profissional em segundos.',
                  icon: Icons.auto_awesome,
                  color: const Color(0xFFF59E0B),
                ),
                _buildFinalSlide(),
              ],
            ),
            if (_currentPage < 2)
              Positioned(
                bottom: 40,
                left: 32,
                right: 32,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: List.generate(
                        3,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 8),
                          height: 8,
                          width: _currentPage == index ? 24 : 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? StageColors.brandBlue
                                : Colors.grey.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StageColors.brandBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('PRÓXIMO',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1)),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 80, color: color),
          ),
          const SizedBox(height: 60),
          Text(
            title,
            style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: StageColors.titleText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: GoogleFonts.inter(
                fontSize: 18, color: StageColors.bodyGray, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFinalSlide() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: StageColors.brandCyan.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.rocket_launch_rounded,
                  size: 48, color: StageColors.brandCyan),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Vamos lá!',
            style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: StageColors.titleText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Siga a trilha interativa e construa seu perfil profissional.',
            style: GoogleFonts.inter(
                fontSize: 16, color: StageColors.bodyGray, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                widget.onFinish();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: StageColors.brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                'Começar agora',
                style: GoogleFonts.inter(
                    fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
