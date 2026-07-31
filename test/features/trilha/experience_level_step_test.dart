import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/profile/application/profile_gaps.dart';
import 'package:career_gamification/features/profile/domain/entities/entities.dart';
import 'package:career_gamification/features/trilha/application/conversation_plan.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';

/// Revisão UX 28/07, achado P1-8 — senioridade coletada e descartada.
///
/// O onboarding pergunta "Em que momento você está agora?", mas isso é
/// SITUAÇÃO DE ESTUDO e vai para `profile_education`. Senioridade
/// (`profile_job_preferences.experience_level`) nunca foi perguntada em lugar
/// nenhum: o campo existia, o editor existia (Perfil → Objetivos), e o único
/// jeito de preencher era a pessoa achar aquela tela sozinha. Resultado
/// medido no relatório: `experience_level = []`.
///
/// A coleta foi para a TRILHA, não para o onboarding — são 12 etapas, e
/// alongar o funil de ativação por um campo Tier 3 custa mais do que rende.
void main() {
  ConversationStep? passoDeSenioridade(List<ConversationStep> plano) {
    for (final s in plano) {
      if (s.id == 'gap.experience_level') return s;
    }
    return null;
  }

  ProfileGaps gapsCom({required bool temSenioridade}) => analyzeProfileGaps(
        // Tudo o mais preenchido, para isolar a lacuna sob teste.
        hasArea: true,
        hasWorkMode: true,
        hasJobType: true,
        hasCity: true,
        hasEducationStatus: true,
        skillsCount: 5,
        experienceCount: 1,
        languagesCount: 1,
        hasSummary: true,
        hasLinkedin: true,
        hasDesiredPosition: true,
        hasCertifications: true,
        hasAwards: true,
        hasProjects: true,
        hasAvailability: true,
        hasInterests: true,
        hasCompanyStage: true,
        hasWorkEnvironment: true,
        hasWorkStyle: true,
        hasExperienceLevel: temSenioridade,
      );

  test('sem senioridade, a trilha PERGUNTA', () {
    final plano = buildConversationPlan(gapsCom(temSenioridade: false));
    expect(passoDeSenioridade(plano), isNotNull);
  });

  test('com senioridade preenchida, a trilha não re-pergunta', () {
    final plano = buildConversationPlan(gapsCom(temSenioridade: true));
    expect(passoDeSenioridade(plano), isNull);
  });

  test('respeita a memória de trechos já abordados', () {
    final plano = buildConversationPlan(
      gapsCom(temSenioridade: false),
      addressed: const {'experience_level'},
    );
    expect(passoDeSenioridade(plano), isNull);
  });

  test('os ids das opções são os MESMOS que o banco aceita', () {
    // O writeback descarta id fora desta lista — valor desconhecido em campo
    // de filtro tiraria a pessoa do funil em silêncio. Se alguém renomear uma
    // opção aqui sem mexer lá, a resposta some sem erro.
    final passo = passoDeSenioridade(
      buildConversationPlan(gapsCom(temSenioridade: false)),
    )!;
    final input = passo.input as ChoiceInput;
    expect(
      input.options.map((o) => o.id).toList(),
      ['entry', 'mid', 'senior'],
    );
    // E são os nomes do enum que `JobPreferences` serializa.
    expect(
      ExperienceLevel.values.map((e) => e.name).toList(),
      containsAll(input.options.map((o) => o.id)),
    );
  });

  test('a mesma pergunta pela porta do Assistente devolve o mesmo passo', () {
    // `sectionSteps` é o caminho de "quero preencher X" e ignora o gate de
    // lacuna. Duas portas para o mesmo campo não podem divergir.
    final direto = sectionSteps(LacunaKey.experienceLevel);
    expect(direto.single.id, 'gap.experience_level');
  });

  test('a escala tem exatamente três degraus', () {
    // Espelha `preferences_tab.dart`. A mesma pergunta em duas superfícies
    // não pode ter duas escalas.
    final passo = passoDeSenioridade(
      buildConversationPlan(gapsCom(temSenioridade: false)),
    )!;
    expect((passo.input as ChoiceInput).options.length, 3);
    expect(ExperienceLevel.values.length, 3);
  });
}
