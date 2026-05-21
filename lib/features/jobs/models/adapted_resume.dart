import '../../resume/resume_viewmodel.dart' show ResumeData, ExperienceItem, EducationItem;

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

  static ResumeData _parseResumeData(Map<String, dynamic> json) {
    List<String> stringList(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }

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

    final educationRaw = (json['education'] as List?) ?? const [];
    final education = educationRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return EducationItem(
        degree: m['degree']?.toString() ?? '',
        institution: m['institution']?.toString() ?? '',
        period: m['period']?.toString() ?? '',
        details: m['details']?.toString() ?? '',
        location: m['location']?.toString() ?? '',
      );
    }).toList();

    return ResumeData(
      fullName: json['fullName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      linkedin: json['linkedin']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      language: json['language']?.toString() ?? 'pt',
      summary: json['summary']?.toString() ?? '',
      skills: stringList(json['skills']),
      experiences: experiences,
      education: education,
      achievements: stringList(json['achievements']),
      interests: stringList(json['interests']),
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
