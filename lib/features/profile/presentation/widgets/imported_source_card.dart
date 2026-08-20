// Fase 5 (IA/Perfil) — F5.2: card compacto "Fonte importada" em Perfil → Dados.
//
// O CV importado é FONTE/proveniência (não um documento de saída), então deixa
// a lista de Currículos (F5.3) e ganha esta casa em Dados. O card mostra o CV
// importado ATUAL (nome + data + status de extração honesto) e oferece:
//   • Ver → abre o detalhe view-only (a nova entrada, já que sai de Currículos);
//   • Remover → RPC atômico `remove_imported_source` (preserva profile_*: os
//     dados já incorporados ao perfil PERMANECEM; só o arquivo-fonte some).
//
// Auto-gating: só renderiza com a flag `trilha_assist_v1` ON E havendo uma
// fonte importada. Flag OFF ou sem import → SizedBox.shrink (nada muda).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/theme.dart';
import '../../../../data/models/models.dart'
    show SavedResume, SavedResumeSource;
import '../../../../services/feature_flags_service.dart';
import '../../../auth/user_viewmodel.dart';
import '../../../home/home_viewmodel.dart';
import '../../../resume/services/general_resume_export.dart';
import '../../application/profile_editor_view_model.dart';
import '../../profile_viewmodel.dart';
import '../../resume_detail_screen.dart';

/// Escolhe a fonte importada a exibir: a marcada como ATUAL
/// (`is_current_source`); na ausência dela, a mais recente `source=imported`.
/// Null quando o usuário não tem nenhum CV importado.
SavedResume? pickImportedSource(List<SavedResume> resumes) {
  final all = pickImportedSources(resumes);
  return all.isEmpty ? null : all.first;
}

/// TODAS as fontes importadas, com a ATUAL primeiro e o resto por recência.
///
/// Existe porque, com a flag ON, a F5.3 tira `imported` da lista de Currículos
/// e este card vira a ÚNICA porta para esses arquivos. Expor só a fonte atual
/// deixava os demais sem nenhuma tela que os alcançasse — nem para ver, nem
/// para remover — enquanto continuavam no banco e no Storage.
///
/// Medido em produção (27/07): 687 usuários têm CV importado; **41 têm mais de
/// um** (máximo 9), somando **54 arquivos** que ficariam órfãos na UI.
List<SavedResume> pickImportedSources(List<SavedResume> resumes) {
  // Ordena por (created_at DESC, id DESC) — mesmo desempate do banco
  // (migration 130000:202), determinístico mesmo com timestamps iguais.
  final imported = resumes
      .where((r) => r.source == SavedResumeSource.imported)
      .toList()
    ..sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
  if (imported.isEmpty) return const [];
  // A marcada como atual sobe para o topo; o resto mantém a ordem por recência.
  final currentIdx = imported.indexWhere((r) => r.isCurrentSource);
  if (currentIdx > 0) {
    final current = imported.removeAt(currentIdx);
    imported.insert(0, current);
  }
  return imported;
}

/// Texto do diálogo de remoção — honesto nos DOIS casos.
///
/// Com o perfil já populado, remover o arquivo realmente não perde nada: os
/// fatos vivem em `profile_*` e a RPC nunca os toca. Mas quando o perfil está
/// VAZIO (o import extraiu o texto e não populou o relacional), o arquivo/texto
/// é a ÚNICA representação daquele currículo — prometer "seus dados continuam
/// salvos" seria mentira, e a remoção de fato degrada o match. Nesse caso a
/// copy avisa em vez de tranquilizar.
String importedRemovalMessage({required bool profileHasContent}) =>
    profileHasContent
        ? 'Remover o arquivo importado NÃO apaga os dados que ele preencheu no '
            'seu perfil — eles continuam salvos. Só o arquivo-fonte é removido.'
        : 'Atenção: os dados deste currículo ainda não foram para o seu perfil. '
            'Removendo o arquivo, essas informações se perdem e seu match pode '
            'piorar.';

/// Rótulo honesto do status de EXTRAÇÃO do arquivo (não afirma o estado atual
/// do perfil — o import é fill-empty e o usuário pode ter editado depois). Null
/// (legado/indisponível) → sem afirmação, não inventa status.
String? importedStatusLabel(String? extractionStatus) {
  switch (extractionStatus) {
    case 'ready':
      return 'Arquivo lido';
    case 'failed':
      return 'Não consegui ler este arquivo';
    case 'pending':
    case 'extracting':
      return 'Processando…';
    default:
      return null;
  }
}

class ImportedSourceCard extends StatefulWidget {
  const ImportedSourceCard({super.key});

  @override
  State<ImportedSourceCard> createState() => _ImportedSourceCardState();
}

class _ImportedSourceCardState extends State<ImportedSourceCard> {
  bool _isRemoving = false;

  bool get _flagOn {
    final uid = context.read<UserViewModel>().user?.id ??
        Supabase.instance.client.auth.currentUser?.id;
    // 20/08/2026: era `isTrilhaAssistEnabledForUser`. Separado para que ligar
    // o Assistente não faça este card aparecer — o fundador decidiu que o CV
    // importado continua morando na aba Currículos.
    return FeatureFlagsService.instance.isImportedSourceHomeEnabledForUser(uid);
  }

  void _view(SavedResume source) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResumeDetailScreen(resume: source)),
    );
  }

  Future<void> _remove(SavedResume source) async {
    // Reusa a definição ÚNICA de "tem conteúdo profissional" do app: se o perfil
    // renderiza um currículo, os fatos estão em profile_* e remover o arquivo é
    // seguro; se não, o arquivo é a única cópia e a copy tem que AVISAR.
    final hasContent = GeneralResumeExport.profileHasContent(
      context.read<ProfileEditorViewModel>(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover este arquivo?'),
        content: Text(importedRemovalMessage(profileHasContent: hasContent)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRemoving = true);
    final vm = context.read<ProfileViewModel>();
    final ok = await vm.removeImportedSource(source);
    if (!mounted) return;
    setState(() => _isRemoving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não consegui remover o arquivo. Tente de novo.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Substituir/Importar: a REVISÃO do import ("CV diz X × você tem Y" +
  /// desfazer) vive no Assistente, o agente transversal de documentos. Aqui só
  /// pedimos a troca de aba + o cartão de import — sem duplicar o motor.
  void _startImport() {
    try {
      final home = context.read<HomeViewModel>();
      home.requestCvImport();
      home.requestTabChange(HomeTabs.resume);
    } catch (_) {
      // Sem HomeViewModel (teste isolado): no-op.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_flagOn) return const SizedBox.shrink();
    final vm = context.watch<ProfileViewModel>();
    final sources = pickImportedSources(vm.savedResumes);
    // Sem fonte: oferece IMPORTAR (não some). Evita o beco pós-remoção — antes
    // o card desaparecia e não havia caminho de volta dentro de Dados.
    if (sources.isEmpty) {
      return ImportedSourceCardView.empty(onImport: _startImport);
    }

    // Um card por arquivo. Com a flag ON este é o único lugar onde as fontes
    // importadas existem na UI, então mostrar só a atual deixaria as demais
    // inalcançáveis (41 usuários, 54 arquivos — medido em 27/07). O primeiro é
    // a fonte atual; os outros só oferecem Ver e Remover, porque "Substituir"
    // age sobre a fonte vigente, não sobre uma antiga.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sources.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          ImportedSourceCardView(
            name: (sources[i].originalFilename?.trim().isNotEmpty ?? false)
                ? sources[i].originalFilename!.trim()
                : sources[i].title,
            dateLabel: _fmtDate(sources[i].createdAt),
            statusLabel: importedStatusLabel(sources[i].extractionStatus),
            isRemoving: _isRemoving,
            onView: () => _view(sources[i]),
            onReplace: i == 0 ? _startImport : null,
            onRemove: () => _remove(sources[i]),
          ),
        ],
      ],
    );
  }

  static String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year}';
  }
}

/// Body puro do card — sem Provider, testável diretamente. Dois modos:
/// com fonte (nome/data/status + Ver/Substituir/Remover) e vazio
/// ([ImportedSourceCardView.empty] — só o convite a importar).
class ImportedSourceCardView extends StatelessWidget {
  const ImportedSourceCardView({
    super.key,
    required this.name,
    required this.dateLabel,
    this.statusLabel,
    this.isRemoving = false,
    this.onView,
    this.onReplace,
    this.onRemove,
  })  : isEmpty = false,
        onImport = null;

  /// Sem nenhum currículo importado: o card NÃO some — oferece importar. Evita
  /// o beco pós-remoção (antes não havia caminho de volta dentro de Dados).
  const ImportedSourceCardView.empty({super.key, this.onImport})
      : isEmpty = true,
        name = '',
        dateLabel = '',
        statusLabel = null,
        isRemoving = false,
        onView = null,
        onReplace = null,
        onRemove = null;

  final String name;
  final String dateLabel;
  final String? statusLabel;
  final bool isRemoving;
  final bool isEmpty;
  final VoidCallback? onView;
  final VoidCallback? onReplace;
  final VoidCallback? onRemove;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Container(
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.12),
                    borderRadius: AppRadius.brMd,
                  ),
                  child: const Icon(
                    Icons.cloud_upload_rounded,
                    size: 20,
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fonte importada',
                        style: AppTextStyles.labelSm,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isEmpty ? 'Nenhum currículo importado' : name,
                        style: AppTextStyles.titleSm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (isEmpty) ...[
              Text(
                'Importe um currículo em PDF para preencher seu perfil mais '
                'rápido. Você revisa o que vem dele antes de aplicar.',
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.base),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Importar currículo'),
                ),
              ),
            ] else ...[
              Text(
                'Importado em $dateLabel',
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textSecondary),
              ),
              if (statusLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  statusLabel!,
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
              const SizedBox(height: AppSpacing.base),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isRemoving ? null : onView,
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('Ver'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isRemoving ? null : onReplace,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Substituir'),
                    ),
                  ),
                ],
              ),
              // Destrutivo em hierarquia menor que Ver/Substituir.
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: isRemoving ? null : onRemove,
                  icon: isRemoving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remover'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
