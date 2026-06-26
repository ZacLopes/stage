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

import 'package:flutter/material.dart';

import '../../../../../core/theme/theme.dart';
import '../../../domain/conversation_step.dart';

/// Dispatcher: renderiza o widget inline certo pro [step.input].
class InlineStepInput extends StatelessWidget {
  const InlineStepInput({
    super.key,
    required this.step,
    required this.onSubmit,
    this.enabled = true,
  });

  final ConversationStep step;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final input = step.input;
    // Nível de idioma vira SLIDER (mockup), mesmo sendo ChoiceInput no domínio.
    if (input is ChoiceInput &&
        input.compact &&
        step.id.startsWith('lang.level.')) {
      return _LevelSlider(step: step, input: input, onSubmit: onSubmit, enabled: enabled);
    }
    return switch (input) {
      ChoiceInput() =>
        _ChoiceChips(step: step, input: input, onSubmit: onSubmit, enabled: enabled),
      GuidedTextInput() =>
        _GuidedText(step: step, input: input, onSubmit: onSubmit, enabled: enabled),
      MonthYearInput() =>
        _MonthYear(step: step, input: input, onSubmit: onSubmit, enabled: enabled),
      SuggestPickInput() =>
        _SuggestPick(step: step, input: input, onSubmit: onSubmit, enabled: enabled),
      AsyncSuggestInput() =>
        _AsyncSuggest(step: step, input: input, onSubmit: onSubmit, enabled: enabled),
      AsyncPickInput() =>
        _AsyncPick(step: step, input: input, onSubmit: onSubmit, enabled: enabled),
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
      required this.enabled});
  final ConversationStep step;
  final ChoiceInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;

  @override
  State<_ChoiceChips> createState() => _ChoiceChipsState();
}

class _ChoiceChipsState extends State<_ChoiceChips> {
  final Set<String> _selected = {};

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
      required this.enabled});
  final ConversationStep step;
  final ChoiceInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;

  @override
  State<_LevelSlider> createState() => _LevelSliderState();
}

class _LevelSliderState extends State<_LevelSlider> {
  late int _index = (widget.input.options.length / 2).floor();

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
      required this.enabled});
  final ConversationStep step;
  final GuidedTextInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;

  @override
  State<_GuidedText> createState() => _GuidedTextState();
}

class _GuidedTextState extends State<_GuidedText> {
  final _controller = TextEditingController();

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
            maxLines: 5,
            maxLength: widget.input.maxLength,
            onChanged: (_) => setState(() {}),
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: widget.input.hint ?? 'Escreva aqui…',
              hintStyle: AppTextStyles.bodyMd
                  .copyWith(color: AppColors.textTertiary),
              isDense: true,
              border: InputBorder.none,
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
      required this.enabled});
  final ConversationStep step;
  final MonthYearInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;

  @override
  State<_MonthYear> createState() => _MonthYearState();
}

class _MonthYearState extends State<_MonthYear> {
  static const _months = [
    'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
  ];
  int? _month;
  int? _year;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = [
      for (var y = now.year; y >= now.year - widget.input.yearsBack; y--) y,
    ];
    final ready = _month != null && _year != null;
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
          Text('Mês', style: AppTextStyles.overline),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var m = 1; m <= 12; m++)
                TrilhaChip(
                  label: _months[m - 1],
                  selected: _month == m,
                  enabled: widget.enabled,
                  onTap: () => setState(() => _month = m),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Ano', style: AppTextStyles.overline),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: years.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, i) => TrilhaChip(
                label: '${years[i]}',
                selected: _year == years[i],
                enabled: widget.enabled,
                onTap: () => setState(() => _year = years[i]),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _InlineCta(
                  label: 'Confirmar',
                  onTap: (widget.enabled && ready)
                      ? () => widget.onSubmit(StepAnswer.monthYear(
                          widget.step.id, _year!, _month!))
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
}

// ── SuggestPickInput: busca + chips (sugestões/catálogo) + adicionar livre ──

class _SuggestPick extends StatefulWidget {
  const _SuggestPick(
      {required this.step,
      required this.input,
      required this.onSubmit,
      required this.enabled});
  final ConversationStep step;
  final SuggestPickInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;

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
      required this.enabled});
  final ConversationStep step;
  final AsyncSuggestInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;

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
    );
  }
}

// ── AsyncPickInput: busca assíncrona (typeahead) — única, submete ao tocar ──

class _AsyncPick extends StatefulWidget {
  const _AsyncPick(
      {required this.step,
      required this.input,
      required this.onSubmit,
      required this.enabled});
  final ConversationStep step;
  final AsyncPickInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;

  @override
  State<_AsyncPick> createState() => _AsyncPickState();
}

class _AsyncPickState extends State<_AsyncPick> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<PickSuggestion> _results = const [];
  bool _loading = false;

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
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
