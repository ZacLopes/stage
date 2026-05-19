import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/swipe_action.dart';
import '../models/job.dart';

class SwipeRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Records a swipe action (upsert: updates if user already swiped this job).
  Future<void> recordSwipe(String userId, String jobId, String action) async {
    try {
      await _client.from('swipe_actions').upsert({
        'user_id': userId,
        'job_id': jobId,
        'action': action,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,job_id');
    } catch (e) {
      print('Error recording swipe: $e');
      rethrow;
    }
  }

  /// Undoes the most recent swipe action for a user.
  /// Returns the job_id that was undone, or null if nothing to undo.
  Future<String?> undoLastSwipe(String userId) async {
    try {
      // Get latest swipe
      final response = await _client
          .from('swipe_actions')
          .select('id, job_id')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      final swipeId = response['id'] as String;
      final jobId = response['job_id'] as String;

      // Delete it
      await _client
          .from('swipe_actions')
          .delete()
          .eq('id', swipeId);

      return jobId;
    } catch (e) {
      print('Error undoing last swipe: $e');
      rethrow;
    }
  }

  /// Gets all jobs the user has liked.
  Future<List<SwipeAction>> getLikedJobs(String userId) async {
    try {
      final response = await _client
          .from('swipe_actions')
          .select()
          .eq('user_id', userId)
          .eq('action', 'liked')
          .order('created_at', ascending: false);

      return (response as List)
          .map((e) => SwipeAction.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      print('Error getting liked jobs: $e');
      rethrow;
    }
  }

  /// Vagas curtidas + dados completos da vaga + flag de aplicada,
  /// ordenadas por curtida mais recente. Usado pela aba "Curtidas".
  Future<List<LikedJob>> getLikedJobsWithDetails(String userId) async {
    try {
      final response = await _client
          .from('swipe_actions')
          .select(
              'id, job_id, applied, applied_at, created_at, jobs(*, companies(*))')
          .eq('user_id', userId)
          .eq('action', 'liked')
          .order('created_at', ascending: false);

      final list = <LikedJob>[];
      for (final row in response as List) {
        final m = Map<String, dynamic>.from(row);
        final jobJson = m['jobs'];
        if (jobJson == null) continue; // job foi removido (CASCADE não cobriu)
        list.add(LikedJob(
          swipeId: m['id'] as String,
          job: Job.fromJson(Map<String, dynamic>.from(jobJson)),
          applied: m['applied'] == true,
          appliedAt: m['applied_at'] != null
              ? DateTime.tryParse(m['applied_at'] as String)
              : null,
          likedAt: DateTime.parse(m['created_at'] as String),
        ));
      }
      return list;
    } catch (e) {
      print('Error getting liked jobs with details: $e');
      rethrow;
    }
  }

  /// Remove o registro de swipe (qualquer action) de um par user×job.
  /// Usado pra desfazer uma vaga salva — apaga a linha em swipe_actions,
  /// fazendo a vaga voltar a estar elegível pro feed em fetches futuros.
  Future<void> removeLike(String userId, String jobId) async {
    try {
      await _client
          .from('swipe_actions')
          .delete()
          .eq('user_id', userId)
          .eq('job_id', jobId);
    } catch (e) {
      print('Error removing like: $e');
      rethrow;
    }
  }

  /// Recria um registro de like com o `created_at` original. Usado pra
  /// desfazer a remoção via SnackBar "Desfazer" — preserva a ordem original
  /// na lista (que é ordenada por created_at desc).
  Future<void> restoreLike(
    String userId,
    String jobId, {
    required DateTime createdAt,
    required bool applied,
    DateTime? appliedAt,
  }) async {
    try {
      await _client.from('swipe_actions').upsert({
        'user_id': userId,
        'job_id': jobId,
        'action': 'liked',
        'created_at': createdAt.toIso8601String(),
        'applied': applied,
        'applied_at': appliedAt?.toIso8601String(),
      }, onConflict: 'user_id,job_id');
    } catch (e) {
      print('Error restoring like: $e');
      rethrow;
    }
  }

  /// Alterna o flag `applied` da vaga curtida do user.
  Future<void> setApplied(String userId, String jobId, bool applied) async {
    try {
      await _client
          .from('swipe_actions')
          .update({
            'applied': applied,
            'applied_at': applied ? DateTime.now().toIso8601String() : null,
          })
          .eq('user_id', userId)
          .eq('job_id', jobId);
    } catch (e) {
      print('Error setting applied flag: $e');
      rethrow;
    }
  }
}

/// Wrapper retornado pela aba "Curtidas" — combina o swipe + a vaga.
class LikedJob {
  final String swipeId;
  final Job job;
  final bool applied;
  final DateTime? appliedAt;
  final DateTime likedAt;

  LikedJob({
    required this.swipeId,
    required this.job,
    required this.applied,
    required this.appliedAt,
    required this.likedAt,
  });

  LikedJob copyWith({bool? applied, DateTime? appliedAt}) => LikedJob(
        swipeId: swipeId,
        job: job,
        applied: applied ?? this.applied,
        appliedAt: appliedAt ?? this.appliedAt,
        likedAt: likedAt,
      );
}
