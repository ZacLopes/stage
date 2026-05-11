import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/models.dart';
import '../features/jobs/models/adapted_resume.dart';
import '../features/jobs/utils/match_score.dart';

/// Erro estruturado da adaptação de currículo. UI usa `code` pra distinguir
/// "perfil incompleto" (sugere completar) de erro temporário (oferece retry).
class ResumeAdaptationException implements Exception {
  /// 'profile_incomplete', 'rate_limited', 'adaptation_rejected',
  /// 'ai_response_invalid', 'job_not_found', 'unauthorized', 'timeout',
  /// 'network'.
  final String code;
  final String message;
  const ResumeAdaptationException(this.code, this.message);

  @override
  String toString() => 'ResumeAdaptationException($code): $message';
}

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

  // ============================================================
  // Resume adaptation (gpt-4o-mini com cache em adapted_resumes)
  // ============================================================

  /// Cache em memória pra mesma sessão (evita re-fetch quando usuário fecha
  /// e reabre o sheet rapidamente). Cache server-side (tabela
  /// adapted_resumes) cobre sessões diferentes.
  final Map<String, AdaptedResume> _adaptedCache = {};

  /// Adapta o currículo do user pra uma vaga específica.
  ///
  /// Lança [ResumeAdaptationException] em todas falhas previsíveis (perfil
  /// incompleto, rate limit, rejeição do validador anti-invenção). UI usa
  /// `e.code` pra mostrar mensagem certa.
  ///
  /// Quando `force=true`, ignora o cache server-side e força nova geração
  /// (usado pelo botão "Tentar de novo" da UI).
  Future<AdaptedResume> adaptResume(String jobId, {bool force = false}) async {
    if (!force) {
      final cached = _adaptedCache[jobId];
      if (cached != null) return cached;
    }

    try {
      final response = await _client.functions
          .invoke(
            'adapt-resume-to-job',
            body: {'job_id': jobId, if (force) 'force': true},
          )
          .timeout(const Duration(seconds: 30));

      // Status 200 path. Em status != 200 o invoke lança FunctionException
      // (capturado abaixo) — não dá pra confiar em response.status aqui.
      final data = response.data;
      if (data is! Map) {
        throw const ResumeAdaptationException(
          'ai_response_invalid',
          'Resposta inválida do servidor.',
        );
      }
      final mapped = Map<String, dynamic>.from(data);

      try {
        final adapted = AdaptedResume.fromJson(mapped, jobId: jobId);
        _adaptedCache[jobId] = adapted;
        return adapted;
      } catch (parseErr, parseStack) {
        // Erros de parse aqui são bugs do contrato edge↔client (não do user).
        // Logamos pra debug e jogamos exception estruturada.
        print('[AIService.adaptResume] parse failed: $parseErr');
        print('[AIService.adaptResume] stack: $parseStack');
        print('[AIService.adaptResume] payload keys: ${mapped.keys.toList()}');
        throw ResumeAdaptationException(
          'ai_response_invalid',
          'Resposta veio em formato inesperado: $parseErr',
        );
      }
    } on ResumeAdaptationException {
      rethrow;
    } on FunctionException catch (e) {
      // Edge function retornou status != 200. O body com {error, detail} vem
      // em e.details. Convertemos pro nosso erro estruturado pra UI saber
      // distinguir "profile_incomplete" (mostra ícone de pessoa + CTA pra
      // completar perfil) de erros técnicos.
      final details = e.details;
      String code = 'unknown';
      String? detail;
      if (details is Map) {
        code = details['error']?.toString() ?? 'unknown';
        detail = details['detail']?.toString();
      }
      throw ResumeAdaptationException(code, detail ?? _humanizeError(code));
    } on FormatException catch (e) {
      throw ResumeAdaptationException(
        'ai_response_invalid',
        'Não consegui ler a resposta: ${e.message}',
      );
    } catch (e) {
      // Timeout, conectividade, etc.
      final msg = e.toString();
      if (msg.toLowerCase().contains('timeout')) {
        throw const ResumeAdaptationException(
          'timeout',
          'A adaptação demorou demais. Tente de novo.',
        );
      }
      throw ResumeAdaptationException('network', msg);
    }
  }

  /// Limpa cache em memória pra uma vaga (ex: depois que user editou perfil).
  void clearAdaptedCache(String jobId) {
    _adaptedCache.remove(jobId);
  }

  /// Mensagens humanas pra códigos de erro do edge function. Source-of-truth
  /// pra UI mostrar texto consistente.
  static String _humanizeError(String code) {
    switch (code) {
      case 'profile_incomplete':
        return 'Complete seu perfil ou suba seu currículo antes de adaptar.';
      case 'job_not_found':
        return 'Esta vaga não está mais disponível.';
      case 'rate_limited':
        return 'Você atingiu o limite diário de adaptações. Tente amanhã.';
      case 'adaptation_rejected':
        return 'A adaptação não passou na verificação de integridade. Tente novamente.';
      case 'ai_response_invalid':
        return 'Resposta da IA veio em formato inesperado. Tente de novo.';
      case 'unauthorized':
        return 'Sessão expirou. Faça login novamente.';
      default:
        return 'Algo deu errado. Tente de novo em instantes.';
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
