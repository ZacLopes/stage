// Fase 2 (casa única do perfil): card "Currículo geral" no topo de
// Perfil → Currículos.
//
// O currículo geral é uma projeção VIRTUAL do perfil (profile_*) — não é um
// registro de saved_resumes. Este card NÃO participa de sort, NÃO entra na
// legenda de SavedResumeSource, NÃO pode ser excluído, NÃO incrementa
// savedResumes e NÃO gera INSERT/UPDATE no banco. Ele só oferece "Ver prévia"
// e "Exportar PDF", ambos derivando do perfil na hora.
//
// Estados (via GeneralResumeExport.profileHasContent — mesmo contrato do export):
//   • carregando inicial (VM sem dados ainda) → skeleton, sem decidir empty;
//   • com conteúdo → "Ver prévia" + "Exportar PDF";
//   • sem conteúdo → "Complete seus Dados..." + "Completar perfil" (→ Perfil →
//     Dados via HomeViewModel.requestProfileSubTab(0), sem rota nova).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../home/home_viewmodel.dart';
import '../../profile/application/profile_editor_view_model.dart';
import '../services/general_resume_export.dart';
import 'general_resume_preview.dart';

/// Card do currículo geral, conectado ao perfil canônico.
class GeneralResumeCard extends StatefulWidget {
  const GeneralResumeCard({super.key});

  @override
  State<GeneralResumeCard> createState() => _GeneralResumeCardState();
}

class _GeneralResumeCardState extends State<GeneralResumeCard> {
  bool _isExporting = false;

  Future<void> _export() async {
    await GeneralResumeExport.export(
      context,
      onBusyChanged: (b) {
        if (mounted) setState(() => _isExporting = b);
      },
    );
  }

  void _openPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GeneralResumePreviewScreen()),
    );
  }

  void _goToData() {
    // Leva a Perfil → Dados (sub-aba 0) pelo TabController existente da
    // ProfileScreen — sem criar rota nova de editor.
    try {
      context.read<HomeViewModel>().requestProfileSubTab(0);
    } catch (_) {
      // Sem HomeViewModel (teste isolado): no-op.
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProfileEditorViewModel>();
    final hasContent = GeneralResumeExport.profileHasContent(p);
    // Carregamento inicial = VM carregando E ainda sem conteúdo. Evita o falso
    // "Complete seus Dados" antes do perfil terminar de carregar. Num reload
    // com dados já presentes, hasContent segue true (sem flicker pra loading).
    final loading = p.isLoading && !hasContent;
    return GeneralResumeCardView(
      hasContent: hasContent,
      isLoading: loading,
      isExporting: _isExporting,
      onPreview: _openPreview,
      onExport: _export,
      onCompleteProfile: _goToData,
    );
  }
}

/// Body puro do card — sem Provider, testável diretamente.
class GeneralResumeCardView extends StatelessWidget {
  const GeneralResumeCardView({
    super.key,
    required this.hasContent,
    this.isLoading = false,
    this.isExporting = false,
    this.onPreview,
    this.onExport,
    this.onCompleteProfile,
  });

  final bool hasContent;
  final bool isLoading;
  final bool isExporting;
  final VoidCallback? onPreview;
  final VoidCallback? onExport;
  final VoidCallback? onCompleteProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: AppRadius.brMd,
                ),
                child: const Icon(
                  Icons.description_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text(
                  'Currículo geral',
                  style: AppTextStyles.titleSm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _generatedBadge(),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._bodyForState(),
        ],
      ),
    );
  }

  List<Widget> _bodyForState() {
    if (isLoading) {
      return [
        Text(
          'Carregando seu perfil…',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.base),
        const LinearProgressIndicator(
          minHeight: 3,
          backgroundColor: AppColors.border,
          color: AppColors.primary,
        ),
      ];
    }
    if (hasContent) {
      return [
        Text(
          'Gerado a partir dos dados atuais do seu perfil.',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.base),
        _responsiveCtas(),
      ];
    }
    return [
      Text(
        'Complete seus Dados para gerar seu currículo.',
        style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.base),
      SizedBox(
        width: double.infinity,
        child: PrimaryButton(
          label: 'Completar perfil',
          icon: Icons.arrow_forward_rounded,
          onPressed: onCompleteProfile,
        ),
      ),
    ];
  }

  /// CTAs responsivos: EMPILHADOS full-width em largura compacta (padrão em
  /// phones); LADO A LADO só quando há folga real. O "Exportar PDF" é largo
  /// (ícone + padding xl), então lado a lado usa botões no tamanho natural
  /// (expand:false) — nunca dois Expanded 50/50, que estrangulariam o export e
  /// dariam overflow. Threshold 440 garante que os dois caibam sem RenderFlex
  /// overflow; abaixo disso, empilha.
  Widget _responsiveCtas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 440) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _previewButton(expand: false),
              _exportButton(expand: false),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: _exportButton(expand: true),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: _previewButton(expand: true),
            ),
          ],
        );
      },
    );
  }

  Widget _previewButton({required bool expand}) => SecondaryButton(
    label: 'Ver prévia',
    expand: expand,
    onPressed: onPreview,
  );

  Widget _exportButton({required bool expand}) => PrimaryButton(
    label: 'Exportar PDF',
    icon: Icons.upload_rounded,
    isLoading: isExporting,
    expand: expand,
    onPressed: onExport,
  );

  Widget _generatedBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.primarySoft,
      borderRadius: AppRadius.brPill,
    ),
    child: Text(
      'Gerado do perfil',
      style: AppTextStyles.labelSm.copyWith(color: AppColors.primary),
    ),
  );
}
