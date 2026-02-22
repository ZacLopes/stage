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
}
