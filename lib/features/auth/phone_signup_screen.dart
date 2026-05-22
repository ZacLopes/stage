// PhoneSignupScreen — substitui EmailSignupScreen no fluxo principal.
//
// Twilio/SMS OTP ainda não configurado. Solução interina: usuário digita
// telefone, mas por baixo dos panos sintetizamos um email determinístico
// ('phone_{e164_digits}@stage.app') e usamos o fluxo email+senha do
// Supabase Auth. Quando Twilio for habilitado, basta trocar a chamada
// pra `signUp(phone: ...)` nativo do Supabase, sem mexer na UI.
//
// O telefone real fica salvo em user_metadata.phone + em profile_personal
// (via fluxo de onboarding). O email sintético nunca é exibido pro usuário.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../core/constants/stage_colors.dart';
import '../../core/utils/auth_error_formatter.dart';
import '../../core/utils/brazil_phone_formatter.dart';
import '../../core/widgets/pii_mask.dart';
import '../../services/analytics_service.dart';
import '../splash/splash_screen.dart' show AuthGate;
import 'phone_auth_helpers.dart';
import 'user_viewmodel.dart';

class PhoneSignupScreen extends StatefulWidget {
  const PhoneSignupScreen({super.key});

  @override
  State<PhoneSignupScreen> createState() => _PhoneSignupScreenState();
}

class _PhoneSignupScreenState extends State<PhoneSignupScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'auth_phone_signup';

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  String _countryCode = '+55';

  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    Analytics.shared.onboardingStepReached(step: 2, stepId: 'auth_phone_signup');
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  int get _phoneDigitsCount =>
      _phoneController.text.replaceAll(RegExp(r'\D'), '').length;

  bool get _isFormValid {
    return _phoneDigitsCount >= 8 &&
        _passwordController.text.length >= 8;
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    final vm = context.read<UserViewModel>();
    final syntheticEmail = PhoneAuthHelpers.syntheticEmail(
      countryCode: _countryCode,
      phone: _phoneController.text,
    );

    try {
      setState(() => _errorMessage = null);
      HapticFeedback.lightImpact();

      await vm.signUp(
        email: syntheticEmail,
        password: _passwordController.text,
        // Nome real coletado depois (first_name + last_name nas masking
        // questions). Placeholder vazio aqui — UserViewModel.signUp aceita.
        name: '',
        age: 18,
      );

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = AuthErrorFormatter.format(e));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: StageColors.error, content: Text(_errorMessage!)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<UserViewModel>().isLoading;

    return PiiMask(
      child: Scaffold(
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
            'Continuar com telefone',
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
                          'Continuar com telefone',
                          style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: StageColors.titleText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Entre ou crie sua conta com seu número.',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: StageColors.subtitleGray,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Telefone (country code + número)
                        Row(
                          children: [
                            SizedBox(
                              width: 124,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _countryCode,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 20),
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
                                    borderSide: const BorderSide(
                                        color: StageColors.brandBlue, width: 2),
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: '+55', child: Text('🇧🇷 +55', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(
                                      value: '+1', child: Text('🇺🇸 +1', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(
                                      value: '+351', child: Text('🇵🇹 +351', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(
                                      value: '+44', child: Text('🇬🇧 +44', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) => setState(() {
                                  _countryCode = v ?? '+55';
                                  _phoneController.clear();
                                }),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildTextField(
                                controller: _phoneController,
                                label: 'Telefone',
                                icon: Icons.phone_iphone_outlined,
                                keyboardType: TextInputType.phone,
                                inputFormatters: _countryCode == '+55'
                                    ? [BrazilPhoneFormatter()]
                                    : [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(15),
                                      ],
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => setState(() {}),
                                validator: (_) => _phoneDigitsCount >= 8
                                    ? null
                                    : 'Insira um telefone válido',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Senha
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Senha',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setState(() {}),
                          validator: (val) => val != null && val.length >= 8
                              ? null
                              : 'A senha precisa ter no mínimo 8 caracteres',
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: StageColors.hintGray),
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
                      ],
                    ),
                  ),
                ),

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

                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
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
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                : Text(
                                    'Continuar',
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.inter(
                        color: StageColors.subtitleGray,
                        fontSize: 12,
                        height: 1.4,
                      ),
                      children: const [
                        TextSpan(text: 'Ao continuar, você concorda com os '),
                        TextSpan(
                          text: 'Termos de Uso',
                          style: TextStyle(
                            color: StageColors.brandBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: ' e '),
                        TextSpan(
                          text: 'Política de Privacidade',
                          style: TextStyle(
                            color: StageColors.brandBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
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

