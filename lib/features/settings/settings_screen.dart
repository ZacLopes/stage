import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../core/utils/display_name.dart';
import '../auth/account_migration_screen.dart';
import '../auth/phone_auth_helpers.dart';
import '../auth/user_viewmodel.dart';
import '../auth/auth_session.dart';
import '../auth/onboarding_screen.dart';
import '../profile/application/profile_editor_view_model.dart';
import 'change_password_screen.dart';
import '../resume/widgets/ai_consent_modal.dart';
import '../resume/widgets/template_thumbnail_generator_screen.dart';
import '../trilha/application/conversation_controller.dart';
import '../trilha/demo/demo_conversation.dart';
import '../trilha/presentation/conversation_screen.dart';
import '../trilha/presentation/trilha_loader_screen.dart';
import '../tutorial/tutorial_controller.dart';
import '../../core/utils/app_notifications.dart';
import '../../services/analytics_events.dart';
import '../../services/analytics_service.dart';
import '../../services/notifications_service.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'settings';

  // Devmode unlock (release builds): toque 7x rápido no título "Configurações"
  // libera a seção [DEV] Ferramentas pro Pedro setar is_internal=true no
  // device dele (sem isso, métricas do Demo Day contam o teste interno).
  static const _kDevmodeUnlockedKey = 'analytics_devmode_unlocked';
  int _titleTapCount = 0;
  DateTime? _firstTapAt;
  bool _devmodeUnlocked = false;
  bool _isInternalDevice = false;

  @override
  void initState() {
    super.initState();
    _hydrateDevmodeState();
  }

  Future<void> _hydrateDevmodeState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _devmodeUnlocked = prefs.getBool(_kDevmodeUnlockedKey) ?? false;
      _isInternalDevice = Analytics.shared.isInternalUser;
    });
  }

  void _onTitleTap() async {
    final now = DateTime.now();
    // Janela de 2s pra completar a sequência de 7 toques.
    if (_firstTapAt == null || now.difference(_firstTapAt!).inSeconds > 2) {
      _firstTapAt = now;
      _titleTapCount = 1;
      return;
    }
    _titleTapCount++;
    if (_titleTapCount >= 7) {
      _titleTapCount = 0;
      _firstTapAt = null;
      final prefs = await SharedPreferences.getInstance();
      final nextValue = !_devmodeUnlocked;
      await prefs.setBool(_kDevmodeUnlockedKey, nextValue);
      if (!mounted) return;
      setState(() => _devmodeUnlocked = nextValue);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nextValue ? 'Devmode liberado' : 'Devmode bloqueado'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _toggleInternalDevice(bool value) async {
    await Analytics.shared.setInternalUser(value);
    if (!mounted) return;
    setState(() => _isInternalDevice = value);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value
          ? 'Device marcado como INTERNO — eventos filtrados do produto'
          : 'Device marcado como EXTERNO'),
      duration: const Duration(seconds: 3),
    ));
  }



  @override
  Widget build(BuildContext context) {
    final userVM = context.watch<UserViewModel>();
    final user = userVM.user;
    final profileEditorVM = context.watch<ProfileEditorViewModel>();
    final isEmailVerified = userVM.isEmailVerified;

    // Display name — prioriza profile_personal (novo onboarding) sobre
    // user_profiles.name legacy, que pode ser o placeholder "User".
    final displayName = resolveDisplayName(profileEditorVM, user?.name);
    final displayInitial =
        displayName.isNotEmpty ? displayName.trim()[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTitleTap,
          child: const Text('Configurações', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Banner de migração OAuth — só aparece pra users legacy de
          // email+senha que ainda não vincularam Apple/Google. Removido
          // o login com email do app (2026-05-26) → esses users precisam
          // migrar antes da sessão atual expirar.
          if (userVM.needsOAuthMigration) ...[
            _OAuthMigrationBanner(),
            const SizedBox(height: 20),
          ],
          // Section: Account
          const _SectionHeader(title: 'Conta'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // User Info Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primarySoft,
                        child: Text(
                          displayInitial,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            // Esconde linha pra contas via phone signup
                            // (email é sintético `phone_<digits>@stage.app`,
                            // exposto era confuso pro user).
                            if (!PhoneAuthHelpers.isSyntheticEmail(user?.email)) ...[
                              const SizedBox(height: 4),
                              Text(
                                user?.email ?? 'email@exemplo.com',
                                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Trocar senha só faz sentido pra users com auth email+senha
                // (identity provider 'email'). Esconde pra:
                //  - Apple/Google OAuth users (~88% da base, sem
                //    encrypted_password em auth.users)
                //  - Phone signup users (synthetic email + senha random,
                //    eles entram via OTP)
                // Pra esses, `signInWithPassword` falharia e a UX seria
                // confusa ("senha atual incorreta" pra alguém que nunca teve).
                if (userVM.hasPasswordAuth &&
                    !PhoneAuthHelpers.isSyntheticEmail(user?.email)) ...[
                  const Divider(height: 1),
                  _SettingsTile(
                    icon: Icons.lock_outline,
                    title: 'Senha',
                    subtitle: 'Trocar senha de acesso',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                      );
                    },
                  ),
                ],

              ],
            ),
          ),

          const SizedBox(height: 32),

          // Section: Notifications — diagnóstico + botão pra reativar push.
          // Vários usuários ficam em "Never Prompted" / "Denied" no OneSignal
          // (relatório: subscription criada mas push permission nunca foi
          // pedida ou foi negada). Sem reativação, eles nunca recebem push
          // — perde retenção. Este item dá o caminho de volta.
          const _SectionHeader(title: 'Notificações'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const _NotificationsTile(),
          ),

          const SizedBox(height: 32),

          // Section: Support
          const _SectionHeader(title: 'Suporte & Sobre'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Destaque: Falar com fundadores. Pra MVP, feedback é ouro —
                // colocamos como primeiro item da seção, com cor diferente.
                _SettingsTile(
                  icon: Icons.favorite_rounded,
                  title: 'Falar com os fundadores',
                  subtitle: 'Mande sua opinião, sugestão ou problema',
                  iconColor: AppColors.error,
                  onTap: () => _showFoundersContactSheet(context),
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.school_outlined,
                  title: 'Tutorial',
                  iconColor: Colors.blue,
                  onTap: () {
                    // Replay do tutorial dinâmico. HomeScreen escuta
                    // `replayRequested` e dispara `start()` quando o
                    // pop do Settings termina.
                    context.read<TutorialController>().requestReplay();
                    Navigator.pop(context);
                  },
                ),

              ],
            ),
          ),

          // Dev tools — visível em debug OU quando devmode unlock (7 toques
          // no título "Configurações") está ativo. Em release puro com
          // devmode bloqueado, fica fora da árvore.
          if (kDebugMode || _devmodeUnlocked) ...[
            const SizedBox(height: 32),
            const _SectionHeader(title: '[DEV] Ferramentas'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Toggle is_internal — quando ON, a person property
                  // is_internal: true entra em todo evento futuro via super
                  // property. Cohort "Internal users" no PostHog filtra
                  // essas sessões fora das métricas de produto.
                  SwitchListTile(
                    value: _isInternalDevice,
                    onChanged: _toggleInternalDevice,
                    title: const Text('Marcar device como interno'),
                    subtitle: Text(_isInternalDevice
                        ? 'Eventos desse device excluídos das métricas (is_internal=true).'
                        : 'Liga pra deixar de poluir o dashboard.'),
                    secondary: Icon(
                      Icons.shield_outlined,
                      color: _isInternalDevice ? AppColors.success : AppColors.textTertiary,
                    ),
                  ),
                  const Divider(height: 1),
                  _SettingsTile(
                    icon: Icons.image_outlined,
                    title: 'Gerar thumbnails dos templates',
                    subtitle: 'Regera os PNGs de preview no Documents/',
                    iconColor: Colors.purple,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TemplateThumbnailGeneratorScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  _SettingsTile(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Trilha de coleta (preview)',
                    subtitle: 'Demonstração conversacional — Increment 1',
                    iconColor: AppColors.primary,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConversationScreen(
                            controller:
                                ConversationController(buildDemoConversation()),
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  _SettingsTile(
                    icon: Icons.auto_awesome_motion_rounded,
                    title: 'Trilha de coleta (REAL — grava no perfil)',
                    subtitle: 'Adaptativa: pergunta só o que falta e salva em profile_*',
                    iconColor: AppColors.success,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TrilhaLoaderScreen(source: 'dev'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Section: Privacy
          const _SectionHeader(title: 'Privacidade'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.security_outlined,
                  title: 'Consentimento de IA',
                  subtitle: user?.aiConsent == true ? 'Autorizado' : 'Não autorizado',
                  iconColor: user?.aiConsent == true ? Colors.green : AppColors.textTertiary,
                  trailing: user?.aiConsent == true 
                    ? TextButton(
                        onPressed: () => _showRevokeConsentDialog(context, userVM),
                        child: const Text('Revogar', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                      )
                    : const Icon(Icons.chevron_right, color: AppColors.textDisabled, size: 20),
                  onTap: user?.aiConsent == true
                      ? null
                      : () => _showGrantConsentModal(context, userVM),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Logout Button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () async {
                 await context.read<UserViewModel>().logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                      (route) => false,
                    );
                  }
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppColors.errorSoft, // Red 50
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Sair da Conta', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Center(
            child: TextButton(
              onPressed: () {
                 showGeneralDialog(
                  context: context,
                  barrierDismissible: true,
                  barrierLabel: '',
                  transitionDuration: const Duration(milliseconds: 200),
                  pageBuilder: (context, anim1, anim2) => Container(),
                  transitionBuilder: (context, anim1, anim2, child) {
                    return Transform.scale(
                      scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack).value,
                      child: AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: EdgeInsets.zero,
                        content: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 40),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Excluir Conta?',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Essa ação é perigosa e irreversível. Todos os seus dados e progresso serão perdidos para sempre.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(color: AppColors.borderStrong),
                                        ),
                                      ),
                                      child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: StatefulBuilder(
                                      builder: (context, setDialogState) {
                                        final userVM = context.watch<UserViewModel>();
                                        final isDeleting = userVM.isLoading;

                                        return ElevatedButton(
                                          onPressed: isDeleting ? null : () async {
                                            try {
                                              await context.read<UserViewModel>().deleteAccount();
                                              if (context.mounted) {
                                                // 1. Close dialog first
                                                Navigator.pop(context); 
                                                // 2. Clear stack and go to Onboarding
                                                Navigator.of(context).pushAndRemoveUntil(
                                                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                                                  (route) => false,
                                                );
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                Navigator.pop(context); // Close dialog
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Erro ao excluir conta: $e'),
                                                    backgroundColor: AppColors.error,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.error,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          child: isDeleting 
                                            ? const SizedBox(
                                                height: 20, 
                                                width: 20, 
                                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                              )
                                            : const Text('Excluir', style: TextStyle(fontWeight: FontWeight.bold)),
                                        );
                                      }
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              child: const Text('Excluir minha conta', style: TextStyle(color: AppColors.error, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _showRevokeConsentDialog(BuildContext context, UserViewModel userVM) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Revogar Consentimento?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Ao revogar o consentimento, você não poderá mais gerar ou atualizar seu currículo com Inteligência Artificial até aceitar novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Manter', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revogar', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await userVM.revokeAIConsent();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Consentimento revogado com sucesso.'),
            backgroundColor: Colors.black87,
          ),
        );
      }
    }
  }

  void _showGrantConsentModal(BuildContext context, UserViewModel userVM) {
    final messenger = ScaffoldMessenger.of(context);
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (dialogContext, _, _) => AIConsentModal(
        onAccept: () async {
          try {
            await userVM.updateAIConsent(true);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Consentimento autorizado.'),
                backgroundColor: Colors.black87,
              ),
            );
          } catch (_) {
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Não foi possível salvar agora. Tente de novo.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        },
        onCancel: () => Navigator.pop(dialogContext),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Founders contact — feedback channels pro MVP
// ─────────────────────────────────────────────────────────────────────

/// Constantes centralizadas — pra trocar contato é só editar aqui.
class _FoundersContact {
  static const String whatsappNumber = '5543991260202'; // DDI+DDD+número, sem +/espaços
  static const String phoneNumber = '+5543991260202';
  static const String email = 'zackourilopes@outlook.com';
  static const String founderName = 'Zac Lopes';
}

void _showFoundersContactSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _FoundersContactSheet(),
  );
}

class _FoundersContactSheet extends StatelessWidget {
  const _FoundersContactSheet();

  Future<void> _openWhatsApp(BuildContext context) async {
    Analytics.shared.foundersContactOpened(channel: 'whatsapp');
    final userName = resolveDisplayName(
      context.read<ProfileEditorViewModel>(),
      context.read<UserViewModel>().user?.name,
    );
    final hasRealName = userName.isNotEmpty && userName != 'Usuário';
    final greeting = hasRealName ? 'Oi, sou o(a) $userName.' : 'Oi!';
    final text = Uri.encodeComponent(
      '$greeting Tô usando o Stage e queria mandar um feedback…',
    );
    final url = Uri.parse('https://wa.me/${_FoundersContact.whatsappNumber}?text=$text');
    await _safeLaunch(context, url, 'WhatsApp');
  }

  Future<void> _openPhone(BuildContext context) async {
    Analytics.shared.foundersContactOpened(channel: 'phone');
    final url = Uri.parse('tel:${_FoundersContact.phoneNumber}');
    await _safeLaunch(context, url, 'ligação');
  }

  Future<void> _openEmail(BuildContext context) async {
    Analytics.shared.foundersContactOpened(channel: 'email');
    final userName = resolveDisplayName(
      context.read<ProfileEditorViewModel>(),
      context.read<UserViewModel>().user?.name,
    );
    final subject = Uri.encodeComponent('Feedback Stage — $userName');
    final body = Uri.encodeComponent(
      'Oi ${_FoundersContact.founderName}!\n\n'
      '[Conte o que aconteceu, sua sugestão ou o que você gostaria de ver no Stage]\n\n'
      '— Enviado pelo app Stage v1.1.0',
    );
    final url = Uri.parse(
      'mailto:${_FoundersContact.email}?subject=$subject&body=$body',
    );
    await _safeLaunch(context, url, 'email');
  }

  Future<void> _safeLaunch(BuildContext context, Uri url, String label) async {
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não consegui abrir o $label. Tente outro canal.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (context.mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao abrir o $label.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.waving_hand_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Falar com os fundadores',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Seu feedback molda o Stage. A gente lê tudo.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _ContactOption(
                icon: Icons.chat_bubble_rounded,
                iconBg: const Color(0xFF25D366),
                title: 'WhatsApp',
                subtitle: 'Chat rápido — geralmente respondo em até 1h',
                badge: 'Mais rápido',
                onTap: () => _openWhatsApp(context),
              ),
              const SizedBox(height: 10),
              _ContactOption(
                icon: Icons.phone_rounded,
                iconBg: AppColors.info,
                title: 'Ligar',
                subtitle: 'Bug crítico ou conversa direta',
                onTap: () => _openPhone(context),
              ),
              const SizedBox(height: 10),
              _ContactOption(
                icon: Icons.mail_rounded,
                iconBg: AppColors.warning,
                title: 'Email',
                subtitle: 'Pra feedback mais elaborado',
                onTap: () => _openEmail(context),
              ),
              const SizedBox(height: 18),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      'Seu contato fica entre você e o time',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactOption extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _ContactOption({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: iconBg.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF047857),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textTertiary,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? AppColors.textTertiary).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor ?? AppColors.textTertiary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary)),
      subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: AppColors.textTertiary, fontSize: 13)) : null,
      trailing: trailing ?? const Icon(Icons.chevron_right, color: AppColors.textDisabled, size: 20),
    );
  }
}

/// Item de Settings que mostra o status das notificações push e oferece
/// reativação one-tap. Refresh do status:
///   - No initState (entrada na tela)
///   - No didChangeDependencies (volta de outra tela)
///   - Após tap de reativar (espera 1s pra OneSignal sincronizar)
///
/// Mensagens de status alinhadas ao OneSignal:
///   - subscribed     → "Ativas" + ícone verde
///   - denied         → "Bloqueadas no iOS · Toque pra reativar"
///   - never_prompted → "Desligadas · Toque pra ativar"
///   - unknown        → "Não foi possível verificar"
class _NotificationsTile extends StatefulWidget {
  const _NotificationsTile();

  @override
  State<_NotificationsTile> createState() => _NotificationsTileState();
}

class _NotificationsTileState extends State<_NotificationsTile> {
  String _status = 'unknown';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await NotificationsService.shared.pushStatus();
    if (!mounted) return;
    setState(() => _status = s);
  }

  Future<void> _onTap() async {
    if (_loading) return;
    // Se já está subscribed, oferecer um teste rápido em vez de mexer.
    if (_status == 'subscribed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notificações já estão ativas ✓'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    Analytics.shared.track(evPushReactivateTapped,
        props: {'previous_status': _status});

    final userId = currentUserIdOrNull();
    final granted = await NotificationsService.shared
        .reactivatePush(userId: userId);

    // Espera o SDK sincronizar antes de re-checar status (iOS roundtrip).
    await Future.delayed(const Duration(seconds: 1));
    await _refresh();

    Analytics.shared.track(evPushReactivateCompleted, props: {
      'granted': granted,
      'new_status': _status,
    });

    if (!mounted) return;
    setState(() => _loading = false);

    final msg = _status == 'subscribed'
        ? 'Notificações ativadas ✓'
        : (granted
            ? 'Aguarde alguns segundos pra sincronizar'
            : 'Pra reativar, vá em Ajustes do iPhone → Stage → Notificações');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  ({IconData icon, Color color, String title, String subtitle}) _viewModel() {
    switch (_status) {
      case 'subscribed':
        return (
          icon: Icons.notifications_active_rounded,
          color: AppColors.success,
          title: 'Notificações',
          subtitle: 'Ativas — você recebe pushes do Stage',
        );
      case 'denied':
        return (
          icon: Icons.notifications_off_rounded,
          color: AppColors.error,
          title: 'Notificações bloqueadas',
          subtitle: 'Toque pra abrir Ajustes do iPhone e reativar',
        );
      case 'never_prompted':
        return (
          icon: Icons.notifications_paused_rounded,
          color: AppColors.warning,
          title: 'Ativar notificações',
          subtitle: 'Vagas que combinam com você chegam direto aqui',
        );
      default:
        return (
          icon: Icons.notifications_none_rounded,
          color: AppColors.textTertiary,
          title: 'Notificações',
          subtitle: 'Toque pra verificar',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = _viewModel();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: _onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: vm.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(vm.icon, color: vm.color, size: 20),
      ),
      title: Text(
        vm.title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        vm.subtitle,
        style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
      ),
      trailing: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right,
              color: AppColors.textDisabled, size: 20),
    );
  }
}

/// Banner pros 112 users legacy de email+senha que precisam vincular
/// Apple ou Google antes que a sessão atual expire (removemos a tela
/// de login com email em 2026-05-26). Renderiza só quando
/// `userVM.needsOAuthMigration == true` — some sozinho assim que o
/// user vincula. Some também pra OAuth users e phone signup.
///
/// Visual: card amarelo destacado no topo do Settings, com CTA pra
/// AccountMigrationScreen. Não-dismissível — a ação é obrigatória.
class _OAuthMigrationBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AccountMigrationScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warningSoft,
          border: Border.all(color: AppColors.xp, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Conecte sua conta',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Vincule Apple ou Google pra continuar entrando.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF92400E),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.warning,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
