import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_preferences.dart';

class PreferencesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Gets the user's saved job preferences.
  Future<UserJobPreferences?> getPreferences(String userId) async {
    try {
      final response = await _client
          .from('user_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;
      return UserJobPreferences.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      print('Error fetching preferences: $e');
      rethrow;
    }
  }

  /// Saves or updates user job preferences (upsert).
  Future<void> savePreferences(String userId, UserJobPreferences prefs) async {
    try {
      final data = prefs.toJson();
      data['user_id'] = userId; // Ensure user_id is set

      await _client.from('user_preferences').upsert(
        data,
        onConflict: 'user_id',
      );
    } catch (e) {
      print('Error saving preferences: $e');
      rethrow;
    }
  }
}
