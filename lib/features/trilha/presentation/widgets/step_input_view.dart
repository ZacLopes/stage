// Renderiza a ENTRADA inline de um passo da conversa (o "widget-first"):
// traduz um [StepInput] no widget certo (chips de escolha / texto guiado) e
// devolve um [StepAnswer] via [onSubmit]. Reusa o design system
// (AppChip, PrimaryButton, AppTextField). PLANO-FASE-6 T6.3.

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/conversation_step.dart';

class StepInputView extends StatefulWidget {
  const StepInputView({
    super.key,
    required this.step,
    required this.onSubmit,
    this.enabled = true,
  });

  final ConversationStep step;
  final ValueChanged<StepAnswer> onSubmit;

  /// Falso enquanto o passo anterior salva — trava a interação.
  final bool enabled;

  @override
  State<StepInputView> createState() => _StepInputViewState();
}

class _StepInputViewState extends State<StepInputView> {
  final Set<String> _selectedIds = {};
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textController.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(StepInputView old) {
    super.didUpdateWidget(old);
    // Passo novo → limpa o estado de seleção/texto.
    if (old.step.id != widget.step.id) {
      _selectedIds.clear();
      _textController.clear();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.step.input;
    return switch (input) {
      ChoiceInput() => _buildChoice(input),
      GuidedTextInput() => _buildGuidedText(input),
    };
  }

  // ── Escolha (chips) ──────────────────────────────────────────────────────
  Widget _buildChoice(ChoiceInput input) {
    final chips = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: input.options.map((o) {
        final selected = _selectedIds.contains(o.id);
        return AppChip(
          label: o.label,
          selected: selected,
          disabled: !widget.enabled ||
              (input.multi &&
                  !selected &&
                  input.maxSelections != null &&
                  _selectedIds.length >= input.maxSelections!),
          onTap: () => _onChipTap(input, o),
        );
      }).toList(),
    );

    if (!input.multi) {
      // Escolha única: tocar já avança — sem botão.
      return chips;
    }

    // Multisseleção: chips + botão de confirmar.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        chips,
        const SizedBox(height: AppSpacing.base),
        PrimaryButton(
          label: 'Continuar',
          onPressed: (_selectedIds.isEmpty || !widget.enabled)
              ? null
              : () => _submitChoice(input),
        ),
      ],
    );
  }

  void _onChipTap(ChoiceInput input, StepOption o) {
    if (!widget.enabled) return;
    if (!input.multi) {
      // Única: seleciona e envia na hora.
      widget.onSubmit(StepAnswer.choice(widget.step.id, [o]));
      return;
    }
    setState(() {
      if (_selectedIds.contains(o.id)) {
        _selectedIds.remove(o.id);
      } else {
        if (input.maxSelections != null &&
            _selectedIds.length >= input.maxSelections!) {
          return;
        }
        _selectedIds.add(o.id);
      }
    });
  }

  void _submitChoice(ChoiceInput input) {
    final selected =
        input.options.where((o) => _selectedIds.contains(o.id)).toList();
    if (selected.isEmpty) return;
    widget.onSubmit(StepAnswer.choice(widget.step.id, selected));
  }

  // ── Texto guiado ─────────────────────────────────────────────────────────
  Widget _buildGuidedText(GuidedTextInput input) {
    final text = _textController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _textController,
          hint: input.hint ?? input.example,
          helper: 'Ex.: ${input.example}',
          maxLength: input.maxLength,
          minLines: input.minLines,
          maxLines: input.minLines + 3,
          enabled: widget.enabled,
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: 'Enviar',
          onPressed: (text.isEmpty || !widget.enabled)
              ? null
              : () => widget.onSubmit(StepAnswer.text(widget.step.id, text)),
        ),
      ],
    );
  }
}
