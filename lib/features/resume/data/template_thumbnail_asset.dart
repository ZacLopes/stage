/// Caminho da miniatura de cada modelo de currículo.
///
/// Revisão UX 28/07, achado P2-29 (segunda metade). O card da aba Currículos
/// desenhava, para TODO currículo, um esqueleto cinza: uma barra escura em
/// cima e cinco barras claras embaixo. É exatamente o desenho que o resto do
/// mundo usa para "carregando" — e como era o mesmo em todos os cards, a
/// biblioteca inteira parecia uma lista travada em loading eterno.
///
/// As miniaturas reais já existiam em `assets/images/templates/`: são as
/// mesmas cinco que o seletor de modelos mostra. Faltava só o card usá-las.
///
/// Retorna null quando o currículo não tem `template_id` (CVs anteriores a
/// 26/05/2026 e PDFs importados) — aí a UI cai no desenho de folha, que
/// continua genérico mas não imita um carregamento.
String? templateThumbnailAsset(String? templateId) {
  if (templateId == null || templateId.isEmpty) return null;
  const conhecidos = {
    'harvard_ats',
    'jakes_resume',
    'forte_foundation',
    'one_page_compact',
    'cobalt_modern',
  };
  // Lista fechada de propósito: o asset é resolvido em runtime e um id
  // desconhecido viraria um caminho que não existe — a miniatura sumiria com
  // um erro de asset no lugar do defeito que ela veio consertar.
  if (!conhecidos.contains(templateId)) return null;
  return 'assets/images/templates/$templateId.png';
}
