// TrailToProfileBridge — mapeia respostas da trilha gamificada (phase_id +
// answer) pras tabelas profile_* relacionais.
//
// Hook no GamificationViewModel.saveAnswer: depois de gravar em user_answers/
// raw_responses (caminho legacy), chama TrailToProfileBridge.route(phaseId, answer)
// pra escrever também no schema relacional. Dual-write durante a Semana 2;
// Semana 3 remove o legacy quando confirmar estabilidade.
//
// Mapeamento corrigido (alinhado à estrutura real das 9 fases existentes):
//   T1 (Direção)            → profile_job_preferences + profile_desired_titles
//   T2 (Minha Base)         → profile_education + filhas
//   T3 (Minhas Experiências) → profile_experiences + profile_bullets
//   T4 (Hard Skills+Idiomas) → profile_skills + profile_languages + profile_certifications
//   T5 (Links & Logística)  → profile_personal (location, headline) + profile_application_countries
//
// IMPORTANTE: esta bridge é defensiva — se o mapeamento de algum phase_id
// específico ainda não foi implementado, ela faz no-op silencioso (não derruba
// a trilha legacy). Conforme cada passo da trilha for "ativado" pra escrever
// no relacional, basta adicionar o case correspondente no switch.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../profile/domain/entities/entities.dart';
import '../../profile/domain/repositories/profile_repository.dart';

class TrailToProfileBridge {
  final ProfileRepository _repo;
  TrailToProfileBridge(this._repo);

  /// Recebe phase_id e answer (como vem do GamificationViewModel) e roteia pra
  /// tabela correspondente. Retorna sem erro mesmo se o phase_id não estiver
  /// mapeado ainda — assim a trilha legacy não quebra.
  Future<void> route({
    required String phaseId,
    required dynamic answer,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Tracks usam prefixos m1, m2, m3, m4, m5 conforme seed_data.
      if (phaseId.startsWith('m1.')) {
        await _routeT1(userId, phaseId, answer);
      } else if (phaseId.startsWith('m2.')) {
        await _routeT2(userId, phaseId, answer);
      } else if (phaseId.startsWith('m3.')) {
        await _routeT3(userId, phaseId, answer);
      } else if (phaseId.startsWith('m4.')) {
        await _routeT4(userId, phaseId, answer);
      } else if (phaseId.startsWith('m5.')) {
        await _routeT5(userId, phaseId, answer);
      }
    } catch (e) {
      // Bridge nunca pode derrubar trilha legacy. Loga só em debug.
      debugPrint('[TrailToProfileBridge] $phaseId failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // T1: Direção / norte profissional
  //
  // 3 sub-perguntas, cada uma roteia pra uma tabela diferente:
  //   m1.1 (M1_3_1_Q2  — área de interesse, multi-choice) → profile_desired_titles
  //   m1.2 (M1_3_1_Q25 — tipo de vaga,      single/multi) → profile_job_preferences.job_types
  //   m1.3 (M1_3_1_Q3  — futuro,              texto livre) → profile_personal.summary
  //
  // Substitui o caminho legacy `gamification_data.whoIAm` (Passo 4 do plano
  // match-score, 2026-05-27) — o write quebrado foi removido em
  // gamification_viewmodel.dart na mesma rodada.
  // ──────────────────────────────────────────────────────────────────────
  Future<void> _routeT1(String userId, String phaseId, dynamic answer) async {
    switch (phaseId) {
      case 'm1.1':
        await _routeT1Areas(userId, answer);
        break;
      case 'm1.2':
        await _routeT1JobTypes(userId, answer);
        break;
      case 'm1.3':
        await _routeT1FutureVision(userId, answer);
        break;
      default:
        // phaseId desconhecido em T1 — no-op silencioso (defensivo).
        break;
    }
  }

  /// m1.1 — área de interesse (multi-choice). Cada opção vira 1 linha em
  /// `profile_desired_titles`. Preserva áreas já existentes (ex: vindas da
  /// aba Perfil → Preferências) — faz merge dedupado em vez de substituir.
  /// Filtra opções não-area ("Ainda estou explorando", "Aberto a oportunidades").
  Future<void> _routeT1Areas(String userId, dynamic answer) async {
    final raw = _toStringList(answer);
    final areas = raw
        .where((a) {
          final n = a.toLowerCase().trim();
          if (n.contains('ainda estou explorando')) return false;
          if (n.contains('aberto a oportunidades')) return false;
          return n.isNotEmpty;
        })
        .toList();
    if (areas.isEmpty) return;

    final existing = await _repo.getDesiredTitles(userId);
    final existingTitlesLower = existing.map((t) => t.title.toLowerCase().trim()).toSet();
    final toAdd = areas
        .where((a) => !existingTitlesLower.contains(a.toLowerCase().trim()))
        .toList();
    if (toAdd.isEmpty) return; // todas já existem

    final entries = <DesiredTitle>[
      ...existing,
      for (var i = 0; i < toAdd.length; i++)
        DesiredTitle(
          id: '',
          userId: userId,
          title: toAdd[i].trim(),
          source: DesiredTitleSource.userAdded,
          orderIndex: existing.length + i,
        ),
    ];
    await _repo.replaceDesiredTitles(userId, entries);
  }

  /// m1.2 — tipo de vaga ("Estágio", "Trainee", etc). Mapeia pra enum
  /// `JobType` e persiste em `profile_job_preferences.job_types`. Merge
  /// dedupado com tipos já existentes (não substitui).
  Future<void> _routeT1JobTypes(String userId, dynamic answer) async {
    final raws = _toStringList(answer);
    final newTypes = <JobType>{};
    for (final raw in raws) {
      final norm = raw.toLowerCase().trim();
      if (norm.isEmpty) continue;
      if (norm.contains('estagio') || norm.contains('estágio')) {
        newTypes.add(JobType.internship);
      } else if (norm.contains('trainee')) {
        newTypes.add(JobType.trainee);
      } else if (norm.contains('clt')) {
        newTypes.add(JobType.juniorFullTime);
      } else if (norm.contains('temporario') || norm.contains('temporário')) {
        newTypes.add(JobType.temporary);
      }
    }
    if (newTypes.isEmpty) return;

    final existing = await _repo.getJobPreferences(userId) ?? JobPreferences(userId: userId);
    final merged = <JobType>{...existing.jobTypes, ...newTypes}.toList();
    if (merged.length == existing.jobTypes.length) return; // nenhum novo
    await _repo.upsertJobPreferences(existing.copyWith(jobTypes: merged));
  }

  /// m1.3 — futuro profissional (texto livre). Vai pra
  /// `profile_personal.summary` SOMENTE se ainda estiver vazio. Não
  /// sobrescreve summary vindo de CV importado ou edição manual.
  Future<void> _routeT1FutureVision(String userId, dynamic answer) async {
    if (answer is! String) return;
    final text = answer.trim();
    if (text.isEmpty) return;

    final existing = await _repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
    if ((existing.summary ?? '').trim().isNotEmpty) {
      return; // já tem summary, preserva
    }
    await _repo.upsertPersonal(existing.copyWith(summary: text));
  }

  // ──────────────────────────────────────────────────────────────────────
  // T2: Educação → profile_education
  // ──────────────────────────────────────────────────────────────────────
  Future<void> _routeT2(String userId, String phaseId, dynamic answer) async {
    // M2 tem AcademicForm que retorna Map com institution/degree/dates.
    if (answer is Map) {
      final m = answer.cast<String, dynamic>();
      final institution = (m['institution'] ?? m['school'] ?? '').toString();
      if (institution.isEmpty) return;
      final edu = Education(
        id: '',
        userId: userId,
        institution: institution,
        location: m['location'] as String?,
        degree: m['degree'] as String?,
        startDate: _parseDate(m['start_date'] ?? m['startDate']),
        endDate: _parseDate(m['end_date'] ?? m['endDate']),
      );
      final majors = <EducationMajor>[];
      final majorList = m['majors'] ?? m['course'];
      if (majorList is String && majorList.isNotEmpty) {
        majors.add(EducationMajor(id: '', educationId: '', name: majorList));
      } else if (majorList is List) {
        for (var i = 0; i < majorList.length; i++) {
          majors.add(EducationMajor(id: '', educationId: '', name: majorList[i].toString(), orderIndex: i));
        }
      }
      await _repo.addEducation(edu.copyWith(majors: majors));
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // T3: Experiência → profile_experiences (bullets via generate-bullets refator)
  // ──────────────────────────────────────────────────────────────────────
  Future<void> _routeT3(String userId, String phaseId, dynamic answer) async {
    // M3.{cat}.{n}.{d1-d6}: d1 título, d2 empresa, d3 datas, d4 location,
    // d5 (responsabilidades), d6 dispara generate-bullets.
    // Pra MVP, só roteamos quando temos um Map estruturado (d1+d2+d3+d4 juntos).
    if (answer is Map) {
      final m = answer.cast<String, dynamic>();
      final title = (m['title'] ?? m['role'] ?? '').toString();
      final company = (m['company'] ?? '').toString();
      final startDate = _parseDate(m['start_date'] ?? m['startDate']);
      if (title.isEmpty || company.isEmpty || startDate == null) return;
      final exp = Experience(
        id: '',
        userId: userId,
        title: title,
        company: company,
        location: m['location'] as String?,
        startDate: startDate,
        endDate: _parseDate(m['end_date'] ?? m['endDate']),
        isCurrent: m['is_current'] == true || m['endDate'] == null,
      );
      await _repo.addExperience(exp);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // T4: Skills + Idiomas + Certificações → profile_skills/_languages/_certs
  // ──────────────────────────────────────────────────────────────────────
  Future<void> _routeT4(String userId, String phaseId, dynamic answer) async {
    // M4_1: tools/skills. M4_2: idiomas.
    if (phaseId.contains('m4_1') || phaseId.contains('m4.1')) {
      // Tools / skills
      final names = _toStringList(answer);
      if (names.isNotEmpty) {
        final existing = await _repo.getSkills(userId);
        final existingNames = existing.map((s) => s.name.toLowerCase()).toSet();
        final newNames = names
            .where((n) => !existingNames.contains(n.toLowerCase()))
            .toList();
        await _repo.replaceSkills(userId, [
          ...existing.map((s) => s.name),
          ...newNames,
        ]);
      }
    } else if (phaseId.contains('m4_2') || phaseId.contains('m4.2')) {
      // Languages
      if (answer is Map) {
        final m = answer.cast<String, dynamic>();
        final name = (m['name'] ?? m['language'] ?? '').toString();
        if (name.isEmpty) return;
        final profStr = (m['proficiency'] ?? m['level'] ?? '').toString().toLowerCase();
        LanguageProficiency? prof;
        switch (profStr) {
          case 'native': case 'nativo': prof = LanguageProficiency.native; break;
          case 'fluent': case 'fluente': prof = LanguageProficiency.fluent; break;
          case 'advanced': case 'avançado': case 'avancado': prof = LanguageProficiency.advanced; break;
          case 'intermediate': case 'intermediário': case 'intermediario': prof = LanguageProficiency.intermediate; break;
          case 'basic': case 'básico': case 'basico': prof = LanguageProficiency.basic; break;
        }
        await _repo.addLanguage(
          Language(id: '', userId: userId, name: name, proficiency: prof),
        );
      } else if (answer is List) {
        for (final item in answer) {
          if (item is Map) await _routeT4(userId, phaseId, item);
        }
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // T5: Links & Logística → profile_personal (location, headline, links)
  // ──────────────────────────────────────────────────────────────────────
  Future<void> _routeT5(String userId, String phaseId, dynamic answer) async {
    if (answer is Map) {
      final m = answer.cast<String, dynamic>();
      final existing = await _repo.getPersonal(userId) ??
          PersonalInfo(userId: userId);
      final updated = existing.copyWith(
        locationCity: (m['city'] ?? existing.locationCity) as String?,
        locationState: (m['state'] ?? existing.locationState) as String?,
        locationCountry: (m['country'] ?? existing.locationCountry ?? 'BR') as String?,
        headline: (m['headline'] ?? m['linkedin_headline'] ?? existing.headline) as String?,
      );
      await _repo.upsertPersonal(updated);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      // Aceita YYYY-MM-DD, YYYY-MM, YYYY/MM, MM/YYYY
      try {
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return DateTime.parse(value);
        if (RegExp(r'^\d{4}-\d{2}$').hasMatch(value)) return DateTime.parse('$value-01');
        if (RegExp(r'^\d{2}/\d{4}$').hasMatch(value)) {
          final parts = value.split('/');
          return DateTime(int.parse(parts[1]), int.parse(parts[0]), 1);
        }
        if (RegExp(r'^\d{4}$').hasMatch(value)) {
          return DateTime(int.parse(value), 1, 1);
        }
      } catch (_) {}
    }
    return null;
  }

  List<String> _toStringList(dynamic value) {
    if (value is String) {
      return value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (value is List) {
      return value.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    }
    if (value is Map) {
      // Pode ser estrutura com tools categorizadas
      final out = <String>[];
      value.forEach((k, v) {
        out.addAll(_toStringList(v));
      });
      return out;
    }
    return const [];
  }
}
