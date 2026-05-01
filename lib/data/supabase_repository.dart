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
      print('🚀 Prefetching all data...');
      
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
      
      print('✅ Prefetch complete! Cached ${fetchedTracks.length} tracks, ${fetchedPhases.length} phases, ${fetchedQuestions.length} questions.');
      
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
        final newProfile = {
          'id': userId,
          'email': user.email ?? '',
          'name': user.userMetadata?['name'] ?? 'User',
          'course': user.userMetadata?['course'] ?? '',
          'semester': user.userMetadata?['semester'] ?? '',
          'age': user.userMetadata?['age'], // Added missing age field
          'xp': 0,
          'level': 1,
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

  Future<void> updateUserXP(String userId, int xp, int level) async {
    try {
      await _client
          .from('user_profiles')
          .update({
            'xp': xp,
            'level': level,
          })
          .eq('id', userId);
    } catch (e) {
      print('Error updating user XP: $e');
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

  Future<void> markPhaseCompleted(String phaseId, int score) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _client.from('user_progress').upsert({
        'user_id': userId,
        'phase_id': phaseId,
        'completed': true,
        'score': score,
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

      await _client.from('user_answers').upsert({
        'user_id': userId,
        'question_id': questionId,
        'answer': answer,
        'answered_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error saving answer: $e');
      rethrow;
    }
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
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching user answers: $e');
      return [];
    }
  }

  Future<Map<String, String>> getUserAnswersWithQuestions() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return {};

      // 1. Fetch raw answers (question_id, answer)
      final response = await _client
          .from('user_answers')
          .select('question_id, answer')
          .eq('user_id', userId);
      
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

  Future<void> saveResume(String title, List<int> pdfBytes) async {
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

      // 2. Save record to table
      await _client.from('saved_resumes').insert({
        'user_id': userId,
        'title': title,
        'file_path': storagePath,
      });
    } catch (e) {
      print('Error saving resume: $e');
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
    final jobData = await _client.from('target_jobs').insert({
      'user_id': userId,
      'title': jobTitle,
      'description_text': descriptionText,
      'source_url': sourceUrl,
      'is_skipped': isSkipped,
    }).select().single();

    final targetJob = TargetJob.fromJson(jobData);
    final campaignName =
        (jobTitle != null && jobTitle.isNotEmpty) ? jobTitle : 'Campanha 1';

    final campaignData = await _client.from('campaigns').insert({
      'user_id': userId,
      'target_job_id': targetJob.id,
      'name': campaignName,
      'status': 'draft',
    }).select().single();

    return Campaign.fromJson(campaignData);
  }
}

