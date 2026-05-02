import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'resume_viewmodel.dart';
import '../../data/models/models.dart';

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

  static Future<Uint8List> generateResumeBytes(
    UserProfile? user,
    ResumeData resume,
    String templateId,
  ) async {
    print('DEBUG: PdfService.generateResumeBytes START');
    if (templateId == 'harvard_ats') {
      return await Printing.convertHtml(
        html: _buildHarvardMcsHtml(user, resume),
        format: PdfPageFormat.a4,
      );
    }
    try {
      final pdf = pw.Document();
      
      final fontRegular = await PdfGoogleFonts.openSansRegular();
      final fontBold = await PdfGoogleFonts.openSansBold();
      final fontItalic = await PdfGoogleFonts.openSansItalic();

      final fontSerif = await PdfGoogleFonts.merriweatherRegular();
      final fontSerifBold = await PdfGoogleFonts.merriweatherBold();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: templateId == 'quickcv' 
              ? const pw.EdgeInsets.symmetric(horizontal: 72, vertical: 40)
              : (templateId == 'modern' ? const pw.EdgeInsets.all(0) : const pw.EdgeInsets.all(40)),
          theme: pw.ThemeData.withFont(
            base: fontRegular,
            bold: fontBold,
            italic: fontItalic,
          ),
          build: (context) {
            switch (templateId) {
              case 'clean':
                return [_buildCleanLayout(user, resume, fontRegular, fontBold)];
              case 'modern':
                return [_buildModernLayout(user, resume, fontRegular, fontBold)];
              case 'creative':
                return [_buildCreativeLayout(user, resume, fontRegular, fontBold)];
              case 'executive':
                return [_buildExecutiveLayout(user, resume, fontSerif, fontSerifBold)];
              case 'quickcv':
                return _buildQuickCvLayout(user, resume, fontRegular, fontBold);
              default:
                return [_buildBasicLayout(user, resume, fontRegular, fontBold)];
            }
          },
        ),
      );

      return await pdf.save();
    } catch (e, stack) {
      print('CRITICAL ERROR in generateResumeBytes: $e\n$stack');
      rethrow;
    }
  }

  // --- 1. Basic Template ---
  static pw.Widget _buildBasicLayout(UserProfile? user, ResumeData resume, pw.Font regular, pw.Font bold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // HEADER
        pw.Text(
          user?.name.toUpperCase() ?? 'SEU NOME',
          style: pw.TextStyle(fontSize: 24, font: bold, fontWeight: pw.FontWeight.bold),
        ),

        pw.SizedBox(height: 2),
        pw.Text(
          'Estudante em ${user?.course ?? "Curso"}',
          style: const pw.TextStyle(fontSize: 14, color: PdfColors.green700),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          '${resume.email} • ${resume.phone} • ${resume.location}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        if (resume.linkedin.isNotEmpty)
          pw.Text(resume.linkedin, style: const pw.TextStyle(fontSize: 10, color: PdfColors.blue700)),

        pw.SizedBox(height: 16),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 16),

        // SUMMARY
        _buildSectionTitle('RESUMO PROFISSIONAL', bold),
        pw.Text(resume.summary.isNotEmpty ? resume.summary : 'Resumo não preenchido.', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 12),

        // SKILLS
        if (resume.skills.isNotEmpty) ...[
          _buildSectionTitle('HABILIDADES', bold),
          pw.Wrap(
            spacing: 6,
            runSpacing: 4,
            children: resume.skills.map((s) => pw.Text('• $s', style: const pw.TextStyle(fontSize: 10))).toList(),
          ),
          pw.SizedBox(height: 12),
        ],

        // EXPERIENCE
        if (resume.experiences.isNotEmpty) ...[
          _buildSectionTitle('EXPERIÊNCIA PROFISSIONAL', bold),
          _buildExperienceList(resume.experiences, bold, regular),
          pw.SizedBox(height: 12),
        ],

        // ACADEMIC PROJECTS (NEW)
        if (resume.academicProjects.isNotEmpty) ...[
          _buildSectionTitle('PROJETOS', bold),
          _buildProjectList(resume.academicProjects, bold, regular),
           pw.SizedBox(height: 12),
        ],

        // LEADERSHIP (NEW)
        if (resume.leadership.isNotEmpty) ...[
          _buildSectionTitle('LIDERANÇA & EXTRACURRICULAR', bold),
          _buildLeadershipList(resume.leadership, bold, regular),
           pw.SizedBox(height: 12),
        ],

        // EDUCATION
        _buildSectionTitle('FORMAÇÃO ACADÊMICA', bold),
        _buildEducation(resume.education, bold, regular),
        pw.SizedBox(height: 12),

        // COURSES
        if (resume.courses.isNotEmpty) ...[
          _buildSectionTitle('CURSOS & CERTIFICAÇÕES', bold),
          _buildCourses(resume.courses, bold, regular),
          pw.SizedBox(height: 12),
        ],

        // LANGUAGES (NEW)
        if (resume.languages.isNotEmpty) ...[
          _buildSectionTitle('IDIOMAS', bold),
          _buildLanguages(resume.languages, bold, regular),
          pw.SizedBox(height: 12),
        ],

        // AWARDS (NEW)
         if (resume.awards.isNotEmpty) ...[
          _buildSectionTitle('PRÊMIOS & RECONHECIMENTOS', bold),
          _buildAwards(resume.awards, bold, regular),
          pw.SizedBox(height: 12),
        ],
      ],
    );
  }

  // --- 2. Clean Template ---
  static pw.Widget _buildCleanLayout(UserProfile? user, ResumeData resume, pw.Font regular, pw.Font bold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          user?.name.toUpperCase() ?? 'SEU NOME',
          style: pw.TextStyle(fontSize: 26, font: bold, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          '${resume.email} | ${resume.phone} | ${resume.location}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
        if (resume.linkedin.isNotEmpty)
           pw.Text(resume.linkedin, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
        
        pw.Divider(height: 30, thickness: 0.5),

        _buildCleanSection('RESUMO', resume.summary, bold),
        
        if (resume.skills.isNotEmpty)
          _buildCleanSection('COMPETÊNCIAS', null, bold, customContent: pw.Wrap(
            alignment: pw.WrapAlignment.center,
            spacing: 12,
            children: resume.skills.map((s) => pw.Text(s.toUpperCase(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800))).toList(),
          )),

        if (resume.experiences.isNotEmpty)
          _buildCleanSection('EXPERIÊNCIA', null, bold, customContent: _buildExperienceList(resume.experiences, bold, regular, centered: true)),

        if (resume.education.isNotEmpty)
          _buildCleanSection('FORMAÇÃO', null, bold, customContent: _buildEducation(resume.education, bold, regular, centered: true)),

        if (resume.academicProjects.isNotEmpty)
           _buildCleanSection('PROJETOS', null, bold, customContent: _buildProjectList(resume.academicProjects, bold, regular, centered: true)),

      ],
    );
  }

  // --- 3. Modern Template (Replaces old Logic) ---
  static pw.Widget _buildModernLayout(UserProfile? user, ResumeData resume, pw.Font regular, pw.Font bold) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Sidebar (Left)
        pw.Container(
          width: 170,
          padding: const pw.EdgeInsets.only(right: 20, top: 0, bottom: 20),
          decoration: const pw.BoxDecoration(
             border: pw.Border(right: pw.BorderSide(color: PdfColors.grey300, width: 0.5))
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Contact
              pw.Text('CONTATO', style: pw.TextStyle(fontSize: 10, font: bold, color: const PdfColor.fromInt(0xFF1F2937))),
              pw.SizedBox(height: 6),
              pw.Text(resume.email, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.Text(resume.phone, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.Text(resume.location, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              if(resume.linkedin.isNotEmpty)
                pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text(resume.linkedin, style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue800))),
              
              pw.SizedBox(height: 24),

              // Education (Sidebar placement for Modern)
              pw.Text('FORMAÇÃO', style: pw.TextStyle(fontSize: 10, font: bold, color: const PdfColor.fromInt(0xFF1F2937))),
              pw.SizedBox(height: 6),
              ...resume.education.map((e) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(e.degree, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.Text(e.institution, style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(e.period, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              )),

              pw.SizedBox(height: 24),

              // Skills
              pw.Text('HABILIDADES', style: pw.TextStyle(fontSize: 10, font: bold, color: const PdfColor.fromInt(0xFF1F2937))),
              pw.SizedBox(height: 6),
              pw.Wrap(
                spacing: 4, runSpacing: 4,
                children: resume.skills.map((s) => pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE5E7EB), borderRadius: pw.BorderRadius.all(pw.Radius.circular(2))),
                  child: pw.Text(s, style: const pw.TextStyle(fontSize: 8))
                )).toList()
              ),

              pw.SizedBox(height: 24),

              // Languages
              if (resume.languages.isNotEmpty) ...[
                pw.Text('IDIOMAS', style: pw.TextStyle(fontSize: 10, font: bold, color: const PdfColor.fromInt(0xFF1F2937))),
                pw.SizedBox(height: 6),
                 ...resume.languages.map((l) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(l.language, style: const pw.TextStyle(fontSize: 9)),
                      pw.Text(l.level, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    ],
                  )
                 )),
              ],
            ],
          ),
        ),

        // Main Content (Right)
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(left: 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  user?.name.toUpperCase() ?? 'NOME',
                  style: pw.TextStyle(fontSize: 30, font: bold, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF111827))
                ),
                pw.Text(
                   user?.course ?? 'Estudante',
                   style: const pw.TextStyle(fontSize: 14, color: PdfColor.fromInt(0xFF059669)) // Emerald 600
                ),
                pw.SizedBox(height: 24),

                _buildModernSection('RESUMO PROFISSIONAL', resume.summary, bold),
                
                if (resume.experiences.isNotEmpty)
                  _buildModernSection('EXPERIÊNCIA', null, bold, customContent: _buildExperienceList(resume.experiences, bold, regular)),

                if (resume.leadership.isNotEmpty)
                  _buildModernSection('LIDERANÇA', null, bold, customContent: _buildLeadershipList(resume.leadership, bold, regular)),

                if (resume.academicProjects.isNotEmpty)
                  _buildModernSection('PROJETOS', null, bold, customContent: _buildProjectList(resume.academicProjects, bold, regular)),

                if (resume.courses.isNotEmpty)
                  _buildModernSection('CURSOS', null, bold, customContent: _buildCourses(resume.courses, bold, regular)),

                 if (resume.awards.isNotEmpty)
                  _buildModernSection('RECONHECIMENTOS', null, bold, customContent: _buildAwards(resume.awards, bold, regular)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- 4. Creative Template ---
  static pw.Widget _buildCreativeLayout(UserProfile? user, ResumeData resume, pw.Font regular, pw.Font bold) {
    return pw.Column(
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(32),
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6366F1), borderRadius: pw.BorderRadius.only(bottomRight: pw.Radius.circular(60))),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(user?.name ?? 'Nome', style: pw.TextStyle(fontSize: 36, font: bold, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              pw.Text(user?.course ?? 'Curso', style: const pw.TextStyle(fontSize: 18, color: PdfColors.white)),
            ],
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(32),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (resume.achievements.isNotEmpty) ...[
                 _buildCreativeSection('PROJETOS DESTAQUE', null, bold, customContent: pw.Column(
                    children: resume.achievements.map((a) => pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: const PdfColor.fromInt(0xFFEEF2FF),
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: const PdfColor.fromInt(0xFFC7D2FE)),
                      ),
                      child: pw.Row(
                        children: [
                          pw.PdfLogo(),
                          pw.SizedBox(width: 12),
                          pw.Expanded(child: pw.Text(a, style: const pw.TextStyle(fontSize: 12, color: PdfColor.fromInt(0xFF4338CA)))),
                        ],
                      ),
                    )).toList(),
                 )),
                 pw.SizedBox(height: 20),
              ],
              
              if (resume.skills.isNotEmpty) ...[
                 _buildCreativeSection('COMPETÊNCIAS', null, bold, customContent: pw.Column(
                children: resume.skills.map((s) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Row(
                    children: [
                      pw.Expanded(flex: 3, child: pw.Text(s, style: pw.TextStyle(fontSize: 12, font: bold, fontWeight: pw.FontWeight.bold))),
                      pw.Expanded(flex: 4, child: pw.Container(
                        height: 6,
                        decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(3)),
                        child: pw.Stack(
                          children: [
                            pw.Container(
                              width: 80,
                              decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFEC4899), borderRadius: pw.BorderRadius.circular(3)),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                )).toList(),
              )),
              pw.SizedBox(height: 20),
              ],

              if (resume.experiences.isNotEmpty)
                  _buildCreativeSection('EXPERIÊNCIA', null, bold, customContent: _buildExperienceList(resume.experiences, bold, regular)),
              
              if (resume.academicProjects.isNotEmpty)
                 _buildCreativeSection('PROJETOS', null, bold, customContent: _buildProjectList(resume.academicProjects, bold, regular)),
                
               if (resume.leadership.isNotEmpty)
                 _buildCreativeSection('LIDERANÇA', null, bold, customContent: _buildLeadershipList(resume.leadership, bold, regular)),

              if (resume.languages.isNotEmpty)
                 _buildCreativeSection('IDIOMAS', null, bold, customContent: _buildLanguages(resume.languages, bold, regular)),

               if (resume.awards.isNotEmpty)
                 _buildCreativeSection('RECONHECIMENTOS', null, bold, customContent: _buildAwards(resume.awards, bold, regular)),
            ],
          ),
        ),
      ],
    );
  }

  // --- 5. Executive Template ---
  static pw.Widget _buildExecutiveLayout(UserProfile? user, ResumeData resume, pw.Font serif, pw.Font serifBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(user?.name.toUpperCase() ?? 'NOME', style: pw.TextStyle(font: serifBold, fontSize: 26, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('${user?.email ?? ""} • ${user?.course ?? ""}', style: pw.TextStyle(font: serif, fontSize: 12)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Divider(thickness: 1, color: PdfColors.black),
        pw.SizedBox(height: 20),
        _buildExecutiveSection('RESUMO PROFISSIONAL', resume.summary, serif, serifBold),
        if (resume.experiences.isNotEmpty)
            _buildExecutiveSection('EXPERIÊNCIA PROFISSIONAL', null, serif, serifBold, customContent: _buildExperienceList(resume.experiences, serifBold, serif)),
        if (resume.leadership.isNotEmpty)
            _buildExecutiveSection('LIDERANÇA', null, serif, serifBold, customContent: _buildLeadershipList(resume.leadership, serifBold, serif)),
        if (resume.academicProjects.isNotEmpty)
            _buildExecutiveSection('PROJETOS', null, serif, serifBold, customContent: _buildProjectList(resume.academicProjects, serifBold, serif)),
        _buildExecutiveSection('FORMAÇÃO ACADÊMICA', null, serif, serifBold, customContent: _buildEducation(resume.education, serifBold, serif)),
      ],
    );
  }

  // --- Helpers & Component Builders ---
  
  static pw.Widget _buildSectionTitle(String title, pw.Font bold) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey900, width: 0.5))),
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Text(title, style: pw.TextStyle(fontSize: 11, font: bold, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5)),
      ),
    );
  }

  // Unified Clean Section
  static pw.Widget _buildCleanSection(String title, String? content, pw.Font bold, {pw.Widget? customContent}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Column(
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10, font: bold, fontWeight: pw.FontWeight.bold, letterSpacing: 1.0, color: PdfColors.grey800)),
          pw.SizedBox(height: 6),
          if (content != null) pw.Text(content, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.2)),
          if (customContent != null) customContent,
        ],
      ),
    );
  }

  // Unified Modern Section
  static pw.Widget _buildModernSection(String title, String? content, pw.Font bold, {pw.Widget? customContent}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 18),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 11, font: bold, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF1F2937))), // Gray 800
          pw.SizedBox(height: 6),
          if (content != null) pw.Text(content, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.2, color: PdfColors.grey800)),
          if (customContent != null) customContent,
        ],
      ),
    );
  }

  static pw.Widget _buildCreativeSection(String title, String? content, pw.Font bold, {pw.Widget? customContent}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 18, font: bold, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF6366F1))),
        pw.SizedBox(height: 8),
        if (content != null) pw.Text(content, style: const pw.TextStyle(fontSize: 12)),
        if (customContent != null) customContent,
      ],
    );
  }

  static pw.Widget _buildExecutiveSection(String title, String? content, pw.Font regular, pw.Font bold, {pw.Widget? customContent}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 12, decoration: pw.TextDecoration.underline, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (content != null) pw.Text(content, style: pw.TextStyle(font: regular, fontSize: 11)),
          if (customContent != null) customContent,
        ],
      ),
    );
  }


  // --- Content List Builders ---

  static pw.Widget _buildExperienceList(List<ExperienceItem> experiences, pw.Font bold, pw.Font regular, {bool centered = false}) {
    return pw.Column(
      children: experiences.map((exp) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(
          crossAxisAlignment: centered ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: centered ? pw.MainAxisAlignment.center : pw.MainAxisAlignment.spaceBetween,
              children: [
                 pw.Expanded(child: pw.Text(exp.role, style: pw.TextStyle(fontSize: 11, font: bold, fontWeight: pw.FontWeight.bold), textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left)),
                 if (!centered) pw.Text(exp.period, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 1),
            pw.Text(exp.company, style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF059669), fontWeight: pw.FontWeight.bold)), 
            pw.SizedBox(height: 2),
            pw.Text(exp.description, textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1)),
            if (centered) pw.Text(exp.period, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
          ],
        ),
      )).toList(),
    );
  }

  static pw.Widget _buildProjectList(List<ResumeProject> projects, pw.Font bold, pw.Font regular, {bool centered = false}) {
    return pw.Column(
      children: projects.map((proj) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: centered ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
          children: [
            pw.Text(proj.title, style: pw.TextStyle(fontSize: 11, font: bold)),
            pw.Text('${proj.role} • ${proj.period}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 1),
            pw.Text(proj.description, textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      )).toList(),
    );
  }

  static pw.Widget _buildLeadershipList(List<ResumeLeadership> leadership, pw.Font bold, pw.Font regular) {
    return pw.Column(
      children: leadership.map((lead) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
             pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(lead.role, style: pw.TextStyle(fontSize: 11, font: bold)),
                pw.Text(lead.period, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ],
            ),
            pw.Text('${lead.organization} • ${lead.location}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
            pw.SizedBox(height: 2),
            pw.Text(lead.description, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      )).toList(),
    );
  }

  static pw.Widget _buildEducation(List<EducationItem> education, pw.Font bold, pw.Font regular, {bool centered = false}) {
    return pw.Column(
      children: education.map((edu) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: centered ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
          children: [
            pw.Text(edu.degree, style: pw.TextStyle(fontSize: 11, font: bold)),
            pw.Text(edu.institution, style: const pw.TextStyle(fontSize: 10)),
            pw.Text(
              '${edu.period}${edu.details.isNotEmpty ? ' • ${edu.details}' : ''}',
              textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)
            ),
          ],
        ),
      )).toList(),
    );
  }

  static pw.Widget _buildCourses(List<ResumeCourse> courses, pw.Font bold, pw.Font regular, {bool centered = false}) {
     return pw.Column(
      children: courses.map((c) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: centered ? pw.MainAxisAlignment.center : pw.MainAxisAlignment.start,
          children: [
             if(!centered) pw.Container(width: 3, height: 3, margin: const pw.EdgeInsets.only(top: 5, right: 6), decoration: const pw.BoxDecoration(color: PdfColors.black, shape: pw.BoxShape.circle)),
             pw.Expanded(
               child: pw.RichText(
                 textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left,
                 text: pw.TextSpan(
                   children: [
                     pw.TextSpan(text: c.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                     pw.TextSpan(text: ' - ${c.institution}', style: const pw.TextStyle(fontSize: 10)),
                     if (c.period.isNotEmpty) pw.TextSpan(text: ' (${c.period})', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                   ]
                 )
               )
             )
          ]
        )
      )).toList(),
    );
  }

  static pw.Widget _buildLanguages(List<ResumeLanguage> languages, pw.Font bold, pw.Font regular) {
    return pw.Wrap(
      spacing: 12,
      runSpacing: 4,
      children: languages.map((l) => pw.RichText(
        text: pw.TextSpan(
          children: [
             pw.TextSpan(text: '${l.language}: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
             pw.TextSpan(text: l.level, style: const pw.TextStyle(fontSize: 10)),
          ]
        )
      )).toList(),
    );
  }

  static pw.Widget _buildAwards(List<ResumeAward> awards, pw.Font bold, pw.Font regular) {
    return pw.Column(
      children: awards.map((a) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(a.title, style: pw.TextStyle(fontSize: 10, font: bold)),
            pw.Text('${a.institution} • ${a.date}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        )
      )).toList(),
    );
  }


  // --- 6. Quick CV Template (Maya Davis Style) ---
  static List<pw.Widget> _buildQuickCvLayout(UserProfile? user, ResumeData resume, pw.Font regular, pw.Font bold) {
    // Define colors
    const primaryColor = PdfColor.fromInt(0xFF355C7D);
    const accentColor = PdfColor.fromInt(0xFFDCE4E8);
    const textColor = PdfColor.fromInt(0xFF343B41);
    const subTextColor = PdfColor.fromInt(0xFF7A7E83);

    // Safe strings
    final name = user?.name ?? 'SEU NOME';
    final course = user?.course ?? 'Curso';
    final linkedin = resume.linkedin.isEmpty ? '' : resume.linkedin.replaceAll('https://', '');

    return [
      // Header (No Padding wrapper needed, handled by page margin)
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Text(
            name,
            style: pw.TextStyle(
              fontSize: 30, // Slightly smaller than screen to fit PDF better
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
              font: bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            course,
            style: pw.TextStyle(
              fontSize: 14,
              fontStyle: pw.FontStyle.italic,
              color: primaryColor,
              font: regular, // Italic font passed as regular if needed, or use bold for contrast
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _buildQuickCvContactItem(resume.email, primaryColor, regular),
              _buildQuickCvContactItem(resume.phone, primaryColor, regular),
              _buildQuickCvContactItem(linkedin, primaryColor, regular),
              _buildQuickCvContactItem(resume.location, primaryColor, regular),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(color: primaryColor, thickness: 1.5),
          pw.SizedBox(height: 20),
        ],
      ),
      // Use Partitions directly 
      _buildQuickCvBalancedLayout(user, resume, regular, bold, primaryColor, textColor, subTextColor),
    ];
  }

  static pw.Widget _buildQuickCvContactItem(String text, PdfColor color, pw.Font font) {
    if (text.isEmpty) return pw.SizedBox.shrink();
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        // Using a bullet instead of icon for simplicity/performance in PDF unless we load icons
        pw.Container(width: 4, height: 4, decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle)),
        pw.SizedBox(width: 4),
        pw.Text(
          text,
          style: pw.TextStyle(fontSize: 10, color: const PdfColor.fromInt(0xFF13191D), font: font),
        ),
      ],
    );
  }

  static pw.Widget _buildQuickCvSectionHeader(String title, PdfColor color, pw.Font font, {String? svgIcon}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
             if (svgIcon != null) ...[
               pw.SvgImage(
                 svg: '<svg viewBox="0 0 24 24"><path d="$svgIcon" fill="#455A64"/></svg>',
                 width: 11,
                 height: 11
               ),
               pw.SizedBox(width: 6),
             ],
             pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: color,
                letterSpacing: 0.5,
                font: font
              ),
            ),
          ]
        ),
        pw.SizedBox(height: 3),
        pw.Container(width: double.infinity, height: 1, color: color),
      ],
    );
  }

  // --- ROBUST BALANCED LAYOUT (Fixes invisible content & Adds Icons) ---
  static pw.Widget _buildQuickCvBalancedLayout(
      UserProfile? user, ResumeData resume, pw.Font regular, pw.Font bold,
      PdfColor primaryColor, PdfColor textColor, PdfColor subTextColor) {
    print('DEBUG: _buildQuickCvBalancedLayout called');
    print('DEBUG: Summary length: ${resume.summary.length}');
    print('DEBUG: Education count: ${resume.education.length}');
    print('DEBUG: Experience count: ${resume.experiences.length}');
    print('DEBUG: Projects count: ${resume.academicProjects.length}');
    print('DEBUG: Skills count: ${resume.skills.length}');
    
    const accentColor = PdfColor.fromInt(0xFFDCE4E8);
    
    // Icons (Material Design Paths)
    const iconSummary = 'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z';
    const iconEdu = 'M5 13.18v4L12 21l7-3.82v-4L12 17l-7-3.82zM12 3L1 9l11 6 9-4.91V17h2V9L12 3z';
    const iconExp = 'M20 6h-4V4c0-1.11-.89-2-2-2h-4c-1.11 0-2 .89-2 2v2H4c-1.11 0-1.99.89-1.99 2L2 19c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-6 0h-4V4h4v2z';
    const iconProj = 'M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z';
    const iconSkills = 'M9 21c0 .55.45 1 1 1h4c.55 0 1-.45 1-1v-1H9v1zm3-19C8.14 2 5 5.14 5 9c0 2.38 1.19 4.47 3 5.74V17c0 .55.45 1 1 1h6c.55 0 1-.45 1-1v-2.26c1.81-1.27 3-3.36 3-5.74 0-3.86-3.14-7-7-7z';
    const iconLang = 'M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zm6.93 6h-2.95c-.32-1.25-.78-2.45-1.38-3.56 1.84.63 3.37 1.91 4.33 3.56z';
    const iconCourses = 'M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2z';
    const iconAwards = 'M20.2 2H3.8c-1.1 0-2 .9-2 2v6c0 3.3 2.7 6 6 6h1.4c1.1 2 3.3 3.4 5.8 3.8V22H9v-2h6v2h-2v-2.2c2.5-.5 4.7-1.8 5.8-3.8H20c3.3 0 6-2.7 6-6V4c0-1.1-.9-2-2-2z';
    const iconInterests = 'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z';

    return pw.Partitions(
      children: [
        // 1. LEFT COLUMN CONTENT (Flex: 2)
        pw.Partition(
          flex: 2, 
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Summary
              if (resume.summary.isNotEmpty) ...[
                 _buildQuickCvSectionHeader('RESUMO PROFISSIONAL', primaryColor, bold, svgIcon: iconSummary),

                 pw.SizedBox(height: 6),
                 pw.Text(resume.summary, style: pw.TextStyle(fontSize: 10, font: regular, color: textColor, lineSpacing: 1.2)),
                 pw.SizedBox(height: 16),
              ],

              // Education
              if (resume.education.isNotEmpty) ...[
                 _buildQuickCvSectionHeader('FORMAÇÃO', primaryColor, bold, svgIcon: iconEdu),
                 ...resume.education.map((edu) => pw.Padding(
                   padding: const pw.EdgeInsets.only(top: 8),
                   child: pw.Column(
                     crossAxisAlignment: pw.CrossAxisAlignment.start,
                     children: [
                       pw.Text(edu.degree, style: pw.TextStyle(fontSize: 11, font: bold, color: textColor)),
                       pw.Text(edu.institution, style: pw.TextStyle(fontSize: 10, font: regular, color: subTextColor, fontStyle: pw.FontStyle.italic)),
                       pw.Text(edu.period, style: pw.TextStyle(fontSize: 10, font: regular, color: subTextColor, fontStyle: pw.FontStyle.italic)),
                       if (edu.details.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(edu.details, style: pw.TextStyle(fontSize: 9, font: regular, color: textColor)),
                       ]
                     ],
                   ),
                 )),
                 pw.SizedBox(height: 16),
              ],

              // Experience
              if (resume.experiences.isNotEmpty) ...[
                 _buildQuickCvSectionHeader('EXPERIÊNCIA PROFISSIONAL', primaryColor, bold, svgIcon: iconExp),
                 ...resume.experiences.map((exp) => pw.Padding(
                   padding: const pw.EdgeInsets.only(top: 8),
                   child: pw.Column(
                     crossAxisAlignment: pw.CrossAxisAlignment.start,
                     children: [
                       pw.Text(exp.role, style: pw.TextStyle(fontSize: 11, font: bold, color: textColor)),
                       pw.Text(exp.company, style: pw.TextStyle(fontSize: 10, font: regular, color: subTextColor, fontStyle: pw.FontStyle.italic)),
                       pw.Text(exp.period, style: pw.TextStyle(fontSize: 10, font: regular, color: subTextColor, fontStyle: pw.FontStyle.italic)),
                       pw.SizedBox(height: 2),
                       pw.Text(exp.description, style: pw.TextStyle(fontSize: 10, font: regular, color: textColor)),
                     ],
                   ),
                 )),
                 pw.SizedBox(height: 16),
              ],

              // Projects
              if (resume.academicProjects.isNotEmpty) ...[
                 _buildQuickCvSectionHeader('PROJETOS', primaryColor, bold, svgIcon: iconProj),
                 ...resume.academicProjects.map((proj) => pw.Padding(
                   padding: const pw.EdgeInsets.only(top: 8),
                   child: pw.Column(
                     crossAxisAlignment: pw.CrossAxisAlignment.start,
                     children: [
                       pw.Text(proj.title, style: pw.TextStyle(fontSize: 11, font: bold, color: textColor)),
                       pw.Text(proj.role, style: pw.TextStyle(fontSize: 10, font: regular, color: subTextColor)),
                       pw.Text(proj.description, style: pw.TextStyle(fontSize: 10, font: regular, color: textColor)),
                     ],
                   ),
                 )),
                 pw.SizedBox(height: 16),
              ],
            ],
          ),
        ),

        // 2. RIGHT COLUMN CONTENT (Flex: 1)       
        pw.Partition(
          flex: 1,
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(left: 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Skills
                if (resume.skills.isNotEmpty) ...[
                   _buildQuickCvSectionHeader('HABILIDADES', primaryColor, bold, svgIcon: iconSkills),
                   pw.SizedBox(height: 6),
                   pw.Wrap(
                     spacing: 4, runSpacing: 4,
                     children: resume.skills.map((s) => pw.Container(
                       padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                       decoration: const pw.BoxDecoration(color: accentColor, borderRadius: pw.BorderRadius.all(pw.Radius.circular(2))),
                       child: pw.Text(s, style: pw.TextStyle(fontSize: 8, font: regular, color: textColor)),
                     )).toList(),
                   ),
                   pw.SizedBox(height: 16),
                ],

                // Courses
                if (resume.courses.isNotEmpty) ...[
                   _buildQuickCvSectionHeader('CURSOS E CERTIFICAÇÕES', primaryColor, bold, svgIcon: iconCourses),
                   pw.SizedBox(height: 6),
                   ...resume.courses.map((course) => pw.Padding(
                     padding: const pw.EdgeInsets.only(bottom: 6),
                     child: pw.Column(
                       crossAxisAlignment: pw.CrossAxisAlignment.start,
                       children: [
                         pw.Text(course.title, style: pw.TextStyle(fontSize: 10, font: bold, color: textColor)),
                         pw.Text(course.institution, style: pw.TextStyle(fontSize: 9, font: regular, color: subTextColor, fontStyle: pw.FontStyle.italic)),
                         pw.Text(course.period, style: pw.TextStyle(fontSize: 9, font: regular, color: subTextColor, fontStyle: pw.FontStyle.italic)),
                       ],
                     ),
                   )),
                   pw.SizedBox(height: 16),
                ],

                // Languages
                if (resume.languages.isNotEmpty) ...[
                   _buildQuickCvSectionHeader('IDIOMAS', primaryColor, bold, svgIcon: iconLang),
                   pw.SizedBox(height: 6),
                   pw.Column(
                     crossAxisAlignment: pw.CrossAxisAlignment.start,
                     children: resume.languages.map((l) => pw.Padding(
                       padding: const pw.EdgeInsets.only(bottom: 2),
                       child: pw.Text('${l.language} - ${l.level}', style: pw.TextStyle(fontSize: 9, font: regular, color: textColor)),
                     )).toList(),
                   ),
                   pw.SizedBox(height: 16),
                ],

                // Awards
                if (resume.awards.isNotEmpty) ...[
                   _buildQuickCvSectionHeader('PREMIAÇÕES', primaryColor, bold, svgIcon: iconAwards),
                   ...resume.awards.map((a) => pw.Padding(
                     padding: const pw.EdgeInsets.only(bottom: 4),
                     child: pw.Text(a.title, style: pw.TextStyle(fontSize: 9, font: regular))
                   )),
                ],

                // Interests
                if (resume.interests.isNotEmpty) ...[
                   pw.SizedBox(height: 16),
                   _buildQuickCvSectionHeader('INTERESSES', primaryColor, bold, svgIcon: iconInterests),
                   pw.SizedBox(height: 6),
                   pw.Wrap(
                     spacing: 4, runSpacing: 4,
                     children: resume.interests.map((s) => pw.Container(
                       padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                       decoration: const pw.BoxDecoration(color: accentColor, borderRadius: pw.BorderRadius.all(pw.Radius.circular(2))),
                       child: pw.Text(s, style: pw.TextStyle(fontSize: 8, font: regular, color: textColor)),
                     )).toList(),
                   ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- 7. Harvard MCS Template (HTML → PDF via Printing.convertHtml) ---
  static String _buildHarvardMcsHtml(UserProfile? user, ResumeData resume) {
    final summaryHtml = resume.summary.trim().isNotEmpty
        ? '<div class="sec">Resumo Profissional</div><div class="entry">${_escapeHtml(resume.summary.trim())}</div>'
        : '';

    final eduItems = resume.education
        .map((e) => _buildHarvardEducationItemHtml(e, resume))
        .join('');
    final educationHtml = resume.education.isNotEmpty
        ? '<div class="sec">Educação</div>$eduItems'
        : '';

    final expItems = resume.experiences
        .map((e) => _buildHarvardExperienceItemHtml(e, resume))
        .join('');
    final experienceHtml = resume.experiences.isNotEmpty
        ? '<div class="sec">Experiência</div>$expItems'
        : '';

    final projectItems = resume.academicProjects
        .map((p) => _buildHarvardActivityItemHtml(
              p.title,
              p.location.isNotEmpty ? p.location : resume.location,
              p.role,
              p.period,
              p.description,
            ))
        .join('');
    final leadItems = resume.leadership
        .map((l) => _buildHarvardActivityItemHtml(
              l.organization,
              l.location.isNotEmpty ? l.location : resume.location,
              l.role,
              l.period,
              l.description,
            ))
        .join('');
    final activitiesHtml = (resume.academicProjects.isNotEmpty || resume.leadership.isNotEmpty)
        ? '<div class="sec">Liderança &amp; Atividades</div>$projectItems$leadItems'
        : '';

    final skillParts = <String>[];
    // Harvard MCS order: Technical Skills → Languages → Tools → Certifications
    // Each as its own labeled line (single line per category).

    if (resume.skills.isNotEmpty) {
      final skillsText = resume.skills.join(', ');
      skillParts.add('<div class="sk"><b>Habilidades Técnicas:</b> $skillsText</div>');
    }

    if (resume.languages.isNotEmpty) {
      // Group by level: "Fluente em Inglês e Português; Básico em Espanhol"
      skillParts.add('<div class="sk"><b>Idiomas:</b> ${_buildLanguagesText(resume.languages)}</div>');
    }

    if (resume.tools.isNotEmpty) {
      // Group by level: "Avançado: Excel, PowerPoint; Intermediário: Figma"
      skillParts.add('<div class="sk"><b>Ferramentas:</b> ${_buildToolsText(resume.tools)}</div>');
    }

    if (resume.courses.isNotEmpty) {
      // Format: "Nome - Instituição (Ano)" when fields are populated
      final courseText = resume.courses.map((c) {
        final parts = <String>[c.title];
        if (c.institution.isNotEmpty) parts.add(c.institution);
        var formatted = parts.join(' - ');
        if (c.period.isNotEmpty) formatted = '$formatted (${c.period})';
        return formatted;
      }).join('; ');
      skillParts.add('<div class="sk"><b>Certificações &amp; Programas:</b> $courseText</div>');
    }

    if (resume.interests.isNotEmpty) {
      // Single continuous sentence per Harvard guidelines
      final interestsText = resume.interests.join(', ');
      skillParts.add('<div class="sk"><b>Interesses:</b> $interestsText</div>');
    }

    final skillsContent = skillParts.join('');
    final skillsHtml = skillParts.isNotEmpty
        ? '<div class="sec">Habilidades, Certificações &amp; Interesses</div>$skillsContent'
        : '';

    return '''<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <style>
    @page { size: A4; margin: 0.5in; }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Times New Roman', Times, serif; font-size: 11pt; color: #000; line-height: 1.2; }
    .header { text-align: center; margin-bottom: 5pt; }
    .name { font-weight: bold; font-size: 17pt; letter-spacing: 0.5pt; }
    .address { font-size: 9.5pt; margin-top: 3pt; }
    .contact { font-size: 9.5pt; margin-top: 1pt; }
    hr { border: none; border-top: 1px solid #000; margin: 5pt 0 10pt; }
    .sec { text-align: center; font-weight: bold; font-size: 11pt; margin: 10pt 0 4pt; }
    .row { display: flex; justify-content: space-between; font-size: 11pt; }
    .row .r { white-space: nowrap; margin-left: 8pt; }
    .bold .l { font-weight: bold; }
    .italic .l { font-style: italic; }
    .italic .r { font-style: italic; }
    .entry { margin-bottom: 6pt; }
    ul { margin: 3pt 0 0 16pt; }
    li { font-size: 11pt; margin-bottom: 1pt; }
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
  <hr>
  $summaryHtml
  $educationHtml
  $experienceHtml
  $activitiesHtml
  $skillsHtml
</body>
</html>''';
  }

  static String _buildHarvardEducationItemHtml(EducationItem edu, ResumeData resume) {
    final location = edu.location.isNotEmpty ? edu.location : resume.location;
    final detailsHtml = edu.details.isNotEmpty
        ? '<div class="detail">${_escapeHtml(edu.details)}</div>'
        : '';

    // Harvard enrichments — render as bullets when present
    final highlightItems = <String>[];
    if (edu.coursework.isNotEmpty) {
      highlightItems.add('<li><b>Disciplinas relevantes:</b> ${_escapeHtml(edu.coursework)}</li>');
    }
    if (edu.gpa.isNotEmpty) {
      highlightItems.add('<li><b>CR:</b> ${_escapeHtml(edu.gpa)}</li>');
    }
    if (edu.honors.isNotEmpty) {
      highlightItems.add('<li><b>Distinções:</b> ${_escapeHtml(edu.honors)}</li>');
    }
    if (edu.repRole.isNotEmpty) {
      highlightItems.add('<li><b>Cargo representativo:</b> ${_escapeHtml(edu.repRole)}</li>');
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
    String description,
  ) {
    // Top row: Organization (bold) + Location (right). Bottom row: Role (italic) + Period.
    final botRow = (leftBot.isNotEmpty || rightBot.isNotEmpty)
        ? '<div class="row italic"><span class="l">$leftBot</span><span class="r">$rightBot</span></div>'
        : '';
    return '<div class="entry">'
        '<div class="row bold"><span class="l">$leftTop</span><span class="r">$rightTop</span></div>'
        '$botRow'
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
  /// Output: "Fluente em Inglês e Português; Básico em Espanhol"
  static String _buildLanguagesText(List<ResumeLanguage> langs) {
    const order = ['Nativo', 'Fluente', 'Avançado', 'Intermediário', 'Básico'];
    final byLevel = <String, List<String>>{};
    for (final l in langs) {
      final level = l.level.trim().isEmpty ? 'Outro' : l.level.trim();
      byLevel.putIfAbsent(level, () => []).add(l.language);
    }
    final parts = <String>[];
    for (final level in order) {
      final list = byLevel.remove(level);
      if (list != null && list.isNotEmpty) {
        parts.add('$level em ${_joinList(list)}');
      }
    }
    // Catch-all for unrecognized levels
    byLevel.forEach((level, list) {
      parts.add('$level em ${_joinList(list)}');
    });
    return parts.join('; ');
  }

  /// Group tools by proficiency level.
  /// Output: "Avançado: Excel, PowerPoint; Intermediário: Figma; Básico: Python"
  static String _buildToolsText(List<ToolWithLevel> tools) {
    const order = ['Avançado', 'Intermediário', 'Básico'];
    final byLevel = <String, List<String>>{};
    for (final t in tools) {
      final level = t.level.trim().isEmpty ? '' : t.level.trim();
      byLevel.putIfAbsent(level, () => []).add(t.name);
    }
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
    if (resume.phone.isNotEmpty) parts.add('Mobile: ${resume.phone}');
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
