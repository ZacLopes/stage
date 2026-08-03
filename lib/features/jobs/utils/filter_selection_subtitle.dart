/// Subtítulo de contagem das seções da folha de filtros.
///
/// Revisão UX 28/07, achado P3-39 (segunda metade): a MESMA folha misturava
/// três formatos, um por seção —
///
///   Áreas         "2/5 selecionadas"
///   Localização   "1/5 • Remoto sempre passa"
///   Modelo/Tipo   "3 selecionado(s)"  ou  "Todos os modelos"
///
/// — para responder sempre a mesma pergunta: quantos eu escolhi, de quantos
/// posso. Três formatos lado a lado fazem o leitor conferir cada um em vez de
/// bater o olho, e o "N selecionado(s)" ainda deixava de dizer qual era o
/// limite justamente onde ele existe.
///
/// Regra única: "N de M" quando há escolha feita, e a frase de estado vazio
/// quando não há — porque zero filtros selecionados não é "0 de 5", é "não
/// estou filtrando nada", que é uma informação diferente e mais útil.
///
/// [emptyLabel] fica com a chamadora porque só ela sabe o gênero e o
/// substantivo ("Todas as áreas", "Todos os modelos").
String filterSelectionSubtitle({
  required int selected,
  required int max,
  required String emptyLabel,
}) {
  if (selected <= 0) return emptyLabel;
  return '$selected de $max';
}
