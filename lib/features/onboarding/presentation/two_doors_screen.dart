// TwoDoorsScreen — escolha entre "Importar currículo" e "Construir pela trilha".
//
// Tela central do novo onboarding profile-first. Inspirada no Sorce, framing
// "Recomendado" + estimativa de tempo pra trilha como âncora psicológica.

import 'package:flutter/material.dart';
import '../../../services/analytics_service.dart';
import 'upload_selector_screen.dart';
import 'onboarding_scaffold.dart';

class TwoDoorsScreen extends StatefulWidget {
  /// Callback quando user escolhe "Construir pela trilha".
  /// Navega pra trilha gamificada existente (será adaptada no Bloco F).
  final VoidCallback onChooseTrail;

  const TwoDoorsScreen({super.key, required this.onChooseTrail});

  @override
  State<TwoDoorsScreen> createState() => _TwoDoorsScreenState();
}

class _TwoDoorsScreenState extends State<TwoDoorsScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.shared.track('onboarding_two_doors_shown');
  }

  void _chooseUpload() {
    AnalyticsService.shared.track('onboarding_door_chosen', props: {'door': 'upload'});
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UploadSelectorScreen()),
    );
  }

  void _chooseTrail() {
    AnalyticsService.shared.track('onboarding_door_chosen', props: {'door': 'trail'});
    widget.onChooseTrail();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Vamos construir seu perfil',
      subtitle: 'Precisamos de algumas informações sobre você',
      showBack: false,
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
