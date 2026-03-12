import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';
import '../../data/local_storage_repository.dart';
import '../../data/database_helper.dart';
import '../gamification/level_system.dart';

class UserViewModel extends ChangeNotifier {
  final SupabaseRepository _repository;
  final LocalStorageRepository _localStorage;
  final SupabaseClient _supabase = Supabase.instance.client;
  
  UserProfile? _user;
  bool _isLoading = true;

  UserViewModel(this._repository, this._localStorage) {
    _init();
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  UserProfile? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null && _supabase.auth.currentUser != null;
  bool get isEmailVerified => _supabase.auth.currentUser?.emailConfirmedAt != null;

  void _init() {
    // Listen to auth state changes
    _supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        _loadUser();
      } else if (event == AuthChangeEvent.signedOut) {
        _user = null;
        notifyListeners();
      }
    });
    
    // Load initial user and prefetch data
    _loadUser();
    // Prefetch content (fire and forget, or await if critical)
    _repository.prefetchAllData();
  }

  Future<void> refreshUser() async {
    await _loadUser();
  }

  Future<void> _loadUser() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      if (_supabase.auth.currentUser != null) {
        // Retry logic to wait for DB trigger creation
        UserProfile? userProfile;
        int attempts = 0;
        while (attempts < 4 && userProfile == null) {
          if (attempts > 0) {
             print('⏳ Profile not found, retrying/creating (${attempts}/4)...');
             await Future.delayed(const Duration(seconds: 1));
          }
          
          try {
            userProfile = await _repository.getUserProfile();
          } catch (e) {
            final errorMsg = e.toString();
            if (errorMsg.contains('SocketException') || 
                errorMsg.contains('HandshakeException') ||
                errorMsg.contains('Connection closed')) {
              print('📡 Network connection issues (Retry $attempts/4)...');
            } else {
              print('Error fetching user profile: $e');
            }
          }
          
          attempts++;
        }
        
        // Fallback: If age is missing in DB profile, check Auth Metadata
        if (userProfile != null && userProfile.age == null) {
          final metadataAge = _supabase.auth.currentUser!.userMetadata?['age'];
          if (metadataAge != null) {
            // "Patch" the user profile in memory with age from metadata
            final age = metadataAge is int ? metadataAge : int.tryParse(metadataAge.toString());
            userProfile = userProfile.copyWith(age: age);
          }
        }
        
        _user = userProfile;
      } else {
        _user = null;
      }
    } catch (e) {
      print('Error loading user: $e');
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign up new user
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    required int age,
    String? course,
    String? semester,
    String? university,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'name': name,
          'age': age,
          'course': course ?? '',
          'semester': semester ?? '',
          'university': university ?? '',
        },
      );

      if (response.user != null) {
        // Profile is automatically created by database trigger
        await _loadUser();
      }
    } catch (e) {
      // Check if error is "User already registered"
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('already registered') || errorMsg.contains('already exists')) {
        print('⚠️ User already exists, attempting to sign in instead...');
        try {
          await signIn(email: email, password: password);
          return; // Exit success if sign in works
        } catch (signInError) {
           print('Sign in after sign up failed: $signInError');
           // Rethrow original error if fallback fails
           rethrow; 
        }
      }
      
      print('Error signing up: $e');
      rethrow;
    } finally {
      // Only set loading false if we aren't redirecting to signIn (which handles its own loading)
      // Actually, signIn sets loading=true then false, so we should be careful not to override.
      // But since we await signIn, it should be fine to set false here at the very end.
      if (!_isDisposed) { // Add disposed check if possible, or just standard
         _isLoading = false;
         notifyListeners();
      }
    }
  }

  // Sign in existing user
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      await _loadUser();
    } catch (e) {
      print('Error signing in: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      // Clear repository cache before sign out so other ViewModels
      // don't see stale data from the previous user session
      _repository.clearCache();

      // Clear local SQLite data
      try {
        await DatabaseHelper.instance.clearAllUserData();
      } catch (e) { print('Local DB cleanup on logout: $e'); }

      await _supabase.auth.signOut();
      _user = null;
      notifyListeners();
    } catch (e) {
      print('Error logging out: $e');
      rethrow;
    }
  }

  // Resend Verification Email
  Future<void> resendVerificationEmail() async {
    _isLoading = true;
    notifyListeners();
    try {
      final email = _supabase.auth.currentUser?.email;
      if (email != null) {
        await _supabase.auth.resend(type: OtpType.signup, email: email);
      }
    } catch (e) {
      print('Error resending verification: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete Account
  Future<void> deleteAccount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      print('🛑 Initiating full account deletion for: $userId');

      // 1. Delete user files from Storage (with timeout)
      try {
        await _repository.deleteUserData().timeout(const Duration(seconds: 15));
      } catch (e) {
        print('⚠️ Storage cleanup timed out or failed: $e');
      }

      // 2. Clear local data (SQLite)
      try {
        await DatabaseHelper.instance.clearAllUserData();
      } catch (e) { print('Local DB cleanup error: $e'); }

      // 3. Clear local storage (Shared Preferences)
      try {
         await _localStorage.clearAll(userId);
      } catch (e) { print('Local storage cleanup error: $e'); }

      // 4. Delete auth account in Supabase (Cascades to all DB tables)
      try {
        await _repository.deleteAuthAccount().timeout(const Duration(seconds: 15));
      } catch (e) {
        print('❌ Auth deletion failed or timed out: $e');
        // If the RPC failed, it might be because the SQL function wasn't added yet.
        // We still proceed to sign out to at least disconnect the user.
      }

      // 5. Clear repository cache
      _repository.clearCache();

      // 6. Hard sign out and clear state
      await _supabase.auth.signOut();
      _user = null;
      print('👋 Account $userId disconnected and cleanup attempted.');
    } catch (e) {
      print('❌ Critical error during deletion process: $e');
      rethrow;
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Update user XP and level
  Future<void> updateXP(int xp, int level) async {
    if (_user == null) return;
    
    try {
      final levelInfo = LevelSystem.getLevelInfo(xp);
      final newLevel = levelInfo.level;

      await _repository.updateUserXP(_user!.id!, xp, newLevel);
      _user = _user!.copyWith(xp: xp, level: newLevel);
      notifyListeners();
    } catch (e) {
      print('Error updating XP: $e');
      rethrow;
    }
  }

  LevelInfo get currentLevelInfo {
    if (_user == null) return LevelSystem.getLevelInfo(0);
    return LevelSystem.getLevelInfo(_user!.xp ?? 0);
  }

  double get currentLevelProgress {
    if (_user == null) return 0.0;
    return LevelSystem.getProgressToNextLevel(_user!.xp ?? 0);
  }

  double get cumulativeLevelProgress {
    if (_user == null) return 0.0;
    final nextThreshold = nextLevelXPThreshold;
    if (nextThreshold == 0) return 1.0;
    return ((_user!.xp ?? 0) / nextThreshold).clamp(0.0, 1.0);
  }

  int get nextLevelXPThreshold {
    if (_user == null) return 100;
    final currentInfo = currentLevelInfo;
    final nextInfo = LevelSystem.getNextLevelInfo(currentInfo.level);
    if (currentInfo.level == nextInfo.level) return _user!.xp ?? 0; // Max level
    return nextInfo.minXP;
  }

  int get currentLevelXP {
    if (_user == null) return 0;
    return (_user!.xp ?? 0) - currentLevelInfo.minXP;
  }

  int get nextLevelXPRequirement {
    if (_user == null) return 100;
    final currentInfo = currentLevelInfo;
    final nextInfo = LevelSystem.getNextLevelInfo(currentInfo.level);
    if (currentInfo.level == nextInfo.level) return 1; // Max level
    return nextInfo.minXP - currentInfo.minXP;
  }

  // Update user profile
  Future<void> updateProfile({
    String? name,
    String? course,
    String? semester,
    String? university,
    int? age,
    String? email,
    String? password,
  }) async {
    if (_user == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Update Auth (Email/Password) + Metadata (Age)
      final Map<String, dynamic> metadataUpdates = {};
      
      // If age is provided, save it to metadata (since DB column might be missing)
      if (age != null) {
        metadataUpdates['age'] = age;
      }

      if (email != null || password != null || metadataUpdates.isNotEmpty) {
        final attributes = UserAttributes(
          email: email,
          password: password,
          data: metadataUpdates.isNotEmpty ? metadataUpdates : null,
        );
        await _supabase.auth.updateUser(attributes);
      }

      // 2. Update Profile Table (Name, Course, Semester)
      // Note: Age is NOT sent to DB here to prevent "column not found" error
      // unless SupabaseRepository filters it or UserProfile.toMap includes/excludes it.
      // Currently UserProfile.toMap DOES NOT include 'age', so it is safe.
      
      if (name != null || course != null || semester != null || university != null || age != null) {
        
        // Handle university update via gamificationData
        Map<String, dynamic> currentGamificationData = Map.from(_user!.gamificationData);
        if (university != null) {
          currentGamificationData['university'] = university;
        }

        // We update the local object fully (including Age) so UI updates immediately
        final updatedProfile = _user!.copyWith(
          name: name,
          course: course,
          semester: semester,
          age: age, // Update in memory
          email: email, 
          gamificationData: currentGamificationData,
        );
        
        // Sync with DB (will ignore age if toMap excludes it)
        await _repository.updateUserProfile(updatedProfile);
        _user = updatedProfile;
      } 
      
      notifyListeners();
    } catch (e) {
      print('Error updating profile: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateAIConsent(bool consent) async {
    if (_user == null) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      await _repository.updateAIConsent(_user!.id!, consent);
      _user = _user!.copyWith(
        aiConsent: consent,
        aiConsentTimestamp: consent ? DateTime.now() : null,
      );
      notifyListeners();
    } catch (e) {
      print('Error updating AI consent: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> revokeAIConsent() async {
    await updateAIConsent(false);
  }
}
