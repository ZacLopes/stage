import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../services/ai_service.dart';
import '../../../services/analytics_service.dart';
import '../../auth/user_viewmodel.dart';
import '../../tutorial/tutorial_keys.dart';
import '../jobs_viewmodel.dart';
import '../models/job.dart';
import '../utils/match_score.dart';
import '../widgets/job_card.dart';
import '../widgets/resume_adaptation_sheet.dart';
import 'job_details_sheet.dart';
import 'job_preferences_screen.dart';

class JobsSwipeScreen extends StatefulWidget {
  const JobsSwipeScreen({super.key});

  @override
  State<JobsSwipeScreen> createState() => _JobsSwipeScreenState();
}

class _JobsSwipeScreenState extends State<JobsSwipeScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // Mantém o State vivo quando o user troca de aba e volta — sem isso o
  // PageView descarta páginas que ficam a 2+ índices da atual, o que
  // reinicia o CardSwiper, perde a posição do card e dispara um re-fetch
  // que reshuffleia a ordem das vagas.
  @override
  bool get wantKeepAlive => true;

  final CardSwiperController _swiperController = CardSwiperController();
  bool _initialized = false;

  // Action button press animations
  late final Map<String, AnimationController> _btnControllers;
  late final Map<String, Animation<double>> _btnScales;

  // Swipe drag tracking (updated by Listener, NOT inside cardBuilder)
  // Range: -1.0 (full reject) .. 0.0 (center) .. +1.0 (full like)
  double _swipeFraction = 0.0;
  double _dragStartX = 0.0;
  // How many px of drag = fraction 1.0  (tuned to feel natural)
  static const double _dragScale = 130.0;

  // ──────────────────────────────────────────────────────────────────
  // Match score (IA) — cache em memória + sliding window
  // ──────────────────────────────────────────────────────────────────
  final AIService _aiService = AIService();
  final Map<String, MatchResult> _matchCache = {}; // jobId → result
  final Set<String> _matchInflight = {};            // calls em andamento
  bool _hydrated = false;                           // primeira hidratação rodou?
  int _currentIndex = 0;                            // posição no swiper
  static const int _bufferAhead = 5;                // janela à frente
  static const int _initialPrefetch = 10;           // 1ª onda
  static const int _maxConcurrent = 4;              // limite OpenAI paralelo

  @override
  void initState() {
    super.initState();
    _btnControllers = {
      'undo': AnimationController(vsync: this, duration: const Duration(milliseconds: 120)),
      'reject': AnimationController(vsync: this, duration: const Duration(milliseconds: 120)),
      'ai': AnimationController(vsync: this, duration: const Duration(milliseconds: 150)),
      'like': AnimationController(vsync: this, duration: const Duration(milliseconds: 120)),
      'share': AnimationController(vsync: this, duration: const Duration(milliseconds: 120)),
    };
    _btnScales = _btnControllers.map((key, ctrl) => MapEntry(
          key,
          Tween<double>(begin: 1.0, end: 0.88).animate(
            CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
          ),
        ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        final vm = context.read<JobsViewModel>();
        await vm.init();
        if (mounted) {
          Analytics.shared.jobFeedOpened(jobsCount: vm.jobs.length);
        }
      });
    }
  }

  @override
  void dispose() {
    _swiperController.dispose();
    for (final c in _btnControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _openPreferences() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const JobPreferencesScreen(),
    );
  }

  void _openJobDetails(Job job, [MatchResult? match]) {
    HapticFeedback.lightImpact();
    Analytics.shared.jobDetailsOpened(jobId: job.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => JobDetailsSheet(job: job, match: match),
    );
  }

  /// Compartilha a vaga atual via share sheet do iOS/Android (apps de
  /// mensagem, email, copiar link, etc). Usa `_currentIndex` pra pegar
  /// a vaga em foco no swiper. Não-op se feed vazio.
  ///
  /// Conteúdo enviado:
  /// - Título + empresa + localização + modelo + tipo
  /// - URL externa (Greenhouse/Lever/Apify) se disponível
  /// - Atribuição "via Stage" (não obrigatório, dá visibilidade)
  Future<void> _shareCurrentJob() async {
    final vm = context.read<JobsViewModel>();
    if (vm.jobs.isEmpty) return;
    final idx = _currentIndex.clamp(0, vm.jobs.length - 1);
    final job = vm.jobs[idx];

    HapticFeedback.lightImpact();

    final buf = StringBuffer();
    buf.writeln('💼 ${job.title}');
    buf.writeln('🏢 ${job.companyName}');
    buf.writeln('📍 ${job.location} • ${job.workModel} • ${job.jobType}');
    if (job.salaryRange.isNotEmpty && job.salaryRange != 'A combinar') {
      buf.writeln('💰 ${job.salaryRange}');
    }
    final url = job.externalUrl;
    if (url != null && url.isNotEmpty) {
      buf.writeln();
      buf.writeln(url);
    }
    buf.writeln();
    buf.writeln('Encontrei essa vaga no Stage 🚀');

    // Origem (origin) é importante no iPad — sem isso o share popover não
    // tem âncora visual e crasha. Pego a posição do botão de share usando
    // o context da própria action bar.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;

    try {
      await Share.share(
        buf.toString(),
        subject: 'Vaga: ${job.title} @ ${job.companyName}',
        sharePositionOrigin: origin,
      );
      Analytics.shared.jobShared(jobId: job.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não consegui compartilhar: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Abre a sheet de adaptação de currículo pra a vaga atual do swiper.
  /// Usa `_currentIndex` (mantido em sincronia pelo onSwipe do CardSwiper).
  /// Não-op se ainda não há vagas carregadas ou índice fora dos limites.
  void _openAdaptationSheet() {
    final vm = context.read<JobsViewModel>();
    if (vm.jobs.isEmpty) return;
    final idx = _currentIndex.clamp(0, vm.jobs.length - 1);
    final job = vm.jobs[idx];
    final match = _matchCache[job.id];

    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ResumeAdaptationSheet(
        job: job,
        matchScoreFromCard: match?.score,
      ),
    );
  }

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    final vm = context.read<JobsViewModel>();
    final action = direction == CardSwiperDirection.right ? 'liked' : 'rejected';
    if (action == 'liked') {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    vm.onSwipe(previousIndex, action);

    // Analytics: instrumenta o swipe pra medir engagement (top funnel)
    if (previousIndex < vm.jobs.length) {
      final job = vm.jobs[previousIndex];
      final cachedMatch = _matchCache[job.id]?.score;
      Analytics.shared.jobSwiped(
        jobId: job.id,
        action: action == 'liked' ? 'like' : 'reject',
        matchScore: cachedMatch,
      );
    }

    // Atualiza posição interna e dispara IA pras próximas vagas (buffer ahead)
    _currentIndex = currentIndex ?? (previousIndex + 1);
    _ensureBufferAhead(vm.jobs);

    // Reset overlay immediately (no setState needed — Listener already stopped)
    if (mounted) setState(() => _swipeFraction = 0.0);
    return true;
  }

  Future<void> _pressButton(String key, VoidCallback action) async {
    HapticFeedback.lightImpact();
    await _btnControllers[key]!.forward();
    action();
    await _btnControllers[key]!.reverse();
  }

  // ──────────────────────────────────────────────────────────────────
  // Match score — sliding window
  // ──────────────────────────────────────────────────────────────────

  /// Resolve o match pra um job: cache em memória → fallback determinístico.
  /// Síncrono, seguro pra usar dentro do cardBuilder do CardSwiper.
  /// Quando chega no card, dispara [_kickOffMatch] em background pra que
  /// o score IA atualize na próxima rebuild.
  ///
  /// Nota: se cache veio com score=0 (IA antiga sem reasons úteis), tratamos
  /// como inválido e usamos fallback. Isso protege contra dados ruins de
  /// versões antigas do prompt.
  MatchResult _resolveMatch(Job job) {
    final cached = _matchCache[job.id];
    if (cached != null && cached.score > 0) return cached;

    // Fallback instantâneo
    final vm = context.read<JobsViewModel>();
    final fallback = MatchScoreCalculator.calculate(
      job: job,
      prefs: vm.preferences,
      gamificationData: context.read<UserViewModel>().user?.gamificationData,
    );

    // Se ainda não disparou IA pra este job, dispara agora.
    if (!_matchInflight.contains(job.id)) {
      _kickOffMatch(job);
    }
    return fallback;
  }

  /// Dispara IA pro job (fire-and-forget). Respeita _maxConcurrent.
  Future<void> _kickOffMatch(Job job) async {
    if (_matchCache.containsKey(job.id) || _matchInflight.contains(job.id)) {
      return;
    }
    // Concurrency limit: se cheio, agenda re-try em 250ms
    if (_matchInflight.length >= _maxConcurrent) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _kickOffMatch(job);
      });
      return;
    }

    _matchInflight.add(job.id);
    try {
      final result = await _aiService.analyzeMatch(job.id);
      if (!mounted) return;
      setState(() {
        _matchCache[job.id] = result;
      });
    } catch (e) {
      // Falha silenciosa — fallback determinístico já está sendo mostrado.
      // Não loggar com print pra não poluir console em casos esperados (offline).
    } finally {
      _matchInflight.remove(job.id);
    }
  }

  /// Hidratação inicial: 1 SELECT em batch nos próximos 20 jobs +
  /// dispara IA pros 10 primeiros que ainda não estão no cache.
  Future<void> _hydrateAndPrefetch(List<Job> jobs) async {
    if (_hydrated || jobs.isEmpty) return;
    _hydrated = true;

    final ids = jobs.take(20).map((j) => j.id).toList();
    final cached = await _aiService.fetchCachedMatches(ids);
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() => _matchCache.addAll(cached));
    }

    // Dispara IA pras N primeiras que ainda não têm cache
    for (final job in jobs.take(_initialPrefetch)) {
      if (!_matchCache.containsKey(job.id)) {
        _kickOffMatch(job);
      }
    }
  }

  /// Garante que [currentIndex+1 .. currentIndex+_bufferAhead] estão em cache
  /// ou inflight. Chamado após cada swipe.
  void _ensureBufferAhead(List<Job> jobs) {
    final start = _currentIndex + 1;
    final end = (start + _bufferAhead).clamp(0, jobs.length);
    for (int i = start; i < end; i++) {
      final job = jobs[i];
      if (!_matchCache.containsKey(job.id)) {
        _kickOffMatch(job);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // requerido pelo AutomaticKeepAliveClientMixin
    final vm = context.watch<JobsViewModel>();

    // Hidrata cache + dispara IA quando vm.jobs chega pela primeira vez.
    if (!_hydrated && !vm.isLoading && vm.jobs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _hydrateAndPrefetch(vm.jobs);
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEEF2FF),
              Color(0xFFF1F5F9),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 4),

              // Stack so we can draw the fixed swipe overlay on top of the cards
              Expanded(
                child: Stack(
                  children: [
                    _buildBody(vm),
                    // Fixed overlay — never rotates, perfectly centered on the card area
                    if (!vm.isLoading && vm.jobs.isNotEmpty)
                      _buildSwipeOverlay(),
                  ],
                ),
              ),

              if (!vm.isLoading && vm.jobs.isNotEmpty)
                _buildActionBar(),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AppBar(
            title: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              ).createShader(bounds),
              child: const Text(
                'Vagas',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            centerTitle: true,
            backgroundColor: Colors.white.withOpacity(0.75),
            elevation: 0,
            scrolledUnderElevation: 0,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: _openPreferences,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Loader exibido enquanto o auto-reload (depois do user esgotar o feed)
  /// está rodando em background. Visual mais leve que o `_buildLoading`
  /// inicial — comunica "buscando mais vagas pra você".
  Widget _buildAutoReloadLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Buscando mais vagas…',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(JobsViewModel vm) {
    // Loading state
    if (vm.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Buscando as melhores vagas\npara o seu perfil...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    // Error state
    if (vm.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFECACA), width: 2),
                ),
                child: const Icon(Icons.wifi_off_rounded, size: 36, color: Color(0xFFEF4444)),
              ),
              const SizedBox(height: 20),
              Text(
                vm.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _buildGradientButton(
                label: 'Tentar novamente',
                icon: Icons.refresh_rounded,
                onTap: () => vm.init(),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state — sem jobs OU todos já foram swipados
    if (vm.jobs.isEmpty || vm.remainingCount == 0) {
      // Auto-reload uma vez antes de mostrar o estado vazio. Captura vagas
      // novas que entraram via sync entre o último fetch e agora. Se já
      // tentou e ainda está vazio (`autoReloadAttempted`), aí mostra o
      // estado normal.
      if (!vm.autoReloadAttempted &&
          !vm.isLoading &&
          !vm.filtersAreTooRestrictive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          vm.tryAutoReload();
        });
        // Renderiza loading enquanto auto-reload acontece.
        return _buildAutoReloadLoading();
      }
      // Distingue 2 cenários: filtros zeraram tudo (vagas existem mas não
      // batem) vs. realmente esgotou. Mensagem e CTA mudam.
      final isFiltersTooStrict = vm.filtersAreTooRestrictive;
      final iconData = isFiltersTooStrict
          ? Icons.filter_alt_off_rounded
          : Icons.rocket_launch_rounded;
      final title = isFiltersTooStrict
          ? 'Nenhuma vaga bate com seus filtros'
          : 'Você explorou tudo!';
      final subtitle = isFiltersTooStrict
          ? 'Existem ${vm.totalAvailable} vagas ativas, mas seus\nfiltros estão muito restritivos. Tente afrouxar.'
          : 'Ajuste seus filtros ou volte\nmais tarde para novas oportunidades.';

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF4F46E5).withOpacity(0.08),
                      const Color(0xFF7C3AED).withOpacity(0.08),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  iconData,
                  size: 48,
                  color: const Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isFiltersTooStrict)
                    _buildOutlinedActionButton(
                      label: 'Limpar filtros',
                      icon: Icons.filter_alt_off_rounded,
                      onTap: () async {
                        await vm.clearPreferences();
                      },
                    )
                  else
                    _buildOutlinedActionButton(
                      label: 'Filtros',
                      icon: Icons.tune_rounded,
                      onTap: _openPreferences,
                    ),
                  const SizedBox(width: 12),
                  _buildGradientButton(
                    label: isFiltersTooStrict ? 'Ajustar' : 'Recarregar',
                    icon: isFiltersTooStrict
                        ? Icons.tune_rounded
                        : Icons.refresh_rounded,
                    onTap: isFiltersTooStrict
                        ? _openPreferences
                        : () => vm.reloadJobs(),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // ─────────────────────────────────────────────────────────────
    // Listener wraps the CardSwiper at the RAW pointer level.
    // It does NOT compete with CardSwiper's GestureDetector because
    // Listener never enters the gesture arena — it only observes.
    // This guarantees the overlay works on every card, not just the first.
    // ─────────────────────────────────────────────────────────────
    return Listener(
      onPointerDown: (e) {
        _dragStartX = e.localPosition.dx;
      },
      onPointerMove: (e) {
        final delta = e.localPosition.dx - _dragStartX;
        final newFraction = (delta / _dragScale).clamp(-1.0, 1.0);
        if ((newFraction - _swipeFraction).abs() > 0.015) {
          setState(() => _swipeFraction = newFraction);
        }
      },
      onPointerUp: (_) {
        // If the swipe wasn't committed (card snaps back), reset the indicator.
        // If it WAS committed, _onSwipe resets it.
        // We delay slightly so the card snap-back finishes before we hide overlay.
        Future.delayed(const Duration(milliseconds: 180), () {
          if (mounted) setState(() => _swipeFraction = 0.0);
        });
      },
      onPointerCancel: (_) {
        if (mounted) setState(() => _swipeFraction = 0.0);
      },
      child: CardSwiper(
        controller: _swiperController,
        cardsCount: vm.jobs.length,
        onSwipe: _onSwipe,
        // Horizontal only — no accidental vertical swipes
        allowedSwipeDirection: const AllowedSwipeDirection.only(
          left: true,
          right: true,
        ),
        threshold: 50,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        numberOfCardsDisplayed: vm.jobs.length > 1 ? 2 : 1,
        // ─── scale: 1.0 is the FIX for cards appearing smaller over time.
        // With scale < 1.0, each back card is multiplied by scale^n,
        // and the advance animation sometimes doesn't fully complete,
        // leaving each new front card slightly smaller than the last.
        // scale: 1.0 = all cards identical size. Depth via backCardOffset only.
        scale: 1.0,
        backCardOffset: const Offset(0, -12),
        cardBuilder: (context, index, percentThresholdX, percentThresholdY) {
          if (index >= vm.jobs.length) return const SizedBox();
          final job = vm.jobs[index];
          final match = _resolveMatch(job);
          return GestureDetector(
            onTap: () => _openJobDetails(job, match),
            child: JobCard(job: job, matchScore: match.score),
          );
        },
      ),
    );
  }

  /// Premium swipe overlay — fixed, never rotates, works on every card.
  Widget _buildSwipeOverlay() {
    final f = _swipeFraction;
    // Ease the raw fraction so the overlay feels responsive but smooth
    final likeT  = f > 0 ? Curves.easeOutCubic.transform(f.clamp(0.0, 1.0))  : 0.0;
    final rejectT = f < 0 ? Curves.easeOutCubic.transform(f.abs().clamp(0.0, 1.0)) : 0.0;

    if (likeT < 0.03 && rejectT < 0.03) return const SizedBox.shrink();

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Ambient gradient wash ──────────────────────────
          // A very subtle directional color from the side being swiped toward,
          // giving the card area a sense of colored light without hiding content.
          if (likeT > 0.03)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF10B981).withOpacity(likeT * 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          if (rejectT > 0.03)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      const Color(0xFFEF4444).withOpacity(rejectT * 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

          // ── Stamp badges ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
            child: Stack(
              children: [
                if (likeT > 0.03)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: _SwipeStamp(
                      icon: Icons.favorite_rounded,
                      label: 'APLICAR',
                      color: const Color(0xFF10B981),
                      t: likeT,
                      flipSign: -1,
                    ),
                  ),
                if (rejectT > 0.03)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _SwipeStamp(
                      icon: Icons.arrow_back_rounded,
                      label: 'PULAR',
                      color: const Color(0xFFEF4444),
                      t: rejectT,
                      flipSign: 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Undo
          _buildActionButton(
            key: 'undo',
            icon: Icons.undo_rounded,
            size: 50,
            iconSize: 22,
            bgColor: Colors.white,
            fgColor: const Color(0xFF94A3B8),
            shadowColor: Colors.black.withOpacity(0.08),
            onTap: () async {
              final vm = context.read<JobsViewModel>();
              await vm.undoLastSwipe();
              try {
                _swiperController.undo();
              } catch (_) {}
            },
          ),

          // Reject
          _buildActionButton(
            key: 'reject',
            icon: Icons.close_rounded,
            size: 62,
            iconSize: 28,
            bgColor: const Color(0xFFFEF2F2),
            fgColor: const Color(0xFFEF4444),
            shadowColor: const Color(0xFFEF4444).withOpacity(0.2),
            onTap: () => _swiperController.swipe(CardSwiperDirection.left),
          ),

          // AI (Center - largest)
          KeyedSubtree(
            key: TutorialKeys.aiButton,
            child: _buildGradientActionButton(
              key: 'ai',
              icon: Icons.auto_awesome_rounded,
              size: 70,
              iconSize: 30,
              colors: [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
              shadowColor: const Color(0xFF4F46E5).withOpacity(0.45),
              onTap: _openAdaptationSheet,
            ),
          ),

          // Like
          _buildActionButton(
            key: 'like',
            icon: Icons.favorite_rounded,
            size: 62,
            iconSize: 28,
            bgColor: const Color(0xFFF0FDF4),
            fgColor: const Color(0xFF10B981),
            shadowColor: const Color(0xFF10B981).withOpacity(0.2),
            onTap: () => _swiperController.swipe(CardSwiperDirection.right),
          ),

          // Share
          _buildActionButton(
            key: 'share',
            icon: Icons.ios_share_rounded,
            size: 50,
            iconSize: 22,
            bgColor: Colors.white,
            fgColor: const Color(0xFF94A3B8),
            shadowColor: Colors.black.withOpacity(0.08),
            onTap: _shareCurrentJob,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String key,
    required IconData icon,
    required double size,
    required double iconSize,
    required Color bgColor,
    required Color fgColor,
    required Color shadowColor,
    required VoidCallback onTap,
  }) {
    return ScaleTransition(
      scale: _btnScales[key]!,
      child: GestureDetector(
        onTapDown: (_) => _btnControllers[key]!.forward(),
        onTapUp: (_) {
          _btnControllers[key]!.reverse();
          onTap();
        },
        onTapCancel: () => _btnControllers[key]!.reverse(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 12,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: fgColor, size: iconSize),
        ),
      ),
    );
  }

  Widget _buildGradientActionButton({
    required String key,
    required IconData icon,
    required double size,
    required double iconSize,
    required List<Color> colors,
    required Color shadowColor,
    required VoidCallback onTap,
  }) {
    return ScaleTransition(
      scale: _btnScales[key]!,
      child: GestureDetector(
        onTapDown: (_) => _btnControllers[key]!.forward(),
        onTapUp: (_) {
          _btnControllers[key]!.reverse();
          onTap();
        },
        onTapCancel: () => _btnControllers[key]!.reverse(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F46E5).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutlinedActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF475569), size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Premium swipe stamp
//  t: 0.0 = invisible/tiny → 1.0 = full size; flipSign: -1 left, +1 right
// ─────────────────────────────────────────────────────────────
class _SwipeStamp extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  /// Eased progress 0.0 → 1.0
  final double t;
  /// -1 = tilt left (like), +1 = tilt right (skip)
  final int flipSign;

  const _SwipeStamp({
    required this.icon,
    required this.label,
    required this.color,
    required this.t,
    required this.flipSign,
  });

  @override
  Widget build(BuildContext context) {
    // Stamp scales from 0.55 → 1.0
    final scale = 0.55 + 0.45 * t;
    // Fixed slight tilt — decorative, NOT tied to grab point
    final tilt = 0.15 * flipSign;

    final Alignment scaleAnchor =
        flipSign < 0 ? Alignment.topLeft : Alignment.topRight;

    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        alignment: scaleAnchor,
        child: Transform.rotate(
          angle: tilt,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Outer glow ring
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withOpacity(0.35 * t),
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.55 * t),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 34),
                ),
              ),
              const SizedBox(height: 8),
              // Label pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4 * t),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
