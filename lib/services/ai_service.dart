import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/models.dart';
import '../features/jobs/models/adapted_resume.dart';
import '../features/jobs/models/job_skills_extraction.dart';
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
  // Timeout cliente subiu de 9s pra 12s em 2026-05-27. Servidor tem
  // OPENAI_TIMEOUT_MS=8000 + ~1-2s de overhead Supabase Gateway + cache
  // lookup → 9s era margem apertada em network lento. 12s dá folga
  // pra retries internos do gateway sem mascarar lentidão real da IA.
  Future<MatchResult> analyzeMatch(String jobId) async {
    final response = await _client.functions
        .invoke('analyze-match', body: {'job_id': jobId})
        .timeout(const Duration(seconds: 12));

    if (response.status != 200) {
      throw Exception('analyze-match status ${response.status}');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    return _parseMatchResult(data);
  }

  /// Versão de prompt do match que o cliente lê do cache (`match_analyses`).
  /// Tem que bater com `PROMPT_VERSION` em `analyze-match/index.ts` —
  /// descasamento vira cache miss no cliente, evitando que scores de regras
  /// antigas apareçam até a IA recomputar.
  ///
  /// O valor REAL em uso vem de `app_config.match_prompt_version`, lido 1x por
  /// sessão em [_resolveMatchPromptVersion]. Trocar esse valor no banco é o
  /// "botão de rollback" instantâneo, sem precisar de release.
  ///
  /// SEM FALLBACK de versão: quando o `app_config` não pode ser lido (rede/RLS)
  /// ou vem vazio, [_resolveMatchPromptVersion] devolve `null` e
  /// [fetchCachedMatches] NÃO hidrata cache nenhum — o cliente cai no
  /// determinístico. Antes o fallback era 'v4' hardcoded, que em QUALQUER falha
  /// de rede hidratava scores da maior coorte MORTA (pré-taxonomia, pré-bônus
  /// de cargo, ~18k rows que o servidor não grava mais): servir cache de uma
  /// versão que ninguém escreve é pior do que não servir cache. (Fase 7 Onda 1.)
  ///
  /// Puro e testável: dado o valor cru do `app_config`, resolve a versão de
  /// confiança (trim + não-vazia) ou `null`.
  static String? resolveMatchPromptVersionFromConfig(String? raw) {
    final v = raw?.trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  /// Cache em memória da versão lida do `app_config` (1 leitura por sessão).
  /// Estático pra ser compartilhado entre instâncias de [AIService]. Só cacheia
  /// versão resolvida (não-nula); falha/vazio reavaliam na próxima chamada.
  static String? _matchPromptVersionCache;

  /// Permite resetar o cache em teste/diagnóstico (não usado em produção).
  static void debugResetMatchPromptVersionCache() =>
      _matchPromptVersionCache = null;

  /// Lê `app_config.match_prompt_version` (id=1) uma vez por sessão e cacheia.
  /// Best-effort igual ao [VersionService]: retorna `null` se não conseguir
  /// resolver (rede/RLS ou valor vazio) — o caller então NÃO hidrata cache
  /// (evita servir versão morta) e cai no determinístico. NUNCA quebra o feed.
  Future<String?> _resolveMatchPromptVersion() async {
    final cached = _matchPromptVersionCache;
    if (cached != null) return cached;
    try {
      final row = await _client
          .from('app_config')
          .select('match_prompt_version')
          .eq('id', 1)
          .maybeSingle();
      final resolved = resolveMatchPromptVersionFromConfig(
        row?['match_prompt_version'] as String?,
      );
      if (resolved != null) _matchPromptVersionCache = resolved;
      return resolved;
    } catch (_) {
      // Rede/RLS: sem versão confiável → sem hidratação (cai no determinístico).
      return null;
    }
  }

  /// Hidrata cache em batch: 1 SELECT direto na tabela match_analyses.
  /// Sem custo de IA. Retorna mapa jobId → MatchResult pros que estão cacheados.
  ///
  /// Filtra por `prompt_version` pra não pegar cache de prompts antigos. Sem
  /// isso, scores inflados de versões anteriores vazam pra UI até a IA
  /// recomputar (pode demorar uma sessão inteira).
  ///
  /// Se a versão não puder ser resolvida (`app_config` ilegível/vazio), devolve
  /// vazio SEM consultar — sem versão de confiança, hidratar seria servir cache
  /// de versão morta; melhor deixar o determinístico assumir.
  Future<Map<String, MatchResult>> fetchCachedMatches(List<String> jobIds) async {
    if (jobIds.isEmpty) return const {};
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const {};

    try {
      final promptVersion = await _resolveMatchPromptVersion();
      if (promptVersion == null) return const {};
      final rows = await _client
          .from('match_analyses')
          .select('job_id, score, reasons')
          .eq('user_id', userId)
          .eq('prompt_version', promptVersion)
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
  ///
  /// Key: `"$jobId|${extraSkills.join(',')}"` — adaptações com extra_skills
  /// diferentes geram cache distinto (alinha com o source_hash server-side).
  final Map<String, AdaptedResume> _adaptedCache = {};

  String _adaptedCacheKey(String jobId, List<String> extraSkills) {
    if (extraSkills.isEmpty) return jobId;
    final norm = extraSkills.map((s) => s.trim().toLowerCase()).toList()..sort();
    return '$jobId|${norm.join(',')}';
  }

  /// Adapta o currículo do user pra uma vaga específica.
  ///
  /// Lança [ResumeAdaptationException] em todas falhas previsíveis (perfil
  /// incompleto, rate limit, rejeição do validador anti-invenção). UI usa
  /// `e.code` pra mostrar mensagem certa.
  ///
  /// Quando `force=true`, ignora o cache server-side e força nova geração
  /// (usado pelo botão "Tentar de novo" da UI).
  ///
  /// `extraSkills`: skills que o user confirmou ter mas não estão no CV
  /// (vindas da tela de confirmação de skills). Vão pro server como
  /// `extra_skills` e são incluídas no CV adaptado.
  Future<AdaptedResume> adaptResume(
    String jobId, {
    bool force = false,
    List<String> extraSkills = const [],
  }) async {
    final cacheKey = _adaptedCacheKey(jobId, extraSkills);
    if (!force) {
      final cached = _adaptedCache[cacheKey];
      if (cached != null) return cached;
    }

    try {
      final response = await _client.functions
          .invoke(
            'adapt-resume-to-job',
            body: {
              'job_id': jobId,
              if (force) 'force': true,
              if (extraSkills.isNotEmpty) 'extra_skills': extraSkills,
            },
          )
          .timeout(const Duration(seconds: 120));

      // 120s: cobre step A (mini, até 50s) + step B (4o, até 50s) +
      // overhead da Edge Function (~10s). F5 adicionou o step B —
      // antes era 90s suficiente, agora a janela total cresceu pra
      // acomodar pipeline em 2 etapas.
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
        _adaptedCache[cacheKey] = adapted;
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
  /// Remove TODAS as variações de extraSkills daquele job.
  void clearAdaptedCache(String jobId) {
    _adaptedCache.removeWhere((key, _) => key == jobId || key.startsWith('$jobId|'));
  }

  // ============================================================
  // Skill extraction (gpt-4o-mini, cache server-side por vaga)
  // ============================================================

  /// Cache em memória das extrações já feitas nesta sessão. Mesmo a 2ª
  /// abertura do sheet de confirmação não dispara network request quando
  /// já tem resultado em memória.
  final Map<String, JobSkillsExtraction> _jobSkillsCache = {};

  /// Extrai skills atômicas dos requisitos+descrição de uma vaga e cruza
  /// contra o CV do user (in_cv) e contra confirmed_skills (pre_confirmed).
  ///
  /// Usado pela `SkillsConfirmationSheet`. Falhas viram exception — caller
  /// trata como "skip silencioso" (não bloqueia o fluxo de adaptação).
  Future<JobSkillsExtraction> extractJobSkills(String jobId) async {
    final cached = _jobSkillsCache[jobId];
    if (cached != null) return cached;

    final response = await _client.functions
        .invoke('extract-job-skills', body: {'job_id': jobId})
        .timeout(const Duration(seconds: 14));

    if (response.status != 200) {
      throw Exception('extract-job-skills status ${response.status}');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final result = JobSkillsExtraction.fromJson(data);
    _jobSkillsCache[jobId] = result;
    return result;
  }

  /// Limpa cache de extrações (ex: ao trocar de user / logout).
  void clearJobSkillsCache() {
    _jobSkillsCache.clear();
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
        return 'A IA gerou conteúdo que não bateu com seu currículo. Toque em "Tentar de novo" pra fazer mais uma rodada.';
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

    // Detecta Cenário C do servidor (analyze-match retorna 1 reason "Sem
    // perfil" matched=false com score=50). Converte pra MatchResult.unknown
    // pra UI renderizar card amarelo "Configure suas preferências" via
    // `match.isUnknown` em vez de "Match razoável 50%" enganoso.
    //
    // Acontece quando user tem `_hasProfileData=true` (qualquer skill basta)
    // mas perfil semanticamente vazio (sem narrativa). hasResume filtra
    // antes no _resolveMatch, mas defesa em profundidade aqui.
    final isScenarioC = reasons.length == 1 &&
        reasons.first.label == 'Sem perfil' &&
        !reasons.first.matched;
    if (isScenarioC) {
      return const MatchResult.unknown();
    }

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
    } on FunctionException catch (e) {
      // Em status != 200 o invoke lança FunctionException com o body em
      // e.details. 429 = rate limit diário (Fase 0 T0.2) — mensagem amigável
      // em vez de erro técnico; a UI existente exibe a mensagem da exception.
      final details = e.details;
      final code = details is Map ? details['error']?.toString() : null;
      if (e.status == 429 || code == 'rate_limit_exceeded') {
        throw Exception(
          'Você atingiu o limite diário de gerações de currículo. '
          'Tente de novo amanhã.',
        );
      }
      print('Error generating resume content: $e');
      rethrow;
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

  /// Gera headline + resumo a partir do PERFIL relacional (profile_*) e grava em
  /// profile_personal (server-side, RLS via JWT). Usado pela trilha de coleta pra
  /// "completar" a aba Perfil ao final. Retorna o resumo gerado, ou null se foi
  /// pulado (perfil sem substância) ou falhou — FAILURE-SAFE: a trilha não quebra.
  Future<String?> generateProfileSummary() async {
    try {
      final response =
          await _client.functions.invoke('generate-profile-summary');
      if (response.status != 200) return null;
      final data = response.data;
      if (data is! Map) return null;
      if (data['skipped'] == true) return null;
      final summary = data['summary'];
      if (summary is String && summary.trim().isNotEmpty) return summary.trim();
      return null;
    } catch (e) {
      return null; // não propaga: o resumo é um "plus", não pode travar a trilha
    }
  }

  /// Sugestões de skills por IA a partir do perfil (curso/experiência/área + o
  /// que já foi marcado). Failure-safe: lista vazia em erro/sem sugestão — o
  /// passo de sugestão da trilha simplesmente não aparece.
  Future<List<String>> suggestProfileSkills() async {
    try {
      final response =
          await _client.functions.invoke('suggest-profile-skills');
      if (response.status != 200) return const [];
      final data = response.data;
      if (data is! Map) return const [];
      final list = data['skills'];
      if (list is! List) return const [];
      return list
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      return const [];
    }
  }

  /// Interpreta TEXTO LIVRE (digitado na barra do chat) e mapeia para os IDs das
  /// opções de um passo de escolha (chips/slider). Usado pela trilha v2 quando o
  /// usuário responde por texto em vez de tocar. Failure-safe: null em
  /// erro/timeout/não-200 → o chat mantém o widget e pede pra tocar numa opção.
  Future<StepInterpretation?> interpretStepAnswer({
    required String stepId,
    required String question,
    required String freeText,
    required List<Map<String, String>> options,
    bool multi = false,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'interpret-step-answer',
        body: {
          'stepId': stepId,
          'question': question,
          'freeText': freeText,
          'options': options,
          'multi': multi,
        },
      ).timeout(const Duration(seconds: 20));
      if (response.status != 200) return null;
      final data = response.data;
      if (data is! Map) return null;
      final ids = data['matched_ids'];
      final matched =
          ids is List ? ids.whereType<String>().toList() : <String>[];
      final conf = data['confidence'];
      final confidence = conf is String ? conf : 'low';
      final r = data['reason'];
      final reason = r is String ? r : '';
      return StepInterpretation(
        matchedIds: matched,
        confidence: confidence,
        reason: reason,
      );
    } catch (e) {
      return null; // não propaga: o chat cai no widget de toque
    }
  }
}

/// Resultado da interpretação de texto livre num passo de escolha (F4).
/// [matchedIds] são ids de opção REAIS do passo (a edge filtra alucinação);
/// vazio = nada casou. [confidence] ∈ {high, medium, low}.
class StepInterpretation {
  final List<String> matchedIds;
  final String confidence;
  final String reason;
  const StepInterpretation({
    required this.matchedIds,
    required this.confidence,
    this.reason = '',
  });
}
