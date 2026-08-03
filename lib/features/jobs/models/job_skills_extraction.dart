/// Resultado da Edge Function `extract-job-skills`.
///
/// Lista de skills atômicas extraídas dos requisitos+descrição de uma vaga,
/// cruzadas contra o CV do user (in_cv) e contra a lista global de
/// confirmed_skills (pre_confirmed).
class JobSkillsExtraction {
  final List<JobSkill> skills;
  final int total;
  final int inCvCount;

  const JobSkillsExtraction({
    required this.skills,
    required this.total,
    required this.inCvCount,
  });

  /// Skills que JÁ estão no CV do user. Renderizadas como lock + verde.
  List<JobSkill> get inCvSkills => skills.where((s) => s.inCv).toList();

  /// Skills que a vaga pede mas NÃO estão no CV. Renderizadas como chips
  /// selecionáveis (o user marca o que tem mas esqueceu de mencionar).
  List<JobSkill> get missingSkills => skills.where((s) => !s.inCv).toList();

  /// Skills missing que já vinham confirmadas em outras vagas (default
  /// pré-selecionada no sheet, mas user pode desmarcar).
  List<JobSkill> get preConfirmedMissing =>
      skills.where((s) => !s.inCv && s.preConfirmed).toList();

  /// True quando não vale mostrar o sheet (sem skills extraídas ou todas
  /// já no CV) — caller pula direto pra adaptação.
  bool get shouldSkip => skills.isEmpty || missingSkills.isEmpty;

  factory JobSkillsExtraction.fromJson(Map<String, dynamic> json) {
    final raw = (json['skills'] as List?) ?? const [];
    final skills = raw
        .map((e) => JobSkill.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return JobSkillsExtraction(
      skills: skills,
      total: (json['total'] as num?)?.toInt() ?? skills.length,
      inCvCount: (json['in_cv_count'] as num?)?.toInt() ??
          skills.where((s) => s.inCv).length,
    );
  }

  /// Reclassifica como "já tenho" as skills que batem com [ownedNames].
  ///
  /// `in_cv` chega do servidor cruzando só as fontes LEGADAS; o que está em
  /// `profile_skills` não conta. Sem isto, a folha reoferecia à pessoa
  /// exatamente as habilidades que ela tinha acabado de cadastrar.
  /// Revisão UX 28/07, achado P2-19 (D2).
  ///
  /// Comparação normalizada (minúsculas, sem acento e sem pontuação) pra
  /// "Power BI", "power bi" e "Power-BI" contarem como a mesma coisa.
  JobSkillsExtraction markingAsInCv(Iterable<String> ownedNames) {
    final owned = ownedNames.map(_normalizeForMatch).where((s) => s.isNotEmpty).toSet();
    if (owned.isEmpty) return this;
    final updated = skills
        .map((s) => s.inCv || !owned.contains(_normalizeForMatch(s.name))
            ? s
            : s.asInCv())
        .toList();
    return JobSkillsExtraction(
      skills: updated,
      total: total,
      inCvCount: updated.where((s) => s.inCv).length,
    );
  }

  /// Chave de IDENTIDADE — espelho exato do `identityKey` de
  /// `supabase/functions/extract-job-skills/index.ts`.
  ///
  /// Preserva `+` e `#` de propósito. Descartá-los faz `C`, `C++` e `C#`
  /// colapsarem todos na string `"c"` — e as três são habilidades DISTINTAS no
  /// catálogo. O efeito é silencioso e caro: [markingAsInCv] só faz upgrade
  /// (`inCv: false → true`), nunca o contrário, então quem declarou C# veria
  /// C++ marcado como "você já tem", o item sairia lockado verde da folha de
  /// confirmação e nunca entraria no `extra_skills` que segue pro
  /// `adapt-resume-to-job`. A pessoa perde a chance de reivindicar a skill e
  /// não recebe erro nenhum.
  ///
  /// O servidor consertou essa classe em 01/08/2026 (commit e21b055, achado no
  /// device-test); este lado tinha ficado com o flatten antigo e reintroduzia o
  /// falso positivo mesmo com a function nova deployada, porque roda DEPOIS da
  /// resposta do servidor. Medido em produção: 19 pessoas com skill da família
  /// C, contra 8 de 487 vagas ativas mencionando C++/C#/.NET.
  ///
  /// O `.` continua sendo descartado — "Node.js" e "nodejs" SÃO a mesma coisa,
  /// e nenhum par do catálogo se distingue só pelo ponto.
  ///
  /// ⚠️ Ao mexer aqui, mexa no `identityKey` do servidor junto: divergência
  /// entre os dois lados volta a produzir exatamente este bug.
  static String _normalizeForMatch(String raw) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    var s = raw.trim().toLowerCase();
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s.replaceAll(RegExp(r'[^a-z0-9+#]'), '');
  }

  /// Resultado vazio (usado em fallbacks silenciosos quando a extração falha).
  static const JobSkillsExtraction empty =
      JobSkillsExtraction(skills: [], total: 0, inCvCount: 0);
}

class JobSkill {
  /// Nome da skill (ex: "Power BI", "Inglês intermediário").
  final String name;

  /// `true` quando a skill já aparece no CV do user (parsed.skills ou
  /// raw_text). Renderizado como item lockado verde.
  final bool inCv;

  /// `true` quando o user já confirmou essa skill em uma vaga anterior
  /// (vem de `gamification_data.confirmed_skills`). Apenas faz sentido
  /// quando `inCv == false` — default pré-selecionada no sheet.
  final bool preConfirmed;

  /// Origem da extração: 'requirements' (lista de requisitos da vaga) ou
  /// 'description' (mencionada na descrição livre). Não é mostrado na UI
  /// hoje, mas é útil pra debug/analytics.
  final String source;

  /// Cópia marcada como já presente no perfil. Ver
  /// [JobSkillsExtraction.markingAsInCv].
  JobSkill asInCv() => JobSkill(
        name: name,
        inCv: true,
        preConfirmed: preConfirmed,
        source: source,
      );

  const JobSkill({
    required this.name,
    required this.inCv,
    required this.preConfirmed,
    required this.source,
  });

  factory JobSkill.fromJson(Map<String, dynamic> json) {
    return JobSkill(
      name: json['name']?.toString() ?? '',
      inCv: json['in_cv'] == true,
      preConfirmed: json['pre_confirmed'] == true,
      source: json['source']?.toString() ?? 'requirements',
    );
  }
}
