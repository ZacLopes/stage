// =============================================================================
// active_resume_hero.dart — a ficha do "currículo em uso".
//
// É o herói da biblioteca e, pra 89% dos usuários (1.043 de 1.168 têm um único
// currículo), é a tela INTEIRA. Por isso ele não é um slide de carrossel: é uma
// ficha, com preview grande, metadado e o contrato honesto do que aquele
// arquivo faz.
//
// O preview é o raster real da página 1 em 326pt, cortado no topo com fade.
// Os ~43% superiores de um A4 contêm nome, contato, formação e o começo da
// experiência — exatamente a parte que identifica o documento. O corte é
// assumido, não acidente.
// =============================================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/models/models.dart';
import '../../services/resume_pdf_cache.dart';
import '../../utils/resume_meta.dart';

class ActiveResumeHero extends StatelessWidget {
  const ActiveResumeHero({
    super.key,
    required this.resume,
    required this.preview,
    required this.reduceMotion,
    required this.onOpen,
    required this.onExplain,
    required this.onRetry,
  });

  final SavedResume resume;
  final ResumePreview preview;
  final bool reduceMotion;
  final VoidCallback onOpen;
  final VoidCallback onExplain;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final meta = buildMetaLine(
      source: resume.source,
      createdAt: resume.createdAt,
      pages: preview.facts.pages,
      bytes: preview.facts.bytes,
    );

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: true,
      label: 'Currículo em uso: ${resume.title}. $meta',
      child: AppCard(
        variant: AppCardVariant.elevated,
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.md,
          AppSpacing.base,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cabecalho(),
            const SizedBox(height: AppSpacing.md),
            _preview(),
            const SizedBox(height: AppSpacing.md),
            Text(
              resume.title,
              style: AppTextStyles.titleMd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              meta,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (resume.isLatestLegacySource) ...[
              const SizedBox(height: AppSpacing.sm),
              const SemanticBadge(
                label: 'Alimentou seu perfil',
                tone: SemanticTone.info,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: AppSpacing.md),
            Text(
              'O Stage usa este arquivo quando você compartilha seu currículo, '
              'e é ele que aparece como "Original" ao lado da versão adaptada '
              'pra uma vaga.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            GhostButton(
              label: 'Entenda o que isso significa',
              onPressed: onExplain,
            ),
            const SizedBox(height: AppSpacing.md),
            SecondaryButton(
              label: 'Ver em tela cheia',
              icon: Icons.fullscreen_rounded,
              onPressed: onOpen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'CURRÍCULO EM USO',
            style: AppTextStyles.overline.copyWith(color: AppColors.primary),
          ),
        ),
        // O check é ESTADO, não botão — daí o IgnorePointer. Botão que não
        // faz nada quando tocado é pior que nenhum botão.
        const IgnorePointer(
          child: Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _preview() {
    return GestureDetector(
      onTap: preview.facts.failed ? onRetry : onOpen,
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: AppColors.primary, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _conteudoPreview(),
            // Fade branco no rodapé: o corte da página vira intenção.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 56,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (preview.png != null)
              Positioned(
                top: 10,
                right: 10,
                child: _botaoExpandir(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _conteudoPreview() {
    if (preview.facts.failed) {
      return _placeholder(
        icone: Icons.cloud_off_rounded,
        texto: 'Toque pra tentar de novo',
      );
    }
    if (preview.facts.tooLargeToPreview) {
      return _placeholder(
        icone: Icons.picture_as_pdf_rounded,
        texto: 'Grande demais pra pré-visualizar',
        cor: AppColors.error,
      );
    }
    if (preview.png == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.description_outlined,
            size: 28,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: AppSpacing.md),
          const SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.primary,
              backgroundColor: AppColors.border,
            ),
          ),
        ],
      );
    }

    return AnimatedOpacity(
      opacity: 1,
      duration: Duration(milliseconds: reduceMotion ? 1 : 200),
      child: Image.memory(
        preview.png!,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
        cacheWidth: kRasterWidthPx,
      ),
    );
  }

  Widget _placeholder({
    required IconData icone,
    required String texto,
    Color cor = AppColors.textTertiary,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icone, size: 28, color: cor),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(color: cor),
          ),
        ),
      ],
    );
  }

  Widget _botaoExpandir() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        shape: BoxShape.circle,
        boxShadow: AppShadows.sm,
      ),
      child: const Icon(
        Icons.open_in_full_rounded,
        size: 16,
        color: AppColors.textSecondary,
      ),
    );
  }
}
