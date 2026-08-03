/// Prefixo constante gravado no título dos CVs adaptados por vaga.
const String kAdaptedResumeTitlePrefix = 'CV adaptado - ';

/// Título do CV para EXIBIÇÃO na biblioteca.
///
/// Os CVs adaptados são salvos como "CV adaptado - <vaga> - <empresa>". Num
/// card estreito com `maxLines: 1`, os 14 caracteres constantes do prefixo
/// comiam o espaço e todos apareciam como "CV adaptado - Est…" — e a feature
/// existe justamente pra gerar UM CV POR VAGA, então a biblioteca ficava com
/// vários itens visualmente idênticos, impossíveis de distinguir.
/// Revisão UX 28/07, achado P2-29 (D3 no backlog).
///
/// A informação não se perde: o selo "Adaptado (IA)" no card já diz o que é.
/// Aplicado na exibição (e não na gravação) pra valer também pros CVs que já
/// estão salvos.
String displayResumeTitle(String stored) {
  final t = stored.trim();
  if (!t.toLowerCase().startsWith(kAdaptedResumeTitlePrefix.toLowerCase())) {
    return t;
  }
  final stripped = t.substring(kAdaptedResumeTitlePrefix.length).trim();
  // Se sobrar nada, o prefixo ERA o título — devolve o original.
  return stripped.isEmpty ? t : stripped;
}
