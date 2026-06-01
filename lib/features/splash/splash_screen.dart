import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../core/theme/theme.dart'; // AppColors, AppGradients
import '../auth/user_viewmodel.dart';
import '../auth/onboarding_screen.dart';
import '../auth/completion_screen.dart';
import '../home/home_screen.dart';
import '../onboarding/presentation/two_doors_screen.dart';

// ─────────────────────────────────────────────────────────────────────────
// TOKENS — tudo que você costuma querer ajustar mora aqui no topo.
// Direção "A Conexão": os dois nós (terminais do S) aparecem separados e o
// traço nasce ao conectá-los → vira a tese do produto (você ↔ oportunidade).
// ─────────────────────────────────────────────────────────────────────────
class _SplashTokens {
  _SplashTokens._();

  // Cores (referenciam o design system; trocar aqui propaga pra splash toda)
  static const Color markColor = AppColors.textOnDark; // branco
  static final Color glowColor = AppColors.brandCyan.withValues(alpha: 0.45);
  static const Gradient background = AppGradients.brand; // cyan → blue

  // Tipografia (fontes bundladas no projeto)
  static const String headingFont = 'Outfit';

  // Conteúdo
  static const String wordmark = 'Stage';

  // Geometria
  static const double markSize = 132; // lado do "S" em px lógicos
  static const double glowSize = 280;

  // Timing
  static const Duration introDuration = Duration(milliseconds: 2200);
  static const Duration exitDuration = Duration(milliseconds: 350);
  static const Duration reducedIntro = Duration(
    milliseconds: 450,
  ); // reduce motion
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin, ScreenTrackingMixin {
  @override
  String get screenName => 'splash';

  late final AnimationController _intro;
  late final AnimationController _exit;
  bool _reduceMotion = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this); // duration definida em didChange
    _exit = AnimationController(
      vsync: this,
      duration: _SplashTokens.exitDuration,
    );

    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) _exit.forward();
    });
    _exit.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) _navigateNext();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Acessibilidade: respeita "reduzir movimento" do SO.
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    if (!_started) {
      _started = true;
      _intro
        ..duration = _reduceMotion
            ? _SplashTokens.reducedIntro
            : _SplashTokens.introDuration
        ..forward();
      // O native splash (flutter_native_splash, sem preserve()) some sozinho
      // quando este 1º frame Flutter pinta. Como a cor nativa (#1E88B8) é o
      // meio do gradient, o handoff é imperceptível.
    }
  }

  void _navigateNext() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AuthGate(),
        transitionsBuilder: (context, anim, secondaryAnimation, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _intro.dispose();
    _exit.dispose();
    super.dispose();
  }

  /// Mapeia o tempo global t∈[0,1] pra um sub-intervalo [b,e] com curva.
  double _seg(double t, double b, double e, Curve c) {
    if (t <= b) return 0;
    if (t >= e) return 1;
    return c.transform((t - b) / (e - b));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        label: 'Stage',
        child: AnimatedBuilder(
          animation: Listenable.merge([_intro, _exit]),
          builder: (context, _) {
            final t = _intro.value;
            final rm = _reduceMotion;

            // Inputs da animação. Em reduce-motion, tudo já no estado final
            // e só um fade master suave entra.
            final double master = rm ? Curves.easeOut.transform(t) : 1.0;
            final double glow = rm ? 0.55 : _seg(t, 0.00, 0.22, Curves.easeOut);
            // nodeA = ponto de PARTIDA (superior-direita): entra primeiro.
            final double nodeA = rm
                ? 1
                : _seg(t, 0.10, 0.30, Curves.easeOutBack);
            // draw = traço guiado pela espinha do S, de cima para baixo.
            final double draw = rm
                ? 1
                : _seg(t, 0.28, 0.70, Curves.easeInOutCubic);
            // nodeB = ponto de CHEGADA (inferior-esquerda): entra quando o
            // traço chega perto, sem deixar o brilho atravessar a bolinha.
            final double nodeB = rm
                ? 1
                : _seg(t, 0.60, 0.82, Curves.easeOutBack);
            final double glint = (rm || draw <= 0.03 || draw >= 0.86)
                ? -1
                : draw;
            final double exactMarkT = rm
                ? 1
                : _seg(t, 0.72, 0.82, Curves.easeOutCubic);
            final double wordT = rm
                ? master
                : _seg(t, 0.72, 0.90, Curves.easeOutCubic);

            // Settle breath (sobe e volta) — só no modo cheio.
            final double breath = rm
                ? 0
                : _seg(t, 0.66, 0.80, Curves.easeInOut) *
                      (1 - _seg(t, 0.80, 0.94, Curves.easeInOut));
            final double markScale = 1 + 0.03 * breath + 0.08 * _exit.value;

            // Opacidade do conteúdo: master (reduce) × fade-out do exit.
            final double fg = (master * (1 - _exit.value)).clamp(0.0, 1.0);

            return Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: _SplashTokens.background,
              ),
              child: Center(
                child: Opacity(
                  opacity: fg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Marca: halo + S desenhado + nós ──────────────────
                      SizedBox(
                        width: _SplashTokens.glowSize,
                        height: _SplashTokens.glowSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Halo de luz (depth / "palco acende")
                            Opacity(
                              opacity: glow,
                              child: Transform.scale(
                                scale:
                                    (0.8 + 0.2 * glow) *
                                    (1 + 0.3 * _exit.value),
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        _SplashTokens.glowColor,
                                        _SplashTokens.glowColor.withValues(
                                          alpha: 0,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // O "S" vetorial + os dois nós
                            Transform.scale(
                              scale: markScale,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Opacity(
                                    opacity: 1 - exactMarkT,
                                    child: CustomPaint(
                                      size: const Size.square(
                                        _SplashTokens.markSize,
                                      ),
                                      painter: _StageMarkPainter(
                                        color: _SplashTokens.markColor,
                                        draw: draw,
                                        nodeA: nodeA,
                                        nodeB: nodeB,
                                        glint: glint,
                                      ),
                                    ),
                                  ),
                                  Opacity(
                                    opacity: exactMarkT,
                                    child: Image.asset(
                                      'assets/images/stage_mark_white.png',
                                      width: _SplashTokens.markSize,
                                      height: _SplashTokens.markSize,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      // ── Wordmark ─────────────────────────────────────────
                      Transform.translate(
                        offset: Offset(0, 10 * (1 - wordT)),
                        child: Opacity(
                          opacity: wordT,
                          child: const Text(
                            _SplashTokens.wordmark,
                            style: TextStyle(
                              fontFamily: _SplashTokens.headingFont,
                              fontSize: 46,
                              fontWeight: FontWeight.w700,
                              color: _SplashTokens.markColor,
                              letterSpacing: 0.5,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Painter da marca: glifo "S" EXATO do brandbook, revelado por um traço
// central de cima para baixo e recortado no shape real do S.
// Vetor puro → crisp em qualquer DPI, 60fps fácil. O path é parseado e
// ajustado UMA vez (cache estático), não a cada frame.
// ─────────────────────────────────────────────────────────────────────────
class _StageMarkPainter extends CustomPainter {
  _StageMarkPainter({
    required this.color,
    required this.draw, // 0..1 progresso do traço
    required this.nodeA, // 0..1 nó superior-direito (partida)
    required this.nodeB, // 0..1 nó inferior-esquerdo (chegada)
    required this.glint, // 0..1 posição da luz; <0 = desligado
  });

  final Color color;
  final double draw, nodeA, nodeB, glint;

  // Path "d" do símbolo "S" (brandbook), em coords glyph-local. Pra trocar o
  // logo no futuro, basta substituir esta string pelo `d` do novo SVG.
  static const String _sPathData =
      'M 91.046875 32.796875 C 74.960938 27.515625 61.789062 20.640625 51.53125 12.171875 C 41.269531 3.703125 34.332031 -5.363281 30.71875 -15.03125 C 27.113281 -24.707031 26.757812 -33.945312 29.65625 -42.75 C 32.050781 -50.019531 35.804688 -54.988281 40.921875 -57.65625 C 46.046875 -60.332031 52.53125 -60.378906 60.375 -57.796875 C 55.019531 -41.515625 55.820312 -27.507812 62.78125 -15.78125 C 69.75 -4.050781 82.035156 4.707031 99.640625 10.5 C 116.492188 16.039062 130.347656 17.46875 141.203125 14.78125 C 152.066406 12.09375 159.320312 5.195312 162.96875 -5.90625 C 165.175781 -12.601562 165.3125 -18.65625 163.375 -24.0625 C 161.4375 -29.476562 157.015625 -35.070312 150.109375 -40.84375 C 143.203125 -46.613281 132.820312 -53.582031 118.96875 -61.75 C 102.613281 -71.375 90.097656 -80.421875 81.421875 -88.890625 C 72.742188 -97.359375 67.210938 -106.019531 64.828125 -114.875 C 62.441406 -123.726562 63.007812 -133.507812 66.53125 -144.21875 C 70.0625 -154.945312 76.175781 -163.382812 84.875 -169.53125 C 93.582031 -175.6875 104.210938 -179.140625 116.765625 -179.890625 C 129.328125 -180.640625 142.976562 -178.59375 157.71875 -173.75 C 171.6875 -169.15625 183.53125 -163.085938 193.25 -155.546875 C 202.96875 -148.003906 209.753906 -139.617188 213.609375 -130.390625 C 217.460938 -121.171875 217.910156 -112.054688 214.953125 -103.046875 C 213.128906 -97.492188 209.929688 -93.71875 205.359375 -91.71875 C 200.785156 -89.726562 194.757812 -89.960938 187.28125 -92.421875 C 189.957031 -107.671875 188.328125 -119.984375 182.390625 -129.359375 C 176.460938 -138.734375 165.75 -145.972656 150.25 -151.078125 C 135.3125 -155.984375 122.957031 -157.125 113.1875 -154.5 C 103.414062 -151.882812 96.953125 -145.785156 93.796875 -136.203125 C 91.597656 -129.503906 91.273438 -123.515625 92.828125 -118.234375 C 94.378906 -112.953125 98.238281 -107.597656 104.40625 -102.171875 C 110.570312 -96.753906 119.695312 -90.46875 131.78125 -83.3125 C 149.925781 -72.675781 163.742188 -62.929688 173.234375 -54.078125 C 182.734375 -45.234375 188.742188 -36.257812 191.265625 -27.15625 C 193.796875 -18.050781 193.265625 -8.039062 189.671875 2.875 C 183.941406 20.300781 172.148438 31.644531 154.296875 36.90625 C 136.441406 42.164062 115.359375 40.796875 91.046875 32.796875 Z';

  // Centros dos dois nós em coords glyph-local (= page - (264.7717, 419.132),
  // extraídos dos círculos cyan do brandbook). Raio-fonte ≈ 16.2.
  static const Offset _nodeTRSrc = Offset(202.13, -88.53); // superior-direita
  static const Offset _nodeBLSrc = Offset(40.93, -23.33); // inferior-esquerda
  static const double _nodeRSrc = 16.2;

  // Cache estático: parse + fit acontecem uma vez (a splash tem tamanho fixo).
  static final Path _srcPath = parseSvgPathData(_sPathData);
  static final Path _traceSrcPath = Path()
    ..moveTo(_nodeTRSrc.dx, _nodeTRSrc.dy)
    ..cubicTo(195, -124, 169, -155, 128, -158)
    ..cubicTo(88, -161, 72, -140, 80, -118)
    ..cubicTo(88, -96, 118, -83, 148, -61)
    ..cubicTo(183, -35, 179, -4, 149, 10)
    ..cubicTo(116, 25, 73, 13, _nodeBLSrc.dx, _nodeBLSrc.dy);
  static Size? _fitSize;
  static Path _fitPath = Path();
  static Path _tracePath = Path();
  static Offset _trPx = Offset.zero;
  static Offset _blPx = Offset.zero;
  static double _rPx = 0;
  static double _traceLength = 0;

  static void _ensureFit(Size size) {
    if (_fitSize == size) return;
    // Bounds combinados (glifo + os dois discos) pra centralizar tudo junto.
    final combined = _srcPath
        .getBounds()
        .expandToInclude(Rect.fromCircle(center: _nodeTRSrc, radius: _nodeRSrc))
        .expandToInclude(
          Rect.fromCircle(center: _nodeBLSrc, radius: _nodeRSrc),
        );
    final s = size.shortestSide / math.max(combined.width, combined.height);
    final dx = (size.width - combined.width * s) / 2 - combined.left * s;
    final dy = (size.height - combined.height * s) / 2 - combined.top * s;
    // Matrix4 column-major: escala s + translação (dx,dy). p' = (s·x+dx, s·y+dy).
    final m = Float64List.fromList(<double>[
      s, 0, 0, 0, //
      0, s, 0, 0, //
      0, 0, 1, 0, //
      dx, dy, 0, 1, //
    ]);
    _fitPath = _srcPath.transform(m);
    _tracePath = _traceSrcPath.transform(m);
    _trPx = Offset(_nodeTRSrc.dx * s + dx, _nodeTRSrc.dy * s + dy);
    _blPx = Offset(_nodeBLSrc.dx * s + dx, _nodeBLSrc.dy * s + dy);
    _rPx = _nodeRSrc * s;
    _traceLength = _tracePath.computeMetrics().fold<double>(
      0,
      (sum, metric) => sum + metric.length,
    );
    _fitSize = size;
  }

  static Path _traceUntil(double progress) {
    final target = _traceLength * progress.clamp(0.0, 1.0);
    var consumed = 0.0;
    final out = Path();
    for (final metric in _tracePath.computeMetrics()) {
      final remaining = target - consumed;
      if (remaining <= 0) break;
      out.addPath(
        metric.extractPath(0, math.min(remaining, metric.length)),
        Offset.zero,
      );
      consumed += metric.length;
    }
    return out;
  }

  static Offset _tracePointAt(double progress) {
    final target = _traceLength * progress.clamp(0.0, 1.0);
    var consumed = 0.0;
    for (final metric in _tracePath.computeMetrics()) {
      if (target <= consumed + metric.length) {
        return metric
                .getTangentForOffset(
                  (target - consumed).clamp(0.0, metric.length),
                )
                ?.position ??
            _trPx;
      }
      consumed += metric.length;
    }
    return _blPx;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureFit(size);

    // 1) Glifo "S" revelado pelo traço + furos que separam os nós do S.
    if (draw > 0) {
      // saveLayer pra que o BlendMode.clear recorte buracos no S revelando o
      // gradient do fundo (efeito do logo: disco dentro de um furo do S).
      canvas.saveLayer(Offset.zero & size, Paint());

      final paint = Paint()
        ..isAntiAlias = true
        ..color = color;
      if (draw >= 0.985) {
        paint.style = PaintingStyle.fill;
        paint.color = color; // estado final / reduce motion: branco sólido
      } else {
        canvas.save();
        canvas.clipPath(_fitPath);
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.shortestSide * 0.38
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(_traceUntil(draw), paint);
        canvas.restore();
      }
      if (draw >= 0.985) canvas.drawPath(_fitPath, paint);

      // Furos ao redor dos nós. O recorte inferior antecipa o crescimento da
      // bolinha para impedir que o traço invada o nó durante o reveal.
      final clear = Paint()..blendMode = BlendMode.clear;
      if (nodeA > 0) canvas.drawCircle(_trPx, _rPx * 1.58 * nodeA, clear);
      final bottomCut = math.max(
        nodeB.clamp(0.0, 1.0),
        ((draw - 0.62) / 0.18).clamp(0.0, 1.0),
      );
      if (bottomCut > 0) {
        canvas.drawCircle(_blPx, _rPx * 1.58 * bottomCut, clear);
        canvas.drawOval(
          Rect.fromCenter(
            center: _blPx.translate(_rPx * 0.62, -_rPx * 1.05),
            width: _rPx * 2.55 * bottomCut,
            height: _rPx * 1.75 * bottomCut,
          ),
          clear,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: _blPx.translate(_rPx * 0.82, -_rPx * 2.28),
            width: _rPx * 2.8 * bottomCut,
            height: _rPx * 1.75 * bottomCut,
          ),
          clear,
        );
        canvas.drawLine(
          _blPx.translate(-_rPx * 0.72, -_rPx * 1.28),
          _blPx.translate(_rPx * 0.72, -_rPx * 2.72),
          Paint()
            ..isAntiAlias = true
            ..blendMode = BlendMode.clear
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = _rPx * 1.05 * bottomCut,
        );
      }

      canvas.restore();

      // 2) Glint: acompanha o traço, mas desliga antes de cruzar o nó final.
      if (glint >= 0) {
        final p = _tracePointAt(glint.clamp(0.04, 0.82));
        canvas.drawCircle(
          p,
          _rPx * 0.7,
          Paint()
            ..color = Colors.white
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
    }

    // 3) Discos brancos dentro dos furos, nas posições exatas do brandbook.
    void node(Offset c, double t) {
      if (t <= 0) return;
      canvas.drawCircle(c, _rPx * t, Paint()..color = color);
    }

    node(_trPx, nodeA);
    node(_blPx, nodeB);
  }

  @override
  bool shouldRepaint(_StageMarkPainter old) =>
      old.draw != draw ||
      old.nodeA != nodeA ||
      old.nodeB != nodeB ||
      old.glint != glint ||
      old.color != color;
}

/// Wrapper to handle auth state: logged in → Home, logged out → Onboarding
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading && viewModel.user == null) {
          // Brief loading state while checking auth
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(gradient: AppGradients.brand),
            ),
          );
        }

        if (viewModel.isLoggedIn) {
          // Roteamento centralizado pós-login. Ordem importa:
          // 1. hasCampaign=true → HomeScreen (user já finalizou onboarding).
          //    Tem prioridade porque o novo flow popula profile_personal mas
          //    NÃO os campos legacy de user_profiles (course/semester/
          //    university) — sem essa prioridade, needsProfileSetup ficaria
          //    true e a gente entraria em loop redirecionando pra TwoDoors.
          // 2. isInProfileFirstFlow → TwoDoorsScreen (QA Dia 7 fix). User está
          //    mid-flow profile-first (tem profile_personal preenchido — IA
          //    extraiu CV OU user respondeu masking question). Sem este check,
          //    quando AttributionScreen salva e dispara notifyListeners, AuthGate
          //    rebuilda, needsProfileSetup retorna false (porque IA preencheu
          //    firstName+lastName+email), AuthGate ia pra CompletionScreen, que
          //    pushava TwoDoorsScreen → loop infinito reportado pelo user.
          // 3. needsProfileSetup → TwoDoorsScreen (entrada do onboarding
          //    profile-first). Cobre Apple/Google sem nome, phone signup, etc.
          // 4. Sem campaign mas sem precisar setup → CompletionScreen (legacy).
          //
          // Esse Consumer re-roteia automaticamente quando o state muda
          // (ex: user finaliza onboarding → hasCampaign vira true → rebuild →
          // HomeScreen). Telas filhas NÃO devem fazer push manual —
          // gera GlobalKey duplicada com a HomeScreen que esse Consumer monta.
          if (viewModel.hasCampaign) {
            return const HomeScreen();
          }
          if (viewModel.isInProfileFirstFlow) {
            return const TwoDoorsScreen();
          }
          if (viewModel.needsProfileSetup) {
            return const TwoDoorsScreen();
          }
          return const CompletionScreen();
        } else {
          return const OnboardingScreen();
        }
      },
    );
  }
}
