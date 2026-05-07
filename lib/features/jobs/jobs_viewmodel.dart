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
  // _jobs é IMUTÁVEL durante a sessão de swipes: o `flutter_card_swiper`
  // mantém um current-index interno que descincroniza se a lista encolher.
  // Em vez de remover items, marcamos os IDs em _swipedIds e o CardSwiper
  // gerencia a animação de saída via seu próprio state.
  List<Job> _jobs = [];
  final Set<String> _swipedIds = {};
  UserJobPreferences? _preferences;
  bool _isLoading = false;
  bool _isPreferencesLoading = false;
  String? _errorMessage;
  int _currentPage = 0;
  bool _hasMorePages = true;

  // Diagnóstico do último fetch — pra UI distinguir "esgotou tudo" de
  // "filtros muito restritivos".
  int _totalAvailable = 0;
  int _totalAfterFilters = 0;

  // Stack of swiped jobs (mais recente no fim) pra suportar undo
  final List<Job> _undoStack = [];

  // Liked jobs (aba "Curtidas") — populado on-demand
  List<LikedJob> _likedJobs = [];
  bool _likedJobsLoading = false;

  // Getters
  List<Job> get jobs => _jobs;
  Set<String> get swipedIds => _swipedIds;
  int get remainingCount => _jobs.length - _swipedIds.length;
  UserJobPreferences? get preferences => _preferences;
  bool get isLoading => _isLoading;
  bool get isPreferencesLoading => _isPreferencesLoading;
  String? get errorMessage => _errorMessage;
  bool get hasMorePages => _hasMorePages;
  List<LikedJob> get likedJobs => _likedJobs;
  bool get likedJobsLoading => _likedJobsLoading;
  int get likedCount => _likedJobs.length;
  int get appliedCount => _likedJobs.where((l) => l.applied).length;
  int get pendingCount => likedCount - appliedCount;

  int get totalAvailable => _totalAvailable;
  int get totalAfterFilters => _totalAfterFilters;

  /// Verdadeiro quando há vagas no banco mas os filtros do user excluíram
  /// todas. UI usa pra mostrar "afrouxe os filtros" em vez de "explorou tudo".
  bool get filtersAreTooRestrictive =>
      _totalAvailable > 0 &&
      _totalAfterFilters == 0 &&
      _preferences != null &&
      !_preferences!.isEmpty;

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
    final result = await _jobRepository.fetchJobsWithDiagnostics(
      preferences: _preferences,
      page: _currentPage,
    );
    _jobs = result.jobs;
    _totalAvailable = result.totalAvailable;
    _totalAfterFilters = result.totalAfterFilters;
    _hasMorePages = _jobs.length >= 10;
  }

  /// Reload jobs (e.g. after changing preferences).
  Future<void> reloadJobs() async {
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    _currentPage = 0;
    _undoStack.clear();
    _swipedIds.clear();
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

  /// Registra uma ação de swipe no DB. **Não remove do array local** —
  /// o CardSwiper gerencia internamente a animação de saída do card e
  /// avança seu próprio current-index. Mexer em `_jobs` aqui descincroniza
  /// o state interno do swiper e trava gestos depois de N swipes.
  Future<void> onSwipe(int index, String action) async {
    if (userId == null) return;
    if (index < 0 || index >= _jobs.length) return;

    final job = _jobs[index];
    if (_swipedIds.contains(job.id)) return; // dedup

    _swipedIds.add(job.id);
    _undoStack.add(job);
    notifyListeners(); // pra atualizar contagem na UI

    try {
      await _swipeRepository.recordSwipe(userId!, job.id, action);
      // Atualiza badge da aba "Curtidas" após swipe right.
      // Silent refresh não bloqueia a UI do swiper.
      if (action == 'liked') {
        loadLikedJobs(silent: true);
      }
    } catch (e) {
      // Rollback otimista
      print('Error recording swipe: $e');
      _swipedIds.remove(job.id);
      _undoStack.removeLast();
      notifyListeners();
    }
  }

  /// Undo: apaga o registro no DB. O caller (UI) chama
  /// `_swiperController.undo()` pra reverter a animação. Aqui só
  /// limpamos o swipedIds para que a UI saiba.
  Future<void> undoLastSwipe() async {
    if (userId == null) return;
    if (_undoStack.isEmpty) return;

    final lastJob = _undoStack.last;

    try {
      final undoneJobId = await _swipeRepository.undoLastSwipe(userId!);
      if (undoneJobId == null) return;

      _undoStack.removeLast();
      _swipedIds.remove(undoneJobId);
      // Remove da lista local de curtidas (caso fosse um like desfeito)
      _likedJobs.removeWhere((l) => l.job.id == undoneJobId);
      notifyListeners();
    } catch (e) {
      print('Error undoing swipe: $e');
      // Mantém estado consistente mesmo em erro
      _undoStack.removeLast();
      _swipedIds.remove(lastJob.id);
      notifyListeners();
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

  // ============================================
  // LIKED JOBS (aba "Curtidas")
  // ============================================

  /// Carrega vagas curtidas do user. Chamado quando a aba abre, no init,
  /// e após cada swipe right (pra manter o badge atualizado).
  Future<void> loadLikedJobs({bool silent = false}) async {
    if (userId == null) return;

    if (!silent) {
      _likedJobsLoading = true;
      notifyListeners();
    }

    try {
      _likedJobs = await _swipeRepository.getLikedJobsWithDetails(userId!);
    } catch (e) {
      print('Error loading liked jobs: $e');
    } finally {
      _likedJobsLoading = false;
      notifyListeners();
    }
  }

  /// Marca/desmarca vaga como aplicada. Otimista: atualiza UI antes do DB.
  Future<void> setApplied(String jobId, bool applied) async {
    if (userId == null) return;

    final idx = _likedJobs.indexWhere((l) => l.job.id == jobId);
    if (idx == -1) return;

    final old = _likedJobs[idx];
    _likedJobs[idx] = old.copyWith(
      applied: applied,
      appliedAt: applied ? DateTime.now() : null,
    );
    notifyListeners();

    try {
      await _swipeRepository.setApplied(userId!, jobId, applied);
    } catch (e) {
      // Rollback otimista
      print('Error setting applied: $e');
      _likedJobs[idx] = old;
      notifyListeners();
    }
  }
}
