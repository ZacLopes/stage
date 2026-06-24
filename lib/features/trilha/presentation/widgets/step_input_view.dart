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
  int? _myMonth;
  int? _myYear;

  /// Carregamento das sugestões assíncronas (AsyncSuggestInput) do passo atual.
  Future<List<String>>? _suggestFuture;

  /// Sugestões carregadas por SuggestPickInput.suggestionsLoader (ex.: skills
  /// pela área). Nulo enquanto carrega → usa o placeholder estático.
  List<String>? _loadedSuggestions;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() => setState(() {}));
    _maybeStartAsyncLoad();
  }

  @override
  void didUpdateWidget(StepInputView old) {
    super.didUpdateWidget(old);
    // Passo novo → limpa o estado de seleção/texto e (re)dispara o load async.
    if (old.step.id != widget.step.id) {
      _selectedIds.clear();
      _textController.clear();
      _myMonth = null;
      _myYear = null;
      _maybeStartAsyncLoad();
    }
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
        // Selecionadas (toque pra remover).
        if (_selectedIds.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _selectedIds
                .map((name) => AppChip(
                      label: name,
                      selected: true,
                      onTap: widget.enabled ? () => _togglePick(name) : null,
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
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
        // Resultados (buscando) ou sugestões (vazio) — toque pra adicionar.
        if (options.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
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
        ],
        const SizedBox(height: AppSpacing.base),
        PrimaryButton(
          label: _selectedIds.isNotEmpty
              ? 'Continuar (${_selectedIds.length})'
              : (input.allowEmpty ? 'Pular' : 'Continuar'),
          onPressed:
              (!widget.enabled || (_selectedIds.isEmpty && !input.allowEmpty))
                  ? null
                  : () => _submitSuggestPick(input),
        ),
      ],
    );
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
    setState(() =>
        _selectedIds.removeWhere((p) => p.toLowerCase() == name.toLowerCase()));
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
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
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
        // Picker opcional (pode pular), com busca/texto livre sobre o catálogo.
        return _buildSuggestPick(SuggestPickInput(
          suggestions: suggestions,
          catalog: input.catalog,
          allowEmpty: true,
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
          label: 'Enviar',
          onPressed: (text.isEmpty || !widget.enabled)
              ? null
              : () => widget.onSubmit(StepAnswer.text(widget.step.id, text)),
        ),
      ],
    );
  }

  // ── Mês/Ano ──────────────────────────────────────────────────────────────
  static const _monthLabels = [
    'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
  ];

  Widget _buildMonthYear(MonthYearInput input) {
    final nowYear = DateTime.now().year;
    final years = [for (var y = nowYear; y >= nowYear - input.yearsBack; y--) y];
    final ready = _myMonth != null && _myYear != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _picker<int>(
                hint: 'Mês',
                value: _myMonth,
                items: [
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem(value: m, child: Text(_monthLabels[m - 1])),
                ],
                onChanged:
                    widget.enabled ? (v) => setState(() => _myMonth = v) : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _picker<int>(
                hint: 'Ano',
                value: _myYear,
                items: [
                  for (final y in years)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged:
                    widget.enabled ? (v) => setState(() => _myYear = v) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.base),
        PrimaryButton(
          label: 'Confirmar',
          onPressed: (ready && widget.enabled)
              ? () => widget.onSubmit(
                  StepAnswer.monthYear(widget.step.id, _myYear!, _myMonth!))
              : null,
        ),
      ],
    );
  }

  Widget _picker<T>({
    required String hint,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          hint: Text(hint,
              style:
                  AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary)),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
