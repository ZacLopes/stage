// AddEditLanguageModal — bottom sheet pra criar/editar Language.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/entities.dart';
import '../../../../core/theme/theme.dart';

class AddEditLanguageModal extends StatefulWidget {
  final Language? initial;
  final void Function(Language) onSave;
  final void Function()? onDelete;

  const AddEditLanguageModal({
    super.key,
    this.initial,
    required this.onSave,
    this.onDelete,
  });

  static Future<void> show({
    required BuildContext context,
    Language? initial,
    required void Function(Language) onSave,
    void Function()? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AddEditLanguageModal(
        initial: initial,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<AddEditLanguageModal> createState() => _AddEditLanguageModalState();
}

class _AddEditLanguageModalState extends State<AddEditLanguageModal> {
  late final TextEditingController _name;
  LanguageProficiency? _proficiency;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _proficiency = widget.initial?.proficiency;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  void _handleSave() {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final lang = (widget.initial ??
            Language(id: '', userId: userId, name: ''))
        .copyWith(
      name: _name.text.trim(),
      proficiency: _proficiency,
    );
    widget.onSave(lang);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.initial == null ? 'Adicionar idioma' : 'Editar idioma',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () {
                    widget.onDelete!();
                    Navigator.of(context).pop();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Idioma',
              hintText: 'Ex: Inglês',
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nível',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: LanguageProficiency.values.map((p) {
              final selected = _proficiency == p;
              return ChoiceChip(
                label: Text(_proficiencyLabel(p)),
                selected: selected,
                onSelected: (v) => setState(() => _proficiency = v ? p : null),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _canSave ? _handleSave : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.borderStrong,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Salvar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _proficiencyLabel(LanguageProficiency p) {
    switch (p) {
      case LanguageProficiency.native: return 'Nativo';
      case LanguageProficiency.fluent: return 'Fluente';
      case LanguageProficiency.advanced: return 'Avançado';
      case LanguageProficiency.intermediate: return 'Intermediário';
      case LanguageProficiency.basic: return 'Básico';
    }
  }
}
