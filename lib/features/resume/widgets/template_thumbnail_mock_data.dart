import '../../../data/models/models.dart';
import '../resume_viewmodel.dart';

/// Mock UserProfile + ResumeData used to render the static thumbnails shown in
/// `ResumeTemplateSelector`. Not displayed to end users — only consumed by
/// `test/generate_template_thumbnails_test.dart` when regenerating the PNG
/// previews under `assets/images/templates/`.
///
/// Fictional persona ("Ana Silva", USP Engenharia de Produção) picked so all
/// four templates render with enough content to be visually distinguishable.

final UserProfile kThumbnailMockProfile = UserProfile(
  name: 'Ana Silva',
  email: 'ana.silva@usp.br',
  course: 'Engenharia de Produção',
  semester: '7',
  age: 22,
  phone: '11987654321',
  aiConsent: true,
);

final ResumeData kThumbnailMockResume = ResumeData(
  fullName: 'Ana Silva',
  email: 'ana.silva@usp.br',
  phone: '(11) 98765-4321',
  linkedin: 'linkedin.com/in/anasilva',
  location: 'São Paulo, SP',
  language: 'pt',
  summary:
      'Estudante de Engenharia de Produção (USP) com experiência em análise de dados, otimização de processos e gestão de projetos. Busco estágio em estratégia e operações, com foco em impacto mensurável e tomada de decisão orientada a dados.',
  skills: const [
    'SQL e Python para análise de dados',
    'Excel avançado e Power BI',
    'Lean Six Sigma (White Belt)',
    'Gestão de projetos (Scrum)',
    'Modelagem financeira',
    'Inglês fluente, Espanhol intermediário',
  ],
  experiences: [
    ExperienceItem(
      role: 'Estagiária de Engenharia',
      company: 'Ambev',
      period: 'Jan 2025 — atual',
      location: 'São Paulo, SP',
      description: '• Reduzi em 18% o tempo de setup de linha por meio de análise SMED, gerando ganho anual estimado de R\$ 240k.\n'
          '• Estruturei painel em Power BI consumido por 32 gestores de produção, eliminando 6h/semana de planilhas manuais.\n'
          '• Liderei piloto de Kanban em 2 áreas, reduzindo lead time em 22% e backlog em 35% em 8 semanas.',
    ),
    ExperienceItem(
      role: 'Monitora de Cálculo I',
      company: 'Escola Politécnica da USP',
      period: 'Mar 2024 — Dez 2024',
      location: 'São Paulo, SP',
      description: '• Conduzi 4 plantões semanais para turma de 120 alunos; aprovação subiu de 61% para 78% ao final do semestre.\n'
          '• Desenvolvi 24 listas de exercícios complementares adotadas oficialmente pelo departamento no semestre seguinte.',
    ),
  ],
  education: [
    EducationItem(
      degree: 'Bacharelado em Engenharia de Produção',
      institution: 'Universidade de São Paulo (USP)',
      period: '2022 — 2027 (previsto)',
      location: 'São Paulo, SP',
      gpa: '8.7/10',
      honors: 'Top 10% da turma; menção honrosa em Pesquisa Operacional (2024)',
      repRole: 'Representante de turma — 2023/2024',
      coursework: 'Pesquisa Operacional, Estatística, Finanças Corporativas, Simulação Computacional, Logística',
    ),
  ],
  academicProjects: [
    ResumeProject(
      title: 'Otimização de rede de distribuição (TCC parcial)',
      role: 'Líder técnica',
      period: '2025',
      location: 'São Paulo, SP',
      description: '• Modelei problema de localização de centros de distribuição em Python (PuLP), reduzindo custo logístico simulado em 14%.\n'
          '• Apresentei resultados em workshop interno da Poli-USP com 80+ participantes.',
    ),
  ],
  leadership: [
    ResumeLeadership(
      role: 'Diretora de Projetos',
      organization: 'Poli Júnior (Empresa Júnior da Poli-USP)',
      period: 'Ago 2023 — Dez 2024',
      location: 'São Paulo, SP',
      description: '• Liderei equipe de 6 consultores em 4 projetos de melhoria de processos com faturamento total de R\$ 180k.\n'
          '• Aumentei NPS médio de clientes de 7,2 para 9,1 em 12 meses ao reformular metodologia de entrega.',
    ),
  ],
  languages: [
    ResumeLanguage(language: 'Português', level: 'Nativo'),
    ResumeLanguage(language: 'Inglês', level: 'Fluente (C1) — TOEFL 105'),
    ResumeLanguage(language: 'Espanhol', level: 'Intermediário (B1)'),
  ],
  courses: [
    ResumeCourse(title: 'Power BI for Business Analysts', institution: 'Microsoft Learn', period: '2024'),
    ResumeCourse(title: 'Lean Six Sigma White Belt', institution: 'FM2S', period: '2023'),
  ],
  interests: const [
    'Corrida de rua',
    'Fotografia analógica',
    'Voluntariado em mentoria de estudantes',
  ],
  achievements: const [
    'Finalista do Desafio Inova Ambev 2025 (top 20 em 1200 inscritos)',
  ],
);
