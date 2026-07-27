import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';

enum TrackStatus { locked, available, completed }

/// Bottom-nav tab indices (post-unification of Trilha into Currículo).
/// Exposed here so screens can reference indices without a cyclic import
/// of HomeScreen.
class HomeTabs {
  static const int jobs = 0;
  static const int saved = 1;
  static const int resume = 2;
  static const int profile = 3;
}

class HomeViewModel extends ChangeNotifier {
  final SupabaseRepository _repository;
  List<Track> _tracks = [];
  final Map<String, List<Phase>> _phasesByTrack = {};
  Set<String> _completedTrackIds = {};
  Set<String> _completedPhaseIds = {};
  bool _isLoading = true;

  HomeViewModel(this._repository) {
    _init();
  }

  void _init() {
    // Listen to auth state changes to clear/reload data
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        _loadData();
      } else if (event == AuthChangeEvent.signedOut) {
        _clearData();
      }
    });

    // Load immediately if user is already logged in
    if (Supabase.instance.client.auth.currentUser != null) {
      _loadData();
    }
  }

  void _clearData() {
    _tracks = [];
    _phasesByTrack.clear();
    _completedTrackIds.clear();
    _completedPhaseIds.clear();
    _pendingTabIndex = null;
    _isLoading = false;
    notifyListeners();
  }

  List<Track> get tracks => _tracks;
  Map<String, List<Phase>> get phasesByTrack => _phasesByTrack;
  bool get isLoading => _isLoading;

  Future<void> _loadData() async {
    _isLoading = true;
    notifyListeners();
    try {
      _tracks = await _repository.getTracks();
      _completedPhaseIds = await _repository.getCompletedPhaseIds();
      _completedTrackIds.clear(); // Clear existing completion state
      
      // Load phases for each track and check completion
      for (var track in _tracks) {
        final activePhases = await _repository.getPhases(track.id);

        _phasesByTrack[track.id] = activePhases;

        if (activePhases.isNotEmpty &&
            activePhases.every((phase) => _completedPhaseIds.contains(phase.id))) {
          _completedTrackIds.add(track.id);
        }
      }
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('SocketException') || 
          errorMsg.contains('HandshakeException') ||
          errorMsg.contains('Connection closed')) {
        print('📡 Network connection issues while loading tracks. Will retry on refresh.');
      } else {
        print('Error loading tracks: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  TrackStatus getTrackStatus(int trackIndex) {
    if (trackIndex >= _tracks.length) return TrackStatus.locked;
    
    final track = _tracks[trackIndex];
    
    // Check if completed
    if (_completedTrackIds.contains(track.id)) {
      return TrackStatus.completed;
    }
    
    // Check if unlocked (first track or previous track completed)
    // The list is in ascending order (1, 2, 3, 4, 5)
    // Index 0 is "Quem eu sou" (Base) -> Always unlocked
    if (trackIndex == 0) {
      return TrackStatus.available;
    }
    
    // Check if the previous track (index - 1) is completed
    final previousTrack = _tracks[trackIndex - 1];
    
    final isPrevCompleted = _completedTrackIds.contains(previousTrack.id);
    // print('Check Unlock: ${track.title} (Idx $trackIndex) | Prev: ${previousTrack.title} | PrevCompleted: $isPrevCompleted');
    
    if (isPrevCompleted) {
      return TrackStatus.available;
    }
    
    return TrackStatus.locked;
  }

  bool isTrackUnlocked(int trackIndex) {
    final status = getTrackStatus(trackIndex);
    return status == TrackStatus.available || status == TrackStatus.completed;
  }

  bool isPhaseCompleted(String phaseId) {
    return _completedPhaseIds.contains(phaseId);
  }

  Future<void> refresh() async {
    await _loadData();
  }

  // ── Tab-change request (used by deep navigation screens) ──────────────────
  int? _pendingTabIndex;
  int? get pendingTabIndex => _pendingTabIndex;

  void requestTabChange(int index) {
    _pendingTabIndex = index;
    notifyListeners();
  }

  void clearPendingTabChange() {
    _pendingTabIndex = null;
    // No notifyListeners() to avoid rebuild loops
  }

  // ── Profile resume highlight (used after auto-save from trail/import) ─────
  /// The Profile tab reads this when it mounts/rebuilds to play a brief
  /// entrance animation on the matching resume card, then calls
  /// [clearProfileHighlight] to dismiss.
  String? _pendingHighlightResumeId;
  String? get pendingHighlightResumeId => _pendingHighlightResumeId;

  void requestProfileHighlight(String resumeId) {
    _pendingHighlightResumeId = resumeId;
    notifyListeners();
  }

  void clearProfileHighlight() {
    _pendingHighlightResumeId = null;
    // No notifyListeners() to avoid rebuild loops
  }

  // ── Pending Profile sub-tab (Info/Preferências/Currículos) ────────────────
  /// Quando setado, a ProfileScreen troca pra essa sub-aba (ex.: o assistente
  /// leva pra biblioteca de currículos = índice 2) num post-frame e limpa.
  int? _pendingProfileSubTabIndex;
  int? get pendingProfileSubTabIndex => _pendingProfileSubTabIndex;

  void requestProfileSubTab(int index) {
    _pendingProfileSubTabIndex = index;
    notifyListeners();
  }

  void clearProfileSubTab() {
    _pendingProfileSubTabIndex = null;
    // No notifyListeners() to avoid rebuild loops
  }

  // ── Pedido de IMPORTAR CV (F5.4) ──────────────────────────────────────────
  /// O card "Fonte importada" (Perfil → Dados) é a casa da fonte, mas a REVISÃO
  /// do import ("CV diz X × você tem Y" + desfazer) vive no Assistente, que é o
  /// agente transversal de documentos. Ao tocar Substituir/Importar, o card pede
  /// a troca pra aba do Assistente E este flag; a ResumeTab consome num
  /// post-frame e empurra o MESMO cartão de import que o assistente já usa —
  /// sem duplicar o motor de revisão.
  bool _pendingCvImport = false;
  bool get pendingCvImport => _pendingCvImport;

  void requestCvImport() {
    _pendingCvImport = true;
    notifyListeners();
  }

  void clearCvImport() {
    _pendingCvImport = false;
    // No notifyListeners() to avoid rebuild loops
  }

  // ── Bottom-nav Profile icon key (target for the landing animation) ────────
  /// HomeScreen sets this key on the Profile bottom-nav item so other
  /// screens can compute its position on-screen and animate towards it.
  final GlobalKey profileNavKey = GlobalKey(debugLabel: 'profileNavKey');

  // ── Pending CV-landing animation trigger ──────────────────────────────────
  /// HomeScreen watches this and plays the "document flying to Profile"
  /// animation when set to true. Used by callers (e.g. the
  /// CurriculumReadyDialog after popping) that can't safely hold their
  /// own context to run the overlay animation themselves.
  bool _pendingLandingAnimation = false;
  bool get pendingLandingAnimation => _pendingLandingAnimation;

  void triggerLandingAnimation() {
    _pendingLandingAnimation = true;
    notifyListeners();
  }

  void clearLandingAnimation() {
    _pendingLandingAnimation = false;
    // No notifyListeners() to avoid rebuild loops
  }

  /// Atomic announce after auto-save: HomeScreen orchestrates the
  /// animation, then switches to [targetTab], then sets the highlight
  /// so the Profile screen plays the entrance animation on the right
  /// card after the user can actually see it.
  String? _deferredHighlightId;
  String? get deferredHighlightId => _deferredHighlightId;

  void announceCvCreated({
    required int targetTab,
    required String highlightId,
  }) {
    _pendingLandingAnimation = true;
    _deferredHighlightId = highlightId; // applied after tab change
    _pendingTabIndex = targetTab;
    notifyListeners();
  }

  void consumeDeferredHighlight() {
    if (_deferredHighlightId != null) {
      _pendingHighlightResumeId = _deferredHighlightId;
      _deferredHighlightId = null;
      notifyListeners();
    }
  }
}
