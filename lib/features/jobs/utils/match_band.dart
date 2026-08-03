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
  /// Rótulo do anel do card, que aparece EM CIMA da palavra "match".
  ///
  /// Masculino porque "match" é masculino em PT-BR: o anel lia "Alta match".
  /// Revisão UX 28/07, achado P2-13. O nome do enum segue feminino porque
  /// concorda com "banda", que é o conceito — não com o que vai na tela.
  String get label => switch (this) {
        MatchBand.alta => 'Alto',
        MatchBand.media => 'Médio',
        MatchBand.baixa => 'Baixo',
      };

  /// Verde é reservado pra success no design system; banda usa a paleta
  /// da marca + neutros (alta = primary, média = âmbar, baixa = cinza).
  Color get color => switch (this) {
        MatchBand.alta => AppColors.primary,
        MatchBand.media => AppColors.warning,
        MatchBand.baixa => AppColors.textTertiary,
      };
}

/// Rótulo e explicação do match no DETALHE da vaga.
///
/// Revisão UX 28/07, achado P2-13: a mesma vaga era descrita com dois
/// vocabulários sem parentesco. O card dizia "Alta"; o detalhe, para o mesmo
/// score de 75, dizia "Bom match". Nada na tela informava que "Alta" e "Bom"
/// eram a mesma coisa — pareciam duas medidas diferentes do mesmo número.
///
/// Agora o detalhe usa o adjetivo da banda, e o balde de 85+ (decisão da
/// Fase 2, que mantém a granularidade extra onde o número exato aparece)
/// vira um SUPERLATIVO da banda alta, não um rótulo paralelo:
///
///   card "Alto"  → detalhe "Match alto" ou "Match excelente"
///   card "Médio" → detalhe "Match médio"
///   card "Baixo" → detalhe "Match baixo"
///
/// Os limiares 70/40 são os mesmos de [matchBandFor], derivados dele, para
/// não existir uma segunda escada que possa divergir em silêncio.
({String label, String description}) matchDetailCopy(int score) {
  final band = matchBandFor(score);
  return switch (band) {
    MatchBand.alta when score >= 85 => (
        label: 'Match excelente',
        description: 'Seu perfil atende muito bem aos requisitos desta vaga.',
      ),
    MatchBand.alta => (
        label: 'Match alto',
        description: 'Você tem um bom alinhamento com o perfil buscado.',
      ),
    MatchBand.media => (
        label: 'Match médio',
        description: 'Algumas coisas batem; veja os pontos abaixo.',
      ),
    MatchBand.baixa => (
        label: 'Match baixo',
        description: 'Esta vaga foge bastante do seu perfil.',
      ),
  };
}
