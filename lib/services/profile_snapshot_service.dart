// ProfileSnapshotService — leitura unificada das 18 tabelas profile_*.
//
// Fase 2 da migração profile-first: features que antes liam de
// `user_profiles.gamification_data.imported_resume.parsed` / `.raw_text`
// agora carregam um snapshot via este serviço.
//
// Capabilities:
//   • loadSnapshot(userId)  → Future<ProfileSnapshot>
//   • snapshot.toResumeData(userFallback?)  → ResumeData pro template/preview
//   • snapshot.toPseudoText()  → string concatenada pra keyword overlap
//   • snapshot.isEmpty  → true quando nenhuma tabela filha tem dados
//
// Os 13 users históricos sem PDF da backfill terão snapshot.isEmpty=true.
// Features devem renderizar empty state graciosamente — NUNCA crashar.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/models.dart' show ResumeCourse, ResumeLanguage;
import '../features/resume/data/profile_pdf_data_loader.dart'
    show ProfilePdfData;
import '../features/profile/data/repositories/profile_repository_supabase.dart';
import '../features/profile/domain/repositories/profile_repository.dart';
import '../features/profile/domain/entities/entities.dart';
import '../features/resume/resume_viewmodel.dart'
    show ResumeData, ExperienceItem, EducationItem, ToolWithLevel;

class ProfileSnapshot {
  final PersonalInfo? personal;
  final List<Experience> experiences;
  final List<Education> education;
  final List<Skill> skills;
  final List<Language> languages;
  final List<Certification> certifications;
  final List<Project> projects;
  final List<Interest> interests;
  final List<Award> awards;
  final List<Coursework> coursework;

  const ProfileSnapshot({
    this.personal,
    this.experiences = const [],
    this.education = const [],
    this.skills = const [],
    this.languages = const [],
    this.certifications = const [],
    this.projects = const [],
    this.interests = const [],
    this.awards = const [],
    this.coursework = const [],
  });

  /// True quando o user não tem nenhum conteúdo PROFISSIONAL real — só
  /// dados básicos de cadastro (first_name/last_name) não contam. Features
  /// devem mostrar CTA "complete seu perfil" nesse estado em vez de tentar
  /// calcular match score / renderizar PDF.
  ///
  /// Critério intencionalmente estrito: first/last name por si só são
  /// dados de identificação (preenchidos via masking_questions do
  /// onboarding novo), não sinalizam "tem perfil profissional pra
  /// analisar". User precisa de pelo menos um summary/headline OU uma
  /// entrada em experience/education/skills/etc pra match score fazer
  /// sentido.
  bool get isEmpty {
    final hasProfessionalSummary = personal != null &&
        ((personal!.summary?.trim().isNotEmpty ?? false) ||
            (personal!.headline?.trim().isNotEmpty ?? false));
    return !hasProfessionalSummary &&
        experiences.isEmpty &&
        education.isEmpty &&
        skills.isEmpty &&
        languages.isEmpty &&
        certifications.isEmpty &&
        projects.isEmpty &&
        interests.isEmpty &&
        awards.isEmpty &&
        coursework.isEmpty;
  }

  /// True quando o user tem MATERIAL NARRATIVO suficiente pra IA adaptar
  /// um CV pra uma vaga específica. Critério mais estrito que [isEmpty]:
  /// skills/summary isolados NÃO bastam — adaptação reescreve bullets de
  /// experiência/projeto/educação, e sem isso a IA não tem o que
  /// reformular (resultado seria um PDF com nome + 1 skill = vazio).
  ///
  /// Aceita:
  ///   - 1+ experiência (com ou sem bullets — IA pode sintetizar a
  ///     partir do título/empresa/período)
  ///   - 1+ projeto (mesma lógica)
  ///   - 1+ formação com major OU atividades (sinal de "graduação com
  ///     conteúdo descritivo")
  ///   - CV importado via extract-profile (profile_source='imported' OU
  ///     last_extracted_at não-null) — significa que existe raw_text /
  ///     parsed no JSONB legacy pra v1 ler como fallback
  bool get canAdaptCv {
    if (experiences.isNotEmpty) return true;
    if (projects.isNotEmpty) return true;
    final hasEducationWithContent = education.any((e) =>
        e.majors.isNotEmpty ||
        e.minors.isNotEmpty ||
        e.activities.isNotEmpty);
    if (hasEducationWithContent) return true;
    final wasImported = personal != null &&
        ((personal!.profileSource == ProfileSource.imported) ||
            (personal!.profileSource == ProfileSource.mixed) ||
            personal!.lastExtractedAt != null);
    if (wasImported) return true;
    return false;
  }

  /// Constrói um "pseudo-texto" — todo o conteúdo relevante das tabelas
  /// concatenado em uma string única. Substitui o antigo
  /// `imported_resume.raw_text` em features de keyword overlap (match
  /// score Cenário B). Quanto mais conteúdo, melhor o overlap.
  String toPseudoText() {
    final buf = StringBuffer();

    final p = personal;
    if (p != null) {
      if ((p.headline ?? '').trim().isNotEmpty) buf.writeln(p.headline);
      if ((p.summary ?? '').trim().isNotEmpty) buf.writeln(p.summary);
    }

    for (final s in skills) {
      buf.writeln(s.name);
    }

    for (final exp in experiences) {
      if (exp.title.isNotEmpty) buf.writeln(exp.title);
      if (exp.company.isNotEmpty) buf.writeln(exp.company);
      if (exp.location?.isNotEmpty ?? false) buf.writeln(exp.location);
      for (final b in exp.bullets) {
        if (b.text.isNotEmpty) buf.writeln(b.text);
      }
    }

    for (final edu in education) {
      if (edu.institution.isNotEmpty) buf.writeln(edu.institution);
      if ((edu.degree ?? '').isNotEmpty) buf.writeln(edu.degree);
      for (final m in edu.majors) {
        if (m.name.isNotEmpty) buf.writeln(m.name);
      }
      for (final m in edu.minors) {
        if (m.name.isNotEmpty) buf.writeln(m.name);
      }
      for (final a in edu.activities) {
        if (a.text.isNotEmpty) buf.writeln(a.text);
      }
    }

    for (final c in certifications) {
      if (c.name.isNotEmpty) buf.writeln(c.name);
      if ((c.issuer ?? '').isNotEmpty) buf.writeln(c.issuer);
    }

    for (final l in languages) {
      if (l.name.isNotEmpty) buf.writeln(l.name);
    }

    for (final proj in projects) {
      if (proj.name.isNotEmpty) buf.writeln(proj.name);
      if ((proj.description ?? '').isNotEmpty) buf.writeln(proj.description);
      for (final b in proj.bullets) {
        if (b.text.isNotEmpty) buf.writeln(b.text);
      }
    }

    for (final i in interests) {
      if (i.name.isNotEmpty) buf.writeln(i.name);
    }

    for (final a in awards) {
      if (a.name.isNotEmpty) buf.writeln(a.name);
    }

    for (final c in coursework) {
      if (c.name.isNotEmpty) buf.writeln(c.name);
    }

    return buf.toString();
  }

  /// Converte o snapshot em [ResumeData] pra alimentar telas de preview
  /// (tela "Original | Adaptado" da adaptação de CV) e templates de PDF.
  ///
  /// `userFallback` permite fornecer nome/email/phone do `UserProfile`
  /// quando `profile_personal` ainda está parcial (ex: só user_id, sem
  /// first_name preenchido).
  ResumeData toResumeData({
    String? userFallbackName,
    String? userFallbackEmail,
    String? userFallbackPhone,
  }) {
    final p = personal;

    String fullName = p?.fullName ?? '';
    if (fullName.trim().isEmpty) {
      fullName = (userFallbackName ?? '').trim();
    }

    String email = p?.email ?? '';
    if (email.trim().isEmpty) email = (userFallbackEmail ?? '').trim();

    String phone = '';
    final cc = (p?.phoneCountryCode ?? '').trim();
    final number = (p?.phoneNumber ?? '').trim();
    if (cc.isNotEmpty && number.isNotEmpty) {
      phone = '$cc $number';
    } else if (number.isNotEmpty) {
      phone = number;
    }
    if (phone.trim().isEmpty) phone = (userFallbackPhone ?? '').trim();

    final linkedin = p?.linkedinUrl ?? '';
    final location = p?.formattedLocation ?? '';
    final summary = p?.summary ?? '';

    final mappedExperiences = experiences
        .map((e) => ExperienceItem(
              role: e.title,
              company: e.company,
              period: e.formattedPeriod,
              description: e.bullets
                  .map((b) => b.text)
                  .where((t) => t.isNotEmpty)
                  .join('\n'),
              location: e.location ?? '',
            ))
        .toList();

    final mappedEducation = education.map((edu) {
      final majors = edu.majors.map((m) => m.name).where((s) => s.isNotEmpty).toList();
      final minors = edu.minors.map((m) => m.name).where((s) => s.isNotEmpty).toList();
      final activitiesText = edu.activities
          .map((a) => a.text)
          .where((s) => s.isNotEmpty)
          .toList();

      String details = '';
      if (majors.isNotEmpty) {
        details = '${majors.join(', ')} Major';
        if (minors.isNotEmpty) {
          details += ' com ${minors.join(', ')} Minor';
        }
      } else if (minors.isNotEmpty) {
        details = 'Minor em ${minors.join(', ')}';
      }

      final gpaStr = edu.gpa != null
          ? (edu.maxGpa != null
              ? '${edu.gpa}/${edu.maxGpa}'
              : edu.gpa!.toString())
          : '';

      return EducationItem(
        degree: edu.degree ?? '',
        institution: edu.institution,
        period: edu.formattedPeriod,
        details: details,
        location: edu.location ?? '',
        gpa: gpaStr,
        activities: activitiesText,
        honors: activitiesText.join('; '),
      );
    }).toList();

    final mappedLanguages = languages
        .where((l) => l.name.trim().isNotEmpty)
        .map((l) => ResumeLanguage(language: l.name, level: l.proficiencyLabel))
        .toList();

    final mappedCertifications = certifications
        .where((c) => c.name.trim().isNotEmpty)
        .map((c) => ResumeCourse(
              title: c.name,
              institution: c.issuer ?? '',
              period: c.date != null
                  ? '${c.date!.year}'
                  : '',
            ))
        .toList();

    // Prêmios → ResumeData.awards (campo próprio, renderado pela seção
    // "Prêmios e Reconhecimentos" do PdfService), NUNCA achievements — que no
    // PdfService divide a área "Atividades/Projetos" com projetos (mutuamente
    // exclusivos) e não tem seção semântica própria. achievements fica RESERVADO
    // pros CVs adaptados/legados. Projetos → academicProjects. As duas seções
    // são independentes → projetos e prêmios aparecem SIMULTANEAMENTE no PDF.
    // Reusa os mapeadores ÚNICOS de ProfilePdfData (uma só conversão).
    final mappedAwards = awards
        .where((a) => a.name.trim().isNotEmpty)
        .map(ProfilePdfData.mapAward)
        .toList();
    final mappedProjects = projects
        .where(ProfilePdfData.projectHasRenderableText)
        .map(ProfilePdfData.mapProject)
        .toList();

    return ResumeData(
      fullName: fullName,
      email: email,
      phone: phone,
      linkedin: linkedin,
      location: location,
      address: p?.locationStreetAddress ?? '',
      summary: summary,
      skills: skills.map((s) => s.name).where((n) => n.trim().isNotEmpty).toList(),
      tools: const <ToolWithLevel>[],
      experiences: mappedExperiences,
      education: mappedEducation,
      languages: mappedLanguages,
      academicProjects: mappedProjects,
      awards: mappedAwards,
      // achievements RESERVADO p/ CVs adaptados/legados — não recebe prêmios.
      achievements: const <String>[],
      interests:
          interests.map((i) => i.name).where((n) => n.trim().isNotEmpty).toList(),
      courses: mappedCertifications,
    );
  }
}

class ProfileSnapshotService {
  final ProfileRepository _repo;

  ProfileSnapshotService({ProfileRepository? repository})
      : _repo = repository ?? ProfileRepositorySupabase();

  /// Carrega snapshot completo do user em paralelo. Falhas individuais
  /// caem pra lista vazia em vez de quebrar tudo — feature deve renderizar
  /// o que conseguiu.
  Future<ProfileSnapshot> loadSnapshot(String userId) async {
    Future<T> safe<T>(Future<T> future, T fallback) async {
      try {
        return await future;
      } catch (_) {
        return fallback;
      }
    }

    final results = await Future.wait<dynamic>([
      safe(_repo.getPersonal(userId), null),
      safe(_repo.getExperiences(userId), const <Experience>[]),
      safe(_repo.getEducation(userId), const <Education>[]),
      safe(_repo.getSkills(userId), const <Skill>[]),
      safe(_repo.getLanguages(userId), const <Language>[]),
      safe(_repo.getCertifications(userId), const <Certification>[]),
      safe(_repo.getProjects(userId), const <Project>[]),
      safe(_repo.getInterests(userId), const <Interest>[]),
      safe(_repo.getAwards(userId), const <Award>[]),
      safe(_repo.getCoursework(userId), const <Coursework>[]),
    ]);

    return ProfileSnapshot(
      personal: results[0] as PersonalInfo?,
      experiences: (results[1] as List).cast<Experience>(),
      education: (results[2] as List).cast<Education>(),
      skills: (results[3] as List).cast<Skill>(),
      languages: (results[4] as List).cast<Language>(),
      certifications: (results[5] as List).cast<Certification>(),
      projects: (results[6] as List).cast<Project>(),
      interests: (results[7] as List).cast<Interest>(),
      awards: (results[8] as List).cast<Award>(),
      coursework: (results[9] as List).cast<Coursework>(),
    );
  }

  /// Loader ESPECÍFICO do currículo geral (nome explícito: deixa o contrato
  /// claro). Regras:
  ///  • As 9 fontes que ALIMENTAM o currículo (personal, experiences, education,
  ///    skills, languages, certifications, projects, interests, awards) são
  ///    ESTRITAS: se QUALQUER uma falhar, a carga inteira falha (o erro propaga)
  ///    → o caller [GeneralResumeExport.runExport] devolve `failed` e NUNCA gera
  ///    um PDF a partir de dados parciais.
  ///  • coursework é BEST-EFFORT: como NÃO entra no currículo geral (ver o
  ///    contrato em GeneralResumeExport — coursework fica de fora), uma falha na
  ///    sua consulta NÃO pode indisponibilizar o export → cai pra lista vazia.
  ///  • Ausência LEGÍTIMA de dados (consultas OK, listas vazias) continua
  ///    sucesso (snapshot vazio → `empty`, não `failed`).
  /// O [loadSnapshot] best-effort acima segue intacto pros outros consumidores.
  Future<ProfileSnapshot> loadGeneralResumeSnapshot(String userId) async {
    // coursework NÃO alimenta o currículo → tolera falha (nunca propaga).
    Future<List<Coursework>> courseworkBestEffort() async {
      try {
        return await _repo.getCoursework(userId);
      } catch (_) {
        return const <Coursework>[];
      }
    }

    // As demais SEM wrapper: Future.wait completa com erro se qualquer uma
    // (fonte que É usada no currículo) falhar.
    final results = await Future.wait<dynamic>([
      _repo.getPersonal(userId),
      _repo.getExperiences(userId),
      _repo.getEducation(userId),
      _repo.getSkills(userId),
      _repo.getLanguages(userId),
      _repo.getCertifications(userId),
      _repo.getProjects(userId),
      _repo.getInterests(userId),
      _repo.getAwards(userId),
      courseworkBestEffort(),
    ]);

    return ProfileSnapshot(
      personal: results[0] as PersonalInfo?,
      experiences: (results[1] as List).cast<Experience>(),
      education: (results[2] as List).cast<Education>(),
      skills: (results[3] as List).cast<Skill>(),
      languages: (results[4] as List).cast<Language>(),
      certifications: (results[5] as List).cast<Certification>(),
      projects: (results[6] as List).cast<Project>(),
      interests: (results[7] as List).cast<Interest>(),
      awards: (results[8] as List).cast<Award>(),
      coursework: (results[9] as List).cast<Coursework>(),
    );
  }

  /// Atalho: carrega snapshot do user autenticado atual. Retorna null se
  /// não há sessão.
  Future<ProfileSnapshot?> loadCurrent() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;
    return loadSnapshot(userId);
  }
}
