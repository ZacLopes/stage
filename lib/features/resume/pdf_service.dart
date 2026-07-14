import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../data/models/models.dart';
import 'resume_viewmodel.dart';

/// Tier de renderização do Harvard MCS. Cada tier define um conjunto
/// específico de CSS (font-size, line-height, margins) e content
/// adjustments (drop INTERESTS a partir de compact2). Iteramos por
/// estes tiers até atingir 1 página preenchida com elegância.
///
/// Ordem: expanded3 (mais espaçoso) → compact5 (mais apertado).
enum RenderTier {
  expanded3, // E3 — 11.5pt, line 1.35, role semibold
  expanded2, // E2 — 11pt, line 1.3
  expanded1, // E1 — 10.5pt, line 1.25
  standard,  // S  — 10pt, line 1.15 (default atual)
  compact1,  // C1 — 10pt, line 1.1
  compact2,  // C2 — 10pt, line 1.05, drop INTERESTS
  compact3,  // C3 — 9.5pt, drop INTERESTS
  compact4,  // C4 — 9.5pt, line 1.0, drop INTERESTS
  compact5,  // C5 — 9pt, ultra-tight (último recurso)
}

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
    // C3: TODOS os 4 templates agora usam loop adaptativo. Garante 1 página
    // independente do template escolhido pelo user. Cada template tem seu
    // próprio `_buildXxxHtml(..., tier: ...)` que aceita RenderTier e
    // gera CSS dinâmico por tier.
    return _generateAdaptive(user, resume, templateId);
  }

  /// Loop adaptativo GENÉRICO: renderiza, conta páginas, ajusta tier até atingir
  /// exatamente 1 página com o tier MAIS ESPAÇOSO possível.
  ///
  /// Algoritmo:
  /// 1. Estima tier inicial baseado em _estimateHarvardMcsLines.
  /// 2. Renderiza no tier atual + conta páginas via Syncfusion.
  /// 3. Se cabe (1 página): guarda como melhor candidato e tenta tier mais
  ///    espaçoso (1 step acima). Se subir não cabe, retorna melhor.
  /// 4. Se não cabe (>1 página): desce pra tier mais apertado. Se já
  ///    tínhamos um que cabia, retorna ele (não vai descer mais que
  ///    necessário). Se nenhum coube ainda, continua descendo.
  /// 5. C5 é o último recurso — se nem ele caber, retorna 2 páginas com
  ///    warning (caso patológico raro).
  ///
  /// Garantias:
  /// - NUNCA dropa SUMMARY (regra do Zac)
  /// - Apenas INTERESTS pode ser dropado (a partir de C2)
  /// - experiences, education, skills, certs, languages, tools intactos
  /// - Performance: tipicamente 1-3 renders (~1-3s total)
  static Future<Uint8List> _generateAdaptive(
    UserProfile? user,
    ResumeData resume,
    String templateId,
  ) async {
    // Cobalt Modern tem layout 2-col (sidebar 30%, main 70%). Bullets na
    // main wrapam mais que nos templates 1-col → estimativa precisa ser
    // ~30% mais pessimista pro loop começar num tier mais compacto.
    final estimated = templateId == 'cobalt_modern'
        ? (_estimateHarvardMcsLines(resume) * 1.3).round()
        : _estimateHarvardMcsLines(resume);
    RenderTier tier = _selectInitialTier(estimated);

    Uint8List? lastSinglePage;
    RenderTier? lastSingleTier;
    Uint8List? lastRender; // fallback se nada coube
    final visited = <RenderTier>{};

    // Direction state: começa em null; vira "up" se primeira render couber,
    // "down" se não. Não inverte direção depois (evita loops).
    String? direction;

    // Safety: máximo 9 iterações (uma por tier).
    for (int i = 0; i < 9; i++) {
      if (visited.contains(tier)) break; // anti-loop
      visited.add(tier);

      final adjusted = _applyTierContent(resume, tier);
      final html = _buildHtmlForTemplate(user, adjusted, templateId, tier);
      final pdf = await Printing.convertHtml(
        html: html,
        format: PdfPageFormat.a4,
      );
      lastRender = pdf;
      final pages = _countPdfPages(pdf);

      if (pages == 1) {
        lastSinglePage = pdf;
        lastSingleTier = tier;
        // Já temos algo que cabe. Tenta subir 1 tier (mais espaçoso).
        // Mas só se direction != 'down' (não inverter pra evitar oscilação).
        if (direction == 'down') {
          return pdf; // direção foi descendo; achou o primeiro que cabe — done
        }
        direction = 'up';
        final upTier = _tierAbove(tier);
        if (upTier == null) return pdf; // E3 já é máximo
        tier = upTier;
        continue;
      } else {
        // Não cabe.
        if (direction == 'up' && lastSinglePage != null) {
          // Subimos demais — volta pro último que cabia.
          return lastSinglePage;
        }
        direction = 'down';
        final downTier = _tierBelow(tier);
        if (downTier == null) {
          // C5 não coube — caso patológico. Log + retorna 2 páginas.
          debugPrint('[pdf-adaptive] WARN: C5 still overflows for user '
              '${user?.id ?? "(unknown)"}, template=$templateId, returning 2-page PDF');
          return pdf;
        }
        tier = downTier;
        continue;
      }
    }

    // Safety net (não deve chegar aqui em fluxos normais)
    if (lastSinglePage != null) {
      debugPrint('[pdf-adaptive] returning best single-page at $lastSingleTier (template=$templateId)');
      return lastSinglePage;
    }
    return lastRender ?? Uint8List(0);
  }

  /// Dispatcher: escolhe builder do template + propaga tier.
  /// Cada `_buildXxxHtml` aceita `RenderTier` opcional (default standard).
  static String _buildHtmlForTemplate(
    UserProfile? user,
    ResumeData resume,
    String templateId,
    RenderTier tier,
  ) {
    return switch (templateId) {
      'jakes_resume'     => _buildJakesResumeHtml(user, resume, tier: tier),
      'forte_foundation' => _buildForteFoundationHtml(user, resume, tier: tier),
      'one_page_compact' => _buildOnePageHtml(user, resume, tier: tier),
      'cobalt_modern'    => _buildCobaltModernHtml(user, resume, tier: tier),
      _                  => _buildHarvardMcsHtml(user, resume, tier: tier),
    };
  }

  /// Seam mínima de teste (Fase 2): expõe o HTML de um template pra asserção de
  /// CONTEÚDO em testes, sem passar por `Printing.convertHtml` (plataforma). Os
  /// `_buildXxxHtml` são construtores de string puros — seguros fora do device.
  /// NÃO usar em produção: produção vai por [generateResumeBytes].
  @visibleForTesting
  static String buildResumeHtmlForTest(
    UserProfile? user,
    ResumeData resume,
    String templateId,
  ) =>
      _buildHtmlForTemplate(user, resume, templateId, RenderTier.standard);

  /// Estima quantas linhas o CV vai ocupar no template Harvard MCS (font 10pt,
  /// A4, margins 0.35in/0.4in). Heurística — ~95 chars por linha de bullet,
  /// ~100 chars por linha de summary. Conservador (tende a subestimar levemente
  /// pra evitar false positives de compact em CVs minimalistas).
  static int _estimateHarvardMcsLines(ResumeData r) {
    int lines = 4; // header: name + address + 2 contact lines
    if (r.summary.isNotEmpty) {
      lines += 2; // SUMMARY section header + spacing
      lines += (r.summary.length / 95).ceil();
    }
    if (r.experiences.isNotEmpty) {
      lines += 1; // PROFESSIONAL EXPERIENCE header
      for (final exp in r.experiences) {
        lines += 3; // institution+location, role+period, entry spacing
        final desc = exp.description;
        if (desc.isNotEmpty) {
          final bullets = desc.split('\n').where((b) => b.trim().isNotEmpty);
          for (final b in bullets) {
            lines += (b.length / 95).ceil().clamp(1, 3);
          }
        }
      }
    }
    if (r.education.isNotEmpty) {
      lines += 1; // EDUCATION header
      for (final edu in r.education) {
        lines += 3; // institution+location, degree+period (with inline minor), spacing
        if (edu.gpa.isNotEmpty) lines += 1;
        lines += edu.activities.length;
      }
    }
    // SKILLS, CERTIFICATIONS & PROGRAMS section
    final hasSkillsSection = r.skills.isNotEmpty ||
        r.languages.isNotEmpty ||
        r.tools.isNotEmpty ||
        r.toolsText.isNotEmpty ||
        r.courses.isNotEmpty;
    if (hasSkillsSection) {
      lines += 1; // section header
      if (r.skills.isNotEmpty) {
        lines += (r.skills.join(', ').length / 95).ceil();
      }
      if (r.languages.isNotEmpty) lines += 1;
      if (r.tools.isNotEmpty || r.toolsText.isNotEmpty) {
        final toolsLen = r.toolsText.isNotEmpty
            ? r.toolsText.length
            : r.tools.map((t) => t.name).join(', ').length;
        lines += (toolsLen / 95).ceil();
      }
      if (r.courses.isNotEmpty) {
        lines += 1; // "Certifications & Programs:" header
        for (final c in r.courses) {
          lines += (c.title.length / 95).ceil();
        }
      }
    }
    if (r.interests.isNotEmpty) {
      lines += 1; // INTERESTS section header
      lines += (r.interests.join(', ').length / 95).ceil();
    }
    return lines;
  }

  /// Se o CV estoura 1 página, dropa seções decorativas pra trazer pra 1
  /// página. Estratégia conservadora — só dropa INTERESTS (única seção
  /// puramente decorativa). NÃO toca em experiences, education, skills,
  /// certifications, languages, tools — tudo factual fica intacto.
  ///
  /// SUMMARY NUNCA é dropado (regra inegociável do Zac).
  static ResumeData _applyTierContent(ResumeData r, RenderTier tier) {
    // INTERESTS só sai a partir de compact2.
    final dropInterests = tier.index >= RenderTier.compact2.index;
    if (dropInterests && r.interests.isNotEmpty) {
      return r.copyWith(interests: const []);
    }
    return r;
  }

  /// Conta páginas do PDF gerado via Syncfusion. Usado pelo loop adaptativo
  /// pra decidir se o tier atual cabe em 1 página ou precisa apertar mais.
  /// Custo: ~5-20ms por count. Negligível.
  ///
  /// IMPORTANTE: usa try/finally pra garantir `dispose()` mesmo quando
  /// `doc.pages.count` lança. Em loops de até 9 iterações, vazamento de
  /// PdfDocument acumula rapidamente e pode crashear o app por OOM.
  static int _countPdfPages(Uint8List bytes) {
    sf.PdfDocument? doc;
    try {
      doc = sf.PdfDocument(inputBytes: bytes);
      return doc.pages.count;
    } catch (_) {
      return 1; // safe default — se falhar, presume cabe
    } finally {
      doc?.dispose();
    }
  }

  /// Escolhe tier inicial baseado em estimativa de linhas. Otimização
  /// pra reduzir iterações: começa no tier mais provável de já caber.
  /// Maioria dos casos: 1-2 renders bastam pra convergir.
  static RenderTier _selectInitialTier(int estimatedLines) {
    if (estimatedLines > 60) return RenderTier.compact2;
    if (estimatedLines > 55) return RenderTier.compact1;
    if (estimatedLines > 45) return RenderTier.standard;
    if (estimatedLines > 35) return RenderTier.expanded1;
    if (estimatedLines > 28) return RenderTier.expanded2;
    return RenderTier.expanded3;
  }

  /// CSS de override universal por tier — aplicável a qualquer template.
  /// Modifica APENAS `body { font-size, line-height }` e `@page { margin }`
  /// via `!important` no FIM do `<style>`. Preserva a identidade visual de
  /// cada template (cores, fonts, hierarquia) — só ajusta densidade global.
  ///
  /// Os 4 templates têm valores "standard" próprios; esse override aplica
  /// um delta proporcional baseado no tier.
  static String _buildTierOverrideCss(RenderTier tier) {
    // Cada tier define um body font-size absoluto + line-height + margem
    // de @page. Em vez de "delta", usamos valores absolutos pra controle
    // total, com `!important` pra sobrepor o CSS do template.
    final cfg = switch (tier) {
      RenderTier.expanded3 => ('11.5pt', '1.35', '0.55in 0.55in'),
      RenderTier.expanded2 => ('11pt',   '1.3',  '0.5in 0.5in'),
      RenderTier.expanded1 => ('10.5pt', '1.25', '0.45in 0.45in'),
      RenderTier.standard  => null, // mantém CSS original do template
      RenderTier.compact1  => ('10pt',   '1.1',  '0.35in 0.35in'),
      RenderTier.compact2  => ('10pt',   '1.05', '0.3in 0.3in'),
      RenderTier.compact3  => ('9.5pt',  '1.05', '0.3in 0.3in'),
      RenderTier.compact4  => ('9.5pt',  '1.0',  '0.25in 0.25in'),
      RenderTier.compact5  => ('9pt',    '1.0',  '0.2in 0.2in'),
    };
    if (cfg == null) return ''; // standard: sem override
    final (fontSize, lineHeight, pageMargin) = cfg;
    return '''
/* Tier override (loop adaptativo) */
@page { size: A4; margin: $pageMargin !important; }
body { font-size: $fontSize !important; line-height: $lineHeight !important; }
''';
  }

  /// Overrides específicos do Cobalt Modern por tier. O override universal
  /// (`_buildTierOverrideCss`) só toca `body font-size` + `line-height` +
  /// `@page margin`. Mas no Cobalt, os fonts internos (.exp-role,
  /// .main-title etc) e os paddings da sidebar/main precisam encolher
  /// proporcionalmente em tiers compact pra realmente caber em 1 página.
  ///
  /// Aplicado APÓS `_buildTierOverrideCss` no fim do `<style>`, então
  /// ganha precedência via ordem do CSS (mesma specificity + !important).
  static String _buildCobaltTierExtraCss(RenderTier tier) {
    // (sidebarPad, mainPad, expMb, mainSecMb, expRoleSize, expSubSize,
    //  mainTitleSize, mainListSize, sideListSize, nameSize, headerPad)
    // Os valores foram ajustados pra Gabriel (perfil large) caber em 1
    // página já em compact1 ou compact2. Compact tiers ficam realmente
    // apertados — line-height vem do _buildTierOverrideCss universal.
    final cfg = switch (tier) {
      RenderTier.expanded3 => null,
      RenderTier.expanded2 => null,
      RenderTier.expanded1 => null,
      RenderTier.standard  => null,
      RenderTier.compact1  => ('11pt', '12pt', '6pt', '9pt', '10pt', '8.5pt', '10pt', '9pt', '8.5pt', '18pt', '12pt'),
      RenderTier.compact2  => ('10pt', '11pt', '5pt', '8pt', '9.5pt', '8pt', '9.5pt', '8.5pt', '8pt', '17pt', '10pt'),
      RenderTier.compact3  => ('9pt', '10pt', '4pt', '7pt', '9.5pt', '8pt', '9.5pt', '8pt', '8pt', '16pt', '9pt'),
      RenderTier.compact4  => ('8pt', '9pt', '4pt', '6pt', '9pt', '7.5pt', '9pt', '8pt', '7.5pt', '15pt', '8pt'),
      RenderTier.compact5  => ('7pt', '8pt', '3pt', '5pt', '8.5pt', '7.5pt', '8.5pt', '7.5pt', '7.5pt', '14pt', '7pt'),
    };
    if (cfg == null) return '';
    final (
      sidebarPad,
      mainPad,
      expMb,
      mainSecMb,
      expRoleSize,
      expSubSize,
      mainTitleSize,
      mainListSize,
      sideListSize,
      nameSize,
      headerPad,
    ) = cfg;
    return '''
/* Cobalt Modern tier extras (compact-specific) */
.header { padding: $headerPad $headerPad $headerPad !important; }
.name { font-size: $nameSize !important; }
.sidebar { padding: $sidebarPad $sidebarPad !important; }
.main { padding: $mainPad $mainPad !important; }
.exp { margin-bottom: $expMb !important; }
.main-sec { margin-bottom: $mainSecMb !important; }
.exp-role { font-size: $expRoleSize !important; }
.exp-sub { font-size: $expSubSize !important; }
.main-title { font-size: $mainTitleSize !important; }
.main-list li { font-size: $mainListSize !important; }
.side-list li { font-size: $sideListSize !important; }
.main-text { font-size: $mainListSize !important; }
.side-sec { margin-bottom: $expMb !important; }
''';
  }

  /// Tier acima na hierarquia (mais espaçoso). Retorna null se já é E3.
  static RenderTier? _tierAbove(RenderTier t) =>
      t.index > 0 ? RenderTier.values[t.index - 1] : null;

  /// Tier abaixo na hierarquia (mais apertado). Retorna null se já é C5.
  static RenderTier? _tierBelow(RenderTier t) =>
      t.index < RenderTier.values.length - 1
          ? RenderTier.values[t.index + 1]
          : null;

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
      'awards': 'Prêmios e Reconhecimentos',
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
      'awards': 'Awards and Recognition',
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

  /// Prêmios com TEXTO renderável (título/instituição/descrição não-vazios após
  /// trim). Um prêmio só com data NÃO renderiza (sem âncora textual). Usado por
  /// TODOS os templates pra montar a seção "Prêmios e Reconhecimentos" a partir
  /// de `ResumeData.awards` (campo próprio; NÃO é `achievements`).
  static List<ResumeAward> _renderableAwards(ResumeData r) => r.awards
      .where((a) =>
          a.title.trim().isNotEmpty ||
          a.institution.trim().isNotEmpty ||
          a.description.trim().isNotEmpty)
      .toList();

  /// Projetos com ÂNCORA PRIMÁRIA renderável (título, papel ou descrição após
  /// trim). Espelha [ProfilePdfData.projectHasRenderableText] no lado do template
  /// (defesa análoga a [_renderableAwards]): relevantWork/período/local sozinhos
  /// NÃO geram uma entrada em branco sob o cabeçalho "Projetos".
  static List<ResumeProject> _renderableProjects(ResumeData r) =>
      r.academicProjects
          .where((p) =>
              p.title.trim().isNotEmpty ||
              p.role.trim().isNotEmpty ||
              p.description.trim().isNotEmpty)
          .toList();

  /// Metadados do prêmio (instituição + data) já com trim; vazio se ambos
  /// vazios. `sep` varia por template.
  static String _awardMeta(ResumeAward a, {String sep = ' · '}) {
    final parts = <String>[
      if (a.institution.trim().isNotEmpty) a.institution.trim(),
      if (a.date.trim().isNotEmpty) a.date.trim(),
    ];
    return parts.join(sep);
  }

  /// CSS dinâmico por RenderTier. Varia font-size, line-height, margins
  /// e role weight (semibold em E3 pra emphasis extra). Mantém estrutura
  /// e identidade visual do Harvard MCS — só ajusta density.
  ///
  /// Valores definidos no plan (tabela de tiers). Standard (S) reproduz
  /// o CSS original — backward-compat se chamado sem tier.
  static String _buildHarvardCssForTier(RenderTier tier) {
    // Lookup-table: cada tier mapeia pros 6 valores que variam.
    // Ordem dos valores: [fontSize, lineHeight, margin, entryMb, secMt, roleWeight]
    final cfg = switch (tier) {
      RenderTier.expanded3 => ('11.5pt', '1.35', '0.5in 0.5in', '8pt', '9pt', '600'),
      RenderTier.expanded2 => ('11pt',   '1.3',  '0.5in 0.5in', '7pt', '8pt', 'normal'),
      RenderTier.expanded1 => ('10.5pt', '1.25', '0.45in 0.4in', '6pt', '7pt', 'normal'),
      RenderTier.standard  => ('10pt',   '1.15', '0.35in 0.3in', '4pt', '5pt', 'normal'),
      RenderTier.compact1  => ('10pt',   '1.1',  '0.3in 0.3in',  '3pt', '4pt', 'normal'),
      RenderTier.compact2  => ('10pt',   '1.05', '0.3in 0.25in', '2.5pt', '3pt', 'normal'),
      RenderTier.compact3  => ('9.5pt',  '1.05', '0.25in 0.25in','2pt', '3pt', 'normal'),
      RenderTier.compact4  => ('9.5pt',  '1.0',  '0.25in 0.25in','2pt', '2pt', 'normal'),
      RenderTier.compact5  => ('9pt',    '1.0',  '0.2in 0.2in',  '1.5pt', '2pt', 'normal'),
    };
    final (fontSize, lineHeight, pageMargin, entryMb, secMt, roleWeight) = cfg;

    return '''
    @page { size: A4; margin: $pageMargin; }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Times New Roman', Times, serif; font-size: $fontSize; color: #000; line-height: $lineHeight; }
    .header { text-align: center; margin-bottom: 3pt; }
    .name { font-weight: bold; font-size: 17pt; letter-spacing: 0.5pt; }
    .address { font-size: 9.5pt; margin-top: 3pt; }
    .contact { font-size: 9.5pt; margin-top: 1pt; }
    hr { border: none; border-top: 1px solid #000; margin: 5pt 0 10pt; }
    .sec { text-align: left; text-transform: uppercase; font-weight: bold; font-size: 10pt; letter-spacing: 0.3pt; margin: $secMt 0 0; padding-bottom: 1pt; border-bottom: 0.5pt solid #000; }
    .sec + * { margin-top: 2pt; }
    .row { display: flex; justify-content: space-between; font-size: $fontSize; }
    .row .r { white-space: nowrap; margin-left: 8pt; }
    .bold .l, .bold .r { font-weight: bold; }
    .italic .l { font-style: italic; font-weight: $roleWeight; }
    .entry { margin-bottom: $entryMb; }
    .rel { font-size: $fontSize; margin: 1pt 0; }
    ul { margin: 1pt 0 0 0; padding: 0; list-style: none; }
    li { font-size: $fontSize; margin-bottom: 0.5pt; padding-left: 0; text-indent: 0; }
    li::before { content: "• "; }
    .sk { font-size: $fontSize; margin-bottom: 2pt; }
    .detail { font-size: 9.5pt; margin-top: 1pt; }
    .ach-item { margin-bottom: 4pt; }
    .ach-title { font-size: 11pt; font-weight: bold; }
    .ach-role { font-size: 10pt; font-style: italic; margin-top: 0.5pt; }
    .ach-meta { font-size: 10pt; color: #444; margin-top: 0.5pt; }
    .ach-desc { font-size: 10.5pt; margin-top: 1pt; }
''';
  }

  static String _buildHarvardMcsHtml(
    UserProfile? user,
    ResumeData resume, {
    RenderTier tier = RenderTier.standard,
  }) {
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

    final harvardProjects = _renderableProjects(resume);
    final projectItems = harvardProjects
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

    final activitiesHtml = (harvardProjects.isNotEmpty || resume.leadership.isNotEmpty)
        ? '<div class="sec">${_l10n('leadership', lang)}</div>$projectItems$leadItems'
        : achievementsHtml;

    // Prêmios (ResumeData.awards) — seção PRÓPRIA, independente de
    // achievements/projetos. Lista simples (título em bold + meta + descrição).
    final awardItems = _renderableAwards(resume).map((a) {
      final title = a.title.trim();
      final meta = _awardMeta(a);
      final desc = a.description.trim();
      final titleHtml = title.isEmpty ? '' : '<b>${_escapeHtml(title)}</b>';
      final metaHtml = meta.isEmpty ? '' : ' (${_escapeHtml(meta)})';
      final descHtml = desc.isEmpty ? '' : ' — ${_escapeHtml(desc)}';
      return '<li>$titleHtml$metaHtml$descHtml</li>';
    }).join('');
    final awardsHtml = awardItems.isEmpty
        ? ''
        : '<div class="sec">${_l10n('awards', lang)}</div><ul>$awardItems</ul>';

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
${_buildHarvardCssForTier(tier)}
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
  $awardsHtml
  $skillsHtml
  $interestsHtml
</body>
</html>''';
  }

  static String _buildHarvardEducationItemHtml(EducationItem edu, ResumeData resume) {
    final location = edu.location;
    // A1: details (ex: "Minor in Finance, Entrepreneurship") agora vai
    // INLINE na linha do degree em vez de subtitle separado. Economiza
    // 1 linha quando details é não-vazio. Quando vazio, comportamento igual.
    final degreeInline = edu.details.isNotEmpty
        ? '${edu.degree} · ${_escapeHtml(edu.details)}'
        : edu.degree;

    // Harvard enrichments — render as bullets when present
    final lang = resume.language;
    final highlightItems = <String>[];
    if (edu.coursework.isNotEmpty) {
      highlightItems.add('<li><b>${_l10n('edu_coursework', lang)}:</b> ${_escapeHtml(edu.coursework)}</li>');
    }
    if (edu.gpa.isNotEmpty) {
      highlightItems.add('<li><b>${_l10n('edu_gpa', lang)}:</b> ${_escapeHtml(edu.gpa)}</li>');
    }
    // activities (Tier 1.2): cada item vira <li> próprio. Se vier no
    // formato "Label: content" (vindo do extract-profile preservando o
    // prefix do CV original), renderiza com label em bold. Senão, sem
    // label. Substitui o legacy `edu.honors` (single-string com `;`)
    // que causava label do template duplicado dentro do conteúdo.
    if (edu.activities.isNotEmpty) {
      for (final a in edu.activities) {
        highlightItems.add(_renderActivityLi(a));
      }
    } else if (edu.honors.isNotEmpty) {
      // Fallback legacy: template antigo com honors single-string.
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
        '<div class="row italic"><span class="l">$degreeInline</span>'
        '<span class="r">${edu.period}</span></div>'
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
        parts.add('$level $preposition ${_joinList(list, lang)}');
      }
    }
    byLevel.forEach((level, list) {
      parts.add('$level $preposition ${_joinList(list, lang)}');
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
  static String _joinList(List<String> items, [String lang = 'pt']) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items[0];
    final conn = lang == 'en' ? 'and' : 'e';
    if (items.length == 2) return '${items[0]} $conn ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')} $conn ${items.last}';
  }

  static String _escapeHtml(String s) =>
      s.replaceAll('&', '&amp;')
       .replaceAll('<', '&lt;')
       .replaceAll('>', '&gt;')
       .replaceAll('"', '&quot;');

  /// Substitui hyphens-minus (`-`) por NON-BREAKING HYPHEN (U+2011 `‑`).
  /// Visualmente idêntico mas o renderer NÃO quebra a linha ali. Usado em
  /// URLs do header (LinkedIn principalmente) — usernames como
  /// `gabriel-hiromiti-matsumoto` antes quebravam em 2 linhas no PDF.
  static String _noBreakHyphens(String s) => s.replaceAll('-', '‑');

  /// Normaliza URL de LinkedIn pra exibição no PDF e retorna HTML pronto
  /// pra interpolar (já escapado). Aplica:
  ///   1. Remove protocol `http(s)://` e `www.`
  ///   2. Remove query string `?param=…` (LinkedIn mobile cola
  ///      `?skipRedirect=true` no link copiado, polui o display)
  ///   3. Remove trailing `/`
  ///   4. Substitui `-` por non-breaking hyphen (não quebra username)
  ///   5. Insere `<wbr>` depois de cada `/` pra permitir quebra suave
  ///      em coluna estreita sem quebrar no meio do username
  static String _cleanLinkedinForDisplay(String raw) {
    var url = raw.replaceAll(RegExp(r'^https?://(www\.)?'), '');
    final qIdx = url.indexOf('?');
    if (qIdx > 0) url = url.substring(0, qIdx);
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    url = _noBreakHyphens(url);
    // Escapa antes de injetar <wbr> pra evitar dupla-escapagem.
    return _escapeHtml(url).replaceAll('/', '/<wbr>');
  }

  /// Insere `<wbr>` (word break opportunity) depois de `@` e `.` no email.
  /// Permite quebra de linha em pontos visualmente aceitáveis quando o
  /// container é estreito — em vez de quebrar no meio da palavra (ex:
  /// `outlook.co` linha 1, `m` linha 2). Já retorna escapado.
  static String _wrappableEmail(String email) {
    final escaped = _escapeHtml(email);
    return escaped
        .replaceAll('@', '@<wbr>')
        .replaceAll('.', '.<wbr>');
  }

  /// Renderiza um item de `EducationItem.activities` como `<li>`. Se a
  /// string vier no formato "Label: content" (preservado do CV original
  /// pelo extract-profile), separa em `<b>Label:</b> content`. Senão
  /// renderiza solto. Limite de 60 chars no label evita falsos positivos
  /// (ex: bullet longo que tem ':' no meio).
  static String _renderActivityLi(String activity) {
    final trimmed = activity.trim();
    if (trimmed.isEmpty) return '';
    final colonIdx = trimmed.indexOf(':');
    if (colonIdx > 0 && colonIdx < 60) {
      final label = trimmed.substring(0, colonIdx).trim();
      final content = trimmed.substring(colonIdx + 1).trim();
      if (label.isNotEmpty && content.isNotEmpty) {
        return '<li><b>${_escapeHtml(label)}:</b> ${_escapeHtml(content)}</li>';
      }
    }
    return '<li>${_escapeHtml(trimmed)}</li>';
  }

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
  static String _buildJakesResumeHtml(
    UserProfile? user,
    ResumeData resume, {
    RenderTier tier = RenderTier.standard,
  }) {
    final lang = resume.language;
    final name = (resume.fullName.isNotEmpty ? resume.fullName : (user?.name ?? '')).trim();

    final contactParts = <String>[];
    if (resume.phone.isNotEmpty) contactParts.add(_escapeHtml(resume.phone));
    if (resume.email.isNotEmpty) contactParts.add(_escapeHtml(resume.email));
    if (resume.linkedin.isNotEmpty) {
      contactParts.add(_cleanLinkedinForDisplay(resume.linkedin));
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
    for (final p in _renderableProjects(resume)) {
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

    // Prêmios (ResumeData.awards) — seção própria via o mesmo helper entry().
    final awardItemsJ = _renderableAwards(resume)
        .map((a) => entry(
              tl: a.title,
              tr: a.date,
              bl: a.institution,
              description: a.description,
            ))
        .join('');
    final awardsHtmlJ = awardItemsJ.isEmpty
        ? ''
        : section(_l10n('awards', lang)) + awardItemsJ;

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
${_buildTierOverrideCss(tier)}
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
  $awardsHtmlJ
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
  static String _buildForteFoundationHtml(
    UserProfile? user,
    ResumeData resume, {
    RenderTier tier = RenderTier.standard,
  }) {
    final lang = resume.language;
    final name = (resume.fullName.isNotEmpty ? resume.fullName : (user?.name ?? '')).trim().toUpperCase();

    final contactParts = <String>[];
    if (resume.location.isNotEmpty) contactParts.add(_escapeHtml(resume.location));
    if (resume.phone.isNotEmpty) contactParts.add(_escapeHtml(resume.phone));
    if (resume.email.isNotEmpty) contactParts.add(_escapeHtml(resume.email));
    if (resume.linkedin.isNotEmpty) {
      contactParts.add(_cleanLinkedinForDisplay(resume.linkedin));
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

    // Resumo/Summary — seção formal após o cabeçalho, antes de Educação. O
    // contrato do currículo geral trata summary como conteúdo renderável, então
    // o Forte PRECISA exibi-lo (senão gerava PDF sem o resumo e retornava ok).
    final summaryHtml = resume.summary.trim().isEmpty
        ? ''
        : '${section(_l10n('summary', lang))}<div class="summary">${_escapeHtml(resume.summary.trim())}</div>';

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
    for (final p in _renderableProjects(resume)) {
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

    // Prêmios (ResumeData.awards) — seção própria. Título (bold) + data à
    // direita; instituição em itálico; descrição abaixo. Sem linha vazia.
    final awardItemsF = _renderableAwards(resume).map((a) {
      final inst = a.institution.trim();
      final desc = a.description.trim();
      final instHtml = inst.isEmpty
          ? ''
          : '<div class="det italic">${_escapeHtml(inst)}</div>';
      final descHtml =
          desc.isEmpty ? '' : '<div class="det">${_escapeHtml(desc)}</div>';
      return '''
        <div class="entry">
          <table class="entry-row"><tr>
            <td class="left bold">${_escapeHtml(a.title.trim())}</td>
            <td class="right bold">${_escapeHtml(a.date.trim())}</td>
          </tr></table>
          $instHtml
          $descHtml
        </div>
      ''';
    }).join('');
    final awardsHtmlF = awardItemsF.isEmpty
        ? ''
        : section(_l10n('awards', lang)) + awardItemsF;

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
.summary { font-size: 10.5pt; margin: 2pt 0 4pt; text-align: justify; }
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
${_buildTierOverrideCss(tier)}
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
  $actHtml
  $awardsHtmlF
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
  static String _buildOnePageHtml(
    UserProfile? user,
    ResumeData resume, {
    RenderTier tier = RenderTier.standard,
  }) {
    final lang = resume.language;
    final name = (resume.fullName.isNotEmpty ? resume.fullName : (user?.name ?? '')).trim();

    final contactParts = <String>[];
    if (resume.email.isNotEmpty) contactParts.add(_escapeHtml(resume.email));
    if (resume.phone.isNotEmpty) contactParts.add(_escapeHtml(resume.phone));
    if (resume.linkedin.isNotEmpty) {
      contactParts.add(_cleanLinkedinForDisplay(resume.linkedin));
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
    for (final p in _renderableProjects(resume)) {
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

    // Prêmios (ResumeData.awards) — seção própria via singleLineEntry.
    final awardItemsO = _renderableAwards(resume)
        .map((a) => singleLineEntry(
              primary: a.title,
              secondary: a.institution,
              tertiary: a.date,
              description: a.description,
            ))
        .join('');
    final awardsHtmlO = awardItemsO.isEmpty
        ? ''
        : section(_l10n('awards', lang)) + awardItemsO;

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
${_buildTierOverrideCss(tier)}
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
  $awardsHtmlO
  $skillsHtml
</body>
</html>''';
  }

  // --- Cobalt Modern Template (2-col, sans-serif, cobalt accent) ---
  //
  // Diferenciado dos 4 templates clássicos (todos single-col, serif,
  // preto-e-branco):
  //   - Layout 2-col via <table> (ATS-friendly; CSS Grid/Flexbox alguns
  //     parsers ATS antigos quebram).
  //   - Sans-serif (Inter / system-ui) — modern.
  //   - Cor de accent #1E40AF (cobalt) em headers, divisores e nome de
  //     empresa em experiences.
  //   - Sidebar 35%: contato + skills + languages + tools + certs + interests.
  //   - Main 65%: summary + experience + education.
  //   - Header full-width com nome grande + linha cobalt embaixo.
  //
  // Compatível com tier override via `${_buildTierOverrideCss(tier)}` antes
  // do `</style>` — loop adaptativo funciona automaticamente.
  static String _buildCobaltModernHtml(
    UserProfile? user,
    ResumeData resume, {
    RenderTier tier = RenderTier.standard,
  }) {
    final lang = resume.language;
    final name = (resume.fullName.isNotEmpty
            ? resume.fullName
            : (user?.name ?? 'Seu Nome'))
        .trim();
    // Headline removida (era "Professional Profile" / "Perfil Profissional").
    // Header agora tem só o nome + linha cobalt, mais clean e dá mais
    // espaço vertical pro main content.
    const headline = '';

    // ──── Sidebar: contato ────
    // Sem icons/emojis — só os valores em texto limpo, ATS-friendly.
    final contactItems = <String>[];
    if (resume.phone.isNotEmpty) {
      contactItems.add('<div class="ct">${_escapeHtml(resume.phone)}</div>');
    }
    if (resume.email.isNotEmpty) {
      contactItems.add('<div class="ct">${_wrappableEmail(resume.email)}</div>');
    }
    if (resume.linkedin.isNotEmpty) {
      contactItems.add('<div class="ct">${_cleanLinkedinForDisplay(resume.linkedin)}</div>');
    }
    final fullLocation = <String>[];
    if (resume.address.isNotEmpty) fullLocation.add(resume.address);
    if (resume.location.isNotEmpty) fullLocation.add(resume.location);
    if (fullLocation.isNotEmpty) {
      contactItems.add('<div class="ct">${_escapeHtml(fullLocation.join(' – '))}</div>');
    }
    final contactHtml = contactItems.isEmpty
        ? ''
        : '<div class="side-sec"><div class="side-title">${_l10n('mobile', lang).toUpperCase() == 'MOBILE' ? 'CONTACT' : 'CONTATO'}</div>${contactItems.join('')}</div>';

    // ──── Sidebar: skills ────
    String sideSec(String title, String content) =>
        content.isEmpty ? '' : '<div class="side-sec"><div class="side-title">$title</div>$content</div>';

    final skillsHtml = resume.skills.isEmpty
        ? ''
        : '<ul class="side-list">${resume.skills.map((s) => '<li>${_escapeHtml(s)}</li>').join('')}</ul>';

    final langsHtml = resume.languages.isEmpty
        ? ''
        : '<ul class="side-list">${resume.languages.map((l) {
            final levelLocalized = _translateLevel(l.level, lang);
            final lvl = levelLocalized.isEmpty ? '' : ' <span class="side-meta">— $levelLocalized</span>';
            return '<li>${_escapeHtml(l.language)}$lvl</li>';
          }).join('')}</ul>';

    String toolsListHtml() {
      if (resume.toolsText.trim().isNotEmpty) {
        return '<div class="side-text">${_escapeHtml(resume.toolsText.trim())}</div>';
      }
      if (resume.tools.isNotEmpty) {
        return '<ul class="side-list">${resume.tools.map((t) {
          final lvl = t.level.trim().isEmpty ? '' : ' <span class="side-meta">— ${_translateLevel(t.level, lang)}</span>';
          return '<li>${_escapeHtml(t.name)}$lvl</li>';
        }).join('')}</ul>';
      }
      return '';
    }

    final certsHtml = resume.courses.isEmpty
        ? ''
        : '<ul class="side-list">${resume.courses.map((c) {
            final title = _escapeHtml(c.title);
            final inst = c.institution.isEmpty ? '' : ' <span class="side-meta">— ${_escapeHtml(c.institution)}</span>';
            final yr = c.period.isEmpty ? '' : ' <span class="side-meta">(${_escapeHtml(c.period)})</span>';
            return '<li>$title$inst$yr</li>';
          }).join('')}</ul>';

    final interestsHtml = resume.interests.isEmpty
        ? ''
        : '<div class="side-text">${_escapeHtml(resume.interests.join(', '))}</div>';

    final sidebarHtml = '''
$contactHtml
${sideSec(lang == 'en' ? 'SKILLS' : 'HABILIDADES', skillsHtml)}
${sideSec(lang == 'en' ? 'LANGUAGES' : 'IDIOMAS', langsHtml)}
${sideSec(lang == 'en' ? 'TOOLS' : 'FERRAMENTAS', toolsListHtml())}
${sideSec(lang == 'en' ? 'CERTIFICATIONS' : 'CERTIFICAÇÕES', certsHtml)}
${sideSec(lang == 'en' ? 'INTERESTS' : 'INTERESSES', interestsHtml)}
''';

    // ──── Main: summary ────
    final summaryHtml = resume.summary.trim().isEmpty
        ? ''
        : '''
<div class="main-sec">
  <div class="main-title">${_l10n('summary', lang).toUpperCase()}</div>
  <div class="main-text">${_escapeHtml(resume.summary.trim())}</div>
</div>''';

    // ──── Main: experience ────
    // Layout: role no topo (sozinho, pode quebrar em 2 linhas se longo),
    // depois company + período + local na MESMA linha de subtitle, depois
    // bullets. Evita o flex space-between que estourava role longo em N
    // linhas estreitas quando coluna main fica apertada.
    final expEntries = resume.experiences.map((e) {
      final bullets = e.description.trim().isEmpty
          ? ''
          : '<ul class="main-list">${e.description.split('\n').where((b) => b.trim().isNotEmpty).map((b) {
              final clean = b.replaceAll('•', '').trim();
              return '<li>${_emphasizeMetrics(_escapeHtml(clean))}</li>';
            }).join('')}</ul>';
      final subParts = <String>[
        if (e.company.trim().isNotEmpty) e.company.trim(),
        if (e.period.trim().isNotEmpty) e.period.trim(),
        if (e.location.trim().isNotEmpty) e.location.trim(),
      ];
      return '''
<div class="exp">
  <div class="exp-role">${_escapeHtml(e.role)}</div>
  <div class="exp-sub">${_escapeHtml(subParts.join(' • '))}</div>
  $bullets
</div>''';
    }).join('');
    final expHtml = resume.experiences.isEmpty
        ? ''
        : '''
<div class="main-sec">
  <div class="main-title">${_l10n('experience', lang).toUpperCase()}</div>
  $expEntries
</div>''';

    // ──── Main: education ────
    final eduEntries = resume.education.map((e) {
      final detailLine = e.details.isEmpty ? '' : '<div class="edu-det">${_escapeHtml(e.details)}</div>';
      final gpaLine = e.gpa.isEmpty
          ? ''
          : '<div class="edu-det"><b>${_l10n('edu_gpa', lang)}:</b> ${_escapeHtml(e.gpa)}</div>';
      final activitiesHtml = (e.activities.isEmpty && e.honors.isEmpty)
          ? ''
          : (e.activities.isNotEmpty
              ? '<ul class="main-list">${e.activities.map(_renderActivityLi).join('')}</ul>'
              : '<div class="edu-det"><b>${_l10n('edu_honors', lang)}:</b> ${_escapeHtml(e.honors)}</div>');
      final subParts = <String>[
        if (e.institution.trim().isNotEmpty) e.institution.trim(),
        if (e.period.trim().isNotEmpty) e.period.trim(),
        if (e.location.trim().isNotEmpty) e.location.trim(),
      ];
      return '''
<div class="exp">
  <div class="exp-role">${_escapeHtml(e.degree)}</div>
  <div class="exp-sub">${_escapeHtml(subParts.join(' • '))}</div>
  $detailLine
  $gpaLine
  $activitiesHtml
</div>''';
    }).join('');
    final eduHtml = resume.education.isEmpty
        ? ''
        : '''
<div class="main-sec">
  <div class="main-title">${_l10n('education', lang).toUpperCase()}</div>
  $eduEntries
</div>''';

    // ──── Main: projetos + liderança ────
    // O Cobalt não renderizava academicProjects/leadership (eram silenciosamente
    // descartados). Agora renderiza — currículo geral e CVs com projetos passam
    // a mostrá-los, iguais aos outros 4 templates.
    String cobaltEntry(String role, List<String> subParts, String description) {
      final bullets = description.trim().isEmpty
          ? ''
          : '<ul class="main-list">${description.split('\n').where((b) => b.trim().isNotEmpty).map((b) {
              final clean = b.replaceAll('•', '').trim();
              return '<li>${_emphasizeMetrics(_escapeHtml(clean))}</li>';
            }).join('')}</ul>';
      final sub = subParts.where((s) => s.trim().isNotEmpty).isEmpty
          ? ''
          : '<div class="exp-sub">${_escapeHtml(subParts.where((s) => s.trim().isNotEmpty).join(' • '))}</div>';
      return '<div class="exp"><div class="exp-role">${_escapeHtml(role)}</div>$sub$bullets</div>';
    }

    final actEntries = <String>[
      for (final p in _renderableProjects(resume))
        cobaltEntry(p.title, [p.role, p.period, p.location], p.description),
      for (final l in resume.leadership)
        cobaltEntry(
            l.organization, [l.role, l.period, l.location], l.description),
    ].join('');
    final projHtmlC = actEntries.isEmpty
        ? ''
        : '''
<div class="main-sec">
  <div class="main-title">${_l10n('projects', lang).toUpperCase()}</div>
  $actEntries
</div>''';

    // ──── Main: prêmios (ResumeData.awards) ────
    final awardEntriesC = _renderableAwards(resume).map((a) {
      final meta = _awardMeta(a);
      final desc = a.description.trim();
      final metaHtml =
          meta.isEmpty ? '' : '<div class="exp-sub">${_escapeHtml(meta)}</div>';
      final descHtml =
          desc.isEmpty ? '' : '<div class="edu-det">${_escapeHtml(desc)}</div>';
      return '<div class="exp"><div class="exp-role">${_escapeHtml(a.title.trim())}</div>$metaHtml$descHtml</div>';
    }).join('');
    final awardsHtmlC = awardEntriesC.isEmpty
        ? ''
        : '''
<div class="main-sec">
  <div class="main-title">${_l10n('awards', lang).toUpperCase()}</div>
  $awardEntriesC
</div>''';

    return '''<!DOCTYPE html>
<html lang="${lang == 'en' ? 'en' : 'pt-BR'}">
<head>
<meta charset="UTF-8">
<style>
@page { size: A4; margin: 0; }
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Inter', -apple-system, 'Segoe UI', 'Helvetica Neue', sans-serif; font-size: 10pt; color: #1E293B; line-height: 1.35; }

/* Header full-width */
.header { padding: 16pt 24pt 10pt; border-bottom: 3pt solid #1E40AF; }
/* Nome em 20pt cabe em 1 linha pra nomes de até ~38 chars. Nomes longos
   ainda quebram em 2 linhas, mas tomam metade da altura comparado a 24pt. */
.name { font-size: 20pt; font-weight: 700; color: #0F172A; letter-spacing: -0.4pt; line-height: 1.1; }
.headline { font-size: 10pt; color: #1E40AF; font-weight: 500; margin-top: 3pt; letter-spacing: 0.3pt; text-transform: uppercase; }

/* 2-col layout via table — ATS-friendly. Sidebar 30% pra dar mais espaço
   ao main e evitar role wrap excessivo em coluna estreita. */
.layout { width: 100%; border-collapse: collapse; }
.sidebar { width: 30%; background: #F8FAFC; padding: 14pt 14pt; vertical-align: top; }
.main { padding: 14pt 18pt; vertical-align: top; }

/* Sidebar */
.side-sec { margin-bottom: 10pt; }
/* letter-spacing reduzido de 1.2pt → 0.5pt — em coluna estreita, 1.2 deixa
   o título visualmente "rasgado" (ex: "H A B I L I D A D E S"). */
.side-title { font-size: 8.5pt; font-weight: 700; color: #1E40AF; letter-spacing: 0.5pt; margin-bottom: 5pt; padding-bottom: 2pt; border-bottom: 1pt solid #CBD5E1; }
.side-list { list-style: none; padding: 0; margin: 0; }
.side-list li { font-size: 9pt; color: #334155; margin-bottom: 2pt; padding-left: 7pt; position: relative; line-height: 1.3; }
.side-list li::before { content: "•"; color: #1E40AF; position: absolute; left: 0; top: 0; font-weight: 700; }
.side-text { font-size: 9pt; color: #334155; line-height: 1.4; }
.side-meta { color: #64748B; font-size: 8pt; }
/* overflow-wrap: anywhere respeita os <wbr> injetados em email/URL (quebra
   em @, ., /) em vez de quebrar em qualquer char como word-break fazia. */
.ct { font-size: 8.5pt; color: #334155; margin-bottom: 3pt; line-height: 1.3; overflow-wrap: anywhere; }

/* Main */
.main-sec { margin-bottom: 11pt; }
.main-title { font-size: 10.5pt; font-weight: 700; color: #0F172A; letter-spacing: 0.8pt; padding-bottom: 3pt; border-bottom: 1.5pt solid #1E40AF; margin-bottom: 7pt; }
.main-text { font-size: 10pt; color: #1E293B; line-height: 1.45; }
.main-list { list-style: none; padding: 0; margin: 3pt 0 0 0; }
.main-list li { font-size: 9.5pt; color: #1E293B; margin-bottom: 2pt; padding-left: 11pt; position: relative; line-height: 1.4; }
.main-list li::before { content: "▸"; color: #1E40AF; position: absolute; left: 0; top: 0; font-weight: 700; }

/* Experience/education entries — role inteira numa linha (pode quebrar
   se MUITO longa), depois subtitle compacto. Sem flex space-between
   que cria wrap catastrófico em coluna estreita. page-break-inside:
   avoid mantém entrada inteira numa página (sem órfãos). */
.exp { margin-bottom: 8pt; page-break-inside: avoid; }
.exp-role { font-size: 10.5pt; font-weight: 700; color: #0F172A; line-height: 1.25; }
.exp-sub { font-size: 9pt; color: #1E40AF; font-weight: 600; margin-top: 1pt; line-height: 1.3; }
.edu-det { font-size: 9pt; color: #475569; margin-top: 2pt; line-height: 1.35; }

/* Mantém o cabeçalho de seção junto com o primeiro item (sem órfã). */
.main-title { page-break-after: avoid; }
${_buildTierOverrideCss(tier)}
${_buildCobaltTierExtraCss(tier)}
</style>
</head>
<body>
  <div class="header">
    <div class="name">${_escapeHtml(name.toUpperCase())}</div>
    ${headline.isEmpty ? '' : '<div class="headline">${_escapeHtml(headline)}</div>'}
  </div>
  <table class="layout"><tr>
    <td class="sidebar">$sidebarHtml</td>
    <td class="main">$summaryHtml$expHtml$eduHtml$projHtmlC$awardsHtmlC</td>
  </tr></table>
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
      parts.add(_cleanLinkedinForDisplay(resume.linkedin));
    }
    return parts.join(' | ');
  }
}
