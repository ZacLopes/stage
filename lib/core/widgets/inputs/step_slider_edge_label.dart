/// Rótulo das PONTAS de um slider de passos.
///
/// Revisão UX 28/07, achado P3-36: o slider de semestre mostrava
/// "1º semestre" na ponta esquerda E na bolha do valor atual ao abrir, porque
/// os dois usavam o mesmo `labelBuilder`. A tela lia
/// "1º semestre … 1º semestre … 12º semestre".
///
/// A ponta responde "até onde vai", a bolha responde "onde estou". Número cru
/// nas pontas resolve as duas: nunca duplica, e ainda cabe melhor no espaço
/// apertado das bordas.
///
/// Só a LÓGICA é compartilhada, não o widget. `_StepSliderBlock`
/// (education_screen) e `_StepSliderField` (add_edit_education_modal) têm
/// wrapper, fundo, raio e padding diferentes — unificar os widgets mudaria a
/// aparência de uma das telas, que é refactor oportunista (R6). O que precisa
/// ser igual é a regra, e ela mora aqui.
String stepSliderEdgeLabel(int value) => '$value';
