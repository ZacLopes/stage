/// Utilitários compartilhados de normalização e matching para filtros de vagas.
///
/// Resolve 3 problemas que tornavam os filtros frustrantes:
/// 1. Acentos: "São Paulo" no picker vs "Sao Paulo" no banco — não batia.
/// 2. Sinônimos de área: o sync externo categoriza em "Recursos Humanos",
///    "Operações", "Produto" etc. mas o picker só oferecia 8 áreas — vagas
///    sumiam silenciosamente.
/// 3. Cidade × estado: usuário escolhe "São Paulo" e quer todas as vagas
///    do estado de SP, não só capital.
///
/// Toda comparação é case-insensitive e accent-insensitive.
library;

class FilterHelpers {
  /// Remove acentos e diacríticos comuns do PT-BR + lowercase + trim.
  /// "São Paulo " → "sao paulo".
  static String normalize(String input) {
    if (input.isEmpty) return input;
    final lower = input.toLowerCase().trim();
    const replacements = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    final buffer = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      buffer.write(replacements[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// Sinônimos de áreas. A chave é a área "canônica" (como armazenada no
  /// banco, vinda do `inferArea` do edge function de sync), os valores são
  /// labels que o usuário pode ter selecionado no picker.
  ///
  /// Bidirecional na prática: o matching faz lookup em ambas direções.
  static const Map<String, List<String>> _areaSynonyms = {
    'rh': ['rh', 'recursos humanos', 'gente', 'gente e gestao', 'people'],
    'recursos humanos': ['rh', 'recursos humanos', 'gente', 'gente e gestao', 'people'],
    'tecnologia': ['tecnologia', 'ti', 'tech', 'engenharia de software', 'desenvolvimento', 'software'],
    'engenharia': ['engenharia', 'engenharia de software', 'engineering'],
    'design': ['design', 'produto', 'ux', 'ui', 'product design', 'experiencia do usuario'],
    'produto': ['produto', 'design', 'product', 'ux', 'ui'],
    'marketing': ['marketing', 'growth', 'comunicacao', 'crm', 'brand'],
    'vendas': ['vendas', 'comercial', 'sales', 'business development'],
    'financas': ['financas', 'finance', 'controladoria', 'contabilidade'],
    'operacoes': ['operacoes', 'operations', 'logistica', 'supply chain', 'cs', 'customer success', 'atendimento', 'suporte'],
    'juridico': ['juridico', 'legal', 'compliance'],
    'administrativo': ['administrativo', 'admin'],
    'geral': ['geral', 'general'],
  };

  /// Compara área da vaga (job.area) com áreas selecionadas pelo user.
  ///
  /// **Estrito**: se o usuário selecionou áreas, só passam vagas com
  /// área definida que bate exatamente (após normalização) ou via sinônimos
  /// conhecidos (RH ↔ Recursos Humanos). Nada de substring nem permissivo
  /// no null — se a vaga não tem área e o usuário pediu uma, exclui.
  ///
  /// Sem substring porque o `inferArea` dos edge functions sempre devolve
  /// um valor canônico ("Tecnologia", "Engenharia", "Geral", …); substring
  /// só causaria falsos positivos.
  static bool isAreaMatch(String? jobArea, List<String> userAreas) {
    if (userAreas.isEmpty) return true;
    if (jobArea == null || jobArea.trim().isEmpty) return false;

    final jobNorm = normalize(jobArea);
    for (final userArea in userAreas) {
      final userNorm = normalize(userArea);
      if (userNorm.isEmpty) continue;

      // Match direto após normalização
      if (jobNorm == userNorm) return true;

      // Match por sinônimos (lookup nas duas direções)
      final synonymsFromJob = _areaSynonyms[jobNorm];
      if (synonymsFromJob != null && synonymsFromJob.contains(userNorm)) {
        return true;
      }
      final synonymsFromUser = _areaSynonyms[userNorm];
      if (synonymsFromUser != null && synonymsFromUser.contains(jobNorm)) {
        return true;
      }
    }
    return false;
  }

  /// Mapa cidade canônica → estado (UF). Usado para matching cidade↔estado:
  /// se o user escolhe "São Paulo" e a vaga é em "Campinas, SP", batemos
  /// porque ambas pertencem ao estado de SP.
  static const Map<String, String> _cityToState = {
    'sao paulo': 'sp',
    'campinas': 'sp',
    'santos': 'sp',
    'sao bernardo do campo': 'sp',
    'guarulhos': 'sp',
    'osasco': 'sp',
    'sao jose dos campos': 'sp',
    'ribeirao preto': 'sp',
    'sorocaba': 'sp',
    'rio de janeiro': 'rj',
    'niteroi': 'rj',
    'belo horizonte': 'mg',
    'uberlandia': 'mg',
    'contagem': 'mg',
    'curitiba': 'pr',
    'londrina': 'pr',
    'porto alegre': 'rs',
    'caxias do sul': 'rs',
    'brasilia': 'df',
    'salvador': 'ba',
    'recife': 'pe',
    'fortaleza': 'ce',
    'manaus': 'am',
    'florianopolis': 'sc',
    'joinville': 'sc',
    'goiania': 'go',
    'vitoria': 'es',
    'belem': 'pa',
  };

  /// Compara localização da vaga com locais selecionados pelo user.
  ///
  /// **Estrito** (no spirit do "filtro tem que filtrar"):
  /// - Se a vaga é remoto → passa (remoto serve qualquer cidade).
  /// - Se a vaga não tem cidade nem estado → exclui (não dá pra confiar).
  /// - Match exato/substring por cidade (cobre "Pinheiros, São Paulo").
  /// - Match por estado: se user escolheu uma cidade conhecida, vagas em
  ///   outras cidades do mesmo estado também batem.
  ///
  /// `workModelRaw` ajuda a tratar remoto sem precisar de cidade.
  static bool isLocationMatch({
    required List<String> userLocations,
    required String? jobCity,
    required String? jobState,
    required String? workModelRaw,
  }) {
    if (userLocations.isEmpty) return true;
    if (workModelRaw == 'remoto') return true;

    final cityRaw = jobCity?.trim() ?? '';
    final stateRaw = jobState?.trim() ?? '';
    if (cityRaw.isEmpty && stateRaw.isEmpty) return false;

    final cityNorm = normalize(cityRaw);
    final stateNorm = normalize(stateRaw);

    for (final userLoc in userLocations) {
      final userNorm = normalize(userLoc);
      if (userNorm.isEmpty) continue;

      // 1. Cidade bate por nome (substring nos dois sentidos pra cobrir
      //    "Pinheiros, São Paulo" vs "São Paulo").
      if (cityNorm.isNotEmpty &&
          (cityNorm.contains(userNorm) || userNorm.contains(cityNorm))) {
        return true;
      }

      // 2. User escolheu o nome do estado direto (ex: "São Paulo" como UF)
      //    e a vaga está em qualquer cidade desse estado.
      final userState = _cityToState[userNorm];
      if (userState != null && stateNorm == userState) return true;

      // 3. User escolheu uma cidade e a vaga está em outra cidade do mesmo estado.
      final cityState = _cityToState[cityNorm];
      if (cityState != null && cityState == userState) return true;

      // 4. Match direto contra UF (caso o user tenha digitado "SP" futuramente).
      if (userNorm == stateNorm) return true;
    }

    return false;
  }

  /// Compara work model com seleção do user. **Estrito**: se o user setou
  /// um modelo e a vaga não tem o campo, exclui.
  static bool isWorkModelMatch(String? jobWorkModel, List<String> userWorkModels) {
    if (userWorkModels.isEmpty) return true;
    if (jobWorkModel == null || jobWorkModel.isEmpty) return false;
    return userWorkModels.contains(jobWorkModel);
  }

  /// Compara job type com seleção do user. **Estrito**: se o user setou
  /// um tipo e a vaga não tem o campo, exclui.
  static bool isJobTypeMatch(String? jobType, List<String> userJobTypes) {
    if (userJobTypes.isEmpty) return true;
    if (jobType == null || jobType.isEmpty) return false;
    return userJobTypes.contains(jobType);
  }

  /// Compara salário mínimo. **Permissivo no null da vaga**: muitas vagas
  /// externas (Greenhouse, Lever) não publicam salário, e excluí-las
  /// silenciosamente quando o user seta um mínimo é o que mais zerava feed.
  /// Em vez disso, deixa passar e o usuário decide ao abrir o detalhe.
  static bool isSalaryMatch(int? jobSalaryMin, int? userMinSalary) {
    if (userMinSalary == null || userMinSalary <= 0) return true;
    if (jobSalaryMin == null) return true; // permissivo
    return jobSalaryMin >= userMinSalary;
  }
}
