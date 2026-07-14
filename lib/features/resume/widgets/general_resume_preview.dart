// Fase 2 (casa única do perfil): prévia REUTILIZÁVEL do currículo geral.
//
// A prévia era privada na ResumeTab. Foi extraída pra este arquivo pra ser
// usada em DOIS lugares sem duplicar helpers:
//   1. Caminho de rollback da ResumeTab (trilha_assist_v1 OFF) — conversa +
//      prévia + toggle, comportamento legado intacto.
//   2. Tela de prévia (GeneralResumePreviewScreen) aberta por Perfil →
//      Currículos quando a flag está ON.
//
// A prévia lê o perfil canônico (ProfileEditorViewModel/profile_*) e se
// atualiza sozinha quando os dados mudam. NÃO persiste nada. As seções seguem
// o que o PDF do currículo geral renderiza (summary, skills, idiomas,
// experiência, formação, PROJETOS, certificações, prêmios, interesses) —
// coerente com o contrato de conteúdo em [GeneralResumeExport].
//
// EQUIVALÊNCIA prévia↔PDF é de CONJUNTO DE SEÇÕES, não pixel-a-pixel: em CVs
// longos o loop adaptativo do PdfService (RenderTier) pode APERTAR ou até
// suprimir seções de baixa prioridade — tipicamente `interests` — pra caber em
// 1 página. Isso é INTENCIONAL (legibilidade > completude), então a prévia pode
// mostrar Interesses que o PDF final omite num currículo denso. Não é bug de
// equivalência.
//
// Estrutura:
//   • GeneralResumePreview      — connected: lê o VM e monta o body.
//   • GeneralResumePreviewBody  — puro (dados planos), testável sem Provider.
//   • GeneralResumeExportBar    — barra "Exportar PDF" compartilhada.
//   • GeneralResumePreviewScreen — rota empilhável (Perfil → Currículos).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../profile/application/profile_editor_view_model.dart';
import '../../profile/domain/entities/entities.dart'
    show Award, Education, Project;
import '../../trilha/application/trilha_hub_status.dart';
import '../data/profile_resume_mapper.dart';
import '../services/general_resume_export.dart';

/// Um item de seção da prévia (título + subtítulo), já formatado pra exibição.
typedef PreviewRow = ({String title, String subtitle});

/// Converte um [Project] canônico na linha da prévia. Ancora o título na MESMA
/// ordem que o PDF surfaceia conteúdo (nome → papel → 1º bullet/descrição), pra
/// nunca gerar uma linha em branco quando o projeto não tem nome (o predicate
/// [ProfileResumeMapper.projectHasRenderableText] admite projetos
/// só-com-bullets).
/// `context` fica só no subtítulo (anotação secundária), nunca como título.
PreviewRow projectPreviewRow(Project pr) {
  final name = ProfileResumeMapper.mapProject(pr).title;
  final role = (pr.role ?? '').trim();
  final ctx = (pr.context ?? '').trim();
  final body = pr.bullets
      .map((b) => b.text.trim())
      .firstWhere(
        (t) => t.isNotEmpty,
        orElse: () => (pr.description ?? '').trim(),
      );
  final title = name.isNotEmpty
      ? name
      : role.isNotEmpty
      ? role
      : (body.isNotEmpty ? body : ctx);
  final subtitle = [
    if (name.isNotEmpty && role.isNotEmpty) role,
    if (ctx.isNotEmpty) ctx,
  ].join(' · ');
  return (title: title, subtitle: subtitle);
}

/// Linha de formação baseada na MESMA projeção do PDF. Assim o card não
/// reintroduz degree/major duplicados e mostra a previsão de conclusão antes
/// de a pessoa exportar o documento.
PreviewRow educationPreviewRow(Education education) {
  final mapped = ProfileResumeMapper.mapEducation(education);
  return (
    title: mapped.degree.isEmpty ? 'Curso' : mapped.degree,
    subtitle: [
      mapped.institution,
      mapped.period,
    ].where((part) => part.trim().isNotEmpty).join(' · '),
  );
}

String awardPreviewTitle(Award award) =>
    ProfileResumeMapper.mapAward(award).title;

/// Prévia do currículo geral conectada ao perfil canônico. Reconstrói (e o PDF
/// exportado reflete) sempre que o [ProfileEditorViewModel] muda.
class GeneralResumePreview extends StatelessWidget {
  const GeneralResumePreview({
    super.key,
    this.hubStatus,
    this.padding,
    this.emptySubtitle = 'Continue a conversa para completar seu perfil.',
  });

  /// Força honesta do perfil (opcional). Quando null, o header cai no
  /// completeness do banco em cor neutra e o painel "próximo ganho" some.
  final TrilhaHubStatus? hubStatus;
  final EdgeInsetsGeometry? padding;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProfileEditorViewModel>();
    return GeneralResumePreviewBody(
      name: p.personal?.fullName.trim() ?? '',
      location: p.personal?.formattedLocation.trim() ?? '',
      strengthPercent: hubStatus?.strengthPercent ?? p.completenessScore,
      hubStatus: hubStatus,
      // Só `summary` (o headline não é renderizado pelo PDF — ver
      // GeneralResumeExport).
      summary: (p.personal?.summary ?? '').trim(),
      // Mesmo trim do predicate/mapper/PDF — item sem texto após trim NÃO vira
      // chip/linha/seção (contrato §5). Espelha os filtros de cert./prêmios.
      skills: p.skills
          .map((s) => s.name)
          .where((n) => n.trim().isNotEmpty)
          .toList(),
      languages: p.languages
          .where((l) => l.name.trim().isNotEmpty)
          .map((l) => (name: l.name, level: l.proficiencyLabel))
          .toList(),
      experiences: p.experiences
          .map(
            (e) => (
              title: e.title,
              subtitle: [
                e.company,
                e.formattedPeriod,
              ].where((s) => s.trim().isNotEmpty).join(' · '),
            ),
          )
          .toList(),
      education: p.education.map(educationPreviewRow).toList(),
      // Projetos filtrados pelo MESMO critério do predicate/mapper
      // (ProfileResumeMapper.projectHasRenderableText) e mapeados por
      // [projectPreviewRow] (título nunca vazio) — coerência prévia↔PDF.
      projects: p.projects
          .where(ProfileResumeMapper.projectHasRenderableText)
          .map(projectPreviewRow)
          .toList(),
      certifications: p.certifications
          .map((c) => c.name)
          .where((n) => n.trim().isNotEmpty)
          .toList(),
      awards: p.awards
          .map(awardPreviewTitle)
          .where((n) => n.trim().isNotEmpty)
          .toList(),
      interests: p.interests
          .map((i) => i.name)
          .where((n) => n.trim().isNotEmpty)
          .toList(),
      padding: padding,
      emptySubtitle: emptySubtitle,
    );
  }
}

/// Body puro da prévia — recebe dados já planos, sem Provider. Renderiza o
/// mesmo layout de sempre (header + seções + empty state), dentro de [PiiMask].
class GeneralResumePreviewBody extends StatelessWidget {
  const GeneralResumePreviewBody({
    super.key,
    required this.name,
    required this.location,
    required this.strengthPercent,
    required this.hubStatus,
    this.summary = '',
    required this.skills,
    required this.languages,
    required this.experiences,
    required this.education,
    this.projects = const [],
    this.certifications = const [],
    this.awards = const [],
    required this.interests,
    this.padding,
    this.emptySubtitle = 'Continue a conversa para completar seu perfil.',
  });

  final String name;
  final String location;
  final int strengthPercent;
  final TrilhaHubStatus? hubStatus;
  final String summary;
  final List<String> skills;
  final List<({String name, String level})> languages;
  final List<PreviewRow> experiences;
  final List<PreviewRow> education;
  final List<PreviewRow> projects;
  final List<String> certifications;
  final List<String> awards;
  final List<String> interests;
  final EdgeInsetsGeometry? padding;
  final String emptySubtitle;

  bool get _hasAny =>
      summary.trim().isNotEmpty ||
      experiences.isNotEmpty ||
      skills.isNotEmpty ||
      education.isNotEmpty ||
      projects.isNotEmpty ||
      languages.isNotEmpty ||
      certifications.isNotEmpty ||
      awards.isNotEmpty ||
      interests.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return PiiMask(
      child: _hasAny
          ? ListView(
              padding:
                  padding ??
                  const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
              children: [
                _header(),
                if (summary.trim().isNotEmpty) _summarySection(),
                if (skills.isNotEmpty) _chipsSection('Habilidades', skills),
                if (languages.isNotEmpty) _languagesSection(),
                if (experiences.isNotEmpty)
                  _rowsSection('Experiência', experiences),
                if (education.isNotEmpty) _rowsSection('Formação', education),
                if (projects.isNotEmpty) _rowsSection('Projetos', projects),
                if (certifications.isNotEmpty)
                  _chipsSection('Certificações', certifications),
                if (awards.isNotEmpty) _chipsSection('Prêmios', awards),
                if (interests.isNotEmpty)
                  _chipsSection('Áreas de interesse', interests),
              ],
            )
          : _previewEmpty(),
    );
  }

  Widget _previewEmpty() => Center(
    child: Padding(
      padding: AppSpacing.allXl,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.description_outlined,
            color: AppColors.textTertiary,
            size: 40,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Seu currículo aparece aqui',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleSm.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            emptySubtitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _header() {
    final hs = hubStatus;
    final pct = strengthPercent;
    final initials = _initials(name);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.base),
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: AppRadius.brMd,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: AppTextStyles.titleSm.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Seu perfil' : name,
                      style: AppTextStyles.titleSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        location,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              _strengthBadge(pct, hs?.level),
            ],
          ),
          // Painel honesto: nunca "beco sem saída". Mostra o próximo ganho (ou
          // comemora de verdade quando não falta nada). Fase 7 · +10 Tarefa 4.
          if (hs != null) ...[
            const SizedBox(height: AppSpacing.md),
            _hubNextWin(hs),
          ],
        ],
      ),
    );
  }

  /// Pílula de força colorida pelo ESTÁGIO real — verde só quando é verdade.
  Widget _strengthBadge(int pct, HubLevel? level) {
    Color bg;
    Color fg;
    switch (level) {
      case HubLevel.complete:
      case HubLevel.shortlistReady:
        bg = AppColors.successSoft;
        fg = AppColors.success;
      case HubLevel.building:
        bg = AppColors.warningSoft;
        fg = AppColors.warning;
      case null:
        bg = AppColors.border;
        fg = AppColors.textTertiary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brPill),
      child: Text('$pct%', style: AppTextStyles.labelSm.copyWith(color: fg)),
    );
  }

  /// O próximo ganho enquadrado por valor — ou a comemoração honesta (completo).
  Widget _hubNextWin(TrilhaHubStatus hs) {
    if (hs.level == HubLevel.complete) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_rounded,
            size: 16,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              hs.message,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.trending_up_rounded,
              size: 15,
              color: AppColors.warning,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'PRÓXIMO GANHO',
              style: AppTextStyles.overline.copyWith(
                color: AppColors.warning,
                letterSpacing: 0.6,
              ),
            ),
            if (hs.nextStepLabel != null)
              Expanded(
                child: Text(
                  ' · ${hs.nextStepLabel}',
                  style: AppTextStyles.overline.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hs.message,
          style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      t.toUpperCase(),
      style: AppTextStyles.overline.copyWith(letterSpacing: 0.6),
    ),
  );

  Widget _card({required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.base),
    padding: AppSpacing.allBase,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.brLg,
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [child],
    ),
  );

  Widget _summarySection() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Resumo'),
        Text(
          summary.trim(),
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  Widget _chipsSection(String title, List<String> items) {
    // Defesa: nunca renderiza chip/seção vazia mesmo se um item só-espaço
    // escapar (o filtro primário é no mapper conectado).
    final visible = items.where((it) => it.trim().isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(title),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final it in visible)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: AppRadius.brSm,
                  ),
                  child: Text(
                    it,
                    style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _languagesSection() {
    final visible = languages.where((l) => l.name.trim().isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Idiomas'),
          for (final lang in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    lang.name,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    lang.level,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rowsSection(String title, List<PreviewRow> rows) {
    // Defesa: descarta linhas totalmente vazias (título E subtítulo em branco).
    final visible = rows
        .where((r) => r.title.trim().isNotEmpty || r.subtitle.trim().isNotEmpty)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(title),
          for (final row in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.title, style: AppTextStyles.labelMd),
                  if (row.subtitle.trim().isNotEmpty)
                    Text(
                      row.subtitle,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '·';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Barra inferior com o botão "Exportar PDF" do currículo geral. Compartilhada
/// entre o rollback da ResumeTab e a tela de prévia. Gerencia seu próprio
/// spinner e desabilita quando o perfil não tem conteúdo renderável.
class GeneralResumeExportBar extends StatefulWidget {
  const GeneralResumeExportBar({super.key});

  @override
  State<GeneralResumeExportBar> createState() => _GeneralResumeExportBarState();
}

class _GeneralResumeExportBarState extends State<GeneralResumeExportBar> {
  bool _isExporting = false;

  Future<void> _export() async {
    await GeneralResumeExport.export(
      context,
      onBusyChanged: (b) {
        if (mounted) setState(() => _isExporting = b);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reconstrói quando o perfil muda pra (des)habilitar o botão.
    final p = context.watch<ProfileEditorViewModel>();
    final canExport = GeneralResumeExport.profileHasContent(p);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: PrimaryButton(
          label: 'Exportar PDF',
          icon: Icons.upload_rounded,
          isLoading: _isExporting,
          onPressed: canExport ? _export : null,
        ),
      ),
    );
  }
}

/// Tela empilhável de prévia do currículo geral, aberta por Perfil →
/// Currículos. Ao voltar, o usuário retorna a Perfil → Currículos.
class GeneralResumePreviewScreen extends StatefulWidget {
  const GeneralResumePreviewScreen({super.key});

  @override
  State<GeneralResumePreviewScreen> createState() =>
      _GeneralResumePreviewScreenState();
}

class _GeneralResumePreviewScreenState
    extends State<GeneralResumePreviewScreen> {
  TrilhaHubStatus? _hubStatus;

  @override
  void initState() {
    super.initState();
    _loadHub();
  }

  Future<void> _loadHub() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final s = await loadTrilhaHubStatus(uid);
      if (mounted) setState(() => _hubStatus = s);
    } catch (_) {
      // Sem hub → header cai no completeness. Nunca trava a tela.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Prévia do currículo', style: AppTextStyles.titleMd),
      ),
      body: Column(
        children: [
          Expanded(
            child: GeneralResumePreview(
              hubStatus: _hubStatus,
              emptySubtitle: 'Complete seus Dados para gerar seu currículo.',
            ),
          ),
          const GeneralResumeExportBar(),
        ],
      ),
    );
  }
}
