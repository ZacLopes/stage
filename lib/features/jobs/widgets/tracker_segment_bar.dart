import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../models/application.dart';

/// Stops do gradiente que esmaece a borda direita da régua.
///
/// Vive fora do `shaderCallback`, como função pura, porque o esmaecimento é a
/// ÚNICA parte visível do C4 e lá dentro ele é inalcançável por teste: o
/// `ui.Shader` é opaco e o `ShaderMask` é incondicional de propósito (ver
/// [_TrackerSegmentBarState.build]), então nenhuma asserção de árvore
/// distingue "esmaece" de "não esmaece". MEDIDO em 27/07 por teste de mutação:
/// igualar os dois ramos — isto é, ressuscitar o C4 por inteiro — mantinha os
/// 8 testes do widget verdes.
///
/// Cobertura residual, declarada: o teste unitário garante os VALORES; que o
/// widget de fato os use está garantido só por haver um único call site.
List<double> fadeStops({required bool canScrollRight}) => canScrollRight
    // Últimos 12% da largura desvanecem: há pílula à direita fora da viewport.
    ? const [0.0, 0.88, 1.0]
    // O "fim" do gradiente cai fora do retângulo: 100% opaco, nada esmaecido.
    : const [0.0, 1.0, 1.0];

/// FASE 3 (T3.1 redesign): barra de segmentos da aba Candidaturas. Pílulas
/// roláveis com contagem; a selecionada anima cor/elevação. Substitui as 4
/// seções empilhadas por um filtro no topo (UX mais limpa + animada).
class TrackerSegmentBar extends StatefulWidget {
  final ApplicationSegment selected;
  final Map<ApplicationSegment, int> counts;
  final ValueChanged<ApplicationSegment> onSelected;

  const TrackerSegmentBar({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  @override
  State<TrackerSegmentBar> createState() => _TrackerSegmentBarState();
}

class _TrackerSegmentBarState extends State<TrackerSegmentBar> {
  final ScrollController _controller = ScrollController();

  /// True quando ainda há pílula à direita fora da viewport.
  ///
  /// C4 do device-test: em telas estreitas a última pílula aparecia cortada
  /// ("Finaliza…") sem nenhum indício de que a régua rola — lia-se como defeito
  /// de layout, não como conteúdo que continua. O esmaecimento só aparece
  /// quando existe algo à direita; onde as 4 pílulas cabem, a barra fica limpa.
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(TrackerSegmentBar old) {
    super.didUpdateWidget(old);
    // O segmento pode mudar SEM toque — a aba reposiciona sozinha depois de
    // uma ação (C1). Se a pílula do novo segmento estiver fora da viewport, o
    // filtro ativo fica invisível e a tela parece ter mudado sozinha sem
    // explicação. Traz a pílula para a vista.
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  /// Rola a régua até a pílula selecionada ficar visível.
  ///
  /// Usa a fração do índice sobre o extent total — não precisa medir cada
  /// pílula, e erra para o lado seguro (mostra a região certa). Não faz nada
  /// quando tudo já cabe na tela.
  void _revealSelected() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.maxScrollExtent <= 0) return;
    final segments = ApplicationSegment.values;
    final idx = segments.indexOf(widget.selected);
    if (idx < 0) return;
    final target =
        (pos.maxScrollExtent * (idx / (segments.length - 1))).clamp(
      0.0,
      pos.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    // Tolerância de 1px evita piscar no fim do scroll por arredondamento.
    final next = pos.pixels < pos.maxScrollExtent - 1;
    if (next != _canScrollRight) setState(() => _canScrollRight = next);
  }

  @override
  Widget build(BuildContext context) {
    // Re-mede quando as contagens mudam de largura (ex.: 9 → 10 itens).
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

    final list = ListView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      children: [
        for (final seg in ApplicationSegment.values) ...[
          _SegmentPill(
            label: seg.label,
            count: widget.counts[seg] ?? 0,
            isSelected: seg == widget.selected,
            onTap: () => widget.onSelected(seg),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );

    // O ShaderMask é SEMPRE aplicado; o que muda é o gradiente. Alternar entre
    // `ShaderMask(child: list)` e `list` trocaria o TIPO do widget no slot,
    // `Widget.canUpdate` falharia, o Element seria descartado e a ListView
    // re-inflada com uma ScrollPosition nova em pixels=0 — a régua pularia de
    // volta ao começo exatamente quando o usuário chegasse à borda direita.
    // Mantendo a árvore estável, só o shader muda.
    return SizedBox(
      height: 40,
      child: ShaderMask(
        // dstIn: o alpha do gradiente vira o alpha da lista — a borda direita
        // some suavemente, sinalizando que há mais conteúdo à direita.
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Colors.white, Colors.white, Colors.transparent],
          stops: fadeStops(canScrollRight: _canScrollRight),
        ).createShader(rect),
        child: list,
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentPill({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? Colors.white : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fg,
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
