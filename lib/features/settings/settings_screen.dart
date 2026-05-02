import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/user_viewmodel.dart';
import '../auth/onboarding_screen.dart';
import 'edit_account_screen.dart';
import '../../services/tutorial_service.dart';
import '../../core/utils/app_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
                _SettingsTile(
                  icon: Icons.school_outlined,
                  title: 'Tutorial',
                  iconColor: Colors.blue,
                  onTap: () {
                    // Trigger tutorial replay
                     Navigator.pop(context);
                     Future.delayed(const Duration(milliseconds: 300), () {
                        TutorialService.triggerTutorial();
                     });
                  },
                ),

                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.info_outline,
                  title: 'Sobre o App',
                  subtitle: 'Versão 1.0.0',
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
