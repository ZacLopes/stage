// AccountMigrationScreen — tela onde users LEGACY de email+senha vinculam
// uma identity OAuth (Apple/Google) à mesma conta. Aberta pelo banner em
// SettingsScreen quando `userVM.needsOAuthMigration == true`.
//
// Fluxo:
//   1. Tap "Vincular Apple/Google" → user_viewmodel.linkAppleIdentity()
//      ou linkGoogleIdentity()
//   2. Em sucesso: identity adicionada na mesma row de auth.users. Banner
//      some (porque needsOAuthMigration vira false). User pode continuar
//      logando com email/senha OU com o OAuth daqui em diante.
//   3. Em cancelamento: nada acontece, user volta pra mesma tela.
//   4. Em falha: snackbar vermelho.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import 'user_viewmodel.dart';

class AccountMigrationScreen extends StatefulWidget {
  const AccountMigrationScreen({super.key});

  @override
  State<AccountMigrationScreen> createState() => _AccountMigrationScreenState();
}

class _AccountMigrationScreenState extends State<AccountMigrationScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'account_migration';

  bool _isLinkingApple = false;
  bool _isLinkingGoogle = false;

  Future<void> _linkApple() async {
    setState(() => _isLinkingApple = true);
    try {
      await context.read<UserViewModel>().linkAppleIdentity();
      if (!mounted) return;
      _showSuccess('Apple');
      Navigator.pop(context);
    } on OAuthLinkException catch (e) {
      // canceled = silent. Outros mostra snackbar.
      if (!mounted) return;
      if (e.code != 'canceled') _showError(e.code);
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLinkingApple = false);
    }
  }

  Future<void> _linkGoogle() async {
    setState(() => _isLinkingGoogle = true);
    try {
      await context.read<UserViewModel>().linkGoogleIdentity();
      // Google retorna via deeplink — não vamos receber o resultado aqui
      // de forma síncrona. O onAuthStateChange listener em UserViewModel
      // chama _loadUser quando userUpdated dispara, e o banner some.
      // Aqui só mantém o spinner; quando user voltar pro app após o
      // browser, a tela faz pop sozinha via guard no didChangeDependencies.
    } on OAuthLinkException catch (e) {
      if (!mounted) return;
      setState(() => _isLinkingGoogle = false);
      if (e.code != 'canceled') _showError(e.code);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLinkingGoogle = false);
      _showError(e.toString());
    }
  }

  void _showSuccess(String providerLabel) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Conta vinculada com $providerLabel!'),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String reason) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Não foi possível vincular: $reason'),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se o user JÁ vinculou (via Google que retornou do browser), fecha a
    // tela automaticamente. needsOAuthMigration vira false assim que o
    // auth state change dispara _loadUser com identities atualizadas.
    final userVM = context.watch<UserViewModel>();
    if (!userVM.needsOAuthMigration && (_isLinkingApple || _isLinkingGoogle)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showSuccess(_isLinkingGoogle ? 'Google' : 'Apple');
          Navigator.pop(context);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isLinkingApple || _isLinkingGoogle;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Conectar conta',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF374151)),
          onPressed: isBusy ? null : () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      size: 32,
                      color: Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Vincule sua conta',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pra continuar acessando o Stage, conecte sua conta ao Apple ou Google. Seus dados, currículos e vagas continuam intactos — só muda a forma de entrar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Apple primeiro porque é o caminho mais limpo no iOS (nativo).
            _ProviderButton(
              icon: Icons.apple,
              label: 'Continuar com Apple',
              isPrimary: true,
              isLoading: _isLinkingApple,
              isDisabled: isBusy,
              onPressed: _linkApple,
            ),
            const SizedBox(height: 12),
            _ProviderButton(
              iconImage: 'assets/images/google.png',
              label: 'Continuar com Google',
              isPrimary: false,
              isLoading: _isLinkingGoogle,
              isDisabled: isBusy,
              onPressed: _linkGoogle,
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Você pode escolher qualquer um — o que for mais prático pra você. Se preferir, depois pode vincular o outro também em Configurações.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9CA3AF),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  final IconData? icon;
  final String? iconImage;
  final String label;
  final bool isPrimary;
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback onPressed;

  const _ProviderButton({
    this.icon,
    this.iconImage,
    required this.label,
    required this.isPrimary,
    required this.isLoading,
    required this.isDisabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isPrimary ? Colors.black : Colors.white;
    final fg = isPrimary ? Colors.white : const Color(0xFF111827);
    return ElevatedButton(
      onPressed: isDisabled ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: isPrimary
            ? const Color(0xFF6B7280)
            : const Color(0xFFE5E7EB),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: isPrimary
              ? BorderSide.none
              : const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
        ),
      ),
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  color: fg,
                  strokeWidth: 2,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 22, color: fg)
            else if (iconImage != null)
              Image.asset(
                iconImage!,
                height: 20,
                width: 20,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.account_circle, size: 22, color: fg),
              ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
