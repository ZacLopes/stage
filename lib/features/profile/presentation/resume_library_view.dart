// =============================================================================
// resume_library_view.dart — a biblioteca de currículos (Perfil → Currículos).
//
// Estrutura: herói (o currículo em uso) + lista das alternativas. NÃO é
// carrossel — 1.043 de 1.168 usuários (89%) têm um único currículo, e um
// carrossel de um slide é chrome puro. Pra quem tem vários, o que discrimina é
// metadado, não pixel: 54% dos multi-currículo têm duplicatas acidentais e 687
// linhas se chamam "Meu Currículo".
//
// ⚠️ O `await` do import mora NESTE State, fora de qualquer Selector/Consumer.
// Não é estilo — é o que faz o import funcionar. `saveResume` chama
// `loadSavedResumes()`, que faz `notifyListeners()` ANTES do await de rede. Se
// o dono do fluxo estiver dentro de um Consumer que troca a subárvore por
// spinner, ele sofre dispose no meio do próprio fluxo, `context.mounted` vira
// false em `cv_import_service.dart` e o `imported_resume.raw_text` — o campo
// que o analyze-match lê — nunca é gravado. O arquivo aparece na lista, o
// perfil fica intacto, e o match segue pontuando o currículo velho. Sintoma
// invisível. Por isso: Selector, e loading como OVERLAY, nunca substituição.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import '../../../data/supabase_repository.dart';
import '../resume_preview_screen.dart';
import '../services/resume_pdf_cache.dart';
import '../utils/resume_meta.dart';
import 'widgets/active_resume_hero.dart';
import 'widgets/resume_row.dart';

class ResumeLibraryView extends StatefulWidget {
  const ResumeLibraryView({
    super.key,
    required this.resumes,
    required this.isLoading,
    this.importEntry,
  });

  /// Já filtrada por `filterLibraryResumes` pelo chamador.
  final List<SavedResume> resumes;
  final bool isLoading;

  /// A porta de importar, montada pelo chamador (que é quem conhece as flags).
  final Widget? importEntry;

  @override
  State<ResumeLibraryView> createState() => _ResumeLibraryViewState();
}

class _ResumeLibraryViewState extends State<ResumeLibraryView> {
  late final ResumePdfCache _cache;

  @override
  void initState() {
    super.initState();
    final repo = SupabaseRepository();
    _cache = ResumePdfCache(loader: repo.downloadResume);
  }

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  void _abrirTelaCheia(List<SavedResume> ordem, SavedResume alvo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResumePreviewScreen(
          resumes: ordem,
          initialIndex: ordem.indexWhere((r) => r.id == alvo.id).clamp(
                0,
                ordem.length - 1,
              ),
        ),
      ),
    );
  }

  void _explicarEmUso() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _InUseExplainerSheet(),
    );
  }

  /// Fatia 3 monta a RPC `set_active_resume` aqui. Hoje o em-uso é DERIVADO
  /// (`resolveActiveResume`), então a promoção ainda não persiste — e a tela
  /// diz isso em vez de fingir que salvou.
  void _usarEste(SavedResume resume) {
    HapticFeedback.mediumImpact();
    AppSnackBar.info(
      context,
      'Escolher o currículo em uso chega na próxima fatia — o banco ainda '
      'não guarda essa escolha.',
    );
  }

  void _abrirMenu(SavedResume resume) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ResumeActionsSheet(
        resume: resume,
        onOpen: () {
          Navigator.of(context).pop();
          _abrirTelaCheia(_ordemDeLeitura(), resume);
        },
      ),
    );
  }

  /// Ordem de folheio na tela cheia: o em-uso primeiro, depois a lista.
  List<SavedResume> _ordemDeLeitura() {
    final ativo = resolveActiveResume(widget.resumes);
    if (ativo == null) return widget.resumes;
    return [
      ativo,
      ...widget.resumes.where((r) => r.id != ativo.id),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final todos = widget.resumes;

    if (widget.isLoading && todos.isEmpty) {
      return const _CarregandoBiblioteca();
    }

    if (todos.isEmpty) {
      return _vazio();
    }

    final ativo = resolveActiveResume(todos);
    final outros = todos.where((r) => r.id != ativo?.id).toList()
      ..sort(compareByRecency);
    final ordem = _ordemDeLeitura();

    return CustomScrollView(
      slivers: [
        if (widget.importEntry != null)
          SliverToBoxAdapter(child: widget.importEntry!),

        if (ativo != null)
          SliverToBoxAdapter(
            child: ValueListenableBuilder<ResumePreview>(
              valueListenable: _cache.watch(ativo),
              builder: (_, preview, __) => ActiveResumeHero(
                key: ValueKey('hero_${ativo.id}'),
                resume: ativo,
                preview: preview,
                reduceMotion: reduceMotion,
                onOpen: () => _abrirTelaCheia(ordem, ativo),
                onExplain: _explicarEmUso,
                onRetry: () => _cache.retry(ativo),
              ),
            ),
          ),

        if (outros.isEmpty)
          const SliverToBoxAdapter(child: _RodapeUmCurriculo())
        else ...[
          SliverToBoxAdapter(child: _cabecalhoLista(outros.length)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            sliver: SliverList.separated(
              itemCount: outros.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                final r = outros[i];
                return ValueListenableBuilder<ResumePreview>(
                  valueListenable: _cache.watch(r),
                  builder: (_, preview, __) => ResumeRow(
                    key: ValueKey(r.id),
                    resume: r,
                    preview: preview,
                    isDuplicate: false,
                    reduceMotion: reduceMotion,
                    onOpen: () => _abrirTelaCheia(ordem, r),
                    onUse: () => _usarEste(r),
                    onMenu: () => _abrirMenu(r),
                  ),
                );
              },
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl2)),
      ],
    );
  }

  Widget _cabecalhoLista(int quantos) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.lg,
        AppSpacing.base,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Text('Outros arquivos ($quantos)', style: AppTextStyles.titleMd),
        ],
      ),
    );
  }

  Widget _vazio() {
    return Column(
      children: [
        if (widget.importEntry != null) widget.importEntry!,
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: EmptyState(
                tone: SemanticEmptyTone.brand,
                icon: Icons.description_outlined,
                title: 'Nenhum currículo por aqui',
                message: 'Importe o PDF que você já tem. Ele fica guardado '
                    'aqui e é o que você compartilha com as empresas.',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================

class _CarregandoBiblioteca extends StatelessWidget {
  const _CarregandoBiblioteca();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: AppSpacing.base),
          Text(
            'Carregando seus currículos…',
            style: AppTextStyles.bodySm,
          ),
        ],
      ),
    );
  }
}

class _RodapeUmCurriculo extends StatelessWidget {
  const _RodapeUmCurriculo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.lg,
        AppSpacing.base,
        0,
      ),
      child: Text(
        'Quando você adicionar outra versão, ela aparece aqui embaixo e você '
        'escolhe qual fica em uso.',
        style: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

/// O sheet que desarma a confusão central: o CV adaptado por vaga é escrito a
/// partir do PERFIL, não deste arquivo. Dizer isso na cara evita a decepção de
/// trocar o arquivo e ver o adaptado igual.
class _InUseExplainerSheet extends StatelessWidget {
  const _InUseExplainerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('O que significa "em uso"', style: AppTextStyles.titleLg),
            const SizedBox(height: AppSpacing.base),
            const _Bullet(
              icone: Icons.ios_share_rounded,
              texto: 'É o PDF que sai quando você compartilha seu currículo.',
            ),
            const SizedBox(height: AppSpacing.md),
            const _Bullet(
              icone: Icons.compare_arrows_rounded,
              texto: 'É o "Original" que aparece do lado quando a IA adapta '
                  'seu currículo pra uma vaga.',
            ),
            const SizedBox(height: AppSpacing.md),
            const _Bullet(
              icone: Icons.hourglass_empty_rounded,
              texto: 'Quando a candidatura automática chegar, é este arquivo '
                  'que vai anexado.',
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Uma coisa importante: o currículo que a IA adapta pra cada vaga '
              'é escrito a partir dos seus dados no perfil, não deste arquivo. '
              'Trocar o currículo em uso não muda o conteúdo do adaptado.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icone, required this.texto});
  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 18, color: AppColors.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            texto,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Fatia 5 enche este sheet (renomear, compartilhar, excluir). Hoje ele já
/// existe pra o `⋮` não ser um botão morto.
class _ResumeActionsSheet extends StatelessWidget {
  const _ResumeActionsSheet({required this.resume, required this.onOpen});

  final SavedResume resume;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              resume.title,
              style: AppTextStyles.titleLg,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ListTile(
            leading: const Icon(
              Icons.fullscreen_rounded,
              color: AppColors.textSecondary,
            ),
            title: Text('Ver em tela cheia', style: AppTextStyles.bodyMd),
            onTap: onOpen,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
