// AddEditEducationModal — bottom sheet pra criar/editar Education.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../auth/auth_session.dart';
import '../../../gamification/widgets/month_year_picker_sheet.dart';
import '../../domain/entities/entities.dart';
import '../../../../core/theme/theme.dart';

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

const _educationLevelSchool = 'school';
const _educationLevelCollege = 'college';
const _educationStatusStudying = 'studying';
const _educationStatusPaused = 'paused';
const _educationStatusGraduated = 'graduated';

const _educationLevelOptions = [
  _DropdownOption(value: _educationLevelCollege, label: 'Faculdade'),
  _DropdownOption(value: _educationLevelSchool, label: 'Escola'),
];

const _schoolStatusOptions = [
  _DropdownOption(value: _educationStatusStudying, label: 'Cursando'),
  _DropdownOption(value: _educationStatusGraduated, label: 'Concluída'),
];

const _collegeStatusOptions = [
  _DropdownOption(value: _educationStatusStudying, label: 'Em andamento'),
  _DropdownOption(value: _educationStatusPaused, label: 'Trancada'),
  _DropdownOption(value: _educationStatusGraduated, label: 'Concluída'),
];

const _kBorderColor = AppColors.border;
const _kLabelColor = AppColors.textTertiary;
const _kHintColor = AppColors.textDisabled;
const _kTextColor = AppColors.textPrimary;
const _kAccent = AppColors.primary;
const _kError = AppColors.error;
const _kChipBg = AppColors.background;

/// Normaliza o degree pra um dos itens de [_degrees]. O extract-profile da OpenAI
/// devolve strings livres em inglês (ex: "Bachelor's degree in Business
/// Administration"); o DropdownButtonFormField exige valor exato da lista,
/// senão assert. Mapeamento conservador → fallback 'Outro'.
String? _normalizeDegree(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  if (_degrees.contains(raw)) return raw;
  final l = raw.toLowerCase();
  if (l.contains('mba')) return 'MBA';
  if (l.contains('phd') || l.contains('ph.d') || l.contains('doutor')) {
    return 'Doutorado';
  }
  if (l.contains('mestrado') ||
      l.contains('master') ||
      l.contains('msc') ||
      l.contains('m.sc')) {
    return 'Mestrado';
  }
  if (l.contains('licenciatura')) return 'Licenciatura';
  if (l.contains('tecnólog') || l.contains('technolog')) return 'Tecnólogo';
  if (l.contains('técnico') ||
      l.contains('technical') ||
      l.contains('technician')) {
    return 'Técnico';
  }
  if (l.contains('bacharel') ||
      l.contains('bachelor') ||
      l.contains('graduação') ||
      l.contains('graduacao') ||
      l.contains('undergrad') ||
      l.contains('b.sc') ||
      l.contains('b.a')) {
    return 'Bacharelado';
  }
  return 'Outro';
}

class AddEditEducationModal extends StatefulWidget {
  final Education? initial;
  final void Function(
    Education updated,
    List<String> majors,
    List<String> minors,
    List<String> activities,
  )
  onSave;
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
    required void Function(Education, List<String>, List<String>, List<String>)
    onSave,
    void Function()? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
  late String _educationLevel;
  late String _educationStatus;
  String? _degree;
  late List<String> _majors;
  late List<String> _minors;
  late List<String> _activities;
  int? _semester;
  int? _schoolYear;
  DateTime? _startDate;
  DateTime? _endDate;
  late final TextEditingController _gpa;
  late final TextEditingController _maxGpa;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _educationLevel = _initialEducationLevel(i);
    _educationStatus = _initialEducationStatus(i, _educationLevel);
    _institution = TextEditingController(text: i?.institution ?? '');
    _location = TextEditingController(text: i?.location ?? '');
    _degree = _normalizeDegree(i?.degree);
    _majors = i?.majors.map((m) => m.name).toList() ?? <String>[];
    _minors = i?.minors.map((m) => m.name).toList() ?? <String>[];
    _activities = i?.activities.map((a) => a.text).toList() ?? <String>[];
    _semester = i?.currentSemester;
    _schoolYear = i?.currentSchoolYear;
    if (_isCollege && _needsSemester) _semester ??= 1;
    if (_isSchool && _educationStatus == _educationStatusStudying) {
      _schoolYear ??= 1;
    }
    _startDate = i?.startDate;
    _endDate = i?.endDate;
    _gpa = TextEditingController(text: i?.gpa?.toString() ?? '');
    _maxGpa = TextEditingController(text: i?.maxGpa?.toString() ?? '');
    _institution.addListener(() => setState(() {}));
    _location.addListener(() => setState(() {}));
    _gpa.addListener(() => setState(() {}));
    _maxGpa.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _institution.dispose();
    _location.dispose();
    _gpa.dispose();
    _maxGpa.dispose();
    super.dispose();
  }

  bool get _isSchool => _educationLevel == _educationLevelSchool;
  bool get _isCollege => _educationLevel == _educationLevelCollege;
  bool get _needsSemester =>
      _isCollege &&
      (_educationStatus == _educationStatusStudying ||
          _educationStatus == _educationStatusPaused);

  bool get _canSave {
    if (_institution.text.trim().isEmpty) return false;
    if (_isSchool) {
      return _educationStatus != _educationStatusStudying ||
          _schoolYear != null;
    }
    return _degree != null &&
        _majors.isNotEmpty &&
        (!_needsSemester || _semester != null);
  }

  String get _institutionLabel =>
      _isSchool ? 'Nome da escola' : 'Nome da faculdade';

  List<_DropdownOption> get _statusOptions =>
      _isSchool ? _schoolStatusOptions : _collegeStatusOptions;

  static String _initialEducationLevel(Education? education) {
    final raw = education?.educationLevel;
    if (raw == _educationLevelSchool || raw == _educationLevelCollege) {
      return raw!;
    }
    if (education?.currentSchoolYear != null) return _educationLevelSchool;
    return _educationLevelCollege;
  }

  static String _initialEducationStatus(Education? education, String level) {
    final raw = education?.educationStatus;
    final allowed = level == _educationLevelSchool
        ? _schoolStatusOptions
        : _collegeStatusOptions;
    if (allowed.any((option) => option.value == raw)) return raw!;
    final endDate = education?.endDate;
    if (endDate != null && endDate.isBefore(DateTime.now())) {
      return _educationStatusGraduated;
    }
    return _educationStatusStudying;
  }

  void _setEducationLevel(String? value) {
    if (value == null) return;
    setState(() {
      _educationLevel = value;
      final allowed = _statusOptions;
      if (!allowed.any((option) => option.value == _educationStatus)) {
        _educationStatus = _educationStatusStudying;
      }
      if (_isSchool && _educationStatus == _educationStatusStudying) {
        _schoolYear ??= 1;
      }
      if (_needsSemester) _semester ??= 1;
    });
  }

  void _setEducationStatus(String? value) {
    if (value == null) return;
    setState(() {
      _educationStatus = value;
      if (_isSchool && _educationStatus == _educationStatusStudying) {
        _schoolYear ??= 1;
      }
      if (_needsSemester) _semester ??= 1;
    });
  }

  Future<void> _pickStart() async {
    FocusScope.of(context).unfocus();
    final r = await showMonthYearPickerSheet(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
    );
    if (r != null) setState(() => _startDate = r);
  }

  Future<void> _pickEnd() async {
    FocusScope.of(context).unfocus();
    final r = await showMonthYearPickerSheet(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
    );
    if (r != null) setState(() => _endDate = r);
  }

  void _handleSave() {
    final userId = currentUserIdOrNull();
    if (userId == null) {
      // ignore: unawaited_futures
      handleSessionLost(context);
      return;
    }
    final base = widget.initial;
    final isSchool = _isSchool;
    final edu = Education(
      id: base?.id ?? '',
      userId: base?.userId ?? userId,
      institution: _institution.text.trim(),
      educationLevel: _educationLevel,
      educationStatus: _educationStatus,
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      degree: isSchool ? 'Ensino médio' : _degree,
      currentSemester: _needsSemester ? _semester : null,
      currentSchoolYear:
          isSchool && _educationStatus == _educationStatusStudying
          ? _schoolYear
          : null,
      startDate: _startDate,
      endDate: _endDate,
      gpa: double.tryParse(_gpa.text.replaceAll(',', '.')),
      maxGpa: double.tryParse(_maxGpa.text.replaceAll(',', '.')),
      orderIndex: base?.orderIndex ?? 0,
      confidence: base?.confidence,
    );
    widget.onSave(
      edu,
      isSchool ? const <String>[] : _majors,
      isSchool ? const <String>[] : _minors,
      _activities,
    );
    Navigator.of(context).pop();
  }

  String? _gpaError() {
    final g = double.tryParse(_gpa.text.replaceAll(',', '.'));
    final m = double.tryParse(_maxGpa.text.replaceAll(',', '.'));
    if (g == null || m == null) return null;
    if (m <= 0) return null;
    if (g > m) return 'GPA acima do máximo';
    if (g > 10) return 'GPA parece alto demais';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.92,
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _UnderlineOptionDropdown(
                          label: 'Tipo de formação',
                          value: _educationLevel,
                          items: _educationLevelOptions,
                          onChanged: _setEducationLevel,
                        ),
                        const SizedBox(height: 20),
                        _UnderlineField(
                          controller: _institution,
                          label: _institutionLabel,
                          required: true,
                          capitalize: true,
                        ),
                        const SizedBox(height: 20),
                        _UnderlineOptionDropdown(
                          label: 'Situação',
                          value: _educationStatus,
                          items: _statusOptions,
                          onChanged: _setEducationStatus,
                        ),
                        if (_isSchool &&
                            _educationStatus == _educationStatusStudying) ...[
                          const SizedBox(height: 20),
                          _StepSliderField(
                            label: 'Ano da escola',
                            value: _schoolYear ?? 1,
                            min: 1,
                            max: 3,
                            labelBuilder: (value) => '$valueº ano',
                            onChanged: (value) =>
                                setState(() => _schoolYear = value),
                          ),
                        ],
                        if (_isCollege) ...[
                          const SizedBox(height: 20),
                          _UnderlineDropdown(
                            label: 'Tipo de diploma',
                            required: true,
                            value: _degree,
                            items: _degrees,
                            onChanged: (v) => setState(() => _degree = v),
                          ),
                          const SizedBox(height: 24),
                          _InlineTagList(
                            label: 'Cursos principais',
                            required: true,
                            items: _majors,
                            hintText: 'Ex: Administração',
                            onChanged: (l) => setState(() => _majors = l),
                          ),
                          if (_needsSemester) ...[
                            const SizedBox(height: 24),
                            _StepSliderField(
                              label: _educationStatus == _educationStatusPaused
                                  ? 'Último semestre cursado'
                                  : 'Semestre atual',
                              value: _semester ?? 1,
                              min: 1,
                              max: 12,
                              labelBuilder: (value) => '$valueº semestre',
                              onChanged: (value) =>
                                  setState(() => _semester = value),
                            ),
                          ],
                        ],
                        const SizedBox(height: 20),
                        _UnderlineField(
                          controller: _location,
                          label: 'Localização',
                          capitalize: true,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _DateField(
                                label: 'Início',
                                required: true,
                                value: _startDate,
                                onTap: _pickStart,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _DateField(
                                label: 'Fim (ou previsto)',
                                value: _endDate,
                                onTap: _pickEnd,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _UnderlineField(
                                controller: _gpa,
                                label: 'GPA',
                                numeric: true,
                                errorText: _gpaError(),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _UnderlineField(
                                controller: _maxGpa,
                                label: 'GPA máximo',
                                numeric: true,
                                errorText: _gpaError(),
                              ),
                            ),
                          ],
                        ),
                        if (_isCollege) ...[
                          const SizedBox(height: 24),
                          _InlineTagList(
                            label: 'Cursos secundários',
                            items: _minors,
                            hintText: 'Ex: Finanças',
                            onChanged: (l) => setState(() => _minors = l),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _InlineTagList(
                          label: 'Atividades',
                          items: _activities,
                          hintText: 'Ex: Atlética, Empresa Júnior',
                          onChanged: (l) => setState(() => _activities = l),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _canSave ? _handleSave : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kAccent.withValues(alpha: 0.4),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      'Salvar',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        _CircleIconButton(
          icon: Icons.close_rounded,
          color: _kTextColor,
          onTap: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Center(
            child: Text(
              widget.initial == null ? 'Adicionar formação' : 'Editar formação',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _kTextColor,
              ),
            ),
          ),
        ),
        if (widget.onDelete != null)
          _CircleIconButton(
            icon: Icons.delete_outline_rounded,
            color: _kError,
            onTap: () {
              widget.onDelete!();
              Navigator.of(context).pop();
            },
          )
        else
          const SizedBox(width: 40),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CircleIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

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
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _FieldLabel({required this.text, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 13,
          color: _kLabelColor,
          fontWeight: FontWeight.w500,
        ),
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: _kError, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}

class _DropdownOption {
  final String value;
  final String label;

  const _DropdownOption({required this.value, required this.label});
}

class _UnderlineField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final bool capitalize;
  final bool numeric;
  final String? errorText;

  const _UnderlineField({
    required this.controller,
    required this.label,
    this.required = false,
    this.capitalize = false,
    this.numeric = false,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label, required: required),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          textCapitalization: capitalize
              ? TextCapitalization.words
              : TextCapitalization.none,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
              : null,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _kTextColor,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: controller.text.isEmpty
                ? null
                : GestureDetector(
                    onTap: () => controller.clear(),
                    child: const Icon(
                      Icons.cancel,
                      color: _kHintColor,
                      size: 20,
                    ),
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: hasError ? _kError : _kBorderColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: hasError ? _kError : _kAccent,
                width: 1.5,
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: const TextStyle(color: _kError, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _UnderlineOptionDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<_DropdownOption> items;
  final ValueChanged<String?> onChanged;

  const _UnderlineOptionDropdown({
    required this.label,
    required this.items,
    required this.onChanged,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _kHintColor,
          ),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _kTextColor,
          ),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: _kBorderColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: _kAccent, width: 1.5),
            ),
          ),
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item.value,
                  child: Text(item.label),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _UnderlineDropdown extends StatelessWidget {
  final String label;
  final bool required;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _UnderlineDropdown({
    required this.label,
    required this.items,
    required this.onChanged,
    this.value,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label, required: required),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _kHintColor,
          ),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _kTextColor,
          ),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: _kBorderColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: _kAccent, width: 1.5),
            ),
          ),
          items: items
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _StepSliderField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String Function(int value) labelBuilder;
  final ValueChanged<int> onChanged;

  const _StepSliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: _kChipBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorderColor),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      labelBuilder(min),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: value == min ? _kAccent : _kHintColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      labelBuilder(value),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _kAccent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      labelBuilder(max),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: value == max ? _kAccent : _kHintColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: _kAccent,
                  inactiveTrackColor: _kBorderColor,
                  thumbColor: _kAccent,
                  overlayColor: _kAccent.withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 9,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                  tickMarkShape: const RoundSliderTickMarkShape(
                    tickMarkRadius: 2,
                  ),
                  activeTickMarkColor: Colors.white.withValues(alpha: 0.65),
                  inactiveTickMarkColor: _kHintColor.withValues(alpha: 0.45),
                ),
                child: Slider(
                  value: value.clamp(min, max).toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: max - min,
                  onChanged: (next) => onChanged(next.round()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final bool required;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label, required: required),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorderColor)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  color: _kHintColor,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value == null ? '--/--' : _fmt(value!),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: value == null ? _kHintColor : _kTextColor,
                    ),
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _kHintColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }
}

/// Preview inline de tags. Mostra chips + lápis. Tocar em qualquer lugar
/// da linha abre o `_ManageTagsSheet` em modal full-screen pra editar.
class _InlineTagList extends StatelessWidget {
  final String label;
  final bool required;
  final List<String> items;
  final String hintText;
  final ValueChanged<List<String>> onChanged;

  const _InlineTagList({
    required this.label,
    required this.items,
    required this.onChanged,
    this.hintText = 'Digite aqui...',
    this.required = false,
  });

  Future<void> _openSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ManageTagsSheet(
        title: 'Gerenciar ${label.toLowerCase()}',
        sectionLabel: label,
        addPlaceholder: hintText,
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openSheet(context),
      borderRadius: BorderRadius.circular(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(text: label, required: required),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorderColor)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            hintText,
                            style: const TextStyle(
                              color: _kHintColor,
                              fontSize: 15,
                            ),
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: items
                              .map((item) => _previewChip(item))
                              .toList(),
                        ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.edit_outlined,
                    color: _kLabelColor,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewChip(String item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _kChipBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        item,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          color: _kTextColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Modal full-screen pra gerenciar tags. Espelha o design da referência:
/// header com X centralizado, "Adicionar novo" com input + botão circular,
/// lista de chips removíveis e botão "Concluir" no rodapé.
///
/// Mantém uma cópia local da lista — só propaga ao parent via [onChanged]
/// quando o user toca em "Concluir". Fechar pelo X descarta.
class _ManageTagsSheet extends StatefulWidget {
  final String title;
  final String sectionLabel;
  final String addPlaceholder;
  final List<String> items;
  final ValueChanged<List<String>> onChanged;

  const _ManageTagsSheet({
    required this.title,
    required this.sectionLabel,
    required this.addPlaceholder,
    required this.items,
    required this.onChanged,
  });

  @override
  State<_ManageTagsSheet> createState() => _ManageTagsSheetState();
}

class _ManageTagsSheetState extends State<_ManageTagsSheet> {
  late List<String> _items;
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _items = [...widget.items];
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

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

  bool get _itemsChanged {
    if (_items.length != widget.items.length) return true;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i] != widget.items[i]) return true;
    }
    return false;
  }

  bool get _hasPending => _input.text.trim().isNotEmpty || _itemsChanged;

  void _done() {
    final v = _input.text.trim();
    final finalList = (v.isNotEmpty && !_items.contains(v))
        ? [..._items, v]
        : _items;
    widget.onChanged(finalList);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _input.text.trim().isNotEmpty;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.92,
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _CircleIconButton(
                      icon: Icons.close_rounded,
                      color: _kTextColor,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _kTextColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: const _FieldLabel(text: 'Adicionar novo'),
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
                        style: const TextStyle(
                          fontSize: 17,
                          color: _kTextColor,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.addPlaceholder,
                          hintStyle: const TextStyle(
                            color: _kHintColor,
                            fontWeight: FontWeight.w500,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: _kBorderColor),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: _kAccent, width: 1.5),
                          ),
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
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _FieldLabel(text: widget.sectionLabel),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _items.map((item) => _sheetChip(item)).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _hasPending ? _done : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kAccent.withValues(alpha: 0.4),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      'Concluir',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Chip do sheet: texto sem ellipsis (quebra linha se preciso) pra user
  // poder verificar conteúdo completo da extração da IA.
  Widget _sheetChip(String item) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 40,
      ),
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
                style: const TextStyle(
                  fontSize: 14,
                  color: _kTextColor,
                  fontWeight: FontWeight.w500,
                ),
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
