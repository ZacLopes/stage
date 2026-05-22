// AddEditExperienceModal — bottom sheet pra criar/editar Experience com bullets.
//
// Bullets aqui são edição local — o ProfileEditorViewModel decide se chama
// add/update/delete individualmente OU se replace tudo via replaceProfile.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../gamification/widgets/month_year_picker_sheet.dart';
import '../../domain/entities/entities.dart';

class AddEditExperienceModal extends StatefulWidget {
  final Experience? initial;
  final void Function(Experience updated, List<String> bulletTexts) onSave;
  final void Function()? onDelete;

  const AddEditExperienceModal({
    super.key,
    this.initial,
    required this.onSave,
    this.onDelete,
  });

  static Future<void> show({
    required BuildContext context,
    Experience? initial,
    required void Function(Experience, List<String>) onSave,
    void Function()? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddEditExperienceModal(
        initial: initial,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<AddEditExperienceModal> createState() => _AddEditExperienceModalState();
}

class _AddEditExperienceModalState extends State<AddEditExperienceModal> {
  late final TextEditingController _title;
  late final TextEditingController _company;
  late final TextEditingController _location;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isCurrent = false;
  late List<TextEditingController> _bullets;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _title = TextEditingController(text: i?.title ?? '');
    _company = TextEditingController(text: i?.company ?? '');
    _location = TextEditingController(text: i?.location ?? '');
    _startDate = i?.startDate;
    _endDate = i?.endDate;
    _isCurrent = i?.isCurrent ?? false;
    final initBullets = i?.bullets.map((b) => b.text).toList() ?? <String>[];
    _bullets = initBullets.map((t) => TextEditingController(text: t)).toList();
    if (_bullets.isEmpty) {
      _bullets.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _company.dispose();
    _location.dispose();
    for (final b in _bullets) {
      b.dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      _title.text.trim().isNotEmpty &&
      _company.text.trim().isNotEmpty &&
      _startDate != null &&
      (_isCurrent || _endDate != null);

  Future<void> _pickStart() async {
    final result = await showMonthYearPickerSheet(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
    );
    if (result != null) setState(() => _startDate = result);
  }

  Future<void> _pickEnd() async {
    final result = await showMonthYearPickerSheet(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
    );
    if (result != null) setState(() => _endDate = result);
  }

  void _handleSave() {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final exp = (widget.initial ??
            Experience(
              id: '', userId: userId,
              title: '', company: '',
              startDate: _startDate!,
            ))
        .copyWith(
      title: _title.text.trim(),
      company: _company.text.trim(),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      startDate: _startDate,
      endDate: _isCurrent ? null : _endDate,
      isCurrent: _isCurrent,
    );
    final bulletTexts = _bullets
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    widget.onSave(exp, bulletTexts);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.initial == null ? 'Adicionar experiência' : 'Editar experiência',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                    onPressed: () {
                      widget.onDelete!();
                      Navigator.of(context).pop();
                    },
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
                    _textField(_title, 'Cargo *', capitalize: true),
                    const SizedBox(height: 12),
                    _textField(_company, 'Empresa *', capitalize: true),
                    const SizedBox(height: 12),
                    _textField(_location, 'Localização', capitalize: true),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dateField('Início *', _startDate, _pickStart)),
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
                    const SizedBox(height: 8),
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
                        const Text('Atualmente trabalho aqui'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Responsabilidades',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(_bullets.length, (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 14),
                                child: Text('•', style: TextStyle(fontSize: 18)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _bullets[i],
                                  decoration: InputDecoration(
                                    hintText: 'Descreva uma responsabilidade...',
                                    filled: true,
                                    fillColor: const Color(0xFFF9FAFB),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                    ),
                                  ),
                                  maxLines: 3,
                                  minLines: 1,
                                  textCapitalization: TextCapitalization.sentences,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: const Color(0xFFEF4444),
                                onPressed: _bullets.length > 1
                                    ? () => setState(() {
                                          _bullets[i].dispose();
                                          _bullets.removeAt(i);
                                        })
                                    : null,
                              ),
                            ],
                          ),
                        )),
                    TextButton.icon(
                      icon: const Icon(Icons.add, color: Color(0xFF00C27A)),
                      label: const Text(
                        'Adicionar responsabilidade',
                        style: TextStyle(color: Color(0xFF00C27A)),
                      ),
                      onPressed: () => setState(() {
                        _bullets.add(TextEditingController());
                      }),
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

  Widget _textField(TextEditingController c, String label, {bool capitalize = false}) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        filled: true, fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true, fillColor: const Color(0xFFF9FAFB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          value == null ? 'Selecionar...' : _formatMonthYear(value),
          style: TextStyle(
            color: value == null ? const Color(0xFF9CA3AF) : Colors.black,
          ),
        ),
      ),
    );
  }

  String _formatMonthYear(DateTime d) {
    const months = ['', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
    return '${months[d.month]} ${d.year}';
  }
}
