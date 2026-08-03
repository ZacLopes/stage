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
import '../../splash/splash_screen.dart' show AuthGate;
import 'masking_questions/attribution_screen.dart';
import 'upload_preview_sheet.dart';
import 'onboarding_scaffold.dart';
import '../../../core/theme/theme.dart';

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
  // Marca quando a TwoDoorsScreen foi mostrada — pra calcular
  // `time_to_decide_ms` no `onboardingDoorChosen` (B.1 do plano v2).
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
    // QA Dia 6 fix: este é o entry do fluxo profile-first. Emite
    // onboarding_started (pareado com onboardingCompleted/_abandoned)
    // e onboarding_two_doors_shown via typed methods.
    // ignore: unawaited_futures
    Analytics.shared.onboardingStarted();
    // ignore: unawaited_futures
    Analytics.shared.onboardingTwoDoorsShown();
  }

  bool _pickingFile = false;

  Future<void> _chooseUpload() async {
    if (_pickingFile) return;
    HapticFeedback.lightImpact();
    final timeToDecideMs = _shownAt != null
        ? DateTime.now().difference(_shownAt!).inMilliseconds
        : 0;
    // ignore: unawaited_futures
    Analytics.shared.onboardingDoorChosen(
      door: 'upload_cv',
      timeToDecideMs: timeToDecideMs,
    );
    // ignore: unawaited_futures
    Analytics.shared.cvImportStarted();
    setState(() => _pickingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        // ignore: unawaited_futures
        Analytics.shared.onboardingCvImportAbandoned(reason: 'picker_cancelled');
        setState(() => _pickingFile = false);
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        // ignore: unawaited_futures
        Analytics.shared.onboardingCvImportAbandoned(reason: 'file_invalid');
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
          style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Sair', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
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
          SnackBar(content: Text('Erro ao sair: $e'), backgroundColor: AppColors.error),
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
    final timeToDecideMs = _shownAt != null
        ? DateTime.now().difference(_shownAt!).inMilliseconds
        : 0;
    // ignore: unawaited_futures
    Analytics.shared.onboardingDoorChosen(
      door: 'trail',
      timeToDecideMs: timeToDecideMs,
    );

    if (widget.onChooseTrail != null) {
      widget.onChooseTrail!();
      return;
    }

    // Trail flow: passa pelas mesmas masking questions do fluxo Upload pra
    // coletar dados pessoais. ExtractionStatusViewModel fica em
    // `notStarted` (sem CV pra extrair) — AllSetScreen detecta isso e
    // pula as telas de revisão de CV, indo direto pras preferences.
    // A campaign é criada no OnboardingCompleteScreen no final do fluxo,
    // igual ao path Upload.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AttributionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Vamos construir seu perfil',
      subtitle: 'Precisamos de algumas informações sobre você',
      showBack: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        tooltip: 'Sair',
        onPressed: _confirmExit,
      ),
      // Sem botão fixo — a escolha é via tap nos cards.
      //
      // `onContinue: null` NÃO basta: o contrato do scaffold é "null desabilita
      // o botão" (as outras telas contam com isso pra travar o Continuar até a
      // pergunta ser respondida), então o botão continuava desenhado, cinza e
      // inerte. Como esta é a PRIMEIRA tela depois do cadastro e "Continuar" é
      // o alvo mais óbvio dela, tocar ali e não ver reação nenhuma passava a
      // impressão de app quebrado no primeiro segundo de uso.
      // `customFooter` vazio remove o rodapé de vez. Revisão UX 28/07, P1-9.
      customFooter: const SizedBox.shrink(),
      child: Column(
        children: [
          _doorCard(
            icon: Icons.upload_file_outlined,
            title: 'Usar meu CV para preencher o perfil',
            badge: 'RECOMENDADO',
            description: 'Jeito mais rápido. Extraímos seus dados direto do arquivo.',
            onTap: _chooseUpload,
          ),
          const SizedBox(height: 16),
          _doorCard(
            icon: Icons.flag_outlined,
            title: 'Preencher passo a passo',
            description: 'Sem um CV em mãos? A gente te guia pelas telas, leva uns 10 min.',
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
            color: isRecommended ? AppColors.brandCyan : AppColors.border,
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
                    color: AppColors.brandCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.brandCyan, size: 26),
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
                            color: AppColors.brandCyan,
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
                const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textDisabled),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
