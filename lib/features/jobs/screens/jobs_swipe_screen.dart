import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/analytics/screen_tracking.dart';
import '../../../core/constants/stage_app_links.dart';
import 'dart:async';

import '../../../services/ai_service.dart';
import '../../../services/analytics_service.dart';
import '../../../services/profile_events.dart';
import '../../../services/profile_snapshot_service.dart';
import '../../auth/user_viewmodel.dart';
import '../../home/home_viewmodel.dart';
import '../../tutorial/tutorial_keys.dart';
import '../jobs_viewmodel.dart';
import '../models/job.dart';
import '../pending_adapted_cv_tracker.dart';
import '../utils/match_score.dart';
import '../widgets/first_save_celebration.dart';
import '../widgets/job_card.dart';
import '../widgets/resume_adaptation_sheet.dart';
import '../widgets/skills_confirmation_sheet.dart';
import 'job_details_sheet.dart';
import 'job_preferences_screen.dart';
import '../../../core/theme/theme.dart';

class JobsSwipeScreen extends StatefulWidget {
  const JobsSwipeScreen({super.key});

  @override
  State<JobsSwipeScreen> createState() => _JobsSwipeScreenState();
}

class _JobsSwipeScreenState extends State<JobsSwipeScreen>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        ScreenTrackingMixin {
  @override
  String get screenName => 'jobs_swipe';

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
  // Prefetch reduzido em 2026-05-27: antes era 10 prefetch + 5 buffer ahead,
  // o que disparava 10 chamadas IA logo na abertura da aba. Como o user só
  // vê 1 card por vez no swiper, as outras 8-9 chamadas eram desperdiçadas
  // se ele saía da tela antes — e ainda esgotavam rate limit (100/dia/user)
  // em sessões de teste ou após mudanças que invalidavam cache.
  //
  // Agora: prefetch só os 3 primeiros + mantém pipeline de 2 prontos à
  // frente. Cards ainda sem score mostram MatchResult.pending (animação
  // de dots pulsando + anel tracejado) — nunca score fake. Quando IA
  // chega em 2-3s, ring atualiza pro score real.
  static const int _bufferAhead = 2;                // janela à frente
  static const int _initialPrefetch = 3;            // 1ª onda
  static const int _maxConcurrent = 4;              // limite OpenAI paralelo

  /// F3.1: variante do experimento `ai_match_v1` (PostHog feature flag).
  /// Valores possíveis:
  ///   'ai_match_v1' (default)  → chama OpenAI via analyze-match (caro, like rate 16%)
  ///   'deterministic_v1'       → usa MatchScoreCalculator client-side (free, like rate 24% na análise)
  /// Lido 1x no didChangeDependencies e cacheado por sessão pra evitar
  /// race condition de troca de variante durante o swipe.
  String? _matchVariant;

  /// Lock pra evitar disparar `showModalBottomSheet` duas vezes pelo mesmo
  /// pending — o build pode rodar várias vezes enquanto a sheet abre.
  bool _openingPendingSheet = false;

  /// Snapshot do `prefsVersion` do JobsViewModel — usado pra detectar quando
  /// o user salva preferências novas ENQUANTO o feed está aberto. Quando muda,
  /// invalidamos o `_matchCache` em memória (scores antigos com prefs velhas).
  /// Null inicial significa "nunca observei ainda" — primeira leitura não
  /// dispara invalidação.
  int? _lastPrefsVersion;

  /// Snapshot do `hasResume` no UserViewModel — usado pra detectar quando o
  /// user importa o CV / completa a trilha ENQUANTO o feed está aberto.
  /// Sem isso, o `_matchCache` em memória mantém `MatchResult.noResume()` da
  /// sessão anterior e os cards não atualizam mesmo com o CV novo no DB.
  bool? _lastHasResume;

  /// Pseudo-texto agregado das tabelas `profile_*` pra alimentar o keyword
  /// overlap do match score determinístico (Cenário B). Carregado uma vez
  /// na primeira hidratação; invalidado quando `hasResume` muda OU
  /// `ProfileEvents` dispara (user editou perfil). Null enquanto não
  /// carregou — `MatchScoreCalculator` lida graciosamente.
  String? _profileText;
  final ProfileSnapshotService _profileSnapshotService =
      ProfileSnapshotService();
  StreamSubscription<void>? _profileEventsSub;

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
    // Re-carrega pseudo-texto sempre que o user edita o perfil
    // (ProfileEditorViewModel emite via ProfileEvents). Sem isso,
    // adicionar skill nova não reflete no match até hot-restart.
    _profileEventsSub = ProfileEvents.instance.changes.listen((_) {
      if (!mounted) return;
      _profileText = null;
      _matchCache.clear();
      _matchInflight.clear();
      _hydrated = false;
      // ignore: unawaited_futures
      _loadProfileTextIfNeeded();
    });
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
        // F3.1: lê variante do experimento de match. Default = 'ai_match_v1'
        // (mantém comportamento atual). Se PostHog devolver 'deterministic_v1',
        // pulamos a chamada IA e usamos MatchScoreCalculator client-side —
        // ~5x mais barato e (segundo análise pre-fix) ~50% melhor like rate.
        final variant = await Analytics.shared.getFlag('ai_match_v1');
        if (mounted) {
          setState(() {
            _matchVariant = variant ?? 'ai_match_v1';
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _profileEventsSub?.cancel();
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

  /// Abre a sheet de adaptação pra um jobId vindo do banner do Home.
  /// Tenta achar o job no feed em cache; se não estiver (já foi swiped
  /// pra fora), busca direto do repo. Em caso de falha de fetch,
  /// só navega — o banner fica visível pra próxima tentativa.
  Future<void> _openPendingAdaptSheet(String jobId, JobsViewModel vm) async {
    try {
      Job? job;
      for (final j in vm.jobs) {
        if (j.id == jobId) {
          job = j;
          break;
        }
      }
      job ??= await vm.fetchJobById(jobId);

      if (!mounted) return;
      if (job == null) {
        // Job foi removido do banco — limpa o banner pra parar de prometer
        // o que não existe.
        // ignore: unawaited_futures
        PendingAdaptedCvTracker.shared.clear();
        return;
      }

      final match = _matchCache[jobId];
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ResumeAdaptationSheet(
          job: job!,
          matchScoreFromCard: match?.score,
        ),
      );
    } finally {
      // Libera o lock após o sheet fechar — se o user tentar abrir de novo
      // (banner reapareceu, raro), funciona.
      _openingPendingSheet = false;
    }
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
    buf.writeln();
    buf.writeln('Encontrei essa vaga no Stage 🚀');
    buf.writeln();
    buf.writeln(StageAppLinks.shareCallToAction);

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
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Abre a sheet de adaptação de currículo pra a vaga atual do swiper.
  /// Usa `_currentIndex` (mantido em sincronia pelo onSwipe do CardSwiper).
  /// Não-op se ainda não há vagas carregadas ou índice fora dos limites.
  Future<void> _openAdaptationSheet() async {
    final vm = context.read<JobsViewModel>();
    if (vm.jobs.isEmpty) return;
    final idx = _currentIndex.clamp(0, vm.jobs.length - 1);
    final job = vm.jobs[idx];
    final match = _matchCache[job.id];

    HapticFeedback.mediumImpact();

    // Sheet de confirmação de skills SÓ aparece quando o user tem CV importado
    // — sem CV não temos como cruzar requisitos da vaga contra parsed/raw_text.
    // Sem CV: pula direto pro adaptation sheet (comportamento idêntico ao pré-feature).
    final userVm = context.read<UserViewModel>();
    final hasResume = userVm.hasResume;
    List<String> extraSkills = const [];

    if (hasResume) {
      final result = await showModalBottomSheet<List<String>?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SkillsConfirmationSheet(job: job),
      );
      if (!mounted) return;
      // null = user fechou sem decidir (drag down ou close button) → aborta
      // o fluxo inteiro. Lista vazia = user pulou explicitamente → segue
      // pra adaptação sem extras.
      if (result == null) return;
      extraSkills = result;
    } else {
      Analytics.shared.skillsConfirmationAutoSkipped(
        jobId: job.id,
        reason: 'no_cv',
      );
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ResumeAdaptationSheet(
        job: job,
        matchScoreFromCard: match?.score,
        extraSkills: extraSkills,
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

    // Analytics: instrumenta o swipe pra medir engagement (top funnel).
    // `matchSource` é o sinal mais importante pra calibração futura: distingue
    // swipes em score IA (preciso) vs fallback determinístico vs unknown.
    if (previousIndex < vm.jobs.length) {
      final job = vm.jobs[previousIndex];
      final cached = _matchCache[job.id];
      final String matchSource;
      final int? matchScore;
      if (cached == null) {
        matchSource = 'fallback_deterministic';
        matchScore = null; // UI tava mostrando determinístico — não sabemos qual número exato sem recalcular
      } else if (cached.isUnknown) {
        matchSource = 'unknown';
        matchScore = null;
      } else {
        // F3.1: tag a variante do experimento como match_source pra que o
        // dashboard PostHog compare like rate IA vs determinístico de forma
        // limpa (sem misturar com 'fallback_deterministic', que significa
        // "IA falhou e mostramos o número antigo").
        matchSource = _matchVariant == 'deterministic_v1'
            ? 'deterministic_v1'
            : 'ai';
        matchScore = cached.score;
      }
      Analytics.shared.jobSwiped(
        jobId: job.id,
        action: action == 'liked' ? 'like' : 'reject',
        matchScore: matchScore,
        matchSource: matchSource,
      );
    }

    // Atualiza posição interna e dispara IA pras próximas vagas (buffer ahead)
    _currentIndex = currentIndex ?? (previousIndex + 1);
    _ensureBufferAhead(vm.jobs);

    // Reset overlay immediately (no setState needed — Listener already stopped)
    if (mounted) setState(() => _swipeFraction = 0.0);

    // Celebração de primeira vaga salva: roda DEPOIS do swipe completar
    // (post frame) pra não conflitar com a animação do CardSwiper.
    if (action == 'liked') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeShowFirstSaveCelebration();
      });
    }

    return true;
  }

  /// Mostra overlay celebratório APENAS na primeira vez que o usuário salva
  /// uma vaga. Flag persistida em SharedPreferences por user_id.
  Future<void> _maybeShowFirstSaveCelebration() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'first_save_celebrated_$userId';
    if (prefs.getBool(key) == true) return;
    if (!mounted) return;

    // Marca como visto ANTES de abrir o overlay — evita race condition se
    // o user salvar 2 vagas rápido (segundo swipe não dispara overlay).
    await prefs.setBool(key, true);
    if (!mounted) return;

    Analytics.shared.track('first_save_celebration_shown');

    await showFirstSaveCelebration(
      context,
      onSeeSaved: () {
        if (!mounted) return;
        Analytics.shared.track('first_save_celebration_continued');
        // Troca pra aba "Salvas" (index 1) via HomeViewModel.
        context.read<HomeViewModel>().requestTabChange(1);
      },
    );
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

  /// Resolve o match pra um job: noResume → cache em memória → pending.
  /// Síncrono, seguro pra usar dentro do cardBuilder do CardSwiper.
  ///
  /// Prioridades:
  /// 1. Sem CV importado e sem trilha → `noResume` (não chama IA, UX pede CV)
  /// 2. Cache em memória existe → retorna o resultado IA
  /// 3. Sem cache → dispara IA em background, retorna pending (placeholder)
  ///
  /// Antes retornava o fallback determinístico como placeholder. Isso causava
  /// "flash" no card: score abria 75/100 (determinístico inflado), trocava de
  /// cor 3-5s depois quando IA chegava com 50 real.
  MatchResult _resolveMatch(Job job) {
    // Sem CV/trilha = sem material pra IA analisar. Mostrar % seria mentira
    // (Cenário C devolve 50 fixo). Substitui pelo CTA "crie seu currículo".
    final userVm = context.read<UserViewModel>();
    if (!userVm.hasResume) {
      return const MatchResult.noResume();
    }

    // Pós Passo 5 (2026-05-27): aplica confidence baseado em quantas
    // dimensões o user declarou. Função do USER (não do par user×vaga),
    // então é constante na sessão. computeConfidence é puro/barato — sem
    // necessidade de cachear.
    final vm = context.read<JobsViewModel>();
    final conf = MatchScoreCalculator.computeConfidence(
      prefs: vm.profilePrefs,
      skillsCount: vm.profileSkillsCount,
    );

    final cached = _matchCache[job.id];
    if (cached != null) {
      // Mescla confidence no MatchResult sem alterar score/reasons que
      // vieram da IA (ou do fallback determinístico). UI usa o confidence
      // pra decidir se exibe número, label "Estimativa parcial", ou
      // "Análise limitada" + CTA.
      return cached.withConfidence(conf.level, conf.missing);
    }

    // Sem cache → dispara IA em background e marca como pending.
    if (!_matchInflight.contains(job.id)) {
      _kickOffMatch(job);
    }
    return const MatchResult.pending();
  }

  /// Dispara match pro job (fire-and-forget). Respeita _maxConcurrent.
  /// F3.1: se _matchVariant == 'deterministic_v1', usa cálculo client-side
  /// (gratuito, ~5x mais rápido) em vez de chamar a Edge Function de IA.
  Future<void> _kickOffMatch(Job job) async {
    if (_matchCache.containsKey(job.id) || _matchInflight.contains(job.id)) {
      return;
    }

    // Caminho determinístico: síncrono, sem rate limit, sem custo de IA.
    if (_matchVariant == 'deterministic_v1') {
      final vm = context.read<JobsViewModel>();
      final userVm = context.read<UserViewModel>();
      // Garante profilePrefs carregado do banco antes de calcular — sem
      // isso há race condition após ProfileEvents.changes (cache foi
      // invalidado mas reload assíncrono ainda não terminou). Sintoma
      // observado: user edita Perfil → vaga mostra "Configure suas
      // preferências" mesmo com tudo declarado, até hot restart.
      await vm.ensureProfilePrefsLoaded();
      if (!mounted) return;
      // Pós Passo 3 (2026-05-27): match score lê IDENTIDADE do Perfil
      // (`profilePrefs`, tabelas relacionais), NÃO os filtros temporários
      // do feed (`preferences`). Filtros só escondem/mostram vagas.
      final result = MatchScoreCalculator.calculate(
        job: job,
        prefs: vm.profilePrefs,
        gamificationData: userVm.user?.gamificationData,
        profileText: _profileText,
      );
      if (!mounted) return;
      setState(() {
        _matchCache[job.id] = result;
      });
      return;
    }

    // Caminho IA (default): chama Edge Function analyze-match (gpt-4o-mini).
    // Concurrency limit: se cheio, agenda re-try em 250ms.
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
      // IA falhou (timeout, rate limit 429, 5xx, offline). Pre-fix essa
      // branch era "falha silenciosa" — _matchInflight era limpo mas o
      // cache ficava vazio e o ring continuava em "pending" eternamente
      // (até user dar swipe, que disparava nova tentativa = mesma falha).
      //
      // Agora: cai pro fallback determinístico (MatchScoreCalculator
      // client-side, gratuito, sem rate limit, mesmo input que a IA via).
      // Pode dar score diferente do que a IA daria, mas é melhor que
      // pending eterno. Se uma sessão futura da IA tiver sucesso, o
      // resultado da IA sobrescreve (precedência no cache).
      if (mounted) {
        try {
          final vm = context.read<JobsViewModel>();
          final userVm = context.read<UserViewModel>();
          // Garante profilePrefs carregado (evita race com ProfileEvents,
          // mesmo motivo do caminho determinístico acima).
          await vm.ensureProfilePrefsLoaded();
          if (!mounted) return;
          // Mesmo princípio do caminho determinístico acima: fallback
          // lê IDENTIDADE do Perfil (profilePrefs), não filtros (preferences).
          final fallback = MatchScoreCalculator.calculate(
            job: job,
            prefs: vm.profilePrefs,
            gamificationData: userVm.user?.gamificationData,
            profileText: _profileText,
          );
          setState(() {
            _matchCache[job.id] = fallback;
          });
        } catch (_) {
          // Fallback também falhou (raro — só se Provider context não
          // estiver disponível). Aceita pending → próximo swipe re-tenta.
        }
      }
    } finally {
      _matchInflight.remove(job.id);
    }
  }

  /// Hidratação inicial: 1 SELECT em batch nos próximos 20 jobs +
  /// pseudo-texto das tabelas `profile_*` (necessário pro Cenário B do
  /// match score determinístico) + dispara IA pros 10 primeiros que
  /// ainda não estão no cache.
  Future<void> _hydrateAndPrefetch(List<Job> jobs) async {
    if (_hydrated || jobs.isEmpty) return;
    _hydrated = true;

    final ids = jobs.take(20).map((j) => j.id).toList();
    final cached = await _aiService.fetchCachedMatches(ids);
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() => _matchCache.addAll(cached));
    }

    // Pré-carrega pseudo-texto do perfil em paralelo. Usado pelo caminho
    // determinístico de _kickOffMatch (Skills/CV × requisitos da vaga).
    // ignore: unawaited_futures
    _loadProfileTextIfNeeded();

    // Dispara IA pras N primeiras que ainda não têm cache
    for (final job in jobs.take(_initialPrefetch)) {
      if (!_matchCache.containsKey(job.id)) {
        _kickOffMatch(job);
      }
    }
  }

  /// Carrega o pseudo-texto agregado das tabelas `profile_*` uma vez por
  /// sessão (ou após `hasResume` mudar). Idempotente: pula se já tem.
  Future<void> _loadProfileTextIfNeeded() async {
    if (_profileText != null) return;
    try {
      final snapshot = await _profileSnapshotService.loadCurrent();
      if (snapshot == null) return;
      final text = snapshot.toPseudoText().trim();
      if (!mounted || text.isEmpty) return;
      setState(() => _profileText = text);
    } catch (_) {
      // Falha silenciosa — match score cai pro Cenário A (só prefs).
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
    final userVm = context.watch<UserViewModel>();

    // Detecta transição "user acabou de ganhar CV" (importou PDF ou completou
    // trilha enquanto o feed estava aberto). Sem isso, o `_matchCache` em
    // memória mantém `MatchResult.noResume()` da hidratação anterior e os
    // cards continuam mostrando "crie seu CV" mesmo com o CV novo no DB.
    final currentHasResume = userVm.hasResume;
    if (_lastHasResume == false && currentHasResume == true) {
      _matchCache.clear();
      _matchInflight.clear();
      _hydrated = false; // re-roda o prefetch IA com o novo perfil
      _profileText = null; // re-carrega pseudo-texto na próxima hidratação
    }
    _lastHasResume = currentHasResume;

    // Detecta mudança em preferências (user salvou filtros novos). O server
    // já invalida via profile_hash, mas o cache de memória aqui ficava com
    // scores velhos. `_lastPrefsVersion == null` no primeiro frame evita
    // disparar invalidação no boot.
    final currentPrefsVersion = vm.prefsVersion;
    if (_lastPrefsVersion != null &&
        _lastPrefsVersion != currentPrefsVersion) {
      _matchCache.clear();
      _matchInflight.clear();
      _hydrated = false;
    }
    _lastPrefsVersion = currentPrefsVersion;

    // Hidrata cache + dispara IA quando vm.jobs chega pela primeira vez.
    if (!_hydrated && !vm.isLoading && vm.jobs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _hydrateAndPrefetch(vm.jobs);
      });
    }

    // Handoff do banner do Home: se algum widget pediu pra abrir a sheet
    // de adaptação de um job específico, abre aqui (após chegar na aba).
    final pendingJobId = vm.pendingAdaptSheetJobId;
    if (pendingJobId != null && !_openingPendingSheet) {
      _openingPendingSheet = true;
      // Consumir AGORA (síncrono) pra evitar que o próximo build dispare
      // de novo enquanto a sheet abre.
      vm.consumePendingAdaptSheet();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openPendingAdaptSheet(pendingJobId, vm);
      });
    }

    return Scaffold(
      // primarySoft = mesma cor do topo do gradient. Sem isso, o cinza
      // surfaceMuted do background do Scaffold vazava nas bordas do
      // device (cantos arredondados / status bar inset) acima do gradient.
      backgroundColor: AppColors.primarySoft,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primarySoft,
              AppColors.surfaceMuted,
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
      // Header transparente — o gradiente do body flui direto até o topo
      // (status bar incluso via `extendBodyBehindAppBar: true`). Sem faixa
      // branca, sem blur sobre fundo claro (que ficava sujo).
      child: AppBar(
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.primary, AppColors.primary],
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _openPreferences,
              child: _FilterButtonWithBadge(
                // Watch — rebuilda só esse botão quando o user salva filtros novos
                activeCount: context
                        .watch<JobsViewModel>()
                        .preferences
                        ?.activeFilterCount ??
                    0,
              ),
            ),
          ),
        ],
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
                colors: [AppColors.primary, AppColors.primary],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.25),
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
              color: AppColors.textSecondary,
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
                  colors: [AppColors.primary, AppColors.primary],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
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
                color: AppColors.textSecondary,
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
                  color: AppColors.errorSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.errorSoft, width: 2),
                ),
                child: const Icon(Icons.wifi_off_rounded, size: 36, color: AppColors.error),
              ),
              const SizedBox(height: 20),
              Text(
                vm.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
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
                      AppColors.primary.withOpacity(0.08),
                      AppColors.primary.withOpacity(0.08),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  iconData,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textTertiary,
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
            child: JobCard(
              job: job,
              matchScore: match.score,
              isPending: match.isPending,
              isNoResume: match.isNoResume,
              confidence: match.confidence,
              missingDimensions: match.missingDimensions,
            ),
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
                      AppColors.success.withOpacity(likeT * 0.18),
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
                      AppColors.error.withOpacity(rejectT * 0.18),
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
                      color: AppColors.success,
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
                      color: AppColors.error,
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
            fgColor: AppColors.textTertiary,
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
            bgColor: AppColors.errorSoft,
            fgColor: AppColors.error,
            shadowColor: AppColors.error.withOpacity(0.2),
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
              colors: [AppColors.primary, AppColors.primary],
              shadowColor: AppColors.primary.withOpacity(0.45),
              onTap: _openAdaptationSheet,
            ),
          ),

          // Like
          _buildActionButton(
            key: 'like',
            icon: Icons.favorite_rounded,
            size: 62,
            iconSize: 28,
            bgColor: AppColors.successSoft,
            fgColor: AppColors.success,
            shadowColor: AppColors.success.withOpacity(0.2),
            onTap: () => _swiperController.swipe(CardSwiperDirection.right),
          ),

          // Share
          _buildActionButton(
            key: 'share',
            icon: Icons.ios_share_rounded,
            size: 50,
            iconSize: 22,
            bgColor: Colors.white,
            fgColor: AppColors.textTertiary,
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
            colors: [AppColors.primary, AppColors.primary],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
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
          border: Border.all(color: AppColors.border, width: 1.5),
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
            Icon(icon, color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
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

/// Botão de filtros do AppBar com badge âmbar mostrando quantos filtros estão
/// ativos. `activeCount = 0` → só o ícone roxo padrão (sem badge).
class _FilterButtonWithBadge extends StatelessWidget {
  final int activeCount;

  const _FilterButtonWithBadge({required this.activeCount});

  @override
  Widget build(BuildContext context) {
    final hasFilters = activeCount > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
        ),
        if (hasFilters)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColors.warning, // âmbar — contrasta com roxo, comunica "atenção" sem ser alarme
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.warning.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '$activeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
