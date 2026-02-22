import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/models.dart';

class LocalStorageRepository {
  static const String _profileKeyPrefix = 'ai_profile_content_';
  static const String _resumeKeyPrefix = 'ai_resume_content_';

  String _getProfileKey(String userId) => '$_profileKeyPrefix$userId';
  String _getResumeKey(String userId) => '$_resumeKeyPrefix$userId';

  Future<void> saveProfileContent(String userId, ProfileContent content) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(content.toJson());
    await prefs.setString(_getProfileKey(userId), jsonString);
  }

  Future<ProfileContent?> getProfileContent(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_getProfileKey(userId));
    
    if (jsonString == null) return null;
    
    try {
      final jsonMap = jsonDecode(jsonString);
      return ProfileContent.fromJson(jsonMap);
    } catch (e) {
      print('Error parsing cached profile content: $e');
      return null;
    }
  }

  Future<void> saveResumeContent(String userId, ResumeContent content) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(content.toJson());
    await prefs.setString(_getResumeKey(userId), jsonString);
  }

  Future<ResumeContent?> getResumeContent(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_getResumeKey(userId));
    
    if (jsonString == null) return null;
    
    try {
      final jsonMap = jsonDecode(jsonString);
      return ResumeContent.fromJson(jsonMap);
    } catch (e) {
      print('Error parsing cached resume content: $e');
      return null;
    }
  }

  Future<void> clearAll(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getProfileKey(userId));
    await prefs.remove(_getResumeKey(userId));
  }
}
