import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/stage_colors.dart';
import '../../../services/analytics_service.dart';
import '../../auth/user_viewmodel.dart';
import '../../resume/pdf_service.dart';
import '../../resume/resume_viewmodel.dart';
import '../models/adapted_resume.dart';
import '../models/job.dart';
import '../pending_adapted_cv_tracker.dart';
import 'resume_block_editor.dart';

/// Tela full-screen de preview do CV adaptado pela IA (F1 da reformulação).
///
/// Substitui a lista de "changes" diff da sheet anterior por uma visualização
/// editável do currículo inteiro. Princípios:
/// - Usuário nunca baixa PDF "no escuro" — vê o resultado renderizado antes.
/// - Cada bloco é editável; tap em qualquer campo abre TextField inline.
/// - Toggle "Adaptado | Original | Lado a lado" pra comparar.
/// - Botão "Voltar ao original" por campo (chip "Mudou") + global.
/// - Telemetria via [Analytics.cvAdaptationUserEdited] alimenta o sinal
///   "o que a IA está errando" pra próximas fases (validador semântico).
///
/// Renderização: Flutter nativo (não WebView). Permite edição direta sem
/// JavaScript bridge e garante consistência cross-platform.
class AdaptedResumePreviewScreen extends StatefulWidget {
  /// Adaptação original vinda do servidor (com IA aplicada).
  final AdaptedResume adapted;

  /// Vaga alvo da adaptação. Usado no header e na telemetria.
  final Job job;

  const AdaptedResumePreviewScreen({
    super.key,
    required this.adapted,
    required this.job,
  });

  @override
  State<AdaptedResumePreviewScreen> createState() =>
      _AdaptedResumePreviewScreenState();
}

class _AdaptedResumePreviewScreenState extends State<AdaptedResumePreviewScreen> {
  late ResumeData _current;
  late final ResumeData _aiAdapted;
  late final ResumeData _original;
  _ViewMode _mode = _ViewMode.adapted;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _aiAdapted = widget.adapted.resumeData;
    _current = widget.adapted.effectiveResumeData;
    // `original` aqui é o CV-base do usuário (pré-adaptação). No fluxo atual
    // não recebemos ele direto; reconstruímos a partir do ResumeViewModel
    // que já tem o ResumeData do user. Caller pode injetar via Provider.
    // Por enquanto usamos o adapted como fallback se não houver original
    // disponível (graceful degradation — preview ainda funciona).
    _original = context.read<ResumeViewModel>().resumeData ?? _aiAdapted;
  }

  /// Substitui o `_current` por um clone com uma mudança específica.
  /// Notifica PostHog para alimentar dashboards de qualidade.
  void _update({
    required String field,
    required ResumeData Function(ResumeData) mutate,
    String editType = 'replace',
  }) {
    final before = _current;
    final after = mutate(_current);
    if (identical(before, after)) return;
    setState(() => _current = after);
    // Telemetria assíncrona — não bloqueia UI.
    // ignore: unawaited_futures
    Analytics.shared.cvAdaptationUserEdited(
      jobId: widget.job.id,
      field: field,
      editType: editType,
      charDiff: _measureDiff(before, after, field),
    );
  }

  int _measureDiff(ResumeData before, ResumeData after, String field) {
    // Heurística simples: para campos string-puros, diferença de length.
    // Para listas e nested, retorna 0 (sinal só de "houve mudança").
    String? bv;
    String? av;
    switch (field) {
      case 'summary':
        bv = before.summary;
        av = after.summary;
        break;
      case 'phone':
        bv = before.phone;
        av = after.phone;
        break;
      case 'email':
        bv = before.email;
        av = after.email;
        break;
      case 'location':
        bv = before.location;
        av = after.location;
        break;
      case 'linkedin':
        bv = before.linkedin;
        av = after.linkedin;
        break;
    }
    if (bv == null || av == null) return 0;
    return av.length - bv.length;
  }

  Future<void> _approveAndDownload() async {
    HapticFeedback.mediumImpact();
    setState(() => _isExporting = true);
    try {
      final user = context.read<UserViewModel>().user;
      final templateId = context.read<ResumeViewModel>().selectedTemplateId;
      await PdfService.generateResume(user, _current, templateId);
      // ignore: unawaited_futures
      Analytics.shared.cvAdaptationPdfDownloaded(jobId: widget.job.id);
      // ignore: unawaited_futures
      PendingAdaptedCvTracker.shared.clear();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar PDF: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _restoreAllToOriginal() {
    HapticFeedback.mediumImpact();
    setState(() => _current = _aiAdapted);
    // ignore: unawaited_futures
    Analytics.shared.cvAdaptationUserEdited(
      jobId: widget.job.id,
      field: 'all',
      editType: 'restore_original',
      charDiff: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildModeToggle(),
            Expanded(child: _buildBody()),
            _buildFooter(mq),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Revisar antes de baixar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          if (_hasEdits)
            TextButton.icon(
              onPressed: _restoreAllToOriginal,
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: const Text(
                'Voltar tudo',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: StageColors.brandCyan,
              ),
            ),
        ],
      ),
    );
  }

  bool get _hasEdits {
    final a = _aiAdapted;
    final c = _current;
    return a.fullName != c.fullName ||
        a.email != c.email ||
        a.phone != c.phone ||
        a.linkedin != c.linkedin ||
        a.location != c.location ||
        a.summary != c.summary ||
        !_listEq(a.skills, c.skills) ||
        !_listEq(a.achievements, c.achievements) ||
        !_listEq(a.interests, c.interests) ||
        !_experienceListEq(a.experiences, c.experiences) ||
        !_educationListEq(a.education, c.education);
  }

  bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _experienceListEq(List<ExperienceItem> a, List<ExperienceItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].role != b[i].role ||
          a[i].company != b[i].company ||
          a[i].period != b[i].period ||
          a[i].description != b[i].description ||
          a[i].location != b[i].location) return false;
    }
    return true;
  }

  bool _educationListEq(List<EducationItem> a, List<EducationItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].degree != b[i].degree ||
          a[i].institution != b[i].institution ||
          a[i].period != b[i].period ||
          a[i].details != b[i].details ||
          a[i].location != b[i].location) return false;
    }
    return true;
  }

  Widget _buildModeToggle() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            _buildToggleButton(_ViewMode.adapted, 'Adaptado'),
            _buildToggleButton(_ViewMode.original, 'Original'),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton(_ViewMode mode, String label) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _mode = mode);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF111827) : const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final data = _mode == _ViewMode.original ? _original : _current;
    final readOnly = _mode == _ViewMode.original;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        _buildResumeCard(data: data, readOnly: readOnly),
      ],
    );
  }

  Widget _buildResumeCard({required ResumeData data, required bool readOnly}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(data, readOnly),
          const SizedBox(height: 18),
          if (data.summary.isNotEmpty || !readOnly) ...[
            _buildSectionTitle('Resumo'),
            ResumeBlockEditor(
              value: data.summary,
              original: _aiAdapted.summary,
              hint: 'Resumo profissional',
              multiline: true,
              readOnly: readOnly,
              maxLength: 600,
              textStyle: const TextStyle(fontSize: 13, height: 1.45, color: Color(0xFF374151)),
              onChanged: (v) => _update(
                field: 'summary',
                mutate: (d) => d.copyWith(summary: v),
              ),
              onRestoreOriginal: _aiAdapted.summary != data.summary
                  ? () => _update(
                        field: 'summary',
                        editType: 'restore_original',
                        mutate: (d) => d.copyWith(summary: _aiAdapted.summary),
                      )
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (data.skills.isNotEmpty || !readOnly) ...[
            ResumeListEditor(
              value: data.skills,
              original: _aiAdapted.skills,
              label: 'HABILIDADES',
              addHint: 'Nova habilidade',
              onChanged: (v) => _update(
                field: 'skills',
                mutate: (d) => d.copyWith(skills: v),
              ),
              onRestoreOriginal: !_listEq(_aiAdapted.skills, data.skills)
                  ? () => _update(
                        field: 'skills',
                        editType: 'restore_original',
                        mutate: (d) => d.copyWith(skills: _aiAdapted.skills),
                      )
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (data.experiences.isNotEmpty) ...[
            _buildSectionTitle('Experiência'),
            ...List.generate(data.experiences.length, (i) {
              final exp = data.experiences[i];
              final origExp = i < _aiAdapted.experiences.length
                  ? _aiAdapted.experiences[i]
                  : exp;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildExperienceBlock(exp, origExp, i, readOnly),
              );
            }),
            const SizedBox(height: 4),
          ],
          if (data.education.isNotEmpty) ...[
            _buildSectionTitle('Formação'),
            ...List.generate(data.education.length, (i) {
              final ed = data.education[i];
              final origEd = i < _aiAdapted.education.length
                  ? _aiAdapted.education[i]
                  : ed;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildEducationBlock(ed, origEd, i, readOnly),
              );
            }),
            const SizedBox(height: 4),
          ],
          if (data.achievements.isNotEmpty || !readOnly) ...[
            ResumeListEditor(
              value: data.achievements,
              original: _aiAdapted.achievements,
              label: 'CONQUISTAS',
              addHint: 'Nova conquista',
              onChanged: (v) => _update(
                field: 'achievements',
                mutate: (d) => d.copyWith(achievements: v),
              ),
              onRestoreOriginal: !_listEq(_aiAdapted.achievements, data.achievements)
                  ? () => _update(
                        field: 'achievements',
                        editType: 'restore_original',
                        mutate: (d) => d.copyWith(achievements: _aiAdapted.achievements),
                      )
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (data.interests.isNotEmpty || !readOnly) ...[
            ResumeListEditor(
              value: data.interests,
              original: _aiAdapted.interests,
              label: 'INTERESSES',
              addHint: 'Novo interesse',
              onChanged: (v) => _update(
                field: 'interests',
                mutate: (d) => d.copyWith(interests: v),
              ),
              onRestoreOriginal: !_listEq(_aiAdapted.interests, data.interests)
                  ? () => _update(
                        field: 'interests',
                        editType: 'restore_original',
                        mutate: (d) => d.copyWith(interests: _aiAdapted.interests),
                      )
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderSection(ResumeData data, bool readOnly) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResumeBlockEditor(
          value: data.fullName,
          original: _aiAdapted.fullName,
          hint: 'Nome completo',
          readOnly: readOnly,
          textStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
            height: 1.1,
          ),
          onChanged: (v) => _update(
            field: 'fullName',
            mutate: (d) => d.copyWith(fullName: v),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _buildContactEditor(
              data.location,
              _aiAdapted.location,
              'Localização',
              readOnly,
              (v) => _update(field: 'location', mutate: (d) => d.copyWith(location: v)),
            ),
            _buildContactEditor(
              data.phone,
              _aiAdapted.phone,
              'Telefone',
              readOnly,
              (v) => _update(field: 'phone', mutate: (d) => d.copyWith(phone: v)),
            ),
            _buildContactEditor(
              data.email,
              _aiAdapted.email,
              'Email',
              readOnly,
              (v) => _update(field: 'email', mutate: (d) => d.copyWith(email: v)),
            ),
            _buildContactEditor(
              data.linkedin,
              _aiAdapted.linkedin,
              'LinkedIn',
              readOnly,
              (v) => _update(field: 'linkedin', mutate: (d) => d.copyWith(linkedin: v)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContactEditor(
    String value,
    String original,
    String hint,
    bool readOnly,
    ValueChanged<String> onChanged,
  ) {
    if (value.isEmpty && readOnly) return const SizedBox.shrink();
    return SizedBox(
      width: 220,
      child: ResumeBlockEditor(
        value: value,
        original: original,
        hint: hint,
        readOnly: readOnly,
        textStyle: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Divider(color: Color(0xFFE5E7EB), height: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildExperienceBlock(
    ExperienceItem exp,
    ExperienceItem orig,
    int index,
    bool readOnly,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ResumeBlockEditor(
                  value: exp.role,
                  original: orig.role,
                  hint: 'Cargo',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                  onChanged: (v) => _update(
                    field: 'experiences.$index.role',
                    mutate: (d) {
                      final list = List<ExperienceItem>.from(d.experiences);
                      list[index] = ExperienceItem(
                        role: v,
                        company: exp.company,
                        period: exp.period,
                        description: exp.description,
                        location: exp.location,
                      );
                      return d.copyWith(experiences: list);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: ResumeBlockEditor(
                  value: exp.period,
                  original: orig.period,
                  hint: 'Período',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (v) => _update(
                    field: 'experiences.$index.period',
                    mutate: (d) {
                      final list = List<ExperienceItem>.from(d.experiences);
                      list[index] = ExperienceItem(
                        role: exp.role,
                        company: exp.company,
                        period: v,
                        description: exp.description,
                        location: exp.location,
                      );
                      return d.copyWith(experiences: list);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ResumeBlockEditor(
                  value: exp.company,
                  original: orig.company,
                  hint: 'Empresa',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF4B5563),
                  ),
                  onChanged: (v) => _update(
                    field: 'experiences.$index.company',
                    mutate: (d) {
                      final list = List<ExperienceItem>.from(d.experiences);
                      list[index] = ExperienceItem(
                        role: exp.role,
                        company: v,
                        period: exp.period,
                        description: exp.description,
                        location: exp.location,
                      );
                      return d.copyWith(experiences: list);
                    },
                  ),
                ),
              ),
              if (exp.location.isNotEmpty || !readOnly) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: ResumeBlockEditor(
                    value: exp.location,
                    original: orig.location,
                    hint: 'Cidade',
                    readOnly: readOnly,
                    textStyle: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                    onChanged: (v) => _update(
                      field: 'experiences.$index.location',
                      mutate: (d) {
                        final list = List<ExperienceItem>.from(d.experiences);
                        list[index] = ExperienceItem(
                          role: exp.role,
                          company: exp.company,
                          period: exp.period,
                          description: exp.description,
                          location: v,
                        );
                        return d.copyWith(experiences: list);
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ResumeBlockEditor(
            value: exp.description,
            original: orig.description,
            hint: 'Descrição / bullets (uma por linha)',
            multiline: true,
            readOnly: readOnly,
            textStyle: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Color(0xFF374151),
            ),
            onChanged: (v) => _update(
              field: 'experiences.$index.description',
              mutate: (d) {
                final list = List<ExperienceItem>.from(d.experiences);
                list[index] = ExperienceItem(
                  role: exp.role,
                  company: exp.company,
                  period: exp.period,
                  description: v,
                  location: exp.location,
                );
                return d.copyWith(experiences: list);
              },
            ),
            onRestoreOriginal: orig.description != exp.description
                ? () => _update(
                      field: 'experiences.$index.description',
                      editType: 'restore_original',
                      mutate: (d) {
                        final list = List<ExperienceItem>.from(d.experiences);
                        list[index] = ExperienceItem(
                          role: exp.role,
                          company: exp.company,
                          period: exp.period,
                          description: orig.description,
                          location: exp.location,
                        );
                        return d.copyWith(experiences: list);
                      },
                    )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildEducationBlock(
    EducationItem ed,
    EducationItem orig,
    int index,
    bool readOnly,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ResumeBlockEditor(
                  value: ed.institution,
                  original: orig.institution,
                  hint: 'Instituição',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                  onChanged: (v) => _update(
                    field: 'education.$index.institution',
                    mutate: (d) {
                      final list = List<EducationItem>.from(d.education);
                      list[index] = EducationItem(
                        degree: ed.degree,
                        institution: v,
                        period: ed.period,
                        details: ed.details,
                        location: ed.location,
                      );
                      return d.copyWith(education: list);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: ResumeBlockEditor(
                  value: ed.period,
                  original: orig.period,
                  hint: 'Período',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (v) => _update(
                    field: 'education.$index.period',
                    mutate: (d) {
                      final list = List<EducationItem>.from(d.education);
                      list[index] = EducationItem(
                        degree: ed.degree,
                        institution: ed.institution,
                        period: v,
                        details: ed.details,
                        location: ed.location,
                      );
                      return d.copyWith(education: list);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ResumeBlockEditor(
                  value: ed.degree,
                  original: orig.degree,
                  hint: 'Curso/Grau',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF4B5563),
                  ),
                  onChanged: (v) => _update(
                    field: 'education.$index.degree',
                    mutate: (d) {
                      final list = List<EducationItem>.from(d.education);
                      list[index] = EducationItem(
                        degree: v,
                        institution: ed.institution,
                        period: ed.period,
                        details: ed.details,
                        location: ed.location,
                      );
                      return d.copyWith(education: list);
                    },
                  ),
                ),
              ),
              if (ed.location.isNotEmpty || !readOnly) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: ResumeBlockEditor(
                    value: ed.location,
                    original: orig.location,
                    hint: 'Cidade',
                    readOnly: readOnly,
                    textStyle: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                    onChanged: (v) => _update(
                      field: 'education.$index.location',
                      mutate: (d) {
                        final list = List<EducationItem>.from(d.education);
                        list[index] = EducationItem(
                          degree: ed.degree,
                          institution: ed.institution,
                          period: ed.period,
                          details: ed.details,
                          location: v,
                        );
                        return d.copyWith(education: list);
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (ed.details.isNotEmpty || !readOnly) ...[
            const SizedBox(height: 6),
            ResumeBlockEditor(
              value: ed.details,
              original: orig.details,
              hint: 'Detalhes (opcional)',
              multiline: true,
              readOnly: readOnly,
              textStyle: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Color(0xFF374151),
              ),
              onChanged: (v) => _update(
                field: 'education.$index.details',
                mutate: (d) {
                  final list = List<EducationItem>.from(d.education);
                  list[index] = EducationItem(
                    degree: ed.degree,
                    institution: ed.institution,
                    period: ed.period,
                    details: v,
                    location: ed.location,
                  );
                  return d.copyWith(education: list);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(MediaQueryData mq) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_hasEdits)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: StageColors.brandCyan,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Editado',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: StageColors.brandCyan,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ElevatedButton(
              onPressed: _isExporting ? null : _approveAndDownload,
              style: ElevatedButton.styleFrom(
                backgroundColor: StageColors.brandCyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isExporting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _hasEdits ? 'Aprovar e baixar' : 'Baixar PDF',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ViewMode { adapted, original }
