// Bottom-sheet de verificação de uma seção do stepper da aba Currículo.
//
// O usuário toca numa seção do stepper (Formação/Experiência/Skills/Idiomas/
// Interesses) e abre este sheet pra CONFERIR o que a trilha coletou de verdade
// — os dados vêm do [ProfileEditorViewModel] (perfil real, já com o import +
// as respostas da conversa). View-only: corrigir é continuar a conversa.
//
// Ao abrir, dispara um `vm.load()` pra garantir frescor (reflete o que acabou
// de ser importado/respondido). Só tokens do design system.

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../profile/application/profile_editor_view_model.dart';
import '../../trilha/application/trilha_section.dart';

/// Abre o sheet de detalhe de [section]. [status] vem do stepper.
Future<void> showSectionDetailSheet(
  BuildContext context, {
  required TrilhaSection section,
  required SectionStatus status,
  required ProfileEditorViewModel vm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) =>
        _SectionDetailSheet(section: section, status: status, vm: vm),
  );
}

class _SectionDetailSheet extends StatefulWidget {
  const _SectionDetailSheet({
    required this.section,
    required this.status,
    required this.vm,
  });

  final TrilhaSection section;
  final SectionStatus status;
  final ProfileEditorViewModel vm;

  @override
  State<_SectionDetailSheet> createState() => _SectionDetailSheetState();
}

class _SectionDetailSheetState extends State<_SectionDetailSheet> {
  @override
  void initState() {
    super.initState();
    // Frescor: reflete o import / a última resposta sem depender de reload externo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: unawaited_futures
      widget.vm.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.82;
    // O inset da home-indicator é absorvido pelo FOOTER (não por um padding
    // externo que levantaria o sheet e deixaria a base "cortada" no escuro).
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      clipBehavior: Clip.antiAlias, // recorta o conteúdo no topo arredondado
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: AnimatedBuilder(
        animation: widget.vm,
        builder: (context, _) {
          final items = _items(widget.vm, widget.section);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppSpacing.sm),
              _handle(),
              _header(items.length),
              const Divider(height: 1, color: AppColors.border),
              Flexible(
                child: items.isEmpty
                    ? _empty()
                    : ListView(
                        padding: AppSpacing.allLg,
                        shrinkWrap: true,
                        children: _content(widget.section),
                      ),
              ),
              _footer(bottomInset),
            ],
          );
        },
      ),
    );
  }

  Widget _handle() => Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: AppRadius.brPill,
        ),
      );

  Widget _header(int count) {
    final s = widget.section;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppGradients.brand,
              borderRadius: AppRadius.brMd,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(_icon(s), color: AppColors.onPrimary, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trilhaSectionLabel(s), style: AppTextStyles.titleMd),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'Nada coletado ainda'
                      : '$count ${count == 1 ? _singular(s) : _plural(s)}',
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          _statusPill(),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final (Color bg, Color fg, String label, IconData icon) =
        switch (widget.status) {
      SectionStatus.done => (
          AppColors.successSoft,
          AppColors.success,
          'Coletado',
          Icons.check_circle_rounded,
        ),
      SectionStatus.current => (
          AppColors.primarySoft,
          AppColors.primary,
          'Coletando',
          Icons.bolt_rounded,
        ),
      SectionStatus.pending => (
          AppColors.surfaceVariant,
          AppColors.textTertiary,
          'A coletar',
          Icons.schedule_rounded,
        ),
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brPill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: AppTextStyles.labelSm
                  .copyWith(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Conteúdo por seção ──────────────────────────────────────────────────────

  /// Lista da seção (tipada via getters do VM) — só pra contagem/vazio.
  List<Object> _items(ProfileEditorViewModel vm, TrilhaSection s) {
    switch (s) {
      case TrilhaSection.formacao:
        return vm.education;
      case TrilhaSection.experiencia:
        return vm.experiences;
      case TrilhaSection.skills:
        return vm.skills;
      case TrilhaSection.idiomas:
        return vm.languages;
      case TrilhaSection.interesses:
        return vm.interests;
      case TrilhaSection.outros:
        return const [];
    }
  }

  List<Widget> _content(TrilhaSection s) {
    final vm = widget.vm;
    switch (s) {
      case TrilhaSection.skills:
        return [_chips([for (final x in vm.skills) x.name])];
      case TrilhaSection.interesses:
        return [_chips([for (final x in vm.interests) x.name])];
      case TrilhaSection.idiomas:
        return [
          for (final l in vm.languages) _row(l.name, l.proficiencyLabel),
        ];
      case TrilhaSection.experiencia:
        return [
          for (final e in vm.experiences)
            _entry(
              title: e.title,
              subtitle: [e.company, e.formattedPeriod]
                  .where((t) => t.trim().isNotEmpty)
                  .join(' · '),
            ),
        ];
      case TrilhaSection.formacao:
        return [
          for (final ed in vm.education)
            _entry(
              title: ed.majors.isNotEmpty
                  ? ed.majors.map((m) => m.name).join(', ')
                  : (ed.degree ?? 'Curso'),
              subtitle: [ed.institution, ed.formattedPeriod]
                  .where((t) => t.trim().isNotEmpty)
                  .join(' · '),
            ),
        ];
      case TrilhaSection.outros:
        return const [];
    }
  }

  Widget _chips(List<String> labels) => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final l in labels)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: AppRadius.brSm,
              ),
              child: Text(l,
                  style: AppTextStyles.labelMd
                      .copyWith(color: AppColors.primary)),
            ),
        ],
      );

  Widget _row(String name, String trailing) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: AppSpacing.allMd,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(name,
                  style: AppTextStyles.bodyMd
                      .copyWith(color: AppColors.textPrimary)),
            ),
            if (trailing.trim().isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: AppRadius.brPill,
                ),
                child: Text(trailing,
                    style: AppTextStyles.labelSm
                        .copyWith(color: AppColors.primary)),
              ),
            ],
          ],
        ),
      );

  Widget _entry({required String title, required String subtitle}) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: AppSpacing.allBase,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: AppTextStyles.labelMd
                    .copyWith(color: AppColors.textPrimary)),
            if (subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ],
        ),
      );

  Widget _empty() => Padding(
        padding: AppSpacing.allXl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(_icon(widget.section),
                  color: AppColors.textTertiary, size: 26),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Ainda não coletei isso',
                style: AppTextStyles.titleSm
                    .copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.status == SectionStatus.current
                  ? 'É o que estou perguntando agora na conversa.'
                  : 'A conversa vai cuidar disso 😉',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );

  Widget _footer(double bottomInset) => Container(
        width: double.infinity,
        color: AppColors.surfaceVariant, // o recorte do pai cuida do formato
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg,
            AppSpacing.lg + bottomInset),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 16, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Algo errado? É só me dizer na conversa que eu corrijo.',
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );

  IconData _icon(TrilhaSection s) => switch (s) {
        TrilhaSection.formacao => Icons.school_rounded,
        TrilhaSection.experiencia => Icons.work_rounded,
        TrilhaSection.skills => Icons.bolt_rounded,
        TrilhaSection.idiomas => Icons.translate_rounded,
        TrilhaSection.interesses => Icons.favorite_rounded,
        TrilhaSection.outros => Icons.more_horiz_rounded,
      };

  String _singular(TrilhaSection s) => switch (s) {
        TrilhaSection.formacao => 'formação',
        TrilhaSection.experiencia => 'experiência',
        TrilhaSection.skills => 'habilidade',
        TrilhaSection.idiomas => 'idioma',
        TrilhaSection.interesses => 'interesse',
        TrilhaSection.outros => 'item',
      };

  String _plural(TrilhaSection s) => switch (s) {
        TrilhaSection.formacao => 'formações',
        TrilhaSection.experiencia => 'experiências',
        TrilhaSection.skills => 'habilidades',
        TrilhaSection.idiomas => 'idiomas',
        TrilhaSection.interesses => 'interesses',
        TrilhaSection.outros => 'itens',
      };
}
