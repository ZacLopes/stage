import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:io';

import '../../core/constants/stage_colors.dart';
import '../auth/user_viewmodel.dart';
import 'ai_score_screen.dart';

class AppGuideScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const AppGuideScreen({super.key, required this.onFinish});

  @override
  State<AppGuideScreen> createState() => _AppGuideScreenState();
}

class _AppGuideScreenState extends State<AppGuideScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isProcessingPdf = false;

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutQuart,
      );
    }
  }

  Future<void> _handlePdfUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.isEmpty || result.files.single.path == null) {
        // Mock for simulator
        _showError('Nenhum arquivo selecionado. Usando currículo de teste.');
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(
            builder: (_) => AIScoreScreen(
              resumeText: 'Texto extraído do PDF de teste...', 
              onFinish: widget.onFinish,
            )
          )
        );
        return;
      }

      setState(() => _isProcessingPdf = true);
      
      final File pdfFile = File(result.files.single.path!);
      final bytes = await pdfFile.readAsBytes();
      
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final String text = PdfTextExtractor(document).extractText();
      document.dispose();

      setState(() => _isProcessingPdf = false);

      if (text.trim().isEmpty) {
        _showError('Não conseguimos ler o texto do seu PDF.');
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(
          builder: (_) => AIScoreScreen(
            resumeText: text, 
            pdfBytes: bytes,
            onFinish: widget.onFinish,
          )
        )
      );
    } catch (e) {
      setState(() => _isProcessingPdf = false);
      _showError('Erro ao processar PDF: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        backgroundColor: StageColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
                  description: 'Siga a trilha interativa e construa sua carreira passo a passo.',
                  imagePath: 'assets/images/onboarding_1.png', // Fallback to icon if missing
                  icon: Icons.map_rounded,
                  color: StageColors.brandBlue,
                ),
                _buildSlide(
                  title: 'Perfil Mágico',
                  description: 'Nossa IA transforma suas conquistas em um currículo profissional em segundos.',
                  imagePath: 'assets/images/onboarding_2.png',
                  icon: Icons.auto_awesome,
                  color: const Color(0xFFF59E0B),
                ),
                _buildFinalChoiceSlide(),
              ],
            ),
            
            // Progress indicators
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
                            color: _currentPage == index ? StageColors.brandBlue : Colors.grey.withOpacity(0.2),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('PRÓXIMO', style: GoogleFonts.inter(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Loading Overlay
            if (_isProcessingPdf)
              Container(
                color: Colors.white.withOpacity(0.9),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: StageColors.brandBlue, strokeWidth: 3),
                      const SizedBox(height: 24),
                      Text('Analisando seu currículo...', 
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: StageColors.titleText)),
                    ],
                  ),
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
    required String imagePath,
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
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: StageColors.titleText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: GoogleFonts.inter(fontSize: 18, color: StageColors.bodyGray, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFinalChoiceSlide() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: StageColors.brandCyan.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.rocket_launch_rounded, size: 48, color: StageColors.brandCyan),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Quase lá!',
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: StageColors.titleText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Escolha como você deseja iniciar sua jornada profissional.',
            style: GoogleFonts.inter(fontSize: 16, color: StageColors.bodyGray),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),

          _ChoiceCard(
            title: 'Analisar meu Currículo',
            description: 'Nossa IA avalia seu currículo atual e indica o que você pode melhorar.',
            icon: Icons.document_scanner_rounded,
            color: const Color(0xFF6366F1),
            onTap: _handlePdfUpload,
            tag: 'RECOMENDADO',
          ),
          
          const SizedBox(height: 16),

          _ChoiceCard(
            title: 'Começar do zero',
            description: 'Siga a trilha interativa e construa seu perfil passo a passo jogando.',
            icon: Icons.videogame_asset_rounded,
            color: StageColors.brandBlue,
            onTap: () {
              widget.onFinish();
              Navigator.of(context).pop();
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? tag;

  const _ChoiceCard({
    required this.title, 
    required this.description, 
    required this.icon, 
    required this.color, 
    required this.onTap, 
    this.tag
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: tag != null ? color : Colors.grey.withOpacity(0.15), width: tag != null ? 2 : 1),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tag != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                        child: Text(tag!, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: StageColors.titleText)),
                    const SizedBox(height: 4),
                    Text(description, style: GoogleFonts.inter(fontSize: 14, color: StageColors.bodyGray, height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
