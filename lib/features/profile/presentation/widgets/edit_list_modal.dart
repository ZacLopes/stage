// EditListModal — modal genérico pra editar listas simples (Skills, Interests,
// Certifications, Awards, Coursework).
//
// Mesmo padrão visual do _ManageTagsSheet (educação): header com X circular,
// "Adicionar novo" + botão + circular, chips com X pra remover, "Salvar" pill.

import 'package:flutter/material.dart';
import '../../../../core/theme/theme.dart';
import '../../domain/skill_name_normalizer.dart';

const _kBorderColor = AppColors.border;
const _kLabelColor = AppColors.textTertiary;
const _kHintColor = AppColors.textDisabled;
const _kTextColor = AppColors.textPrimary;
const _kAccent = AppColors.primary;
const _kChipBg = AppColors.background;

class EditListModal extends StatefulWidget {
  final String title;
  final String inputLabel;
  final List<String> initialItems;
  final List<String> suggestions;
  final String? guidanceText;
  final int? recommendedMinItems;
  final int? maxItems;
  final void Function(List<String> updatedItems) onSave;

  const EditListModal({
    super.key,
    required this.title,
    required this.inputLabel,
    required this.initialItems,
    this.suggestions = const [],
    this.guidanceText,
    this.recommendedMinItems,
    this.maxItems,
    required this.onSave,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String inputLabel,
    required List<String> initialItems,
    List<String> suggestions = const [],
    String? guidanceText,
    int? recommendedMinItems,
    int? maxItems,
    required void Function(List<String>) onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditListModal(
        title: title,
        inputLabel: inputLabel,
        initialItems: initialItems,
        suggestions: suggestions,
        guidanceText: guidanceText,
        recommendedMinItems: recommendedMinItems,
        maxItems: maxItems,
        onSave: onSave,
      ),
    );
  }

  @override
  State<EditListModal> createState() => _EditListModalState();
}

class _EditListModalState extends State<EditListModal> {
  late List<String> _items;
  final _input = TextEditingController();
  final _focus = FocusNode();
  late int _duplicatesGrouped;

  @override
  void initState() {
    super.initState();
    _items = normalizeSkillNames(widget.initialItems);
    _duplicatesGrouped = widget.initialItems
            .where((item) => cleanSkillName(item).isNotEmpty)
            .length -
        _items.length;
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _sectionLabel {
    final t = widget.title.trim();
    final stripped = t.toLowerCase().startsWith('editar ') ? t.substring(7) : t;
    if (stripped.isEmpty) return stripped;
    return stripped[0].toUpperCase() + stripped.substring(1);
  }

  bool get _itemsChanged {
    if (_items.length != widget.initialItems.length) return true;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i] != widget.initialItems[i]) return true;
    }
    return false;
  }

  bool get _hasPending => _input.text.trim().isNotEmpty || _itemsChanged;

  bool get _withinLimit =>
      widget.maxItems == null || _items.length <= widget.maxItems!;

  bool get _atLimit =>
      widget.maxItems != null && _items.length >= widget.maxItems!;

  bool get _hasBlockedInput {
    final value = cleanSkillName(_input.text);
    return value.isNotEmpty && !_containsEquivalent(value) && _atLimit;
  }

  bool _containsEquivalent(String value) {
    final key = foldSkillName(value);
    return key.isNotEmpty && _items.any((item) => foldSkillName(item) == key);
  }

  void _add() {
    final v = cleanSkillName(_input.text);
    if (v.isEmpty || _atLimit) return;
    if (_containsEquivalent(v)) {
      _input.clear();
      return;
    }
    setState(() => _items.add(v));
    _input.clear();
    _focus.requestFocus();
  }

  void _remove(String item) {
    setState(() => _items.remove(item));
  }

  // Typeahead (P5 Fase C): sugere canônicas do catálogo conforme digita.
  // Acento-insensível e case-insensível; exclui já-adicionados; teto de 6.
  // Sem suggestions (flag OFF) → bloco não renderiza, input texto-livre normal.
  List<String> get _filteredSuggestions {
    final q = foldSkillName(_input.text);
    if (q.isEmpty || widget.suggestions.isEmpty) return const [];
    final added = _items.map(foldSkillName).toSet();
    final out = <String>[];
    for (final s in widget.suggestions) {
      if (out.length >= 6) break;
      final fs = foldSkillName(s);
      if (fs.contains(q) && !added.contains(fs)) out.add(s);
    }
    return out;
  }

  void _addSuggestion(String s) {
    if (_atLimit) return;
    final clean = cleanSkillName(s);
    if (!_containsEquivalent(clean)) setState(() => _items.add(clean));
    _input.clear();
    _focus.requestFocus();
  }

  void _save() {
    final v = cleanSkillName(_input.text);
    if (_hasBlockedInput) return;
    final canAppend = v.isNotEmpty && !_containsEquivalent(v) && !_atLimit;
    final finalList = normalizeSkillNames(canAppend ? [..._items, v] : _items);
    if (widget.maxItems != null && finalList.length > widget.maxItems!) return;
    widget.onSave(finalList);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pendingText = cleanSkillName(_input.text);
    final canAdd = pendingText.isNotEmpty &&
        !_containsEquivalent(pendingText) &&
        !_atLimit;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _CircleIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kTextColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
              if (widget.guidanceText != null || widget.maxItems != null) ...[
                const SizedBox(height: 16),
                _ListGuidance(
                  text: widget.guidanceText,
                  count: _items.length,
                  recommendedMin: widget.recommendedMinItems,
                  max: widget.maxItems,
                ),
              ],
              if (_duplicatesGrouped > 0) ...[
                const SizedBox(height: 8),
                Text(
                  _duplicatesGrouped == 1
                      ? '1 duplicata equivalente foi agrupada. Revise e salve para confirmar.'
                      : '$_duplicatesGrouped duplicatas equivalentes foram agrupadas. Revise e salve para confirmar.',
                  style: const TextStyle(color: _kLabelColor, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: _FieldLabel(text: 'Adicionar novo'),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _add(),
                      style: const TextStyle(fontSize: 17, color: _kTextColor, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: widget.inputLabel,
                        hintStyle: const TextStyle(color: _kHintColor, fontWeight: FontWeight.w500),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _kBorderColor)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _kAccent, width: 1.5)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: canAdd ? _add : null,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: canAdd ? _kAccent : _kChipBg,
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        color: canAdd ? Colors.white : _kHintColor,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
              if (_filteredSuggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _filteredSuggestions
                        .map(
                          (s) => GestureDetector(
                            onTap: () => _addSuggestion(s),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: _kChipBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _kBorderColor),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.add_rounded, size: 14, color: _kAccent),
                                  const SizedBox(width: 4),
                                  Text(
                                    s,
                                    style: const TextStyle(fontSize: 13, color: _kTextColor, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              if (_items.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      'Nada adicionado ainda',
                      style: TextStyle(color: _kHintColor.withValues(alpha: 0.8), fontSize: 14),
                    ),
                  ),
                )
              else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: _FieldLabel(text: _sectionLabel),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _items.map(_chip).toList(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _hasPending && _withinLimit && !_hasBlockedInput
                      ? _save
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _kAccent.withValues(alpha: 0.4),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: const Text('Salvar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _chip(String item) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: _kChipBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                item,
                style: const TextStyle(fontSize: 14, color: _kTextColor, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _remove(item),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 16, color: _kLabelColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListGuidance extends StatelessWidget {
  final String? text;
  final int count;
  final int? recommendedMin;
  final int? max;

  const _ListGuidance({
    required this.text,
    required this.count,
    required this.recommendedMin,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    final overLimit = max != null && count > max!;
    final belowRecommended = recommendedMin != null && count < recommendedMin!;
    final color = overLimit
        ? AppColors.error
        : (belowRecommended ? AppColors.warning : _kAccent);
    final status = overLimit
        ? 'Remova ${count - max!} para salvar.'
        : (belowRecommended
            ? 'Você pode adicionar mais ${recommendedMin! - count}.'
            : null);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (text != null)
                  Text(text!, style: const TextStyle(color: _kTextColor, fontSize: 12, height: 1.35, fontWeight: FontWeight.w500)),
                if (status != null) ...[
                  if (text != null) const SizedBox(height: 4),
                  Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          if (max != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count/$max', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ],
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

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
          child: Icon(icon, color: _kTextColor, size: 22),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, color: _kLabelColor, fontWeight: FontWeight.w500),
    );
  }
}
