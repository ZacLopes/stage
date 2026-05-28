import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../../services/ai_service.dart';
import '../../../core/theme/theme.dart';

enum _SuggestState { idle, loading, loaded, error }

class ToolsCatalogWidget extends StatefulWidget {
  final Function(String) onSelect;
  final List<String> categories; // kept for API compatibility
  final String? initialValue;
  final String? campaignId;

  const ToolsCatalogWidget({
    super.key,
    required this.onSelect,
    required this.categories,
    this.initialValue,
    this.campaignId,
  });

  @override
  State<ToolsCatalogWidget> createState() => _ToolsCatalogWidgetState();
}

class _ToolsCatalogWidgetState extends State<ToolsCatalogWidget> {
  final List<Map<String, String>> _items = [];
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _aiService = AIService();

  String? _pendingLevel;
  _SuggestState _suggestState = _SuggestState.idle;
  List<String> _suggestions = [];
  String? _suggestJobContext;

  static const _levels = ['Básico', 'Intermediário', 'Avançado'];

  static const _levelColors = {
    'Básico': AppColors.success,
    'Intermediário': AppColors.warning,
    'Avançado': AppColors.error,
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final List<dynamic> list = jsonDecode(widget.initialValue!);
        for (final item in list) {
          final cat = item['category'] as String? ?? item['tool'] as String? ?? '';
          final level = item['level'] as String? ?? '';
          if (cat.isNotEmpty && level.isNotEmpty) {
            _items.add({'tool': cat, 'level': level});
          }
        }
      } catch (_) {}
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _add() {
    final tool = _controller.text.trim();
    if (tool.isEmpty || _pendingLevel == null) return;
    final duplicate = _items.any(
      (e) => e['tool']!.toLowerCase() == tool.toLowerCase(),
    );
    if (duplicate) return;
    HapticFeedback.lightImpact();
    setState(() {
      _items.add({'tool': tool, 'level': _pendingLevel!});
      _controller.clear();
      _pendingLevel = null;
    });
    _emit();
  }

  void _remove(int index) {
    HapticFeedback.selectionClick();
    setState(() => _items.removeAt(index));
    _emit();
  }

  void _emit() {
    if (_items.isNotEmpty) {
      widget.onSelect(jsonEncode(
        _items.map((e) => {'category': e['tool'], 'level': e['level']}).toList(),
      ));
    }
  }

  void _tapSuggestion(String tool) {
    // If already added, ignore
    if (_items.any((e) => e['tool']!.toLowerCase() == tool.toLowerCase())) return;
    HapticFeedback.selectionClick();
    setState(() {
      _controller.text = tool;
      _pendingLevel = null;
    });
    // Scroll focus to input so user can pick the level
    _focusNode.requestFocus();
  }

  Future<void> _fetchSuggestions() async {
    if (widget.campaignId == null) return;
    setState(() => _suggestState = _SuggestState.loading);
    try {
      final result = await _aiService.suggestTools(widget.campaignId!);
      final tools = (result['tools'] as List).cast<String>();
      setState(() {
        _suggestions = tools;
        _suggestJobContext = result['job_context'] as String?;
        _suggestState = _SuggestState.loaded;
      });
    } catch (_) {
      setState(() => _suggestState = _SuggestState.error);
    }
  }

  bool get _canAdd => _controller.text.trim().isNotEmpty && _pendingLevel != null;

  bool _isAdded(String tool) =>
      _items.any((e) => e['tool']!.toLowerCase() == tool.toLowerCase());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Input card ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _add(),
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Ex: Figma, Python, Excel…',
                  hintStyle: TextStyle(color: AppColors.borderStrong, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'NÍVEL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDisabled,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: _levels.map((level) {
                  final isChosen = _pendingLevel == level;
                  final color = _levelColors[level]!;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _pendingLevel = level);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: EdgeInsets.only(
                          right: level == _levels.last ? 0 : 8,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isChosen ? color : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isChosen ? color : AppColors.border,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          level,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isChosen ? Colors.white : AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _canAdd ? 1.0 : 0.4,
                  child: GestureDetector(
                    onTap: _canAdd ? _add : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Adicionar ferramenta',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Suggestion section ──────────────────────────────────────────
        if (widget.campaignId != null) ...[
          const SizedBox(height: 16),
          _buildSuggestionSection(),
        ],

        // ── Added items list ────────────────────────────────────────────
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'FERRAMENTAS ADICIONADAS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textDisabled,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          ..._items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final level = item['level']!;
            final color = _levelColors[level]!;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item['tool']!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      level,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _remove(index),
                    child: const Icon(Icons.close, size: 18, color: AppColors.borderStrong),
                  ),
                ],
              ),
            );
          }),
        ],

        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSuggestionSection() {
    switch (_suggestState) {
      case _SuggestState.idle:
        return _SuggestionBanner(onTap: _fetchSuggestions);

      case _SuggestState.loading:
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primarySoft, width: 1.5),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Pesquisando ferramentas para a sua vaga…',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );

      case _SuggestState.loaded:
        return _buildSuggestionChips();

      case _SuggestState.error:
        return GestureDetector(
          onTap: _fetchSuggestions,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.warningSoft, width: 1.5),
            ),
            child: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: AppColors.warning, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Não consegui carregar. Toque para tentar de novo.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildSuggestionChips() {
    final headline = _suggestJobContext != null && _suggestJobContext!.isNotEmpty
        ? 'Mais pedidas para $_suggestJobContext'
        : 'Mais pedidas no mercado agora';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primarySoft, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Toque para preencher o campo — depois escolha o nível e adicione.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions.map((tool) {
              final added = _isAdded(tool);
              return GestureDetector(
                onTap: added ? null : () => _tapSuggestion(tool),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: added ? AppColors.primarySoft : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: added ? AppColors.primary : AppColors.borderStrong,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (added) ...[
                        const Icon(Icons.check, size: 13, color: AppColors.primary),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        tool,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: added
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SuggestionBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _SuggestionBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primarySoft, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pesquisamos vagas parecidas com a sua',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3730A3),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Reunimos as ferramentas mais cobradas nas seleções hoje. Quer dar uma olhada?',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Ver ferramentas da minha vaga →',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
