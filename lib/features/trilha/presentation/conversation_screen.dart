// Tela da Trilha de Coleta conversacional (PLANO-FASE-6 T6.3).
//
// Versão PUSHADA do chat: Scaffold + SafeArea + chrome completo (header com X de
// fechar, barra de progresso, undo, e PopScope de confirmação de saída). É o que
// o convite pós-onboarding e o modo dev empurram via Navigator.
//
// O MOTOR da conversa (ritmo, bolhas, dock de entrada, finalização por IA) vive
// em [ChatThreadView] — reusado também embutido na aba Currículo, sem chrome.
// Aqui só montamos o chrome pushado em volta dele; os defaults do ChatThreadView
// já reproduzem o comportamento histórico desta tela.

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../application/conversation_controller.dart';
import 'widgets/chat_thread_view.dart';

class ConversationScreen extends StatelessWidget {
  const ConversationScreen({
    super.key,
    required this.controller,
    this.title = 'Vamos completar seu perfil',
    this.onCompleted,
    this.onAbandoned,
    this.onFinalize,
  });

  final ConversationController controller;
  final String title;

  /// Chamado quando a trilha termina (todos os passos respondidos).
  final VoidCallback? onCompleted;

  /// Chamado se a tela fecha ANTES de concluir (com ao menos 1 resposta dada).
  final void Function(int answered, int total)? onAbandoned;

  /// Roda na conclusão (ex.: a IA monta o resumo do perfil). Retorna o resumo
  /// gerado pra prévia, ou null. FAILURE-SAFE: erro não trava a conclusão.
  final Future<String?> Function()? onFinalize;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        // O footer cuida do inset de baixo (preenche o branco até a borda) —
        // senão sobra uma faixa cinza embaixo dos botões.
        bottom: false,
        child: ChatThreadView(
          controller: controller,
          title: title,
          onCompleted: onCompleted,
          onAbandoned: onAbandoned,
          onFinalize: onFinalize,
          // Chrome pushado (defaults — explícito pra deixar a intenção clara).
          showHeader: true,
          showCloseButton: true,
          showProgressBar: true,
          enablePopScope: true,
          popOnComplete: true,
          emitAbandonOnDispose: true,
          footerUsesScaffoldInset: true,
        ),
      ),
    );
  }
}
