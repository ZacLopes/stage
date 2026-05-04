import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/constants/stage_colors.dart';
import '../../services/pdf_text_extractor.dart';
import '../../services/tutorial_service.dart';
import '../home/ai_score_screen.dart';
import '../home/home_viewmodel.dart';
import '../auth/user_viewmodel.dart';
import 'target_job_screen.dart';

class CompletionScreen extends StatefulWidget {
  const CompletionScreen({super.key});

  @override
  State<CompletionScreen> createState() => _CompletionScreenState();
}

class _CompletionScreenState extends State<CompletionScreen>
    with TickerProviderStateMixin {
  late AnimationController _appearController;
  late Animation<double> _fadeHeader;
  late Animation<Offset> _slideCard1;
  late Animation<Offset> _slideCard2;

  bool _isPickingFile = false;

  @override
  void initState() {
    super.initState();
    _appearController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));

    _fadeHeader = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _appearController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut)));
    _slideCard1 = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _appearController,
            curve: const Interval(0.2, 0.7, curve: Curves.easeOutCubic)));
    _slideCard2 = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _appearController,
            curve: const Interval(0.4, 0.9, curve: Curves.easeOutCubic)));

    _appearController.forward();
  }

  @override
  void dispose() {
    _appearController.dispose();
    super.dispose();
  }

  /// Caminho B: usuário quer construir o CV pela trilha. Cria a campaign
  /// pedindo o cargo-alvo, depois cai na Trilha.
  Future<void> _startTrackPath() async {
    await TutorialService().markAsSeen();
    if (!mounted) return;

    context.read<HomeViewModel>().requestTabChange(1);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TargetJobScreen()),
      (route) => false,
    );
  }

  /// Caminho A: usuário já tem CV pronto.
  /// Fluxo: pickFile → extrai texto → TargetJobScreen → AIScoreScreen contextualizado.
  Future<void> _uploadResumePath() async {
    setState(() => _isPickingFile = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _isPickingFile = false);
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;

      if (bytes == null) {
        _showError('Não foi possível ler o arquivo. Tente novamente.');
        if (mounted) setState(() => _isPickingFile = false);
        return;
      }

      // Extrai texto do PDF
      String resumeText;
      try {
        resumeText = ResumePdfExtractor.extract(bytes);
      } catch (e) {
        _showError('Não foi possível ler este PDF. Verifique se ele não está protegido.');
        if (mounted) setState(() => _isPickingFile = false);
        return;
      }

      if (!ResumePdfExtractor.isUsable(resumeText)) {
        _showError(
          'O PDF parece ser uma imagem (sem texto). Exporte seu currículo como PDF de texto e tente novamente.',
        );
        if (mounted) setState(() => _isPickingFile = false);
        return;
      }

      if (!mounted) return;
      setState(() => _isPickingFile = false);

      await TutorialService().markAsSeen();
      if (!mounted) return;

      // Próximo passo: pedir vaga-alvo, depois ir pra análise contextualizada.
      // A AIScoreScreen é responsável pela navegação final pra Home (com
      // seu próprio context, evitando o bug de callbacks chamados em telas
      // já desmontadas pelo pushReplacement).
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TargetJobScreen(
            contextHeadline: 'CV recebido • Vamos contextualizar',
            onContinue: (jobTitle, sourceUrl) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => AIScoreScreen(
                    resumeText: resumeText,
                    pdfBytes: bytes,
                    targetJobTitle: jobTitle.isEmpty ? null : jobTitle,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      _showError('Erro inesperado ao selecionar o arquivo: $e');
      if (mounted) setState(() => _isPickingFile = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: StageColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName = context.read<UserViewModel>().user?.name ?? 'Pronto';
    final firstName = userName.split(' ').first;

    return Scaffold(
      backgroundColor: StageColors.offWhite,
      body: SafeArea(
        child: _isPickingFile
            ? _PickingLoader()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 48),
                    AnimatedBuilder(
                      animation: _fadeHeader,
                      builder: (context, child) =>
                          Opacity(opacity: _fadeHeader.value, child: child),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: StageColors.ctaGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Perfil Criado! 🎉',
                              style: GoogleFonts.inter(
                                color: StageColors.ctaGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Como você quer\ncomeçar, $firstName?',
                            style: GoogleFonts.outfit(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: StageColors.titleText,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Escolha um caminho para começar a aplicar para vagas.',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: StageColors.subtitleGray,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    AnimatedBuilder(
                      animation: _slideCard1,
                      builder: (context, child) => Opacity(
                        opacity: _fadeHeader.value,
                        child: SlideTransition(
                            position: _slideCard1, child: child),
                      ),
                      child: _PathCard(
                        title: 'Já tenho um currículo',
                        subtitle:
                            'Envie seu PDF — analisamos contra a vaga que você quer e você já pode aplicar.',
                        icon: Icons.document_scanner_rounded,
                        color: StageColors.brandBlue,
                        onTap: _uploadResumePath,
                        isPrimary: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedBuilder(
                      animation: _slideCard2,
                      builder: (context, child) => Opacity(
                        opacity: _fadeHeader.value,
                        child: SlideTransition(
                            position: _slideCard2, child: child),
                      ),
                      child: _PathCard(
                        title: 'Começar do zero',
                        subtitle:
                            'Vamos construir seu currículo passo a passo na trilha interativa.',
                        icon: Icons.auto_awesome_rounded,
                        color: StageColors.ctaGreen,
                        onTap: _startTrackPath,
                        isPrimary: false,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PickingLoader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: StageColors.brandCyan),
          const SizedBox(height: 16),
          Text(
            'Processando seu currículo...',
            style: GoogleFonts.inter(
              color: StageColors.subtitleGray,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isPrimary;

  const _PathCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: isPrimary ? color.withOpacity(0.3) : Colors.grey[200]!,
              width: isPrimary ? 2 : 1),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: StageColors.titleText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: StageColors.bodyGray,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.grey[300], size: 16),
          ],
        ),
      ),
    );
  }
}
