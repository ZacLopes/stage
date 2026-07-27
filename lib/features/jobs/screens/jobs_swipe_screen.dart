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
import '../../../services/analytics_events.dart';
import '../../../services/analytics_service.dart';
import '../../../services/facebook_events_service.dart';
import '../../../services/profile_events.dart';
import '../../../services/profile_snapshot_service.dart';
import '../../auth/user_viewmodel.dart';
import '../../home/home_viewmodel.dart';
import '../../tutorial/tutorial_keys.dart';
import '../job_swipe_context.dart';
import '../jobs_viewmodel.dart';
import '../models/job.dart';
import '../pending_adapted_cv_tracker.dart';
import '../utils/match_score.dart';
import '../../../services/notifications_service.dart';
import '../widgets/company_request_sheet.dart';
import '../widgets/first_save_celebration.dart';
import '../widgets/job_card.dart';
import '../widgets/resume_adaptation_sheet.dart';
import '../widgets/skills_confirmation_sheet.dart';
import 'job_details_sheet.dart';
import 'job_preferences_screen.dart';
import 'jobs_list_screen.dart';
import '../../../core/theme/theme.dart';
import '../utils/adapt_gate.dart';

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
  // FASE 2 fixes (#3): o MAPA de resultados agora vive no JobsViewModel
  // (cache compartilhado com o detalhe da lista/salvas — antes o detalhe
  // aberto fora do swipe não tinha match e mostrava 0%). A sliding-window e o
  // _matchInflight abaixo FICAM locais — só o RESULTADO é compartilhado.
  Map<String, MatchResult> get _matchCache =>
      context.read<JobsViewModel>().matchResultCache;
  final Set<String> _matchInflight = {};            // calls em andamento
  bool _hydrated = false;                           // primeira hidratação rodou?
  int _currentIndex = 0;                            // posição no swiper
  // T2.2 — dedupe pra job_card_shown: dispara 1x por card/sessão (revealed
  // preference). Sem isso o evento duplicaria a cada rebuild do stack.
  final Set<String> _cardShownJobIds = {};
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

  /// Lock pra `_openAdaptationSheet`. Sem isso, double-tap no botão de
  /// adaptar (QA Dia 8) abria 2 SkillsConfirmationSheet → 2 ResumeAdaptationSheet
  /// → 2x chamada de IA (dobra custo OpenAI) + `adapt_failed` fantasma
  /// disparando do widget disposto. O guard é síncrono pra cortar antes
  /// do showModalBottomSheet começar a animar.
  bool _openingAdaptSheet = false;

  /// Guard pra disparar `requestAttIfNeeded` no PRIMEIRO swipe da sessão.
  /// ATT saiu do home open — Apple recomenda pedir tracking só depois do
  /// user ter contexto do app. Primeiro swipe = "user já entendeu que
  /// somos um app de vagas" = momento certo pra prompt.
  bool _attRequested = false;

  /// Snapshot do `prefsVersion` do JobsViewModel — usado pra detectar quando
  /// o user salva preferências novas ENQUANTO o feed está aberto. Quando muda,
  /// invalidamos o `_matchCache` em memória (scores antigos com prefs velhas).
  /// Null inicial significa "nunca observei ainda" — primeira leitura não
  /// dispara invalidação.
  int? _lastPrefsVersion;

  /// FASE 2 (T2.2): snapshot do `feedEpoch` do VM. Quando muda (página
  /// nova do RPC substituiu `_jobs`), o CardSwiper é recriado via Key e o
  /// índice/dedupe de exposição zeram — reinício coincide com array
  /// esgotado, sem dessincronizar o current-index interno (B4).
  int _lastFeedEpoch = 0;

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
    _profileEventsSub = ProfileEvents.instance.matchInputsChanged.listen((_) {
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
        // T2.4 — holdout do match resolvido 1x por sessão (gate de
        // elegibilidade + flag PostHog; failure-safe = controle).
        unawaited(vm.resolveMatchScoreHoldout());
        if (mounted) {
          Analytics.shared.jobFeedOpened(jobsCount: vm.jobs.length);
          // T2.2 — card do topo exibido (exposição). Sem isso o funil
          // feed→swipe→details→apply e o "apply rate por bucket" ficavam sem
          // o passo de exposição (job_card_shown não tinha emissor no app).
          _trackCardShown(vm, _currentIndex);
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

  /// T2.3 — CTA de alerta do estado A: garante permissão de push (o digest
  /// diário existente já avisa de vagas novas; sem permissão ele não chega).
  Future<void> _enableNewJobsAlert() async {
    HapticFeedback.lightImpact();
    final granted = await NotificationsService.shared
        .requestPermission(fallbackToSettings: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'Boa! Te avisamos quando entrarem vagas novas. 🔔'
              : 'Ative as notificações nos Ajustes pra receber o alerta.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }


  void _openJobDetails(Job job, [MatchResult? match]) {
    HapticFeedback.lightImpact();
    Analytics.shared.jobDetailsOpened(
      jobId: job.id,
      matchScore: match?.score ?? job.matchScore,
    );
    // Facebook ViewContent — intent forte. Dispara em todo "Ver detalhes"
    // (sem dedupe — cada view é sinal de interesse contínuo).
    // ignore: unawaited_futures
    FacebookEventsService.shared.logViewContent(
      jobId: job.id,
      jobTitle: job.title,
      company: job.company?.name,
    );
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
    // Fix QA Dia 8: guard contra double-tap. Sem isso, dois taps rápidos
    // no botão de adaptar abriam 2x SkillsConfirmationSheet → 2x chamada
    // de extract-job-skills → 2x adaptResume (cada uma custa $0,01-0,03 OpenAI)
    // e disparavam `adapt_started` duplicado + `adapt_failed` fantasma do
    // widget já disposed. Reset no finally garante reabertura legítima depois.
    if (_openingAdaptSheet) return;
    _openingAdaptSheet = true;
    try {
      await _openAdaptationSheetInner();
    } finally {
      if (mounted) _openingAdaptSheet = false;
    }
  }

  Future<void> _openAdaptationSheetInner() async {
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

    // F6 (§5 do device-test): o gate rodava DEPOIS desta folha — o usuário
    // escolhia habilidades, clicava "Adaptar como está" e só então descobria
    // que não dava, com o app já sabendo antes de abrir a folha. Avaliamos
    // antes: se está barrado, pula a folha e vai direto pra sheet, que renderiza
    // o erro honesto com a saída certa.
    final gate = evaluateAdaptGate(
      hasNarrativeMaterial: userVm.canAdaptCv,
      skillCount: userVm.skillCount,
      skillCountIsReliable: userVm.skillCountIsReliable,
    );

    if (gate == AdaptGateResult.allowed && hasResume) {
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
        reason: gate != AdaptGateResult.allowed ? 'gate_blocked' : 'no_cv',
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
        // Fix QA Dia 8 (Bug 2): em swipes rápidos o cache IA pode não ter
        // chegado, mas o `Job.matchScore` carregado do feed traz o baseline
        // determinístico computado no fetch. Sem esse fallback, 14 de 15
        // swipes consecutivos vinham com match_score=null e os gráficos do
        // pitch ficavam capados.
        matchScore = (job.matchScore > 0) ? job.matchScore : null;
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
      // Activation milestone — idempotente (1x por device).
      // ignore: unawaited_futures
      Analytics.shared.activationMilestoneHit(milestone: 'first_swipe');
      // B.14 do plano v2 — enriquecer com position_in_feed (revealed
      // preference), company_id, modality, salary_bucket, location_bucket.
      // Sem isso, "match converte por área/empresa/range salarial?" é cego.
      Analytics.shared.jobSwiped(
        jobId: job.id,
        action: action == 'liked' ? 'like' : 'reject',
        matchScore: matchScore,
        matchSource: matchSource,
        // Confidence do match (Passo 5) — só quando há análise real (cache IA
        // resolvido e não-unknown). Powers o insight de distribuição de
        // confidence no dashboard Match v9.
        matchConfidence: (cached != null && !cached.isUnknown)
            ? cached.confidence.name
            : null,
        // application_method ('email'|'url'): permite o funil "swipe-right em
        // vaga com candidatura por email → aplicou por email".
        applicationMethod: job.applicationMethod,
        positionInFeed: previousIndex,
        companyId: job.companyId,
        companyName: job.companyName,
        modality: job.workModelRaw ?? job.workModel,
        salaryBucket: _bucketSalary(job.salaryMin, job.salaryMax),
        locationBucket: _bucketLocation(job.locationCity, job.locationState),
        feedMode: 'swipe', // FASE 2: save-rate por modo (lista emite 'list')
        // T2.4 — holdout: o que o user VIU de fato (pós-flag e
        // pós-confidence) + variante pra cortar a análise por atribuição.
        scoreVisible: vm.matchScoreVisible &&
            cached != null &&
            !cached.isUnknown &&
            cached.confidence != MatchConfidence.low,
        holdoutVariant: vm.holdoutVariant,
      );
      // Fix QA Dia 8 (Bug 3): persiste o `matchScore` por job_id pra que a
      // aba Curtidas leia o número correto depois (sem isso `match_score=0`
      // chegava no apply, quebrando a correlação match × conversão).
      // ignore: unawaited_futures
      JobSwipeContext.shared.recordSwipe(job.id, matchScore);

      // Facebook AddToWishlist — só no primeiro swipe right por (user, jobId).
      // Dedupado em SharedPreferences via logAddToWishlistFirstTime.
      if (action == 'liked') {
        // ignore: unawaited_futures
        FacebookEventsService.shared.logAddToWishlistFirstTime(
          userId: Supabase.instance.client.auth.currentUser?.id,
          jobId: job.id,
        );
      }

      // ATT prompt — disparar 1x por sessão no PRIMEIRO swipe (qualquer
      // direção). User já entendeu o contexto do app aqui, então o opt-in
      // rate tende a ser maior do que se pedisse logo na entrada do home.
      // SDK é internamente idempotente (não re-prompta se já foi decidido).
      if (!_attRequested) {
        _attRequested = true;
        // ignore: unawaited_futures
        FacebookEventsService.shared.requestAttIfNeeded();
      }
    }

    // Atualiza posição interna e dispara IA pras próximas vagas (buffer ahead)
    _currentIndex = currentIndex ?? (previousIndex + 1);
    _ensureBufferAhead(vm.jobs);
    // T2.2 — novo card do topo exibido após o swipe avançar a posição.
    _trackCardShown(vm, _currentIndex);

    // B.17 — feed_exhausted agora é emitido em JobsViewModel.tryAutoReload
    // (ponto real de exaustão = remainingCount==0). Esta condição
    // `_currentIndex >= jobs.length` nunca era atingida (a tela troca pro
    // empty-state antes), por isso o evento ficava 0 all-time. Movido pra lá.

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

  /// T2.2 — Emite `job_card_shown` quando o card no índice [index] vira o
  /// topo da pilha (exposição / revealed preference). Deduplicado por job.id
  /// (1x por card/sessão). `match_score` usa o resultado IA cacheado quando
  /// disponível; senão o baseline determinístico do feed (mesma lógica do
  /// swipe). Fire-and-forget — analytics nunca quebra a UI.
  void _trackCardShown(JobsViewModel vm, int index) {
    if (index < 0 || index >= vm.jobs.length) return;
    final job = vm.jobs[index];
    if (!_cardShownJobIds.add(job.id)) return; // já exibido nesta sessão
    final cached = _matchCache[job.id];
    final int score = (cached != null && !cached.isUnknown)
        ? cached.score
        : (job.matchScore > 0 ? job.matchScore : 0);
    // ignore: unawaited_futures
    Analytics.shared.jobCardShown(
      jobId: job.id,
      matchScore: score,
      positionInFeed: index,
      companyId: job.companyId,
      modality: job.workModelRaw ?? job.workModel,
      salaryBucket: _bucketSalary(job.salaryMin, job.salaryMax),
      locationBucket: _bucketLocation(job.locationCity, job.locationState),
      feedMode: 'swipe', // FASE 2: exposição por modo
      // T2.4 — holdout: exposição com/sem banda visível + variante.
      scoreVisible: vm.matchScoreVisible &&
          cached != null &&
          !cached.isUnknown &&
          cached.confidence != MatchConfidence.low,
      holdoutVariant: vm.holdoutVariant,
    );
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

    Analytics.shared.track(evFirstSaveCelebrationShown);

    await showFirstSaveCelebration(
      context,
      onSeeSaved: () {
        if (!mounted) return;
        Analytics.shared.track(evFirstSaveCelebrationContinued);
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

    // FASE 2 (T2.2): página nova do RPC substituiu _jobs (snapshot do
    // swipe avançou) → o CardSwiper renasce via Key(feedEpoch); índice e
    // dedupe de exposição zeram junto e o match IA re-hidrata pro
    // snapshot novo. No-op com flag OFF (epoch fica em 0).
    if (_lastFeedEpoch != vm.feedEpoch) {
      _lastFeedEpoch = vm.feedEpoch;
      _currentIndex = 0;
      _cardShownJobIds.clear();
      _matchInflight.clear();
      _hydrated = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _trackCardShown(context.read<JobsViewModel>(), _currentIndex);
      });
    }

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
          // FASE 2 (T2.2): modo LISTA (flag feed_list_v1 + toggle, D-6).
          // O swipe (abaixo) segue sendo o padrão.
          child: vm.feedRpcEnabled && vm.feedMode == JobsViewModel.feedModeList
              ? const JobsListView()
              : Column(
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
          // FASE 2 (T2.2): toggle swipe↔lista — só com feed_list_v1 ON.
          if (context.watch<JobsViewModel>().feedRpcEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: Builder(builder: (context) {
                  final vm = context.watch<JobsViewModel>();
                  return _FeedModeToggle(
                    isList: vm.feedMode == JobsViewModel.feedModeList,
                    onChanged: (list) {
                      HapticFeedback.lightImpact();
                      // ignore: unawaited_futures
                      vm.setFeedMode(list
                          ? JobsViewModel.feedModeList
                          : JobsViewModel.feedModeSwipe);
                    },
                  );
                }),
              ),
            ),
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
      // Distingue 2 cenários (T2.3, exaustão honesta): estado B = filtros
      // zeraram tudo (vagas existem mas não batem); estado A = fim das
      // relevantes de verdade. B1/D2 do plano provaram que os DOIS existem
      // hoje — esses estados são produto, não edge case.
      final isFiltersTooStrict = vm.filtersAreTooRestrictive;
      final iconData = isFiltersTooStrict
          ? Icons.filter_alt_off_rounded
          : Icons.task_alt_rounded;
      final title = isFiltersTooStrict
          ? 'Nenhuma vaga bate com seus filtros'
          : 'Você viu as relevantes por agora';
      final subtitle = isFiltersTooStrict
          ? 'Existem ${vm.totalAvailable} vagas ativas, mas seus\nfiltros estão muito restritivos. Tente afrouxar.'
          : 'Vagas novas entram toda semana.\nA gente te avisa quando chegarem.';

      // Overflow fix (15/06): em telas mais baixas o estado A (vários botões:
      // alerta + expandir + pedir empresa + recarregar) passava da altura
      // disponível → "RenderFlex overflowed". SingleChildScrollView deixa a
      // tela rolar em vez de estourar. (Centralizava antes; agora alinha ao
      // topo e rola quando não cabe — aceitável pra empty state.)
      return SingleChildScrollView(
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
              if (isFiltersTooStrict)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildOutlinedActionButton(
                      label: 'Limpar filtros',
                      icon: Icons.filter_alt_off_rounded,
                      onTap: () async {
                        await vm.clearPreferences();
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildGradientButton(
                      label: 'Ajustar',
                      icon: Icons.tune_rounded,
                      onTap: _openPreferences,
                    ),
                  ],
                )
              else ...[
                // T2.3 — estado A: alerta (digest existente) + expansão
                // honesta (só quando o filtro de modelo exclui remotas) +
                // pedido de empresa.
                _buildGradientButton(
                  label: 'Me avisar de vagas novas',
                  icon: Icons.notifications_active_rounded,
                  onTap: _enableNewJobsAlert,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (vm.canExpandToRemote) ...[
                      _buildOutlinedActionButton(
                        label: 'Incluir remotas',
                        icon: Icons.public_rounded,
                        onTap: () => vm.expandFiltersWithRemote(),
                      ),
                      const SizedBox(width: 12),
                    ],
                    _buildOutlinedActionButton(
                      label: 'Pedir uma empresa',
                      icon: Icons.add_business_rounded,
                      onTap: () => CompanyRequestSheet.show(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => vm.reloadJobs(),
                  icon: const Icon(Icons.refresh_rounded,
                      size: 18, color: AppColors.textTertiary),
                  label: const Text(
                    'Recarregar',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
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
        // FASE 2 (T2.2): Key por feedEpoch — página nova do RPC recria o
        // swiper do zero (índice interno zera com o array novo; B4).
        // Com flag OFF o epoch é constante 0 → comportamento idêntico.
        key: ValueKey('feed_epoch_${vm.feedEpoch}'),
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
              // T2.4 — holdout: variante 'hidden' não vê banda pré-swipe.
              showScore: vm.matchScoreVisible,
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
                      label: 'SALVAR',
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

  // ── Buckets pra analytics B.14 ─────────────────────────────
  /// Discretiza salário em buckets pra agregação no PostHog.
  /// Boa prática: cohorts de salário em 4-5 bins. Granular demais polui.
  String? _bucketSalary(int? min, int? max) {
    final v = min ?? max;
    if (v == null || v <= 0) return null;
    if (v < 2000) return 'lt_2k';
    if (v < 4000) return '2k_4k';
    if (v < 6000) return '4k_6k';
    if (v < 10000) return '6k_10k';
    return 'gte_10k';
  }

  /// Discretiza localização em buckets úteis: maiores capitais SP/RJ/BH/POA,
  /// outras (Brasil), remoto. Cobre 80%+ do feed sem cardinalidade alta.
  String? _bucketLocation(String? city, String? state) {
    final c = city?.toLowerCase().trim() ?? '';
    final s = state?.toLowerCase().trim() ?? '';
    if (c.contains('são paulo') || c == 'sao paulo' || c == 'sp') return 'sp_capital';
    if (c.contains('rio de janeiro') || c == 'rj') return 'rj_capital';
    if (c.contains('belo horizonte') || c == 'bh') return 'bh_capital';
    if (c.contains('porto alegre') || c == 'poa') return 'poa_capital';
    if (s == 'sp') return 'sp_interior';
    if (s == 'rj') return 'rj_interior';
    if (s == 'mg') return 'mg_other';
    if (s == 'rs') return 'rs_other';
    if (s.isNotEmpty) return 'br_other_$s';
    return null;
  }
}

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
/// Toggle de visualização do feed: Cards (swipe) ↔ Lista. Segmented control no
/// estilo Stage (segmento ativo azul + sombra da marca, desliza suave). Mostra
/// os DOIS modos com o ativo rotulado — pra o usuário entender de cara que
/// aquilo troca a visualização (antes era um ícone único, ambíguo).
class _FeedModeToggle extends StatelessWidget {
  const _FeedModeToggle({required this.isList, required this.onChanged});

  /// true = lista, false = cards (swipe).
  final bool isList;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            icon: Icons.style_rounded,
            label: 'Cards',
            selected: !isList,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 2),
          _segment(
            icon: Icons.view_agenda_rounded,
            label: 'Lista',
            selected: isList,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 10 : 7,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.onPrimary : AppColors.textTertiary,
            ),
            // A label só aparece no segmento ATIVO (expande suave) — compacto no
            // header e destaca o modo atual.
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        label,
                        style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

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
