import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../core/constants/stage_colors.dart';
import '../../services/analytics_service.dart';
import '../../services/cv_import_service.dart';
import '../home/home_viewmodel.dart';
import '../auth/user_viewmodel.dart';
import '../onboarding/presentation/two_doors_screen.dart';

/// Pós-cadastro: usuário escolhe entre subir um CV pronto (vai pra biblioteca,
/// sem análise) ou construir o CV pela trilha. Em ambos os caminhos a campaign
/// é criada como "skipped" — o target da vaga será coletado contextualmente
/// (na hora de adaptar CV pra uma vaga específica), não em onboarding.
class CompletionScreen extends StatefulWidget {
  const CompletionScreen({super.key});

  @override
  State<CompletionScreen> createState() => _CompletionScreenState();
}

class _CompletionScreenState extends State<CompletionScreen>
    with TickerProviderStateMixin, ScreenTrackingMixin {
  @override
  String get screenName => 'onboarding_completion';

  late AnimationController _appearController;
  late Animation<double> _fadeHeader;
  late Animation<Offset> _slideCard1;
  late Animation<Offset> _slideCard2;

  bool _isPickingFile = false;

  @override
  void initState() {
    super.initState();
    Analytics.shared.onboardingStepReached(step: 4, stepId: 'cv_upload_choice');

    // Profile-first (Semana 2): se feature flag `new_onboarding_enabled` está
    // on, redireciona pra TwoDoorsScreen (novo fluxo). Senão mantém CompletionScreen.
    // Check é async — feito em postFrame pra não bloquear o initial frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Garante identify ANTES de consultar flag (race condition em cold start)
      await Analytics.shared.identifyIfLoggedIn();
      // Força reload pra pegar valor mais recente do server (SDK tem cache local)
      try {
        await Posthog().reloadFeatureFlags();
      } catch (e) {
        debugPrint('[CompletionScreen] reloadFeatureFlags failed: $e');
      }
      final flag = await Analytics.shared.getFlag('new_onboarding_enabled');
      debugPrint('[CompletionScreen] new_onboarding_enabled = $flag');
      if (!mounted) return;
      if (flag == 'true') {
        // TwoDoorsScreen agora é standalone — tem fluxo trail próprio.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TwoDoorsScreen()),
        );
      }
    });

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

  /// Caminho A: usuário já tem CV pronto.
  /// Delega o pipeline (pick → save → extract + analytics) pro [CvImportService]
  /// — fonte única pra cv_import_started/succeeded/failed. Aqui só fazemos o
  /// pós-import (createCampaign skipped + onboardingCompleted).
  Future<void> _uploadResumePath() async {
    setState(() => _isPickingFile = true);

    final result = await CvImportService.pickAndImport(context);

    if (!result.success) {
      if (result.errorMessage != null) _showError(result.errorMessage!);
      if (mounted) setState(() => _isPickingFile = false);
      return;
    }

    if (!mounted) return;

    // Cria campaign sem target (skipped) — o cargo-alvo será coletado
    // contextualmente depois (na hora de adaptar CV pra uma vaga específica).
    // Sem isso o AuthGate continuaria roteando pra CompletionScreen porque
    // `hasCampaign` é o flag de "onboarding finalizado".
    try {
      await context.read<UserViewModel>().createCampaign(isSkipped: true);
    } catch (e) {
      debugPrint('createCampaign(skip) failed (non-blocking): $e');
    }

    if (!mounted) return;

    Analytics.shared.onboardingCompleted();
    // Não navega manualmente — o AuthGate (Consumer<UserViewModel>) detecta
    // hasCampaign=true (setado por createCampaign acima) e re-renderiza
    // pra HomeScreen automaticamente. Push manual aqui duplicava o AuthGate
    // na árvore → GlobalKey colisão (tutorial.jobsTab da BottomNav).
  }

  /// Caminho B: construir o CV pela trilha (dentro da aba Currículo).
  Future<void> _startTrackPath() async {
    if (!mounted) return;
    setState(() => _isPickingFile = true);

    try {
      await context.read<UserViewModel>().createCampaign(isSkipped: true);
    } catch (e) {
      debugPrint('createCampaign(skip) failed (non-blocking): $e');
    }

    if (!mounted) return;

    // Pede pra abrir na aba Currículo (que tem a trilha de construção).
    context.read<HomeViewModel>().requestTabChange(HomeTabs.resume);

    Analytics.shared.onboardingCompleted();
    // Não navega manualmente — Consumer<UserViewModel> em AuthGate detecta
    // hasCampaign=true e renderiza HomeScreen. Ver comentário em _uploadResumePath.
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
                            'Escolha um caminho pra começar a aplicar para vagas.',
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
                            'Suba seu PDF — fica salvo na sua biblioteca e você já parte pra aplicar pras vagas.',
                        icon: Icons.upload_file_rounded,
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
            'Salvando seu currículo...',
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
