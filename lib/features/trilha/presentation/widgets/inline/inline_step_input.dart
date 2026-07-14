// Widgets de entrada INLINE da trilha v2 (PLANO chat v2 — F1).
//
// Diferente do StepInputView antigo (que vivia numa doca embaixo), estes
// widgets aparecem NO FIO da conversa, logo abaixo da pergunta da IA. São
// refeitos do zero, fiéis aos mockups (chips ✓, slider de nível, busca inline),
// usando só tokens Stage. Cada um coleta o dado e chama [onSubmit] com o
// [StepAnswer] no MESMO formato do domínio (compatível com o write-back).
//
// O modo "card preenchido/editável (✎)" do passo JÁ respondido fica em
// answer_card.dart — aqui é só o modo ATIVO (responder).

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../../../core/theme/theme.dart';
import '../../../domain/conversation_step.dart';
import '../experience_type_picker.dart';
import '../trilha_option_tile.dart';

/// Dispatcher: renderiza o widget inline certo pro [step.input].
class InlineStepInput extends StatelessWidget {
  const InlineStepInput({
    super.key,
    required this.step,
    required this.onSubmit,
    this.enabled = true,
    this.initialAnswer,
  });

  final ConversationStep step;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;

  /// Resposta já dada, pra PRÉ-PREENCHER o widget ao EDITAR (toque no lápis).
  /// Null no fluxo normal (passo novo, em branco). Cada widget lê daqui pra
  /// abrir com o que o usuário tinha escrito — nunca zerado.
  final StepAnswer? initialAnswer;

  @override
  Widget build(BuildContext context) {
    final input = step.input;
    // Nível de idioma vira SLIDER (mockup), mesmo sendo ChoiceInput no domínio.
    if (input is ChoiceInput &&
        input.compact &&
        step.id.startsWith('lang.level.')) {
      return _LevelSlider(
          step: step,
          input: input,
          onSubmit: onSubmit,
          enabled: enabled,
          initialAnswer: initialAnswer);
    }
    return switch (input) {
      ChoiceInput() => _ChoiceChips(
          step: step,
          input: input,
          onSubmit: onSubmit,
          enabled: enabled,
          initialAnswer: initialAnswer),
      GuidedTextInput() => _GuidedText(
          step: step,
          input: input,
          onSubmit: onSubmit,
          enabled: enabled,
          initialAnswer: initialAnswer),
      MonthYearInput() => _MonthYear(
          step: step,
          input: input,
          onSubmit: onSubmit,
          enabled: enabled,
          initialAnswer: initialAnswer),
      SuggestPickInput() => _SuggestPick(
          step: step,
          input: input,
          onSubmit: onSubmit,
          enabled: enabled,
          initialAnswer: initialAnswer),
      AsyncSuggestInput() => _AsyncSuggest(
          step: step,
          input: input,
          onSubmit: onSubmit,
          enabled: enabled,
          initialAnswer: initialAnswer),
      AsyncPickInput() => _AsyncPick(
          step: step,
          input: input,
          onSubmit: onSubmit,
          enabled: enabled,
          initialAnswer: initialAnswer),
      ExperienceTypeInput() => ExperienceTypePicker(
          stepId: step.id,
          input: input,
          onSubmit: onSubmit,
          enabled: enabled,
          initialAnswer: initialAnswer),
    };
  }
}

// ── Chip selecionável (átomo visual, fiel ao mockup) ────────────────────────

class TrilhaChip extends StatelessWidget {
  const TrilhaChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: AppRadius.brPill,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded,
                  size: 15, color: AppColors.onPrimary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: AppTextStyles.labelMd.copyWith(
                color: selected ? AppColors.onPrimary : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CTA de destaque pra escolha ÚNICA de uma opção (a abertura da trilha).
/// Largura cheia, gradiente da marca, seta e mola no toque (com haptic) — pra
/// o "Bora começar" ter cara de convite, não de chip solto. Desabilitado
/// enquanto o passo anterior salva (esmaece + ignora o toque).
class _ChoiceCta extends StatefulWidget {
  const _ChoiceCta({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_ChoiceCta> createState() => _ChoiceCtaState();
}

class _ChoiceCtaState extends State<_ChoiceCta> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.enabled) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.enabled ? 1 : 0.5,
      duration: const Duration(milliseconds: 150),
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.enabled
            ? () {
                HapticFeedback.mediumImpact();
                widget.onTap();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: double.infinity,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppGradients.brand,
              borderRadius: AppRadius.brPill,
              boxShadow: widget.enabled ? AppShadows.brand : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: AppTextStyles.labelLg.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.arrow_forward_rounded,
                    size: 20, color: AppColors.onPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão primário cheio (CTA dos widgets — "Confirmar", "Enviar"…).
class _InlineCta extends StatelessWidget {
  const _InlineCta({required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: Material(
        color: on ? AppColors.primary : AppColors.primary.withValues(alpha: 0.4),
        borderRadius: AppRadius.brMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.brMd,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.onPrimary),
                  const SizedBox(width: 7),
                ],
                Text(label,
                    style: AppTextStyles.labelLg
                        .copyWith(color: AppColors.onPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão "Pular" discreto (secundário) pros passos opcionais.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text('Pular',
          style:
              AppTextStyles.labelMd.copyWith(color: AppColors.textTertiary)),
    );
  }
}

// ── ChoiceInput: chips (única auto-submete; múltipla com confirmar) ──────────

class _ChoiceChips extends StatefulWidget {
  const _ChoiceChips(
      {required this.step,
      required this.input,
      required this.onSubmit,
      required this.enabled,
      this.initialAnswer});
  final ConversationStep step;
  final ChoiceInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;
  final StepAnswer? initialAnswer;

  @override
  State<_ChoiceChips> createState() => _ChoiceChipsState();
}

class _ChoiceChipsState extends State<_ChoiceChips> {
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    // Edição: re-marca o que já estava escolhido (ids da resposta anterior).
    final init = widget.initialAnswer?.value;
    if (init is List) _selected.addAll(init.map((e) => e.toString()));
  }

  void _toggle(StepOption o) {
    if (!widget.enabled) return;
    if (!widget.input.multi) {
      // Única: submete na hora.
      widget.onSubmit(StepAnswer.choice(widget.step.id, [o]));
      return;
    }
    setState(() {
      if (_selected.contains(o.id)) {
        _selected.remove(o.id);
      } else {
        final max = widget.input.maxSelections;
        if (max != null && _selected.length >= max) return;
        _selected.add(o.id);
      }
    });
  }

  void _confirm() {
    final chosen =
        widget.input.options.where((o) => _selected.contains(o.id)).toList();
    widget.onSubmit(StepAnswer.choice(widget.step.id, chosen));
  }

  @override
  Widget build(BuildContext context) {
    // Escolha ÚNICA de UMA opção (a abertura "Bora começar", o único passo
    // assim): não é um chip solto e miúdo perdido no canto — é O convite pra
    // começar. Vira um CTA cheio, com o gradiente da marca, seta e mola no
    // toque. (Yes/Não e afins têm 2+ opções → seguem como chips lado a lado.)
    if (!widget.input.multi && widget.input.options.length == 1) {
      final o = widget.input.options.first;
      return _ChoiceCta(
        label: o.label,
        enabled: widget.enabled,
        onTap: () => widget.onSubmit(StepAnswer.choice(widget.step.id, [o])),
      );
    }

    // Escolha ÚNICA com 2+ opções "com respiro" (não-compacta) → tiles cheios
    // empilhados (título + subtítulo + seta), tocar já avança. Bem mais legível
    // que chips soltos pra perguntas tipo "que empresa combina com você?".
    if (!widget.input.multi && !widget.input.compact) {
      final options = widget.input.options;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            TrilhaOptionTile(
              label: options[i].label,
              subtitle: options[i].subtitle,
              onTap: widget.enabled ? () => _toggle(options[i]) : null,
            ),
          ],
        ],
      );
    }

    // Compacta (escalas/nível) ou multisseleção → chips lado a lado.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final o in widget.input.options)
              TrilhaChip(
                label: o.label,
                selected: _selected.contains(o.id),
                onTap: () => _toggle(o),
                enabled: widget.enabled,
              ),
          ],
        ),
        if (widget.input.multi) ...[
          const SizedBox(height: AppSpacing.md),
          _InlineCta(
            label: _selected.isEmpty
                ? 'Confirmar'
                : 'Confirmar ${_selected.length} selecionada${_selected.length > 1 ? 's' : ''}',
            onTap: (widget.enabled && _selected.isNotEmpty) ? _confirm : null,
          ),
        ],
      ],
    );
  }
}

// ── Slider de nível (idioma): Básico → Intermediário → Avançado → … ─────────

class _LevelSlider extends StatefulWidget {
  const _LevelSlider(
      {required this.step,
      required this.input,
      required this.onSubmit,
      required this.enabled,
      this.initialAnswer});
  final ConversationStep step;
  final ChoiceInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;
  final StepAnswer? initialAnswer;

  @override
  State<_LevelSlider> createState() => _LevelSliderState();
}

class _LevelSliderState extends State<_LevelSlider> {
  late int _index = _initialIndex();

  /// Português começa em "Nativo" (caso comum p/ usuário BR); os demais idiomas
  /// começam no meio da escala. Na EDIÇÃO, começa no nível já escolhido.
  int _initialIndex() {
    final opts = widget.input.options;
    final init = widget.initialAnswer?.value;
    if (init is List && init.isNotEmpty) {
      final i = opts.indexWhere((o) => o.id == init.first.toString());
      if (i >= 0) return i;
    }
    if (widget.step.id.toLowerCase() == 'lang.level.português') {
      final i = opts.indexWhere((o) => o.id == 'native');
      if (i >= 0) return i;
    }
    return (opts.length / 2).floor();
  }

  @override
  Widget build(BuildContext context) {
    final opts = widget.input.options;
    final current = opts[_index];
    return Container(
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Nível', style: AppTextStyles.labelLg),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: AppRadius.brPill,
                ),
                child: Text(current.label,
                    style: AppTextStyles.labelMd
                        .copyWith(color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.surface,
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 18),
              thumbShape: const _RingThumb(),
            ),
            child: Slider(
              value: _index.toDouble(),
              min: 0,
              max: (opts.length - 1).toDouble(),
              divisions: opts.length - 1,
              onChanged: widget.enabled
                  ? (v) => setState(() => _index = v.round())
                  : null,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final o in opts)
                Flexible(
                  child: Text(
                    o.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelSm.copyWith(
                      fontSize: 9.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InlineCta(
            label: 'Confirmar',
            onTap: widget.enabled
                ? () =>
                    widget.onSubmit(StepAnswer.choice(widget.step.id, [current]))
                : null,
          ),
        ],
      ),
    );
  }
}

/// Thumb em anel (branco com borda azul) — combina com o mockup.
class _RingThumb extends SliderComponentShape {
  const _RingThumb();
  @override
  Size getPreferredSize(bool enabled, bool isDiscrete) => const Size(22, 22);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final canvas = context.canvas;
    canvas.drawCircle(center, 11, Paint()..color = AppColors.surface);
    canvas.drawCircle(
        center,
        11,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }
}

// ── GuidedTextInput: campo multi-linha + exemplo + Enviar/Pular ─────────────

class _GuidedText extends StatefulWidget {
  const _GuidedText(
      {required this.step,
      required this.input,
      required this.onSubmit,
      required this.enabled,
      this.initialAnswer});
  final ConversationStep step;
  final GuidedTextInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;
  final StepAnswer? initialAnswer;

  @override
  State<_GuidedText> createState() => _GuidedTextState();
}

class _GuidedTextState extends State<_GuidedText> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Edição: reabre com o texto que o usuário já tinha escrito.
    final init = widget.initialAnswer?.value;
    if (init is String) _controller.text = init;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            enabled: widget.enabled,
            minLines: widget.input.minLines,
            // Deriva do maxLength (não mais 5 cravado): textão abre num campo
            // alto o bastante pra LER o texto inteiro na edição (device-test).
            maxLines: widget.input.effectiveMaxLines,
            maxLength: widget.input.maxLength,
            onChanged: (_) => setState(() {}),
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
            // Sem o fill/borda do inputDecorationTheme global (que desenhava um
            // "retângulo dentro" do nosso container) — campo limpo.
            decoration: InputDecoration(
              hintText: widget.input.hint ?? 'Escreva aqui…',
              hintStyle: AppTextStyles.bodyMd
                  .copyWith(color: AppColors.textTertiary),
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              counterText: '',
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ex.: ${widget.input.example}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
              ),
              Text('${_controller.text.characters.length}/${widget.input.maxLength}',
                  style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _InlineCta(
                  label: 'Enviar',
                  icon: Icons.send_rounded,
                  onTap: (widget.enabled && _controller.text.trim().isNotEmpty)
                      ? () => widget.onSubmit(
                          StepAnswer.text(widget.step.id, _controller.text))
                      : null,
                ),
              ),
              if (widget.input.optional) ...[
                const SizedBox(width: AppSpacing.sm),
                _SkipButton(
                  onTap: () =>
                      widget.onSubmit(StepAnswer.text(widget.step.id, '')),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── MonthYearInput: chips de mês + ano + Confirmar/Pular ────────────────────

class _MonthYear extends StatefulWidget {
  const _MonthYear(
      {required this.step,
      required this.input,
      required this.onSubmit,
      required this.enabled,
      this.initialAnswer});
  final ConversationStep step;
  final MonthYearInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;
  final StepAnswer? initialAnswer;

  @override
  State<_MonthYear> createState() => _MonthYearState();
}

class _MonthYearState extends State<_MonthYear> {
  static const _months = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  late final List<int> _years;
  late int _monthIndex; // 0..11
  late int _yearIndex; // 0 = ano mais recente
  late final FixedExtentScrollController _monthCtrl;
  late final FixedExtentScrollController _yearCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _years = [
      for (var y = now.year; y >= now.year - widget.input.yearsBack; y--) y,
    ];
    _monthIndex = now.month - 1;
    _yearIndex = 0;
    // Edição: reposiciona as rodas no mês/ano já gravado ('YYYY-MM').
    final init = widget.initialAnswer?.value;
    if (init is String) {
      final parts = init.split('-');
      if (parts.length == 2) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (m != null && m >= 1 && m <= 12) _monthIndex = m - 1;
        if (y != null) {
          final yi = _years.indexOf(y);
          if (yi >= 0) _yearIndex = yi;
        }
      }
    }
    _monthCtrl = FixedExtentScrollController(initialItem: _monthIndex);
    _yearCtrl = FixedExtentScrollController(initialItem: _yearIndex);
  }

  @override
  void dispose() {
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _onMonth(int i) {
    HapticFeedback.selectionClick(); // tique tátil a cada item (como o iOS)
    setState(() => _monthIndex = i);
  }

  void _onYear(int i) {
    HapticFeedback.selectionClick();
    setState(() => _yearIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Mês', style: AppTextStyles.overline)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Ano', style: AppTextStyles.overline)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Rodas roláveis (mês | ano) com tique tátil — feel de picker nativo.
          IgnorePointer(
            ignoring: !widget.enabled,
            child: SizedBox(
              height: 168,
              child: Row(
                children: [
                  Expanded(
                    child: _wheel(
                      controller: _monthCtrl,
                      count: 12,
                      selected: _monthIndex,
                      onChanged: _onMonth,
                      labelFor: (i) => _months[i],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _wheel(
                      controller: _yearCtrl,
                      count: _years.length,
                      selected: _yearIndex,
                      onChanged: _onYear,
                      labelFor: (i) => '${_years[i]}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _InlineCta(
                  label: 'Confirmar',
                  onTap: widget.enabled
                      ? () => widget.onSubmit(StepAnswer.monthYear(
                          widget.step.id, _years[_yearIndex], _monthIndex + 1))
                      : null,
                ),
              ),
              if (widget.input.optional) ...[
                const SizedBox(width: AppSpacing.sm),
                _SkipButton(
                  onTap: () => widget.onSubmit(
                      StepAnswer.text(widget.step.id, '')),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required int selected,
    required ValueChanged<int> onChanged,
    required String Function(int) labelFor,
  }) {
    return CupertinoPicker(
      scrollController: controller,
      itemExtent: 40,
      squeeze: 1.1,
      diameterRatio: 1.25,
      onSelectedItemChanged: onChanged,
      selectionOverlay: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: AppColors.primarySoft.withValues(alpha: 0.45),
          borderRadius: AppRadius.brSm,
        ),
      ),
      children: [
        for (var i = 0; i < count; i++)
          Center(
            child: Text(
              labelFor(i),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleSm.copyWith(
                color:
                    i == selected ? AppColors.primary : AppColors.textPrimary,
                fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// ── SuggestPickInput: busca + chips (sugestões/catálogo) + adicionar livre ──

class _SuggestPick extends StatefulWidget {
  const _SuggestPick(
      {required this.step,
      required this.input,
      required this.onSubmit,
      required this.enabled,
      this.initialAnswer});
  final ConversationStep step;
  final SuggestPickInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;
  final StepAnswer? initialAnswer;

  @override
  State<_SuggestPick> createState() => _SuggestPickState();
}

class _SuggestPickState extends State<_SuggestPick> {
  final _search = TextEditingController();
  final List<String> _selected = [];
  late List<String> _suggestions = widget.input.suggestions;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Edição: reabre com o que já estava selecionado (nomes da resposta).
    final init = widget.initialAnswer?.value;
    if (init is List) _selected.addAll(init.map((e) => e.toString()));
    final loader = widget.input.suggestionsLoader;
    if (loader != null) {
      _loading = true;
      loader().then((s) {
        if (!mounted) return;
        setState(() {
          if (s.isNotEmpty) _suggestions = s;
          _loading = false;
        });
      }).catchError((_) {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String name) {
    setState(() {
      if (_selected.contains(name)) {
        _selected.remove(name);
      } else {
        final max = widget.input.maxSelections;
        if (max != null && _selected.length >= max) return;
        _selected.add(name);
      }
    });
  }

  void _addFree() {
    final t = _search.text.trim();
    if (t.isEmpty) return;
    setState(() {
      if (!_selected.contains(t)) _selected.add(t);
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    // Pool = sugestões + catálogo, filtrado pela busca; já selecionados primeiro.
    final pool = <String>{..._selected, ..._suggestions, ...widget.input.catalog};
    final visible = pool
        .where((s) => query.isEmpty || s.toLowerCase().contains(query))
        .take(12)
        .toList();
    final hasExactMatch =
        pool.any((s) => s.toLowerCase() == query) || query.isEmpty;
    final min = widget.input.minSelections;
    final canConfirm = widget.input.allowEmpty || _selected.length >= (min > 0 ? min : 1);

    return Container(
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.input.allowFreeText || widget.input.catalog.isNotEmpty)
            _SearchField(
              controller: _search,
              hint: widget.input.searchHint,
              enabled: widget.enabled,
              onChanged: (_) => setState(() {}),
              onSubmitted: widget.input.allowFreeText ? (_) => _addFree() : null,
            ),
          if (_loading) ...[
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary)),
              const SizedBox(width: AppSpacing.sm),
              Text('Carregando sugestões…', style: AppTextStyles.bodySm),
            ]),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final s in visible)
                TrilhaChip(
                  label: s,
                  selected: _selected.contains(s),
                  enabled: widget.enabled,
                  onTap: () => _toggle(s),
                ),
              if (widget.input.allowFreeText && query.isNotEmpty && !hasExactMatch)
                TrilhaChip(
                  label: '+ ${_search.text.trim()}',
                  selected: false,
                  enabled: widget.enabled,
                  onTap: _addFree,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _InlineCta(
                  label: _selected.isEmpty
                      ? (min > 0 ? 'Escolha ao menos $min' : 'Continuar')
                      : (min > 0 && _selected.length < min
                          ? 'Faltam ${min - _selected.length}'
                          : 'Continuar (${_selected.length})'),
                  onTap: (widget.enabled && canConfirm)
                      ? () => widget.onSubmit(StepAnswer.choice(
                          widget.step.id,
                          [for (final s in _selected) StepOption(id: s, label: s)]))
                      : null,
                ),
              ),
              if (widget.input.allowEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                _SkipButton(
                  onTap: () =>
                      widget.onSubmit(StepAnswer.choice(widget.step.id, const [])),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── AsyncSuggestInput: carrega sugestões → vira SuggestPick ─────────────────

class _AsyncSuggest extends StatefulWidget {
  const _AsyncSuggest(
      {required this.step,
      required this.input,
      required this.onSubmit,
      required this.enabled,
      this.initialAnswer});
  final ConversationStep step;
  final AsyncSuggestInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;
  final StepAnswer? initialAnswer;

  @override
  State<_AsyncSuggest> createState() => _AsyncSuggestState();
}

class _AsyncSuggestState extends State<_AsyncSuggest> {
  List<String>? _loaded;

  @override
  void initState() {
    super.initState();
    widget.input.load().then((s) {
      if (mounted) setState(() => _loaded = s);
    }).catchError((_) {
      if (mounted) setState(() => _loaded = const <String>[]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _loaded;
    if (loaded == null) {
      return Container(
        padding: AppSpacing.allBase,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(widget.input.loadingHint, style: AppTextStyles.bodySm)),
        ]),
      );
    }
    // Delega ao SuggestPick (opcional → pode pular).
    return _SuggestPick(
      step: widget.step,
      input: SuggestPickInput(
        suggestions: loaded,
        catalog: widget.input.catalog,
        allowEmpty: true,
        minSelections: widget.input.minSelections,
        searchHint: 'Buscar ou adicionar…',
      ),
      onSubmit: widget.onSubmit,
      enabled: widget.enabled,
      initialAnswer: widget.initialAnswer,
    );
  }
}

// ── AsyncPickInput: busca assíncrona (typeahead) — única, submete ao tocar ──

class _AsyncPick extends StatefulWidget {
  const _AsyncPick(
      {required this.step,
      required this.input,
      required this.onSubmit,
      required this.enabled,
      this.initialAnswer});
  final ConversationStep step;
  final AsyncPickInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;
  final StepAnswer? initialAnswer;

  @override
  State<_AsyncPick> createState() => _AsyncPickState();
}

class _AsyncPickState extends State<_AsyncPick> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<PickSuggestion> _results = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Edição: reabre com o valor já escolhido no campo (sem re-disparar busca —
    // setar .text não chama onChanged). O usuário vê o atual e pode manter
    // ("Usar …") ou apagar e buscar outro.
    final label = widget.initialAnswer?.displayText;
    if (label != null && label.isNotEmpty) _search.text = label;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    setState(() {});
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final r = await widget.input.search(query);
        if (mounted) {
          setState(() {
            _results = r;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _results = const [];
            _loading = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim();
    return Container(
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchField(
            controller: _search,
            hint: widget.input.searchHint,
            enabled: widget.enabled,
            onChanged: _onChanged,
          ),
          if (_loading) ...[
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary)),
              const SizedBox(width: AppSpacing.sm),
              Text(widget.input.loadingHint, style: AppTextStyles.bodySm),
            ]),
          ],
          for (final r in _results)
            _ResultTile(
              label: r.label,
              onTap: () => widget.onSubmit(StepAnswer.pick(widget.step.id,
                  label: r.label, value: r.value)),
            ),
          if (widget.input.allowFreeText && q.length >= 2 && !_loading)
            _ResultTile(
              label: 'Usar "$q"',
              icon: Icons.add_rounded,
              onTap: () => widget.onSubmit(
                  StepAnswer.pick(widget.step.id, label: q, value: q)),
            ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon ?? Icons.place_outlined,
                size: 18, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child: Text(label,
                    style: AppTextStyles.bodyMd
                        .copyWith(color: AppColors.textPrimary))),
          ],
        ),
      ),
    );
  }
}

// ── Campo de busca compartilhado ────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.onChanged,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              size: 18, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction:
                  onSubmitted != null ? TextInputAction.done : TextInputAction.search,
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle:
                    AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
