// EditListModal — modal genérico pra editar listas simples (Skills, Interests,
// Coursework, Awards descritivos). Reusa o DynamicListInputWidget da gamificação.

import 'package:flutter/material.dart';
import '../../../gamification/widgets/dynamic_list_input_widget.dart';

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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => EditListModal(
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

  @override
  void initState() {
    super.initState();
    _items = [...widget.initialItems];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: media.viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: DynamicListInputWidget(
                  inputLabel: widget.inputLabel,
                  hintText: widget.inputLabel,
                  initialValue: _items,
                  suggestions: widget.suggestions,
                  onSelect: (list) => setState(() => _items = list),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  widget.onSave(_items);
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C27A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Salvar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
