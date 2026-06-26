// Renderiza a ENTRADA inline de um passo da conversa (o "widget-first"):
// traduz um [StepInput] no widget certo (chips de escolha / texto guiado) e
// devolve um [StepAnswer] via [onSubmit]. Reusa o design system
// (AppChip, PrimaryButton, AppTextField). PLANO-FASE-6 T6.3.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/conversation_step.dart';
import 'chat_bubbles.dart';

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

  /// Selecionados que estão SAINDO (animação de remoção) antes de saírem da lista.
  final Set<String> _exiting = {};
  final TextEditingController _textController = TextEditingController();
  int? _myMonth;
  int? _myYear;

  /// Carregamento das sugestões assíncronas (AsyncSuggestInput) do passo atual.
  Future<List<String>>? _suggestFuture;

  /// Sugestões carregadas por SuggestPickInput.suggestionsLoader (ex.: skills
  /// pela área). Nulo enquanto carrega → usa o placeholder estático.
  List<String>? _loadedSuggestions;

  /// Debounce do autosave do rascunho de texto guiado.
  Timer? _draftTimer;
  static const _draftPrefix = 'trilha_draft_';
  String get _draftKey => '$_draftPrefix${widget.step.id}';

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _restoreDraft();
    _maybeStartAsyncLoad();
  }

  @override
  void didUpdateWidget(StepInputView old) {
    super.didUpdateWidget(old);
    // Passo novo → limpa o estado de seleção/texto e (re)dispara o load async.
    if (old.step.id != widget.step.id) {
      _selectedIds.clear();
      _draftTimer?.cancel();
      _textController.clear();
      _myMonth = null;
      _myYear = null;
      _restoreDraft(); // recupera rascunho salvo deste passo (se houver)
      _maybeStartAsyncLoad();
    }
  }

  // Autosave do texto em andamento (só GuidedTextInput): se o SO mata o app com
  // o teclado aberto, o rascunho volta na reabertura. Persiste no device, com
  // debounce; limpa ao enviar/pular.
  void _onTextChanged() {
    setState(() {});
    if (widget.step.input is GuidedTextInput) {
      _draftTimer?.cancel();
      _draftTimer = Timer(const Duration(milliseconds: 400), _saveDraft);
    }
  }

  // Failure-safe: rascunho é conveniência; erro de storage nunca trava a trilha.
  Future<void> _restoreDraft() async {
    if (widget.step.input is! GuidedTextInput) return;
    final key = _draftKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(key);
      if (saved != null &&
          saved.isNotEmpty &&
          mounted &&
          key == _draftKey && // o passo não mudou durante o await
          _textController.text.isEmpty) {
        _textController.text = saved;
      }
    } catch (_) {/* sem rascunho, segue normal */}
  }

  Future<void> _saveDraft() async {
    if (widget.step.input is! GuidedTextInput) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = _textController.text;
      if (t.isEmpty) {
        await prefs.remove(_draftKey);
      } else {
        await prefs.setString(_draftKey, t);
      }
    } catch (_) {/* ignora */}
  }

  Future<void> _clearDraft(String stepId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_draftPrefix$stepId');
    } catch (_) {/* ignora */}
  }

  void _maybeStartAsyncLoad() {
    final input = widget.step.input;
    _suggestFuture = input is AsyncSuggestInput ? input.load() : null;
    _loadedSuggestions = null;
    if (input is SuggestPickInput && input.suggestionsLoader != null) {
      input.suggestionsLoader!().then((r) {
        if (mounted) setState(() => _loadedSuggestions = r);
      }).catchError((_) {
        // mantém o placeholder estático
      });
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.step.input;
    return switch (input) {
      ChoiceInput() => _buildChoice(input),
      GuidedTextInput() => _buildGuidedText(input),
      MonthYearInput() => _buildMonthYear(input),
      SuggestPickInput() => _buildSuggestPick(input),
      AsyncSuggestInput() => _buildAsyncSuggest(input),
    };
  }

  // ── Escolha ──────────────────────────────────────────────────────────────
  Widget _buildChoice(ChoiceInput input) {
    // Escolha ÚNICA (tocar já avança). compact = chips (escala/nível);
    // 1 opção = CTA de largura cheia; 2+ = tiles empilhados.
    if (!input.multi) {
      if (input.compact) {
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: input.options
              .map((o) => AppChip(
                    label: o.label,
                    disabled: !widget.enabled,
                    onTap: () => _onChipTap(input, o),
                  ))
              .toList(),
        );
      }
      if (input.options.length == 1) {
        final o = input.options.first;
        return PrimaryButton(
          label: o.label,
          onPressed: widget.enabled ? () => _onChipTap(input, o) : null,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < input.options.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _OptionTile(
              label: input.options[i].label,
              subtitle: input.options[i].subtitle,
              onTap: widget.enabled
                  ? () => _onChipTap(input, input.options[i])
                  : null,
            ),
          ],
        ],
      );
    }

    // Multisseleção: chips + botão de confirmar (com contador).
    final chips = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: input.options.map((o) {
        final selected = _selectedIds.contains(o.id);
        return AppChip(
          label: o.label,
          selected: selected,
          disabled: !widget.enabled ||
              (!selected &&
                  input.maxSelections != null &&
                  _selectedIds.length >= input.maxSelections!),
          onTap: () => _onChipTap(input, o),
        );
      }).toList(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        chips,
        const SizedBox(height: AppSpacing.base),
        PrimaryButton(
          label: _selectedIds.isEmpty
              ? 'Continuar'
              : 'Continuar (${_selectedIds.length})',
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

  // ── Sugestões + busca no catálogo + adicionar livre ──────────────────────
  // O "meio-termo": chips sugeridos (reconhecer) + typeahead local sobre o
  // catálogo (ajudar a completar) + adicionar qualquer termo (autonomia, nunca
  // trava). Aqui `_selectedIds` guarda NOMES (não ids de opção). O listener do
  // _textController (initState) re-renderiza a cada tecla → filtro ao vivo.
  Widget _buildSuggestPick(SuggestPickInput input) {
    final query = _textController.text.trim();
    final lower = query.toLowerCase();
    final atMax = input.maxSelections != null &&
        _selectedIds.length >= input.maxSelections!;

    // Sugestões efetivas: as carregadas (ex.: pela área) substituem o estático.
    final effectiveSuggestions =
        (_loadedSuggestions != null && _loadedSuggestions!.isNotEmpty)
            ? _loadedSuggestions!
            : input.suggestions;
    // Pool = sugestões + catálogo, dedup case-insensitive (sugestões primeiro).
    final seen = <String>{};
    final pool = <String>[];
    for (final s in [...effectiveSuggestions, ...input.catalog]) {
      final k = s.toLowerCase().trim();
      if (k.isEmpty || seen.contains(k)) continue;
      seen.add(k);
      pool.add(s);
    }
    bool isPicked(String s) =>
        _selectedIds.any((p) => p.toLowerCase() == s.toLowerCase());

    final searching = query.isNotEmpty;
    final options = searching
        ? pool.where((s) => s.toLowerCase().contains(lower) && !isPicked(s)).take(10).toList()
        : pool.where((s) => !isPicked(s)).take(12).toList();
    final exact = pool.any((s) => s.toLowerCase() == lower) || isPicked(query);
    final showFreeAdd = input.allowFreeText && searching && !exact && !atMax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selecionadas (toque pra remover) — altura amortecida.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _selectedIds.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _selectedIds
                        .map((name) => _AnimatedChip(
                              key: ValueKey(name),
                              exiting: _exiting.contains(name),
                              child: AppChip(
                                label: name,
                                selected: true,
                                onTap: widget.enabled
                                    ? () => _togglePick(name)
                                    : null,
                              ),
                            ))
                        .toList(),
                  ),
                ),
        ),
        // Busca.
        AppTextField(
          controller: _textController,
          hint: input.searchHint,
          prefixIcon: const Icon(Icons.search_rounded,
              size: 20, color: AppColors.textTertiary),
          enabled: widget.enabled && !atMax,
        ),
        // "+ Adicionar 'X'" (texto livre — o backend canoniza).
        if (showFreeAdd)
          Align(
            alignment: Alignment.centerLeft,
            child: GhostButton(
              label: 'Adicionar "$query"',
              icon: Icons.add_rounded,
              onPressed: () => _addPick(query),
            ),
          ),
        // Resultados (buscando) ou sugestões (vazio) — altura amortecida.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: options.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: options
                        .map((s) => AppChip(
                              label: s,
                              icon: searching ? null : Icons.add_rounded,
                              disabled: !widget.enabled || atMax,
                              onTap: () => _addPick(s),
                            ))
                        .toList(),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.base),
        PrimaryButton(
          label: _continueLabel(input),
          onPressed:
              _canContinuePick(input) ? () => _submitSuggestPick(input) : null,
        ),
      ],
    );
  }

  /// Mínimo pra liberar o "Continuar": minSelections explícito, senão 0 (se pode
  /// pular) ou 1 (multisseleção comum).
  int _minPick(SuggestPickInput input) =>
      input.minSelections > 0 ? input.minSelections : (input.allowEmpty ? 0 : 1);

  bool _canContinuePick(SuggestPickInput input) =>
      widget.enabled && _selectedIds.length >= _minPick(input);

  String _continueLabel(SuggestPickInput input) {
    final min = _minPick(input);
    final count = _selectedIds.length;
    if (count >= min) return count == 0 ? 'Pular' : 'Continuar ($count)';
    return count == 0 ? 'Escolha pelo menos $min' : 'Faltam ${min - count}';
  }

  void _addPick(String name) {
    final n = name.trim();
    if (n.isEmpty || !widget.enabled) return;
    if (_selectedIds.any((p) => p.toLowerCase() == n.toLowerCase())) return;
    setState(() {
      _selectedIds.add(n);
      _textController.clear();
    });
  }

  void _togglePick(String name) {
    if (_exiting.contains(name)) return; // já saindo
    // Marca como "saindo" (anima encolhendo+fade) e remove de fato ao terminar.
    setState(() => _exiting.add(name));
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _selectedIds.removeWhere((p) => p.toLowerCase() == name.toLowerCase());
        _exiting.remove(name);
      });
    });
  }

  void _submitSuggestPick(SuggestPickInput input) {
    if (_selectedIds.isEmpty) {
      if (!input.allowEmpty) return;
      // Passo opcional (sugestão da IA) → segue sem adicionar.
      widget.onSubmit(StepAnswer(
          stepId: widget.step.id, value: const <String>[], displayText: 'Pular'));
      return;
    }
    final selected =
        _selectedIds.map((n) => StepOption(id: n, label: n)).toList();
    widget.onSubmit(StepAnswer.choice(widget.step.id, selected));
  }

  // ── Sugestões assíncronas (IA) ───────────────────────────────────────────
  // Mostra "carregando" enquanto a IA pensa; depois renderiza as sugestões como
  // um picker OPCIONAL (pode pular). Failure-safe: load() devolve [] em erro.
  Widget _buildAsyncSuggest(AsyncSuggestInput input) {
    return FutureBuilder<List<String>>(
      future: _suggestFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Row(
            children: [
              const TypingDots(dot: 7),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  input.loadingHint,
                  style: AppTextStyles.bodyMd
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          );
        }
        final suggestions = snap.data ?? const <String>[];
        // Picker com busca/texto livre; opcional só se minSelections == 0.
        return _buildSuggestPick(SuggestPickInput(
          suggestions: suggestions,
          catalog: input.catalog,
          allowEmpty: input.minSelections == 0,
          minSelections: input.minSelections,
          searchHint: 'Buscar ou adicionar a sua…',
        ));
      },
    );
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
          label: text.isEmpty && input.optional ? 'Pular' : 'Enviar',
          onPressed: (!widget.enabled || (text.isEmpty && !input.optional))
              ? null
              : () {
                  _clearDraft(widget.step.id); // enviou → não precisa do rascunho
                  widget.onSubmit(text.isEmpty
                      ? StepAnswer(
                          stepId: widget.step.id, value: '', displayText: 'Pular')
                      : StepAnswer.text(widget.step.id, text));
                },
        ),
      ],
    );
  }

  // ── Mês/Ano ──────────────────────────────────────────────────────────────
  static const _monthLabels = [
    'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
  ];

  // Mês/Ano: chips roláveis (mesma linguagem do resto — adeus dropdown nativo).
  Widget _buildMonthYear(MonthYearInput input) {
    final nowYear = DateTime.now().year;
    final years = [for (var y = nowYear; y >= nowYear - input.yearsBack; y--) y];
    final ready = _myMonth != null && _myYear != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pickerLabel('Mês'),
        const SizedBox(height: AppSpacing.xs),
        _chipRow([
          for (var m = 1; m <= 12; m++)
            AppChip(
              label: _monthLabels[m - 1],
              selected: _myMonth == m,
              disabled: !widget.enabled,
              onTap: () => setState(() => _myMonth = m),
            ),
        ]),
        const SizedBox(height: AppSpacing.md),
        _pickerLabel('Ano'),
        const SizedBox(height: AppSpacing.xs),
        _chipRow([
          for (final y in years)
            AppChip(
              label: '$y',
              selected: _myYear == y,
              disabled: !widget.enabled,
              onTap: () => setState(() => _myYear = y),
            ),
        ]),
        const SizedBox(height: AppSpacing.base),
        PrimaryButton(
          label: !ready && input.optional ? 'Pular' : 'Confirmar',
          onPressed: (!widget.enabled || (!ready && !input.optional))
              ? null
              : ready
                  ? () => widget.onSubmit(StepAnswer.monthYear(
                      widget.step.id, _myYear!, _myMonth!))
                  : () => widget.onSubmit(StepAnswer(
                      stepId: widget.step.id, value: '', displayText: 'Pular')),
        ),
      ],
    );
  }

  Widget _pickerLabel(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style:
                AppTextStyles.labelMd.copyWith(color: AppColors.textTertiary)),
      );

  Widget _chipRow(List<Widget> chips) => SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, i) => Center(child: chips[i]),
        ),
      );
}

/// Chip que entra com "pop" (fade + scale) e sai encolhendo+fade ao remover.
class _AnimatedChip extends StatefulWidget {
  const _AnimatedChip({super.key, required this.child, this.exiting = false});

  final Widget child;
  final bool exiting;

  @override
  State<_AnimatedChip> createState() => _AnimatedChipState();
}

class _AnimatedChipState extends State<_AnimatedChip> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _shown && !widget.exiting;
    return AnimatedScale(
      scale: visible ? 1.0 : 0.6,
      duration: const Duration(milliseconds: 200),
      curve: visible ? Curves.easeOutBack : Curves.easeIn,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 180),
        child: widget.child,
      ),
    );
  }
}

/// Opção de escolha única como tile de largura cheia (rótulo + subtítulo
/// opcional), com mola no toque + haptic. Mais "intencional" que um chip solto
/// quando há 2+ opções.
class _OptionTile extends StatefulWidget {
  const _OptionTile({required this.label, this.subtitle, this.onTap});

  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.brLg,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                }
              : null,
          onHighlightChanged:
              enabled ? (v) => setState(() => _pressed = v) : null,
          borderRadius: AppRadius.brLg,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.base,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.brLg,
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: AppTextStyles.titleSm
                            .copyWith(color: AppColors.textPrimary),
                      ),
                      if (widget.subtitle != null &&
                          widget.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: AppTextStyles.bodySm
                              .copyWith(color: AppColors.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    size: 18, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
