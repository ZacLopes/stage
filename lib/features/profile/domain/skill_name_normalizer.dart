/// Faixa recomendada para um perfil legível e útil no match.
const int kRecommendedMinProfileSkills = 6;
const int kMaxProfileSkills = 12;

/// Remove espaços acidentais sem alterar a grafia escolhida pelo usuário.
String cleanSkillName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Chave de comparação de skills: sem diferença de caixa ou acentos.
///
/// Não resolve aliases semânticos (ex.: "Excel básico" → "Excel"). Essa
/// decisão depende da taxonomia e deve continuar explícita para o usuário.
String foldSkillName(String value) {
  return cleanSkillName(value)
      .toLowerCase()
      .replaceAll(RegExp('[áàâãä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôõö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll('ñ', 'n');
}

/// Aplica trim/colapso de espaços e remove duplicatas equivalentes mantendo a
/// primeira grafia e a ordem escolhidas pelo usuário. Nunca trunca a lista.
List<String> normalizeSkillNames(Iterable<String> names) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in names) {
    final name = cleanSkillName(raw);
    final key = foldSkillName(name);
    if (key.isEmpty || !seen.add(key)) continue;
    result.add(name);
  }
  return result;
}
