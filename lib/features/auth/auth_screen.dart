import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/stage_colors.dart';
import '../../core/utils/auth_error_formatter.dart';
import '../home/home_screen.dart';
import 'user_viewmodel.dart';
import 'email_signup_screen.dart';
// Note: We'll see profile setup and completion screen navigation from here or signUp

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
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

  void _onAuthChanged() {
    if (!mounted) return;
    
    final vm = context.read<UserViewModel>();
    if (vm.isLoggedIn && !vm.isLoading) {
      // Force kill the web browser sheet immediately.
      // This is the silver bullet for SafariViewController getting stuck.
      try {
        closeInAppWebView();
      } catch (_) {}

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
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

  void _navigateToEmailSignup() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, anim, secAnim) => const EmailSignupScreen(),
        transitionsBuilder: (context, anim, secAnim, child) {
          final slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
          return SlideTransition(position: slide, child: child);
        },
      ),
    );
  }

  void _showLoginSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _LoginBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        'Vamos começar!',
                        style: GoogleFonts.outfit(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: StageColors.titleText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Crie sua conta em segundos.',
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
                      // Google
                      _SocialButton(
                        icon: Icons.g_mobiledata_rounded,
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
        
                      // Email
                      _SocialButton(
                        icon: Icons.email_outlined,
                        text: 'Criar conta com e-mail',
                        textColor: StageColors.brandBlue,
                        backgroundColor: Colors.transparent,
                        borderColor: StageColors.brandBlue,
                        onPressed: _navigateToEmailSignup,
                      ),
                      
                      const SizedBox(height: 32),
        
                      // Login Link
                      GestureDetector(
                        onTap: _showLoginSheet,
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(
                              color: StageColors.bodyGray,
                              fontSize: 15,
                            ),
                            children: const [
                              TextSpan(text: 'Já tem uma conta? '),
                              TextSpan(
                                text: 'Entrar',
                                style: TextStyle(
                                  color: StageColors.brandBlue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
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
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onPressed;

  const _SocialButton({
    required this.icon,
    required this.text,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onPressed,
  });

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
                Icon(icon, color: textColor, size: 28),
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

// ==========================================
// LOGIN BOTTOM SHEET
// ==========================================
class _LoginBottomSheet extends StatefulWidget {
  const _LoginBottomSheet();

  @override
  State<_LoginBottomSheet> createState() => _LoginBottomSheetState();
}

class _LoginBottomSheetState extends State<_LoginBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    
    final vm = context.read<UserViewModel>();
    try {
      setState(() => _errorMessage = null);
      
      await vm.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        if (vm.isLoggedIn) {
          // Send them to home screen (existing accounts skip profile setup)
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AuthErrorFormatter.format(e);
        });
        
        // Also keep the snackbar as a backup/standard feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: StageColors.error,
            content: Text(_errorMessage!),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<UserViewModel>().isLoading;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Entrar',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: StageColors.titleText,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'E-mail',
                    hintText: 'seu@email.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  validator: (val) => val != null && val.contains('@') ? null : 'E-mail inválido',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  validator: (val) => val != null && val.isNotEmpty ? null : 'Insira a senha',
                ),
              ],
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: StageColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StageColors.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: StageColors.error, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(
                        color: StageColors.error,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: StageColors.ctaGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: isLoading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : Text('Entrar', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
