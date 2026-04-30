import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/job_repository.dart';
import 'data/swipe_repository.dart';
import 'data/preferences_repository.dart';
import 'models/job.dart';
import 'models/user_preferences.dart';

class JobsViewModel extends ChangeNotifier {
  final JobRepository _jobRepository;
  final SwipeRepository _swipeRepository;
  final PreferencesRepository _preferencesRepository;

  JobsViewModel(
    this._jobRepository,
    this._swipeRepository,
    this._preferencesRepository,
  );

  // State
  List<Job> _jobs = [];
  UserJobPreferences? _preferences;
  bool _isLoading = false;
  bool _isPreferencesLoading = false;
  String? _errorMessage;
  int _currentPage = 0;
  bool _hasMorePages = true;

  // Stack of undone job IDs (to re-add cards)
  final List<Job> _undoStack = [];

  // Getters
  List<Job> get jobs => _jobs;
  UserJobPreferences? get preferences => _preferences;
  bool get isLoading => _isLoading;
  bool get isPreferencesLoading => _isPreferencesLoading;
  String? get errorMessage => _errorMessage;
  bool get hasMorePages => _hasMorePages;

  String? get userId => Supabase.instance.client.auth.currentUser?.id;

  /// Initialize: load preferences then jobs.
  Future<void> init({bool forceRefresh = false}) async {
    if (userId == null) return;
    
    // Avoid redundant loading if already in progress or if data exists
    if (_isLoading) return;
    
    if (!forceRefresh && _jobs.isNotEmpty) {
       _silentInit();
       return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _performFetch();
    } catch (e) {
      _errorMessage = 'Erro ao carregar vagas. Tente novamente.';
      print('Error initializing jobs: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _silentInit() async {
    try {
      await _performFetch();
      notifyListeners();
    } catch (e) {
      print('Silent job refresh error: $e');
    }
  }

  Future<void> _performFetch() async {
    // Load preferences first
    _preferences = await _preferencesRepository.getPreferences(userId!);
    
    // Then load jobs with those preferences
    _currentPage = 0;
    _jobs = await _jobRepository.fetchJobs(
      preferences: _preferences,
      page: _currentPage,
    );
    _hasMorePages = _jobs.length >= 10;
  }

  /// Reload jobs (e.g. after changing preferences).
  Future<void> reloadJobs() async {
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    _currentPage = 0;
    _undoStack.clear();
    notifyListeners();

    try {
      await _performFetch();
    } catch (e) {
      _errorMessage = 'Erro ao carregar vagas. Tente novamente.';
      print('Error reloading jobs: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Record a swipe action (like or reject) and remove card from list.
  Future<void> onSwipe(int index, String action) async {
    if (userId == null) return;
    if (index < 0 || index >= _jobs.length) return;

    final job = _jobs[index];
    
    // Optimistic: remove from local list immediately
    _undoStack.add(job);
    _jobs.removeAt(index);
    notifyListeners();

    try {
      await _swipeRepository.recordSwipe(userId!, job.id, action);
    } catch (e) {
      // Rollback on error
      print('Error recording swipe: $e');
      _jobs.insert(index.clamp(0, _jobs.length), job);
      _undoStack.removeLast();
      notifyListeners();
    }
  }

  /// Undo the last swipe: deletes from DB and re-adds card to front.
  Future<void> undoLastSwipe() async {
    if (userId == null) return;

    try {
      final undoneJobId = await _swipeRepository.undoLastSwipe(userId!);
      if (undoneJobId == null) return;

      // Check undo stack first (locally cached)
      final localIndex = _undoStack.lastIndexWhere((j) => j.id == undoneJobId);
      if (localIndex >= 0) {
        final job = _undoStack.removeAt(localIndex);
        _jobs.insert(0, job);
        notifyListeners();
        return;
      }

      // If not in local stack, fetch from DB
      final job = await _jobRepository.getJobById(undoneJobId);
      if (job != null) {
        _jobs.insert(0, job);
        notifyListeners();
      }
    } catch (e) {
      print('Error undoing swipe: $e');
    }
  }

  // ============================================
  // PREFERENCES
  // ============================================

  /// Load preferences from DB.
  Future<void> loadPreferences() async {
    if (userId == null) return;
    _isPreferencesLoading = true;
    notifyListeners();

    try {
      _preferences = await _preferencesRepository.getPreferences(userId!);
    } catch (e) {
      print('Error loading preferences: $e');
    } finally {
      _isPreferencesLoading = false;
      notifyListeners();
    }
  }

  /// Save preferences and reload jobs with new filters.
  Future<void> savePreferences(UserJobPreferences prefs) async {
    if (userId == null) return;

    try {
      await _preferencesRepository.savePreferences(userId!, prefs);
      _preferences = prefs;
      // Reload jobs with new filters
      await reloadJobs();
    } catch (e) {
      print('Error saving preferences: $e');
      rethrow;
    }
  }

  /// Clear all preferences.
  Future<void> clearPreferences() async {
    if (userId == null) return;

    final emptyPrefs = UserJobPreferences(userId: userId!);
    await savePreferences(emptyPrefs);
  }

  /// Get a fresh copy of a job by ID (for details screen).
  Future<Job?> getJobDetails(String jobId) async {
    try {
      return await _jobRepository.getJobById(jobId);
    } catch (e) {
      print('Error getting job details: $e');
      return null;
    }
  }
}
