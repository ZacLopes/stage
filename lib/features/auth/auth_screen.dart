import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../core/constants/stage_colors.dart';
import '../../core/utils/auth_error_formatter.dart';
import '../splash/splash_screen.dart' show AuthGate;
import 'phone_signup_screen.dart';
import 'user_viewmodel.dart';
import '../../core/widgets/pii_mask.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin, ScreenTrackingMixin {
  @override
  String get screenName => 'auth';

  late AnimationController _animController;
  late Animation<double> _fadeHeader;
  late Animation<Offset> _slideBtns;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeHeader = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _slideBtns = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic)),
    );

    _animController.forward();

    // Listen for auth changes to navigate to Home automatically
    // This is crucial for OAuth/Deep Linking success
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserViewModel>().addListener(_onAuthChanged);
    });
  }

  /// Bandeira pra evitar que o listener dispare múltiplas navegações
  /// — uma vez disparado e a navegação iniciada, nunca mais age.
  bool _navigated = false;

  void _onAuthChanged() {
    if (!mounted || _navigated) return;

    // CRÍTICO: só age se a AuthScreen ainda for a rota do topo. Sem essa
    // checagem, qualquer notifyListeners do UserViewModel disparado por
    // telas pushadas em cima da AuthScreen (EmailSignup, ProfileSetup,
    // CompletionScreen, AIScoreScreen, etc) fazia esta tela navegar por
    // baixo e quebrar o fluxo do usuário (provocava "ciclo infinito"
    // quando o usuário clicava "Aplicar com este currículo").
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;

    final vm = context.read<UserViewModel>();
    if (vm.isLoggedIn && !vm.isLoading) {
      _navigated = true;

      // Mata o sheet do navegador (OAuth pode prendê-lo aberto)
      try {
        closeInAppWebView();
      } catch (_) {}

      // Roteamento delegado pro AuthGate, que decide entre NameInputScreen /
      // CompletionScreen / HomeScreen baseado em needsName + hasCampaign.
      // Empurrar telas específicas daqui causava GlobalKey duplicada
      // (auth_screen pushava HomeScreen enquanto o AuthGate Consumer
      // também montava uma — duas BottomNavigationBars na árvore).
      // O caminho de email/senha NÃO usa esse listener — EmailSignup já
      // navega manualmente pra ProfileSetupScreen após o signUp.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    // Avoid memory leaks and late listeners
    // We use context.read with a try-catch because the provider might be already disposed
    try {
      if (mounted) {
        context.read<UserViewModel>().removeListener(_onAuthChanged);
      }
    } catch (_) {}
    _animController.dispose();
    super.dispose();
  }

  void _showPlaceholder(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Login com $provider em breve!')),
    );
  }

  void _navigateToPhoneSignup() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, anim, secAnim) => const PhoneSignupScreen(),
        transitionsBuilder: (context, anim, secAnim, child) {
          final slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
          return SlideTransition(position: slide, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PiiMask(child: Scaffold(
      backgroundColor: StageColors.offWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) => Opacity(
                    opacity: _fadeHeader.value,
                    child: child,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 32),
                      // Compact logo
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: StageColors.brandGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: StageColors.brandBlue.withOpacity(0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/images/image copy.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Vamos lá!',
                        style: GoogleFonts.outfit(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: StageColors.titleText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sua jornada começa em segundos.',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: StageColors.subtitleGray,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
        
                const SizedBox(height: 64), // Replaced Spacer with fixed spacing for scrolling
        
                // Buttons
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) => Opacity(
                    opacity: _fadeHeader.value,
                    child: SlideTransition(
                      position: _slideBtns,
                      child: child,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Google — logo oficial colorida (4 cores) via SVG
                      _SocialButton(
                        leadingWidget: SvgPicture.asset(
                          'assets/icons/google.svg',
                          width: 22,
                          height: 22,
                        ),
                        text: 'Continuar com Google',
                        textColor: StageColors.darkText,
                        backgroundColor: Colors.white,
                        borderColor: StageColors.chipBorder,
                        onPressed: () async {
                          try {
                            await context.read<UserViewModel>().signInWithOAuth(OAuthProvider.google);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: StageColors.error,
                                  content: Text(AuthErrorFormatter.format(e)),
                                ),
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Apple
                      _SocialButton(
                        icon: Icons.apple,
                        text: 'Continuar com Apple',
                        textColor: Colors.white,
                        backgroundColor: Colors.black,
                        borderColor: Colors.black,
                        onPressed: () async {
                          try {
                            await context.read<UserViewModel>().signInWithApple();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: StageColors.error,
                                  content: Text(AuthErrorFormatter.format(e)),
                                ),
                              );
                            }
                          }
                        },
                      ),
                      
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey[300])),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'ou',
                              style: GoogleFonts.inter(
                                color: StageColors.subtitleGray,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.grey[300])),
                        ],
                      ),
                      const SizedBox(height: 24),
        
                      // Telefone (substitui email — Twilio/OTP ainda não
                      // configurado, conta usa email sintético internamente).
                      _SocialButton(
                        icon: Icons.phone_iphone_outlined,
                        text: 'Continuar com telefone',
                        textColor: StageColors.brandBlue,
                        backgroundColor: Colors.transparent,
                        borderColor: StageColors.brandBlue,
                        onPressed: _navigateToPhoneSignup,
                      ),
                      
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class _SocialButton extends StatelessWidget {
  /// Ícone do Material — usado pra Apple e Email (monocromáticos).
  /// Se [leadingWidget] for fornecido, ele substitui o `icon`.
  final IconData? icon;

  /// Widget customizado pro lugar do ícone — usado pro Google
  /// (logo colorida via SVG, não dá pra reproduzir com IconData).
  final Widget? leadingWidget;

  final String text;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onPressed;

  const _SocialButton({
    this.icon,
    this.leadingWidget,
    required this.text,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onPressed,
  }) : assert(icon != null || leadingWidget != null,
            'Pass icon (IconData) OR leadingWidget (Widget)');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 1.5),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: leadingWidget ?? Icon(icon, color: textColor, size: 28),
                  ),
                ),
                Expanded(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(width: 28), // Balance icon width
              ],
            ),
          ),
        ),
      ),
    );
  }
}

