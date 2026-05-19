import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import '../auth/user_viewmodel.dart';
import '../auth/onboarding_screen.dart';
import 'edit_account_screen.dart';
import '../tutorial/tutorial_controller.dart';
import '../../core/utils/app_notifications.dart';
import '../../services/analytics_service.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'settings';

  @override
  void initState() {
    super.initState();
  }



  @override
  Widget build(BuildContext context) {
    final userVM = context.watch<UserViewModel>();
    final user = userVM.user;
    final isEmailVerified = userVM.isEmailVerified;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Configurações', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
                        backgroundColor: const Color(0xFFEEF2FF),
                        child: Text(
                          user?.name.substring(0, 1).toUpperCase() ?? 'U',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.name ?? 'Usuário', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(user?.email ?? 'email@exemplo.com', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.person_outline,
                  title: 'Dados Pessoais',
                  subtitle: 'Nome, curso, universidade',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EditAccountScreen()),
                    );
                  },
                ),

              ],
            ),
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
                  iconColor: const Color(0xFFEF4444),
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

                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.info_outline,
                  title: 'Sobre o App',
                  subtitle: 'Versão 1.1.0',
                  iconColor: Colors.grey,
                  onTap: () {},
                ),
              ],
            ),
          ),

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
                  iconColor: user?.aiConsent == true ? Colors.green : Colors.grey,
                  trailing: user?.aiConsent == true 
                    ? TextButton(
                        onPressed: () => _showRevokeConsentDialog(context, userVM),
                        child: const Text('Revogar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      )
                    : const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 20),
                  onTap: user?.aiConsent == true ? null : () {
                    // This will be handled by the Resume tab when they try to generate
                  },
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
                backgroundColor: const Color(0xFFFEE2E2), // Red 50
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Sair da Conta', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
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
                                child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 40),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Excluir Conta?',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Essa ação é perigosa e irreversível. Todos os seus dados e progresso serão perdidos para sempre.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
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
                                          side: BorderSide(color: Colors.grey.shade300),
                                        ),
                                      ),
                                      child: const Text('Cancelar', style: TextStyle(color: Color(0xFF374151), fontWeight: FontWeight.bold)),
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
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
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
              child: const Text('Excluir minha conta', style: TextStyle(color: Colors.red, fontSize: 14)),
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
            child: const Text('Manter', style: TextStyle(color: Color(0xFF374151))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revogar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
    final userName = context.read<UserViewModel>().user?.name ?? '';
    final greeting = userName.isNotEmpty ? 'Oi, sou o(a) $userName.' : 'Oi!';
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
    final userName = context.read<UserViewModel>().user?.name ?? '';
    final subject = Uri.encodeComponent('Feedback Stage — ${userName.isNotEmpty ? userName : 'Usuário'}');
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
            backgroundColor: Colors.red.shade600,
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
          backgroundColor: Colors.red.shade600,
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
                    color: const Color(0xFFE2E8F0),
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
                        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withOpacity(0.3),
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
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Seu feedback molda o Stage. A gente lê tudo.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
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
                iconBg: const Color(0xFF0EA5E9),
                title: 'Ligar',
                subtitle: 'Bug crítico ou conversa direta',
                onTap: () => _openPhone(context),
              ),
              const SizedBox(height: 10),
              _ContactOption(
                icon: Icons.mail_rounded,
                iconBg: const Color(0xFFF59E0B),
                title: 'Email',
                subtitle: 'Pra feedback mais elaborado',
                onTap: () => _openEmail(context),
              ),
              const SizedBox(height: 18),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 13, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 6),
                    Text(
                      'Seu contato fica entre você e o time',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
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
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
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
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.15),
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
                        color: Color(0xFF64748B),
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
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
          color: Colors.grey[500],
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
          color: (iconColor ?? const Color(0xFF6B7280)).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor ?? const Color(0xFF6B7280), size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF1F2937))),
      subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: Colors.grey[500], fontSize: 13)) : null,
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 20),
    );
  }
}
