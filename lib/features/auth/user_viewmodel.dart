import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';
import '../../data/local_storage_repository.dart';
import '../../data/database_helper.dart';

class UserViewModel extends ChangeNotifier {
  final SupabaseRepository _repository;
  final LocalStorageRepository _localStorage;
  final SupabaseClient _supabase = Supabase.instance.client;
  
  UserProfile? _user;
  bool _isLoading = true;
  Campaign? _currentCampaign;

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
  Campaign? get currentCampaign => _currentCampaign;
  bool get hasCampaign => _currentCampaign != null;
  bool get showM1ResetNotice =>
      _user?.gamificationData['show_m1_reset_notice'] == true;

  void _init() {
    // Listen to auth state changes
    _supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        _loadUser();
      } else if (event == AuthChangeEvent.signedOut) {
        _user = null;
        _currentCampaign = null;
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
             // Profile not found yet; waiting for DB trigger to populate.
             await Future.delayed(const Duration(seconds: 1));
          }

          try {
            userProfile = await _repository.getUserProfile();
          } catch (e) {
            // Swallow transient errors during retries; surfacing only the
            // final failure (after all attempts) keeps the console clean.
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
        if (_user != null) {
          _currentCampaign = await _repository.getLatestCampaign(_user!.id!);
        }
      } else {
        _user = null;
        _currentCampaign = null;
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

  Future<void> clearM1ResetNotice() async {
    if (_user == null || !showM1ResetNotice) return;
    await _repository.clearM1ResetNotice(_user!.id!);
    final updatedData = Map<String, dynamic>.from(_user!.gamificationData)
      ..remove('show_m1_reset_notice');
    _user = _user!.copyWith(gamificationData: updatedData);
    notifyListeners();
  }

  Future<void> createCampaign({
    String? jobTitle,
    String? descriptionText,
    String? sourceUrl,
    bool isSkipped = false,
  }) async {
    if (_user == null) return;
    _currentCampaign = await _repository.createCampaignWithTargetJob(
      userId: _user!.id!,
      jobTitle: jobTitle,
      descriptionText: descriptionText,
      sourceUrl: sourceUrl,
      isSkipped: isSkipped,
    );
    notifyListeners();
  }

  // Sign in with OAuth Provider (Google, Apple, etc.)
  Future<void> signInWithOAuth(OAuthProvider provider) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _supabase.auth.signInWithOAuth(
        provider,
        redirectTo: 'io.supabase.stage://login-callback',
        queryParams: {
          'prompt': 'select_account',
        },
      );
    } catch (e) {
      print('Error signing in with OAuth ($provider): $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Native Apple Sign In
  Future<void> signInWithApple() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final rawNonce = _supabase.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('Apple Id token missing.');
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      // Load user profile first so _user is populated
      await _loadUser();

      // Apple only sends the real name on the FIRST authorization.
      // Capture it immediately and persist if the profile still has
      // the generic "User" fallback (or is empty).
      final givenName = credential.givenName ?? '';
      final familyName = credential.familyName ?? '';
      final appleName = '$givenName $familyName'.trim();

      if (appleName.isNotEmpty &&
          (_user == null || (_user!.name ?? '').isEmpty || _user!.name == 'User')) {
        // Update profile table with the real name from Apple
        await _repository.updateUserProfile(
          _user!.copyWith(name: appleName),
        );
        _user = _user!.copyWith(name: appleName);
        notifyListeners();
      }

    } catch (e) {
      print('Error signing in with Apple natively: $e');
      rethrow;
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
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

  // Update user profile
  Future<void> updateProfile({
    String? name,
    String? course,
    String? semester,
    String? university,
    int? age,
    String? email,
    String? password,
    Map<String, dynamic>? gamificationData,
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
      
      if (name != null || course != null || semester != null || university != null || age != null || gamificationData != null) {
        
        // Merge gamification data
        Map<String, dynamic> mergedGamificationData = Map.from(_user!.gamificationData);
        if (gamificationData != null) {
          mergedGamificationData.addAll(gamificationData);
        }
        if (university != null) {
          mergedGamificationData['university'] = university;
        }

        final updatedProfile = _user!.copyWith(
          name: name,
          course: course,
          semester: semester,
          age: age,
          email: email, 
          gamificationData: mergedGamificationData,
        );
        
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
