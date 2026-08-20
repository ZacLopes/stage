// =============================================================================
// resume_row.dart — uma alternativa na biblioteca de currículos.
//
// A lista NÃO contém o currículo em uso: ele vive no herói acima. Aqui ficam
// "os outros arquivos". Quando o usuário promove um, a linha some daqui e sobe
// pro herói — a consequência da ação fica visível, sem precisar de explicação.
//
// Altura FIXA em 108 de propósito: os fatos assíncronos (páginas, tamanho)
// chegam depois do primeiro frame, e reservar o espaço desde o começo é o que
// impede a lista de pular enquanto carrega.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/models/models.dart';
import '../../services/resume_pdf_cache.dart';
import '../../utils/resume_meta.dart';

class ResumeRow extends StatefulWidget {
  const ResumeRow({
    super.key,
    required this.resume,
    required this.preview,
    required this.isDuplicate,
    required this.reduceMotion,
    required this.onOpen,
    required this.onUse,
    required this.onMenu,
  });

  final SavedResume resume;
  final ResumePreview preview;
  final bool isDuplicate;
  final bool reduceMotion;
  final VoidCallback onOpen;
  final VoidCallback onUse;
  final VoidCallback onMenu;

  @override
  State<ResumeRow> createState() => _ResumeRowState();
}

class _ResumeRowState extends State<ResumeRow> {
  bool _pressed = false;

  bool get _podeVirarAtivo => isEligibleAsActive(widget.resume);

  @override
  Widget build(BuildContext context) {
    final meta = buildMetaLine(
      source: widget.resume.source,
      createdAt: widget.resume.createdAt,
      pages: widget.preview.facts.pages,
      // Sem o tamanho: a linha tem 234pt de texto contra os 326pt do herói, e
      // "· 21 KB" era exatamente o que estourava e virava reticências.
    );

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: false,
      button: true,
      label: '${widget.resume.title}. $meta',
      child: AnimatedScale(
        scale: _pressed && !widget.reduceMotion ? 0.97 : 1.0,
        duration: Duration(milliseconds: widget.reduceMotion ? 1 : 110),
        curve: Curves.easeOut,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onOpen();
          },
          child: AppCard(
            padding: AppSpacing.allMd,
            child: SizedBox(
              height: 84,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _miniatura(),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _texto(meta)),
                  _botaoMenu(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniatura() {
    final facts = widget.preview.facts;
    Widget conteudo;

    if (facts.failed) {
      conteudo = const Icon(
        Icons.cloud_off_rounded,
        size: 20,
        color: AppColors.textTertiary,
      );
    } else if (facts.tooLargeToPreview) {
      conteudo = const Icon(
        Icons.picture_as_pdf_rounded,
        size: 20,
        color: AppColors.error,
      );
    } else if (widget.preview.png == null) {
      conteudo = const Icon(
        Icons.description_outlined,
        size: 20,
        color: AppColors.textDisabled,
      );
    } else {
      // MESMO PNG do herói, só reescalado. Um raster por arquivo.
      conteudo = Image.memory(
        widget.preview.png!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
        cacheWidth: 144,
      );
    }

    return Container(
      width: 48,
      height: 67,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.brSm,
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(child: conteudo),
    );
  }

  Widget _texto(String meta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.resume.title,
          style: AppTextStyles.titleSm,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          meta,
          style: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const Spacer(),
        _terceiraLinha(),
      ],
    );
  }

  /// Prioridade quando o espaço é curto: promover > aviso > duplicado.
  Widget _terceiraLinha() {
    if (!_podeVirarAtivo) {
      return Text(
        'Não vira o currículo em uso',
        style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Row(
      children: [
        _pillUsarEste(),
        if (widget.isDuplicate) ...[
          const SizedBox(width: AppSpacing.sm),
          const Flexible(
            child: SemanticBadge(
              label: 'Parece cópia',
              tone: SemanticTone.neutral,
            ),
          ),
        ],
      ],
    );
  }

  Widget _pillUsarEste() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onUse();
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: AppRadius.brPill,
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          'Usar este',
          style: AppTextStyles.labelMd.copyWith(color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _botaoMenu() {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: const Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: AppColors.textTertiary,
        ),
        tooltip: 'Mais ações',
        onPressed: widget.onMenu,
      ),
    );
  }
}
