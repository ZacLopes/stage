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
    final Map<String, dynamic> result = {
      'education': <String, dynamic>{},
      'highlights': <String, dynamic>{},
    };

    // --- 2.1 Minha Guilda: formulário acadêmico unificado ---
    if (answers['M2_1_1_Q1'] != null) {
      try {
        final Map<String, dynamic> form = jsonDecode(answers['M2_1_1_Q1']);
        result['education']['institution'] = form['institution_name'];
        result['education']['course'] = form['course_name'];
        result['education']['status'] = form['course_status'];
        result['education']['start_date'] = form['course_start_mm_yyyy'];
        result['education']['end_date'] = form['course_end_mm_yyyy'];
        result['education']['duration_months'] = form['duration_months'];
        result['education']['semester'] = form['semester'];
        result['education']['period'] = form['period'];
      } catch (e) {
        print('Error parsing academic form: $e');
      }
    }

    // Formação anterior (opcional)
    if (answers['M2_1_1_Q3'] != null) {
      try {
        final Map<String, dynamic> prev = jsonDecode(answers['M2_1_1_Q3']);
        result['education']['secondary_institution'] = prev['institution'];
        result['education']['secondary_course'] = prev['course'];
        result['education']['secondary_status'] = prev['status'];
      } catch (e) {
        print('Error parsing secondary education: $e');
      }
    }

    // --- 2.2 Cursos (ex-M3.2) ---
    if (answers['M3_2_1_Q2'] != null) {
      try {
        final raw = answers['M3_2_1_Q2'].toString();
        if (raw != 'skipped' && raw.isNotEmpty && raw != '[]') {
          final List<dynamic> list = jsonDecode(raw);
          result['education']['courses'] =
              list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (e) {
        print('Error parsing courses: $e');
      }
    }

    // --- 2.3 Medalhas de Honra ---
    if (answers['M2_3_1_Q1'] != null) {
      result['highlights']['scholarship'] = answers['M2_3_1_Q1'];
    }

    if (answers['M2_3_1_Q4'] != null) {
      try {
        final Map<String, dynamic> award = jsonDecode(answers['M2_3_1_Q4']);
        result['highlights']['has_award'] = award['has_award'];
        result['highlights']['award_name'] = award['award_name'];
      } catch (e) {
        print('Error parsing award: $e');
      }
    }

    return result;
  }

  static Map<String, dynamic> processModule3Answers(Map<String, dynamic> answers) {
    final Map<String, dynamic> result = {
      'experiences': <Map<String, dynamic>>[],
      'activities': <Map<String, dynamic>>[],
    };

    // --- 3.1 Experiências ---
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

    // --- 3.2 Atividades extracurriculares (ex-M2.3.2) ---
    if (answers['M2_3_1_Q2'] != null) {
      try {
        final raw = answers['M2_3_1_Q2'].toString();
        if (raw != 'skipped' && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            result['activities'] =
                decoded.map((e) => Map<String, dynamic>.from(e)).toList();
          }
        }
      } catch (e) {
        print('Error parsing activities: $e');
      }
    }

    return result;
  }
}
