import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/theme.dart';

/// Captures Harvard-style academic highlights: GPA/CR, distinctions,
/// representative role, relevant coursework. All fields optional —
/// emits as soon as the user types, with debounce.
///
/// Output JSON shape:
/// ```json
/// { "gpa":"8.9", "honors":"...", "rep_role":"...", "coursework":"..." }
/// ```
class AcademicHighlightsFormWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String? initialValue;

  const AcademicHighlightsFormWidget({
    super.key,
    required this.onSelect,
    this.initialValue,
  });

  @override
  State<AcademicHighlightsFormWidget> createState() =>
      _AcademicHighlightsFormWidgetState();
}

class _AcademicHighlightsFormWidgetState
    extends State<AcademicHighlightsFormWidget> {
  final _gpaController = TextEditingController();
  final _honorsController = TextEditingController();
  final _repRoleController = TextEditingController();
  final _courseworkController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final v = jsonDecode(widget.initialValue!);
        if (v is Map) {
          _gpaController.text = (v['gpa'] ?? '').toString();
          _honorsController.text = (v['honors'] ?? '').toString();
          _repRoleController.text = (v['rep_role'] ?? '').toString();
          _courseworkController.text = (v['coursework'] ?? '').toString();
        }
      } catch (_) {}
    }
    _gpaController.addListener(_scheduleEmit);
    _honorsController.addListener(_scheduleEmit);
    _repRoleController.addListener(_scheduleEmit);
    _courseworkController.addListener(_scheduleEmit);
    // Always emit so the question screen accepts even an empty form
    // (all fields optional → user can simply tap Continue).
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gpaController.dispose();
    _honorsController.dispose();
    _repRoleController.dispose();
    _courseworkController.dispose();
    super.dispose();
  }

  void _scheduleEmit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _emit);
  }

  void _emit() {
    widget.onSelect(jsonEncode({
      'gpa': _gpaController.text.trim(),
      'honors': _honorsController.text.trim(),
      'rep_role': _repRoleController.text.trim(),
      'coursework': _courseworkController.text.trim(),
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tudo aqui é opcional. Preencha só o que se aplica — só inclua o '
          'que vai fortalecer seu currículo.',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 24),

        // GPA
        _sectionLabel('CR / GPA (opcional)'),
        const SizedBox(height: 4),
        const Text(
          'Inclua só se for ≥ 8,0/10. Use ponto ou vírgula. Ex: 8.9',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _textField(
          controller: _gpaController,
          hint: '8.9',
          icon: Icons.grade_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
        ),

        const SizedBox(height: 24),

        // Honors / Distinções
        _sectionLabel('Distinções acadêmicas (opcional)'),
        const SizedBox(height: 4),
        const Text(
          'Ex: "1º colocado em 2 semestres", "Bolsa de mérito", "Top 5% da turma"',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _textField(
          controller: _honorsController,
          hint: 'Sua distinção…',
          icon: Icons.emoji_events_outlined,
          maxLines: 2,
        ),

        const SizedBox(height: 24),

        // Representative role
        _sectionLabel('Cargo representativo (opcional)'),
        const SizedBox(height: 4),
        const Text(
          'Ex: "Representante de turma", "Conselho acadêmico", "Diretor da Atlética"',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _textField(
          controller: _repRoleController,
          hint: 'Seu cargo…',
          icon: Icons.groups_outlined,
        ),

        const SizedBox(height: 24),

        // Coursework
        _sectionLabel('Disciplinas relevantes (opcional)'),
        const SizedBox(height: 4),
        const Text(
          'Até 6 disciplinas relevantes para a vaga-alvo, separadas por vírgula. '
          'Ex: Finanças Corporativas, Valuation, Análise de Mercado',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _textField(
          controller: _courseworkController,
          hint: 'Disciplina 1, Disciplina 2…',
          icon: Icons.menu_book_outlined,
          maxLines: 3,
        ),

        const SizedBox(height: 12),
      ],
    );
  }

  Widget _sectionLabel(String label) => Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
          letterSpacing: 1,
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) =>
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.borderStrong),
          prefixIcon: Icon(icon, color: AppColors.textDisabled, size: 20),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.success, width: 2),
          ),
        ),
      );
}
