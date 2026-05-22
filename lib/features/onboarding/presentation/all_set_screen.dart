// AllSetScreen — "Tudo certo!" — última tela antes da revisão linear.
//
// Cópia varia conforme caminho (upload vs trilha). Após user tocar Continue,
// navega pra ReviewPersonalInfoScreen (Container 1, Tela A).

import 'package:flutter/material.dart';
import 'onboarding_scaffold.dart';
// ReviewPersonalInfoScreen criada no Bloco E

class AllSetScreen extends StatelessWidget {
  /// 'upload' ou 'trail' — define cópia.
  final String viaPath;

  /// Callback pra navegar pra próxima tela (ReviewPersonalInfoScreen).
  /// Injetado pra evitar dependência circular entre módulos.
  final VoidCallback onContinue;

  const AllSetScreen({
    super.key,
    required this.viaPath,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final isUpload = viaPath == 'upload';
    return OnboardingScaffold(
      progress: 0.7,
      showBack: false,
      onContinue: onContinue,
      continueLabel: 'Revisar perfil',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFF00C27A).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: Color(0xFF00C27A), size: 56),
              ),
              const SizedBox(height: 28),
              const Text(
                'Tudo certo!',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                isUpload
                    ? 'Extraímos suas informações. Dá uma olhada se ficou tudo certinho.'
                    : 'Agora vamos confirmar seu perfil.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
