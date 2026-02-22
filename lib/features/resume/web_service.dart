import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/models.dart';
import 'resume_viewmodel.dart';

class WebService {
  static Future<void> generateAndShareWebLink(
    UserProfile? user,
    ResumeData resume,
    String templateId,
  ) async {
    final htmlContent = _generateHtml(user, resume, templateId);
    final fileName = 'curriculo_web_${user?.name.replaceAll(' ', '_') ?? 'profissional'}.html';

    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$fileName');
      
      await file.writeAsString(htmlContent);

      await Share.shareXFiles(
        [XFile(file.path)],
      );
    } catch (e) {
      print('Error generating Web Link: $e');
      rethrow;
    }
  }

  static String _generateHtml(UserProfile? user, ResumeData resume, String templateId) {
    switch (templateId) {
      case 'clean':
        return _buildCleanHtml(user, resume);
      case 'modern':
        return _buildModernHtml(user, resume);
      case 'creative':
        return _buildCreativeHtml(user, resume);
      case 'executive':
        return _buildExecutiveHtml(user, resume);
      case 'basic':
      default:
        return _buildBasicHtml(user, resume);
    }
  }

  static String _addMetaTags(String content) {
    return content.replaceFirst('<head>', '<head><meta name="viewport" content="width=device-width, initial-scale=1.0">');
  }

  // --- 1. Basic Template ---
  static String _buildBasicHtml(UserProfile? user, ResumeData resume) {
    return _addMetaTags('''
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
      <meta charset="UTF-8">
      <title>Currículo - ${user?.name}</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 20px; }
        h1 { color: #2c3e50; border-bottom: 2px solid #2c3e50; padding-bottom: 10px; }
        h2 { color: #16a085; margin-top: 30px; border-bottom: 1px solid #eee; padding-bottom: 5px; }
        .header { text-align: left; margin-bottom: 40px; }
        .role { font-weight: bold; font-size: 1.1em; color: #2c3e50; }
        .company { color: #16a085; font-style: italic; }
        @media (max-width: 600px) {
          body { padding: 10px; }
          h1 { font-size: 24px; }
        }
      </style>
    </head>
    <body>
      <div class="header">
        <h1>${user?.name.toUpperCase() ?? 'SEU NOME'}</h1>
        <div>Estudante em ${user?.course ?? "Curso"}</div>
        <div>${user?.email ?? "email@exemplo.com"}</div>
      </div>
      ${_buildCommonSections(resume, user)}
    </body>
    </html>
    ''');
  }

  // --- 2. Clean Template ---
  static String _buildCleanHtml(UserProfile? user, ResumeData resume) {
    return _addMetaTags('''
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
      <meta charset="UTF-8">
      <title>Currículo - ${user?.name}</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #000; text-align: center; max-width: 800px; margin: 0 auto; padding: 40px; }
        h1 { font-size: 28px; letter-spacing: 2px; margin-bottom: 5px; }
        h2 { font-size: 14px; font-weight: bold; letter-spacing: 1.5px; margin-top: 30px; text-transform: uppercase; }
        .contact { color: #666; font-size: 12px; margin-bottom: 40px; border-bottom: 1px solid #ccc; padding-bottom: 20px; }
        .section-content { margin-bottom: 20px; }
        ul { list-style-type: none; padding: 0; }
        li { margin-bottom: 5px; }
        @media (max-width: 600px) {
          body { padding: 20px; text-align: left; }
          h1 { text-align: center; }
          .contact { text-align: center; }
        }
      </style>
    </head>
    <body>
      <h1>${user?.name.toUpperCase() ?? 'SEU NOME'}</h1>
      <div class="contact">${user?.email ?? ""} | ${user?.course ?? ""}</div>
      
      <h2>RESUMO PROFISSIONAL</h2>
      <p>${resume.summary}</p>

      <h2>EDUCAÇÃO</h2>
      <p><strong>${user?.course ?? 'Curso'}</strong><br>Universidade/Instituição<br>${user?.semester != null ? '${user!.semester}° semestre' : ''}</p>

      <h2>EXPERIÊNCIA</h2>
      ${resume.experiences.map((e) => '<p><strong>${e.role}</strong> em <em>${e.company}</em><br>${e.description}</p>').join('')}

      <h2>HABILIDADES</h2>
      <p>${resume.skills.join(' • ')}</p>
    </body>
    </html>
    ''');
  }

  // --- 3. Modern Template ---
  static String _buildModernHtml(UserProfile? user, ResumeData resume) {
    return _addMetaTags('''
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
      <meta charset="UTF-8">
      <title>Currículo - ${user?.name}</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; margin: 0; padding: 0; display: flex; min-height: 100vh; }
        .sidebar { background-color: #F3F4F6; width: 30%; color: #333; padding: 30px; box-sizing: border-box; }
        .main { width: 70%; padding: 40px; box-sizing: border-box; }
        h1 { color: #111827; font-size: 28px; margin: 0; }
        h2 { font-size: 14px; font-weight: bold; color: #111827; border-bottom: 2px solid #0F766E; padding-bottom: 5px; margin-top: 20px; }
        .sidebar h3 { font-size: 12px; font-weight: bold; margin-top: 20px; }
        .role { font-weight: bold; }
        .company { color: #0F766E; font-weight: bold; font-size: 0.9em; }
        ul { padding-left: 20px; }
        
        @media (max-width: 768px) {
          body { flex-direction: column; }
          .sidebar { width: 100%; padding: 20px; }
          .main { width: 100%; padding: 20px; }
        }
      </style>
    </head>
    <body>
      <div class="sidebar">
        <div style="font-size: 30px; font-weight: bold; margin-bottom: 20px;">${user?.name.substring(0, 1).toUpperCase() ?? 'U'}</div>
        <h3>CONTATO</h3>
        <p>${user?.email ?? ''}<br>${user?.course ?? ''}</p>
        <h3>HABILIDADES</h3>
        <ul>${resume.skills.map((s) => '<li>$s</li>').join('')}</ul>
        ${(resume.interests.isNotEmpty) ? '<h3>INTERESSES</h3><ul>${resume.interests.map((i) => '<li>$i</li>').join('')}</ul>' : ''}
      </div>
      <div class="main">
        <h1>${user?.name.toUpperCase() ?? 'NOME'}</h1>
        <div style="color: #0F766E; font-weight: bold;">${user?.course ?? 'Curso'}</div>
        
        <h2>RESUMO</h2>
        <p>${resume.summary}</p>

        <h2>EXPERIÊNCIA</h2>
        ${resume.experiences.map((e) => '<div><div class="role">${e.role}</div><div class="company">${e.company}</div><p>${e.description}</p></div>').join('')}

        ${(resume.achievements.isNotEmpty) ? '<h2>PROJETOS ACADÊMICOS</h2><ul>${resume.achievements.map((a) => '<li>$a</li>').join('')}</ul>' : ''}

        <h2>FORMAÇÃO</h2>
        <p><strong>${user?.course ?? 'Curso'}</strong><br>Universidade/Instituição</p>
      </div>
    </body>
    </html>
    ''');
  }

  // --- 4. Creative Template ---
  static String _buildCreativeHtml(UserProfile? user, ResumeData resume) {
    return _addMetaTags('''
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
      <meta charset="UTF-8">
      <title>Currículo - ${user?.name}</title>
      <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; color: #333; margin: 0; }
        .header { background-color: #6366F1; color: white; padding: 40px; text-align: center; }
        h1 { margin: 0; font-size: 36px; }
        h2 { color: #6366F1; font-size: 20px; font-weight: bold; margin-top: 30px; }
        .content { padding: 40px; max-width: 800px; margin: 0 auto; }
        .skill-bar { background-color: #eee; height: 10px; width: 100%; margin-bottom: 10px; border-radius: 5px; overflow: hidden; }
        .skill-fill { background-color: #EC4899; height: 100%; width: 80%; }
        
        @media (max-width: 600px) {
          .header { padding: 20px; }
          .content { padding: 20px; }
          h1 { font-size: 28px; }
        }
      </style>
    </head>
    <body>
      <div class="header">
        <h1>${user?.name ?? 'Nome'}</h1>
        <div>${user?.course ?? 'Curso'}</div>
      </div>
      <div class="content">
        ${(resume.achievements.isNotEmpty) ? '<h2>PROJETOS DESTAQUE</h2><ul>${resume.achievements.map((a) => '<li>$a</li>').join('')}</ul>' : ''}

        <h2>COMPETÊNCIAS</h2>
        ${resume.skills.map((s) => '<div>${s}</div><div class="skill-bar"><div class="skill-fill"></div></div>').join('')}

        <h2>EXPERIÊNCIA</h2>
        ${resume.experiences.map((e) => '<p><strong>${e.role}</strong> | <span style="color:#6366F1">${e.company}</span><br>${e.description}</p>').join('')}
      </div>
    </body>
    </html>
    ''');
  }

  // --- 5. Executive Template ---
  static String _buildExecutiveHtml(UserProfile? user, ResumeData resume) {
    return _addMetaTags('''
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
      <meta charset="UTF-8">
      <title>Currículo - ${user?.name}</title>
      <style>
        body { font-family: 'Times New Roman', Times, serif; color: #000; max-width: 800px; margin: 0 auto; padding: 40px; }
        .header { text-align: center; border-bottom: 1px solid #000; padding-bottom: 20px; margin-bottom: 20px; }
        h1 { font-size: 26px; margin-bottom: 5px; }
        h2 { font-size: 14px; text-decoration: underline; text-transform: uppercase; margin-top: 20px; }
        .exp-header { display: flex; justify-content: space-between; font-weight: bold; }
        
        @media (max-width: 600px) {
          body { padding: 20px; }
          .exp-header { flex-direction: column; }
          .exp-header span { float: none; display: block; }
        }
      </style>
    </head>
    <body>
      <div class="header">
        <h1>${user?.name.toUpperCase() ?? 'NOME'}</h1>
        <div>${user?.email ?? ""} • ${user?.course ?? ""}</div>
      </div>

      <h2>Resumo Profissional</h2>
      <p>${resume.summary}</p>

      <h2>Experiência Profissional</h2>
      ${resume.experiences.map((e) => '''
        <div style="margin-bottom: 15px;">
          <div style="font-weight: bold;">${e.role} <span style="float:right; font-style: italic;">${e.period}</span></div>
          <div>${e.company}</div>
          <p style="text-align: justify;">${e.description}</p>
        </div>
      ''').join('')}

      <h2>Formação Acadêmica</h2>
      <div style="font-weight: bold;">Universidade/Instituição <span style="float:right; font-style: italic;">Conclusão: 202X</span></div>
      <div>${user?.course ?? 'Curso'}</div>
    </body>
    </html>
    ''');
  }

  static String _buildCommonSections(ResumeData resume, UserProfile? user) {
    return '''
      <h2>RESUMO PROFISSIONAL</h2>
      <p>${resume.summary}</p>

      <h2>HABILIDADES</h2>
      <ul>${resume.skills.map((s) => '<li>$s</li>').join('')}</ul>

      <h2>EXPERIÊNCIA</h2>
      ${resume.experiences.map((exp) => '''
        <div class="experience-item">
          <div class="role">${exp.role}</div>
          <div class="company">${exp.company}</div>
          <p>${exp.description}</p>
        </div>
      ''').join('')}

      <h2>FORMAÇÃO</h2>
      <div class="experience-item">
        <div class="role">${user?.course ?? 'Curso'}</div>
        <div class="company">Universidade/Instituição</div>
        <p>${user?.semester != null ? '${user!.semester}° semestre' : 'Semestre'}</p>
      </div>

      ${(resume.interests.isNotEmpty) ? '<h2>INTERESSES</h2><ul>${resume.interests.map((i) => '<li>$i</li>').join('')}</ul>' : ''}
    ''';
  }
}
