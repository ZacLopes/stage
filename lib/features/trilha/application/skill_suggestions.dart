// Sugestões de skills por área (PLANO-FASE-6 — degrau 1 do "meio-termo").
//
// Personaliza os chips INICIAIS do passo de skills pela(s) área(s) que a pessoa
// escolheu — reconhecimento rápido ("ah, eu uso isso") em vez de uma lista
// genérica. Não precisa ser exaustivo: o typeahead sobre o skills_catalog (165
// canônicas) + o "adicionar livre" cobrem a cauda longa. Os nomes aqui são
// pensados pra casar com a taxonomia (skill_aliases canoniza no backend).

const Map<String, List<String>> _byArea = {
  'Tecnologia': [
    'Python', 'SQL', 'Java', 'JavaScript', 'Git', 'HTML', 'CSS',
    'Lógica de programação',
  ],
  'Engenharia': [
    'AutoCAD', 'SolidWorks', 'Excel', 'MATLAB', 'Power BI',
    'Gestão de projetos', 'Pacote Office', 'Lean',
  ],
  'Design': [
    'Figma', 'Photoshop', 'Illustrator', 'Canva', 'UX/UI',
    'Prototipagem', 'InDesign', 'Adobe XD',
  ],
  'Produto': [
    'Gestão de produtos', 'Figma', 'SQL', 'Análise de dados', 'Scrum',
    'Jira', 'Métricas', 'Excel',
  ],
  'Marketing': [
    'Marketing digital', 'Redes sociais', 'Canva', 'Google Analytics', 'SEO',
    'Copywriting', 'Tráfego pago', 'E-mail marketing',
  ],
  'Vendas': [
    'Vendas', 'CRM', 'Negociação', 'Prospecção', 'Atendimento ao cliente',
    'Salesforce', 'Excel', 'Comunicação',
  ],
  'Finanças': [
    'Excel', 'Power BI', 'Análise financeira', 'Contabilidade', 'SQL',
    'Modelagem financeira', 'Controladoria', 'Pacote Office',
  ],
  'Recursos Humanos': [
    'Recrutamento e seleção', 'Excel', 'Departamento pessoal', 'Comunicação',
    'Gestão de pessoas', 'Treinamento', 'Pacote Office', 'LGPD',
  ],
  'Operações': [
    'Excel', 'Power BI', 'Gestão de projetos', 'Logística', 'Lean',
    'Processos', 'SAP', 'Pacote Office',
  ],
  'Jurídico': [
    'Direito', 'Redação jurídica', 'Pesquisa jurídica', 'Contratos', 'LGPD',
    'Compliance', 'Pacote Office', 'Comunicação',
  ],
  'Administrativo': [
    'Pacote Office', 'Excel', 'Organização', 'Atendimento ao cliente',
    'Rotinas administrativas', 'Comunicação', 'ERP', 'Gestão de agenda',
  ],
  'Saúde': [
    'Atendimento ao paciente', 'Excel', 'Pacote Office', 'Comunicação',
    'Gestão em saúde', 'Prontuário eletrônico', 'Biossegurança',
    'Trabalho em equipe',
  ],
};

/// Lista genérica boa pra quem está "ainda explorando" ou cuja área não tem
/// mapa dedicado.
const List<String> _general = [
  'Excel', 'Pacote Office', 'Power BI', 'Python', 'Canva', 'Marketing digital',
  'Redes sociais', 'Vendas', 'Comunicação', 'Trabalho em equipe',
  'Atendimento ao cliente', 'Gestão de projetos',
];

/// Sugestões de skills pra apresentar como chips, dadas as [areas] do usuário.
/// Une as áreas que casam (dedup, ordem por relevância), com fallback genérico.
List<String> suggestedSkillsForAreas(List<String> areas) {
  final out = <String>[];
  final seen = <String>{};
  void add(String s) {
    if (seen.add(s.toLowerCase())) out.add(s);
  }

  for (final area in areas) {
    final list = _byArea[area.trim()];
    if (list != null) list.forEach(add);
  }
  if (out.isEmpty) _general.forEach(add);
  return out.take(14).toList(growable: false);
}
