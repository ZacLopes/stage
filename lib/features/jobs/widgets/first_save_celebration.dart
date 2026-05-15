import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Overlay celebratório exibido na PRIMEIRA vez que o usuário salva uma vaga
/// (swipe à direita). Educa que vagas salvas vão pra outra aba e é lá que ele
/// aplica.
///
/// Design:
/// - Backdrop escuro
/// - Heart animado com escala bounce + glow pulsante
/// - Card explicativo com slide-up + fade
/// - CTA principal "Ver vagas salvas →" indigo→purple
/// - Botão sutil "Continuar curtindo vagas"
Future<bool?> showFirstSaveCelebration(
  BuildContext context, {
  required VoidCallback onSeeSaved,
}) {
  HapticFeedback.mediumImpact();
  return Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => _FirstSaveCelebration(onSeeSaved: onSeeSaved),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    ),
  );
}

class _FirstSaveCelebration extends StatefulWidget {
  final VoidCallback onSeeSaved;
  const _FirstSaveCelebration({required this.onSeeSaved});

  @override
  State<_FirstSaveCelebration> createState() => _FirstSaveCelebrationState();
}

class _FirstSaveCelebrationState extends State<_FirstSaveCelebration>
    with TickerProviderStateMixin {
  static const _indigo = Color(0xFF4F46E5);
  static const _purple = Color(0xFF7C3AED);
  static const _emerald = Color(0xFF10B981);
  static const _textPrimary = Color(0xFF0F172A);
  static const _textSecondary = Color(0xFF475569);

  late final AnimationController _heartCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _cardCtrl;
  late final AnimationController _ctaCtrl;

  late final Animation<double> _heartScale;
  late final Animation<double> _heartFade;
  late final Animation<double> _glowOpacity;
  late final Animation<double> _cardSlide;
  late final Animation<double> _cardFade;
  late final Animation<double> _ctaScale;

  @override
  void initState() {
    super.initState();

    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.15).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 65,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 35,
      ),
    ]).animate(_heartCtrl);
    _heartFade = CurvedAnimation(
      parent: _heartCtrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowOpacity = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _cardSlide = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic),
    );
    _cardFade = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut);

    _ctaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _ctaScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctaCtrl, curve: Curves.easeOutBack),
    );

    _orchestrate();
  }

  Future<void> _orchestrate() async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    _heartCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 380));
    if (!mounted) return;
    _cardCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    _ctaCtrl.forward();
  }

  @override
  void dispose() {
    _heartCtrl.dispose();
    _glowCtrl.dispose();
    _cardCtrl.dispose();
    _ctaCtrl.dispose();
    super.dispose();
  }

  void _onSeeSaved() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSeeSaved();
    });
  }

  void _onContinue() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              _buildHeart(),
              const SizedBox(height: 32),
              _buildExplanationCard(),
              const SizedBox(height: 22),
              _buildCta(),
              const SizedBox(height: 10),
              _buildContinueButton(),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeart() {
    return FadeTransition(
      opacity: _heartFade,
      child: AnimatedBuilder(
        animation: Listenable.merge([_heartScale, _glowOpacity]),
        builder: (context, _) {
          return SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _emerald.withOpacity(_glowOpacity.value * 0.6),
                        _emerald.withOpacity(0.0),
                      ],
                      stops: const [0.3, 1.0],
                    ),
                  ),
                ),
                Transform.scale(
                  scale: _heartScale.value,
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [_emerald, Color(0xFF34D399)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _emerald.withOpacity(0.42),
                          blurRadius: 36,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildExplanationCard() {
    return AnimatedBuilder(
      animation: Listenable.merge([_cardSlide, _cardFade]),
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _cardSlide.value),
          child: Opacity(opacity: _cardFade.value, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            const Text(
              'Você salvou sua\nprimeira vaga! 🎯',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
                height: 1.25,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Suas vagas curtidas ficam na aba "Salvas".',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                color: _textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _indigo.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.touch_app_rounded, size: 16, color: _indigo),
                ),
                const SizedBox(width: 10),
                const Flexible(
                  child: Text(
                    'Lá você toca na vaga e aplica direto no site da empresa.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCta() {
    return ScaleTransition(
      scale: _ctaScale,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_indigo, _purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _indigo.withOpacity(0.42),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: InkWell(
              onTap: _onSeeSaved,
              borderRadius: BorderRadius.circular(16),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ver vagas salvas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return ScaleTransition(
      scale: _ctaScale,
      child: TextButton(
        onPressed: _onContinue,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        child: Text(
          'Continuar curtindo vagas',
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
