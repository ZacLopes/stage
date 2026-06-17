// EditListModal — modal genérico pra editar listas simples (Skills, Interests,
// Certifications, Awards, Coursework).
//
// Mesmo padrão visual do _ManageTagsSheet (educação): header com X circular,
// "Adicionar novo" + botão + circular, chips com X pra remover, "Salvar" pill.

import 'package:flutter/material.dart';
import '../../../../core/theme/theme.dart';

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
  final void Function(List<String> updatedItems) onSave;

  const EditListModal({
    super.key,
    required this.title,
    required this.inputLabel,
    required this.initialItems,
    this.suggestions = const [],
    required this.onSave,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String inputLabel,
    required List<String> initialItems,
    List<String> suggestions = const [],
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

  @override
  void initState() {
    super.initState();
    _items = [...widget.initialItems];
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

  void _add() {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    if (_items.contains(v)) {
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
  static String _fold(String s) => s.toLowerCase().replaceAll(RegExp('[áàâã]'), 'a').replaceAll(RegExp('[éê]'), 'e').replaceAll('í', 'i').replaceAll(RegExp('[óôõ]'), 'o').replaceAll('ú', 'u').replaceAll('ç', 'c');

  List<String> get _filteredSuggestions {
    final q = _fold(_input.text.trim());
    if (q.isEmpty || widget.suggestions.isEmpty) return const [];
    final added = _items.map(_fold).toSet();
    final out = <String>[];
    for (final s in widget.suggestions) {
      if (out.length >= 6) break;
      final fs = _fold(s);
      if (fs.contains(q) && !added.contains(fs)) out.add(s);
    }
    return out;
  }

  void _addSuggestion(String s) {
    if (!_items.contains(s)) setState(() => _items.add(s));
    _input.clear();
    _focus.requestFocus();
  }

  void _save() {
    final v = _input.text.trim();
    final finalList = (v.isNotEmpty && !_items.contains(v)) ? [..._items, v] : _items;
    widget.onSave(finalList);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _input.text.trim().isNotEmpty;
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
                  onPressed: _hasPending ? _save : null,
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
