// Fase 2 (casa única do perfil): composição/gating VISUAL da aba Assistente.
//
// Extraído da ResumeTab pra ser TESTÁVEL sem Supabase (a ResumeTab instancia o
// controller lendo Supabase no initState). Decide entre:
//   • CONVERSA ÚNICA (trilha_assist_v1 ON): header + conversa, SEM CurriculoToggle
//     e SEM IndexedStack de prévia.
//   • SHELL legado (OFF / rollback): header com toggle + IndexedStack
//     [conversa, prévia].
// Preserva o colapso do header quando o teclado abre. Não conhece o controller
// nem os ViewModels — recebe os slots já montados (via WidgetBuilder, pra só
// construir o que a variante ativa precisa).

import 'package:flutter/material.dart';

class AssistantTabLayout extends StatelessWidget {
  const AssistantTabLayout({
    super.key,
    required this.assistEnabled,
    required this.keyboardOpen,
    required this.assistantTopBar,
    required this.legacyTopBar,
    required this.conversa,
    required this.preview,
    required this.tabIndex,
  });

  final bool assistEnabled;
  final bool keyboardOpen;
  final WidgetBuilder assistantTopBar;
  final WidgetBuilder legacyTopBar;
  final WidgetBuilder conversa;
  final WidgetBuilder preview;

  /// Índice do IndexedStack no shell legado (0 = conversa, 1 = prévia).
  final int tabIndex;

  /// Header que colapsa suave quando o teclado abre — libera altura pra conversa
  /// e evita que o dock de entrada tampe a pergunta.
  Widget _collapsingHeader(BuildContext context, WidgetBuilder topBar) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: keyboardOpen
          ? const SizedBox(width: double.infinity)
          : topBar(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (assistEnabled) {
      return SafeArea(
        bottom: false,
        child: Column(
          children: [
            _collapsingHeader(context, assistantTopBar),
            Expanded(child: conversa(context)),
          ],
        ),
      );
    }
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _collapsingHeader(context, legacyTopBar),
          Expanded(
            child: IndexedStack(
              index: tabIndex,
              children: [conversa(context), preview(context)],
            ),
          ),
        ],
      ),
    );
  }
}
