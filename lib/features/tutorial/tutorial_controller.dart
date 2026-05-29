import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/analytics_service.dart';
import 'tutorial_step.dart';

/// Manages the dynamic spotlight tutorial: orchestrates the step
/// sequence, runs each step's `onEnter` (e.g. tab-switch) before
/// showing it, and persists "already seen" per user in SharedPreferences.
///
/// Lifecycle:
///   - [start] kicks off the sequence at step 0
///   - [next] advances; auto-finishes when past the last step
///   - [skip] aborts and marks as seen
///   - [finish] is the same as [skip] but used for the natural end
///   - [reset] clears the seen flag (used in dev/debug)
///
/// The widget that mounts the [TutorialOverlay] listens to this
/// ChangeNotifier and rebuilds on every step transition.
class TutorialController extends ChangeNotifier {
  static const String _kPrefPrefix = 'has_seen_tutorial_v2_';

  int _currentIndex = -1;
  List<TutorialStep> _steps = const [];
  bool _isTransitioning = false;
  bool _replayRequested = false;
  // Telemetria (B.11 do plano v2). `_flow` identifica qual sequência está
  // rodando (default 'home_main' — único hoje). `_startedAt` marca o
  // início pra calcular `duration_ms` no tutorial_completed.
  String _flow = 'home_main';
  DateTime? _startedAt;

  bool get isRunning => _currentIndex >= 0 && _currentIndex < _steps.length;
  TutorialStep? get currentStep => isRunning ? _steps[_currentIndex] : null;
  int get currentIndex => _currentIndex;
  int get totalSteps => _steps.length;
  bool get isTransitioning => _isTransitioning;
  bool get replayRequested => _replayRequested;

  /// Used by Settings → Tutorial. HomeScreen watches this flag, calls
  /// [start] with its sequence when set, then clears via
  /// [consumeReplayRequest]. Two-step pattern avoids the controller
  /// needing to know the actual step list (which lives in HomeScreen).
  void requestReplay() {
    _replayRequested = true;
    notifyListeners();
  }

  void consumeReplayRequest() {
    _replayRequested = false;
    // No notifyListeners() — avoid rebuild loop. The caller is about to
    // call [start] which notifies anyway.
  }

  Future<void> start({
    required List<TutorialStep> steps,
    String flow = 'home_main',
  }) async {
    if (steps.isEmpty) return;
    _steps = steps;
    _currentIndex = 0;
    _flow = flow;
    _startedAt = DateTime.now();
    // ignore: unawaited_futures
    Analytics.shared.tutorialStarted(flow: _flow);
    // ignore: unawaited_futures
    Analytics.shared.tutorialStepShown(flow: _flow, step: 0);
    notifyListeners();
    await _runOnEnter();
  }

  Future<void> next() async {
    if (!isRunning || _isTransitioning) return;
    final newIndex = _currentIndex + 1;
    if (newIndex >= _steps.length) {
      await _finishInternal(skipped: false);
      return;
    }
    _currentIndex = newIndex;
    // ignore: unawaited_futures
    Analytics.shared.tutorialStepShown(flow: _flow, step: newIndex);
    notifyListeners();
    await _runOnEnter();
  }

  Future<void> skip() async {
    final stepAtSkip = _currentIndex;
    // ignore: unawaited_futures
    Analytics.shared.tutorialStepDismissed(flow: _flow, step: stepAtSkip);
    await _finishInternal(skipped: true);
  }

  /// Mantido pra compat. Trata como skip pra emitir o evento certo.
  Future<void> finish() async {
    await _finishInternal(skipped: true);
  }

  /// Encerra o tutorial em sucesso após a última tela ("Pronto! Por onde
  /// quer começar?") — usuário escolheu próxima ação (Ver vagas / Cuidar
  /// do CV). Emite `tutorial_completed` com `next_action`.
  Future<void> finishWithChoice({required String nextAction}) async {
    await _finishInternal(skipped: false, nextAction: nextAction);
  }

  Future<void> _finishInternal({
    required bool skipped,
    String? nextAction,
  }) async {
    final startedAt = _startedAt;
    final durationMs = startedAt != null
        ? DateTime.now().difference(startedAt).inMilliseconds
        : 0;
    if (skipped) {
      // ignore: unawaited_futures
      Analytics.shared.tutorialSkipped(flow: _flow);
    } else {
      // ignore: unawaited_futures
      Analytics.shared.tutorialCompleted(
        flow: _flow,
        durationMs: durationMs,
        nextAction: nextAction,
      );
    }
    _currentIndex = -1;
    _steps = const [];
    _isTransitioning = false;
    _startedAt = null;
    await _markSeen();
    notifyListeners();
  }

  Future<void> _runOnEnter() async {
    final step = currentStep;
    if (step == null) return;
    final cb = step.onEnter;
    if (cb == null) return;
    _isTransitioning = true;
    notifyListeners();
    try {
      await cb();
      // Let the target widget actually mount + layout. A single frame
      // isn't enough when there's a PageView animation involved.
      await Future.delayed(const Duration(milliseconds: 380));
    } finally {
      _isTransitioning = false;
      notifyListeners();
    }
  }

  // ── Persistence ─────────────────────────────────────────────────────
  static String _keyFor(String userId) => '$_kPrefPrefix$userId';

  /// True if the current user has already seen (or skipped) the tutorial.
  /// Returns false when there's no logged-in user (safe default — won't
  /// show the tutorial during the auth flow).
  static Future<bool> hasSeen() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFor(userId)) ?? false;
  }

  Future<void> _markSeen() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFor(userId), true);
  }

  /// Clears the "seen" flag for the current user. Used when the user
  /// taps "Tutorial" in Settings — the next call to [start] will run as
  /// if they were a brand new user.
  static Future<void> resetSeen() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFor(userId), false);
  }
}
