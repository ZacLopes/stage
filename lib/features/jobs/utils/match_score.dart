import '../models/job.dart';
import '../models/user_preferences.dart';

/// Resultado de um cálculo de match: score 0-100 + razões explicáveis.
class MatchResult {
  final int score;
  final List<MatchReason> reasons;
  const MatchResult({required this.score, required this.reasons});
}

class MatchReason {
  /// Label curto da dimensão avaliada (ex: "Área", "Cidade").
  final String label;

  /// True se a vaga atende esse critério da preferência.
  final bool matched;

  /// Peso máximo da dimensão (quanto contribuiu pro score se matched=true).
  final int weight;

  /// Detalhe humano-legível ("Marketing", "São Paulo, SP").
  final String? detail;

  const MatchReason({
    required this.label,
    required this.matched,
    required this.weight,
    this.detail,
  });
}

/// Calcula score de match (0-100) entre uma vaga e o perfil do usuário.
///
/// Pesos:
/// - Área:           30 pontos
/// - Tipo de vaga:   20 pontos
/// - Cidade:         15 pontos (remoto sempre passa)
/// - Modelo:         15 pontos
/// - Salário:        10 pontos
/// - Skills (texto): 10 pontos (proporcional)
///
/// Sem preferências configuradas → fallback de 75 com nota explicativa
/// (não quero mostrar 50% pra todo mundo zerado).
class MatchScoreCalculator {
  static MatchResult calculate({
    required Job job,
    UserJobPreferences? prefs,
    Map<String, dynamic>? gamificationData,
  }) {
    if (prefs == null || prefs.isEmpty) {
      return const MatchResult(
        score: 75,
        reasons: [
          MatchReason(
            label: 'Sem preferências',
            matched: false,
            weight: 0,
            detail: 'Configure suas preferências em Vagas > filtros pra match preciso.',
          ),
        ],
      );
    }

    final reasons = <MatchReason>[];
    int score = 0;
    int totalWeight = 0;

    // ── 1. Área (30) ────────────────────────────────────────────────
    if (prefs.areas.isNotEmpty) {
      final matched = job.area != null && prefs.areas.contains(job.area);
      const weight = 30;
      totalWeight += weight;
      if (matched) score += weight;
      reasons.add(MatchReason(
        label: 'Área de interesse',
        matched: matched,
        weight: weight,
        detail: job.area,
      ));
    }

    // ── 2. Tipo de vaga (20) ────────────────────────────────────────
    if (prefs.jobTypes.isNotEmpty) {
      final matched = job.jobTypeRaw != null && prefs.jobTypes.contains(job.jobTypeRaw);
      const weight = 20;
      totalWeight += weight;
      if (matched) score += weight;
      reasons.add(MatchReason(
        label: 'Tipo de vaga',
        matched: matched,
        weight: weight,
        detail: job.jobType,
      ));
    }

    // ── 3. Cidade (15) ──────────────────────────────────────────────
    if (prefs.locations.isNotEmpty) {
      bool matched = false;
      String? detail;
      if (job.workModelRaw == 'remoto') {
        matched = true;
        detail = 'Remoto';
      } else if (job.locationCity != null) {
        final cityLower = job.locationCity!.toLowerCase();
        matched = prefs.locations.any((loc) => cityLower.contains(loc.toLowerCase()));
        detail = job.locationCity;
      }
      const weight = 15;
      totalWeight += weight;
      if (matched) score += weight;
      reasons.add(MatchReason(
        label: 'Localização',
        matched: matched,
        weight: weight,
        detail: detail,
      ));
    }

    // ── 4. Modelo de trabalho (15) ──────────────────────────────────
    if (prefs.workModels.isNotEmpty) {
      final matched = job.workModelRaw != null && prefs.workModels.contains(job.workModelRaw);
      const weight = 15;
      totalWeight += weight;
      if (matched) score += weight;
      reasons.add(MatchReason(
        label: 'Modelo',
        matched: matched,
        weight: weight,
        detail: job.workModel,
      ));
    }

    // ── 5. Salário (10) — só conta se o user configurou explicitamente ──
    if (prefs.minSalary != null && prefs.minSalary! > 0) {
      final matched = job.salaryMin != null && job.salaryMin! >= prefs.minSalary!;
      const weight = 10;
      totalWeight += weight;
      if (matched) score += weight;
      reasons.add(MatchReason(
        label: 'Salário',
        matched: matched,
        weight: weight,
        detail: job.salaryRange,
      ));
    }

    // ── 6. Skills/CV × requisitos da vaga (10, proporcional) ──────
    // Aceita 2 fontes pra perfil do user: skills estruturadas (vindo
    // da trilha) OU texto bruto do CV importado. Comparamos contra
    // requirements + description da vaga.
    final userPool = _extractUserPool(gamificationData);
    if (userPool.isNotEmpty) {
      const weight = 10;
      totalWeight += weight;
      final overlap = _computeOverlap(userPool, job);
      final partial = (overlap * weight).round().clamp(0, weight);
      score += partial;
      reasons.add(MatchReason(
        label: 'Compatibilidade de perfil',
        matched: partial > weight ~/ 2,
        weight: weight,
        detail: '${(overlap * 100).round()}% dos requisitos batem com seu perfil',
      ));
    }

    // Normaliza pra escala 0-100 (quando o user só configurou parte das prefs,
    // totalWeight pode ser <100). Garante mínimo de 30 pra não ser absurdamente
    // baixo num matching baseline.
    final normalized = totalWeight > 0
        ? (score / totalWeight * 100).round()
        : 75;
    final clamped = normalized.clamp(30, 100);

    return MatchResult(score: clamped, reasons: reasons);
  }

  // ── Helpers ─────────────────────────────────────────────────────

  /// Stop-words PT-BR + EN comuns que não agregam ao match. Filtradas dos
  /// requisitos antes de procurar no perfil do user.
  static const _stopWords = <String>{
    // PT-BR
    'a', 'o', 'e', 'de', 'do', 'da', 'dos', 'das', 'em', 'no', 'na', 'nos',
    'nas', 'um', 'uma', 'uns', 'umas', 'para', 'por', 'com', 'sem', 'sob',
    'como', 'que', 'qual', 'quais', 'se', 'ao', 'aos', 'à', 'às', 'ou',
    'mas', 'pela', 'pelo', 'pelas', 'pelos', 'ser', 'ter', 'estar',
    'são', 'foi', 'será', 'mais', 'menos', 'muito', 'pouco',
    'também', 'já', 'ainda', 'sempre', 'nunca', 'aqui', 'ali', 'lá',
    'sobre', 'após', 'antes', 'durante', 'entre', 'até', 'desde',
    // EN (palavras que não conflitam com PT já listadas acima)
    'the', 'and', 'or', 'of', 'to', 'in', 'for', 'on', 'at', 'by', 'with',
    'as', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has',
    'had', 'does', 'did', 'will', 'would', 'should', 'could',
    // Genéricos de descrição de vaga
    'vaga', 'vagas', 'cargo', 'área', 'time', 'equipe', 'empresa', 'pessoa',
    'pessoas', 'experiência', 'experiencia', 'experiências', 'experiencias',
    'conhecimento', 'conhecimentos', 'desejável', 'desejaveis', 'requisitos',
    'requisito', 'atividade', 'atividades', 'responsabilidade',
    'responsabilidades', 'qualificação', 'qualificações', 'cursando',
    'graduação', 'graduado', 'formação', 'curso', 'cursos',
  };

  /// Extrai um "pool" de palavras-chave que representam o perfil do user.
  /// Une skills estruturadas (gamificationData.whoIAm.derived.skills) com
  /// texto bruto do CV importado (gamificationData.imported_resume.raw_text).
  /// Retorna lower-case, sem duplicados.
  static Set<String> _extractUserPool(Map<String, dynamic>? data) {
    if (data == null) return const {};
    final pool = <String>{};

    void addText(String? s) {
      if (s == null || s.isEmpty) return;
      // Tokeniza por whitespace e pontuação, filtra stop-words, mantém ≥3 chars
      for (final raw in s.split(RegExp(r'[\s,.;:!?()\[\]{}<>"/\\\-•|]+'))) {
        final w = raw.trim().toLowerCase().replaceAll(RegExp(r'[^\wá-ú]'), '');
        if (w.length < 3) continue;
        if (_stopWords.contains(w)) continue;
        // Filtra puramente numéricos
        if (RegExp(r'^\d+$').hasMatch(w)) continue;
        pool.add(w);
      }
    }

    // 1. Skills estruturadas (vindo da trilha)
    final whoIAm = data['whoIAm'];
    if (whoIAm is Map && whoIAm['derived'] is Map) {
      addText((whoIAm['derived'] as Map)['skills']?.toString());
      addText((whoIAm['derived'] as Map)['summary']?.toString());
      addText((whoIAm['derived'] as Map)['interests']?.toString());
    }

    // 2. CV importado — skills estruturadas (caso futuro AI parsing)
    final imported = data['imported_resume'];
    if (imported is Map) {
      addText(imported['skills']?.toString());
      // Texto bruto do PDF (caminho atual: sem AI, só keyword overlap)
      addText(imported['raw_text']?.toString());
    }

    return pool;
  }

  /// Calcula quanto dos requisitos da vaga estão presentes no pool do user.
  /// Para cada palavra significativa dos requirements/description da vaga,
  /// vê se aparece no pool. Retorna ratio 0.0-1.0.
  static double _computeOverlap(Set<String> userPool, Job job) {
    if (userPool.isEmpty) return 0.0;

    // Junta requisitos + descrição (descrição cap em 1500 chars pra não
    // diluir demais com texto irrelevante de "sobre a empresa")
    final desc = job.description.length > 1500
        ? job.description.substring(0, 1500)
        : job.description;
    final haystackText = '${job.requirements.join(" ")} $desc';

    final jobKeywords = <String>{};
    for (final raw in haystackText.split(RegExp(r'[\s,.;:!?()\[\]{}<>"/\\\-•|]+'))) {
      final w = raw.trim().toLowerCase().replaceAll(RegExp(r'[^\wá-ú]'), '');
      if (w.length < 4) continue; // filtra mais agressivo aqui (4+ chars)
      if (_stopWords.contains(w)) continue;
      if (RegExp(r'^\d+$').hasMatch(w)) continue;
      jobKeywords.add(w);
    }

    if (jobKeywords.isEmpty) return 0.0;

    int matches = 0;
    for (final kw in jobKeywords) {
      if (userPool.contains(kw)) matches++;
    }
    // Ratio + boost levinho (em raras vagas, ~10-15 keywords matching = score 100%)
    final raw = matches / jobKeywords.length;
    return (raw * 2.5).clamp(0.0, 1.0);
  }
}
