// ChangePasswordScreen — única responsabilidade: trocar a senha do usuário.
//
// Fluxo:
//   1. User digita senha ATUAL + NOVA + CONFIRMA NOVA
//   2. Checklist visual mostra requisitos (8+ chars, 1 letra, 1 número)
//   3. Botão habilita só com checklist completo + match de confirm
//   4. Submit chama `UserViewModel.changePassword` que:
//      a. Re-autentica via signInWithPassword (valida senha atual)
//      b. Chama auth.updateUser pra trocar
//   5. Erros vêm como PasswordChangeException tipada — traduz pra PT
//
// Os outros dados pessoais (nome, idade, email, telefone) são editados na
// aba Perfil > sub-aba Informações.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import '../auth/user_viewmodel.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/safe_error_text.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'settings_change_password';

  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  // Live state dos requisitos. Atualizado a cada onChanged do campo "Nova
  // senha" pra alimentar o checklist visual.
  bool _reqMinLength = false;
  bool _reqHasLetter = false;
  bool _reqHasNumber = false;

  // Erro do server (senha atual incorreta etc) — separado do form
  // validator porque vem após submit e some no próximo digitar.
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(_updateRequirements);
  }

  @override
  void dispose() {
    _newPasswordController.removeListener(_updateRequirements);
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _updateRequirements() {
    final v = _newPasswordController.text;
    final next = (
      minLength: v.length >= 8,
      hasLetter: RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(v),
      hasNumber: RegExp(r'[0-9]').hasMatch(v),
    );
    if (next.minLength == _reqMinLength &&
        next.hasLetter == _reqHasLetter &&
        next.hasNumber == _reqHasNumber) {
      return;
    }
    setState(() {
      _reqMinLength = next.minLength;
      _reqHasLetter = next.hasLetter;
      _reqHasNumber = next.hasNumber;
    });
  }

  bool get _allRequirementsMet =>
      _reqMinLength && _reqHasLetter && _reqHasNumber;

  String? _validateCurrent(String? v) {
    if (v == null || v.isEmpty) return 'Digite sua senha atual';
    return null;
  }

  String? _validateNew(String? v) {
    if (v == null || v.isEmpty) return 'Digite uma nova senha';
    if (!_allRequirementsMet) return 'A senha não atende os requisitos';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Confirme a nova senha';
    if (v != _newPasswordController.text) return 'As senhas não conferem';
    return null;
  }

  /// Traduz `PasswordChangeException.code` pra mensagem PT-BR. Tabela
  /// centralizada — fácil ajustar redação sem mexer no ViewModel.
  String _messageForCode(String code) {
    switch (code) {
      case 'wrong_password':
        return 'Senha atual incorreta. Tente de novo.';
      case 'no_email':
        return 'Conta sem email associado — entre em contato com o suporte.';
      case 'weak_password':
        return 'Senha muito fraca. Use letras e números.';
      case 'same_password':
        return 'A nova senha precisa ser diferente da atual.';
      case 'network':
        return 'Falha de conexão. Verifique sua internet.';
      default:
        return 'Erro ao trocar a senha. Tente novamente.';
    }
  }

  Future<void> _save() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      await context.read<UserViewModel>().changePassword(
            currentPassword: _currentPasswordController.text,
            newPassword: _newPasswordController.text,
          );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Senha atualizada com sucesso!'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } on PasswordChangeException catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = _messageForCode(e.code);
        // Senha atual errada → limpa só esse campo pra forçar redigitar.
        if (e.code == 'wrong_password') {
          _currentPasswordController.clear();
        }
      });
    } catch (e) {
      if (!mounted) return;
      // Era `'Erro inesperado: $e'` — interpolação crua de exceção direto na
      // tela, a mesma classe de vazamento que o `SafeErrorText` foi criado
      // para fechar (o device-test de 24/07 chegou a ver a URL do projeto
      // Supabase na UI), reaberta em outro arquivo.
      setState(() => _serverError = SafeErrorText.orFallback(
            e,
            'Não consegui trocar a senha agora. Tente de novo em instantes.',
          ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Trocar senha',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _passwordField(
                      controller: _currentPasswordController,
                      label: 'Senha atual',
                      obscure: _obscureCurrent,
                      onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
                      validator: _validateCurrent,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    _passwordField(
                      controller: _newPasswordController,
                      label: 'Nova senha',
                      obscure: _obscureNew,
                      onToggle: () => setState(() => _obscureNew = !_obscureNew),
                      validator: _validateNew,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    _RequirementsChecklist(
                      hasMinLength: _reqMinLength,
                      hasLetter: _reqHasLetter,
                      hasNumber: _reqHasNumber,
                    ),
                    const SizedBox(height: 16),
                    _passwordField(
                      controller: _confirmPasswordController,
                      label: 'Confirme a nova senha',
                      obscure: _obscureConfirm,
                      onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      validator: _validateConfirm,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                    ),
                  ],
                ),
              ),
              if (_serverError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _serverError!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (_isLoading || !_allRequirementsMet) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.borderStrong,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'SALVAR NOVA SENHA',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textTertiary),
        prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textTertiary),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.textTertiary,
          ),
          onPressed: onToggle,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.success, width: 2),
        ),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

/// Checklist visual dos requisitos da senha nova. Cada item fica
/// verde quando satisfeito; cinza quando não. Atualiza em tempo real
/// conforme o user digita — feedback imediato evita "submit, falha,
/// volta, lê erro, tenta de novo".
class _RequirementsChecklist extends StatelessWidget {
  final bool hasMinLength;
  final bool hasLetter;
  final bool hasNumber;

  const _RequirementsChecklist({
    required this.hasMinLength,
    required this.hasLetter,
    required this.hasNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _item('Pelo menos 8 caracteres', hasMinLength),
        _item('Inclui letra', hasLetter),
        _item('Inclui número', hasNumber),
      ],
    );
  }

  Widget _item(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 16,
            color: met ? AppColors.success : AppColors.borderStrong,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: met ? AppColors.success : AppColors.textTertiary,
              fontWeight: met ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
