// OnboardingScaffold — layout padrão das telas do novo onboarding.
//
// Estrutura: AppBar com back + progress bar (opcional), header (título+sub),
// conteúdo, e botão Continue no rodapé fixo.

import 'package:flutter/material.dart';

class OnboardingScaffold extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final double? progress; // 0..1, null esconde a barra
  final Widget child;
  final String continueLabel;
  final VoidCallback? onContinue; // null desabilita botão
  final bool showBack;
  final Widget? skipButton; // pra "Pular essa parte"
  final Color continueColor;

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
    this.continueColor = const Color(0xFF00C27A),
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        automaticallyImplyLeading: showBack,
        title: progress == null
            ? null
            : ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0, 1),
                  backgroundColor: const Color(0xFFE5E7EB),
                  color: const Color(0xFF00C27A),
                  minHeight: 4,
                ),
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15),
                        ),
                      ),
                    const SizedBox(height: 20),
                    child,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  if (skipButton != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: skipButton!,
                    ),
                  SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: continueColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFD1D5DB),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        continueLabel,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
