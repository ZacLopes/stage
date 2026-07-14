// Semana 3 — Bloco B: carregador profile-first pra renderização de PDFs.
//
// Lê as 18 tabelas relacionais (`profile_*`) e expõe uma `ProfilePdfData`
// que sabe se converter pra `ResumeData` (o modelo legacy que os
// `_buildXxxHtml` do `PdfService` já consomem).
//
// Por que adapter e NÃO duplicar 4 _buildHtmlV2:
//   Paridade visual = mesma saída HTML quando os dados são iguais. Manter
//   um único conjunto de templates evita drift entre v1/v2 e concentra
//   todo o risco do v2 numa única função (`toResumeData`) que é fácil
//   de validar diff-a-diff.
//
// Fallback ao v1: `load()` retorna `null` quando o perfil estruturado está
// vazio (sem profile_personal, sem experiences, sem education). O renderer
// vê o null e cai pro v1 (`gamification_data` JSONB). Sem isso, user de
// trilha fresca veria PDF vazio em vez do CV importado.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/models.dart';
import '../../profile/domain/entities/entities.dart';
import '../resume_viewmodel.dart' show ResumeData, ExperienceItem;
import 'profile_resume_mapper.dart';

class ProfilePdfData {
  final PersonalInfo personal;
  final List<Experience> experiences;
  final List<Education> education;
  final List<Skill> skills;
  final List<Language> languages;
  final List<Certification> certifications;
  final List<Project> projects;
  final List<Interest> interests;
  final List<Award> awards;

  const ProfilePdfData({
    required this.personal,
    required this.experiences,
    required this.education,
    required this.skills,
    required this.languages,
    required this.certifications,
    required this.projects,
    required this.interests,
    required this.awards,
  });

  /// Carrega o perfil completo do schema relacional. Retorna `null` quando
  /// o perfil estruturado está vazio o suficiente pra que renderizar v2
  /// resulte num PDF inutil — caller deve cair pro v1.
  ///
  /// Critério de "vazio": sem `profile_personal` OU sem nenhuma experience
  /// E nenhuma education. Mesmo critério usado pelo match v2 cenário B
  /// (consistência intencional).
  static Future<ProfilePdfData?> load(String userId) async {
    final client = Supabase.instance.client;
    try {
      // 1. Personal é obrigatório — se não existe, falha rápido pra v1.
      final personalRow = await client
          .from('profile_personal')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (personalRow == null) {
        if (kDebugMode) debugPrint('[ProfilePdfData] no personal → fallback v1');
        return null;
      }
      final personal = PersonalInfo.fromMap(personalRow);

      // 2. Demais tabelas em paralelo. Cada query é independente e RLS
      //    garante user_id = auth.uid().
      final results = await Future.wait([
        client
            .from('profile_experiences')
            .select('*, profile_bullets(*)')
            .eq('user_id', userId)
            .order('order_index', ascending: true),
        client
            .from('profile_education')
            .select('*, profile_education_majors(*), profile_education_minors(*), profile_education_activities(*)')
            .eq('user_id', userId)
            .order('order_index', ascending: true),
        client.from('profile_skills').select().eq('user_id', userId).order('order_index', ascending: true),
        client.from('profile_languages').select().eq('user_id', userId).order('order_index', ascending: true),
        client.from('profile_certifications').select().eq('user_id', userId).order('order_index', ascending: true),
        client
            .from('profile_projects')
            .select('*, profile_project_bullets(*)')
            .eq('user_id', userId)
            .order('order_index', ascending: true),
        client.from('profile_interests').select().eq('user_id', userId).order('order_index', ascending: true),
        client.from('profile_awards').select().eq('user_id', userId).order('order_index', ascending: true),
      ]);

      final experiences = (results[0] as List)
          .map((r) => Experience.fromMap(r as Map<String, dynamic>))
          .toList();
      final education = (results[1] as List)
          .map((r) => Education.fromMap(r as Map<String, dynamic>))
          .toList();
      final skills = (results[2] as List)
          .map((r) => Skill.fromMap(r as Map<String, dynamic>))
          .toList();
      final languages = (results[3] as List)
          .map((r) => Language.fromMap(r as Map<String, dynamic>))
          .toList();
      final certifications = (results[4] as List)
          .map((r) => Certification.fromMap(r as Map<String, dynamic>))
          .toList();
      final projects = (results[5] as List)
          .map((r) => Project.fromMap(r as Map<String, dynamic>))
          .toList();
      final interests = (results[6] as List)
          .map((r) => Interest.fromMap(r as Map<String, dynamic>))
          .toList();
      final awards = (results[7] as List)
          .map((r) => Award.fromMap(r as Map<String, dynamic>))
          .toList();

      // Perfil "esqueleto": personal existe mas sem nenhum dado estrutural
      // útil. Cai pro v1 em vez de gerar um PDF só com cabeçalho.
      if (experiences.isEmpty && education.isEmpty) {
        if (kDebugMode) {
          debugPrint('[ProfilePdfData] empty profile (no exp+edu) → fallback v1');
        }
        return null;
      }

      return ProfilePdfData(
        personal: personal,
        experiences: experiences,
        education: education,
        skills: skills,
        languages: languages,
        certifications: certifications,
        projects: projects,
        interests: interests,
        awards: awards,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ProfilePdfData] load erro: $e → fallback v1');
      return null;
    }
  }

  /// Converte pro modelo legacy `ResumeData` consumido pelos
  /// `_buildXxxHtml`. Mantém idioma e o fluxo de renderização inalterado.
  ///
  /// Decisões de mapping (justifica casos não-óbvios):
  ///   - `skills` → lista de nomes ordenados por order_index. Tools/toolsText
  ///     ficam vazios (schema não os separa; templates já lidam).
  ///   - `experiences.description` → bullets concatenados por '\n', mesma
  ///     convenção que o pré-parser do adapt-resume-to-job usa.
  ///   - `education` → [ProfileResumeMapper.mapEducation], a mesma projeção
  ///     usada pelo currículo geral. Grau/curso duplicados são consolidados e
  ///     a previsão de conclusão é preservada.
  ///   - `education.coursework` → vazio (tabela `profile_coursework` está
  ///     dormente desde 2026-05-22, conteúdo migrou pra profile_skills).
  ///   - `education.gpa` → "X.XX/Y.YY" ou "X.XX" se max_gpa null.
  ///   - `achievements` → vazio (schema relacional não tem campo equivalente
  ///     fora de bullets, que já entram em experiences).
  ///   - `awards.institution/description` → vazios (schema só tem name+date).
  ResumeData toResumeData() {
    final fullName = personal.fullName;
    final phone = _formatPhone(personal.phoneCountryCode, personal.phoneNumber);
    final location = personal.formattedLocation;

    final skillNames = skills.map((s) => s.name).where((n) => n.trim().isNotEmpty).toList();

    final experiencesOut = experiences.map((exp) {
      final bulletsText = exp.bullets
          .where((b) => b.text.trim().isNotEmpty)
          .map((b) => b.text)
          .join('\n');
      return ExperienceItem(
        role: exp.title,
        company: exp.company,
        period: exp.formattedPeriod,
        description: bulletsText,
        location: exp.location ?? '',
      );
    }).toList();

    // MESMA projeção usada por ProfileSnapshot (currículo geral). Isso
    // impede drift de degree/major, período previsto, GPA e activities entre
    // o caminho relacional v2 e o snapshot canônico.
    final educationOut = education
        .map(ProfileResumeMapper.mapEducation)
        .toList();

    final interestNames = interests.map((i) => i.name).where((n) => n.trim().isNotEmpty).toList();

    final languagesOut = languages
        .where((l) => l.name.trim().isNotEmpty)
        .map((l) => ResumeLanguage(language: l.name, level: l.proficiencyLabel))
        .toList();

    // Prêmios → ResumeData.awards (campo próprio, renderado pela seção
    // "Prêmios e Reconhecimentos" do PdfService) — NÃO achievements. Reusa o
    // mapeador ÚNICO [mapAward] (mesma conversão do currículo geral).
    final awardsOut = awards
        .where((a) => a.name.trim().isNotEmpty)
        .map(mapAward)
        .toList();

    // Projetos → academicProjects via mapeador ÚNICO [mapProject] (mesma
    // conversão do currículo geral — sem duas conversões divergentes).
    final academicProjects =
        projects.where(projectHasRenderableText).map(mapProject).toList();

    // Certifications viram "courses" no schema legacy (templates v1 já
    // tratam como cursos relevantes/certificações na mesma seção).
    final courses = certifications
        .where((c) => c.name.trim().isNotEmpty)
        .map((c) => ResumeCourse(
              title: c.name,
              institution: c.issuer ?? '',
              period: c.date != null ? _formatYear(c.date!) : '',
            ))
        .toList();

    return ResumeData(
      fullName: fullName,
      email: personal.email ?? '',
      phone: phone,
      linkedin: personal.linkedinUrl ?? '',
      location: location,
      address: personal.locationStreetAddress ?? '',
      language: 'pt',
      summary: personal.summary ?? '',
      skills: skillNames,
      tools: const [],
      toolsText: '',
      experiences: experiencesOut,
      education: educationOut,
      achievements: const [],
      interests: interestNames,
      academicProjects: academicProjects,
      leadership: const [],
      courses: courses,
      languages: languagesOut,
      awards: awardsOut,
    );
  }

  String _formatPhone(String? cc, String? num) {
    final c = (cc ?? '').trim();
    final n = (num ?? '').trim();
    // Telefone só faz sentido com número. Sem número, retorna vazio mesmo
    // que tenha country code (4 users reais na base hoje têm cc='+55' e
    // n=NULL — antes mostraria "Mobile: +55" sem número no PDF).
    if (n.isEmpty) return '';

    // Só dígitos pra normalizar — números podem vir como "43991260202",
    // "(43) 99126-0202", "43 99126 0202", etc.
    final digits = n.replaceAll(RegExp(r'\D'), '');

    // Brasil: country code '+55' → formato (DD) 9XXXX-XXXX (celular, 11
    // dígitos) ou (DD) XXXX-XXXX (fixo, 10 dígitos). Sem '+55' no display
    // — o CV é brasileiro, o prefixo é redundante e ocupa espaço.
    if ((c == '+55' || c.isEmpty) && (digits.length == 10 || digits.length == 11)) {
      final ddd = digits.substring(0, 2);
      final rest = digits.substring(2);
      if (rest.length == 9) {
        return '($ddd) ${rest.substring(0, 5)}-${rest.substring(5)}';
      }
      return '($ddd) ${rest.substring(0, 4)}-${rest.substring(4)}';
    }

    // Outros países: mantém formato cc + número como veio (sem assumir
    // padrão regional que pode estar errado).
    if (c.isEmpty) return n;
    return '$c $n';
  }

  // ── Mapeadores ÚNICOS (projeto/prêmio) ────────────────────────────────
  // Reutilizados pelo currículo geral (ProfileSnapshot.toResumeData) pra que
  // exista UMA conversão de Project→ResumeProject e Award→ResumeAward, não
  // duas divergentes. São puros/estáticos (não tocam Supabase).

  /// Um projeto tem texto renderável quando tem uma ÂNCORA PRIMÁRIA com texto
  /// após trim: nome, papel, descrição livre ou algum bullet. O `context`
  /// (→ ResumeProject.relevantWork) é uma anotação SECUNDÁRIA que só o template
  /// Harvard renderiza — sozinho ele NÃO habilita o projeto (senão os outros 4
  /// templates mostrariam um cabeçalho "Projetos" com uma entrada em branco).
  /// Mesmo critério no predicate, no mapper, na prévia e nos templates.
  static bool projectHasRenderableText(Project p) =>
      ProfileResumeMapper.projectHasRenderableText(p);

  /// Project → ResumeProject (academicProjects). Bullets viram descrição
  /// multi-linha; sem bullets, cai na descrição livre legada.
  static ResumeProject mapProject(Project p) =>
      ProfileResumeMapper.mapProject(p);

  /// Award → ResumeAward (campo próprio ResumeData.awards). O schema
  /// relacional só tem name+date; institution/description ficam vazios.
  static ResumeAward mapAward(Award a) => ProfileResumeMapper.mapAward(a);

  static String _formatYear(DateTime d) => d.year.toString();
}
