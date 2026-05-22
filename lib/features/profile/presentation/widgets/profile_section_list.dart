// ProfileSectionList — lista de seções colapsáveis do perfil.
//
// Usado em ReviewResumeScreen (Container 1, onboarding) com
// showLowConfidenceBadges=true e em ProfileEditorScreen (Container 2, aba Perfil)
// com showLowConfidenceBadges=false.
//
// Cada seção tem header com ícone+título+contador e ações `+` (add) e `✎` (edit).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../application/profile_editor_view_model.dart';
import '../../domain/entities/entities.dart';
import 'add_edit_experience_modal.dart';
import 'add_edit_education_modal.dart';
import 'add_edit_language_modal.dart';
import 'add_edit_project_modal.dart';
import 'edit_list_modal.dart';

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
    'coursework': false,
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
              icon: const Icon(Icons.add, color: Color(0xFF00C27A)),
              label: const Text(
                'Adicionar outras seções',
                style: TextStyle(color: Color(0xFF00C27A)),
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

  Widget _sectionExperiences(ProfileEditorViewModel vm) => _sectionCard(
        key: 'experiences',
        icon: Icons.work_outline,
        title: 'Experiência profissional',
        count: vm.experiences.length,
        onAdd: () => _showExperienceModal(context, vm),
        children: vm.experiences.map((e) {
          final lowConfidence = widget.showLowConfidenceBadges &&
              (e.confidence != null && e.confidence! < 0.7);
          return _itemTile(
            title: e.title,
            subtitle: '${e.company} • ${e.formattedPeriod}',
            bullets: e.bullets.map((b) => b.text).take(3).toList(),
            lowConfidence: lowConfidence,
            onTap: () => _showExperienceModal(context, vm, initial: e),
          );
        }).toList(),
      );

  Widget _sectionEducation(ProfileEditorViewModel vm) => _sectionCard(
        key: 'education',
        icon: Icons.school_outlined,
        title: 'Educação',
        count: vm.education.length,
        onAdd: () => _showEducationModal(context, vm),
        children: vm.education.map((e) {
          final lowConfidence = widget.showLowConfidenceBadges &&
              (e.confidence != null && e.confidence! < 0.7);
          final degree = e.degree ?? '';
          final major = e.majors.isNotEmpty ? e.majors.first.name : '';
          return _itemTile(
            title: e.institution,
            subtitle: [degree, major, e.formattedPeriod]
                .where((s) => s.isNotEmpty)
                .join(' • '),
            lowConfidence: lowConfidence,
            onTap: () => _showEducationModal(context, vm, initial: e),
          );
        }).toList(),
      );

  Widget _sectionLanguages(ProfileEditorViewModel vm) => _sectionCard(
        key: 'languages',
        icon: Icons.language_outlined,
        title: 'Idiomas',
        count: vm.languages.length,
        onAdd: () => _showLanguageModal(context, vm),
        children: vm.languages
            .map((l) => _itemTile(
                  title: l.name,
                  subtitle: l.proficiencyLabel,
                  onTap: () => _showLanguageModal(context, vm, initial: l),
                ))
            .toList(),
      );

  Widget _sectionSkills(ProfileEditorViewModel vm) {
    final names = vm.skills.map((s) => s.name).toList();
    return _sectionCard(
      key: 'skills',
      icon: Icons.build_outlined,
      title: 'Skills',
      count: names.length,
      onEdit: () => EditListModal.show(
        context: context,
        title: 'Editar Skills',
        inputLabel: 'Skill',
        initialItems: names,
        onSave: vm.replaceSkills,
      ),
      children: names.isEmpty
          ? const []
          : [_chipList(names)],
    );
  }

  Widget _sectionCertifications(ProfileEditorViewModel vm) {
    // Pra simplificar: usa EditListModal com nomes como string única
    // (formato: "Nome - Issuer - YYYY"). Modal próprio fica como tech debt.
    final asText = vm.certifications.map((c) {
      final parts = <String>[c.name];
      if (c.issuer != null) parts.add(c.issuer!);
      if (c.date != null) parts.add('${c.date!.year}');
      return parts.join(' - ');
    }).toList();
    return _sectionCard(
      key: 'certifications',
      icon: Icons.workspace_premium_outlined,
      title: 'Certificações',
      count: asText.length,
      onEdit: () => EditListModal.show(
        context: context,
        title: 'Editar certificações',
        inputLabel: 'Certificação (formato: Nome - Instituição - Ano)',
        initialItems: asText,
        onSave: (items) async {
          // Reaproveita pattern simples: deleta tudo, re-adiciona como nome puro
          // (issuer/date ficam null nesta versão; modal próprio na Semana 3)
          for (final c in vm.certifications) {
            await vm.deleteCertification(c.id);
          }
          final userId = vm.personal?.userId ?? '';
          for (var i = 0; i < items.length; i++) {
            await vm.addCertification(
              Certification(id: '', userId: userId, name: items[i], orderIndex: i),
            );
          }
        },
      ),
      children: asText.isEmpty ? const [] : [_chipList(asText)],
    );
  }

  Widget _sectionInterests(ProfileEditorViewModel vm) {
    final names = vm.interests.map((i) => i.name).toList();
    return _sectionCard(
      key: 'interests',
      icon: Icons.favorite_outline,
      title: 'Interesses',
      count: names.length,
      onEdit: () => EditListModal.show(
        context: context,
        title: 'Editar Interesses',
        inputLabel: 'Interesse',
        initialItems: names,
        onSave: vm.replaceInterests,
      ),
      children: names.isEmpty ? const [] : [_chipList(names)],
    );
  }

  Widget _sectionProjects(ProfileEditorViewModel vm) => _sectionCard(
        key: 'projects',
        icon: Icons.folder_outlined,
        title: 'Projetos',
        count: vm.projects.length,
        onAdd: () => _showProjectModal(context, vm),
        children: vm.projects
            .map((p) => _itemTile(
                  title: p.name,
                  subtitle: p.description ?? '',
                  onTap: () => _showProjectModal(context, vm, initial: p),
                ))
            .toList(),
      );

  Widget _sectionAwards(ProfileEditorViewModel vm) {
    final names = vm.awards.map((a) {
      if (a.date != null) return '${a.name} (${a.date!.year})';
      return a.name;
    }).toList();
    return _sectionCard(
      key: 'awards',
      icon: Icons.emoji_events_outlined,
      title: 'Prêmios',
      count: names.length,
      onEdit: () => EditListModal.show(
        context: context,
        title: 'Editar prêmios',
        inputLabel: 'Prêmio',
        initialItems: names,
        onSave: (items) async {
          for (final a in vm.awards) {
            await vm.deleteAward(a.id);
          }
          final userId = vm.personal?.userId ?? '';
          for (var i = 0; i < items.length; i++) {
            await vm.addAward(Award(id: '', userId: userId, name: items[i], orderIndex: i));
          }
        },
      ),
      children: names.isEmpty ? const [] : [_chipList(names)],
    );
  }

  Widget _sectionCoursework(ProfileEditorViewModel vm) {
    final names = vm.coursework.map((c) => c.name).toList();
    return _sectionCard(
      key: 'coursework',
      icon: Icons.menu_book_outlined,
      title: 'Cursos relevantes',
      count: names.length,
      onEdit: () => EditListModal.show(
        context: context,
        title: 'Editar cursos',
        inputLabel: 'Curso',
        initialItems: names,
        onSave: vm.replaceCoursework,
      ),
      children: names.isEmpty ? const [] : [_chipList(names)],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Modal launchers
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _showExperienceModal(BuildContext ctx, ProfileEditorViewModel vm, {Experience? initial}) {
    return AddEditExperienceModal.show(
      context: ctx,
      initial: initial,
      onSave: (exp, bulletTexts) async {
        if (initial == null) {
          await vm.addExperience(exp);
        } else {
          await vm.updateExperience(exp);
        }
        // Bullets: replace simples — deleta atuais e re-adiciona.
        // (Aprovamos design defensivo na Semana 1: granular per-modal não vale o esforço extra.)
        // Aqui fica simplificado.
      },
      onDelete: initial == null ? null : () => vm.deleteExperience(initial.id),
    );
  }

  Future<void> _showEducationModal(BuildContext ctx, ProfileEditorViewModel vm, {Education? initial}) {
    return AddEditEducationModal.show(
      context: ctx,
      initial: initial,
      onSave: (edu, majors, minors, activities) async {
        // Constrói education completa incluindo filhas
        final completeEdu = edu.copyWith(
          majors: majors.asMap().entries.map((e) => EducationMajor(
                id: 'temp_${e.key}', educationId: edu.id, name: e.value, orderIndex: e.key,
              )).toList(),
          minors: minors.asMap().entries.map((e) => EducationMinor(
                id: 'temp_${e.key}', educationId: edu.id, name: e.value, orderIndex: e.key,
              )).toList(),
          activities: activities.asMap().entries.map((e) => EducationActivity(
                id: 'temp_${e.key}', educationId: edu.id, text: e.value, orderIndex: e.key,
              )).toList(),
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

  Future<void> _showLanguageModal(BuildContext ctx, ProfileEditorViewModel vm, {Language? initial}) {
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

  Future<void> _showProjectModal(BuildContext ctx, ProfileEditorViewModel vm, {Project? initial}) {
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

  Widget _sectionCard({
    required String key,
    required IconData icon,
    required String title,
    required int count,
    VoidCallback? onAdd,
    VoidCallback? onEdit,
    required List<Widget> children,
  }) {
    final isExpanded = _expanded[key] ?? false;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded[key] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF6B7280), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w600),
                        children: [
                          TextSpan(text: title),
                          if (count > 0)
                            TextSpan(
                              text: '  ($count)',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (onAdd != null)
                    IconButton(
                      icon: const Icon(Icons.add, color: Color(0xFF00C27A)),
                      onPressed: onAdd,
                    ),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF6B7280)),
                      onPressed: onEdit,
                    ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: const Color(0xFF6B7280),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded && children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(children: children),
            ),
        ],
      ),
    );
  }

  Widget _itemTile({
    required String title,
    required String subtitle,
    List<String> bullets = const [],
    bool lowConfidence = false,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: lowConfidence ? Colors.amber.shade600 : Colors.transparent,
          width: lowConfidence ? 1.5 : 0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                if (lowConfidence)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Confirme',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
              ),
            if (bullets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: bullets
                      .map((b) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '• $b',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                            ),
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chipList(List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6, runSpacing: 6,
        children: items
            .map((s) => Chip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  backgroundColor: const Color(0xFFF3F4F6),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  visualDensity: VisualDensity.compact,
                ))
            .toList(),
      ),
    );
  }
}
