// ProfileSectionList — lista de seções colapsáveis do perfil.
//
// Usado em ReviewResumeScreen (Container 1, onboarding) com
// showLowConfidenceBadges=true e em ProfileEditorScreen (Container 2, aba Perfil)
// com showLowConfidenceBadges=false.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth/auth_session.dart';
import '../../application/profile_editor_view_model.dart';
import '../../domain/award_editor_reconciliation.dart';
import '../../domain/entities/entities.dart';
import '../../domain/skill_name_normalizer.dart';
import '../../../resume/data/profile_resume_mapper.dart';
import 'add_edit_certification_modal.dart';
import 'add_edit_experience_modal.dart';
import 'add_edit_education_modal.dart';
import 'add_edit_language_modal.dart';
import 'add_edit_project_modal.dart';
import 'edit_list_modal.dart';
import '../../../../core/theme/theme.dart';

const _kBorderColor = AppColors.border;
const _kCardBg = AppColors.surfaceVariant;
const _kChipBg = AppColors.background;
const _kTextColor = AppColors.textPrimary;
const _kMutedText = AppColors.textTertiary;
const _kAccent = AppColors.primary;

class ProfileSectionList extends StatefulWidget {
  /// Se true, destaca campos com confidence < 0.7 com borda amarela. Usado no
  /// modo revisão (pós-extração de CV).
  final bool showLowConfidenceBadges;

  /// Se true, mostra seções opcionais (Awards, Coursework) por default.
  /// Se false, esconde atrás de "Adicionar outras seções".
  final bool showOptionalSections;

  const ProfileSectionList({
    super.key,
    this.showLowConfidenceBadges = false,
    this.showOptionalSections = false,
  });

  @override
  State<ProfileSectionList> createState() => _ProfileSectionListState();
}

class _ProfileSectionListState extends State<ProfileSectionList> {
  final Map<String, bool> _expanded = {
    'experiences': true,
    'education': true,
    'languages': false,
    'skills': false,
    'certifications': false,
    'projects': false,
    'interests': false,
    'awards': false,
  };
  late bool _showOptional;

  @override
  void initState() {
    super.initState();
    _showOptional = widget.showOptionalSections;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileEditorViewModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionExperiences(vm),
        _sectionEducation(vm),
        _sectionLanguages(vm),
        _sectionSkills(vm),
        _sectionCertifications(vm),
        _sectionInterests(vm),
        _sectionProjects(vm),
        if (_showOptional) ...[
          _sectionAwards(vm),
          _sectionCoursework(vm),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.add_rounded, color: _kAccent),
              label: const Text(
                'Adicionar outras seções',
                style: TextStyle(color: _kAccent, fontWeight: FontWeight.w600),
              ),
              onPressed: () => setState(() => _showOptional = true),
            ),
          ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Seções específicas
  // ──────────────────────────────────────────────────────────────────────

  Widget _sectionExperiences(ProfileEditorViewModel vm) => _sectionShell(
    key: 'experiences',
    title: 'Experiência profissional',
    count: vm.experiences.length,
    onAdd: () => _showExperienceModal(context, vm),
    children: vm.experiences.map((e) {
      final lowConfidence =
          widget.showLowConfidenceBadges &&
          (e.confidence != null && e.confidence! < 0.7);
      return _ItemCard(
        avatarText: e.company,
        title: e.title,
        subtitle: e.company,
        period: e.formattedPeriod,
        location: e.location,
        bullets: e.bullets.map((b) => b.text).toList(),
        lowConfidence: lowConfidence,
        onTap: () => _showExperienceModal(context, vm, initial: e),
        onDelete: () => vm.deleteExperience(e.id),
      );
    }).toList(),
  );

  Widget _sectionEducation(ProfileEditorViewModel vm) => _sectionShell(
    key: 'education',
    title: 'Educação',
    count: vm.education.length,
    onAdd: () => _showEducationModal(context, vm),
    children: vm.education.map((e) {
      final lowConfidence =
          widget.showLowConfidenceBadges &&
          (e.confidence != null && e.confidence! < 0.7);
      final subtitle = ProfileResumeMapper.formatEducationQualification(e);
      final details = <_DetailLine>[
        if (_educationStatusDetail(e) != null)
          _DetailLine(label: 'Situação', value: _educationStatusDetail(e)!),
        if (e.currentSemester != null)
          _DetailLine(
            label: e.educationStatus == 'paused'
                ? 'Último semestre'
                : 'Semestre atual',
            value: '${e.currentSemester}º semestre',
          ),
        if (e.currentSchoolYear != null)
          _DetailLine(
            label: 'Ano escolar',
            value: '${e.currentSchoolYear}º ano',
          ),
        if (e.educationStatus == 'studying' && e.endDate == null)
          const _DetailLine(
            label: 'Previsão de conclusão',
            value: 'Não informada',
          ),
        if (e.majors.length > 1)
          _DetailLine(
            label: 'Cursos principais',
            value: e.majors.map((m) => m.name).join(', '),
          ),
        if (e.minors.isNotEmpty)
          _DetailLine(
            label: 'Cursos secundários',
            value: e.minors.map((m) => m.name).join(', '),
          ),
        if (e.gpa != null)
          _DetailLine(label: 'GPA', value: e.gpa!.toStringAsFixed(2)),
        if (e.activities.isNotEmpty)
          _DetailLine(
            label: 'Atividades',
            value: e.activities.map((a) => a.text).join(', '),
          ),
      ];
      return _ItemCard(
        avatarText: e.institution,
        title: e.institution,
        subtitle: subtitle.isEmpty ? null : subtitle,
        period: e.formattedPeriod,
        location: e.location,
        details: details,
        lowConfidence: lowConfidence,
        onTap: () => _showEducationModal(context, vm, initial: e),
        onDelete: () => vm.deleteEducation(e.id),
      );
    }).toList(),
  );

  Widget _sectionLanguages(ProfileEditorViewModel vm) => _sectionShell(
    key: 'languages',
    title: 'Idiomas',
    count: vm.languages.length,
    onAdd: () => _showLanguageModal(context, vm),
    children: vm.languages
        .map(
          (l) => _ItemCard(
            avatarText: l.name,
            title: l.name,
            subtitle: l.proficiencyLabel,
            onTap: () => _showLanguageModal(context, vm, initial: l),
            onDelete: () => vm.deleteLanguage(l.id),
          ),
        )
        .toList(),
  );

  Widget _sectionSkills(ProfileEditorViewModel vm) {
    final names = vm.skills.map((s) => s.name).toList();
    return _sectionShell(
      key: 'skills',
      title: 'Habilidades',
      count: names.length,
      onEdit: () => EditListModal.show(
        context: context,
        title: 'Editar habilidades',
        inputLabel: 'Habilidade',
        initialItems: names,
        suggestions: vm.skillSuggestions,
        guidanceText:
            'Priorize de 6 a 12 habilidades que você realmente usa e que são '
            'relevantes para as vagas que busca.',
        recommendedMinItems: kRecommendedMinProfileSkills,
        maxItems: kMaxProfileSkills,
        onSave: vm.replaceSkills,
      ),
      children: names.isEmpty ? const [] : [_ChipList(items: names)],
    );
  }

  /// Certificações — item a item, com campos estruturados.
  ///
  /// Era a única lista do editor sem modal próprio: usava o `EditListModal`
  /// genérico, que só entende texto solto. Ele exibia "Nome - Instituição - Ano"
  /// numa linha e, ao salvar, apagava TODAS as certificações e regravava cada
  /// linha inteira no campo `name`, com `issuer` e `date` nulos — abrir e salvar
  /// sem mudar nada já destruía a estrutura e poluía o nome com a concatenação.
  /// Medido em produção em 27/07: 392 certificações de 126 pessoas com
  /// instituição ou data a perder, e 19 linhas de 13 pessoas já destruídas.
  Widget _sectionCertifications(ProfileEditorViewModel vm) {
    return _sectionShell(
      key: 'certifications',
      title: 'Certificações',
      count: vm.certifications.length,
      onAdd: () => _showCertificationModal(context, vm),
      children: vm.certifications.map((c) {
        return _ItemCard(
          avatarText: c.issuer ?? c.name,
          title: c.name,
          subtitle: (c.issuer != null && c.issuer!.isNotEmpty) ? c.issuer : null,
          period: c.date == null ? null : _formatCertificationDate(c.date!),
          onTap: () => _showCertificationModal(context, vm, initial: c),
          onDelete: () => vm.deleteCertification(c.id),
        );
      }).toList(),
    );
  }

  Widget _sectionInterests(ProfileEditorViewModel vm) {
    final names = vm.interests.map((i) => i.name).toList();
    return _sectionShell(
      key: 'interests',
      title: 'Interesses',
      count: names.length,
      onEdit: () => EditListModal.show(
        context: context,
        title: 'Editar Interesses',
        inputLabel: 'Interesse',
        initialItems: names,
        onSave: vm.replaceInterests,
      ),
      children: names.isEmpty ? const [] : [_ChipList(items: names)],
    );
  }

  // Fase 3 F1c — matérias/disciplinas relevantes (lista simples, como interesses).
  Widget _sectionCoursework(ProfileEditorViewModel vm) {
    final names = vm.coursework.map((c) => c.name).toList();
    return _sectionShell(
      key: 'coursework',
      title: 'Disciplinas relevantes',
      count: names.length,
      onEdit: () => EditListModal.show(
        context: context,
        title: 'Editar disciplinas',
        inputLabel: 'Disciplina',
        initialItems: names,
        onSave: vm.replaceCoursework,
      ),
      children: names.isEmpty ? const [] : [_ChipList(items: names)],
    );
  }

  Widget _sectionProjects(ProfileEditorViewModel vm) => _sectionShell(
    key: 'projects',
    title: 'Projetos',
    count: vm.projects.length,
    onAdd: () => _showProjectModal(context, vm),
    children: vm.projects.map((p) {
      // Subtitle: role + context (ex: "Fundador • Empresa Júnior")
      final parts = <String>[];
      if (p.role != null && p.role!.isNotEmpty) parts.add(p.role!);
      if (p.context != null && p.context!.isNotEmpty) parts.add(p.context!);
      final subtitle = parts.join(' • ');
      // Bullets: usa os bullets novos; fallback pro description legado
      final bullets = p.bullets.isNotEmpty
          ? p.bullets.map((b) => b.text).toList()
          : (p.description != null && p.description!.isNotEmpty
                ? [p.description!]
                : <String>[]);
      // Period only if at least one date is set
      final hasPeriod = p.startDate != null || p.endDate != null;
      return _ItemCard(
        avatarText: p.name,
        title: p.name,
        subtitle: subtitle.isEmpty ? null : subtitle,
        period: hasPeriod ? _formatProjectPeriod(p) : null,
        bullets: bullets,
        onTap: () => _showProjectModal(context, vm, initial: p),
        onDelete: () => vm.deleteProject(p.id),
      );
    }).toList(),
  );

  /// Mês/ano da certificação. Só mês e ano porque é o que o picker coleta —
  /// mostrar dia daria uma precisão que o dado não tem.
  String _formatCertificationDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatProjectPeriod(Project p) {
    const months = [
      '',
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    String fmt(DateTime? d) => d == null ? '' : '${months[d.month]} ${d.year}';
    final start = fmt(p.startDate);
    final end = p.isCurrent ? 'Atual' : fmt(p.endDate);
    if (start.isEmpty && end.isEmpty) return '';
    if (start.isEmpty) return end;
    if (end.isEmpty) return start;
    return '$start - $end';
  }

  Widget _sectionAwards(ProfileEditorViewModel vm) {
    final names = vm.awards.map(awardEditorLabel).toList();
    return _sectionShell(
      key: 'awards',
      title: 'Prêmios',
      count: names.length,
      onEdit: () => EditListModal.show(
        context: context,
        title: 'Editar prêmios',
        inputLabel: 'Prêmio',
        initialItems: names,
        onSave: (items) async {
          final userId = currentUserIdOrNull();
          if (userId == null) {
            // ignore: unawaited_futures
            handleSessionLost(context);
            return;
          }
          final desired = reconcileAwardLabels(
            userId: userId,
            current: vm.awards,
            labels: items,
          );
          await vm.replaceAwards(desired);
        },
      ),
      children: names.isEmpty ? const [] : [_ChipList(items: names)],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Modal launchers
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _showExperienceModal(
    BuildContext ctx,
    ProfileEditorViewModel vm, {
    Experience? initial,
  }) {
    return AddEditExperienceModal.show(
      context: ctx,
      initial: initial,
      onSave: (exp, bulletTexts) async {
        // AddEditExperienceModal já embute os objetos Bullet para preservar IDs
        // e metadados. O fallback cobre chamadas antigas/testes que ainda
        // entreguem apenas os textos.
        final complete = exp.bullets.isNotEmpty || bulletTexts.isEmpty
            ? exp
            : exp.copyWith(
                bullets: bulletTexts
                    .asMap()
                    .entries
                    .map(
                      (entry) => Bullet(
                        id: '',
                        experienceId: exp.id,
                        text: entry.value.trim(),
                        orderIndex: entry.key,
                      ),
                    )
                    .toList(),
              );
        if (initial == null) {
          await vm.addExperience(complete);
        } else {
          await vm.updateExperience(complete);
        }
      },
      onDelete: initial == null ? null : () => vm.deleteExperience(initial.id),
    );
  }

  Future<void> _showEducationModal(
    BuildContext ctx,
    ProfileEditorViewModel vm, {
    Education? initial,
  }) {
    return AddEditEducationModal.show(
      context: ctx,
      initial: initial,
      onSave: (edu, majors, minors, activities) async {
        final completeEdu = edu.copyWith(
          majors: majors
              .asMap()
              .entries
              .map(
                (e) => EducationMajor(
                  id: 'temp_${e.key}',
                  educationId: edu.id,
                  name: e.value,
                  orderIndex: e.key,
                ),
              )
              .toList(),
          minors: minors
              .asMap()
              .entries
              .map(
                (e) => EducationMinor(
                  id: 'temp_${e.key}',
                  educationId: edu.id,
                  name: e.value,
                  orderIndex: e.key,
                ),
              )
              .toList(),
          activities: activities
              .asMap()
              .entries
              .map(
                (e) => EducationActivity(
                  id: 'temp_${e.key}',
                  educationId: edu.id,
                  text: e.value,
                  orderIndex: e.key,
                ),
              )
              .toList(),
        );
        if (initial == null) {
          await vm.addEducation(completeEdu);
        } else {
          await vm.updateEducation(completeEdu);
        }
      },
      onDelete: initial == null ? null : () => vm.deleteEducation(initial.id),
    );
  }

  Future<void> _showLanguageModal(
    BuildContext ctx,
    ProfileEditorViewModel vm, {
    Language? initial,
  }) {
    return AddEditLanguageModal.show(
      context: ctx,
      initial: initial,
      onSave: (lang) async {
        if (initial == null) {
          await vm.addLanguage(lang);
        } else {
          await vm.updateLanguage(lang);
        }
      },
      onDelete: initial == null ? null : () => vm.deleteLanguage(initial.id),
    );
  }

  Future<void> _showCertificationModal(
    BuildContext ctx,
    ProfileEditorViewModel vm, {
    Certification? initial,
  }) {
    return AddEditCertificationModal.show(
      context: ctx,
      initial: initial,
      onSave: (c) async {
        if (initial == null) {
          await vm.addCertification(c);
        } else {
          await vm.updateCertification(c);
        }
      },
      onDelete:
          initial == null ? null : () => vm.deleteCertification(initial.id),
    );
  }

  Future<void> _showProjectModal(
    BuildContext ctx,
    ProfileEditorViewModel vm, {
    Project? initial,
  }) {
    return AddEditProjectModal.show(
      context: ctx,
      initial: initial,
      onSave: (p) async {
        if (initial == null) {
          await vm.addProject(p);
        } else {
          await vm.updateProject(p);
        }
      },
      onDelete: initial == null ? null : () => vm.deleteProject(initial.id),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // UI helpers
  // ──────────────────────────────────────────────────────────────────────

  Widget _sectionShell({
    required String key,
    required String title,
    required int count,
    VoidCallback? onAdd,
    VoidCallback? onEdit,
    required List<Widget> children,
  }) {
    final isExpanded = _expanded[key] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            title: title,
            count: count,
            isExpanded: isExpanded,
            onToggle: () => setState(() => _expanded[key] = !isExpanded),
            onAdd: onAdd,
            onEdit: onEdit,
          ),
          if (isExpanded && children.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...children,
          ],
        ],
      ),
    );
  }
}

String? _educationStatusDetail(Education education) {
  final level = education.educationLevel;
  final status = education.educationStatus;
  if (level == 'school') {
    switch (status) {
      case 'studying':
        return 'Escola em andamento';
      case 'graduated':
        return 'Escola concluída';
      case 'paused':
        return 'Escola pausada';
    }
    if (education.currentSchoolYear != null) return 'Escola em andamento';
    return 'Escola';
  }
  if (level == 'college' || education.currentSemester != null) {
    switch (status) {
      case 'studying':
        return 'Faculdade em andamento';
      case 'paused':
        return 'Faculdade trancada';
      case 'graduated':
        return 'Faculdade concluída';
      case 'not_studying':
        return 'Não está estudando';
      case 'not_started':
        return 'Ainda não começou';
      case 'not_in_college':
        return 'Não está na faculdade';
    }
    return 'Faculdade';
  }
  switch (status) {
    case 'studying':
      return 'Em andamento';
    case 'paused':
      return 'Pausada';
    case 'graduated':
      return 'Concluída';
  }
  return null;
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.isExpanded,
    required this.onToggle,
    this.onAdd,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _kTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '($count)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kMutedText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _kMutedText,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onAdd != null)
          _SquareIconButton(icon: Icons.add_rounded, onTap: onAdd!)
        else if (onEdit != null)
          _SquareIconButton(icon: Icons.edit_outlined, onTap: onEdit!),
      ],
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SquareIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kChipBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: _kTextColor, size: 22),
        ),
      ),
    );
  }
}

class _DetailLine {
  final String label;
  final String value;
  const _DetailLine({required this.label, required this.value});
}

/// Card de item (experiência, educação, etc.). Avatar quadrado com inicial,
/// texto estruturado em linhas, bullets com "Mostrar mais (N)" e menu "...".
class _ItemCard extends StatefulWidget {
  final String avatarText;
  final String title;
  final String? subtitle;
  final String? period;
  final String? location;
  final List<String> bullets;
  final List<_DetailLine> details;
  final bool lowConfidence;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ItemCard({
    required this.avatarText,
    required this.title,
    required this.onTap,
    required this.onDelete,
    this.subtitle,
    this.period,
    this.location,
    this.bullets = const [],
    this.details = const [],
    this.lowConfidence = false,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  static const _initialBulletLimit = 1;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visibleBullets = _expanded
        ? widget.bullets
        : widget.bullets.take(_initialBulletLimit).toList();
    final hiddenCount = widget.bullets.length - visibleBullets.length;
    final letter = widget.avatarText.trim().isEmpty
        ? '?'
        : widget.avatarText.trim()[0].toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.lowConfidence ? AppColors.warning : _kBorderColor,
          width: widget.lowConfidence ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _kCardBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      letter,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _kTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _kTextColor,
                            height: 1.25,
                          ),
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              widget.subtitle!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: _kMutedText,
                              ),
                            ),
                          ),
                        if (widget.period != null && widget.period!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              widget.period!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _kMutedText,
                              ),
                            ),
                          ),
                        if (widget.location != null &&
                            widget.location!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              widget.location!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _kMutedText,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _ItemMenuButton(
                    onEdit: widget.onTap,
                    onDelete: widget.onDelete,
                  ),
                ],
              ),
              if (widget.bullets.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...visibleBullets.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6, right: 8),
                          child: Icon(
                            Icons.circle,
                            size: 4,
                            color: _kMutedText,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            b,
                            style: const TextStyle(
                              fontSize: 14,
                              color: _kTextColor,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (hiddenCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: GestureDetector(
                      onTap: () => setState(() => _expanded = true),
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        'Mostrar mais ($hiddenCount)',
                        style: const TextStyle(
                          fontSize: 14,
                          color: _kMutedText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
              if (widget.details.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...widget.details.map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: _kTextColor,
                        ),
                        children: [
                          TextSpan(
                            text: '${d.label}: ',
                            style: const TextStyle(color: _kMutedText),
                          ),
                          TextSpan(text: d.value),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (widget.lowConfidence) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warningSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Confirme',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemMenuButton extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ItemMenuButton({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, color: _kMutedText, size: 22),
      padding: EdgeInsets.zero,
      tooltip: '',
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18, color: _kTextColor),
              SizedBox(width: 10),
              Text('Editar'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.error,
              ),
              const SizedBox(width: 10),
              Text('Excluir', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChipList extends StatelessWidget {
  final List<String> items;
  const _ChipList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((s) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _kChipBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              s,
              style: const TextStyle(
                fontSize: 14,
                color: _kTextColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
