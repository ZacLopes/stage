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
      'inventory': <String>[],
      'counts': <String, int>{},
    };

    // --- Inventory (M3_1_1_Q1) ---
    if (answers['M3_1_1_Q1'] != null) {
      try {
        final raw = answers['M3_1_1_Q1'].toString();
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          result['inventory'] = parsed.map((e) => e.toString()).toList();
        }
      } catch (e) {
        print('Error parsing inventory: $e');
      }
    }

    // --- Quantity (M3_1_1_QCount) ---
    if (answers['M3_1_1_QCount'] != null) {
      try {
        final raw = answers['M3_1_1_QCount'].toString();
        final Map<String, dynamic> parsed = jsonDecode(raw);
        result['counts'] = {
          for (final e in parsed.entries) e.key: (e.value as num).toInt()
        };
      } catch (e) {
        print('Error parsing experience counts: $e');
      }
    }

    // --- D-questions: aggregate D1-D5 per (category, index) ---
    // Pattern: M3_D{1-5}_{cat}_{n}
    final dPattern = RegExp(r'^M3_D(\d+)_(\w+)_(\d+)$');
    // Group by cat_n key
    final Map<String, Map<String, dynamic>> expMap = {};
    answers.forEach((key, value) {
      final m = dPattern.firstMatch(key);
      if (m == null || value == null || value.toString().isEmpty) return;
      final d = int.parse(m.group(1)!);
      final cat = m.group(2)!;
      final n = int.parse(m.group(3)!);
      final expKey = '${cat}_$n';

      expMap.putIfAbsent(expKey, () => {'category': cat, 'index': n});

      switch (d) {
        case 1:
          try {
            expMap[expKey]!['details'] = jsonDecode(value.toString());
          } catch (_) {
            expMap[expKey]!['details'] = value.toString();
          }
        case 2:
          expMap[expKey]!['org_context'] = value.toString();
        case 3:
          expMap[expKey]!['why_chosen'] = value.toString();
        case 4:
          expMap[expKey]!['what_i_did'] = value.toString();
        case 5:
          expMap[expKey]!['impact'] = value.toString();
      }
    });

    // Sort by category then index so output is deterministic
    final sortedKeys = expMap.keys.toList()
      ..sort((a, b) => a.compareTo(b));
    result['experiences'] = sortedKeys.map((k) => expMap[k]!).toList();

    return result;
  }
}
