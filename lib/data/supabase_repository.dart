import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/models.dart';

class SupabaseRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ============================================
  // CACHE SYSTEM
  // ============================================
  
  List<Track>? _cachedTracks;
  Map<String, List<Phase>> _cachedPhases = {}; // trackId -> phases
  Map<String, List<Question>> _cachedQuestions = {}; // phaseId -> questions
  bool _isCacheInitialized = false;

  Future<void> prefetchAllData() async {
    if (_isCacheInitialized) return;

    try {
      // Prefetching all gamification data (tracks/phases/questions)
      
      // 1. Fetch ALL Tracks
      final tracksResponse = await _client
          .from('tracks')
          .select()
          .order('order_index', ascending: true);
      final fetchedTracks = (tracksResponse as List).map((e) => Track.fromMap(e)).toList();
      fetchedTracks.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      // 2. Fetch ALL Phases
      final phasesResponse = await _client
          .from('phases')
          .select()
          .order('order_index');
      final fetchedPhases = (phasesResponse as List).map((e) => Phase.fromMap(e)).toList();
      
      // Organize phases by trackId
      final Map<String, List<Phase>> phasesMap = {};
      // Sort all phases by orderIndex first
      fetchedPhases.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      
      for (var phase in fetchedPhases) {
        if (!phasesMap.containsKey(phase.trackId)) {
          phasesMap[phase.trackId] = [];
        }
        phasesMap[phase.trackId]!.add(phase);
      }

      // 3. Fetch ALL Questions
      final questionsResponse = await _client
          .from('questions')
          .select()
          .order('id');
      final fetchedQuestions = (questionsResponse as List).map((e) => Question.fromMap(e)).toList();
      
      // Organize questions by phaseId
      final Map<String, List<Question>> questionsMap = {};
      // Sort all questions by ID first to guarantee order
      fetchedQuestions.sort((a, b) => a.id.compareTo(b.id));

      for (var question in fetchedQuestions) {
        if (!questionsMap.containsKey(question.phaseId)) {
          questionsMap[question.phaseId] = [];
        }
        questionsMap[question.phaseId]!.add(question);
      }

      // ATOMIC ASSIGNMENT
      _cachedTracks = fetchedTracks;
      _cachedPhases = phasesMap;  // Assumes _cachedPhases is Map<String, List<Phase>>
      _cachedQuestions = questionsMap; // Assumes _cachedQuestions is Map<String, List<Question>>
      _isCacheInitialized = true;
      
      // Cache populated: ${fetchedTracks.length} tracks / ${fetchedPhases.length} phases / ${fetchedQuestions.length} questions
      
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('SocketException') || 
          errorMsg.contains('HandshakeException') ||
          errorMsg.contains('Connection closed')) {
        print('📡 Network unavailable during startup. App will retry when connection is restored.');
      } else {
        print('❌ Error prefetching data: $e');
      }
      // On error, we just leave cache empty and fall back to individual fetches if needed
    }
  }

  void clearCache() {
    _cachedTracks = null;
    _cachedPhases.clear();
    _cachedQuestions.clear();
    _isCacheInitialized = false;
    print('🧹 Cache cleared.');
  }

  // ============================================
  // TRACKS (Mundos)
  // ============================================

  Future<List<Track>> getTracks() async {
    // Return cache if available
    if (_cachedTracks != null && _cachedTracks!.isNotEmpty) {
      return _cachedTracks!;
    }

    try {
      final response = await _client
          .from('tracks')
          .select()
          .order('order_index', ascending: true);
      
      final tracks = (response as List).map((e) => Track.fromMap(e)).toList();
      tracks.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return tracks;
    } catch (e) {
      print('Error fetching tracks: $e');
      return [];
    }
  }

  // ============================================
  // PHASES (Etapas)
  // ============================================

  Future<List<Phase>> getPhases(String trackId) async {
    // Return cache if available
    if (_cachedPhases.containsKey(trackId)) {
      return _cachedPhases[trackId]!;
    }

    try {
      final response = await _client
          .from('phases')
          .select()
          .eq('track_id', trackId)
          .order('order_index', ascending: true);
      
      return (response as List).map((e) => Phase.fromMap(e)).toList();
    } catch (e) {
      print('Error fetching phases: $e');
      return [];
    }
  }

  // ============================================
  // QUESTIONS
  // ============================================

  Future<List<Question>> getQuestions(String phaseId) async {
    // Return cache if available
    if (_cachedQuestions.containsKey(phaseId)) {
      return _cachedQuestions[phaseId]!;
    }

    try {
      final response = await _client
          .from('questions')
          .select()
          .eq('phase_id', phaseId)
          .order('id', ascending: true);
      
      return (response as List).map((e) => Question.fromMap(e)).toList();
    } catch (e) {
      print('Error fetching questions: $e');
      return [];
    }
  }

  // ============================================
  // USER PROFILE
  // ============================================

  Future<UserProfile?> getUserProfile() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle(); // Use maybeSingle instead of single to avoid error if not found
      
      if (response == null) {
        // Profile doesn't exist, create it
        final user = _client.auth.currentUser!;
        // Nome via cadeia de fallbacks (full_name → given+family → email
        // prefix → null). Quando null, gravamos string vazia — coluna no DB
        // é NOT NULL. App detecta nome vazio via UserViewModel.needsName e
        // abre a tela "Como podemos te chamar?".
        final resolvedName = resolveAuthName(user) ?? '';
        final newProfile = {
          'id': userId,
          'email': user.email ?? '',
          'name': resolvedName,
          'course': user.userMetadata?['course'] ?? '',
          'semester': user.userMetadata?['semester'] ?? '',
          'age': user.userMetadata?['age'],
          'phone': null, // preenchido depois no ProfileSetup
          'ai_consent': false,
          'ai_consent_timestamp': null,
        };

        await _client.from('user_profiles').insert(newProfile);
        return UserProfile.fromMap(newProfile);
      }
      
      // Auto-sync age if missing in profile but present in metadata (Fix for existing users)
      if (response['age'] == null) {
        final user = _client.auth.currentUser;
        if (user?.userMetadata?['age'] != null) {
           final ageFromMeta = user!.userMetadata!['age'];
           // Now safe to update because column exists
           await _client.from('user_profiles').update({'age': ageFromMeta}).eq('id', userId);
           response['age'] = ageFromMeta;
        }
      }
      
      return UserProfile.fromMap(response);
    } catch (e) {
      // Check for duplicate key error (race condition with trigger)
      if (e.toString().contains('duplicate key') || e.toString().contains('23505')) {
         print('⚠️ Race condition in profile creation detected. Retrying fetch...');
         try {
            // Read-after-write consistency check
            final userId = _client.auth.currentUser?.id;
            if (userId != null) {
              final response = await _client
                  .from('user_profiles')
                  .select()
                  .eq('id', userId)
                  .single(); // Should exist now
              return UserProfile.fromMap(response);
            }
         } catch (retryError) {
            print('Retry fetch failed: $retryError');
         }
      }
      
      print('Error fetching user profile: $e');
      // Return null so ViewModel can decide to show error or try again
      return null;
    }
  }

  Future<void> updateUserProfile(UserProfile profile) async {
    try {
      if (profile.id == null) {
        throw Exception('Cannot update profile without ID');
      }
      
      await _client
          .from('user_profiles')
          .update(profile.toMap())
          .eq('id', profile.id!);
    } catch (e) {
      print('Error updating user profile: $e');
      rethrow;
    }
  }

  Future<void> deleteUserData() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      print('🧹 Starting data cleanup for user: $userId');

      // 1. Delete Files from Storage (Storage does NOT cascade)
      try {
        final List<FileObject> files = await _client.storage.from('resumes').list(path: userId);
        if (files.isNotEmpty) {
          final List<String> pathsToDelete = files.map((file) => '$userId/${file.name}').toList();
          await _client.storage.from('resumes').remove(pathsToDelete);
          print('✅ Deleted ${pathsToDelete.length} files from storage.');
        }
      } catch (e) {
        print('⚠️ Non-critical error deleting storage files: $e');
      }

      // 2. Manual cleanup of potential orphaned data or custom tables 
      // (Optional, as Auth delete cascades into Profiles which cascade into everything else)
      // We skip manual DB deletes here to avoid constraint/RLS issues that might block deletion.
      
      print('✅ Pre-deletion cleanup complete.');
    } catch (e) {
      print('❌ Error in deleteUserData: $e');
      // We don't rethrow here because we want to attempt the Auth deletion anyway
    }
  }

  Future<void> deleteAuthAccount() async {
    try {
      await _client.rpc('delete_user');
      print('✅ Auth account deleted successfully via RPC.');
    } catch (e) {
      print('Error deleting auth account: $e');
      rethrow;
    }
  }

  Future<void> _safeDelete(String table, String column, String value) async {
    try {
      await _client.from(table).delete().eq(column, value);
    } catch (_) {
      // Ignore error (table might not exist)
    }
  }

  // ============================================
  // USER PROGRESS
  // ============================================

  Future<void> markPhaseCompleted(String phaseId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _client.from('user_progress').upsert({
        'user_id': userId,
        'phase_id': phaseId,
        'completed': true,
        'completed_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error marking phase completed: $e');
      rethrow;
    }
  }

  Future<bool> isPhaseCompleted(String phaseId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await _client
          .from('user_progress')
          .select()
          .eq('user_id', userId)
          .eq('phase_id', phaseId)
          .eq('completed', true)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      print('Error checking phase completion: $e');
      return false;
    }
  }

  Future<Set<String>> getCompletedPhaseIds() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return {};

      final response = await _client
          .from('user_progress')
          .select('phase_id')
          .eq('user_id', userId)
          .eq('completed', true);
      
      return (response as List)
          .map((e) => e['phase_id'] as String)
          .toSet();
    } catch (e) {
      print('Error getting completed phases: $e');
      return {};
    }
  }

  Future<bool> isTrackCompleted(String trackId) async {
    try {
      final phases = await getPhases(trackId);

      if (phases.isEmpty) return false;

      final completedPhases = await getCompletedPhaseIds();
      
      // Check if all active phases in this track are completed
      return phases.every((phase) => completedPhases.contains(phase.id));
    } catch (e) {
      print('Error checking track completion: $e');
      return false;
    }
  }

  Future<bool> isEntireCourseCompleted() async {
    try {
      final totalPhases = await getTotalPhaseCount();
      if (totalPhases <= 0) return false;

      final tracks = await getTracks();
      final Set<String> activePhaseIds = {};
      for (var track in tracks) {
        final phases = await getPhases(track.id);
        activePhaseIds.addAll(phases.map((p) => p.id));
      }

      final completedPhases = await getCompletedPhaseIds();
      final completedActive = completedPhases.where((id) => activePhaseIds.contains(id)).length;
      
      return completedActive >= activePhaseIds.length && activePhaseIds.isNotEmpty;
    } catch (e) {
      print('Error checking entire course completion: $e');
      return false;
    }
  }

  Future<Set<String>> getCompletedTrackIds() async {
    try {
      final tracks = await getTracks();
      final completedTrackIds = <String>{};

      for (var track in tracks) {
        if (await isTrackCompleted(track.id)) {
          completedTrackIds.add(track.id);
        }
      }

      return completedTrackIds;
    } catch (e) {
      print('Error getting completed tracks: $e');
      return {};
    }
  }

  Future<int> getTotalPhaseCount() async {
    try {
      // Fetch all phases to apply filter
      final List<Phase> allPhases = [];
      if (_isCacheInitialized) {
        _cachedPhases.forEach((_, phases) => allPhases.addAll(phases));
      } else {
        final response = await _client.from('phases').select();
        allPhases.addAll((response as List).map((e) => Phase.fromMap(e)).toList());
      }
      
      return allPhases.length;
    } catch (e) {
      print('Error getting total phase count: $e');
      // Fallback if count() fails or if using older Postgrest
      try {
         final response = await _client.from('phases').select('id');
         return (response as List).length;
      } catch (e2) {
        return 1; // Avoid division by zero
      }
    }
  }

  // ============================================
  // USER ANSWERS (for Resume Generation)
  // ============================================

  Future<void> saveAnswer(String questionId, String answer) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Explicit onConflict so the upsert actually upserts on
      // (user_id, question_id). Without this, default upsert uses the
      // primary key — and since `id` is auto-generated, every call
      // historically inserted a new row instead of replacing.
      await _client.from('user_answers').upsert({
        'user_id': userId,
        'question_id': questionId,
        'answer': answer,
        'answered_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,question_id');
    } catch (e) {
      print('Error saving answer: $e');
      rethrow;
    }
  }

  /// Replaces the user's answer for a given question by deleting any prior
  /// rows and inserting fresh. Used by the resume edit flow to ensure a
  /// single source-of-truth row per question.
  Future<void> replaceAnswer(String questionId, String answer) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');
    await _client
        .from('user_answers')
        .delete()
        .eq('user_id', userId)
        .eq('question_id', questionId);
    await _client.from('user_answers').insert({
      'user_id': userId,
      'question_id': questionId,
      'answer': answer,
      'answered_at': DateTime.now().toIso8601String(),
    });
  }

  /// Same as [saveRawResponse] but deletes any prior row for the same
  /// (user_id, phase_id) before inserting — works regardless of whether the
  /// UNIQUE constraint exists. Throws on failure (no silent swallowing).
  Future<void> replaceRawResponse({
    required String phaseId,
    required String question,
    required String answer,
    required String answerType,
    required int questionOrder,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');
    await _client
        .from('raw_responses')
        .delete()
        .eq('user_id', userId)
        .eq('phase_id', phaseId);
    await _client.from('raw_responses').insert({
      'user_id': userId,
      'phase_id': phaseId,
      'question': question,
      'answer': answer,
      'answer_type': answerType,
      'question_order': questionOrder,
    });
  }

  /// Fetches a target_job row by id.
  Future<TargetJob?> getTargetJob(String targetJobId) async {
    try {
      final data = await _client
          .from('target_jobs')
          .select()
          .eq('id', targetJobId)
          .maybeSingle();
      return data != null ? TargetJob.fromJson(data) : null;
    } catch (e) {
      print('Error fetching target job: $e');
      return null;
    }
  }

  /// Updates the active campaign's target_job (title and/or description).
  /// Returns the campaign id if successful.
  Future<void> updateTargetJob({
    required String campaignId,
    String? title,
    String? descriptionText,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    // Get the campaign's target_job_id
    final campaign = await _client
        .from('campaigns')
        .select('target_job_id')
        .eq('id', campaignId)
        .eq('user_id', userId)
        .maybeSingle();
    if (campaign == null) return;
    final targetJobId = campaign['target_job_id'] as String?;
    if (targetJobId == null) return;

    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (descriptionText != null) updates['description_text'] = descriptionText;
    if (updates.isEmpty) return;
    // is_skipped becomes false once user supplies a real title
    if (title != null && title.trim().isNotEmpty) updates['is_skipped'] = false;

    await _client.from('target_jobs').update(updates).eq('id', targetJobId);
  }

  /// Returns a map of {questionId → answer} for the given question IDs.
  /// Used by GamificationViewModel to restore partial phase progress.
  Future<Map<String, String>> getAnswersForQuestions(
      List<String> questionIds) async {
    if (questionIds.isEmpty) return {};
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return {};
      final response = await _client
          .from('user_answers')
          .select('question_id, answer')
          .eq('user_id', userId)
          .inFilter('question_id', questionIds);
      return {
        for (final row in response as List<dynamic>)
          row['question_id'] as String: row['answer'] as String,
      };
    } catch (e) {
      print('Error fetching answers for questions: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getUserAnswers() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _client
          .from('user_answers')
          .select('question_id, answer, answered_at')
          .eq('user_id', userId)
          .order('answered_at', ascending: false);

      // DEDUPE by question_id, keeping the most recent row. Defends against
      // the legacy `saveAnswer` bug that did upsert-without-onConflict, which
      // historically inserted multiple rows per (user_id, question_id) pair.
      final seen = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final item in response as List) {
        final qid = item['question_id'] as String?;
        if (qid == null) continue;
        if (seen.add(qid)) deduped.add(Map<String, dynamic>.from(item));
      }
      return deduped;
    } catch (e) {
      print('Error fetching user answers: $e');
      return [];
    }
  }

  /// Retorna respostas indexadas por `question_id` (ex: `M1_3_1_Q2`).
  /// Usado por `processModule1/2/3Answers` em `GamificationLogic`, que
  /// fazem lookup por ID estático. Inclui dedupe (mais recente vence) e
  /// orphan-guard de M3_D{2-6}_* quando o D1 correspondente sumiu.
  ///
  /// Diferente de `getUserAnswersWithQuestions()` (que indexa pelo enunciado
  /// da pergunta, formato esperado por prompts de IA).
  Future<Map<String, String>> getUserAnswersByQuestionId() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return {};

      final rawResponse = await _client
          .from('user_answers')
          .select('question_id, answer, answered_at')
          .eq('user_id', userId)
          .order('answered_at', ascending: false);

      // Dedupe por question_id, mais recente vence (mesma regra do
      // getUserAnswersWithQuestions).
      final seenQids = <String>{};
      final response = <Map<String, dynamic>>[];
      for (final item in rawResponse as List) {
        final qid = item['question_id'] as String?;
        if (qid == null) continue;
        if (seenQids.add(qid)) response.add(Map<String, dynamic>.from(item));
      }

      // Orphan-guard: M3_D{2-6}_{cat}_{idx} só vive se o D1 correspondente
      // existe. Caso contrário é resíduo de uma experiência deletada.
      final aliveExperiences = <String>{};
      final dRe = RegExp(r'^M3_D1_([a-z]+)_(\d+)$');
      for (final item in response) {
        final qid = item['question_id'] as String? ?? '';
        final m = dRe.firstMatch(qid);
        if (m != null) aliveExperiences.add('${m.group(1)}_${m.group(2)}');
      }
      response.removeWhere((item) {
        final qid = item['question_id'] as String? ?? '';
        final m = RegExp(r'^M3_D[2-6]_([a-z]+)_(\d+)$').firstMatch(qid);
        if (m == null) return false;
        return !aliveExperiences.contains('${m.group(1)}_${m.group(2)}');
      });

      final answersMap = <String, String>{};
      for (final item in response) {
        final qId = item['question_id'] as String;
        final rawAnswer = item['answer'];
        if (rawAnswer == null) continue;
        answersMap[qId] = rawAnswer is String
            ? rawAnswer
            : rawAnswer.toString();
      }
      return answersMap;
    } catch (e) {
      print('Error fetching user answers by question id: $e');
      return {};
    }
  }

  Future<Map<String, String>> getUserAnswersWithQuestions() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return {};

      // 1. Fetch raw answers (question_id, answer) — order DESC + dedup by
      //    question_id so legacy duplicate rows don't surface as phantom
      //    "...content #2" entries to the AI (a primary cause of ghost
      //    experiences re-appearing after delete).
      final rawResponse = await _client
          .from('user_answers')
          .select('question_id, answer, answered_at')
          .eq('user_id', userId)
          .order('answered_at', ascending: false);
      final seenQids = <String>{};
      final response = <Map<String, dynamic>>[];
      for (final item in rawResponse as List) {
        final qid = item['question_id'] as String?;
        if (qid == null) continue;
        if (seenQids.add(qid)) response.add(Map<String, dynamic>.from(item));
      }

      // 1b. ORPHAN GUARD: when an experience was deleted but a stray
      //     M3_D{N}_{cat}_{idx} row survived (RLS, network, etc.), filter
      //     it out before sending to the AI. Rule: an experience is
      //     "alive" only if its D1 row still exists. If D1 is gone, drop
      //     all D2-D6 with the same cat+idx — they're orphans.
      final aliveExperiences = <String>{}; // "${cat}_${idx}" set
      final dRe = RegExp(r'^M3_D1_([a-z]+)_(\d+)$');
      for (final item in response) {
        final qid = item['question_id'] as String? ?? '';
        final m = dRe.firstMatch(qid);
        if (m != null) aliveExperiences.add('${m.group(1)}_${m.group(2)}');
      }
      response.removeWhere((item) {
        final qid = item['question_id'] as String? ?? '';
        final m = RegExp(r'^M3_D[2-6]_([a-z]+)_(\d+)$').firstMatch(qid);
        if (m == null) return false;
        final key = '${m.group(1)}_${m.group(2)}';
        final orphan = !aliveExperiences.contains(key);
        if (orphan) {
          print('[getUserAnswersWithQuestions] dropping orphan answer: $qid');
        }
        return orphan;
      });
      
      // 2. Fetch all question contents for lookup
      final Map<String, String> qContentMap = {};
      
      if (_isCacheInitialized) {
        // Use cached questions if available
        for (var questions in _cachedQuestions.values) {
          for (var q in questions) {
            qContentMap[q.id] = q.content;
          }
        }
      } else {
        // Fallback to direct fetch if cache not ready
        final questionsResp = await _client.from('questions').select('id, content');
        for(var q in questionsResp as List) {
           qContentMap[q['id'].toString()] = q['content'].toString();
        }
      }

      final answersMap = <String, String>{};
      
      // Counter for duplicate keys (fixing Data Loss issue)
      final Map<String, int> keyCounts = {};

      for (var item in response as List) {
        final qId = item['question_id'] as String;
        final rawAnswer = item['answer'];
        String? answer;
        
        if (rawAnswer is String) {
          answer = rawAnswer;
        } else if (rawAnswer != null) {
          try {
             // Pretty print JSON for better readability by AI
             answer = const JsonEncoder.withIndent('  ').convert(rawAnswer);
          } catch (_) {
             answer = rawAnswer.toString();
          }
        }
        
        if (answer == null) continue;
        
        String? content = qContentMap[qId];
        
        // --- CONTEXT INJECTION (Fixing "Architect" context issue) ---
        if (content == null && qId.contains('_')) {
           try {
             final lastUnderscore = qId.lastIndexOf('_');
             if (lastUnderscore > 0) {
               final baseId = qId.substring(0, lastUnderscore);
               content = qContentMap[baseId];
               
               // Dynamic Context Injection based on ID patterns
               if (qId.startsWith("M3_2_1_Q2_COURSE")) {
                 content = "Curso/Certificação (${item['question_id']})";
               }
             }
           } catch (_) {}
        }

        // --- SPECIALLY HANDLED DYNAMIC QUESTIONS ---
        // Fix for Languages (M4_2_1_Q2): Replace placeholder with actual language from ID suffix
        // Also handle cases where content was found normally but still has placeholder
        if (qId.startsWith('M4_2_1_Q2_')) {
           final languageSuffix = qId.replaceFirst('M4_2_1_Q2_', '');
           // If content was found (either direct or via underscore logic above)
           if (content != null) {
              content = content.replaceAll('{language}', languageSuffix);
           }
        }
        
        // Specific Fallbacks
        if (content == null) {
           if (qId == 'M3_2_1_Q2') content = "Quais são as conquistas da sua estante de aprendizado?";
           else if (qId.startsWith('M3_1_1_Q2')) content = "Curso Extra / Certificação";
        }

        // --- KEY COLLISION HANDLING (Fixing Overwrite issue) ---
        String finalKey = content ?? 'Question [$qId]';
        
        if (keyCounts.containsKey(finalKey)) {
          final count = keyCounts[finalKey]! + 1;
          keyCounts[finalKey] = count;
          finalKey = "$finalKey #$count"; // Append #2, #3, etc.
        } else {
          keyCounts[finalKey] = 1;
        }

        answersMap[finalKey] = answer;
      }
      
      return answersMap;
    } catch (e) {
      print('Error fetching user answers with questions: $e');
      return {};
    }
  }


  // ============================================
  // SEED DATA (Admin only - for initial setup)
  // ============================================

  Future<void> seedData(
    List<Track> tracks,
    List<Phase> phases,
    List<Question> questions,
  ) async {
    try {
      // Insert tracks
      for (var track in tracks) {
        await _client.from('tracks').upsert(track.toMap());
      }

      // Insert phases
      print('Inserting ${phases.length} phases...');
      for (var phase in phases) {
        await _client.from('phases').upsert(phase.toMap());
      }

      // Insert questions
      print('Inserting ${questions.length} questions...');
      for (var question in questions) {
        await _client.from('questions').upsert(question.toMap());
      }

      print('Seed data uploaded successfully!');
    } catch (e) {
      rethrow;
    }
  }

  // Ensure a single question exists (Sync-on-demand)
  Future<void> ensureQuestionExists(Question question) async {
    try {
      // Always upsert to ensure content matches the latest version in code
      await _client.from('questions').upsert(question.toMap());
    } catch (e) {
      print('Error ensuring question exists: $e');
    }
  }

  // ============================================
  // SAVED RESUMES (Biblioteca)
  // ============================================

  Future<List<SavedResume>> getSavedResumes() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _client
          .from('saved_resumes')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      
      return (response as List).map((e) => SavedResume.fromMap(e)).toList();
    } catch (e) {
      print('Error fetching saved resumes: $e');
      return [];
    }
  }

  Future<SavedResume> saveResume(
    String title,
    List<int> pdfBytes, {
    SavedResumeSource source = SavedResumeSource.manual,
    Map<String, dynamic>? resumeData,
    String? templateId,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$timestamp.pdf';
      final storagePath = '$userId/$fileName';

      // 1. Upload to Storage
      await _client.storage.from('resumes').uploadBinary(
        storagePath,
        pdfBytes is Uint8List ? pdfBytes : Uint8List.fromList(pdfBytes),
        fileOptions: const FileOptions(contentType: 'application/pdf'),
      );

      // 2. Save record to table and return the inserted row
      final inserted = await _client
          .from('saved_resumes')
          .insert({
            'user_id': userId,
            'title': title,
            'file_path': storagePath,
            'source': source.dbValue,
            if (resumeData != null) 'resume_data': resumeData,
            if (templateId != null) 'template_id': templateId,
          })
          .select()
          .single();

      return SavedResume.fromMap(inserted);
    } catch (e) {
      print('Error saving resume: $e');
      rethrow;
    }
  }

  /// Substitui o PDF de um saved_resume e atualiza o template_id no DB.
  /// Usado quando o user troca o template de um CV existente na
  /// biblioteca: re-render no client → upload sobrescreve mesmo
  /// `file_path` → update da coluna `template_id`.
  ///
  /// Retorna o `SavedResume` atualizado.
  Future<SavedResume> updateResumeTemplate({
    required String resumeId,
    required String filePath,
    required List<int> pdfBytes,
    required String templateId,
  }) async {
    try {
      // 1. Sobrescreve o PDF no mesmo file_path (upsert: true). Mantém o
      //    path estável — não precisa atualizar file_path no DB.
      await _client.storage.from('resumes').uploadBinary(
        filePath,
        pdfBytes is Uint8List ? pdfBytes : Uint8List.fromList(pdfBytes),
        fileOptions: const FileOptions(
          contentType: 'application/pdf',
          upsert: true,
        ),
      );

      // 2. Atualiza template_id no DB e devolve a row atualizada.
      final updated = await _client
          .from('saved_resumes')
          .update({'template_id': templateId})
          .eq('id', resumeId)
          .select()
          .single();

      return SavedResume.fromMap(updated);
    } catch (e) {
      print('Error updating resume template: $e');
      rethrow;
    }
  }

  Future<void> deleteSavedResume(String resumeId, String filePath) async {
    try {
      // 1. Delete from Storage
      await _client.storage.from('resumes').remove([filePath]);

      // 2. Delete record from table
      await _client.from('saved_resumes').delete().eq('id', resumeId);
    } catch (e) {
      print('Error deleting saved resume: $e');
      rethrow;
    }
  }

  Future<Uint8List> downloadResume(String filePath) async {
    try {
      return await _client.storage.from('resumes').download(filePath);
    } catch (e) {
      print('Error downloading resume: $e');
      rethrow;
    }
  }

  Future<void> updateAIConsent(String userId, bool consent) async {
    try {
      await _client
          .from('user_profiles')
          .update({
            'ai_consent': consent,
            'ai_consent_timestamp': consent ? DateTime.now().toIso8601String() : null,
          })
          .eq('id', userId);
    } catch (e) {
      print('Error updating AI consent: $e');
      rethrow;
    }
  }

  Future<void> saveRawResponse({
    required String userId,
    required String phaseId,
    required String question,
    required String answer,
    required String answerType,
    required int questionOrder,
  }) async {
    try {
      await _client.from('raw_responses').upsert({
        'user_id': userId,
        'phase_id': phaseId,
        'question': question,
        'answer': answer,
        'answer_type': answerType,
        'question_order': questionOrder,
      }, onConflict: 'user_id,phase_id');
    } catch (e) {
      print('Error saving raw response: $e');
    }
  }

  Future<void> clearM1ResetNotice(String userId) async {
    try {
      final data = await _client
          .from('user_profiles')
          .select('gamification_data')
          .eq('id', userId)
          .single();
      final Map<String, dynamic> gData =
          Map<String, dynamic>.from(data['gamification_data'] ?? {});
      gData.remove('show_m1_reset_notice');
      await _client
          .from('user_profiles')
          .update({'gamification_data': gData})
          .eq('id', userId);
    } catch (e) {
      print('Error clearing M1 reset notice: $e');
    }
  }

  /// Fase 1 T1.7: fonte única do gate de onboarding. Substitui o marcador
  /// legacy `hasCampaign` (campaigns viraram fóssil; a bridge no banco cobre
  /// builds antigas que ainda criam campaign).
  Future<DateTime?> getOnboardingCompletedAt(String userId) async {
    try {
      final row = await _client
          .from('profile_personal')
          .select('onboarding_completed_at')
          .eq('user_id', userId)
          .maybeSingle();
      final raw = row?['onboarding_completed_at'] as String?;
      return raw != null ? DateTime.tryParse(raw) : null;
    } catch (e) {
      print('Error fetching onboarding_completed_at: $e');
      return null;
    }
  }

  /// Marca o onboarding como concluído. Idempotente: não sobrescreve data
  /// existente. INSERT mínimo é seguro (NOT NULLs de profile_personal têm
  /// default — verificado na Fase 1); upsert parcial só toca a coluna nova.
  Future<DateTime> markOnboardingCompleted(String userId) async {
    final existing = await getOnboardingCompletedAt(userId);
    if (existing != null) return existing;
    final now = DateTime.now().toUtc();
    await _withTransientRetry(() => _client.from('profile_personal').upsert({
          'user_id': userId,
          'onboarding_completed_at': now.toIso8601String(),
        }, onConflict: 'user_id'));
    return now;
  }

  Future<Campaign?> getLatestCampaign(String userId) async {
    try {
      final data = await _client
          .from('campaigns')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return data != null ? Campaign.fromJson(data) : null;
    } catch (e) {
      print('Error fetching campaign: $e');
      return null;
    }
  }

  Future<Campaign> createCampaignWithTargetJob({
    required String userId,
    String? jobTitle,
    String? descriptionText,
    String? sourceUrl,
    bool isSkipped = false,
  }) async {
    final jobData = await _withTransientRetry(() => _client.from('target_jobs').insert({
          'user_id': userId,
          'title': jobTitle,
          'description_text': descriptionText,
          'source_url': sourceUrl,
          'is_skipped': isSkipped,
        }).select().single());

    final targetJob = TargetJob.fromJson(jobData);
    final campaignName =
        (jobTitle != null && jobTitle.isNotEmpty) ? jobTitle : 'Campanha 1';

    final campaignData = await _withTransientRetry(() => _client.from('campaigns').insert({
          'user_id': userId,
          'target_job_id': targetJob.id,
          'name': campaignName,
          'status': 'draft',
        }).select().single());

    return Campaign.fromJson(campaignData);
  }

  /// Reexecuta uma operação até 3x com backoff (200ms, 600ms, 1.4s) quando o
  /// erro é tipicamente transiente: TCP fechado, timeout, header incompleto,
  /// DNS, etc. Erros 4xx do Postgres (RLS, constraint) NÃO são retryados —
  /// não fazem sentido tentar de novo.
  Future<T> _withTransientRetry<T>(Future<T> Function() task,
      {int maxAttempts = 3}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await task();
      } catch (e) {
        lastError = e;
        final msg = e.toString();
        final isTransient = msg.contains('Connection closed') ||
            msg.contains('SocketException') ||
            msg.contains('Connection reset') ||
            msg.contains('Failed host lookup') ||
            msg.contains('TimeoutException') ||
            msg.contains('ClientException') ||
            msg.contains('502') ||
            msg.contains('503') ||
            msg.contains('504');

        if (!isTransient || attempt == maxAttempts) rethrow;

        final delayMs = 200 * (1 << (attempt - 1)) + (attempt * 100);
        print('⚠️ Transient error (attempt $attempt/$maxAttempts): $e — retrying in ${delayMs}ms');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    throw lastError ?? Exception('Retry failed without explicit error');
  }

  // ============================================================
  // Phase 5 — Bullet & summary persistence
  // ============================================================

  /// Save an approved bullet chosen (or written) by the user.
  Future<ApprovedBullet> approveBullet({
    required String campaignId,
    required String finalText,
    required String source,
    required String experiencePhaseId,
    String? bulletVersionId,
    int displayOrder = 0,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    // Mark the chosen bullet_version as was_chosen
    if (bulletVersionId != null && source != 'user_written') {
      await _client.from('bullet_versions').update({'was_chosen': true}).eq('id', bulletVersionId);
    }

    final data = await _client.from('approved_bullets').insert({
      'campaign_id': campaignId,
      'user_id': userId,
      'bullet_version_id': bulletVersionId,
      'final_text': finalText,
      'display_order': displayOrder,
      'source': source,
      'experience_phase_id': experiencePhaseId,
      'is_active': true,
      'approved_at': DateTime.now().toIso8601String(),
    }).select().single();

    return ApprovedBullet.fromJson(data);
  }

  /// Fetch all active approved bullets for a campaign, ordered.
  Future<List<ApprovedBullet>> getApprovedBullets(String campaignId) async {
    try {
      final response = await _client
          .from('approved_bullets')
          .select()
          .eq('campaign_id', campaignId)
          .eq('is_active', true)
          .order('display_order', ascending: true);
      return (response as List).map((e) => ApprovedBullet.fromJson(e)).toList();
    } catch (e) {
      print('Error fetching approved bullets: $e');
      return [];
    }
  }

  /// Updates the text of an existing approved bullet.
  Future<void> updateApprovedBulletText(String bulletId, String newText) async {
    await _client
        .from('approved_bullets')
        .update({'final_text': newText})
        .eq('id', bulletId);
  }

  /// Soft-deletes an approved bullet (is_active = false).
  Future<void> softDeleteApprovedBullet(String bulletId) async {
    await _client
        .from('approved_bullets')
        .update({'is_active': false})
        .eq('id', bulletId);
  }

  /// Soft-deletes all approved bullets for a given experience phase.
  Future<void> softDeleteAllBulletsForPhase(
    String campaignId,
    String experiencePhaseId,
  ) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('approved_bullets')
        .update({'is_active': false})
        .eq('user_id', userId)
        .eq('campaign_id', campaignId)
        .eq('experience_phase_id', experiencePhaseId);
  }

  /// Permanently removes raw_responses for a given experience phase
  /// (e.g. m3.lead.0.d1 .. m3.lead.0.d6).
  Future<void> deleteRawResponsesForPhase(String experiencePhaseId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('raw_responses')
        .delete()
        .eq('user_id', userId)
        .like('phase_id', '$experiencePhaseId.%');
  }

  /// Permanently removes the user_answers entries for D1-D6 of a given
  /// experience (M3_D1_${cat}_${n} .. M3_D6_${cat}_${n}). Uses a single
  /// batch DELETE with `inFilter` for atomicity, logs the result, and
  /// verifies post-delete that no rows survived.
  Future<void> deleteExperienceUserAnswers(String cat, int idx) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      print('[deleteExperienceUserAnswers] no user id, skipping');
      return;
    }
    final ids = List.generate(6, (d) => 'M3_D${d + 1}_${cat}_$idx');

    // Batch delete (one round-trip)
    try {
      await _client
          .from('user_answers')
          .delete()
          .eq('user_id', userId)
          .inFilter('question_id', ids);
    } catch (e) {
      print('[deleteExperienceUserAnswers] batch delete FAILED for cat=$cat idx=$idx: $e');
      // Fall back to per-id loop in case `inFilter` isn't supported
      for (final id in ids) {
        try {
          await _client
              .from('user_answers')
              .delete()
              .eq('user_id', userId)
              .eq('question_id', id);
        } catch (e2) {
          print('[deleteExperienceUserAnswers] per-id delete FAILED for $id: $e2');
        }
      }
    }

    // Verify deletion and retry once for any survivors
    try {
      final survivors = await _client
          .from('user_answers')
          .select('question_id')
          .eq('user_id', userId)
          .inFilter('question_id', ids);
      final list = (survivors as List?) ?? const [];
      if (list.isNotEmpty) {
        print('[deleteExperienceUserAnswers] WARNING ${list.length} rows survived first delete: $list. Retrying.');
        for (final row in list) {
          final qid = (row as Map)['question_id'] as String?;
          if (qid == null) continue;
          try {
            await _client
                .from('user_answers')
                .delete()
                .eq('user_id', userId)
                .eq('question_id', qid);
          } catch (e) {
            print('[deleteExperienceUserAnswers] retry delete FAILED for $qid: $e');
          }
        }
      } else {
        print('[deleteExperienceUserAnswers] verified clean for cat=$cat idx=$idx');
      }
    } catch (e) {
      print('[deleteExperienceUserAnswers] verification query FAILED: $e');
    }
  }

  /// Save a chosen/edited professional summary to section_versions.
  Future<void> saveSectionVersion({
    required String campaignId,
    required String content,
    required int versionNumber,
    String? versionId,
    bool wasEdited = false,
    String? editedContent,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    // Always unmark every prior chosen version of this campaign+section so
    // we end up with a single "EM USO" row.
    await _client
        .from('section_versions')
        .update({'was_chosen': false})
        .eq('campaign_id', campaignId)
        .eq('section_type', 'resumo_profissional');

    if (versionId != null) {
      await _client.from('section_versions').update({
        'was_chosen': true,
        'was_edited': wasEdited,
        'edited_content': editedContent,
      }).eq('id', versionId);
    } else {
      await _client.from('section_versions').insert({
        'campaign_id': campaignId,
        'user_id': userId,
        'section_type': 'resumo_profissional',
        'content': content,
        'version_number': versionNumber,
        'model_used': 'user_written',
        'was_chosen': true,
        'was_edited': wasEdited,
        'edited_content': editedContent,
      });
    }
  }

  /// Fetches ALL summary versions for a campaign (chosen + history),
  /// ordered most-recent first. Used by the version history UI.
  Future<List<SectionVersion>> getAllSummaryVersions(String campaignId) async {
    try {
      final response = await _client
          .from('section_versions')
          .select()
          .eq('campaign_id', campaignId)
          .eq('section_type', 'resumo_profissional')
          .order('created_at', ascending: false);
      return (response as List).map((e) => SectionVersion.fromJson(e)).toList();
    } catch (e) {
      print('Error fetching summary versions: $e');
      return [];
    }
  }

  /// Marks a specific section_version as the new chosen one (and unmarks all
  /// other versions of the same campaign + section).
  Future<void> chooseSummaryVersion(String campaignId, String versionId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');
    await _client
        .from('section_versions')
        .update({'was_chosen': false})
        .eq('campaign_id', campaignId)
        .eq('section_type', 'resumo_profissional');
    await _client
        .from('section_versions')
        .update({'was_chosen': true})
        .eq('id', versionId);
  }

  /// Fetch the approved (was_chosen) professional summary for a campaign.
  Future<SectionVersion?> getApprovedSummary(String campaignId) async {
    try {
      final response = await _client
          .from('section_versions')
          .select()
          .eq('campaign_id', campaignId)
          .eq('section_type', 'resumo_profissional')
          .eq('was_chosen', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response != null ? SectionVersion.fromJson(response) : null;
    } catch (e) {
      print('Error fetching approved summary: $e');
      return null;
    }
  }
}

/// Normaliza nome humano pra Title Case com preposições BR em minúsculo.
/// Trim, colapsa whitespace, primeira letra de cada palavra maiúscula.
///
/// Exemplos:
///   "joao silva"        → "Joao Silva"
///   "JOAO SILVA"        → "Joao Silva"
///   "  joão  da silva " → "João da Silva"
///   "MARIA DOS SANTOS"  → "Maria dos Santos"
///   "Pedro"             → "Pedro"
///
/// Preposições ("de", "da", "do", "dos", "das", "e") ficam em minúsculo
/// **só quando não são a primeira palavra** — "Da Silva" sozinho fica "Da Silva".
String normalizeName(String input) {
  final cleaned = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return cleaned;

  const lowercaseConnectors = {
    'de', 'da', 'do', 'dos', 'das', 'e', 'di', 'du', 'del', 'della', 'van', 'von',
  };

  final parts = cleaned.split(' ');
  final buf = <String>[];
  for (var i = 0; i < parts.length; i++) {
    final word = parts[i];
    if (word.isEmpty) continue;
    final lower = word.toLowerCase();
    if (i > 0 && lowercaseConnectors.contains(lower)) {
      buf.add(lower);
    } else {
      // toUpperCase do primeiro caracter cobre acentos (á → Á, etc.).
      buf.add(lower[0].toUpperCase() + lower.substring(1));
    }
  }
  return buf.join(' ');
}

/// Cadeia de fallbacks pra extrair o nome do usuário a partir do `User` do
/// Supabase. Retorna `null` se nada decente sobrou — o app trata `null` como
/// sinal pra abrir a tela "Como podemos te chamar?".
///
/// Ordem:
/// 1. `userMetadata['full_name']` — Google, e Apple quando o name vem no JWT
/// 2. `userMetadata['name']` — alguns providers
/// 3. `given_name + family_name` — formato alternativo
/// 4. Email prefix capitalizado — "joao.silva@gmail.com" → "Joao Silva"
/// 5. `null` — força a tela de input
///
/// Importante: nunca retorna o literal "User" (bug antigo) nem strings com
/// somente espaços.
String? resolveAuthName(User user) {
  final meta = user.userMetadata ?? const {};

  String? clean(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    if (s.toLowerCase() == 'user') return null; // sentinela legacy
    return s;
  }

  // 1. full_name (Google, Apple quando manda no JWT)
  final fullName = clean(meta['full_name']);
  if (fullName != null) return normalizeName(fullName);

  // 2. name
  final name = clean(meta['name']);
  if (name != null) return normalizeName(name);

  // 3. given_name + family_name
  final given = clean(meta['given_name']);
  final family = clean(meta['family_name']);
  if (given != null || family != null) {
    final joined = [given, family].where((s) => s != null).join(' ');
    return normalizeName(joined);
  }

  // 4. Email prefix → "joao.silva" / "joao_silva" / "joao+work" → "Joao Silva"
  final email = clean(user.email);
  if (email != null && email.contains('@')) {
    final prefix = email.split('@').first;
    final cleaned = prefix.split('+').first; // remove "+tag"
    final spaced = cleaned.split(RegExp(r'[._\-]')).where((p) => p.isNotEmpty).join(' ');
    if (spaced.isNotEmpty) return normalizeName(spaced);
  }

  // 5. Nada decente — força a tela de input
  return null;
}

