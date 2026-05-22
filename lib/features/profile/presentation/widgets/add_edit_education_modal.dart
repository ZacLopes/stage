// AddEditEducationModal — bottom sheet pra criar/editar Education.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../gamification/widgets/month_year_picker_sheet.dart';
import '../../../gamification/widgets/dynamic_list_input_widget.dart';
import '../../domain/entities/entities.dart';

const _degrees = [
  'Técnico',
  'Bacharelado',
  'Licenciatura',
  'Tecnólogo',
  'MBA',
  'Mestrado',
  'Doutorado',
  'Outro',
];

class AddEditEducationModal extends StatefulWidget {
  final Education? initial;
  final void Function(Education updated, List<String> majors, List<String> minors, List<String> activities) onSave;
  final void Function()? onDelete;

  const AddEditEducationModal({
    super.key,
    this.initial,
    required this.onSave,
    this.onDelete,
  });

  static Future<void> show({
    required BuildContext context,
    Education? initial,
    required void Function(Education, List<String>, List<String>, List<String>) onSave,
    void Function()? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddEditEducationModal(
        initial: initial,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<AddEditEducationModal> createState() => _AddEditEducationModalState();
}

class _AddEditEducationModalState extends State<AddEditEducationModal> {
  late final TextEditingController _institution;
  late final TextEditingController _location;
  String? _degree;
  late List<String> _majors;
  late List<String> _minors;
  late List<String> _activities;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isCurrent = false;
  late final TextEditingController _gpa;
  late final TextEditingController _maxGpa;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _institution = TextEditingController(text: i?.institution ?? '');
    _location = TextEditingController(text: i?.location ?? '');
    _degree = i?.degree;
    _majors = i?.majors.map((m) => m.name).toList() ?? <String>[];
    _minors = i?.minors.map((m) => m.name).toList() ?? <String>[];
    _activities = i?.activities.map((a) => a.text).toList() ?? <String>[];
    _startDate = i?.startDate;
    _endDate = i?.endDate;
    _isCurrent = i?.endDate == null && i?.startDate != null;
    _gpa = TextEditingController(text: i?.gpa?.toString() ?? '');
    _maxGpa = TextEditingController(text: i?.maxGpa?.toString() ?? '');
  }

  @override
  void dispose() {
    _institution.dispose();
    _location.dispose();
    _gpa.dispose();
    _maxGpa.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _institution.text.trim().isNotEmpty && _degree != null && _majors.isNotEmpty;

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
    final edu = (widget.initial ??
            Education(id: '', userId: userId, institution: ''))
        .copyWith(
      institution: _institution.text.trim(),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      degree: _degree,
      startDate: _startDate,
      endDate: _isCurrent ? null : _endDate,
      gpa: double.tryParse(_gpa.text.replaceAll(',', '.')),
      maxGpa: double.tryParse(_maxGpa.text.replaceAll(',', '.')),
    );
    widget.onSave(edu, _majors, _minors, _activities);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
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
                    widget.initial == null ? 'Adicionar formação' : 'Editar formação',
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
                    _tf(_institution, 'Instituição *', capitalize: true),
                    const SizedBox(height: 12),
                    _tf(_location, 'Localização', capitalize: true),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _degree,
                      decoration: _decoration('Tipo de diploma *'),
                      items: _degrees.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                      onChanged: (v) => setState(() => _degree = v),
                    ),
                    const SizedBox(height: 12),
                    const Text('Cursos principais *', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DynamicListInputWidget(
                      inputLabel: 'Curso principal',
                      hintText: 'Ex: Administração',
                      initialValue: _majors,
                      onSelect: (l) => setState(() => _majors = l),
                    ),
                    const SizedBox(height: 12),
                    const Text('Cursos secundários', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DynamicListInputWidget(
                      inputLabel: 'Curso secundário',
                      initialValue: _minors,
                      onSelect: (l) => setState(() => _minors = l),
                    ),
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
                        const Text('Estou cursando'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _tf(_gpa, 'GPA', numeric: true)),
                        const SizedBox(width: 12),
                        Expanded(child: _tf(_maxGpa, 'GPA máximo', numeric: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Atividades', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DynamicListInputWidget(
                      inputLabel: 'Atividade',
                      hintText: 'Ex: Atlética, Empresa Júnior',
                      initialValue: _activities,
                      onSelect: (l) => setState(() => _activities = l),
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

  Widget _tf(TextEditingController c, String label, {bool capitalize = false, bool numeric = false}) {
    return TextField(
      controller: c,
      decoration: _decoration(label),
      textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
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
