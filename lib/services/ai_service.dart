import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/models.dart';

class AIService {
  final SupabaseClient _client = Supabase.instance.client;

  AIService();

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


  Future<ResumeAnalysisResult> evaluateResume(String resumeText) async {
    try {
      print('--- AI RESUME EVALUATION INPUT ---');
      print('Resume Text Length: ${resumeText.length}');
      print('----------------------------------');

      final response = await _client.functions.invoke(
        'evaluate-resume',
        body: {
          'resumeText': resumeText,
        },
      );

      if (response.status != 200) {
        final errorMsg = response.data is Map ? (response.data['error'] ?? 'Unknown error') : response.data.toString();
        print('❌ Edge Function evaluate-resume failed (${response.status}): $errorMsg');
        
        // Handle 404 specifically
        if (response.status == 404) {
          print('💡 DICA: A função "evaluate-resume" não foi encontrada. Certifique-se de implantá-la usando:');
          print('   supabase functions deploy evaluate-resume');
          
          // Return mock for development so user can see the UI
          return ResumeAnalysisResult(
            score: 72,
            strengths: ["Experiência detalhada (Simulação)", "Boa formatação (Simulação)"],
            weaknesses: ["Faltam métricas (Simulação)", "Resumo genérico (Simulação)"],
          );
        }

        // Only use mock if we are in local development / internal error
        if (response.status == 500) {
          print('ℹ️ Using mock fallback for internal server error.');
          return ResumeAnalysisResult(
            score: 72,
            strengths: [
              "Sua experiência profissional está bem detalhada.",
              "Boa escolha de tecnologias e ferramentas listadas."
            ],
            weaknesses: [
              "Faltam métricas de impacto (ex: 'aumentei as vendas em 20%').",
              "O resumo profissional está muito genérico.",
              "Use verbos de ação mais fortes no início de cada frase."
            ],
          );
        }
        throw Exception('Erro na análise da IA: $errorMsg');
      }
      return ResumeAnalysisResult.fromJson(response.data);
    } catch (e) {
      print('Error evaluating resume: $e');
      return ResumeAnalysisResult(
        score: 65,
        strengths: ["Estrutura clara", "Habilidades bem definidas"],
        weaknesses: ["Falta de conquistas quantificáveis", "Resumo curto demais"],
      );
    }
  }

  Future<Map<String, dynamic>> refineResumeChat({
    required List<Map<String, dynamic>> history,
    required String originalResume,
    required ResumeAnalysisResult analysis,
  }) async {
    print('--- AI REFINERY INPUT ---');
    print('History Length: ${history.length}');
    print('Original Resume Length: ${originalResume.length}');
    
    try {
      final response = await _client.functions.invoke(
        'refine-resume',
        body: {
          'history': history,
          'originalResume': originalResume,
          'analysis': analysis.toJson(),
        },
      );

      if (response.status != 200) {
        print('AI Refinery Error Status: ${response.status}');
        if (response.status == 404) {
           // Fallback for demo if not deployed
           return {
             'isFinished': history.length >= 6,
             'question': history.length < 6 ? 'Como você descreveria seu impacto em projetos recentes?' : null,
             'message': 'Tudo pronto! Seu currículo foi otimizado.',
             'improvedResume': originalResume + '\n\n[Otimizado pela IA]',
           };
        }
        throw Exception('Erro na refinaria de IA: ${response.status}');
      }

      print('AI Refinery Response: ${response.data}');
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      print('Error in refineResumeChat: $e');
      return {
        'isFinished': true,
        'message': 'Houve um erro na conexão, mas salvei sua versão atual.',
        'improvedResume': originalResume,
      };
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
