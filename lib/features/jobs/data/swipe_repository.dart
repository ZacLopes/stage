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
}
