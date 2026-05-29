import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:career_gamification/features/gamification/gamification_viewmodel.dart';
import 'package:career_gamification/features/home/home_viewmodel.dart';
import 'package:career_gamification/features/auth/user_viewmodel.dart';
import 'package:career_gamification/features/profile/profile_viewmodel.dart';
import 'package:career_gamification/features/resume/resume_viewmodel.dart';
import 'package:career_gamification/features/resume/widgets/ai_consent_modal.dart';
import 'package:career_gamification/data/models/models.dart';
import '../../../core/theme/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Particle model for confetti effects
// ─────────────────────────────────────────────────────────────────────────────
class _Particle {
  final double startX;
  final double startY;
  final double driftX;
  final double fallDist;
  final Color color;
  final double size;
  final bool isCircle;
  final double delay;
  final double rotSpeed;

  const _Particle({
    required this.startX,
    required this.startY,
    required this.driftX,
    required this.fallDist,
    required this.color,
    required this.size,
    required this.isCircle,
    required this.delay,
    required this.rotSpeed,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Track color map
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, Color> _trackColors = {
  'track_1': AppColors.primary,
  'track_2': AppColors.info,
  'track_3': Color(0xFFF97316),
  'track_4': AppColors.success,
  'track_5': Color(0xFF8B5CF6),
};

const Map<String, String> _trackNames = {
  'track_1': 'Direção',
  'track_2': 'Minha Base',
  'track_3': 'Minhas Experiências',
  'track_4': 'Hard Skills & Idiomas',
  'track_5': 'Links & Logística',
};

// ═════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET — always shows phase completion, then pops track dialog if needed
// ═════════════════════════════════════════════════════════════════════════════
class PhaseCompletionWidget extends StatefulWidget {
  final Phase phase;
  final GamificationViewModel viewModel;

  const PhaseCompletionWidget({
    super.key,
    required this.phase,
    required this.viewModel,
  });

  @override
  State<PhaseCompletionWidget> createState() => _PhaseCompletionWidgetState();
}

class _PhaseCompletionWidgetState extends State<PhaseCompletionWidget>
    with TickerProviderStateMixin {
  late bool _isLastPhaseOfTrack;
  late bool _isLastTrack;

  late AnimationController _mainCtrl;
  late AnimationController _pulseCtrl;

  late Animation<double> _scaleAnim;
  late Animation<double> _slideAnim;
  late Animation<double> _opacityAnim;

  bool _isSaving = false;

  Color get _trackColor =>
      _trackColors[widget.phase.trackId] ?? AppColors.success;

  int get _phaseNumber {
    final sorted = List<Phase>.from(widget.viewModel.phases)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final idx = sorted.indexWhere((p) => p.id == widget.phase.id);
    return idx + 1;
  }

  int get _totalPhases => widget.viewModel.phases.length;

  @override
  void initState() {
    super.initState();
    _detectMode();
    _initAnimations();
  }

  void _detectMode() {
    final sorted = List<Phase>.from(widget.viewModel.phases)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    _isLastPhaseOfTrack =
        sorted.isNotEmpty && sorted.last.id == widget.phase.id;
    _isLastTrack = widget.phase.trackId == 'track_5';
  }

  void _initAnimations() {
    _mainCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _scaleAnim = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
    );

    _slideAnim = Tween<double>(begin: 60, end: 0).animate(CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
    ));

    _opacityAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.35, 0.85, curve: Curves.easeOut),
    ));

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _mainCtrl.forward();
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONTINUE handler — saves, then shows track dialog if track is done
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _handleContinue() async {
    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      await widget.viewModel.saveProgress(widget.phase);
      if (!mounted) return;
      await context.read<UserViewModel>().refreshUser();
      if (!mounted) return;
      await context.read<HomeViewModel>().refresh();
      if (!mounted) return;

      // Fonte de verdade primária: checar se TODAS as fases do curso estão
      // completas via repo. Cobre o caso em que `_phases` está stale (user
      // entrou na fase via direct-push de OpenTrailView sem chamar
      // loadPhases). Se sim, sempre mostra o currículo-pronto, independente
      // da detecção local de "last phase".
      final entireCourseDone = await widget.viewModel.isEntireCourseCompleted();
      if (!mounted) return;

      if (entireCourseDone) {
        _isLastTrack = true; // garante que o dialog certo aparece
        await _showTrackCompletionDialog();
      } else if (_isLastPhaseOfTrack) {
        await _showTrackCompletionDialog();
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: AppColors.error),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  /// Called from the Curriculum Ready dialog button. Orchestrates the
  /// full trail-end sequence:
  ///   1. Ask for AI consent if not yet granted.
  ///   2. Generate the CV with AI (forceRefresh on the ResumeViewModel).
  ///   3. Auto-save the result to the user's library.
  ///   4. Pop gamification stack → animate "document → Profile tab" →
  ///      switch to Profile + highlight the new card.
  ///
  /// If consent is declined: aborts gracefully, closing the celebration
  /// without generating anything. The user can revisit later.
  Future<void> _completeAndGuideToProfile(BuildContext dialogCtx) async {
    final homeVM = context.read<HomeViewModel>();
    final resumeVM = context.read<ResumeViewModel>();
    final profileVM = context.read<ProfileViewModel>();
    final userVM = context.read<UserViewModel>();

    // Step 1: AI consent. If not yet granted, ask now — this is the moment
    // the user actually needs IA, so the prompt makes sense in context.
    final user = userVM.user;
    if (user != null && !user.aiConsent) {
      final accepted = await _askAiConsent(dialogCtx);
      if (!mounted) return;
      if (!accepted) {
        // User declined — close celebration and let them stay on the
        // phase-completion screen. They can re-tap the button to retry.
        Navigator.pop(dialogCtx);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Sem o consentimento, não conseguimos gerar seu currículo com IA. '
                'Você pode aceitar nos ajustes a qualquer momento.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }

    // Step 2: replace the celebration with a fullscreen "generating" overlay
    // so user has visual feedback during the (potentially 5–10s) AI call.
    Navigator.pop(dialogCtx); // close celebration
    if (!mounted) return;
    final overlay = _GeneratingOverlay.show(context);

    SavedResume? saved;
    try {
      // Force regenerate to make sure we have fresh content from the
      // just-completed trail answers (cached _resumeData may be stale).
      await resumeVM.loadResumeData(forceRefresh: true);
      if (!mounted) {
        overlay.remove();
        return;
      }

      // Step 3: save snapshot to library with unique "Currículo Stage" title.
      // Passa profileVM.saveResume como callback pra atualizar a lista
      // local (`savedResumes`) — sem isso a aba Perfil mostra stale até
      // pull-to-refresh.
      saved = await resumeVM.autoSaveTrailResume(
        userVM.user,
        profileVM.resolveUniqueTitle,
        profileVM.saveResume,
      );
    } catch (e) {
      debugPrint('Trail completion CV pipeline failed: $e');
    } finally {
      overlay.remove();
    }

    if (!mounted) return;

    // Step 4: pop gamification stack, then hand off to HomeScreen which
    // plays the landing animation + switches tab + highlights the card.
    Navigator.popUntil(context, (route) => route.isFirst);

    if (saved != null) {
      homeVM.announceCvCreated(
        targetTab: HomeTabs.profile,
        highlightId: saved.id,
      );
    } else {
      // CV pipeline failed but user still ends up on Profile so they can
      // see whatever entries they have / retry from there.
      homeVM.requestTabChange(HomeTabs.profile);
    }
  }

  /// Shows the AI consent modal. Resolves to `true` only if the user
  /// explicitly accepts; declining/dismissing resolves to `false`.
  /// Also persists the consent in user_profiles on accept.
  Future<bool> _askAiConsent(BuildContext anchorCtx) async {
    final userVM = context.read<UserViewModel>();
    final completer = Completer<bool>();

    showGeneralDialog(
      context: anchorCtx,
      barrierDismissible: false,
      pageBuilder: (_, __, ___) => AIConsentModal(
        onAccept: () async {
          await userVM.updateAIConsent(true);
          if (anchorCtx.mounted) Navigator.pop(anchorCtx);
          if (!completer.isCompleted) completer.complete(true);
        },
        onCancel: () {
          if (anchorCtx.mounted) Navigator.pop(anchorCtx);
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  Future<void> _showTrackCompletionDialog() async {
    if (!mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 500),
      transitionBuilder: (ctx, anim, _, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1.0).animate(curve),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, _, __) {
        if (_isLastTrack) {
          return _CurriculumReadyDialog(
            onAction: () => _completeAndGuideToProfile(ctx),
          );
        } else {
          return _TrackCompletionDialog(
            trackId: widget.phase.trackId,
            onAction: () {
              Navigator.pop(ctx); // close dialog
              Navigator.popUntil(context, (route) => route.isFirst);
            },
          );
        }
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD — always renders the clean phase-completion screen
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Color(0xFFE8FDF3)],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
              children: [
                const Spacer(flex: 2),

                // ── Animated checkmark icon ─────────────────────────────
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulse glow ring
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => Container(
                          width: 110 + _pulseCtrl.value * 10,
                          height: 110 + _pulseCtrl.value * 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success
                                .withOpacity(0.08 + _pulseCtrl.value * 0.06),
                          ),
                        ),
                      ),
                      // Main icon
                      ScaleTransition(
                        scale: _scaleAnim,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.success.withOpacity(0.45),
                                blurRadius: 24,
                                spreadRadius: 4,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 64,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Text block ──────────────────────────────────────────
                AnimatedBuilder(
                  animation: _mainCtrl,
                  builder: (_, __) => Opacity(
                    opacity: _opacityAnim.value,
                    child: Transform.translate(
                      offset: Offset(0, _slideAnim.value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            const Text(
                              'Fase Concluída!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.phase.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_totalPhases > 1)
                              Text(
                                'Fase $_phaseNumber de $_totalPhases nesta trilha',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textDisabled,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 3),

                // ── Button ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: AnimatedBuilder(
                    animation: _opacityAnim,
                    builder: (_, __) => Opacity(
                      opacity: _opacityAnim.value,
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _handleContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.border,
                            elevation: 4,
                            shadowColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ).copyWith(
                            elevation: WidgetStateProperty.resolveWith(
                                (s) => s.contains(WidgetState.pressed) ? 0 : 4),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : const Text(
                                  'CONTINUAR',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TRACK COMPLETION DIALOG — shown over phase completion when track is done
// ═════════════════════════════════════════════════════════════════════════════
class _TrackCompletionDialog extends StatefulWidget {
  final String trackId;
  final VoidCallback onAction;

  const _TrackCompletionDialog({
    required this.trackId,
    required this.onAction,
  });

  @override
  State<_TrackCompletionDialog> createState() => _TrackCompletionDialogState();
}

class _TrackCompletionDialogState extends State<_TrackCompletionDialog>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _particleCtrl;
  late List<_Particle> _particles;

  Color get _trackColor =>
      _trackColors[widget.trackId] ?? AppColors.success;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();

    _buildParticles();
  }

  void _buildParticles() {
    final rng = math.Random(widget.trackId.hashCode);
    final palette = [
      _trackColor,
      _trackColor.withOpacity(0.6),
      Colors.white,
      AppColors.gold,
      const Color(0xFFFF6B6B),
    ];
    _particles = List.generate(16, (i) {
      final color = palette[i % palette.length];
      return _Particle(
        startX: 0.05 + rng.nextDouble() * 0.9,
        startY: -0.05 - rng.nextDouble() * 0.25,
        driftX: (rng.nextDouble() - 0.5) * 0.35,
        fallDist: 0.6 + rng.nextDouble() * 0.45,
        color: color,
        size: 6 + rng.nextDouble() * 7,
        isCircle: rng.nextBool(),
        delay: i / 16,
        rotSpeed: 1 + rng.nextDouble() * 3,
      );
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trackColor = _trackColor;
    final darkColor = HSLColor.fromColor(trackColor)
        .withLightness(
            (HSLColor.fromColor(trackColor).lightness - 0.25).clamp(0.0, 1.0))
        .toColor();
    final lightColor = HSLColor.fromColor(trackColor)
        .withLightness(
            (HSLColor.fromColor(trackColor).lightness + 0.15).clamp(0.0, 1.0))
        .toColor();
    final trackName = _trackNames[widget.trackId] ?? 'Trilha';

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.88,
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [darkColor, trackColor, lightColor],
            ),
            boxShadow: [
              BoxShadow(
                color: trackColor.withOpacity(0.5),
                blurRadius: 40,
                spreadRadius: 2,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Confetti particles
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: AnimatedBuilder(
                    animation: _particleCtrl,
                    builder: (_, __) => CustomPaint(
                      painter: _ParticlePainter(
                        particles: _particles,
                        progress: _particleCtrl.value,
                      ),
                    ),
                  ),
                ),
              ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Trophy with glow
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) => Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.18),
                          border: Border.all(
                            color: Colors.white
                                .withOpacity(0.5 + _pulseCtrl.value * 0.3),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white
                                  .withOpacity(0.15 + _pulseCtrl.value * 0.1),
                              blurRadius: 28 + _pulseCtrl.value * 10,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('🏆', style: TextStyle(fontSize: 52)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Title
                    const Text(
                      'Trilha Concluída!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      trackName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Unlock chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: AppColors.success.withOpacity(0.6),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_open_rounded,
                              color: AppColors.success, size: 15),
                          SizedBox(width: 6),
                          Text(
                            'Próxima trilha desbloqueada!',
                            style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: widget.onAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: trackColor,
                          elevation: 4,
                          shadowColor: Colors.black26,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'VER AS TRILHAS',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: trackColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CURRICULUM READY DIALOG — last track completed, navigate to Resume tab
// ═════════════════════════════════════════════════════════════════════════════
class _CurriculumReadyDialog extends StatefulWidget {
  final VoidCallback onAction;

  const _CurriculumReadyDialog({
    required this.onAction,
  });

  @override
  State<_CurriculumReadyDialog> createState() =>
      _CurriculumReadyDialogState();
}

class _CurriculumReadyDialogState extends State<_CurriculumReadyDialog>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _shimmerCtrl;
  late AnimationController _buttonGlowCtrl;
  late AnimationController _floatCtrl;
  late AnimationController _particleCtrl;
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _buttonGlowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();

    _buildParticles();
  }

  void _buildParticles() {
    final rng = math.Random(99);
    const palette = [
      AppColors.gold,
      AppColors.warning,
      Color(0xFF00E5FF),
      Color(0xFFFF4081),
      Color(0xFF69F0AE),
      Color(0xFFE040FB),
      Color(0xFFFFFFFF),
    ];
    _particles = List.generate(22, (i) {
      final color = palette[i % palette.length];
      return _Particle(
        startX: 0.05 + rng.nextDouble() * 0.9,
        startY: -0.05 - rng.nextDouble() * 0.3,
        driftX: (rng.nextDouble() - 0.5) * 0.4,
        fallDist: 0.6 + rng.nextDouble() * 0.5,
        color: color,
        size: 6 + rng.nextDouble() * 8,
        isCircle: rng.nextBool(),
        delay: i / 22,
        rotSpeed: 1 + rng.nextDouble() * 3,
      );
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _buttonGlowCtrl.dispose();
    _floatCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F0C29),
                Color(0xFF2D1B69),
                Color(0xFF4C1D95),
                Color(0xFF3730A3),
              ],
              stops: [0.0, 0.3, 0.65, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.5),
                blurRadius: 40,
                spreadRadius: 2,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Star field
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: _StarFieldWidget(),
                ),
              ),

              // Confetti
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: AnimatedBuilder(
                    animation: _particleCtrl,
                    builder: (_, __) => CustomPaint(
                      painter: _ParticlePainter(
                        particles: _particles,
                        progress: _particleCtrl.value,
                      ),
                    ),
                  ),
                ),
              ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated icon with shimmer ring
                    AnimatedBuilder(
                      animation: Listenable.merge(
                          [_shimmerCtrl, _floatCtrl, _pulseCtrl]),
                      builder: (_, __) {
                        final floatY =
                            math.sin(_floatCtrl.value * math.pi) * 8;
                        return Transform.translate(
                          offset: Offset(0, -floatY),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer shimmer ring
                              Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: SweepGradient(
                                    startAngle:
                                        _shimmerCtrl.value * 2 * math.pi,
                                    endAngle:
                                        _shimmerCtrl.value * 2 * math.pi +
                                            math.pi,
                                    colors: const [
                                      AppColors.gold,
                                      AppColors.warning,
                                      Colors.transparent,
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              // Pulse glow
                              Container(
                                width: 122 + _pulseCtrl.value * 10,
                                height: 122 + _pulseCtrl.value * 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.gold.withOpacity(
                                      0.08 + _pulseCtrl.value * 0.06),
                                ),
                              ),
                              // Inner circle
                              Container(
                                width: 105,
                                height: 105,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const RadialGradient(
                                    colors: [
                                      AppColors.primary,
                                      Color(0xFF2D1B69),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: AppColors.gold
                                        .withOpacity(0.7),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.gold
                                          .withOpacity(
                                              0.3 + _pulseCtrl.value * 0.2),
                                      blurRadius: 25,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text('📄',
                                      style: TextStyle(fontSize: 48)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 28),

                    // Gold title
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          AppColors.gold,
                          AppColors.warning,
                          AppColors.gold,
                        ],
                      ).createShader(bounds),
                      child: const Text(
                        'Currículo Pronto! 🚀',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Você completou todas as trilhas!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.95),
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Seu currículo profissional está\npronto para o mercado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.70),
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // CTA button — glowing gold
                    AnimatedBuilder(
                      animation: _buttonGlowCtrl,
                      builder: (_, __) => Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withOpacity(
                                  0.3 + _buttonGlowCtrl.value * 0.35),
                              blurRadius: 18 + _buttonGlowCtrl.value * 14,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: widget.onAction,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ).copyWith(
                              backgroundColor: WidgetStateProperty.all(
                                  Colors.transparent),
                            ),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  AppColors.gold,
                                  AppColors.warning,
                                  AppColors.gold,
                                ]),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Text(
                                  '✨  VER MEU CURRÍCULO  ✨',
                                  style: TextStyle(
                                    color: Color(0xFF1E1B4B),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Acesse, edite e exporte seu currículo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Star field widget (for Mode 3 dialog background)
// ─────────────────────────────────────────────────────────────────────────────
class _StarFieldWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rng = math.Random(42);
    return CustomPaint(
      painter: _StarFieldPainter(
        dots: List.generate(40, (_) => Offset(rng.nextDouble(), rng.nextDouble())),
        radii: List.generate(40, (_) => 0.4 + rng.nextDouble() * 1.2),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Particle CustomPainter
// ─────────────────────────────────────────────────────────────────────────────
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  const _ParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final start = p.delay * 0.5;
      final end = start + 0.6;
      if (progress < start) continue;
      final t = ((progress - start) / (end - start)).clamp(0.0, 1.0);

      final x = (p.startX + p.driftX * t) * size.width;
      final y = (p.startY + p.fallDist * t) * size.height;
      final opacity = t < 0.8 ? 1.0 : (1.0 - t) / 0.2;
      final rotation = t * p.rotSpeed * math.pi * 2;

      final paint = Paint()
        ..color = p.color.withOpacity(opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: p.size, height: p.size * 0.6),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Star-field CustomPainter
// ─────────────────────────────────────────────────────────────────────────────
class _StarFieldPainter extends CustomPainter {
  final List<Offset> dots;
  final List<double> radii;

  const _StarFieldPainter({required this.dots, required this.radii});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < dots.length; i++) {
      canvas.drawCircle(
        Offset(dots[i].dx * size.width, dots[i].dy * size.height),
        radii[i],
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarFieldPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Generating overlay — fullscreen blocking overlay shown while the trail-end
// pipeline (CV regen via AI → auto-save) runs. Removed when the work is done.
// ─────────────────────────────────────────────────────────────────────────────
class _GeneratingOverlay {
  final OverlayEntry _entry;
  bool _removed = false;

  _GeneratingOverlay._(this._entry);

  static _GeneratingOverlay show(BuildContext context) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => const _GeneratingOverlayContent(),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    return _GeneratingOverlay._(entry);
  }

  void remove() {
    if (_removed) return;
    _removed = true;
    _entry.remove();
  }
}

class _GeneratingOverlayContent extends StatelessWidget {
  const _GeneratingOverlayContent();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.55),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B4B),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.4),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Gerando seu currículo…',
                style: TextStyle(fontFamily: 'Outfit', 
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'A IA tá montando bullets Harvard com suas respostas',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', 
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
