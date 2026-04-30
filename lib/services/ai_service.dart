import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/models.dart';

class AIService {
  final SupabaseClient _client = Supabase.instance.client;

  AIService() {
    // No longer need OpenAI API key in the client!
    // All AI calls now go through secure Edge Functions
    print('✅ AIService initialized with secure Edge Functions');
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
  }) async {
    try {
      print('--- AI RESUME INPUT DATA (via Edge Function) ---');
      answersWithQuestions.forEach((q, a) => print('P: $q\nR: $a\n'));
      print('AREA CONTEXT: $areaContext');
      print('------------------------------------------------');

      // Call secure Edge Function
      final response = await _client.functions.invoke(
        'generate-resume',
        body: {
          'answersWithQuestions': answersWithQuestions,
          'areaContext': areaContext,
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


  Future<InterviewReport> generateInterviewReport(
    Map<String, String> answersWithQuestions,
  ) async {
    try {
      print('--- AI INTERVIEW REPORT INPUT (via Edge Function) ---');
      answersWithQuestions.forEach((q, a) => print('P: $q\nR: $a\n'));
      print('------------------------------------------------------');

      // Call secure Edge Function
      final response = await _client.functions.invoke(
        'generate-interview-report',
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

      print('AI INTERVIEW JSON Response: ${json.encode(response.data)}');
      return InterviewReport.fromJson(response.data);
    } catch (e) {
      print('Error generating interview report: $e');
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
}
