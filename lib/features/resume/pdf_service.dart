import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../data/models/models.dart';
import 'resume_viewmodel.dart';

class PdfService {
  static Future<void> generateResume(
    UserProfile? user,
    ResumeData resume,
    String templateId,
  ) async {
    try {
      final bytes = await generateResumeBytes(user, resume, templateId);
      
      final safeName = user?.name ?? 'profissional';
      final filename = 'curriculo_${safeName.replaceAll(' ', '_')}.pdf';
      
      await Printing.sharePdf(
        bytes: bytes,
        filename: filename,
      );
    } catch (e) {
      print('Error in generateResume: $e');
      rethrow;
    }
  }

  /// Gera o PDF do currículo. Todos os templates ativos são renderizados via
  /// HTML → PDF (`Printing.convertHtml`), pois HTML/CSS dá controle ATS-friendly
  /// muito superior aos widgets `pw.*`.
  ///
  /// Templates suportados:
  ///   - `harvard_ats`       Harvard MCS (default)
  ///   - `jakes_resume`      Jake Gutierrez LaTeX-style (tech)
  ///   - `forte_foundation`  Padrão MBA banking/consulting
  ///   - `one_page_compact`  Estudante early-career, 1 página garantida
  ///
  /// IDs desconhecidos caem em `harvard_ats` (mais seguro).
  ///
  /// REGENERATE: ao alterar o HTML/CSS de qualquer template abaixo, regere
  /// os PNGs de preview em `assets/images/templates/` via
  /// Settings → "[DEV] Gerar thumbnails dos templates".
  static Future<Uint8List> generateResumeBytes(
    UserProfile? user,
    ResumeData resume,
    String templateId,
  ) async {
    final html = switch (templateId) {
      'jakes_resume'     => _buildJakesResumeHtml(user, resume),
      'forte_foundation' => _buildForteFoundationHtml(user, resume),
      'one_page_compact' => _buildOnePageHtml(user, resume),
      _                  => _buildHarvardMcsHtml(user, resume), // default + harvard_ats
    };
    return await Printing.convertHtml(
      html: html,
      format: PdfPageFormat.a4,
    );
  }

  // --- 7. Harvard MCS Template (HTML → PDF via Printing.convertHtml) ---
  /// Returns the localized label for a given key, based on resume.language.
  static String _l10n(String key, String lang) {
    final pt = const {
      'summary': 'Sumário',
      'education': 'Educação',
      'experience': 'Experiência Profissional',
      'leadership': 'Atividades Extracurriculares',
      'skills_section': 'Habilidades, Certificações &amp; Programas',
      'technical_skills': 'Habilidades Técnicas',
      'languages': 'Idiomas',
      'tools': 'Ferramentas',
      'certifications': 'Certificações &amp; Programas',
      'interests': 'Interesses',
      'mobile': 'Mobile',
      'edu_coursework': 'Disciplinas relevantes',
      'edu_gpa': 'CR',
      'edu_honors': 'Honras &amp; Distinção Acadêmica',
      'edu_rep_role': 'Cargo representativo',
      'relevant_work': 'Trabalho Relevante',
      'projects': 'Projetos &amp; Liderança',
      'courses': 'Cursos &amp; Certificações',
      'coursework': 'Disciplinas',
      'lvl_native': 'Nativo',
      'lvl_fluent': 'Fluente',
      'lvl_advanced': 'Avançado',
      'lvl_intermediate': 'Intermediário',
      'lvl_basic': 'Básico',
      'lang_in': 'em', // "Fluente em Inglês"
    };
    final en = const {
      'summary': 'Summary',
      'education': 'Education',
      'experience': 'Professional Experience',
      'leadership': 'Extracurricular Activities',
      'skills_section': 'Skills, Certifications &amp; Programs',
      'technical_skills': 'Technical Skills',
      'languages': 'Languages',
      'tools': 'Tools',
      'certifications': 'Certifications &amp; Programs',
      'interests': 'Interests',
      'mobile': 'Mobile',
      'edu_coursework': 'Relevant Coursework',
      'edu_gpa': 'GPA',
      'edu_honors': 'Honors &amp; Academic Distinction',
      'edu_rep_role': 'Representative Role',
      'relevant_work': 'Relevant Work',
      'projects': 'Projects &amp; Leadership',
      'courses': 'Courses &amp; Certifications',
      'coursework': 'Coursework',
      'lvl_native': 'Native',
      'lvl_fluent': 'Fluent',
      'lvl_advanced': 'Advanced',
      'lvl_intermediate': 'Intermediate',
      'lvl_basic': 'Basic',
      'lang_in': 'in', // "Fluent in English"
    };
    return (lang == 'en' ? en[key] : pt[key]) ?? key;
  }

  /// Translates a Portuguese proficiency level to English when needed.
  /// Used so that AI output that still has PT levels (cache from before
  /// the EN regeneration) renders correctly under EN templates.
  static String _translateLevel(String level, String lang) {
    if (lang != 'en') return level;
    switch (level.toLowerCase().trim()) {
      case 'nativo':
        return 'Native';
      case 'fluente':
        return 'Fluent';
      case 'avançado':
      case 'avancado':
        return 'Advanced';
      case 'intermediário':
      case 'intermediario':
        return 'Intermediate';
      case 'básico':
      case 'basico':
        return 'Basic';
      default:
        return level;
    }
  }

  static String _buildHarvardMcsHtml(UserProfile? user, ResumeData resume) {
    final lang = resume.language;
    final summaryHtml = resume.summary.trim().isNotEmpty
        ? '<div class="sec">${_l10n('summary', lang)}</div><div class="entry">${_escapeHtml(resume.summary.trim())}</div>'
        : '';

    final eduItems = resume.education
        .map((e) => _buildHarvardEducationItemHtml(e, resume))
        .join('');
    final educationHtml = resume.education.isNotEmpty
        ? '<div class="sec">${_l10n('education', lang)}</div>$eduItems'
        : '';

    final expItems = resume.experiences
        .map((e) => _buildHarvardExperienceItemHtml(e, resume))
        .join('');
    final experienceHtml = resume.experiences.isNotEmpty
        ? '<div class="sec">${_l10n('experience', lang)}</div>$expItems'
        : '';

    final projectItems = resume.academicProjects
        .map((p) => _buildHarvardActivityItemHtml(
              p.title,
              p.location,
              p.role,
              p.period,
              p.description,
              relevantWork: p.relevantWork,
              relevantLabel: _l10n('relevant_work', lang),
            ))
        .join('');
    final leadItems = resume.leadership
        .map((l) => _buildHarvardActivityItemHtml(
              l.organization,
              l.location,
              l.role,
              l.period,
              l.description,
              relevantWork: l.relevantWork,
              relevantLabel: _l10n('relevant_work', lang),
            ))
        .join('');
    // Achievements (do servidor: projetos + certificações vindos de adapt-resume).
    // Cada item vem com marcador `▸` separando title/role/description (até 3 partes).
    // Renderização: title em bold, role em itálico/cinza, description em texto normal.
    final achievementsBullets = resume.achievements
        .where((a) => a.trim().isNotEmpty)
        .map((a) => _renderAchievementItem(a.trim()))
        .join('');
    final achievementsHtml = achievementsBullets.isEmpty
        ? ''
        : '<div class="sec">${_l10n('leadership', lang)}</div>$achievementsBullets';

    final activitiesHtml = (resume.academicProjects.isNotEmpty || resume.leadership.isNotEmpty)
        ? '<div class="sec">${_l10n('leadership', lang)}</div>$projectItems$leadItems'
        : achievementsHtml;

    final skillParts = <String>[];
    // Harvard MCS order: Technical Skills → Languages → Tools → Certifications
    // Each as its own labeled line (single line per category).

    String _withDot(String s) => s.trimRight().endsWith('.') ? s : '$s.';

    if (resume.skills.isNotEmpty) {
      final skillsText = _withDot(resume.skills.join(', '));
      skillParts.add('<div class="sk"><b>${_l10n('technical_skills', lang)}:</b> $skillsText</div>');
    }

    if (resume.languages.isNotEmpty) {
      skillParts.add('<div class="sk"><b>${_l10n('languages', lang)}:</b> ${_withDot(_buildLanguagesText(resume.languages, lang))}</div>');
    }

    if (resume.toolsText.trim().isNotEmpty) {
      skillParts.add('<div class="sk"><b>${_l10n('tools', lang)}:</b> ${_withDot(_escapeHtml(resume.toolsText.trim()))}</div>');
    } else if (resume.tools.isNotEmpty) {
      skillParts.add('<div class="sk"><b>${_l10n('tools', lang)}:</b> ${_withDot(_buildToolsText(resume.tools, lang))}</div>');
    }

    if (resume.courses.isNotEmpty) {
      final courseItems = resume.courses.map((c) {
        final parts = <String>[c.title];
        if (c.institution.isNotEmpty) parts.add(c.institution);
        var formatted = parts.join(' - ');
        if (c.period.isNotEmpty) formatted = '$formatted (${c.period})';
        if (!formatted.trimRight().endsWith('.')) formatted = '$formatted.';
        return '<li>${_escapeHtml(formatted)}</li>';
      }).join('');
      skillParts.add('<div class="sk"><b>${_l10n('certifications', lang)}:</b></div><ul>$courseItems</ul>');
    }

    final skillsContent = skillParts.join('');
    final skillsHtml = skillParts.isNotEmpty
        ? '<div class="sec">${_l10n('skills_section', lang)}</div>$skillsContent'
        : '';

    final interestsHtml = resume.interests.isNotEmpty
        ? '<div class="sec">${_l10n('interests', lang)}</div>'
          '<div class="entry"><b>${_l10n('interests', lang)}:</b> ${_escapeHtml(resume.interests.join(', '))}</div>'
        : '';

    return '''<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <style>
    @page { size: A4; margin: 0.4in 0.45in; }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Times New Roman', Times, serif; font-size: 11pt; color: #000; line-height: 1.15; }
    .header { text-align: center; margin-bottom: 3pt; }
    .name { font-weight: bold; font-size: 17pt; letter-spacing: 0.5pt; }
    .address { font-size: 9.5pt; margin-top: 3pt; }
    .contact { font-size: 9.5pt; margin-top: 1pt; }
    hr { border: none; border-top: 1px solid #000; margin: 5pt 0 10pt; }
    .sec { text-align: left; text-transform: uppercase; font-weight: bold; font-size: 11pt; letter-spacing: 0.3pt; margin: 5pt 0 0; padding-bottom: 1pt; border-bottom: 0.5pt solid #000; }
    .sec + * { margin-top: 2pt; }
    .row { display: flex; justify-content: space-between; font-size: 11pt; }
    .row .r { white-space: nowrap; margin-left: 8pt; }
    .bold .l, .bold .r { font-weight: bold; }
    .italic .l { font-style: italic; }
    .entry { margin-bottom: 4pt; }
    .rel { font-size: 11pt; margin: 1pt 0; }
    ul { margin: 1pt 0 0 0; padding: 0; list-style: none; }
    li { font-size: 11pt; margin-bottom: 0.5pt; padding-left: 0; text-indent: 0; }
    li::before { content: "• "; }
    .sk { font-size: 11pt; margin-bottom: 2pt; }
    .detail { font-size: 9.5pt; margin-top: 1pt; }
    .ach-item { margin-bottom: 4pt; }
    .ach-title { font-size: 11pt; font-weight: bold; }
    .ach-role { font-size: 10pt; font-style: italic; margin-top: 0.5pt; }
    .ach-meta { font-size: 10pt; color: #444; margin-top: 0.5pt; }
    .ach-desc { font-size: 10.5pt; margin-top: 1pt; }
  </style>
</head>
<body>
  <div class="header">
    <div class="name">${(resume.fullName.isNotEmpty ? resume.fullName : (user?.name ?? "Seu Nome")).toUpperCase()}</div>
    ${_buildHarvardAddressLine(resume)}
    <div class="contact">${_buildHarvardContactString(resume)}</div>
  </div>
  $summaryHtml
  $experienceHtml
  $educationHtml
  $activitiesHtml
  $skillsHtml
  $interestsHtml
</body>
</html>''';
  }

  static String _buildHarvardEducationItemHtml(EducationItem edu, ResumeData resume) {
    final location = edu.location;
    final detailsHtml = edu.details.isNotEmpty
        ? '<div class="detail">${_escapeHtml(edu.details)}</div>'
        : '';

    // Harvard enrichments — render as bullets when present
    final lang = resume.language;
    final highlightItems = <String>[];
    if (edu.coursework.isNotEmpty) {
      highlightItems.add('<li><b>${_l10n('edu_coursework', lang)}:</b> ${_escapeHtml(edu.coursework)}</li>');
    }
    if (edu.gpa.isNotEmpty) {
      highlightItems.add('<li><b>${_l10n('edu_gpa', lang)}:</b> ${_escapeHtml(edu.gpa)}</li>');
    }
    if (edu.honors.isNotEmpty) {
      highlightItems.add('<li><b>${_l10n('edu_honors', lang)}:</b> ${_escapeHtml(edu.honors)}</li>');
    }
    if (edu.repRole.isNotEmpty) {
      highlightItems.add('<li><b>${_l10n('edu_rep_role', lang)}:</b> ${_escapeHtml(edu.repRole)}</li>');
    }
    final highlightsHtml = highlightItems.isNotEmpty
        ? '<ul>${highlightItems.join('')}</ul>'
        : '';

    return '<div class="entry">'
        '<div class="row bold"><span class="l">${edu.institution}</span>'
        '<span class="r">$location</span></div>'
        '<div class="row italic"><span class="l">${edu.degree}</span>'
        '<span class="r">${edu.period}</span></div>'
        '$detailsHtml'
        '$highlightsHtml'
        '</div>';
  }

  static String _buildHarvardExperienceItemHtml(ExperienceItem exp, ResumeData resume) {
    final location = exp.location;
    // Top row: Company (bold) + Location (right). Bottom row: Role (italic) + Period.
    return '<div class="entry">'
        '<div class="row bold"><span class="l">${exp.company}</span>'
        '<span class="r">$location</span></div>'
        '<div class="row italic"><span class="l">${exp.role}</span>'
        '<span class="r">${exp.period}</span></div>'
        '${_buildHarvardBulletsHtml(exp.description)}'
        '</div>';
  }

  static String _buildHarvardActivityItemHtml(
    String leftTop,
    String rightTop,
    String leftBot,
    String rightBot,
    String description, {
    String relevantWork = '',
    String relevantLabel = 'Relevant Work',
  }) {
    // Top row: Organization (bold) + Location (right). Bottom row: Role (italic) + Period.
    final botRow = (leftBot.isNotEmpty || rightBot.isNotEmpty)
        ? '<div class="row italic"><span class="l">$leftBot</span><span class="r">$rightBot</span></div>'
        : '';
    final relRow = relevantWork.trim().isNotEmpty
        ? '<div class="rel"><b>${_escapeHtml(relevantLabel)}:</b> ${_escapeHtml(relevantWork.trim())}</div>'
        : '';
    return '<div class="entry">'
        '<div class="row bold"><span class="l">$leftTop</span><span class="r">$rightTop</span></div>'
        '$botRow'
        '$relRow'
        '${_buildHarvardBulletsHtml(description)}'
        '</div>';
  }

  static String _buildHarvardBulletsHtml(String description) {
    final lines = description.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return '';
    final items = lines.map((line) {
      final clean = line.replaceAll('•', '').trim();
      return '<li>${_emphasizeMetrics(clean)}</li>';
    }).join('');
    return '<ul>$items</ul>';
  }

  /// Bolds quantitative tokens inside bullet text (Harvard "fact-based" rule).
  /// Catches:
  ///   percentages       — "20%", "2,5%", "20 %"
  ///   plus-counts       — "200+", "1.000+"
  ///   currency          — "R$ 50.000", "R$ 1M"
  ///   Brazilian numbers — "1.000 downloads", "200 pessoas", "5 anos"
  ///   rankings          — "1º lugar", "1ª colocada", "top 5"
  ///   ranges of hours   — "100 horas"
  /// The pattern intentionally avoids matching dates ("2024", "Jan 2025") which
  /// the bullet rarely mentions in body text (dates live in the row header).
  static String _emphasizeMetrics(String text) {
    final patterns = <RegExp>[
      // Percent: 20%, 2,5%, 1.5%
      RegExp(r'\d+(?:[.,]\d+)?\s*%'),
      // Plus-counts: 200+, 1.000+, 5+
      RegExp(r'\d+(?:[.,]\d+)*\+'),
      // Currency: R$ 50.000, R$ 1M, R$ 1,5K
      RegExp(r'R\$\s*\d+(?:[.,]\d+)*\s*[KMB]?', caseSensitive: false),
      // Rankings: 1º, 2ª, 3°, top 5
      RegExp(r'\b\d+[ºª°]\b'),
      RegExp(r'\btop\s*\d+\b', caseSensitive: false),
      // Number + countable noun (downloads, usuários, pessoas, horas, etc.)
      RegExp(
        r'\b\d+(?:[.,]\d+)*\s+(?:downloads?|usuários?|usuarios?|membros?|pessoas?|alunos?|clientes?|atendentes?|alvos?|empresas?|projetos?|países?|paises?|horas?|meses?|anos?|semanas?|dias?|trainees?|participantes?)',
        caseSensitive: false,
      ),
    ];

    String out = text;
    for (final re in patterns) {
      out = out.replaceAllMapped(re, (m) => '<b>${m.group(0)}</b>');
    }
    return out;
  }

  /// Group languages by proficiency level into Harvard-style sentences.
  /// Output PT: "Fluente em Inglês e Português; Básico em Espanhol"
  /// Output EN: "Fluent in English and Portuguese; Basic in Spanish"
  static String _buildLanguagesText(List<ResumeLanguage> langs, String lang) {
    // Canonical order in PT — gets translated for EN at render time.
    const ptOrder = ['Nativo', 'Fluente', 'Avançado', 'Intermediário', 'Básico'];
    const enOrder = ['Native', 'Fluent', 'Advanced', 'Intermediate', 'Basic'];
    final byLevel = <String, List<String>>{};
    for (final l in langs) {
      // Normalize the level — accept either PT or EN input from cache
      final raw = l.level.trim();
      final normalized = _translateLevel(raw, lang).isNotEmpty
          ? _translateLevel(raw, lang)
          : raw;
      final key = normalized.isEmpty ? 'Outro' : normalized;
      byLevel.putIfAbsent(key, () => []).add(l.language);
    }
    final order = lang == 'en' ? enOrder : ptOrder;
    final parts = <String>[];
    final preposition = _l10n('lang_in', lang);
    for (final level in order) {
      final list = byLevel.remove(level);
      if (list != null && list.isNotEmpty) {
        parts.add('$level $preposition ${_joinList(list)}');
      }
    }
    byLevel.forEach((level, list) {
      parts.add('$level $preposition ${_joinList(list)}');
    });
    return parts.join('; ');
  }

  /// Group tools by proficiency level.
  /// Output PT: "Avançado: Excel, PowerPoint; Intermediário: Figma"
  /// Output EN: "Advanced: Excel, PowerPoint; Intermediate: Figma"
  static String _buildToolsText(List<ToolWithLevel> tools, String lang) {
    const ptOrder = ['Avançado', 'Intermediário', 'Básico'];
    const enOrder = ['Advanced', 'Intermediate', 'Basic'];
    final byLevel = <String, List<String>>{};
    for (final t in tools) {
      final raw = t.level.trim();
      final normalized = raw.isEmpty ? '' : _translateLevel(raw, lang);
      byLevel.putIfAbsent(normalized, () => []).add(t.name);
    }
    final order = lang == 'en' ? enOrder : ptOrder;
    final parts = <String>[];
    for (final level in order) {
      final list = byLevel.remove(level);
      if (list != null && list.isNotEmpty) {
        parts.add('$level: ${list.join(', ')}');
      }
    }
    final unleveled = byLevel.remove('');
    if (unleveled != null && unleveled.isNotEmpty) {
      parts.add(unleveled.join(', '));
    }
    byLevel.forEach((level, list) {
      parts.add('$level: ${list.join(', ')}');
    });
    return parts.join('; ');
  }

  /// Joins a list of strings with proper Portuguese conjunctions.
  /// ["A"] → "A"; ["A","B"] → "A e B"; ["A","B","C"] → "A, B e C"
  static String _joinList(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items[0];
    if (items.length == 2) return '${items[0]} e ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')} e ${items.last}';
  }

  static String _escapeHtml(String s) =>
      s.replaceAll('&', '&amp;')
       .replaceAll('<', '&lt;')
       .replaceAll('>', '&gt;')
       .replaceAll('"', '&quot;');

  /// Renderiza um item de achievement do servidor.
  ///
  /// Server pode mandar com até 3 partes separadas por " ▸ ": title, role,
  /// description. Renderiza:
  ///   - 1 parte: bullet simples
  ///   - 2 partes: title (bold) + segunda parte (cinza)
  ///   - 3 partes: title (bold) — role (italic cinza) → description (texto)
  ///
  /// Exemplo:
  ///   "Modelagem Financeira ▸ Wall Street Prep ▸ 2025"
  ///   → "<b>Modelagem Financeira</b> · Wall Street Prep · <i>2025</i>"
  ///
  ///   "Diretor de Projetos na Liga de Mercado Financeiro ▸ Diretor de Projetos ▸ Gerenciei..."
  ///   → entry com title em bold + role em italic + description embaixo
  static String _renderAchievementItem(String raw) {
    final parts = raw.split('▸').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.length == 1) {
      return '<div class="ach-item"><div class="ach-title">${_escapeHtml(parts[0])}</div></div>';
    }
    if (parts.length == 2) {
      return '<div class="ach-item">'
          '<div class="ach-title">${_escapeHtml(parts[0])}</div>'
          '<div class="ach-meta">${_escapeHtml(parts[1])}</div>'
          '</div>';
    }
    // 3+ parts: title (bold), role (italic small), description (regular)
    final title = parts[0];
    final role = parts[1];
    final description = parts.sublist(2).join(' — ');
    return '<div class="ach-item">'
        '<div class="ach-title">${_escapeHtml(title)}</div>'
        '<div class="ach-role">${_escapeHtml(role)}</div>'
        '<div class="ach-desc">${_escapeHtml(description)}</div>'
        '</div>';
  }

  // ───────────────────────────────────────────────────────────────────
  //  Jake's Resume template (HTML)
  // ───────────────────────────────────────────────────────────────────
  //
  // Layout inspirado no template LaTeX clássico do Jake Gutierrez — padrão
  // mundial pra CVs de tech/CS. 1 coluna, fonte serif, header centralizado,
  // seções com underline. Densidade alta mas com whitespace bem distribuído.
  //
  // ATS compliance (testado em Greenhouse, Workday, Lever, Gupy):
  // - Texto puro em ordem linear (sem colunas, sem tabelas pra layout)
  // - Fonte Garamond/Georgia (alternativas comuns ao Computer Modern)
  // - Headers em palavras-chave padrão (Experience, Education, etc)
  // - Datas alinhadas à direita com `<span class="right">` (parsers leem
  //   linearmente — alinhamento é só visual)
  // - Sem imagens, sem ícones, sem emojis
  // - PDF gerado por Printing.convertHtml → texto selecionável
  // ───────────────────────────────────────────────────────────────────
  //  Jake's Resume — LaTeX classic (serif, two-line entries, HR dividers)
  // ───────────────────────────────────────────────────────────────────
  //
  // Identidade visual: cabeçalho serifado grande centralizado, sem caps
  // forte. Cada seção tem uma linha horizontal AO LADO do título (HR
  // após o nome da seção). Cada entrada tem 2 linhas: (a) instituição
  // bold + local à direita, (b) cargo italic + datas à direita italic.
  // Inspirado no template de Jake Gutierrez tão usado em vagas de tech.
  static String _buildJakesResumeHtml(UserProfile? user, ResumeData resume) {
    final lang = resume.language;
    final name = (resume.fullName.isNotEmpty ? resume.fullName : (user?.name ?? '')).trim();

    final contactParts = <String>[];
    if (resume.phone.isNotEmpty) contactParts.add(_escapeHtml(resume.phone));
    if (resume.email.isNotEmpty) contactParts.add(_escapeHtml(resume.email));
    if (resume.linkedin.isNotEmpty) {
      contactParts.add(_escapeHtml(resume.linkedin.replaceAll(RegExp(r'^https?://(www\.)?'), '')));
    }
    if (resume.location.isNotEmpty) contactParts.add(_escapeHtml(resume.location));
    final contactLine = contactParts.join(' | ');

    String section(String title) =>
        '<div class="sec-row"><span class="sec">${title.toUpperCase()}</span><span class="sec-hr"></span></div>';

    String entry({
      required String tl,
      required String tr,
      String bl = '',
      String br = '',
      String details = '',
      String description = '',
    }) {
      final bullets = description.trim().isEmpty
          ? ''
          : '<ul>${description.split('\n').where((l) => l.trim().isNotEmpty).map((l) {
              final clean = l.replaceAll('•', '').trim();
              return '<li>${_emphasizeMetrics(_escapeHtml(clean))}</li>';
            }).join()}</ul>';
      final det = details.trim().isEmpty
          ? ''
          : '<div class="det">${_escapeHtml(details.trim())}</div>';
      final sub = (bl.isNotEmpty || br.isNotEmpty)
          ? '<div class="row sub"><span class="i">${_escapeHtml(bl)}</span><span class="r i">${_escapeHtml(br)}</span></div>'
          : '';
      return '''
        <div class="entry">
          <div class="row top"><span class="b">${_escapeHtml(tl)}</span><span class="r">${_escapeHtml(tr)}</span></div>
          $sub
          $det
          $bullets
        </div>
      ''';
    }

    final summaryHtml = resume.summary.trim().isNotEmpty
        ? '${section(_l10n('summary', lang))}<p class="summary">${_escapeHtml(resume.summary.trim())}</p>'
        : '';

    final eduHtml = resume.education.isEmpty
        ? ''
        : section(_l10n('education', lang)) +
            resume.education.map((e) => entry(
                  tl: e.institution,
                  tr: e.location,
                  bl: e.degree,
                  br: e.period,
                  details: [
                    if (e.gpa.isNotEmpty) '${_l10n('edu_gpa', lang)}: ${e.gpa}',
                    if (e.coursework.isNotEmpty) '${_l10n('coursework', lang)}: ${e.coursework}',
                    if (e.details.isNotEmpty) e.details,
                  ].join(' · '),
                )).join();

    final expHtml = resume.experiences.isEmpty
        ? ''
        : section(_l10n('experience', lang)) +
            resume.experiences.map((e) => entry(
                  tl: e.role,
                  tr: e.period,
                  bl: e.company,
                  br: e.location,
                  description: e.description,
                )).join();

    final projItems = <String>[];
    for (final p in resume.academicProjects) {
      projItems.add(entry(
        tl: p.title,
        tr: p.period,
        bl: p.role,
        br: p.location,
        description: p.description,
      ));
    }
    for (final l in resume.leadership) {
      projItems.add(entry(
        tl: l.organization,
        tr: l.period,
        bl: l.role,
        br: l.location,
        description: l.description,
      ));
    }
    // Achievements (do servidor: projetos + certificações vindos de adapt-resume).
    // Render bonito via _renderAchievementItem (split ▸ → title/role/description).
    final achievementsItemsJ = resume.achievements
        .where((a) => a.trim().isNotEmpty)
        .map((a) => _renderAchievementItem(a.trim()))
        .join('');
    final projHtml = projItems.isEmpty
        ? (achievementsItemsJ.isEmpty
            ? ''
            : section(_l10n('projects', lang)) + achievementsItemsJ)
        : section(_l10n('projects', lang)) + projItems.join();

    final skillsParts = <String>[];
    if (resume.skills.isNotEmpty) {
      skillsParts.add('<div class="skline"><b>${_l10n('technical_skills', lang)}:</b> ${_escapeHtml(resume.skills.join(', '))}</div>');
    }
    if (resume.languages.isNotEmpty) {
      skillsParts.add('<div class="skline"><b>${_l10n('languages', lang)}:</b> ${_buildLanguagesText(resume.languages, lang)}</div>');
    }
    if (resume.toolsText.trim().isNotEmpty) {
      skillsParts.add('<div class="skline"><b>${_l10n('tools', lang)}:</b> ${_escapeHtml(resume.toolsText.trim())}</div>');
    } else if (resume.tools.isNotEmpty) {
      skillsParts.add('<div class="skline"><b>${_l10n('tools', lang)}:</b> ${_buildToolsText(resume.tools, lang)}</div>');
    }
    if (resume.courses.isNotEmpty) {
      final cs = resume.courses.map((c) => c.title).join(', ');
      skillsParts.add('<div class="skline"><b>${_l10n('courses', lang)}:</b> ${_escapeHtml(cs)}</div>');
    }
    if (resume.interests.isNotEmpty) {
      skillsParts.add('<div class="skline"><b>${_l10n('interests', lang)}:</b> ${_escapeHtml(resume.interests.join(', '))}</div>');
    }
    final skillsHtml = skillsParts.isEmpty
        ? ''
        : section(_l10n('technical_skills', lang)) + skillsParts.join();

    return '''<!DOCTYPE html>
<html lang="${lang == 'en' ? 'en' : 'pt-BR'}">
<head>
<meta charset="UTF-8">
<style>
@page { size: A4; margin: 0.5in 0.6in; }
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Latin Modern Roman', 'Computer Modern', 'Georgia', 'Cambria', serif; font-size: 11pt; color: #000; line-height: 1.28; }
.header { text-align: center; margin-bottom: 6pt; }
.name { font-size: 24pt; font-weight: normal; letter-spacing: 0.5pt; }
.contact { font-size: 10pt; margin-top: 3pt; }
.sec-row { display: flex; align-items: center; margin: 10pt 0 4pt; }
.sec { font-size: 11pt; font-weight: bold; letter-spacing: 1pt; margin-right: 6pt; white-space: nowrap; }
.sec-hr { flex: 1; height: 0; border-top: 0.6pt solid #000; }
.entry { margin-bottom: 6pt; }
.row { display: flex; justify-content: space-between; align-items: baseline; font-size: 10.5pt; }
.row.top { font-size: 11pt; }
.row.sub { margin-top: 1pt; }
.row .r { white-space: nowrap; margin-left: 10pt; }
.b { font-weight: bold; }
.i { font-style: italic; }
.summary { font-size: 10.5pt; margin: 2pt 0 0; }
.det { font-size: 10pt; margin-top: 2pt; font-style: italic; }
ul { margin: 3pt 0 0 0; padding-left: 18pt; }
li { font-size: 10.5pt; margin-bottom: 1pt; }
.skline { font-size: 10.5pt; margin-bottom: 2pt; }
.ach-item { margin-bottom: 5pt; }
.ach-title { font-size: 11pt; font-weight: bold; }
.ach-role { font-size: 10pt; font-style: italic; margin-top: 1pt; }
.ach-meta { font-size: 10pt; color: #444; margin-top: 1pt; }
.ach-desc { font-size: 10.5pt; margin-top: 2pt; }
</style>
</head>
<body>
  <div class="header">
    <div class="name">${_escapeHtml(name)}</div>
    <div class="contact">$contactLine</div>
  </div>
  $summaryHtml
  $eduHtml
  $expHtml
  $projHtml
  $skillsHtml
</body>
</html>''';
  }

  // ───────────────────────────────────────────────────────────────────
  //  Forte Foundation template (HTML) — MBA Banking/Consulting standard
  // ───────────────────────────────────────────────────────────────────
  //
  // Padrão Forte Foundation MBA Career Guide — usado em recruiting de
  // Goldman Sachs, JP Morgan, Morgan Stanley, McKinsey, BCG, Bain, Itaú BBA,
  // Stone, Pactual. Conservador, datas alinhadas à direita, GPA prominente,
  // 1 página obrigatória.
  //
  // ATS compliance: 1 coluna, sem ícones, Times New Roman/Garamond, headers
  // institucionais ("EDUCATION", "PROFESSIONAL EXPERIENCE").
  //
  // Order: Education (primeiro, padrão MBA) → Experience → Leadership/Activities
  // → Skills/Additional Information
  // ───────────────────────────────────────────────────────────────────
  //  Forte Foundation — MBA banking/consulting (CAPS, double-border, formal)
  // ───────────────────────────────────────────────────────────────────
  //
  // Identidade visual: nome em CAIXA ALTA centralizado com tracking
  // exagerado (espaço entre letras), DUAS linhas horizontais abaixo
  // do cabeçalho (estilo emblema). Seções com borda superior + inferior
  // (look "double-line"). Hyphens (–) nos bullets. Education primeiro
  // com GPA prominente. Pensado pra Goldman, McKinsey, BCG, MBA.
  static String _buildForteFoundationHtml(UserProfile? user, ResumeData resume) {
    final lang = resume.language;
    final name = (resume.fullName.isNotEmpty ? resume.fullName : (user?.name ?? '')).trim().toUpperCase();

    final contactParts = <String>[];
    if (resume.location.isNotEmpty) contactParts.add(_escapeHtml(resume.location));
    if (resume.phone.isNotEmpty) contactParts.add(_escapeHtml(resume.phone));
    if (resume.email.isNotEmpty) contactParts.add(_escapeHtml(resume.email));
    if (resume.linkedin.isNotEmpty) {
      contactParts.add(_escapeHtml(resume.linkedin.replaceAll(RegExp(r'^https?://(www\.)?'), '')));
    }
    final contactLine = contactParts.join(' • ');

    String section(String title) =>
        '<div class="sec">${title.toUpperCase()}</div>';

    String bulletList(String desc) {
      final lines = desc.split('\n').map((l) => l.replaceAll('•', '').trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) return '';
      return '<ul>${lines.map((l) => '<li>${_emphasizeMetrics(_escapeHtml(l))}</li>').join()}</ul>';
    }

    String entryEdu({
      required String institution,
      required String location,
      required String degree,
      required String period,
      String gpa = '',
      String honors = '',
      String coursework = '',
      String details = '',
    }) {
      final extras = <String>[];
      if (gpa.isNotEmpty) extras.add('${_l10n('edu_gpa', lang)}: $gpa');
      if (honors.isNotEmpty) extras.add(honors);
      final extrasLine = extras.isEmpty
          ? ''
          : '<div class="extras">${_escapeHtml(extras.join('  |  '))}</div>';
      final cw = coursework.isEmpty
          ? ''
          : '<div class="course"><i>${_l10n('edu_coursework', lang)}:</i> ${_escapeHtml(coursework)}</div>';
      final det = details.isEmpty
          ? ''
          : '<div class="det">${_escapeHtml(details)}</div>';
      return '''
        <div class="entry">
          <table class="entry-row"><tr>
            <td class="left bold">${_escapeHtml(institution)}</td>
            <td class="right bold">${_escapeHtml(location)}</td>
          </tr></table>
          <table class="entry-row"><tr>
            <td class="left italic">${_escapeHtml(degree)}</td>
            <td class="right italic">${_escapeHtml(period)}</td>
          </tr></table>
          $extrasLine
          $cw
          $det
        </div>
      ''';
    }

    String entryExp({
      required String company,
      required String location,
      required String role,
      required String period,
      required String description,
    }) {
      return '''
        <div class="entry">
          <table class="entry-row"><tr>
            <td class="left bold">${_escapeHtml(company)}</td>
            <td class="right bold">${_escapeHtml(location)}</td>
          </tr></table>
          <table class="entry-row"><tr>
            <td class="left italic">${_escapeHtml(role)}</td>
            <td class="right italic">${_escapeHtml(period)}</td>
          </tr></table>
          ${bulletList(description)}
        </div>
      ''';
    }

    final eduHtml = resume.education.isEmpty
        ? ''
        : section(_l10n('education', lang)) +
            resume.education.map((e) => entryEdu(
                  institution: e.institution,
                  location: e.location,
                  degree: e.degree,
                  period: e.period,
                  gpa: e.gpa,
                  honors: e.honors,
                  coursework: e.coursework,
                  details: e.details,
                )).join();

    final expHtml = resume.experiences.isEmpty
        ? ''
        : section(_l10n('experience', lang)) +
            resume.experiences.map((e) => entryExp(
                  company: e.company,
                  location: e.location,
                  role: e.role,
                  period: e.period,
                  description: e.description,
                )).join();

    final actItems = <String>[];
    for (final p in resume.academicProjects) {
      actItems.add(entryExp(
        company: p.title,
        location: p.location,
        role: p.role,
        period: p.period,
        description: p.description,
      ));
    }
    for (final l in resume.leadership) {
      actItems.add(entryExp(
        company: l.organization,
        location: l.location,
        role: l.role,
        period: l.period,
        description: l.description,
      ));
    }
    // Achievements (do servidor: projetos + certificações vindos de adapt-resume).
    // Render bonito via _renderAchievementItem.
    final achievementsItemsF = resume.achievements
        .where((a) => a.trim().isNotEmpty)
        .map((a) => _renderAchievementItem(a.trim()))
        .join('');
    final actHtml = actItems.isEmpty
        ? (achievementsItemsF.isEmpty
            ? ''
            : section(_l10n('leadership', lang)) + achievementsItemsF)
        : section(_l10n('leadership', lang)) + actItems.join();

    final addParts = <String>[];
    if (resume.skills.isNotEmpty) {
      addParts.add('<div class="add-row"><b>${_l10n('technical_skills', lang)}:</b> ${_escapeHtml(resume.skills.join(', '))}.</div>');
    }
    if (resume.languages.isNotEmpty) {
      addParts.add('<div class="add-row"><b>${_l10n('languages', lang)}:</b> ${_buildLanguagesText(resume.languages, lang)}.</div>');
    }
    if (resume.courses.isNotEmpty) {
      final cs = resume.courses.map((c) => c.title).join(', ');
      addParts.add('<div class="add-row"><b>${_l10n('courses', lang)}:</b> ${_escapeHtml(cs)}.</div>');
    }
    if (resume.interests.isNotEmpty) {
      addParts.add('<div class="add-row"><b>${_l10n('interests', lang)}:</b> ${_escapeHtml(resume.interests.join(', '))}.</div>');
    }
    final addTitle = lang == 'en' ? 'ADDITIONAL INFORMATION' : 'INFORMAÇÕES ADICIONAIS';
    final addHtml = addParts.isEmpty ? '' : '<div class="sec">$addTitle</div>${addParts.join()}';

    return '''<!DOCTYPE html>
<html lang="${lang == 'en' ? 'en' : 'pt-BR'}">
<head>
<meta charset="UTF-8">
<style>
@page { size: A4; margin: 0.6in 0.65in; }
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Times New Roman', 'Times', serif; font-size: 10.5pt; color: #000; line-height: 1.32; }
.header { text-align: center; margin-bottom: 10pt; padding: 8pt 0; border-top: 2pt solid #000; border-bottom: 0.5pt solid #000; }
.name { font-size: 19pt; font-weight: bold; letter-spacing: 6pt; text-transform: uppercase; }
.contact { font-size: 9.5pt; margin-top: 5pt; letter-spacing: 0.5pt; }
.sec { font-size: 11pt; font-weight: bold; letter-spacing: 2pt; text-transform: uppercase; text-align: center; margin: 12pt 0 5pt; padding: 2pt 0; border-top: 0.4pt solid #000; border-bottom: 0.4pt solid #000; }
.entry { margin-bottom: 7pt; }
.entry-row { width: 100%; border-collapse: collapse; }
.entry-row td { vertical-align: baseline; padding: 0; font-size: 10.5pt; }
.left { text-align: left; }
.right { text-align: right; white-space: nowrap; }
.bold { font-weight: bold; }
.italic { font-style: italic; }
.extras { font-size: 9.5pt; margin-top: 2pt; }
.course { font-size: 10pt; margin-top: 2pt; }
.det { font-size: 10pt; margin-top: 2pt; }
.ach-item { margin-bottom: 6pt; }
.ach-title { font-size: 10.5pt; font-weight: bold; }
.ach-role { font-size: 10pt; font-style: italic; margin-top: 1pt; }
.ach-meta { font-size: 10pt; color: #555; margin-top: 1pt; }
.ach-desc { font-size: 10pt; margin-top: 2pt; }
ul { margin: 3pt 0 0 0; padding: 0; list-style: none; }
li { font-size: 10.5pt; margin-bottom: 1pt; padding-left: 12pt; text-indent: -10pt; }
li::before { content: "– "; font-weight: bold; }
.add-row { font-size: 10.5pt; margin-bottom: 2pt; }
</style>
</head>
<body>
  <div class="header">
    <div class="name">${_escapeHtml(name)}</div>
    <div class="contact">$contactLine</div>
  </div>
  $eduHtml
  $expHtml
  $actHtml
  $addHtml
</body>
</html>''';
  }

  // ───────────────────────────────────────────────────────────────────
  //  One-Page Compact template (HTML) — student first-job standard
  // ───────────────────────────────────────────────────────────────────
  //
  // Inspirado em templates de career centers universitários (Insper, FGV,
  // Link School). Compacto pra caber tudo em 1 página, mesmo com pouca
  // experiência. Visual moderno mas sem firulas.
  //
  // ATS compliance: 1 coluna, Helvetica/Arial (sans-serif neutro), headers
  // padrão, datas em formato MM/YYYY-friendly.
  //
  // Order: Header → Education → Experience → Projects → Skills (priority
  // pra estudante que tem mais formação que experiência).
  // ───────────────────────────────────────────────────────────────────
  //  One-Page Compact — modern student (sans-serif, indigo, single-line entries)
  // ───────────────────────────────────────────────────────────────────
  //
  // Identidade visual: nome ALINHADO À ESQUERDA grande em sans-serif
  // bold, contato em linha abaixo. Seções com cor INDIGO (#4F46E5),
  // sem bordas, só destaque por cor. Cada entrada é uma LINHA SÓ
  // (role · company · period · location inline) — mais compacto que
  // os outros. Bullets com chevron (›). Pensado pra trainees/estágios.
  static String _buildOnePageHtml(UserProfile? user, ResumeData resume) {
    final lang = resume.language;
    final name = (resume.fullName.isNotEmpty ? resume.fullName : (user?.name ?? '')).trim();

    final contactParts = <String>[];
    if (resume.email.isNotEmpty) contactParts.add(_escapeHtml(resume.email));
    if (resume.phone.isNotEmpty) contactParts.add(_escapeHtml(resume.phone));
    if (resume.linkedin.isNotEmpty) {
      contactParts.add(_escapeHtml(resume.linkedin.replaceAll(RegExp(r'^https?://(www\.)?'), '')));
    }
    if (resume.location.isNotEmpty) contactParts.add(_escapeHtml(resume.location));
    final contactLine = contactParts.join('  ·  ');

    String section(String title) => '<div class="sec">${title.toLowerCase()}</div>';

    String bulletList(String desc) {
      final lines = desc.split('\n').map((l) => l.replaceAll('•', '').trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) return '';
      return '<ul>${lines.map((l) => '<li>${_emphasizeMetrics(_escapeHtml(l))}</li>').join()}</ul>';
    }

    String singleLineEntry({
      required String primary, // bold (role / institution / title)
      required String secondary, // company / degree / org
      String tertiary = '', // period
      String location = '',
      String description = '',
      String details = '',
    }) {
      final inlineParts = <String>[];
      if (secondary.isNotEmpty) inlineParts.add('<span class="sec-text">${_escapeHtml(secondary)}</span>');
      if (tertiary.isNotEmpty) inlineParts.add('<span class="meta">${_escapeHtml(tertiary)}</span>');
      if (location.isNotEmpty) inlineParts.add('<span class="meta">${_escapeHtml(location)}</span>');
      final inlineLine = inlineParts.join('  ·  ');
      final det = details.isEmpty ? '' : '<div class="det">${_escapeHtml(details)}</div>';
      return '''
        <div class="entry">
          <div class="line"><span class="primary">${_escapeHtml(primary)}</span>${inlineLine.isNotEmpty ? '<span class="dot"> · </span>' : ''}$inlineLine</div>
          $det
          ${bulletList(description)}
        </div>
      ''';
    }

    final summaryHtml = resume.summary.trim().isNotEmpty
        ? '${section(_l10n('summary', lang))}<p class="summary">${_escapeHtml(resume.summary.trim())}</p>'
        : '';

    final eduHtml = resume.education.isEmpty
        ? ''
        : section(_l10n('education', lang)) +
            resume.education.map((e) => singleLineEntry(
                  primary: e.degree,
                  secondary: e.institution,
                  tertiary: e.period,
                  location: e.location,
                  details: [
                    if (e.gpa.isNotEmpty) '${_l10n('edu_gpa', lang)}: ${e.gpa}',
                    if (e.coursework.isNotEmpty) e.coursework,
                    if (e.details.isNotEmpty) e.details,
                  ].join(' · '),
                )).join();

    final expHtml = resume.experiences.isEmpty
        ? ''
        : section(_l10n('experience', lang)) +
            resume.experiences.map((e) => singleLineEntry(
                  primary: e.role,
                  secondary: e.company,
                  tertiary: e.period,
                  location: e.location,
                  description: e.description,
                )).join();

    final projItems = <String>[];
    for (final p in resume.academicProjects) {
      projItems.add(singleLineEntry(
        primary: p.title,
        secondary: p.role,
        tertiary: p.period,
        description: p.description,
      ));
    }
    for (final l in resume.leadership) {
      projItems.add(singleLineEntry(
        primary: l.organization,
        secondary: l.role,
        tertiary: l.period,
        description: l.description,
      ));
    }
    // Achievements (do servidor: projetos + certificações vindos de adapt-resume).
    // Render bonito via _renderAchievementItem.
    final achievementsItemsO = resume.achievements
        .where((a) => a.trim().isNotEmpty)
        .map((a) => _renderAchievementItem(a.trim()))
        .join('');
    final projHtml = projItems.isEmpty
        ? (achievementsItemsO.isEmpty
            ? ''
            : section(_l10n('projects', lang)) + achievementsItemsO)
        : section(_l10n('projects', lang)) + projItems.join();

    // Skills as pill-grouped chips per category
    final skillBlocks = <String>[];
    if (resume.skills.isNotEmpty) {
      final pills = resume.skills.map((s) => '<span class="pill">${_escapeHtml(s)}</span>').join();
      skillBlocks.add('<div class="skblock"><span class="sklabel">${_l10n('technical_skills', lang)}</span><div class="skpills">$pills</div></div>');
    }
    if (resume.languages.isNotEmpty) {
      final pills = resume.languages.map((l) => '<span class="pill">${_escapeHtml(l.language)} <span class="pill-meta">${_escapeHtml(_translateLevel(l.level, lang))}</span></span>').join();
      skillBlocks.add('<div class="skblock"><span class="sklabel">${_l10n('languages', lang)}</span><div class="skpills">$pills</div></div>');
    }
    if (resume.courses.isNotEmpty) {
      final pills = resume.courses.map((c) => '<span class="pill">${_escapeHtml(c.title)}</span>').join();
      skillBlocks.add('<div class="skblock"><span class="sklabel">${_l10n('courses', lang)}</span><div class="skpills">$pills</div></div>');
    }
    if (resume.interests.isNotEmpty) {
      final pills = resume.interests.map((i) => '<span class="pill">${_escapeHtml(i)}</span>').join();
      skillBlocks.add('<div class="skblock"><span class="sklabel">${_l10n('interests', lang)}</span><div class="skpills">$pills</div></div>');
    }
    final skillsHtml = skillBlocks.isEmpty
        ? ''
        : section(_l10n('technical_skills', lang)) + skillBlocks.join();

    return '''<!DOCTYPE html>
<html lang="${lang == 'en' ? 'en' : 'pt-BR'}">
<head>
<meta charset="UTF-8">
<style>
@page { size: A4; margin: 0.5in 0.55in; }
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Helvetica', 'Arial', 'Segoe UI', sans-serif; font-size: 10pt; color: #1f2937; line-height: 1.4; }
.header { text-align: left; margin-bottom: 8pt; padding-bottom: 6pt; border-bottom: 2pt solid #4F46E5; }
.name { font-size: 24pt; font-weight: 800; color: #0f172a; letter-spacing: -0.5pt; }
.contact { font-size: 9.5pt; color: #64748b; margin-top: 4pt; }
.sec { font-size: 11pt; font-weight: 800; color: #4F46E5; text-transform: lowercase; margin: 10pt 0 4pt; letter-spacing: -0.2pt; }
.entry { margin-bottom: 5pt; }
.line { font-size: 10.5pt; }
.primary { font-weight: 700; color: #0f172a; }
.sec-text { color: #334155; font-weight: 500; }
.meta { color: #64748b; font-size: 9.5pt; }
.dot { color: #cbd5e1; }
.summary { font-size: 10pt; color: #334155; margin: 2pt 0 0; }
.det { font-size: 9.5pt; color: #64748b; margin-top: 1pt; font-style: italic; }
ul { margin: 2pt 0 0 0; padding: 0; list-style: none; }
li { font-size: 10pt; color: #334155; margin-bottom: 1pt; padding-left: 12pt; text-indent: -10pt; }
li::before { content: "› "; color: #4F46E5; font-weight: bold; }
.ach-item { margin-bottom: 5pt; }
.ach-title { font-size: 10.5pt; font-weight: 700; color: #0f172a; }
.ach-role { font-size: 9.5pt; font-style: italic; color: #64748b; margin-top: 1pt; }
.ach-meta { font-size: 9.5pt; color: #64748b; margin-top: 1pt; }
.ach-desc { font-size: 10pt; color: #334155; margin-top: 1pt; }
.skblock { margin-bottom: 4pt; }
.sklabel { display: inline-block; font-size: 9pt; font-weight: 700; color: #64748b; text-transform: uppercase; letter-spacing: 0.8pt; margin-right: 6pt; }
.skpills { display: inline; }
.pill { display: inline-block; background: #EEF2FF; color: #3730A3; padding: 1pt 6pt; border-radius: 8pt; margin: 1pt 2pt 1pt 0; font-size: 9pt; }
.pill-meta { color: #6366F1; font-size: 8.5pt; }
</style>
</head>
<body>
  <div class="header">
    <div class="name">${_escapeHtml(name)}</div>
    <div class="contact">$contactLine</div>
  </div>
  $summaryHtml
  $eduHtml
  $expHtml
  $projHtml
  $skillsHtml
</body>
</html>''';
  }

  /// Builds the optional address line (above the contact line) when the user
  /// provided a full street address. Falls back to empty string otherwise —
  /// the city stays on the contact line.
  static String _buildHarvardAddressLine(ResumeData resume) {
    final addr = resume.address.trim();
    if (addr.isEmpty) return '';
    // Combine "Rua X, 123 – Bairro" with city/state when both are available
    final pieces = <String>[addr];
    if (resume.location.trim().isNotEmpty) pieces.add(resume.location.trim());
    return '<div class="address">${_escapeHtml(pieces.join(' – '))}</div>';
  }

  static String _buildHarvardContactString(ResumeData resume) {
    final parts = <String>[];
    // If address line is present, the city already appears there — skip it
    // here to avoid duplication.
    if (resume.address.trim().isEmpty && resume.location.trim().isNotEmpty) {
      parts.add(resume.location);
    }
    if (resume.phone.isNotEmpty) parts.add('${_l10n('mobile', resume.language)}: ${resume.phone}');
    if (resume.email.isNotEmpty) parts.add(resume.email);
    if (resume.linkedin.isNotEmpty) {
      parts.add(resume.linkedin
          .replaceAll('https://', '')
          .replaceAll('http://', '')
          .replaceAll('www.', ''));
    }
    return parts.join(' | ');
  }
}
