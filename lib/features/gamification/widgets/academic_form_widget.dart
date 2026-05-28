import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'month_year_picker_sheet.dart';
import '../../../core/theme/theme.dart';

class AcademicFormWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String? initialValue;

  const AcademicFormWidget({
    super.key,
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<AcademicFormWidget> createState() => _AcademicFormWidgetState();
}

class _AcademicFormWidgetState extends State<AcademicFormWidget> {
  final _institutionController = TextEditingController();
  final _courseController = TextEditingController();
  String _status = 'Cursando';
  DateTime _startDate = DateTime(DateTime.now().year - 2, 3);
  DateTime _endDate = DateTime(DateTime.now().year + 2, 12);
  String _semester = '3º Sem';
  String _period = 'Noturno';

  static const _semesters = ['1º Sem', '2º Sem', '3º Sem', '4º Sem', '5º Sem', '6º Sem', '7º Sem', '8º Sem', 'Finalizando'];
  static const _periods = ['Matutino', 'Vespertino', 'Noturno', 'Integral', 'EAD'];
  static const _statuses = ['Cursando', 'Concluído', 'Trancado'];

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final data = jsonDecode(widget.initialValue!);
        _institutionController.text = data['institution_name'] ?? '';
        _courseController.text = data['course_name'] ?? '';
        _status = data['course_status'] ?? 'Cursando';
        _semester = data['semester'] ?? '3º Sem';
        _period = data['period'] ?? 'Noturno';
        if (data['course_start_mm_yyyy'] != null) _startDate = _parseDate(data['course_start_mm_yyyy']);
        if (data['course_end_mm_yyyy'] != null) _endDate = _parseDate(data['course_end_mm_yyyy']);
      } catch (_) {}
    }
    _institutionController.addListener(_emitIfValid);
    _courseController.addListener(_emitIfValid);
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitIfValid());
  }

  @override
  void dispose() {
    _institutionController.dispose();
    _courseController.dispose();
    super.dispose();
  }

  DateTime _parseDate(String s) {
    try {
      final parts = s.split('/');
      return DateTime(int.parse(parts[1]), int.parse(parts[0]));
    } catch (_) {
      return DateTime.now();
    }
  }

  String _formatDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  int _durationMonths() {
    final months = (_endDate.year - _startDate.year) * 12 + _endDate.month - _startDate.month;
    return months < 0 ? 0 : months;
  }

  void _emitIfValid() {
    if (_institutionController.text.length >= 2 && _courseController.text.length >= 2) {
      widget.onSelect(jsonEncode({
        'institution_name': _institutionController.text.trim(),
        'course_name': _courseController.text.trim(),
        'course_status': _status,
        'course_start_mm_yyyy': _formatDate(_startDate),
        'course_end_mm_yyyy': _formatDate(_endDate),
        'duration_months': _durationMonths(),
        'semester': _semester,
        'period': _period,
      }));
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showMonthYearPickerSheet(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = DateTime(_startDate.year + 2, _startDate.month);
          }
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _startDate = DateTime(_endDate.year - 2, _endDate.month);
          }
        }
      });
      _emitIfValid();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card institution + course
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.info],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.badge, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                const Text('CARTEIRINHA ESTUDANTIL',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13)),
              ]),
              const SizedBox(height: 20),
              _cardField('INSTITUIÇÃO DE ENSINO', _institutionController, Icons.account_balance),
              const SizedBox(height: 14),
              _cardField('NOME DO CURSO', _courseController, Icons.menu_book),
              const SizedBox(height: 20),
              const Text('STATUS', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _statuses.map((s) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _statusChip(s),
                  )).toList(),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Dates row
        _sectionLabel('PERÍODO DO CURSO'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _dateCard('INÍCIO', _startDate, true)),
          const SizedBox(width: 12),
          Expanded(child: _dateCard('FIM', _endDate, false)),
        ]),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Duração: ${_durationLabel()}',
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ),

        const SizedBox(height: 24),

        // Semester
        _sectionLabel('SEMESTRE ATUAL'),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _semesters.map((s) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _selectChip(s, _semester == s, () {
                setState(() => _semester = s);
                _emitIfValid();
              }),
            )).toList(),
          ),
        ),

        const SizedBox(height: 24),

        // Period
        _sectionLabel('PERÍODO'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _periods.map((p) => _selectChip(p, _period == p, () {
            setState(() => _period = p);
            _emitIfValid();
          })).toList(),
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  Widget _cardField(String label, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: TextField(
            controller: controller,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Digite aqui...',
              hintStyle: const TextStyle(color: AppColors.borderStrong),
              prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String label) {
    final selected = _status == label;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _status = label);
        _emitIfValid();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(20),
          border: selected ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? AppColors.primary : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            )),
      ),
    );
  }

  Widget _dateCard(String label, DateTime date, bool isStart) {
    return GestureDetector(
      onTap: () => _pickDate(isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 2),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: AppColors.textDisabled, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(_formatDate(date),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Icon(Icons.calendar_today, color: AppColors.primary, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _selectChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 2,
          ),
          boxShadow: selected ? [] : [const BoxShadow(color: AppColors.border, offset: Offset(0, 3), blurRadius: 0)],
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            )),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
  );

  String _durationLabel() {
    final months = _durationMonths();
    final y = months ~/ 12;
    final m = months % 12;
    if (y == 0 && m == 0) return '0 meses';
    final parts = <String>[];
    if (y > 0) parts.add('$y ${y == 1 ? 'ano' : 'anos'}');
    if (m > 0) parts.add('$m ${m == 1 ? 'mês' : 'meses'}');
    return parts.join(' e ');
  }
}
