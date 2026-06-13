import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';

/// FASE 2 (T2.4): bandas do match score pré-swipe. O número 0-100 sai do
/// card e da célula (vira banda); o número completo só aparece no DETALHE
/// da vaga. Limiares do plano-mãe F2: Alta ≥70 · Média 40-69 · Baixa <40.
enum MatchBand { alta, media, baixa }

MatchBand matchBandFor(int score) {
  if (score >= 70) return MatchBand.alta;
  if (score >= 40) return MatchBand.media;
  return MatchBand.baixa;
}

extension MatchBandUi on MatchBand {
  String get label => switch (this) {
        MatchBand.alta => 'Alta',
        MatchBand.media => 'Média',
        MatchBand.baixa => 'Baixa',
      };

  /// Verde é reservado pra success no design system; banda usa a paleta
  /// da marca + neutros (alta = primary, média = âmbar, baixa = cinza).
  Color get color => switch (this) {
        MatchBand.alta => AppColors.primary,
        MatchBand.media => AppColors.warning,
        MatchBand.baixa => AppColors.textTertiary,
      };
}
