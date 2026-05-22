// AddEditProjectModal — bottom sheet pra criar/editar Project.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../gamification/widgets/month_year_picker_sheet.dart';
import '../../domain/entities/entities.dart';

class AddEditProjectModal extends StatefulWidget {
  final Project? initial;
  final void Function(Project) onSave;
  final void Function()? onDelete;

  const AddEditProjectModal({
    super.key,
    this.initial,
    required this.onSave,
    this.onDelete,
  });

  static Future<void> show({
    required BuildContext context,
    Project? initial,
    required void Function(Project) onSave,
    void Function()? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddEditProjectModal(
        initial: initial,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<AddEditProjectModal> createState() => _AddEditProjectModalState();
}

class _AddEditProjectModalState extends State<AddEditProjectModal> {
  late final TextEditingController _name;
  late final TextEditingController _website;
  late final TextEditingController _description;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isCurrent = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.name ?? '');
    _website = TextEditingController(text: i?.website ?? '');
    _description = TextEditingController(text: i?.description ?? '');
    _startDate = i?.startDate;
    _endDate = i?.endDate;
    _isCurrent = i?.isCurrent ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _website.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  Future<void> _pickStart() async {
    final r = await showMonthYearPickerSheet(context: context, initialDate: _startDate ?? DateTime.now());
    if (r != null) setState(() => _startDate = r);
  }

  Future<void> _pickEnd() async {
    final r = await showMonthYearPickerSheet(context: context, initialDate: _endDate ?? DateTime.now());
    if (r != null) setState(() => _endDate = r);
  }

  void _handleSave() {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final p = (widget.initial ?? Project(id: '', userId: userId, name: '')).copyWith(
      name: _name.text.trim(),
      website: _website.text.trim().isEmpty ? null : _website.text.trim(),
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      startDate: _startDate,
      endDate: _isCurrent ? null : _endDate,
      isCurrent: _isCurrent,
    );
    widget.onSave(p);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFD1D5DB), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.initial == null ? 'Adicionar projeto' : 'Editar projeto',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                    onPressed: () { widget.onDelete!(); Navigator.of(context).pop(); },
                  ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tf(_name, 'Nome do projeto *', capitalize: true),
                    const SizedBox(height: 12),
                    _tf(_website, 'Website / Link'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dateField('Início', _startDate, _pickStart)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AbsorbPointer(
                            absorbing: _isCurrent,
                            child: Opacity(
                              opacity: _isCurrent ? 0.4 : 1,
                              child: _dateField('Fim', _endDate, _pickEnd),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: _isCurrent,
                          activeColor: const Color(0xFF00C27A),
                          onChanged: (v) => setState(() {
                            _isCurrent = v ?? false;
                            if (_isCurrent) _endDate = null;
                          }),
                        ),
                        const Text('Em andamento'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _description,
                      decoration: _decoration('Descrição'),
                      maxLines: 5, minLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _canSave ? _handleSave : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C27A),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFD1D5DB),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Salvar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        filled: true, fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      );

  Widget _tf(TextEditingController c, String label, {bool capitalize = false}) {
    return TextField(
      controller: c,
      decoration: _decoration(label),
      textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _decoration(label).copyWith(suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
        child: Text(
          value == null ? 'Selecionar...' : _fmt(value),
          style: TextStyle(color: value == null ? const Color(0xFF9CA3AF) : Colors.black),
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    const m = ['', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
    return '${m[d.month]} ${d.year}';
  }
}
