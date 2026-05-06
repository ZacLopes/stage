import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/models.dart';
import '../features/jobs/utils/match_score.dart';

class AIService {
  final SupabaseClient _client = Supabase.instance.client;

  AIService();

  // ============================================================
  // Match analysis (gpt-4o-mini com cache em match_analyses)
  // ============================================================

  /// Calcula match IA pra uma vaga. Lança exception em qualquer falha —
  /// caller (JobsSwipeScreen) faz fallback pro determinístico.
  Future<MatchResult> analyzeMatch(String jobId) async {
    final response = await _client.functions
        .invoke('analyze-match', body: {'job_id': jobId})
        .timeout(const Duration(seconds: 9));

    if (response.status != 200) {
      throw Exception('analyze-match status ${response.status}');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    return _parseMatchResult(data);
  }

  /// Hidrata cache em batch: 1 SELECT direto na tabela match_analyses.
  /// Sem custo de IA. Retorna mapa jobId → MatchResult pros que estão cacheados.
  Future<Map<String, MatchResult>> fetchCachedMatches(List<String> jobIds) async {
    if (jobIds.isEmpty) return const {};
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const {};

    try {
      final rows = await _client
          .from('match_analyses')
          .select('job_id, score, reasons')
          .eq('user_id', userId)
          .inFilter('job_id', jobIds);

      final out = <String, MatchResult>{};
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final jobId = row['job_id']?.toString();
        if (jobId == null) continue;
        out[jobId] = _parseMatchResult(row);
      }
      return out;
    } catch (e) {
      // Falha no SELECT não pode quebrar a tela. Cliente cai pro determinístico.
      print('fetchCachedMatches failed: $e');
      return const {};
    }
  }

  static MatchResult _parseMatchResult(Map<String, dynamic> data) {
    final score = (data['score'] as num?)?.toInt().clamp(0, 100) ?? 0;
    final rawReasons = (data['reasons'] as List?) ?? const [];
    final reasons = rawReasons.map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return MatchReason(
        label: m['label']?.toString() ?? '',
        matched: m['matched'] == true,
        weight: (m['weight'] as num?)?.toInt() ?? 0,
        detail: m['detail']?.toString(),
      );
    }).toList();
    return MatchResult(score: score, reasons: reasons);
  }

  Future<ProfileContent> generateProfileContent(
    Map<String, String> answersWithQuestions,
  ) async {
    try {
      print('--- AI INPUT DATA (via Edge Function) ---');
      answersWithQuestions.forEach((q, a) => print('P: $q\nR: $a\n'));
      print('------------------------------------------');

      // Call secure Edge Function instead of OpenAI directly
      final response = await _client.functions.invoke(
        'generate-profile',
        body: {
          'answersWithQuestions': answersWithQuestions,
        },
      );

      if (response.status != 200) {
        final errorData = response.data;
        if (errorData is Map && errorData.containsKey('error')) {
          throw Exception('Edge Function error: ${errorData['error']}');
        }
        throw Exception('Edge Function returned status ${response.status}');
      }

      print('AI JSON Response: ${json.encode(response.data)}');
      return ProfileContent.fromJson(response.data);
    } catch (e) {
      print('Error generating profile content: $e');
      rethrow;
    }
  }

  Future<ResumeContent> generateResumeContent(
    Map<String, String> answersWithQuestions, {
    String? areaContext,
    String? language, // 'pt' | 'en' (defaults to 'pt' on the server)
  }) async {
    try {
      print('--- AI RESUME INPUT DATA (via Edge Function) ---');
      answersWithQuestions.forEach((q, a) => print('P: $q\nR: $a\n'));
      print('AREA CONTEXT: $areaContext  •  LANGUAGE: ${language ?? "pt"}');
      print('------------------------------------------------');

      // Call secure Edge Function
      final response = await _client.functions.invoke(
        'generate-resume',
        body: {
          'answersWithQuestions': answersWithQuestions,
          'areaContext': areaContext,
          if (language != null) 'language': language,
        },
      );

      if (response.status != 200) {
        final errorData = response.data;
        if (errorData is Map && errorData.containsKey('error')) {
          throw Exception('Edge Function error: ${errorData['error']}');
        }
        throw Exception('Edge Function returned status ${response.status}');
      }

      print('AI RESUME JSON Response: ${json.encode(response.data)}');
      return ResumeContent.fromJson(response.data);
    } catch (e) {
      print('Error generating resume content: $e');
      rethrow;
    }
  }


  // ============================================================
  // Phase 5 — Bullet & summary generation
  // ============================================================

  Future<BulletGenerationResult> generateBullets({
    required String experiencePhaseId,
    required String campaignId,
    String? clarificationAnswer,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'generate-bullets',
        body: {
          'experience_phase_id': experiencePhaseId,
          'campaign_id': campaignId,
          if (clarificationAnswer != null) 'clarification_answer': clarificationAnswer,
        },
      );

      if (response.status != 200) {
        throw Exception('generate-bullets error: ${response.status}');
      }

      final data = Map<String, dynamic>.from(response.data as Map);
      final rawBullets = data['bullets'] as List?;
      final rawClarification = data['needs_clarification'];

      final bullets = (rawBullets ?? []).map((b) {
        final map = Map<String, dynamic>.from(b as Map);
        return BulletVersion(
          id: map['version_id'] as String? ?? '',
          campaignId: campaignId,
          experiencePhaseId: experiencePhaseId,
          content: map['content'] as String,
          angle: map['angle'] as String,
          confidence: (map['confidence'] as num?)?.toDouble() ?? 0.8,
        );
      }).toList();

      BulletClarification? clarification;
      if (rawClarification != null) {
        clarification = BulletClarification.fromJson(
          Map<String, dynamic>.from(rawClarification as Map),
        );
      }

      return BulletGenerationResult(bullets: bullets, needsClarification: clarification);
    } catch (e) {
      print('Error generating bullets: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> suggestTools(String campaignId) async {
    try {
      final response = await _client.functions.invoke(
        'suggest-tools',
        body: {'campaign_id': campaignId},
      );

      if (response.status != 200) {
        throw Exception('suggest-tools error: ${response.status}');
      }

      final data = Map<String, dynamic>.from(response.data as Map);
      final rawTools = data['tools'] as List?;
      return {
        'tools': (rawTools ?? []).map((e) => e.toString()).toList(),
        'job_context': data['job_context'] as String?,
      };
    } catch (e) {
      print('Error suggesting tools: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> generateSummary(String campaignId) async {
    try {
      final response = await _client.functions.invoke(
        'generate-summary',
        body: {'campaign_id': campaignId},
      );

      if (response.status != 200) {
        throw Exception('generate-summary error: ${response.status}');
      }

      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      print('Error generating summary: $e');
      rethrow;
    }
  }
}
