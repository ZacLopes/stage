// Fase 2 (casa única do perfil): card "Currículo geral" no topo de
// Perfil → Currículos.
//
// O CONTEÚDO do currículo geral é uma projeção VIRTUAL do perfil (profile_*).
// F4.4: com a flag ON, o export persiste uma VERSÃO (source='general') e o card
// vira um documento real — mostra "última versão salva em DD/MM", um badge
// "Perfil mudou" quando o perfil foi editado depois da versão (fingerprint
// atual ≠ o da versão), e um seletor de modelo pro próximo export. A leitura da
// versão + o cálculo de staleness são best-effort (falham em silêncio; o card
// nunca trava). Sem versão (ou flag OFF), o card segue com a copy anterior.
//
// Estados (via GeneralResumeExport.profileHasContent — mesmo contrato do export):
//   • carregando inicial (VM sem dados ainda) → skeleton, sem decidir empty;
//   • com conteúdo → versão/staleness/modelo + "Ver prévia" + "Exportar PDF";
//   • sem conteúdo → "Complete seus Dados..." + "Completar perfil" (→ Perfil →
//     Dados via HomeViewModel.requestProfileSubTab(0), sem rota nova).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/contact_email.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/user_viewmodel.dart';
import '../../home/home_viewmodel.dart';
import '../../profile/application/profile_editor_view_model.dart';
import '../resume_viewmodel.dart';
import '../services/general_resume_export.dart';
import '../services/general_resume_status.dart';
import 'general_resume_preview.dart';
import 'resume_template_selector.dart';

/// Card do currículo geral, conectado ao perfil canônico.
class GeneralResumeCard extends StatefulWidget {
  const GeneralResumeCard({super.key});

  @override
  State<GeneralResumeCard> createState() => _GeneralResumeCardState();
}

class _GeneralResumeCardState extends State<GeneralResumeCard> {
  bool _isExporting = false;
  GeneralResumeStatus _status = GeneralResumeStatus.none;
  bool _templateInitialized = false;

  /// Template do CURRÍCULO GERAL — estado local deste card, não o singleton
  /// global do ResumeViewModel (que é compartilhado com o CV adaptado por vaga
  /// e o CV da trilha). Semeado da última versão salva; quando o usuário troca
  /// pelo seletor, capturamos a escolha aqui em vez de deixar o global mandar.
  String? _generalTemplateId;

  /// Template efetivo do Currículo geral: a escolha local, senão o global
  /// (que é o que o seletor escreve quando o usuário troca explicitamente).
  String _effectiveTemplateId(ResumeViewModel vm) =>
      _generalTemplateId ?? vm.selectedTemplateId;
  final GeneralResumeStatusLoader _loader =
      GeneralResumeStatusLoader.production();

  @override
  void initState() {
    super.initState();
    // Sem assinatura de ProfileEvents: a última versão salva só muda quando o
    // usuário EXPORTA — editar o perfil não toca `saved_resumes`. Antes o card
    // recarregava as 10 tabelas do perfil e re-hasheava o currículo a cada
    // evento, só para recalcular o selo que saiu em 27/07.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadStatus());
  }

  Future<void> _reloadStatus() async {
    if (!mounted) return;
    final userVM = context.read<UserViewModel>();
    final uid = userVM.user?.id ??
        Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _status = GeneralResumeStatus.none);
      return;
    }
    final fallbackName = userVM.user?.name;
    GeneralResumeStatus status;
    try {
      status = await _loader.load(uid, userFallbackName: fallbackName);
    } catch (_) {
      return; // status best-effort — falha não altera o que já está no card.
    }
    if (!mounted) return;
    // Code-review 27/07: aqui era `context.read<ResumeViewModel>()
    // .setSelectedTemplateId(v.templateId)` — uma escrita SILENCIOSA num
    // singleton GLOBAL, feita só por montar Perfil → Currículos.
    //
    // Esse mesmo `selectedTemplateId` é lido pelo CV adaptado por vaga
    // (resume_adaptation_sheet.dart:370, adapted_resume_preview_screen.dart:155)
    // e pelo CV da trilha (resume_viewmodel.dart:1937/1991). Resultado: quem
    // salvou o Currículo geral em Cobalt via o próximo CV adaptado sair em
    // Cobalt sem ter escolhido nada.
    //
    // Agora o template do Currículo geral é ESTADO LOCAL deste card e vai
    // explícito para o export. Nada vaza para os outros fluxos.
    final v = status.lastVersion;
    setState(() {
      _status = status;
      if (!_templateInitialized && v != null) {
        _templateInitialized = true;
        _generalTemplateId = v.templateId;
      }
    });
  }

  Future<void> _export() async {
    await GeneralResumeExport.export(
      context,
      templateId: _generalTemplateId,
      onBusyChanged: (b) {
        if (mounted) setState(() => _isExporting = b);
      },
    );
    // O export não dispara ProfileEvents (não muta o perfil), mas a versão pode
    // ter mudado → recarrega pra refletir a nova data e limpar o "Perfil mudou".
    await _reloadStatus();
  }

  void _openPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GeneralResumePreviewScreen()),
    );
  }

  void _pickTemplate() {
    // O seletor já escreve `selectedTemplateId` no ResumeViewModel — o chip e o
    // export refletem a escolha (o card observa o ResumeViewModel).
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ResumeTemplateSelector(),
    ).then((_) {
      // Escolha EXPLÍCITA do usuário: captura localmente para o export do
      // Currículo geral usar, sem depender do singleton continuar com esse
      // valor (outros fluxos também escrevem nele).
      if (!mounted) return;
      setState(() {
        _generalTemplateId = context.read<ResumeViewModel>().selectedTemplateId;
      });
    });
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

  String? _versionLabel() {
    final v = _status.lastVersion;
    if (v == null) return null;
    final d = v.createdAt?.toLocal();
    if (d == null) return 'Última versão salva';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Última versão salva em ${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProfileEditorViewModel>();
    final resumeVM = context.watch<ResumeViewModel>();
    final hasContent = GeneralResumeExport.profileHasContent(p);
    // Carregamento inicial = VM carregando E ainda sem conteúdo. Evita o falso
    // "Complete seus Dados" antes do perfil terminar de carregar. Num reload
    // com dados já presentes, hasContent segue true (sem flicker pra loading).
    final loading = p.isLoading && !hasContent;
    return GeneralResumeCardView(
      hasContent: hasContent,
      hasUsableContactEmail: ContactEmail.isUsable(p.personal?.email),
      isLoading: loading,
      isExporting: _isExporting,
      versionLabel: _versionLabel(),
      templateName:
          ResumeTemplateSelector.displayName(_effectiveTemplateId(resumeVM)),
      onPreview: _openPreview,
      onExport: _export,
      onPickTemplate: _pickTemplate,
      onCompleteProfile: _goToData,
    );
  }
}

/// Body puro do card — sem Provider, testável diretamente.
class GeneralResumeCardView extends StatelessWidget {
  const GeneralResumeCardView({
    super.key,
    required this.hasContent,
    this.hasUsableContactEmail = true,
    this.isLoading = false,
    this.isExporting = false,
    this.versionLabel,
    this.templateName,
    this.onPreview,
    this.onExport,
    this.onPickTemplate,
    this.onCompleteProfile,
  });

  final bool hasContent;
  final bool hasUsableContactEmail;
  final bool isLoading;
  final bool isExporting;

  /// "Última versão salva em DD/MM/YYYY" — null quando ainda não há versão
  /// persistida (então o card mostra a copy "gerado a partir dos dados atuais").
  final String? versionLabel;

  /// Perfil foi editado depois da última versão (fingerprint divergente).

  /// Nome do modelo que o próximo export usará (chip do seletor). null = não
  /// mostra a linha de modelo.
  final String? templateName;

  final VoidCallback? onPreview;
  final VoidCallback? onExport;
  final VoidCallback? onPickTemplate;
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
              _headerBadge(),
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
          versionLabel ?? 'Gerado a partir dos dados atuais do seu perfil.',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
        ),
        if (templateName != null) ...[
          const SizedBox(height: AppSpacing.md),
          _templateRow(),
        ],
        if (!hasUsableContactEmail) ...[
          const SizedBox(height: AppSpacing.md),
          _contactEmailWarning(),
        ],
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

  Widget _contactEmailWarning() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.warningSoft,
      borderRadius: AppRadius.brMd,
      border: Border.all(color: AppColors.warning),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adicione um e-mail de contato antes de enviar o currículo. Seu e-mail de login não será exibido.',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: onCompleteProfile,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Adicionar e-mail'),
        ),
      ],
    ),
  );

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

  /// Badge do header. O ramo âmbar "Perfil mudou" foi removido em 27/07 —
  /// ver general_resume_status.dart para o porquê.
  Widget _headerBadge() => _generatedBadge();

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

  /// Linha do modelo do próximo export + botão "Trocar" (abre o seletor).
  Widget _templateRow() => Row(
    children: [
      const Icon(
        Icons.style_outlined,
        size: 16,
        color: AppColors.textTertiary,
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          'Modelo: ${templateName ?? ''}',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      TextButton(
        onPressed: onPickTemplate,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('Trocar'),
      ),
    ],
  );
}
