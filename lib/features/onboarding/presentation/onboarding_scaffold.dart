// OnboardingScaffold — layout padrão das telas do novo onboarding.
//
// Estrutura: header com back button circular + progress bar inline,
// título + subtítulo no body, conteúdo scrollable, botão Continue
// pill fixo no rodapé.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../../core/theme/theme.dart';

const _kBorderColor = AppColors.border;
const _kTextColor = AppColors.textPrimary;
const _kMutedText = AppColors.textTertiary;
const _kAccent = AppColors.primary;

class OnboardingScaffold extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final double? progress; // 0..1, null esconde a barra
  final Widget child;
  final String continueLabel;
  final VoidCallback? onContinue; // null desabilita botão
  final bool showBack;
  final Widget? skipButton; // pra "Pular essa parte"
  final Widget? leading; // override total do leading (ex: botão de sair custom)
  final Color continueColor;
  /// Se fornecido, substitui o footer padrão (botão Continuar + skipButton).
  /// Útil quando a tela precisa de dois CTAs ou layout custom no rodapé.
  final Widget? customFooter;

  const OnboardingScaffold({
    super.key,
    this.title,
    this.subtitle,
    this.progress,
    required this.child,
    this.continueLabel = 'Continuar',
    this.onContinue,
    this.showBack = true,
    this.skipButton,
    this.leading,
    this.continueColor = _kAccent,
    this.customFooter,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: _kTextColor,
                          height: 1.15,
                        ),
                      ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(color: _kMutedText, fontSize: 15),
                        ),
                      ),
                    const SizedBox(height: 20),
                    child,
                  ],
                ),
              ),
            ),
            customFooter ?? _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (showBack)
            _CircleBackButton(onTap: () => Navigator.of(context).maybePop())
          else
            const SizedBox(width: 40),
          if (progress != null) ...[
            const SizedBox(width: 16),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0, 1),
                  backgroundColor: _kBorderColor,
                  color: _kAccent,
                  minHeight: 6,
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          if (skipButton != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: skipButton!,
            ),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onContinue == null
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      onContinue!();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: continueColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: continueColor.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: Text(
                continueLabel,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CircleBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _kBorderColor),
          ),
          child: const Icon(Icons.arrow_back_rounded, color: _kTextColor, size: 22),
        ),
      ),
    );
  }
}
