import 'dart:convert';
import '../../data/models/models.dart';

class GamificationLogic {
  static Map<String, dynamic> processModule1Answers(Map<String, dynamic> answers) {
    // Initialize result structure
    final Map<String, dynamic> result = {
      'soft_skills': <String>[],
      'traits': <String, dynamic>{},
    };
    
    final Set<String> softSkills = {};
    
    // --- M1.1: Meus Pontos Fortes ---
    
    // Q1: Role Profile
    final roleAnswer = answers['M1_1_1_Q1'];
    if (roleAnswer != null) {
      result['traits']['role_profile'] = roleAnswer;
      switch (roleAnswer) {
        case 'architect':
          softSkills.add('Organização e Planejamento');
          result['traits']['technical_adjectives'] = 'Perfil analítico e focado em estruturação de negócios';
          break;
        case 'visionary':
          softSkills.add('Criatividade e Inovação');
          result['traits']['technical_adjectives'] = 'Perfil criativo e focado em inovação e diferenciação';
          break;
        case 'chief':
          softSkills.add('Liderança');
          softSkills.add('Gestão de Pessoas');
          result['traits']['technical_adjectives'] = 'Perfil de liderança e focado em resultados e gestão';
          break;
        case 'builder':
          softSkills.add('Proatividade');
          softSkills.add('Foco em Resultados');
          result['traits']['technical_adjectives'] = 'Perfil técnico e focado em execução e qualidade';
          break;
        case 'negotiator':
          softSkills.add('Trabalho em Equipe');
          softSkills.add('Inteligência Emocional');
          result['traits']['technical_adjectives'] = 'Perfil colaborativo e focado em comunicação e união';
          break;
      }
    }

    // Q2: Crisis Response
    final crisisAnswer = answers['M1_1_1_Q2'];
    if (crisisAnswer != null) {
      result['traits']['crisis_response'] = crisisAnswer;
      switch (crisisAnswer) {
        case 'prioritize_execute':
          softSkills.add('Adaptabilidade');
          softSkills.add('Agilidade');
          break;
        case 'investigate_cause':
          softSkills.add('Pensamento Analítico');
          softSkills.add('Resolução de Problemas');
          break;
        case 'seek_support':
          softSkills.add('Comunicação');
          softSkills.add('Humildade Intelectual');
          break;
        case 'negotiate':
          softSkills.add('Negociação');
          softSkills.add('Visão Estratégica');
          break;
      }
    }

    // Q3: Attention (Slider)
    final attentionAnswer = answers['M1_1_1_Q3'];
    if (attentionAnswer != null) {
      final double val = double.tryParse(attentionAnswer.toString()) ?? 50.0;
      result['traits']['attention_slider'] = val;
      
      if (val <= 35) {
        result['traits']['attention_profile'] = 'Detalhista / Rigor';
        softSkills.add('Atenção aos Detalhes');
      } else if (val >= 65) {
        result['traits']['attention_profile'] = 'Visão do Todo / Agilidade';
        softSkills.add('Visão Sistêmica');
      } else {
        result['traits']['attention_profile'] = 'Equilibrado';
        softSkills.add('Equilíbrio');
      }
    }

    // Q4: Communication Rank
    final commAnswer = answers['M1_1_1_Q4'];
    if (commAnswer != null && commAnswer is List) {
      result['traits']['communication_rank'] = commAnswer;
      if (commAnswer.isNotEmpty) {
        final top1 = commAnswer[0].toString();
        if (top1.contains('Falar')) softSkills.add('Oratória');
        if (top1.contains('Escrever')) softSkills.add('Comunicação Escrita');
        if (top1.contains('Visualizar')) softSkills.add('Criatividade Visual');
        if (top1.contains('Ouvir')) softSkills.add('Escuta Ativa');
      }
    }
    
    // --- M1.2: Culture ---
    
    // Q1: Environment
    final envAnswer = answers['M1_2_1_Q1'];
    if (envAnswer != null) {
      result['traits']['culture_env'] = envAnswer;
      switch (envAnswer) {
        case 'laboratory':
          softSkills.add('Concentração');
          break;
        case 'arena':
          softSkills.add('Competitividade Saudável');
          break;
        case 'community':
          softSkills.add('Colaboração');
          break;
        case 'stage':
          softSkills.add('Relacionamento Interpessoal');
          break;
      }
    }
    
    // Q2: Learning Style
    final learnAnswer = answers['M1_2_1_Q2'];
    if (learnAnswer != null) {
       result['traits']['learnability_style'] = learnAnswer;
       switch (learnAnswer) {
         case 'self_research':
           softSkills.add('Autodidatismo');
           break;
         case 'consult_expert':
           softSkills.add('Networking');
           break;
         case 'trial_error':
           softSkills.add('Learning agility');
           break;
         case 'read_manual':
           softSkills.add('Compliance');
           break;
       }
    }



    // --- M1.3: Compass ---

    // Q1: Success Driver
    // Q1: Success Driver
    final successAnswer = answers['M1_3_1_Q1'];
    if (successAnswer != null && successAnswer is List) {
       result['traits']['success_rank'] = successAnswer;
       if (successAnswer.isNotEmpty) {
         final top1 = successAnswer[0].toString().toLowerCase();
         String driver = 'unknown';
         if (top1.contains('mestria')) driver = 'mastery';
         else if (top1.contains('impacto')) driver = 'impact';
         else if (top1.contains('ascensão')) driver = 'ascension';
         else if (top1.contains('estabilidade')) driver = 'stability';
         else if (top1.contains('autonomia')) driver = 'autonomy';
         
         result['traits']['success_driver_top1'] = driver;
       }
    }
    
    // Q2: Interest Areas
    final interestsAnswer = answers['M1_3_1_Q2'];
    if (interestsAnswer != null && interestsAnswer is List) {
      result['traits']['interest_areas'] = interestsAnswer;
      
      final List<String> areas = (interestsAnswer).map((e) => e.toString()).toList();
      bool isExploring = areas.any((element) => element.contains('Ainda estou explorando'));
      
      if (isExploring) {
        result['traits']['resume_tone'] = 'generalist_learner';
        result['traits']['highlight_soft_skills'] = true;
        // Generic soft skills for explorers
        softSkills.add('Vontade de Aprender');
        softSkills.add('Curiosidade Intelectual');
        softSkills.add('Adaptabilidade');
      } else {
        result['traits']['hard_skills_focus'] = areas;
      }
    }

    // Q3: Vision
    final visionAnswer = answers['M1_3_1_Q3'];
    if (visionAnswer != null) {
      result['traits']['future_vision'] = visionAnswer;
      switch (visionAnswer) {
        case 'founder':
          softSkills.add('Mentalidade Empreendedora');
          softSkills.add('Validação de MVP');
          softSkills.add('Proatividade');
          break;
        case 'ceo':
          softSkills.add('Gestão de Projetos');
          softSkills.add('Comunicação Assertiva');
          softSkills.add('Foco em Resultados');
          break;
        case 'master':
          softSkills.add('Busca por Excelência Técnica');
          softSkills.add('Resolução de Problemas Complexos');
          softSkills.add('Especialização');
          break;
        case 'strategist':
          softSkills.add('Pensamento Analítico');
          softSkills.add('Visão de Mercado');
          softSkills.add('Eficiência Operacional');
          break;
      }
    }

    result['soft_skills'] = softSkills.toList();
    return result;
  }

  static Map<String, dynamic> processModule2Answers(Map<String, dynamic> answers) {
    print('Processing Module 2 answers: $answers');
    final Map<String, dynamic> result = {
      'education': <String, dynamic>{},
      'highlights': <String, dynamic>{},
    };
    
    // --- 2.1 Minha Guilda ---
    // Q1: Current Education (Renamed from Q2)
    if (answers['M2_1_1_Q1'] != null) {
      try {
        final Map<String, dynamic> idCard = jsonDecode(answers['M2_1_1_Q1']);
        result['education']['institution'] = idCard['institution_name'];
        result['education']['course'] = idCard['course_name'];
        result['education']['status'] = idCard['course_status'];
      } catch (e) {
        print('Error parsing ID Card: $e');
      }
    }

    // Q3 & Q4: Secondary Education (Secondary Background)
    if (answers['M2_1_1_Q3'] != null) {
       try {
         final Map<String, dynamic> secondaryCard = jsonDecode(answers['M2_1_1_Q3']);
         result['education']['secondary_institution'] = secondaryCard['institution'];
         result['education']['secondary_course'] = secondaryCard['course'];
         result['education']['secondary_status'] = secondaryCard['status'];
       } catch (e) {
         print('Error parsing Secondary ID Card: $e');
       }
    }

    if (answers['M2_1_1_Q4'] != null) {
      result['strengths']['bridge_knowledge'] = answers['M2_1_1_Q4']; // Story/Bridge text
    }

    // --- 2.2 Datas e Logística ---
    if (answers['M2_2_1_Q1'] != null) {
      try {
        final Map<String, dynamic> dates = jsonDecode(answers['M2_2_1_Q1']);
        result['education']['start_date'] = dates['course_start_mm_yyyy'];
        result['education']['end_date'] = dates['course_end_mm_yyyy'];
        result['education']['duration_months'] = dates['duration_months'];
      } catch (e) {
        print('Error parsing Dates: $e');
      }
    }
    
    if (answers['M2_2_1_Q2'] != null) {
      result['education']['semester'] = answers['M2_2_1_Q2'];
    }
    
    if (answers['M2_2_1_Q3'] != null) {
      result['education']['period'] = answers['M2_2_1_Q3'];
    }

    // --- 2.3 Medalhas de Honra ---
    if (answers['M2_3_1_Q1'] != null) {
      result['highlights']['scholarship'] = answers['M2_3_1_Q1'];
    }
    
    if (answers['M2_3_1_Q2'] != null) {
      // It's a list actually, stored as comma string or piped string by repository?
      // Repository uses .join(',') for Lists if not careful, or store answer as is?
      // Repository.saveAnswer joins with comma if it is a list?
      // "answer is List ? answer.join(',') : answer.toString()"
      // Wait, repository join(',') might break json lists.
      // But BadgeMultiSelect returns List<String>.
      // Repository `saveAnswer`: `answer is List ? answer.join(',')`.
      // So retrieving it: it will be a String "monitoria,inic_cientifica".
      // We need to split it back.
      final String raw = answers['M2_3_1_Q2'].toString();
      result['highlights']['activities'] = raw.split(',');
    }
    
    if (answers['M2_3_1_Q3'] != null) {
      result['highlights']['highlight_text'] = answers['M2_3_1_Q3'];
    }
    
    if (answers['M2_3_1_Q4'] != null) {
      try {
        final Map<String, dynamic> award = jsonDecode(answers['M2_3_1_Q4']);
        result['highlights']['has_award'] = award['has_award'];
        result['highlights']['award_name'] = award['award_name'];
      } catch (e) {
         print('Error parsing Award: $e');
      }
    }
    
    return result;
  }

  static Map<String, dynamic> processModule3Answers(Map<String, dynamic> answers) {
    final Map<String, dynamic> result = {
      'experiences': <Map<String, dynamic>>[],
      'courses': <Map<String, dynamic>>[],
    };

    // --- 3.1 Experiences ---
    // Iterate through all keys to find experience forms (M3_1_1_Q2_*)
    answers.forEach((key, value) {
      if (key.startsWith('M3_1_1_Q2')) {
         try {
           if (value != null && value.toString() != 'skipped') {
              final Map<String, dynamic> expData = jsonDecode(value.toString());
              result['experiences'].add(expData);
           }
         } catch (e) {
           print('Error parsing experience $key: $e');
         }
      }
    });

    // --- 3.2 Courses ---
    if (answers['M3_2_1_Q2'] != null) {
      try {
        final raw = answers['M3_2_1_Q2'].toString();
        // If it was skipped or empty
        if (raw != 'skipped' && raw.isNotEmpty && raw != '[]') {
           final List<dynamic> list = jsonDecode(raw);
           result['courses'].addAll(list.map((e) => Map<String, dynamic>.from(e)).toList());
        }
      } catch (e) {
        print('Error parsing courses: $e');
      }
    }
    
    return result;
  }
}
