import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/data/models/models.dart'
    show ResumeAward, ResumeCourse, ResumeLanguage, ResumeLeadership, ResumeProject;
import 'package:career_gamification/features/jobs/models/adapted_resume.dart';
import 'package:career_gamification/features/resume/resume_viewmodel.dart'
    show ResumeData, ExperienceItem, EducationItem, ToolWithLevel;

// F4.2 — serializer COMPLETO de ResumeData. Garante que o Currículo geral
// round-tripa sem perda (awards/academicProjects/leadership + issuer/ano de
// certificações + level de tools + toolsText) e que o formato LEGADO
// (tools/certifications como string[]) ainda parseia sem quebrar.
void main() {
  // ResumeData que espelha o que o Currículo geral produz — todas as seções
  // que o serializer antigo descartava, populadas.
  ResumeData fullResume() => ResumeData(
        fullName: 'Ana Silva',
        email: 'ana@example.com',
        phone: '+55 11 99999-0000',
        linkedin: 'linkedin.com/in/ana',
        location: 'São Paulo, SP',
        address: 'Rua X, 100',
        language: 'pt',
        summary: 'Resumo profissional.',
        skills: const ['Dart', 'Flutter'],
        tools: [ToolWithLevel('Figma', 'Avançado'), ToolWithLevel('Git', '')],
        toolsText: 'Figma (Avançado), Git',
        experiences: [
          ExperienceItem(
            role: 'Dev',
            company: 'Acme',
            period: '2022 – 2024',
            description: 'Bullet 1\nBullet 2',
            location: 'Remoto',
          ),
        ],
        education: [
          EducationItem(
            degree: 'Bacharelado em CC',
            institution: 'USP',
            period: '2019 – 2023',
            details: 'Ênfase em IA',
            location: 'São Paulo',
            gpa: '8.9/10',
            activities: const ['Monitor de Algoritmos'],
          ),
        ],
        languages: [ResumeLanguage(language: 'Inglês', level: 'Fluente')],
        academicProjects: [
          ResumeProject(
            title: 'App de Vagas',
            role: 'Autor',
            period: '2023',
            description: 'Fez X e Y.',
            location: 'Remoto',
            relevantWork: 'Contexto do projeto',
            experiencePhaseId: 'm3.proj.0',
          ),
        ],
        leadership: [
          ResumeLeadership(
            role: 'Coordenador',
            organization: 'Grêmio',
            period: '2021',
            location: 'SP',
            description: 'Liderou Z.',
            relevantWork: '',
            experiencePhaseId: '',
          ),
        ],
        courses: [
          ResumeCourse(title: 'AWS SAA', institution: 'Amazon', period: '2023'),
        ],
        awards: [
          ResumeAward(
            title: 'Melhor TCC',
            institution: 'USP',
            date: '2023',
            description: 'Prêmio X.',
          ),
        ],
        achievements: const ['Conquista legada'],
        interests: const ['Xadrez'],
      );

  group('serializeResumeData / parseResumeData — round-trip completo', () {
    test('preserva awards, projetos, liderança, tools+level, toolsText e '
        'issuer/ano das certificações', () {
      final original = fullResume();
      final json = AdaptedResume.serializeResumeData(original);
      final parsed = AdaptedResume.parseResumeData(json);

      // Escalares
      expect(parsed.fullName, 'Ana Silva');
      expect(parsed.summary, 'Resumo profissional.');
      expect(parsed.address, 'Rua X, 100');
      expect(parsed.toolsText, 'Figma (Avançado), Git');

      // Tools com level preservado
      expect(parsed.tools.length, 2);
      expect(parsed.tools[0].name, 'Figma');
      expect(parsed.tools[0].level, 'Avançado');
      expect(parsed.tools[1].name, 'Git');
      expect(parsed.tools[1].level, '');

      // Certificações com issuer + ano (o serializer antigo perdia)
      expect(parsed.courses.length, 1);
      expect(parsed.courses[0].title, 'AWS SAA');
      expect(parsed.courses[0].institution, 'Amazon');
      expect(parsed.courses[0].period, '2023');

      // Awards (o serializer antigo descartava por completo)
      expect(parsed.awards.length, 1);
      expect(parsed.awards[0].title, 'Melhor TCC');
      expect(parsed.awards[0].institution, 'USP');
      expect(parsed.awards[0].date, '2023');
      expect(parsed.awards[0].description, 'Prêmio X.');

      // Projetos acadêmicos (descartados antes)
      expect(parsed.academicProjects.length, 1);
      expect(parsed.academicProjects[0].title, 'App de Vagas');
      expect(parsed.academicProjects[0].role, 'Autor');
      expect(parsed.academicProjects[0].description, 'Fez X e Y.');
      expect(parsed.academicProjects[0].relevantWork, 'Contexto do projeto');
      expect(parsed.academicProjects[0].experiencePhaseId, 'm3.proj.0');

      // Liderança
      expect(parsed.leadership.length, 1);
      expect(parsed.leadership[0].role, 'Coordenador');
      expect(parsed.leadership[0].organization, 'Grêmio');
      expect(parsed.leadership[0].description, 'Liderou Z.');

      // Seções que já funcionavam continuam
      expect(parsed.skills, ['Dart', 'Flutter']);
      expect(parsed.achievements, ['Conquista legada']);
      expect(parsed.interests, ['Xadrez']);
      expect(parsed.experiences.single.company, 'Acme');
      expect(parsed.education.single.institution, 'USP');
      expect(parsed.education.single.gpa, '8.9/10');
      expect(parsed.languages.single.language, 'Inglês');
    });

    test('round-trip é idempotente (serialize→parse→serialize estável)', () {
      final original = fullResume();
      final json1 = AdaptedResume.serializeResumeData(original);
      final json2 =
          AdaptedResume.serializeResumeData(AdaptedResume.parseResumeData(json1));
      expect(json2, json1);
    });
  });

  group('retrocompatibilidade — formato LEGADO (string[])', () {
    test('certifications e tools como string[] parseiam sem perda', () {
      // Exatamente o que rows adaptadas antigas e o servidor mandam.
      final legacy = {
        'fullName': 'Bia',
        'summary': 'x',
        'skills': ['SQL'],
        'tools': ['Excel', 'Python'],
        'certifications': ['Scrum Master', 'PMP'],
        'experiences': [],
        'education': [],
        'languages': [],
        'achievements': [],
        'interests': [],
      };
      final parsed = AdaptedResume.parseResumeData(legacy);

      expect(parsed.tools.map((t) => t.name).toList(), ['Excel', 'Python']);
      expect(parsed.tools.every((t) => t.level == ''), isTrue);
      expect(parsed.courses.map((c) => c.title).toList(),
          ['Scrum Master', 'PMP']);
      expect(parsed.courses.every((c) => c.institution == ''), isTrue);

      // Seções novas ausentes → vazias, sem quebrar.
      expect(parsed.awards, isEmpty);
      expect(parsed.academicProjects, isEmpty);
      expect(parsed.leadership, isEmpty);
      expect(parsed.toolsText, '');
    });

    test('JSON totalmente vazio não quebra e vira ResumeData vazio', () {
      final parsed = AdaptedResume.parseResumeData(<String, dynamic>{});
      expect(parsed.awards, isEmpty);
      expect(parsed.academicProjects, isEmpty);
      expect(parsed.leadership, isEmpty);
      expect(parsed.courses, isEmpty);
      expect(parsed.tools, isEmpty);
    });

    test('itens malformados/incompletos são tolerados', () {
      final messy = {
        'awards': [
          {'title': 'Só título'},
          {'institution': 'sem título → dropado'},
        ],
        'academicProjects': [
          {'title': 'P', 'role': 'R'},
          {'location': 'sem âncora → dropado'},
        ],
        'tools': [
          {'name': 'Notion', 'level': 'Básico'},
          'Trello', // item String no meio de Maps
        ],
        'certifications': [
          {'title': 'C1'},
          'C2 string',
        ],
      };
      final parsed = AdaptedResume.parseResumeData(messy);

      expect(parsed.awards.length, 1);
      expect(parsed.awards[0].title, 'Só título');
      expect(parsed.academicProjects.length, 1);
      expect(parsed.academicProjects[0].title, 'P');
      expect(parsed.tools.map((t) => t.name).toList(), ['Notion', 'Trello']);
      expect(parsed.tools[0].level, 'Básico');
      expect(parsed.courses.map((c) => c.title).toList(), ['C1', 'C2 string']);
    });
  });

  // ── Compatibilidade entre versões do app (27/07) ────────────────────────
  //
  // A F4.2 gravou o formato rico NA CHAVE ANTIGA. Binário já publicado lê essa
  // chave esperando `string[]` e, ao achar objetos, imprimia
  // `{title: X, institution: Y}` dentro do PDF que o candidato anexa numa vaga.
  // Agora escrevemos nos DOIS formatos.
  group('escrita dupla: binário antigo continua lendo', () {
    ResumeData sample() => ResumeData(
          fullName: 'Zac',
          email: 'z@x.com',
          phone: '',
          location: '',
          summary: '',
          skills: [],
          tools: const [ToolWithLevel('Power BI', 'Avançado')],
          experiences: [],
          education: [],
          languages: [],
          courses: [
            ResumeCourse(
                title: 'Google Data Analytics',
                institution: 'Coursera',
                period: '2025'),
          ],
        );

    test('a chave ANTIGA volta a ser string[] — nada de objeto cru no PDF', () {
      final json = AdaptedResume.serializeResumeData(sample());

      // É exatamente o que o binário antigo espera: lista de strings.
      expect(json['certifications'], isA<List>());
      expect(json['certifications'], ['Google Data Analytics']);
      expect(json['tools'], ['Power BI']);

      // Nenhum item da chave legada pode ser Map — era esse o vazamento.
      for (final key in ['certifications', 'tools']) {
        for (final item in (json[key] as List)) {
          expect(item, isA<String>(), reason: '$key trouxe objeto cru');
        }
      }
    });

    test('a chave NOVA carrega o detalhe rico', () {
      final json = AdaptedResume.serializeResumeData(sample());
      final cert = (json['certifications_v2'] as List).first as Map;
      expect(cert['title'], 'Google Data Analytics');
      expect(cert['institution'], 'Coursera');
      expect(cert['period'], '2025');
      final tool = (json['tools_v2'] as List).first as Map;
      expect(tool['name'], 'Power BI');
      expect(tool['level'], 'Avançado');
    });

    test('round-trip completo: nada se perde pelo caminho novo', () {
      final parsed = AdaptedResume.parseResumeData(
        AdaptedResume.serializeResumeData(sample()),
      );
      expect(parsed.courses.first.title, 'Google Data Analytics');
      expect(parsed.courses.first.institution, 'Coursera');
      expect(parsed.courses.first.period, '2025');
      expect(parsed.tools.first.name, 'Power BI');
      expect(parsed.tools.first.level, 'Avançado');
    });

    test('sem _v2 (row legada) cai na chave antiga, aceitando String e Map', () {
      // Row escrita ANTES da F4.2: string pura.
      final legado = AdaptedResume.parseResumeData({
        'fullName': 'Z',
        'certifications': ['Só o título'],
        'tools': ['Excel'],
      });
      expect(legado.courses.first.title, 'Só o título');
      expect(legado.courses.first.institution, '');
      expect(legado.tools.first.name, 'Excel');

      // Row escrita NA JANELA entre a F4.2 e hoje: objetos na chave antiga.
      final janela = AdaptedResume.parseResumeData({
        'fullName': 'Z',
        'certifications': [
          {'title': 'C', 'institution': 'I', 'period': '2024'}
        ],
        'tools': [
          {'name': 'T', 'level': 'L'}
        ],
      });
      expect(janela.courses.first.institution, 'I');
      expect(janela.tools.first.level, 'L');
    });

    test('_v2 vence a chave antiga quando os dois existem', () {
      final parsed = AdaptedResume.parseResumeData({
        'fullName': 'Z',
        'certifications': ['antigo'],
        'certifications_v2': [
          {'title': 'novo', 'institution': 'I', 'period': '2026'}
        ],
      });
      expect(parsed.courses.first.title, 'novo');
      expect(parsed.courses.first.institution, 'I');
    });
  });
}
