import 'dart:convert';
import '../../data/models/models.dart';

class GamificationLogic {
  static Map<String, dynamic> processModule1Answers(Map<String, dynamic> answers) {
    final Map<String, dynamic> result = {
      'soft_skills': <String>[],
      'traits': <String, dynamic>{},
    };

    final Set<String> softSkills = {};

    // --- Etapa 1.1: Área de foco ---
    final interestsAnswer = answers['M1_3_1_Q2'];
    if (interestsAnswer != null) {
      final List<String> areas = interestsAnswer is List
          ? interestsAnswer.map((e) => e.toString()).toList()
          : interestsAnswer.toString().split(',').map((e) => e.trim()).toList();
      result['traits']['interest_areas'] = areas;

      if (areas.any((e) => e.contains('Ainda estou explorando'))) {
        result['traits']['resume_tone'] = 'generalist_learner';
        result['traits']['highlight_soft_skills'] = true;
        softSkills.add('Vontade de Aprender');
        softSkills.add('Curiosidade Intelectual');
        softSkills.add('Adaptabilidade');
      } else {
        result['traits']['hard_skills_focus'] = areas;
      }
    }

    // --- Etapa 1.2: Tipo de oportunidade ---
    final oppAnswer = answers['M1_3_1_Q25'];
    if (oppAnswer != null) {
      final List<String> types = oppAnswer is List
          ? oppAnswer.map((e) => e.toString()).toList()
          : oppAnswer.toString().split(',').map((e) => e.trim()).toList();
      result['traits']['opportunity_types'] = types;
    }

    // --- Etapa 1.3: Norte profissional (texto livre) ---
    final visionAnswer = answers['M1_3_1_Q3'];
    if (visionAnswer != null && visionAnswer.toString().isNotEmpty) {
      result['traits']['future_vision_text'] = visionAnswer.toString();
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
