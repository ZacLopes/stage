// EducationScreen — coleta/confirma a situação acadêmica no onboarding.
//
// Caminho manual: usuário preenche escola/faculdade do zero. Caminho upload:
// a tela vem depois da revisão do CV, pré-preenchida com o que a IA extraiu,
// para garantir faculdade/curso/semestre nas tabelas relacionais.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/theme.dart';
import '../../../../services/analytics_service.dart';
import '../../../auth/auth_session.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/data/repositories/profile_repository_supabase.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../../profile/presentation/widgets/institution_typeahead_field.dart';
import '../../utils/onboarding_input_decoration.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import '../preferences/desired_titles_screen.dart';

const _kBorderColor = AppColors.border;
const _kLabelColor = AppColors.textTertiary;
const _kTextColor = AppColors.textPrimary;
const _kAccent = AppColors.primary;

enum _EducationMoment {
  inSchool,
  inCollege,
  collegePaused,
  collegeGraduated,
  notStudying,
}

extension on _EducationMoment {
  String get dbValue {
    switch (this) {
      case _EducationMoment.inSchool:
        return 'in_school';
      case _EducationMoment.inCollege:
        return 'in_college';
      case _EducationMoment.collegePaused:
        return 'college_paused';
      case _EducationMoment.collegeGraduated:
        return 'college_graduated';
      case _EducationMoment.notStudying:
        return 'not_studying';
    }
  }

  String get educationStatus {
    switch (this) {
      case _EducationMoment.inSchool:
      case _EducationMoment.inCollege:
        return 'studying';
      case _EducationMoment.collegePaused:
        return 'paused';
      case _EducationMoment.collegeGraduated:
        return 'graduated';
      case _EducationMoment.notStudying:
        return 'not_studying';
    }
  }

  String get title {
    switch (this) {
      case _EducationMoment.inSchool:
        return 'Estou na escola';
      case _EducationMoment.inCollege:
        return 'Estou na faculdade';
      case _EducationMoment.collegePaused:
        return 'Tranquei a faculdade';
      case _EducationMoment.collegeGraduated:
        return 'Já terminei a faculdade';
      case _EducationMoment.notStudying:
        return 'Não estou estudando agora';
    }
  }

  String get subtitle {
    switch (this) {
      case _EducationMoment.inSchool:
        return 'Ensino médio ou equivalente.';
      case _EducationMoment.inCollege:
        return 'Graduação em andamento.';
      case _EducationMoment.collegePaused:
        return 'Você começou, mas pausou.';
      case _EducationMoment.collegeGraduated:
        return 'Graduação concluída.';
      case _EducationMoment.notStudying:
        return 'Sem escola ou faculdade no momento.';
    }
  }

  IconData get icon {
    switch (this) {
      case _EducationMoment.inSchool:
        return Icons.school_outlined;
      case _EducationMoment.inCollege:
        return Icons.account_balance_outlined;
      case _EducationMoment.collegePaused:
        return Icons.pause_circle_outline_rounded;
      case _EducationMoment.collegeGraduated:
        return Icons.workspace_premium_outlined;
      case _EducationMoment.notStudying:
        return Icons.person_outline_rounded;
    }
  }

  bool get needsSchool => this == _EducationMoment.inSchool;

  bool get needsCollege =>
      this == _EducationMoment.inCollege ||
      this == _EducationMoment.collegePaused ||
      this == _EducationMoment.collegeGraduated;

  bool get needsCourse => needsCollege;

  bool get needsSemester =>
      this == _EducationMoment.inCollege ||
      this == _EducationMoment.collegePaused;

  String get institutionLabel =>
      needsSchool ? 'Nome da escola' : 'Nome da faculdade';

  String get institutionHint =>
      needsSchool ? 'Ex: Colégio Bandeirantes' : 'Ex: USP, Mackenzie, Insper';

  String get semesterLabel => this == _EducationMoment.collegePaused
      ? 'Último semestre cursado'
      : 'Semestre atual';

  String get legacySemesterLabel {
    switch (this) {
      case _EducationMoment.inSchool:
        return 'Estou na escola';
      case _EducationMoment.inCollege:
        return '';
      case _EducationMoment.collegePaused:
        return 'Trancado';
      case _EducationMoment.collegeGraduated:
        return 'Formado';
      case _EducationMoment.notStudying:
        return 'Não estou estudando';
    }
  }
}

class EducationScreen extends StatefulWidget {
  const EducationScreen({super.key});

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  final _schoolController = TextEditingController();
  final _collegeController = TextEditingController();
  final _courseController = TextEditingController();
  final _repo = ProfileRepositorySupabase();

  _EducationMoment? _moment;
  int? _semester;
  int? _schoolYear;

  /// id do catálogo `institutions` quando o user escolhe uma sugestão do
  /// typeahead (Fase 1 T1.6). Null = texto livre. Editar o campo depois de
  /// selecionar limpa (callback do widget).
  String? _collegeInstitutionId;
  bool _saving = false;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
    _schoolController.addListener(_refresh);
    _collegeController.addListener(_refresh);
    _courseController.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  @override
  void dispose() {
    _schoolController.dispose();
    _collegeController.dispose();
    _courseController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _hydrate() async {
    final userId = currentUserIdOrNull();
    if (userId == null) return;
    try {
      final rows = await _repo.getEducation(userId);
      final school = _findSchool(rows);
      final college = _findCollege(rows);
      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('course, semester, gamification_data')
          .eq('id', userId)
          .maybeSingle();
      final gamificationData = Map<String, dynamic>.from(
        (profile?['gamification_data'] as Map?) ?? const {},
      );

      if (!mounted) return;
      setState(() {
        if (school != null) {
          _schoolController.text = school.institution;
          _schoolYear =
              school.currentSchoolYear ??
              _parseSchoolYear(gamificationData['school_year']);
        } else {
          _schoolController.text = _clean(gamificationData['school']) ?? '';
          _schoolYear = _parseSchoolYear(gamificationData['school_year']);
        }

        if (college != null) {
          _collegeController.text = college.institution;
          _collegeInstitutionId = college.institutionId;
          if (college.majors.isNotEmpty) {
            _courseController.text = college.majors.first.name;
          } else {
            _courseController.text = _degreeAsCourse(college.degree) ?? '';
          }
          _semester = college.currentSemester;
        } else {
          _collegeController.text =
              _clean(gamificationData['university']) ?? '';
          _courseController.text = _clean(profile?['course']) ?? '';
          _semester = _parseSemester(
            gamificationData['current_semester'] ?? profile?['semester'],
          );
        }

        _moment =
            _momentFromEducation(school: school, college: college) ??
            _momentFromDb(_clean(gamificationData['education_moment'])) ??
            _momentFromDb(_clean(gamificationData['college_status']));
        if (_moment == _EducationMoment.inSchool) {
          _schoolYear ??= 1;
        }
        if (_moment?.needsSemester == true) {
          _semester ??= 1;
        }
      });
    } catch (_) {
      // Hidratação é best-effort; save ainda valida tudo antes de continuar.
    }
  }

  bool get _canContinue {
    final moment = _moment;
    if (moment == null || _saving) return false;
    if (moment.needsSchool && _schoolController.text.trim().isEmpty) {
      return false;
    }
    if (moment.needsSchool && _schoolYear == null) return false;
    if (moment.needsCollege) {
      if (_collegeController.text.trim().isEmpty) return false;
      if (_courseController.text.trim().isEmpty) return false;
    }
    if (moment.needsSemester && _semester == null) return false;
    return true;
  }

  Future<void> _continue() async {
    if (!_canContinue) return;
    final userId = currentUserIdOrNull();
    if (userId == null) {
      // ignore: unawaited_futures
      handleSessionLost(context);
      return;
    }

    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => _saveEducation(userId),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;

    final timeMs = _shownAt != null
        ? DateTime.now().difference(_shownAt!).inMilliseconds
        : 0;
    final moment = _moment!;
    // ignore: unawaited_futures
    AnalyticsService.shared.track(
      'onboarding_masking_question_answered',
      props: {
        'question': 'education',
        'education_moment': moment.dbValue,
        'has_school': moment.needsSchool,
        'has_college': moment.needsCollege,
        'has_semester': moment.needsSemester && _semester != null,
        'has_school_year': moment.needsSchool && _schoolYear != null,
        'time_ms': timeMs,
      },
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DesiredTitlesScreen()),
    );
  }

  Future<void> _saveEducation(String userId) async {
    final moment = _moment;
    if (moment == null) throw StateError('Formação incompleta.');

    final existing = await _repo.getEducation(userId);
    final school = _findSchool(existing);
    final college = _findCollege(existing);

    String? schoolName;
    String? collegeName;
    String? courseName;
    int? schoolYear;

    if (moment.needsSchool) {
      schoolName = _schoolController.text.trim();
      schoolYear = _schoolYear;
      if (schoolName.isEmpty) throw StateError('Escola incompleta.');
      if (schoolYear == null) throw StateError('Ano escolar incompleto.');
      await _upsertSchool(
        userId: userId,
        existing: school,
        name: schoolName,
        schoolYear: schoolYear,
      );
      await _deleteEducation(college);
    } else if (moment.needsCollege) {
      collegeName = _collegeController.text.trim();
      courseName = _courseController.text.trim();
      if (collegeName.isEmpty || courseName.isEmpty) {
        throw StateError('Faculdade incompleta.');
      }
      await _upsertCollege(
        userId: userId,
        existing: college,
        moment: moment,
        name: collegeName,
        course: courseName,
        semester: moment.needsSemester ? _semester : null,
      );
      await _deleteEducation(school);
    } else {
      await _deleteEducation(school);
      await _deleteEducation(college);
    }

    await _syncLegacyUserProfile(
      userId: userId,
      moment: moment,
      schoolName: schoolName,
      schoolYear: schoolYear,
      collegeName: collegeName,
      courseName: courseName,
      semester: moment.needsSemester ? _semester : null,
    );

    if (mounted) {
      await context.read<ProfileEditorViewModel>().load();
    }
  }

  Future<void> _upsertSchool({
    required String userId,
    required Education? existing,
    required String name,
    required int schoolYear,
  }) async {
    final education = Education(
      id: existing?.id ?? '',
      userId: existing?.userId ?? userId,
      institution: name,
      educationLevel: 'school',
      educationStatus: _EducationMoment.inSchool.educationStatus,
      degree: 'Ensino médio',
      currentSchoolYear: schoolYear,
      orderIndex: existing?.orderIndex ?? 0,
      confidence: existing?.confidence,
    );

    if (existing == null) {
      await _repo.addEducation(education);
    } else {
      await _repo.updateEducation(education);
    }
  }

  Future<void> _upsertCollege({
    required String userId,
    required Education? existing,
    required _EducationMoment moment,
    required String name,
    required String course,
    required int? semester,
  }) async {
    final education = Education(
      id: existing?.id ?? '',
      userId: existing?.userId ?? userId,
      institution: name,
      // Typeahead desta sessão > vínculo pré-existente (se o texto não
      // mudou) > null (texto livre). O raw text é sempre a verdade.
      institutionId: _collegeInstitutionId ??
          (name == existing?.institution ? existing?.institutionId : null),
      educationLevel: 'college',
      educationStatus: moment.educationStatus,
      location: existing?.location,
      degree: 'Graduação',
      currentSemester: semester,
      currentSchoolYear: null,
      startDate: existing?.startDate,
      endDate: existing?.endDate,
      gpa: existing?.gpa,
      maxGpa: existing?.maxGpa,
      orderIndex: existing?.orderIndex ?? 0,
      confidence: existing?.confidence,
      majors: [
        EducationMajor(id: '', educationId: existing?.id ?? '', name: course),
      ],
      minors: existing?.minors ?? const [],
      activities: existing?.activities ?? const [],
    );

    if (existing == null) {
      await _repo.addEducation(education);
    } else {
      await _repo.updateEducation(education);
    }
  }

  Future<void> _deleteEducation(Education? education) async {
    if (education == null) return;
    await _repo.deleteEducation(education.id);
  }

  Future<void> _syncLegacyUserProfile({
    required String userId,
    required _EducationMoment moment,
    required String? schoolName,
    required int? schoolYear,
    required String? collegeName,
    required String? courseName,
    required int? semester,
  }) async {
    final supabase = Supabase.instance.client;
    final row = await supabase
        .from('user_profiles')
        .select('gamification_data')
        .eq('id', userId)
        .maybeSingle();
    final data = Map<String, dynamic>.from(
      (row?['gamification_data'] as Map?) ?? const {},
    );

    data['education_moment'] = moment.dbValue;
    if (schoolName != null && schoolName.trim().isNotEmpty) {
      data['school'] = schoolName.trim();
    } else {
      data.remove('school');
    }
    if (schoolYear != null) {
      data['school_year'] = schoolYear;
    } else {
      data.remove('school_year');
    }
    if (collegeName != null && collegeName.trim().isNotEmpty) {
      data['university'] = collegeName.trim();
    } else {
      data.remove('university');
    }
    if (semester != null) {
      data['current_semester'] = semester;
    } else {
      data.remove('current_semester');
    }

    await supabase
        .from('user_profiles')
        .update({
          'course': courseName ?? '',
          'semester': _legacySemesterLabel(moment, semester, schoolYear),
          'gamification_data': data,
        })
        .eq('id', userId);
  }

  String _legacySemesterLabel(
    _EducationMoment moment,
    int? semester,
    int? schoolYear,
  ) {
    if (moment.needsSchool && schoolYear != null) {
      return '$schoolYearº ano do ensino médio';
    }
    if (moment.needsSemester && semester != null) {
      final suffix = moment == _EducationMoment.collegePaused
          ? ' (trancado)'
          : '';
      return '$semester semestre$suffix';
    }
    return moment.legacySemesterLabel;
  }

  Education? _findSchool(List<Education> rows) {
    for (final e in rows) {
      final level = (e.educationLevel ?? '').toLowerCase();
      final degree = (e.degree ?? '').toLowerCase();
      if (level == 'school' ||
          degree.contains('ensino medio') ||
          degree.contains('ensino médio')) {
        return e;
      }
    }
    return null;
  }

  Education? _findCollege(List<Education> rows) {
    for (final e in rows) {
      if ((e.educationLevel ?? '').toLowerCase() == 'college') return e;
    }
    for (final e in rows) {
      if (_findSchool([e]) == null && e.majors.isNotEmpty) return e;
    }
    return null;
  }

  _EducationMoment? _momentFromEducation({
    required Education? school,
    required Education? college,
  }) {
    if (college != null) {
      return _momentFromCollegeStatus(college.educationStatus) ??
          (college.currentSemester != null
              ? _EducationMoment.inCollege
              : _momentFromCollegeDates(college));
    }
    if (school != null) return _EducationMoment.inSchool;
    return null;
  }

  _EducationMoment? _momentFromCollegeStatus(String? raw) {
    switch (raw) {
      case 'studying':
        return _EducationMoment.inCollege;
      case 'paused':
        return _EducationMoment.collegePaused;
      case 'graduated':
        return _EducationMoment.collegeGraduated;
      case 'not_started':
      case 'not_in_college':
      case 'not_studying':
        return _EducationMoment.notStudying;
      default:
        return null;
    }
  }

  _EducationMoment _momentFromCollegeDates(Education college) {
    final endDate = college.endDate;
    if (endDate != null && endDate.isBefore(DateTime.now())) {
      return _EducationMoment.collegeGraduated;
    }
    return _EducationMoment.inCollege;
  }

  _EducationMoment? _momentFromDb(String? raw) {
    switch (raw) {
      case 'in_school':
        return _EducationMoment.inSchool;
      case 'in_college':
        return _EducationMoment.inCollege;
      case 'college_paused':
        return _EducationMoment.collegePaused;
      case 'college_graduated':
        return _EducationMoment.collegeGraduated;
      case 'not_studying':
        return _EducationMoment.notStudying;
      default:
        return _momentFromCollegeStatus(raw);
    }
  }

  int? _parseSemester(Object? raw) {
    if (raw is num) return _validSemester(raw.toInt());
    final text = _clean(raw);
    if (text == null) return null;
    final match = RegExp(r'\d+').firstMatch(text);
    return _validSemester(int.tryParse(match?.group(0) ?? ''));
  }

  int? _parseSchoolYear(Object? raw) {
    if (raw is num) return _validSchoolYear(raw.toInt());
    final text = _clean(raw);
    if (text == null) return null;
    final match = RegExp(r'\d+').firstMatch(text);
    return _validSchoolYear(int.tryParse(match?.group(0) ?? ''));
  }

  int? _validSemester(int? value) {
    if (value == null || value < 1 || value > 12) return null;
    return value;
  }

  int? _validSchoolYear(int? value) {
    if (value == null || value < 1 || value > 3) return null;
    return value;
  }

  String? _clean(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? _degreeAsCourse(String? degree) {
    final text = _clean(degree);
    if (text == null) return null;
    final normalized = text.toLowerCase();
    if (normalized == 'graduação' || normalized == 'graduacao') return null;
    if (normalized.contains('ensino médio') ||
        normalized.contains('ensino medio')) {
      return null;
    }
    return text;
  }

  void _selectMoment(_EducationMoment moment) {
    HapticFeedback.selectionClick();
    setState(() {
      _moment = moment;
      if (moment.needsSchool) _schoolYear ??= 1;
      if (moment.needsSemester) _semester ??= 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final moment = _moment;
    return OnboardingScaffold(
      title: 'Em que momento você está agora?',
      subtitle: 'A gente usa isso para ajustar as vagas ao seu momento.',
      progress: 0.61,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: _canContinue ? _continue : null,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_buildMomentChoices(moment)],
        ),
      ),
    );
  }

  Widget _buildMomentChoices(_EducationMoment? moment) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in _EducationMoment.values) ...[
          _MomentCard(
            title: option.title,
            subtitle: option.subtitle,
            icon: option.icon,
            selected: moment == option,
            onTap: () => _selectMoment(option),
            child: moment == option && option != _EducationMoment.notStudying
                ? _buildDetailFields(option)
                : null,
          ),
          if (option != _EducationMoment.values.last)
            const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildDetailFields(_EducationMoment moment) {
    final institutionController = moment.needsSchool
        ? _schoolController
        : _collegeController;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldBlock(
          title: moment.institutionLabel,
          // Fase 1 T1.6: faculdade ganha typeahead contra o catálogo
          // `institutions` (95 IES) — seleção grava institution_id; texto
          // livre continua valendo ("outra"). Escola segue campo livre
          // (catálogo não cobre escolas).
          child: moment.needsSchool
              ? TextField(
                  controller: institutionController,
                  textCapitalization: TextCapitalization.words,
                  decoration: onboardingInputDecoration(
                    hintText: moment.institutionHint,
                  ),
                )
              : InstitutionTypeaheadField(
                  controller: institutionController,
                  onInstitutionSelected: (s) => _collegeInstitutionId = s?.id,
                  decoration: onboardingInputDecoration(
                    hintText: moment.institutionHint,
                  ),
                ),
        ),
        if (moment.needsSchool) ...[
          const SizedBox(height: 12),
          _StepSliderBlock(
            title: 'Ano da escola',
            value: _schoolYear ?? 1,
            min: 1,
            max: 3,
            labelBuilder: _schoolYearLabel,
            onChanged: (value) => setState(() => _schoolYear = value),
          ),
        ],
        if (moment.needsCourse) ...[
          const SizedBox(height: 12),
          _FieldBlock(
            title: 'Curso',
            child: TextField(
              controller: _courseController,
              textCapitalization: TextCapitalization.words,
              decoration: onboardingInputDecoration(
                hintText: 'Ex: Administração, Direito, Engenharia',
              ),
            ),
          ),
        ],
        if (moment.needsSemester) ...[
          const SizedBox(height: 12),
          _StepSliderBlock(
            title: moment.semesterLabel,
            value: _semester ?? 1,
            min: 1,
            max: 12,
            labelBuilder: _semesterLabel,
            onChanged: (value) => setState(() => _semester = value),
          ),
        ],
      ],
    );
  }

  String _schoolYearLabel(int value) => '$valueº ano';

  String _semesterLabel(int value) => '$valueº semestre';
}

class _MomentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Widget? child;

  const _MomentCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _kAccent : _kBorderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: selected ? _kAccent : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          icon,
                          color: selected ? Colors.white : _kTextColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: _kTextColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: _kLabelColor,
                                fontSize: 13,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected ? _kAccent : AppColors.textDisabled,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: child == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: child!,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldBlock extends StatelessWidget {
  final String title;
  final Widget child;

  const _FieldBlock({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _kTextColor,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _StepSliderBlock extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final String Function(int value) labelBuilder;
  final ValueChanged<int> onChanged;

  const _StepSliderBlock({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(min, max).toInt();
    return _FieldBlock(
      title: title,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorderColor),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  labelBuilder(min),
                  style: const TextStyle(
                    color: _kLabelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    labelBuilder(clampedValue),
                    style: const TextStyle(
                      color: _kAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  labelBuilder(max),
                  style: const TextStyle(
                    color: _kLabelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                activeTrackColor: _kAccent,
                inactiveTrackColor: AppColors.border,
                thumbColor: _kAccent,
                overlayColor: _kAccent.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: clampedValue.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min,
                label: labelBuilder(clampedValue),
                onChanged: (next) => onChanged(next.round()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
