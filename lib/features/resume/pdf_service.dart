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
              p.location.isNotEmpty ? p.location : resume.location,
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
              l.location.isNotEmpty ? l.location : resume.location,
              l.role,
              l.period,
              l.description,
              relevantWork: l.relevantWork,
              relevantLabel: _l10n('relevant_work', lang),
            ))
        .join('');
    final activitiesHtml = (resume.academicProjects.isNotEmpty || resume.leadership.isNotEmpty)
        ? '<div class="sec">${_l10n('leadership', lang)}</div>$projectItems$leadItems'
        : '';

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
  </style>
</head>
<body>
  <div class="header">
    <div class="name">${(user?.name ?? "Seu Nome").toUpperCase()}</div>
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
    final location = edu.location.isNotEmpty ? edu.location : resume.location;
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
    final location = exp.location.isNotEmpty ? exp.location : resume.location;
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
  static String _buildJakesResumeHtml(UserProfile? user, ResumeData resume) {
    final lang = resume.language;
    final name = (resume.fullName.isNotEmpty ? resume.fullName : (user?.name ?? '')).trim();

    // Contact line — ATS-friendly: separado por `|` pra ser facilmente parseado.
    final contactParts = <String>[];
    if (resume.phone.isNotEmpty) contactParts.add(_escapeHtml(resume.phone));
    if (resume.email.isNotEmpty) contactParts.add(_escapeHtml(resume.email));
    if (resume.linkedin.isNotEmpty) contactParts.add(_escapeHtml(resume.linkedin));
    if (resume.location.isNotEmpty) contactParts.add(_escapeHtml(resume.location));
    final contactLine = contactParts.join(' | ');

    // Summary (optional)
    final summaryHtml = resume.summary.trim().isNotEmpty
        ? '<h2>${_l10n('summary', lang)}</h2><p class="summary">${_escapeHtml(resume.summary.trim())}</p>'
        : '';

    // Education
    final eduHtml = resume.education.isEmpty
        ? ''
        : '<h2>${_l10n('education', lang)}</h2>' +
            resume.education.map((e) {
              final loc = e.location.isNotEmpty ? e.location : resume.location;
              return '''
              <div class="entry">
                <div class="entry-line"><span class="bold">${_escapeHtml(e.institution)}</span><span class="right">${_escapeHtml(loc)}</span></div>
                <div class="entry-line"><span class="italic">${_escapeHtml(e.degree)}</span><span class="right italic">${_escapeHtml(e.period)}</span></div>
                ${e.coursework.isNotEmpty ? '<div class="sub"><span class="bold">${_l10n('coursework', lang)}:</span> ${_escapeHtml(e.coursework)}</div>' : ''}
                ${e.details.isNotEmpty ? '<div class="sub">${_escapeHtml(e.details)}</div>' : ''}
              </div>
              ''';
            }).join('');

    // Experience
    final expHtml = resume.experiences.isEmpty
        ? ''
        : '<h2>${_l10n('experience', lang)}</h2>' +
            resume.experiences.map((e) {
              final loc = e.location.isNotEmpty ? e.location : resume.location;
              final bullets = e.description
                  .split('\n')
                  .map((b) => b.trim())
                  .where((b) => b.isNotEmpty)
                  .map((b) => '<li>${_escapeHtml(b)}</li>')
                  .join('');
              return '''
              <div class="entry">
                <div class="entry-line"><span class="bold">${_escapeHtml(e.role)}</span><span class="right italic">${_escapeHtml(e.period)}</span></div>
                <div class="entry-line"><span class="italic">${_escapeHtml(e.company)}</span><span class="right">${_escapeHtml(loc)}</span></div>
                ${bullets.isNotEmpty ? '<ul>$bullets</ul>' : ''}
              </div>
              ''';
            }).join('');

    // Projects / Leadership (concatenados sob "Projects")
    final projItems = <String>[];
    for (final p in resume.academicProjects) {
      final bullets = p.description
          .split('\n')
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .map((b) => '<li>${_escapeHtml(b)}</li>')
          .join('');
      projItems.add('''
        <div class="entry">
          <div class="entry-line"><span class="bold">${_escapeHtml(p.title)}</span>${p.role.isNotEmpty ? ' | <span class="italic">${_escapeHtml(p.role)}</span>' : ''}<span class="right italic">${_escapeHtml(p.period)}</span></div>
          ${bullets.isNotEmpty ? '<ul>$bullets</ul>' : ''}
        </div>
        ''');
    }
    for (final l in resume.leadership) {
      final bullets = l.description
          .split('\n')
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .map((b) => '<li>${_escapeHtml(b)}</li>')
          .join('');
      projItems.add('''
        <div class="entry">
          <div class="entry-line"><span class="bold">${_escapeHtml(l.organization)}</span>${l.role.isNotEmpty ? ' | <span class="italic">${_escapeHtml(l.role)}</span>' : ''}<span class="right italic">${_escapeHtml(l.period)}</span></div>
          ${bullets.isNotEmpty ? '<ul>$bullets</ul>' : ''}
        </div>
        ''');
    }
    final projHtml = projItems.isEmpty
        ? ''
        : '<h2>${_l10n('projects', lang)}</h2>${projItems.join('')}';

    // Technical Skills
    final skillsParts = <String>[];
    if (resume.skills.isNotEmpty) {
      skillsParts.add('<span class="bold">${_l10n('technical_skills', lang)}:</span> ${_escapeHtml(resume.skills.join(', '))}');
    }
    if (resume.languages.isNotEmpty) {
      final langs = resume.languages.map((l) => '${l.language} (${l.level})').join(', ');
      skillsParts.add('<span class="bold">${_l10n('languages', lang)}:</span> ${_escapeHtml(langs)}');
    }
    if (resume.courses.isNotEmpty) {
      final courses = resume.courses.map((c) => c.title).join(', ');
      skillsParts.add('<span class="bold">${_l10n('courses', lang)}:</span> ${_escapeHtml(courses)}');
    }
    if (resume.interests.isNotEmpty) {
      skillsParts.add('<span class="bold">${_l10n('interests', lang)}:</span> ${_escapeHtml(resume.interests.join(', '))}');
    }
    final skillsHtml = skillsParts.isEmpty
        ? ''
        : '<h2>${_l10n('technical_skills', lang)}</h2>' +
            skillsParts.map((p) => '<div class="skill-line">$p</div>').join('');

    return '''
<!DOCTYPE html>
<html lang="${lang == 'en' ? 'en' : 'pt-BR'}">
<head>
<meta charset="UTF-8" />
<title>${_escapeHtml(name)}</title>
<style>
  @page { size: A4; margin: 0.5in 0.7in; }
  body {
    font-family: "Garamond", "EB Garamond", "Georgia", serif;
    font-size: 10.5pt;
    color: #000;
    margin: 0;
    line-height: 1.25;
  }
  .header { text-align: center; margin-bottom: 8px; }
  .header h1 {
    font-size: 22pt;
    font-weight: normal;
    margin: 0 0 4px 0;
    letter-spacing: 0.5px;
  }
  .header .contact {
    font-size: 10pt;
    color: #000;
  }
  h2 {
    text-transform: uppercase;
    font-size: 11pt;
    margin: 10px 0 3px 0;
    padding-bottom: 1px;
    border-bottom: 0.75pt solid #000;
    letter-spacing: 0.5px;
  }
  .entry { margin-bottom: 6px; }
  .entry-line {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
  }
  .right { float: none; }
  .bold { font-weight: bold; }
  .italic { font-style: italic; }
  .sub {
    font-size: 10pt;
    margin-top: 1px;
  }
  ul {
    margin: 3px 0 4px 0;
    padding-left: 22px;
  }
  li {
    margin-bottom: 2px;
    font-size: 10.5pt;
  }
  .summary {
    margin: 4px 0;
  }
  .skill-line { margin: 1px 0; }
</style>
</head>
<body>
  <div class="header">
    <h1>${_escapeHtml(name)}</h1>
    <div class="contact">$contactLine</div>
  </div>
  $summaryHtml
  $eduHtml
  $expHtml
  $projHtml
  $skillsHtml
</body>
</html>
''';
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
  static String _buildForteFoundationHtml(UserProfile? user, ResumeData resume) {
    final lang = resume.language;
    final name = (resume.fullName.isNotEmpty ? resume.fullName : (user?.name ?? '')).trim();

    final contactParts = <String>[];
    if (resume.location.isNotEmpty) contactParts.add(_escapeHtml(resume.location));
    if (resume.phone.isNotEmpty) contactParts.add(_escapeHtml(resume.phone));
    if (resume.email.isNotEmpty) contactParts.add(_escapeHtml(resume.email));
    if (resume.linkedin.isNotEmpty) contactParts.add(_escapeHtml(resume.linkedin));
    final contactLine = contactParts.join(' • ');

    // Education — prominent placement (top), with GPA if available
    final eduHtml = resume.education.isEmpty
        ? ''
        : '<h2>${_l10n('education', lang)}</h2>' +
            resume.education.map((e) {
              final loc = e.location.isNotEmpty ? e.location : resume.location;
              final extras = <String>[];
              if (e.gpa.isNotEmpty) extras.add('${_l10n('edu_gpa', lang)}: ${_escapeHtml(e.gpa)}');
              if (e.honors.isNotEmpty) extras.add(_escapeHtml(e.honors));
              if (e.repRole.isNotEmpty) extras.add(_escapeHtml(e.repRole));
              final extrasLine = extras.isNotEmpty ? '<div class="extras">${extras.join(' &nbsp;|&nbsp; ')}</div>' : '';
              final coursework = e.coursework.isNotEmpty
                  ? '<div class="coursework"><span class="italic">${_l10n('edu_coursework', lang)}:</span> ${_escapeHtml(e.coursework)}</div>'
                  : '';
              return '''
              <div class="entry">
                <div class="entry-head">
                  <span class="bold">${_escapeHtml(e.institution)}</span>
                  <span class="right bold">${_escapeHtml(loc)}</span>
                </div>
                <div class="entry-sub">
                  <span class="italic">${_escapeHtml(e.degree)}</span>
                  <span class="right italic">${_escapeHtml(e.period)}</span>
                </div>
                $extrasLine
                $coursework
              </div>
              ''';
            }).join('');

    final expHtml = resume.experiences.isEmpty
        ? ''
        : '<h2>${_l10n('experience', lang)}</h2>' +
            resume.experiences.map((e) {
              final loc = e.location.isNotEmpty ? e.location : resume.location;
              final bullets = e.description
                  .split('\n')
                  .map((b) => b.trim())
                  .where((b) => b.isNotEmpty)
                  .map((b) => '<li>${_escapeHtml(b)}</li>')
                  .join('');
              return '''
              <div class="entry">
                <div class="entry-head">
                  <span class="bold">${_escapeHtml(e.company)}</span>
                  <span class="right bold">${_escapeHtml(loc)}</span>
                </div>
                <div class="entry-sub">
                  <span class="italic">${_escapeHtml(e.role)}</span>
                  <span class="right italic">${_escapeHtml(e.period)}</span>
                </div>
                ${bullets.isNotEmpty ? '<ul>$bullets</ul>' : ''}
              </div>
              ''';
            }).join('');

    // Leadership / Activities
    final actItems = <String>[];
    for (final l in resume.leadership) {
      final loc = l.location.isNotEmpty ? l.location : resume.location;
      final bullets = l.description
          .split('\n')
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .map((b) => '<li>${_escapeHtml(b)}</li>')
          .join('');
      actItems.add('''
        <div class="entry">
          <div class="entry-head">
            <span class="bold">${_escapeHtml(l.organization)}</span>
            <span class="right bold">${_escapeHtml(loc)}</span>
          </div>
          <div class="entry-sub">
            <span class="italic">${_escapeHtml(l.role)}</span>
            <span class="right italic">${_escapeHtml(l.period)}</span>
          </div>
          ${bullets.isNotEmpty ? '<ul>$bullets</ul>' : ''}
        </div>
        ''');
    }
    for (final p in resume.academicProjects) {
      final bullets = p.description
          .split('\n')
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .map((b) => '<li>${_escapeHtml(b)}</li>')
          .join('');
      actItems.add('''
        <div class="entry">
          <div class="entry-head">
            <span class="bold">${_escapeHtml(p.title)}</span>
            <span class="right bold">${_escapeHtml(p.location.isNotEmpty ? p.location : resume.location)}</span>
          </div>
          <div class="entry-sub">
            <span class="italic">${_escapeHtml(p.role)}</span>
            <span class="right italic">${_escapeHtml(p.period)}</span>
          </div>
          ${bullets.isNotEmpty ? '<ul>$bullets</ul>' : ''}
        </div>
        ''');
    }
    final actHtml = actItems.isEmpty
        ? ''
        : '<h2>${_l10n('leadership', lang)}</h2>${actItems.join('')}';

    // Additional Information (skills + languages + interests) — one consolidated section
    final addParts = <String>[];
    if (resume.skills.isNotEmpty) {
      addParts.add('<div><span class="bold">${_l10n('technical_skills', lang)}:</span> ${_escapeHtml(resume.skills.join(', '))}</div>');
    }
    if (resume.languages.isNotEmpty) {
      final langs = resume.languages.map((l) => '${_escapeHtml(l.language)} (${_escapeHtml(l.level)})').join(', ');
      addParts.add('<div><span class="bold">${_l10n('languages', lang)}:</span> $langs</div>');
    }
    if (resume.courses.isNotEmpty) {
      final courses = resume.courses
          .map((c) => '${_escapeHtml(c.title)}${c.institution.isNotEmpty ? ' (${_escapeHtml(c.institution)})' : ''}')
          .join(', ');
      addParts.add('<div><span class="bold">${_l10n('courses', lang)}:</span> $courses</div>');
    }
    if (resume.interests.isNotEmpty) {
      addParts.add('<div><span class="bold">${_l10n('interests', lang)}:</span> ${_escapeHtml(resume.interests.join(', '))}</div>');
    }
    final addHtml = addParts.isEmpty
        ? ''
        : '<h2>${lang == 'en' ? 'ADDITIONAL INFORMATION' : 'INFORMAÇÕES ADICIONAIS'}</h2><div class="add-block">${addParts.join('')}</div>';

    return '''
<!DOCTYPE html>
<html lang="${lang == 'en' ? 'en' : 'pt-BR'}">
<head>
<meta charset="UTF-8" />
<title>${_escapeHtml(name)}</title>
<style>
  @page { size: A4; margin: 0.6in 0.7in; }
  body {
    font-family: "Times New Roman", "Times", "Georgia", serif;
    font-size: 10.5pt;
    color: #000;
    margin: 0;
    line-height: 1.3;
  }
  .header {
    text-align: center;
    border-bottom: 1.2pt solid #000;
    padding-bottom: 6px;
    margin-bottom: 8px;
  }
  .header h1 {
    font-size: 18pt;
    font-weight: bold;
    text-transform: uppercase;
    margin: 0 0 3px 0;
    letter-spacing: 2.5px;
  }
  .header .contact { font-size: 10pt; }
  h2 {
    text-transform: uppercase;
    font-size: 11pt;
    font-weight: bold;
    margin: 12px 0 4px 0;
    padding-bottom: 1px;
    border-bottom: 0.5pt solid #000;
    letter-spacing: 1.2px;
  }
  .entry { margin-bottom: 8px; }
  .entry-head, .entry-sub {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
  }
  .bold { font-weight: bold; }
  .italic { font-style: italic; }
  .extras, .coursework {
    font-size: 9.5pt;
    margin-top: 2px;
  }
  ul {
    margin: 3px 0 4px 0;
    padding-left: 22px;
  }
  li {
    margin-bottom: 2px;
    font-size: 10.5pt;
  }
  .add-block div { margin: 1px 0; font-size: 10pt; }
</style>
</head>
<body>
  <div class="header">
    <h1>${_escapeHtml(name)}</h1>
    <div class="contact">$contactLine</div>
  </div>
  $eduHtml
  $expHtml
  $actHtml
  $addHtml
</body>
</html>
''';
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
  static String _buildOnePageHtml(UserProfile? user, ResumeData resume) {
    final lang = resume.language;
    final name = (resume.fullName.isNotEmpty ? resume.fullName : (user?.name ?? '')).trim();

    final contactParts = <String>[];
    if (resume.email.isNotEmpty) contactParts.add(_escapeHtml(resume.email));
    if (resume.phone.isNotEmpty) contactParts.add(_escapeHtml(resume.phone));
    if (resume.linkedin.isNotEmpty) contactParts.add(_escapeHtml(resume.linkedin));
    if (resume.location.isNotEmpty) contactParts.add(_escapeHtml(resume.location));
    final contactLine = contactParts.join(' · ');

    final summaryHtml = resume.summary.trim().isNotEmpty
        ? '<p class="summary">${_escapeHtml(resume.summary.trim())}</p>'
        : '';

    final eduHtml = resume.education.isEmpty
        ? ''
        : '<h2>${_l10n('education', lang)}</h2>' +
            resume.education.map((e) {
              final loc = e.location.isNotEmpty ? e.location : resume.location;
              return '''
              <div class="row">
                <div class="row-main">
                  <span class="bold">${_escapeHtml(e.degree)}</span> · ${_escapeHtml(e.institution)}
                  ${e.gpa.isNotEmpty ? '· <span class="dim">${_l10n('edu_gpa', lang)} ${_escapeHtml(e.gpa)}</span>' : ''}
                </div>
                <div class="row-meta">${_escapeHtml(e.period)} · ${_escapeHtml(loc)}</div>
                ${e.coursework.isNotEmpty ? '<div class="row-sub"><span class="dim">${_l10n('edu_coursework', lang)}:</span> ${_escapeHtml(e.coursework)}</div>' : ''}
                ${e.details.isNotEmpty ? '<div class="row-sub">${_escapeHtml(e.details)}</div>' : ''}
              </div>
              ''';
            }).join('');

    final expHtml = resume.experiences.isEmpty
        ? ''
        : '<h2>${_l10n('experience', lang)}</h2>' +
            resume.experiences.map((e) {
              final loc = e.location.isNotEmpty ? e.location : resume.location;
              final bullets = e.description
                  .split('\n')
                  .map((b) => b.trim())
                  .where((b) => b.isNotEmpty)
                  .map((b) => '<li>${_escapeHtml(b)}</li>')
                  .join('');
              return '''
              <div class="row">
                <div class="row-main">
                  <span class="bold">${_escapeHtml(e.role)}</span> · ${_escapeHtml(e.company)}
                </div>
                <div class="row-meta">${_escapeHtml(e.period)} · ${_escapeHtml(loc)}</div>
                ${bullets.isNotEmpty ? '<ul>$bullets</ul>' : ''}
              </div>
              ''';
            }).join('');

    // Projects (academic + leadership condensed)
    final projItems = <String>[];
    for (final p in resume.academicProjects) {
      final bullets = p.description
          .split('\n')
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .map((b) => '<li>${_escapeHtml(b)}</li>')
          .join('');
      projItems.add('''
        <div class="row">
          <div class="row-main"><span class="bold">${_escapeHtml(p.title)}</span>${p.role.isNotEmpty ? ' · ${_escapeHtml(p.role)}' : ''}</div>
          <div class="row-meta">${_escapeHtml(p.period)}</div>
          ${bullets.isNotEmpty ? '<ul>$bullets</ul>' : ''}
        </div>
        ''');
    }
    for (final l in resume.leadership) {
      final bullets = l.description
          .split('\n')
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .map((b) => '<li>${_escapeHtml(b)}</li>')
          .join('');
      projItems.add('''
        <div class="row">
          <div class="row-main"><span class="bold">${_escapeHtml(l.organization)}</span>${l.role.isNotEmpty ? ' · ${_escapeHtml(l.role)}' : ''}</div>
          <div class="row-meta">${_escapeHtml(l.period)}</div>
          ${bullets.isNotEmpty ? '<ul>$bullets</ul>' : ''}
        </div>
        ''');
    }
    final projHtml = projItems.isEmpty
        ? ''
        : '<h2>${_l10n('projects', lang)}</h2>${projItems.join('')}';

    // Skills consolidated em uma linha cada
    final skillItems = <String>[];
    if (resume.skills.isNotEmpty) {
      skillItems.add('<div><span class="bold">${_l10n('technical_skills', lang)}:</span> ${_escapeHtml(resume.skills.join(' · '))}</div>');
    }
    if (resume.languages.isNotEmpty) {
      final langs = resume.languages.map((l) => '${_escapeHtml(l.language)} (${_escapeHtml(l.level)})').join(' · ');
      skillItems.add('<div><span class="bold">${_l10n('languages', lang)}:</span> $langs</div>');
    }
    if (resume.courses.isNotEmpty) {
      final courses = resume.courses.map((c) => _escapeHtml(c.title)).join(' · ');
      skillItems.add('<div><span class="bold">${_l10n('courses', lang)}:</span> $courses</div>');
    }
    if (resume.interests.isNotEmpty) {
      skillItems.add('<div><span class="bold">${_l10n('interests', lang)}:</span> ${_escapeHtml(resume.interests.join(' · '))}</div>');
    }
    final skillsHtml = skillItems.isEmpty
        ? ''
        : '<h2>${_l10n('technical_skills', lang)}</h2><div class="skills">${skillItems.join('')}</div>';

    return '''
<!DOCTYPE html>
<html lang="${lang == 'en' ? 'en' : 'pt-BR'}">
<head>
<meta charset="UTF-8" />
<title>${_escapeHtml(name)}</title>
<style>
  @page { size: A4; margin: 0.45in 0.55in; }
  body {
    font-family: "Helvetica", "Arial", "Segoe UI", sans-serif;
    font-size: 10pt;
    color: #1f2937;
    margin: 0;
    line-height: 1.32;
  }
  .header {
    margin-bottom: 6px;
  }
  .header h1 {
    font-size: 19pt;
    font-weight: 700;
    margin: 0 0 2px 0;
    color: #0f172a;
    letter-spacing: -0.3pt;
  }
  .header .contact {
    font-size: 9.5pt;
    color: #475569;
  }
  h2 {
    text-transform: uppercase;
    font-size: 9.5pt;
    color: #0f172a;
    margin: 9px 0 3px 0;
    padding-bottom: 2px;
    border-bottom: 0.75pt solid #cbd5e1;
    font-weight: 700;
    letter-spacing: 1pt;
  }
  .row { margin-bottom: 6px; }
  .row-main {
    font-size: 10.5pt;
    color: #0f172a;
  }
  .row-meta {
    font-size: 9pt;
    color: #64748b;
    margin-top: 1px;
  }
  .row-sub {
    font-size: 9.5pt;
    color: #334155;
    margin-top: 2px;
  }
  .bold { font-weight: 700; }
  .dim { color: #64748b; }
  ul {
    margin: 3px 0 0 0;
    padding-left: 18px;
  }
  li {
    margin-bottom: 1px;
    font-size: 10pt;
    color: #334155;
  }
  .summary {
    margin: 4px 0 0 0;
    font-size: 10pt;
    color: #334155;
  }
  .skills div { margin: 1px 0; font-size: 9.5pt; }
</style>
</head>
<body>
  <div class="header">
    <h1>${_escapeHtml(name)}</h1>
    <div class="contact">$contactLine</div>
    $summaryHtml
  </div>
  $eduHtml
  $expHtml
  $projHtml
  $skillsHtml
</body>
</html>
''';
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
