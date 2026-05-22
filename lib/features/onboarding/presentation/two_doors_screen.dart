// TwoDoorsScreen — escolha entre "Importar currículo" e "Construir pela trilha".
//
// Tela central do novo onboarding profile-first. Inspirada no Sorce, framing
// "Recomendado" + estimativa de tempo pra trilha como âncora psicológica.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';
import '../../../services/analytics_service.dart';
import '../../auth/user_viewmodel.dart';
import '../../home/home_viewmodel.dart';
import '../../splash/splash_screen.dart' show AuthGate;
import 'upload_preview_sheet.dart';
import 'onboarding_scaffold.dart';

class TwoDoorsScreen extends StatefulWidget {
  /// Callback opcional pra "Construir pela trilha". Se null, usa default:
  /// cria campaign skipped + abre aba Currículo (mesma lógica da CompletionScreen
  /// legacy). Standalone — funciona como root do AuthGate.
  final VoidCallback? onChooseTrail;

  const TwoDoorsScreen({super.key, this.onChooseTrail});

  @override
  State<TwoDoorsScreen> createState() => _TwoDoorsScreenState();
}

class _TwoDoorsScreenState extends State<TwoDoorsScreen> {
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.shared.track('onboarding_two_doors_shown');
  }

  bool _pickingFile = false;

  Future<void> _chooseUpload() async {
    if (_pickingFile) return;
    HapticFeedback.lightImpact();
    AnalyticsService.shared.track('onboarding_door_chosen', props: {'door': 'upload'});
    AnalyticsService.shared.track('onboarding_upload_started');
    setState(() => _pickingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _pickingFile = false);
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _pickingFile = false);
        return;
      }
      setState(() => _pickingFile = false);
      _showPreviewSheet(bytes, file.name);
    } catch (e) {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  /// Seta de voltar = sair da conta (conta NÃO é deletada — fica no Supabase
  /// Auth com hasCampaign=false e o usuário retoma daqui no próximo login).
  /// Sem isso, um pop simples geraria loop com o AuthGate.
  Future<void> _confirmExit() async {
    HapticFeedback.selectionClick();
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sair da conta?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Sua conta fica salva — você volta exatamente daqui quando fizer login de novo.',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Sair', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (shouldExit != true || !mounted) return;
    try {
      await context.read<UserViewModel>().logout();
      if (!mounted) return;
      // TwoDoorsScreen foi pushada com pushReplacement em cima do AuthGate.
      // Logout sozinho atualiza o Consumer<UserViewModel> que vive dentro do
      // AuthGate, mas essa tela continua no topo do Navigator stack —
      // visualmente "presa". pushAndRemoveUntil força volta pra raiz; o
      // AuthGate detecta isLoggedIn=false e renderiza AuthScreen.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao sair: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  void _showPreviewSheet(Uint8List bytes, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => UploadPreviewSheet(
        pdfBytes: bytes,
        fileName: name,
        onReplace: _chooseUpload, // "Trocar arquivo" reabre o picker
      ),
    );
  }

  Future<void> _chooseTrail() async {
    if (_processing) return;
    HapticFeedback.lightImpact();
    AnalyticsService.shared.track('onboarding_door_chosen', props: {'door': 'trail'});

    if (widget.onChooseTrail != null) {
      widget.onChooseTrail!();
      return;
    }

    // Default standalone: cria campaign skipped + abre aba Currículo.
    // AuthGate detecta hasCampaign=true e renderiza HomeScreen automaticamente,
    // com a tab Resume selecionada (que tem a trilha existente).
    setState(() => _processing = true);
    try {
      await context.read<UserViewModel>().createCampaign(isSkipped: true);
      if (!mounted) return;
      context.read<HomeViewModel>().requestTabChange(HomeTabs.resume);
      Analytics.shared.onboardingCompleted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Vamos construir seu perfil',
      subtitle: 'Precisamos de algumas informações sobre você',
      showBack: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF1F2937)),
        tooltip: 'Sair',
        onPressed: _confirmExit,
      ),
      onContinue: null, // sem botão fixo — escolha é via tap nos cards
      child: Column(
        children: [
          _doorCard(
            icon: Icons.upload_file_outlined,
            title: 'Importar currículo',
            badge: 'RECOMENDADO',
            description: 'Jeito mais rápido. Vamos extrair suas informações automaticamente.',
            onTap: _chooseUpload,
          ),
          const SizedBox(height: 16),
          _doorCard(
            icon: Icons.flag_outlined,
            title: 'Construir pela trilha',
            description: 'Sem currículo? Sem problema. A gente te guia passo a passo, leva uns 10 min.',
            onTap: _chooseTrail,
          ),
        ],
      ),
    );
  }

  Widget _doorCard({
    required IconData icon,
    required String title,
    String? badge,
    required String description,
    required VoidCallback onTap,
  }) {
    final isRecommended = badge != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRecommended ? const Color(0xFF00C27A) : const Color(0xFFE5E7EB),
            width: isRecommended ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C27A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: const Color(0xFF00C27A), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C27A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF9CA3AF)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
