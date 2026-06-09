import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/culture_fit_profile.dart';

class CultureFitRepository {
  final SupabaseClient _client = Supabase.instance.client;

  static String _storageKey(String userId) => 'culture_fit_profile_$userId';

  Future<CultureFitProfile?> load(String userId) async {
    final local = await _loadLocal(userId);
    final remote = await _loadRemote(userId);

    if (remote == null) return local;
    if (local == null) {
      await _saveLocal(remote);
      return remote;
    }

    final localUpdated =
        local.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final remoteUpdated =
        remote.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (remoteUpdated.isAfter(localUpdated)) {
      await _saveLocal(remote);
      return remote;
    }

    return local;
  }

  Future<CultureFitProfile> save(CultureFitProfile profile) async {
    final saved = profile.copyWith(updatedAt: DateTime.now());
    await _saveLocal(saved);
    await _saveRemoteBestEffort(saved);
    return saved;
  }

  Future<CultureFitProfile?> _loadLocal(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      map['user_id'] = userId;
      return CultureFitProfile.fromJson(map);
    } catch (e) {
      developer.log('loadLocal failed', name: 'CultureFitRepository', error: e);
      return null;
    }
  }

  Future<void> _saveLocal(CultureFitProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey(profile.userId),
      jsonEncode(profile.toJson()),
    );
  }

  Future<CultureFitProfile?> _loadRemote(String userId) async {
    try {
      final row = await _client
          .from('user_culture_fit_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return null;
      return CultureFitProfile.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      developer.log(
        'loadRemote failed',
        name: 'CultureFitRepository',
        error: e,
      );
      return null;
    }
  }

  Future<void> _saveRemoteBestEffort(CultureFitProfile profile) async {
    try {
      await _client
          .from('user_culture_fit_preferences')
          .upsert(profile.toJson(), onConflict: 'user_id');
    } catch (e) {
      developer.log(
        'saveRemote failed',
        name: 'CultureFitRepository',
        error: e,
      );
    }
  }
}
