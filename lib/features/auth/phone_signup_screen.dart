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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/stage_legal_links.dart';
import '../../core/utils/open_legal_link.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/auth_error_formatter.dart';
import '../../core/utils/brazil_phone_formatter.dart';
import '../../core/widgets/country_code_field.dart';
import '../../core/widgets/pii_mask.dart';
import '../../services/analytics_service.dart';
import '../splash/splash_screen.dart' show AuthGate;
import 'password_rule.dart';
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
  /// DDI selecionado. Antes era caixa de texto livre; virou o MESMO seletor
  /// com bandeira que o onboarding usa duas telas depois (revisão UX 28/07,
  /// achado P3-42) — ver `CountryCodeField`.
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
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  /// Recognizers dos links legais. Precisam ser campos (não criados no build)
  /// pra poderem ser liberados no dispose.
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => openLegalLink(StageLegalLinks.termsUrl);
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => openLegalLink(StageLegalLinks.privacyUrl);

  int get _phoneDigitsCount =>
      _phoneController.text.replaceAll(RegExp(r'\D'), '').length;

  bool get _isFormValid {
    return _phoneDigitsCount >= 8 &&
        passwordRuleError(_passwordController.text) == null;
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

      // QA Dia 6 fix: emite auth_signup_started canônico ANTES do
      // sign-up real. Pareado com auth_signup_completed (listener no VM).
      // ignore: unawaited_futures
      Analytics.shared.authSignupStarted(method: 'phone');

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
        // Banner inline com animação cobre a comunicação do erro. SnackBar
        // sobreposto criava duplicação visual (2 mensagens iguais ao mesmo
        // tempo), removido.
        setState(() => _errorMessage = AuthErrorFormatter.format(e, identifier: AuthIdentifier.phone));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<UserViewModel>().isLoading;

    return PiiMask(
      child: Scaffold(
        backgroundColor: AppColors.surfaceVariant,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceVariant,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Continuar com telefone',
            style: TextStyle(fontFamily: 'Outfit', 
              color: AppColors.textPrimary,
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
                          style: TextStyle(fontFamily: 'Outfit', 
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Entre ou crie sua conta com seu número.',
                          style: TextStyle(fontFamily: 'Inter', 
                            fontSize: 16,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Telefone (DDI editável + número)
                        Row(
                          children: [
                            SizedBox(
                              width: 130,
                              child: CountryCodeField(
                                value: _countryCode,
                                decoration: InputDecoration(
                                  labelText: 'DDI',
                                  labelStyle: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.brandBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                        color: AppColors.borderStrong),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                        color: AppColors.borderStrong),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(
                                        color: AppColors.brandBlue, width: 2),
                                  ),
                                ),
                                onChanged: (v) => setState(() {
                                  _countryCode = v;
                                  // Limpa o número quando o DDI muda — máscara
                                  // BR só vale pra +55, e outros países podem
                                  // ter formatos incompatíveis com o que já
                                  // estava digitado.
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
                          // Limpa o banner de erro assim que a pessoa começa a
                          // corrigir. Antes ele só sumia no próximo toque em
                          // "Continuar" — ela editava a senha com a mensagem de
                          // falha ainda na tela, o que faz parecer que nada
                          // mudou. O comentário do AnimatedSwitcher abaixo já
                          // afirmava que isso acontecia; não acontecia.
                          onChanged: (_) => setState(() => _errorMessage = null),
                          validator: (val) => passwordRuleError(val ?? ''),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: AppColors.textDisabled),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 12),
                          // Deriva da MESMA regra que valida. Eram duas
                          // strings independentes: o validador checava uma
                          // coisa e o texto anunciava outra.
                          child: Text(
                            kPasswordRuleHint,
                            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textDisabled),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // AnimatedSwitcher faz o banner entrar com fade + expansão
                // vertical (sizeFactor com axisAlignment -1 cresce de cima
                // pra baixo). Quando _errorMessage volta a null (ex: user
                // edita a senha pra tentar de novo), some com a mesma curva.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        axisAlignment: -1,
                        child: child,
                      ),
                    );
                  },
                  child: _errorMessage == null
                      ? const SizedBox.shrink(key: ValueKey('error-empty'))
                      : Padding(
                          key: const ValueKey('error-banner'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.error.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: AppColors.error, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.error,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                        color: _isFormValid ? AppColors.primary : AppColors.borderStrong,
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
                                    style: TextStyle(fontFamily: 'Outfit', 
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _isFormValid ? Colors.white : AppColors.textTertiary,
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
                      style: TextStyle(fontFamily: 'Inter', 
                        color: AppColors.textTertiary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                      // Estes dois eram TextSpan SEM `recognizer`: azuis,
                      // negrito, com toda a cara de link — e não abriam nada.
                      children: [
                        const TextSpan(
                            text: 'Ao continuar, você concorda com os '),
                        TextSpan(
                          text: 'Termos de Uso',
                          style: const TextStyle(
                            color: AppColors.brandBlue,
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: _termsTap,
                        ),
                        const TextSpan(text: ' e '),
                        TextSpan(
                          text: 'Política de Privacidade',
                          style: const TextStyle(
                            color: AppColors.brandBlue,
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: _privacyTap,
                        ),
                        const TextSpan(text: '.'),
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
      style: TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontFamily: 'Inter', color: AppColors.textTertiary),
        floatingLabelStyle: TextStyle(fontFamily: 'Inter', color: AppColors.brandBlue, fontWeight: FontWeight.bold),
        prefixIcon: Icon(icon, color: AppColors.textDisabled),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}

