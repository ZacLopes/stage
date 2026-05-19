import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../core/constants/stage_colors.dart';
import '../../core/utils/auth_error_formatter.dart';
import '../../services/analytics_service.dart';
import '../splash/splash_screen.dart' show AuthGate;
import 'user_viewmodel.dart';
import '../../core/widgets/pii_mask.dart';

class EmailSignupScreen extends StatefulWidget {
  const EmailSignupScreen({super.key});

  @override
  State<EmailSignupScreen> createState() => _EmailSignupScreenState();
}

class _EmailSignupScreenState extends State<EmailSignupScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'auth_email_signup';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _acceptedTerms = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    Analytics.shared.onboardingStepReached(step: 2, stepId: 'auth_email_signup');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    return _nameController.text.trim().isNotEmpty &&
           _emailController.text.trim().isNotEmpty &&
           _passwordController.text.isNotEmpty &&
           _acceptedTerms;
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate() || !_acceptedTerms) return;

    final vm = context.read<UserViewModel>();
    
    try {
      setState(() => _errorMessage = null);
      
      // In a real flow, you'll call signUp here.
      // Since age is required by the existing ViewModel but we collect it in the next step,
      // we pass a placeholder (18) and update it for real in ProfileSetupScreen.
      await vm.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        age: 18, // Placeholder until Step 1 of ProfileSetup
      );

      if (mounted) {
        // Empurra AuthGate (não ProfileSetup direto): o Consumer central
        // detecta needsProfileSetup=true e renderiza ProfileSetup. Quando o
        // user salva, o mesmo Consumer rebuilda pra CompletionScreen.
        // Empurrar ProfileSetup direto + Consumer rebuild causava duplicata
        // de GlobalKey (tutorial.jobsTab da BottomNav).
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AuthErrorFormatter.format(e);
        });
        
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

    return PiiMask(child: Scaffold(
      backgroundColor: StageColors.offWhite,
      appBar: AppBar(
        backgroundColor: StageColors.offWhite,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: StageColors.darkText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Criar Conta',
          style: GoogleFonts.outfit(
            color: StageColors.titleText,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Vamos começar!',
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: StageColors.titleText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Preencha seus dados para criar sua conta.',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: StageColors.subtitleGray,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Name Field
                      _buildTextField(
                        controller: _nameController,
                        label: 'Nome Completo',
                        icon: Icons.person_outline,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}), // To evaluate _isFormValid
                        validator: (val) => val != null && val.trim().contains(' ') 
                          ? null : 'Insira seu nome e sobrenome',
                      ),
                      const SizedBox(height: 20),

                      // Email Field
                      _buildTextField(
                        controller: _emailController,
                        label: 'E-mail',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        validator: (val) => val != null && val.contains('@') 
                          ? null : 'Insira um e-mail válido',
                      ),
                      const SizedBox(height: 20),

                      // Password Field
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Senha',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        validator: (val) => val != null && val.length >= 8 
                          ? null : 'A senha precisa ter no mínimo 8 caracteres',
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: StageColors.hintGray),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 12),
                        child: Text(
                          'Mínimo 8 caracteres, uma letra e um número',
                          style: GoogleFonts.inter(fontSize: 12, color: StageColors.hintGray),
                        ),
                      ),
                      
                      const SizedBox(height: 32),

                      // Terms
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            activeColor: StageColors.brandBlue,
                            onChanged: (val) => setState(() => _acceptedTerms = val ?? false),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: RichText(
                                text: TextSpan(
                                  style: GoogleFonts.inter(color: StageColors.bodyGray, fontSize: 13, height: 1.4),
                                  children: const [
                                    TextSpan(text: 'Li e aceito os '),
                                    TextSpan(
                                      text: 'Termos de Uso',
                                      style: TextStyle(color: StageColors.brandBlue, fontWeight: FontWeight.bold),
                                    ),
                                    TextSpan(text: ' e '),
                                    TextSpan(
                                      text: 'Política de Privacidade',
                                      style: TextStyle(color: StageColors.brandBlue, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Error Message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Container(
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
                ),

              // Bottom Button
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: _isFormValid ? StageColors.ctaGreen : Colors.grey[300],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: (_isFormValid && !isLoading) ? _handleSignup : null,
                        borderRadius: BorderRadius.circular(16),
                        child: Center(
                          child: isLoading
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                            : Text(
                                'Criar Conta',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _isFormValid ? Colors.white : Colors.grey[500],
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      onChanged: onChanged,
      style: GoogleFonts.inter(color: StageColors.darkText, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: StageColors.subtitleGray),
        floatingLabelStyle: GoogleFonts.inter(color: StageColors.brandBlue, fontWeight: FontWeight.bold),
        prefixIcon: Icon(icon, color: StageColors.hintGray),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: StageColors.chipBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: StageColors.chipBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: StageColors.brandBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: StageColors.error),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
