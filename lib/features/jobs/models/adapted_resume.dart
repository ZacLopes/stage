import '../../../data/models/models.dart'
    show
        ResumeAward,
        ResumeCourse,
        ResumeLanguage,
        ResumeLeadership,
        ResumeProject;
import '../../resume/resume_viewmodel.dart'
    show ResumeData, ExperienceItem, EducationItem, ToolWithLevel;

// ────────────────────────────────────────────────────────────────────────────
// Helpers de detecção de redundância em education.activities
// ────────────────────────────────────────────────────────────────────────────
//
// Quando uma activity é "Relevant Coursework: <majors+minors>", ela repete
// no PDF a mesma informação já presente no `detailLine` do EducationItem
// (renderizado como subtítulo acima das activities). Filtramos antes do
// EducationItem ser construído pra evitar a dup visível.

const _redundancyStopWords = {
  'with', 'and', 'of', 'the', 'a', 'an', 'in', 'on', 'for',
  'com', 'e', 'de', 'do', 'da', 'dos', 'das', 'em', 'para',
  'major', 'minor', 'majors', 'minors',
};

const _courseworkLabelsNormalized = {
  'relevant coursework',
  'coursework',
  'relevant courses',
  'disciplinas',
  'disciplinas relevantes',
};

/// Lowercase + remove diacritics. Char-by-char mapping (mesmo padrão de
/// `_stripAccents` em work_locations_screen.dart:316).
String _stripDiacriticsLower(String s) {
  const map = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.split('')) {
    buf.write(map[ch] ?? ch);
  }
  return buf.toString();
}

Set<String> _tokenizeForRedundancy(String s) {
  final normalized = _stripDiacriticsLower(s);
  return normalized
      .split(RegExp(r'[\s,.;:!?()\[\]{}<>"/\\\-•|&]+'))
      .where((w) => w.length >= 3 && !_redundancyStopWords.contains(w))
      .toSet();
}

/// Retorna true se essa activity for `Relevant Coursework: [majors+minors]`
/// — ou seja, repete informação já presente no detailLine. Drop pra evitar
/// dup visível no PDF (Harvard MCS renderiza activity como bullet, e
/// detailLine renderiza acima como subtítulo).
bool _isRedundantCourseworkActivity(
  String activity,
  List<String> majors,
  List<String> minors,
) {
  final colonIdx = activity.indexOf(':');
  if (colonIdx <= 0 || colonIdx >= 60) return false;
  final label = _stripDiacriticsLower(activity.substring(0, colonIdx).trim());
  if (!_courseworkLabelsNormalized.contains(label)) return false;

  final content = activity.substring(colonIdx + 1).trim();
  if (content.isEmpty) return false;

  final contentTokens = _tokenizeForRedundancy(content);
  if (contentTokens.isEmpty) return false;

  final majorMinorTokens =
      _tokenizeForRedundancy([...majors, ...minors].join(' '));
  if (majorMinorTokens.isEmpty) return false;

  final intersection = contentTokens.intersection(majorMinorTokens);
  final overlap = intersection.length / contentTokens.length;
  return overlap >= 0.7;
}

/// Resultado da adaptação de currículo pra uma vaga específica.
///
/// Vem da edge function `adapt-resume-to-job`. Toda informação aqui já passou
/// pelo validador anti-invenção server-side: nome, email, empresas, datas e
/// instituições estão garantidamente iguais ao input original.
class AdaptedResume {
  /// ID da vaga pra qual foi adaptado.
  final String jobId;

  /// Lista de mudanças explicáveis (máximo 6). Cada uma documenta um ajuste
  /// feito, com before/after pra UI mostrar diff.
  final List<ResumeChange> changes;

  /// Currículo adaptado completo, no mesmo formato que o resto do app
  /// consome (PdfService, ResumeEditScreen). Pronto pra exportar.
  final ResumeData resumeData;

  /// Score de match estimado ANTES da adaptação (0-100). Heurístico.
  final int? matchScoreBefore;

  /// Score de match estimado DEPOIS da adaptação (0-100). Sempre >= before.
  final int? matchScoreAfter;

  /// Veio do cache server-side (sem custo de IA)?
  final bool cached;

  /// Modelo usado (ex: "gpt-4o-mini").
  final String? modelUsed;

  /// Skills extras que o user confirmou ter (e que foram incluídas no CV
  /// adaptado). Vem da tela de "confirmação de skills" antes da adaptação.
  /// Vazio quando user pulou ou não confirmou nenhuma.
  final List<String> extraSkillsUsed;

  /// Versão editada pelo usuário na tela de preview (F1). Null quando o
  /// usuário não editou nada — `resumeData` é usado direto. Quando não-null,
  /// é o que vai para o PDF final. `resumeData` original fica preservado
  /// para mostrar diff e permitir "voltar ao original".
  final ResumeData? userEditedResumeData;

  const AdaptedResume({
    required this.jobId,
    required this.changes,
    required this.resumeData,
    this.matchScoreBefore,
    this.matchScoreAfter,
    this.cached = false,
    this.modelUsed,
    this.extraSkillsUsed = const [],
    this.userEditedResumeData,
  });

  /// Dados efetivos para gerar o PDF — versão editada se existe, senão a
  /// adaptada pela IA. Use sempre que for renderizar/exportar.
  ResumeData get effectiveResumeData => userEditedResumeData ?? resumeData;

  /// True se o usuário editou pelo menos um campo na preview.
  bool get hasUserEdits => userEditedResumeData != null;

  /// Quantos pontos de match a adaptação adicionou. Null se não temos os dois
  /// scores. Sempre >= 0 (clamp no server-side).
  int? get matchUpgrade {
    if (matchScoreBefore == null || matchScoreAfter == null) return null;
    return matchScoreAfter! - matchScoreBefore!;
  }

  AdaptedResume copyWith({
    ResumeData? userEditedResumeData,
    bool clearUserEdits = false,
  }) {
    return AdaptedResume(
      jobId: jobId,
      changes: changes,
      resumeData: resumeData,
      matchScoreBefore: matchScoreBefore,
      matchScoreAfter: matchScoreAfter,
      cached: cached,
      modelUsed: modelUsed,
      extraSkillsUsed: extraSkillsUsed,
      userEditedResumeData: clearUserEdits ? null : (userEditedResumeData ?? this.userEditedResumeData),
    );
  }

  factory AdaptedResume.fromJson(Map<String, dynamic> json, {required String jobId}) {
    final rawChanges = (json['changes'] as List?) ?? const [];
    final changes = rawChanges
        .map((e) => ResumeChange.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final rawResume = json['resume_data'];
    if (rawResume is! Map) {
      throw const FormatException('resume_data ausente ou em formato inválido');
    }
    final resumeData = _parseResumeData(Map<String, dynamic>.from(rawResume));

    final rawExtra = (json['extra_skills_used'] as List?) ?? const [];
    final extraSkillsUsed = rawExtra
        .map((e) => e?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    return AdaptedResume(
      jobId: jobId,
      changes: changes,
      resumeData: resumeData,
      matchScoreBefore: (json['match_score_before'] as num?)?.toInt(),
      matchScoreAfter: (json['match_score_after'] as num?)?.toInt(),
      cached: json['cached'] == true,
      modelUsed: json['model_used']?.toString(),
      extraSkillsUsed: extraSkillsUsed,
    );
  }

  /// Constrói um `ResumeData` a partir do JSON estruturado do servidor.
  /// Exposto público pra também montar o "original" na tela de preview a
  /// partir de `gamification_data.imported_resume.parsed`.
  static ResumeData parseResumeData(Map<String, dynamic> json) =>
      _parseResumeData(json);

  /// Serializa um `ResumeData` no MESMO formato JSON que `parseResumeData`
  /// espera (roundtrip preservado). Usado pra persistir o `resume_data` em
  /// `saved_resumes` — permite re-render com template diferente depois.
  ///
  /// F4.2: o serializer é COMPLETO o suficiente para o Currículo geral
  /// round-tripar sem perda — `awards`, `academicProjects` e `leadership`
  /// (seções que o formato adaptado antigo não tinha) e `certifications` com
  /// `institution`/`period` (issuer/ano). `tools` sai como `{name, level}` e
  /// há `toolsText`. Retrocompatível: o parser ainda lê o formato legado
  /// (`tools`/`certifications` como `string[]`) — ausência de uma seção nova
  /// vira lista vazia.
  ///
  /// Fronteira consciente (inalterada): education sai como `details` já
  /// montado (não restaura majors/minors separados — a projeção constrói a
  /// detail line a partir deles e o `EducationItem` guarda só o detail final);
  /// `honors`/`repRole`/`coursework` são derivados no parse e ficam vazios na
  /// projeção geral. Activities preservadas.
  static Map<String, dynamic> serializeResumeData(ResumeData r) {
    return <String, dynamic>{
      'fullName': r.fullName,
      'email': r.email,
      'phone': r.phone,
      'linkedin': r.linkedin,
      'location': r.location,
      'streetAddress': r.address,
      'language': r.language,
      'summary': r.summary,
      'skills': r.skills,
      // tools: chave LEGADA mantida como `string[]` de propósito — é o que
      // binários já publicados sabem ler. O nível vai em `tools_v2`, que só o
      // parser novo procura. Ver a nota de compatibilidade em `_parseResumeData`.
      'tools': r.tools
          .where((t) => t.name.isNotEmpty)
          .map((t) => t.name)
          .toList(),
      'tools_v2': r.tools
          .where((t) => t.name.isNotEmpty)
          .map((t) => {'name': t.name, 'level': t.level})
          .toList(),
      'toolsText': r.toolsText,
      'experiences': r.experiences.map((e) => {
            'role': e.role,
            'company': e.company,
            'period': e.period,
            'description': e.description,
            'location': e.location,
          }).toList(),
      'education': r.education.map((e) => {
            'degree': e.degree,
            'institution': e.institution,
            'period': e.period,
            'details': e.details,
            'location': e.location,
            'gpa': e.gpa,
            'activities': e.activities,
          }).toList(),
      'languages': r.languages.map((l) => {
            'name': l.language,
            'proficiency': l.level,
          }).toList(),
      'achievements': r.achievements,
      'interests': r.interests,
      // certifications: chave LEGADA mantida como `string[]` (só o título) —
      // é o que binários já publicados sabem ler. Instituição e ano vão em
      // `certifications_v2`. Ver a nota de compatibilidade em `_parseResumeData`.
      'certifications': r.courses.map((c) => c.title).toList(),
      'certifications_v2': r.courses
          .map((c) => {
                'title': c.title,
                'institution': c.institution,
                'period': c.period,
              })
          .toList(),
      // Seções que o Currículo geral popula e o formato adaptado antigo não
      // tinha. Ausência no parse (rows antigas) vira lista vazia.
      'academicProjects': r.academicProjects
          .map((p) => {
                'title': p.title,
                'role': p.role,
                'period': p.period,
                'description': p.description,
                'location': p.location,
                'relevantWork': p.relevantWork,
                'experiencePhaseId': p.experiencePhaseId,
              })
          .toList(),
      'awards': r.awards
          .map((a) => {
                'title': a.title,
                'institution': a.institution,
                'date': a.date,
                'description': a.description,
              })
          .toList(),
      'leadership': r.leadership
          .map((l) => {
                'role': l.role,
                'organization': l.organization,
                'period': l.period,
                'location': l.location,
                'description': l.description,
                'relevantWork': l.relevantWork,
                'experiencePhaseId': l.experiencePhaseId,
              })
          .toList(),
    };
  }

  static ResumeData _parseResumeData(Map<String, dynamic> json) {
    List<String> stringList(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }

    /// Leitura tolerante de lista heterogênea (itens String OU Map).
    ///
    /// A F4.2 trocou `certifications`/`tools` de `string[]` para lista de
    /// objetos e, junto, trocou o `stringList` tolerante por `as List?` — um
    /// cast duro que LANÇA quando a row legada guardou outra coisa, derrubando
    /// a tela de detalhe em vez de degradar para vazio. Achado do code-review
    /// de 27/07: restaura a tolerância mantendo o formato novo.
    List<dynamic> anyList(dynamic v) => v is List ? v : const [];

    final experiencesRaw = (json['experiences'] as List?) ?? const [];
    final experiences = experiencesRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return ExperienceItem(
        role: m['role']?.toString() ?? '',
        company: m['company']?.toString() ?? '',
        period: m['period']?.toString() ?? '',
        description: m['description']?.toString() ?? '',
        location: m['location']?.toString() ?? '',
      );
    }).toList();

    // Education v2 (Tier 1.5): a IA retorna `gpa`, `majors`, `minors`,
    // `activities` separados. Mapeamos pros campos do template Harvard:
    //   - gpa            → edu.gpa
    //   - majors[]       → edu.details (linha de detalhe sob o degree;
    //                      ex: "Business Admin Major with Finance Minor")
    //   - minors[]       → entram no details junto pra formar a linha
    //   - activities[]   → edu.honors (seção "Honras & Distinção Acadêmica")
    // Backward compat: se v1 só manda `details: string`, usa direto.
    final educationRaw = (json['education'] as List?) ?? const [];
    final education = educationRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final majors = stringList(m['majors']);
      final minors = stringList(m['minors']);
      // Filtra activities redundantes — "Relevant Coursework: Business
      // Administration Major with Finance & Entrepreneurship Minor" repete
      // a mesma info do detailLine (renderizado acima como subtítulo).
      // Drop pra evitar dup visível no PDF e economizar 1-2 linhas.
      // Heurística: token overlap >= 70% entre content (pós ":") e
      // (majors + minors). Activities legítimas (Honors, Class Rep,
      // cursos diferentes do major) passam intactas.
      final rawActivities = stringList(m['activities']);
      final activities = rawActivities
          .where((a) => !_isRedundantCourseworkActivity(a, majors, minors))
          .toList();
      final detailsLegacy = m['details']?.toString() ?? '';
      final degree = m['degree']?.toString() ?? '';
      // Constrói detail line: "Major X with Minor Y". Se v1 (sem majors[]),
      // usa o `details` cru do GPT. Idioma vem do resume.language.
      final lang = (json['language']?.toString() ?? 'pt');
      final isEn = lang.toLowerCase().startsWith('en');
      String detailLine = detailsLegacy;
      if (majors.isNotEmpty) {
        // A1: se o major já aparece no degree ("Bachelor's degree in
        // Business Administration" + major "Business Administration"),
        // não repete — renderiza só o minor. Evita "Bachelor's in BA"
        // + "BA Major with Finance Minor" (repetindo "BA" 2x).
        final degreeTokens = _tokenizeForRedundancy(degree);
        final majorsTokens = _tokenizeForRedundancy(majors.join(' '));
        final majorRedundantWithDegree = majorsTokens.isNotEmpty &&
            majorsTokens.every((t) => degreeTokens.contains(t));

        // PT-BR não tem "Major": aqui o curso É a graduação. O ternário
        // original (`isEn ? 'Major' : 'Major'`) tinha os DOIS ramos iguais — o
        // caminho PT nunca foi escrito —, então o sufixo em inglês vazava
        // direto pro PDF do recrutador: "Engenharia de Produção Major".
        // O caminho do currículo GERAL já tratava disso
        // (profile_resume_mapper.dart:20 — "nunca injeta os sufixos
        // artificiais ingleses 'Major'/'Minor'"); só o ADAPTADO ficou para
        // trás. "Minor" segue como estrangeirismo em PT (decisão anterior,
        // ver o comentário do ramo redundante logo abaixo).

        if (majorRedundantWithDegree && minors.isNotEmpty) {
          // Só minor: "Minor in Finance" / "Minors in Finance, Entrepreneurship".
          // Em PT, mantém singular ("Minor em") — termo é estrangeirismo
          // e não tem flexão de plural natural.
          final minorLabel = isEn
              ? (minors.length > 1 ? 'Minors in' : 'Minor in')
              : 'Minor em';
          detailLine = '$minorLabel ${minors.join(', ')}';
        } else if (majorRedundantWithDegree) {
          // Major redundante + sem minors → sem detail line
          detailLine = '';
        } else if (isEn) {
          // "Business Administration Major with Finance Minor"
          detailLine = '${majors.join(', ')} Major';
          if (minors.isNotEmpty) {
            detailLine += ' with ${minors.join(', ')} Minor';
          }
        } else {
          // PT: só o curso. "Engenharia de Produção" — sem sufixo.
          detailLine = majors.join(', ');
          if (minors.isNotEmpty) {
            detailLine += ' com Minor em ${minors.join(', ')}';
          }
        }
      }
      // Honors fallback pra templates não-Harvard (Jakes, Forte, OnePage)
      // que ainda renderizam `honors` single-string. Faz strip do prefix
      // "Honors and Academic Distinction:" se presente — evita dup com
      // label que esses templates colocam ao redor do campo. Pro Harvard
      // MCS o campo `activities` (lista) tem prioridade.
      const honorsPrefixes = [
        'honors and academic distinction:',
        'honors & academic distinction:',
        'honras e distinção acadêmica:',
        'honras & distinção acadêmica:',
      ];
      String stripHonorsPrefix(String s) {
        final lower = s.toLowerCase();
        for (final p in honorsPrefixes) {
          if (lower.startsWith(p)) return s.substring(p.length).trim();
        }
        return s;
      }
      final honorsLine = activities
          .map(stripHonorsPrefix)
          .where((s) => s.isNotEmpty)
          .join('; ');

      return EducationItem(
        degree: m['degree']?.toString() ?? '',
        institution: m['institution']?.toString() ?? '',
        period: m['period']?.toString() ?? '',
        details: detailLine,
        location: m['location']?.toString() ?? '',
        gpa: m['gpa']?.toString() ?? '',
        // activities (Tier 1.2): preserva lista — Harvard MCS renderiza
        // cada item como <li> com label semântico (Honors:, Class Rep:).
        activities: activities,
        // honors mantido (com strip do prefix dup) pra templates que
        // renderizam honors single-string com label próprio.
        honors: honorsLine,
        repRole: '',
        coursework: '',
      );
    }).toList();

    // Helper: só os itens Map de uma lista, cada um como Map<String,dynamic>.
    List<Map<String, dynamic>> mapList(dynamic v) {
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    // ── COMPATIBILIDADE ENTRE VERSÕES DO APP (27/07) ───────────────────────
    //
    // A F4.2 enriqueceu certificações/tools, mas gravou o formato novo NA
    // CHAVE ANTIGA. Binários já publicados leem essa chave esperando
    // `string[]`: ao encontrar objetos, o `toString()` deles ia parar no PDF
    // como `{title: X, institution: Y}` — num documento que o candidato anexa
    // numa vaga.
    //
    // Agora a escrita é DUPLA: a chave antiga volta a ser `string[]` (binário
    // velho lê e fica feliz) e o detalhe rico mora em `*_v2`. A leitura prefere
    // `_v2`; sem ele, cai na antiga — que segue aceitando String E Map, porque
    // rows gravadas na janela entre a F4.2 e hoje têm objetos ali.
    final certificationsRaw = anyList(json['certifications_v2']).isNotEmpty
        ? anyList(json['certifications_v2'])
        : anyList(json['certifications']);
    final certifications = certificationsRaw
        .map((c) {
          if (c is Map) {
            final m = Map<String, dynamic>.from(c);
            return ResumeCourse(
              title: m['title']?.toString() ?? '',
              institution: m['institution']?.toString() ?? '',
              period: m['period']?.toString() ?? '',
            );
          }
          return ResumeCourse(
              title: c?.toString() ?? '', institution: '', period: '');
        })
        .where((c) => c.title.isNotEmpty)
        .toList();

    // Mesma política de escrita dupla das certificações (ver acima).
    final toolsRaw = anyList(json['tools_v2']).isNotEmpty
        ? anyList(json['tools_v2'])
        : anyList(json['tools']);
    final tools = toolsRaw
        .map((t) {
          if (t is Map) {
            final m = Map<String, dynamic>.from(t);
            return ToolWithLevel(
              m['name']?.toString() ?? '',
              m['level']?.toString() ?? '',
            );
          }
          return ToolWithLevel(t?.toString() ?? '', '');
        })
        .where((t) => t.name.isNotEmpty)
        .toList();

    // Seções que o Currículo geral popula (F4.2). Rows legadas não têm essas
    // chaves → lista vazia. Filtro conservador dropa só entradas sem âncora.
    final academicProjects = mapList(json['academicProjects'])
        .map((m) => ResumeProject(
              title: m['title']?.toString() ?? '',
              role: m['role']?.toString() ?? '',
              period: m['period']?.toString() ?? '',
              description: m['description']?.toString() ?? '',
              location: m['location']?.toString() ?? '',
              relevantWork: m['relevantWork']?.toString() ?? '',
              experiencePhaseId: m['experiencePhaseId']?.toString() ?? '',
            ))
        .where((p) =>
            p.title.isNotEmpty ||
            p.role.isNotEmpty ||
            p.description.isNotEmpty)
        .toList();

    final awards = mapList(json['awards'])
        .map((m) => ResumeAward(
              title: m['title']?.toString() ?? '',
              institution: m['institution']?.toString() ?? '',
              date: m['date']?.toString() ?? '',
              description: m['description']?.toString() ?? '',
            ))
        .where((a) => a.title.isNotEmpty)
        .toList();

    final leadership = mapList(json['leadership'])
        .map((m) => ResumeLeadership(
              role: m['role']?.toString() ?? '',
              organization: m['organization']?.toString() ?? '',
              period: m['period']?.toString() ?? '',
              location: m['location']?.toString() ?? '',
              description: m['description']?.toString() ?? '',
              relevantWork: m['relevantWork']?.toString() ?? '',
              experiencePhaseId: m['experiencePhaseId']?.toString() ?? '',
            ))
        .where((l) => l.role.isNotEmpty || l.organization.isNotEmpty)
        .toList();

    // Languages v2 (Tier 1.5): GPT retorna [{name, proficiency}]. Antes
    // o template renderizava languages como dado opcional vazio. Agora
    // populado a partir da seção Languages do CV original.
    final languagesRaw = (json['languages'] as List?) ?? const [];
    final languages = languagesRaw
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          return ResumeLanguage(
            language: m['name']?.toString() ?? '',
            level: m['proficiency']?.toString() ?? '',
          );
        })
        .where((l) => l.language.isNotEmpty)
        .toList();

    return ResumeData(
      fullName: json['fullName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      linkedin: json['linkedin']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      // streetAddress (Tier 1.5) — preserva rua + bairro completo. Template
      // Harvard mostra na linha de endereço sob o nome.
      address: json['streetAddress']?.toString() ?? '',
      language: json['language']?.toString() ?? 'pt',
      summary: json['summary']?.toString() ?? '',
      skills: stringList(json['skills']),
      tools: tools,
      toolsText: json['toolsText']?.toString() ?? '',
      experiences: experiences,
      education: education,
      languages: languages,
      academicProjects: academicProjects,
      leadership: leadership,
      achievements: stringList(json['achievements']),
      interests: stringList(json['interests']),
      courses: certifications,
      awards: awards,
    );
  }
}

/// Uma mudança específica feita na adaptação (ex: "reordenei skills",
/// "reformulei bullet de Nubank"). UI mostra como diff antes/depois.
class ResumeChange {
  /// Identificador técnico do campo (ex: "summary", "skills",
  /// "experiences[0].description"). Pra UI agrupar/iconear.
  final String field;

  /// Label humano (ex: "Resumo profissional", "Habilidades",
  /// "Experiência: Estagiário @ Nubank"). PT-BR.
  final String label;

  /// Conteúdo antes (texto livre). UI mostra com strikethrough cinza.
  final String before;

  /// Conteúdo depois. UI mostra com destaque.
  final String after;

  /// Razão curta (≤80 chars). Ex: "Coloca Figma primeiro porque vaga pede".
  final String reason;

  const ResumeChange({
    required this.field,
    required this.label,
    required this.before,
    required this.after,
    required this.reason,
  });

  factory ResumeChange.fromJson(Map<String, dynamic> json) {
    return ResumeChange(
      field: json['field']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      before: json['before']?.toString() ?? '',
      after: json['after']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
    );
  }

  /// Categoria visual da mudança, pra UI escolher ícone/cor.
  ChangeCategory get category {
    final f = field.toLowerCase();
    if (f.contains('summary') || f.contains('resumo')) return ChangeCategory.summary;
    if (f.contains('skill') || f.contains('habilidade')) return ChangeCategory.skills;
    if (f.contains('experience') || f.contains('exper')) return ChangeCategory.experience;
    if (f.contains('education') || f.contains('formac')) return ChangeCategory.education;
    if (f.contains('achiev') || f.contains('conquist')) return ChangeCategory.achievements;
    return ChangeCategory.other;
  }
}

enum ChangeCategory { summary, skills, experience, education, achievements, other }
