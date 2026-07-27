import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/ai_service.dart';
import '../../services/analytics_events.dart';
import '../../services/analytics_service.dart';
import '../../services/feature_flags_service.dart';
import '../../services/profile_events.dart';
import '../../services/profile_snapshot_service.dart';
import 'data/applications_repository.dart';
import 'data/feed_pager.dart';
import 'data/job_repository.dart';
import 'data/swipe_repository.dart';
import 'models/application.dart';
import 'models/job.dart';
import 'models/user_preferences.dart';
import 'utils/feed_exhaustion.dart';
import 'utils/holdout_gate.dart';
import 'utils/match_score.dart';

class JobsViewModel extends ChangeNotifier {
  final JobRepository _jobRepository;
  final SwipeRepository _swipeRepository;

  /// Fase 1: fonte de verdade do "apliquei" é `applications` (máquina de
  /// estados no banco). Substituiu o PreferencesRepository morto que ocupava
  /// esta posição do construtor (injeção deprecated desde 27/05, removida).
  final ApplicationsRepository _applicationsRepository;
  final AIService _aiService;

  /// Cache da application por job_id (hidratado em [loadLikedJobs]).
  /// `LikedJob.applied` é DERIVADO daqui — `swipe_actions.applied` virou
  /// legacy (builds antigas ainda escrevem; a bridge do banco converte).
  Map<String, Application> _applicationsByJob = {};

  /// Fase 3 (T3.3): applications manuais (type='manual', job_id null) — não
  /// têm vaga atrelada, vivem soltas na aba Candidaturas.
  List<Application> _manualApplications = [];
  List<Application> get manualApplications => _manualApplications;

  /// Listener pra mudanças no auth Supabase. Garante que `init()` rode
  /// assim que o user logar (caso o widget tenha sido construído antes
  /// da sessão estar pronta — race condition que bloqueava o feed até
  /// hot-restart).
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<void>? _profileEventsSub;

  JobsViewModel(
    this._jobRepository,
    this._swipeRepository,
    this._applicationsRepository,
    this._aiService,
  ) {
    // Invalida cache de profileText E profilePrefs quando o user edita o
    // perfil — sem isso, adicionar skill via Profile Editor ou mudar
    // preferências via tab Perfil não reflete no match score determinístico
    // até hot-restart.
    _profileEventsSub = ProfileEvents.instance.matchInputsChanged.listen((_) {
      _profileTextLoaded = false;
      _cachedProfileText = null;
      _profilePrefsLoaded = false;
      _cachedProfilePrefs = null;
      _cachedProfileSkillsCount = 0;
      // Prefs/skills mudaram → scores determinísticos cacheados ficam velhos.
      _matchResultCache.clear();
      notifyListeners();
      // Recarrega profilePrefs em background e re-aplica filtros do feed
      // se o user ainda não setou filtros locais (caso típico: terminou
      // onboarding e foi pra aba Vagas — relacional acabou de receber
      // dados, mas feed continuaria sem filtros sem este reload).
      // ignore: unawaited_futures
      _onProfileChanged();
    });
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          // QA Dia 6 fix: NÃO disparar init() aqui. JobsSwipeScreen
          // chama vm.init() no seu initState (linha ~164), o que
          // garante que feed só carrega quando user está VISUALIZANDO
          // a aba Vagas. O auto-init pelo auth listener disparava
          // `feed_loaded` ~1s pós-signup, antes mesmo do AuthGate
          // decidir se navega pra onboarding ou home — poluindo o
          // funil de ativação.
          break;
        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userDeleted:
          // Limpa estado pra o próximo user logar do zero.
          _jobs = [];
          _swipedIds.clear();
          _undoStack.clear();
          _preferences = null;
          _likedJobs = [];
          _errorMessage = null;
          _autoReloadAttempted = false;
          _gamificationDataLoaded = false;
          _cachedGamificationData = null;
          _profileTextLoaded = false;
          _cachedProfileText = null;
          _profilePrefsLoaded = false;
          _cachedProfilePrefs = null;
          _cachedProfileSkillsCount = 0;
          _matchResultCache.clear();
          _totalAvailable = 0;
          _totalAfterFilters = 0;
          _totalMatchingCatalog = -1;
          // FASE 2 (T2.2): zera a sessão RPC pro próximo user.
          _feedPager = null;
          _rpcSessionActive = false;
          _feedRows.clear();
          _feedModeRaw = feedModeSwipe;
          _exhaustedEmittedRpc = false;
          // FASE 2 (T2.4): holdout re-resolve pro próximo user.
          _holdoutVariant = null;
          _holdoutResolved = false;
          notifyListeners();
          break;
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileEventsSub?.cancel();
    super.dispose();
  }

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
  // Quantas vagas batem com os filtros no catálogo inteiro IGNORANDO swipe.
  // Distingue "esgotou as relevantes" (>0, feed vazio = A) de "filtros
  // restritivos" (0 = B). -1 = desconhecido (caminho RPC ainda não fornece).
  int _totalMatchingCatalog = -1;

  // ── FASE 2 (T2.2): feed server-side atrás de feed_list_v1 ───────────
  // Com a flag ON, AMBOS os modos consomem o RPC get_feed_page (D-6):
  // lista = scroll infinito por cursor; swipe = snapshot imutável da
  // página corrente (_jobs vira A PÁGINA, e esgotá-la avança via
  // tryAutoReload + recriação do CardSwiper pela tela via feedEpoch).
  // Flag OFF = caminho legacy intocado (rollback).
  static const String feedModeSwipe = 'swipe';
  static const String feedModeList = 'list';

  FeedPager? _feedPager;
  bool _rpcSessionActive = false;
  String _feedModeRaw = feedModeSwipe;
  int _feedEpoch = 0;
  bool _isLoadingMore = false;
  bool _exhaustedEmittedRpc = false;
  final Map<String, FeedPageRow> _feedRows = {};

  bool get feedRpcEnabled => FeatureFlagsService.instance
      .isEnabledForUser(FeatureFlagKeys.feedListV1, userId);

  /// Modo persistido do feed; só vale com a flag ON (OFF = sempre swipe).
  String get feedMode => feedRpcEnabled ? _feedModeRaw : feedModeSwipe;

  /// (REV-1) 'rpc'|'legacy' — prop do feed_loaded; é o corte do aceite P50.
  String get feedSource => _rpcSessionActive ? 'rpc' : 'legacy';

  /// Incrementa a cada SUBSTITUIÇÃO de _jobs no caminho RPC — a tela usa
  /// como Key do CardSwiper (recriar swiper = índice interno zera junto
  /// com o array novo; resolve B4 sem refatorar o plugin).
  int get feedEpoch => _feedEpoch;
  bool get isLoadingMore => _isLoadingMore;

  /// Row do RPC (score server + razões) da vaga — chips da célula da lista.
  FeedPageRow? feedRowFor(String jobId) => _feedRows[jobId];

  /// Vagas visíveis no modo lista (exclui as já swipadas na sessão — a
  /// lista PODE remover células; a restrição de array imutável é do
  /// CardSwiper, não daqui).
  List<Job> get listJobs =>
      _jobs.where((j) => !_swipedIds.contains(j.id)).toList();

  // Stack of swiped jobs (mais recente no fim) pra suportar undo
  final List<Job> _undoStack = [];

  // Liked jobs (aba "Curtidas") — populado on-demand
  List<LikedJob> _likedJobs = [];
  bool _likedJobsLoading = false;

  // Getters
  List<Job> get jobs => _jobs;
  Set<String> get swipedIds => _swipedIds;
  int get remainingCount => _jobs.length - _swipedIds.length;

  /// Filtros TEMPORÁRIOS de feed (vivem em SharedPreferences local após
  /// Passo 3 do plano match-score, 2026-05-27). Mexer aqui só altera o
  /// que aparece no feed — NÃO afeta o match score. Pra identidade que
  /// alimenta o match, ver [profilePrefs].
  UserJobPreferences? get preferences => _preferences;

  /// Preferências de IDENTIDADE lidas das tabelas relacionais
  /// (`profile_job_preferences`, `profile_desired_titles`,
  /// `profile_other_locations`). Alimenta o MatchScoreCalculator no
  /// fallback determinístico. Carregado por [_loadProfilePrefs] e
  /// cacheado por sessão (invalida em `ProfileEvents.changes`).
  UserJobPreferences? get profilePrefs => _cachedProfilePrefs;
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

  // ── Invalidação de match cache em mudança de preferências ──────────
  /// Contador monotônico bumpado em `savePreferences`/`clearPreferences`.
  /// JobsSwipeScreen compara com `_lastPrefsVersion` no build pra detectar
  /// mudança e limpar o `_matchCache` em memória — sem isso, scores
  /// computados com prefs antigas continuariam aparecendo nos cards
  /// (cache de servidor invalida via profile_hash, mas o de memória não).
  int _prefsVersion = 0;
  int get prefsVersion => _prefsVersion;

  // ── Pending adapt sheet (cross-tab handoff do banner do Home) ───────
  /// JobId que o banner do Home pediu pra abrir o sheet de adaptação.
  /// JobsSwipeScreen observa, abre a sheet (fetchando o job se preciso) e
  /// chama [consumePendingAdaptSheet] pra limpar.
  ///
  /// Sem isso, tocar "Abrir" no banner só navega pra aba Vagas e o user
  /// precisa caçar a vaga manualmente — quebra a promessa do banner.
  String? _pendingAdaptSheetJobId;
  String? get pendingAdaptSheetJobId => _pendingAdaptSheetJobId;

  void requestOpenAdaptSheet(String jobId) {
    if (_pendingAdaptSheetJobId == jobId) return;
    _pendingAdaptSheetJobId = jobId;
    notifyListeners();
  }

  void consumePendingAdaptSheet() {
    if (_pendingAdaptSheetJobId == null) return;
    _pendingAdaptSheetJobId = null;
    // Sem notifyListeners — quem consome já está reagindo a notify anterior;
    // notificar de novo causaria rebuild redundante.
  }

  /// Busca um Job direto do repo (não usa cache do _jobs). Necessário pra
  /// quando o banner do Home pede pra abrir a sheet de uma vaga que já foi
  /// swiped (saiu do feed).
  Future<Job?> fetchJobById(String id) => _jobRepository.getJobById(id);

  /// Verdadeiro quando os filtros do user NÃO batem com NENHUMA vaga do
  /// catálogo (B), não quando ele apenas esgotou as relevantes swipando todas
  /// (A). Usa [totalMatchingCatalog] (matches ignorando swipe) — antes usava
  /// `_totalAfterFilters == 0`, que virava 0 depois de swipar tudo e flipava
  /// pra B errado (bug 15/06).
  bool get filtersAreTooRestrictive => feedFiltersTooRestrictive(
        prefsActive: _preferences != null && !_preferences!.isEmpty,
        totalAvailable: _totalAvailable,
        totalMatchingCatalog: _totalMatchingCatalog,
      );

  String? get userId => Supabase.instance.client.auth.currentUser?.id;

  /// Aguarda o auth ficar pronto com short-poll. Retorna o user_id se aparecer
  /// dentro do timeout, null caso contrário. Usado pra mitigar a race entre o
  /// widget montar e a sessão Supabase restaurar do storage local (cold start
  /// do app pode levar 100-500ms).
  Future<String?> _awaitUserId({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final id = userId;
    if (id != null) return id;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final retry = userId;
      if (retry != null) return retry;
    }
    return null;
  }

  /// Initialize: load preferences then jobs.
  ///
  /// Idempotente: chamadas subsequentes não fazem nada se já carregou.
  /// O repo embaralha a lista a cada fetch (linha 111 de job_repository),
  /// então reentrar nesse fluxo sem necessidade trocaria a ordem dos
  /// cards visíveis pro user — efeito ruim ao voltar pra aba Vagas.
  /// Use [forceRefresh] ou [reloadJobs] quando quiser re-fetch explícito.
  Future<void> init({bool forceRefresh = false}) async {
    if (_isLoading) return;
    if (!forceRefresh && _jobs.isNotEmpty) {
      // Cache hit — emite feed_loaded com cache_hit=true pra dashboard
      // distinguir loads "frios" (rede) de "warm" (memória).
      Analytics.shared.feedLoaded(
        subTab: 'para_voce',
        jobsCount: _jobs.length,
        cacheHit: true,
        feedSource: feedSource,
        feedMode: feedMode,
      );
      return; // no-op: já inicializado, mantém ordem atual dos cards
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final loadStartedAt = DateTime.now();

    try {
      // Espera o auth ficar pronto se ainda não estiver (race condition no
      // cold start). Sem isso, init() rodando antes da sessão restaurar
      // travava o feed até hot-restart.
      final id = await _awaitUserId();
      if (id == null) {
        // Realmente sem user — provavelmente deslogou. UI mostra estado vazio.
        return;
      }
      // FASE 2 (T2.2): modo persistido (swipe|lista) — só relevante com a
      // flag ON, mas a leitura é barata e failure-safe.
      await _loadFeedMode(id);
      await _performFetch();
      // B.17 do plano v2 — feed_loaded com duration_ms + cache_hit=false
      // (foi pra rede). Sinal-âncora pra "tempo de feed pronto".
      // (REV-1) feed_source corta o aceite P50 da Fase 2 por rota.
      Analytics.shared.feedLoaded(
        subTab: 'para_voce',
        jobsCount: _jobs.length,
        loadDurationMs: DateTime.now().difference(loadStartedAt).inMilliseconds,
        cacheHit: false,
        feedSource: feedSource,
        feedMode: feedMode,
      );
    } catch (e) {
      _errorMessage = 'Erro ao carregar vagas. Tente novamente.';
      print('Error initializing jobs: $e');
      Analytics.shared.feedLoadFailed(
        subTab: 'para_voce',
        errorCode: e.runtimeType.toString(),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _performFetch() async {
    // FASE 2 (T2.2): com feed_list_v1 ON o feed vem do RPC get_feed_page.
    // O caminho legacy abaixo segue INTOCADO — rollback = flag OFF.
    if (feedRpcEnabled) {
      await _performRpcFetch();
      return;
    }
    _rpcSessionActive = false;
    // 1) Carrega FILTROS temporários do feed (local). Se não existem
    //    (null), default = identidade do Perfil (tabelas relacionais), pra
    //    que o user na 1ª abertura veja feed filtrado por área/cidade
    //    declaradas. User pode mexer nos filtros depois sem afetar o Perfil.
    //
    //    NOTA: NÃO usar `isEmpty` no check — quando o user limpa explicitamente,
    //    _loadLocalFilters retorna um UserJobPreferences vazio (não null) pra
    //    sinalizar "limpou de propósito". Usar `isEmpty` aqui faria o fallback
    //    ao Perfil voltar, anulando o efeito do "Limpar filtros".
    final uid = userId!;
    _preferences = await _loadLocalFilters(uid);
    if (_preferences == null) {
      _preferences = await _loadProfilePrefs();
    } else {
      // Pré-carrega profilePrefs em paralelo (match score precisa).
      // ignore: unawaited_futures
      _loadProfilePrefs();
    }

    // Then load jobs with those preferences (filters de atributos: área,
    // localização, modelo, tipo, salário — feitos no SQL/repo)
    _currentPage = 0;
    final result = await _jobRepository.fetchJobsWithDiagnostics(
      preferences: _preferences,
      page: _currentPage,
    );
    var jobs = result.jobs;
    _totalAvailable = result.totalAvailable;
    _totalMatchingCatalog = result.totalMatchingCatalog;

    // Filtro adicional: match score mínimo. Aplicado client-side porque
    // score depende do PAR (user, vaga) e não está na linha de `jobs`.
    // Combina cache de match_analyses (IA, preciso) + fallback determinístico
    // — sem custo de IA extra. Aplicado SOMENTE quando o user setou um
    // mínimo explícito; sem isso, deixamos tudo passar.
    final minScore = _preferences?.minMatchScore;
    if (minScore != null && minScore > 0 && jobs.isNotEmpty) {
      jobs = await _filterByMatchScore(jobs, minScore);
    }

    _jobs = jobs;
    _totalAfterFilters = jobs.length;
    // Único page request hoje retorna até o cap do JobRepository. Sinaliza
    // pra UI se atingiu o cap (improvável na prática).
    _hasMorePages = _jobs.length >= 5000;
  }

  // ──────────────────────────────────────────────────────────────────
  // FASE 2 (T2.2): fetch via RPC get_feed_page (flag feed_list_v1 ON)
  // ──────────────────────────────────────────────────────────────────

  /// Reinicia a sessão de paginação e busca a 1ª página. A resolução de
  /// filtros é o ESPELHO do caminho legacy (filtros locais SE existem,
  /// senão prefs do Perfil — D-8); o RPC recebe os filtros como args e lê
  /// as prefs de RANKING server-side via auth.uid().
  Future<void> _performRpcFetch() async {
    final uid = userId!;
    _preferences = await _loadLocalFilters(uid);
    if (_preferences == null) {
      _preferences = await _loadProfilePrefs();
    } else {
      // Pré-carrega profilePrefs em paralelo (match score precisa).
      // ignore: unawaited_futures
      _loadProfilePrefs();
    }

    _feedPager = FeedPager(_jobRepository.callFeedPageRpc);
    _feedRows.clear();
    _exhaustedEmittedRpc = false;
    _rpcSessionActive = true;
    _currentPage = 0;

    await _fetchRpcPage(replaceJobs: true);
  }

  /// Busca UMA página do RPC e hidrata as vagas. [replaceJobs] substitui
  /// `_jobs` (snapshot do swipe / 1ª página) — e bumpa [feedEpoch] pra
  /// tela recriar o CardSwiper; `false` = appenda (scroll da lista).
  ///
  /// `min_match_score` continua client-side por página (D-8: depende do
  /// par user×vaga + cache match_analyses) — página pode encolher; se
  /// encolher a ZERO com mais páginas no servidor, busca a próxima
  /// (guard de 5 tentativas pra não varrer o catálogo num gesto só).
  Future<void> _fetchRpcPage({required bool replaceJobs}) async {
    final pager = _feedPager;
    if (pager == null) return;

    final prefs = _preferences;
    final minScore = prefs?.minMatchScore;
    var pageJobs = <Job>[];
    var attempts = 0;

    while (true) {
      attempts++;
      final rows = await pager.fetchNext(
        areas: prefs?.areas,
        locations: prefs?.locations,
        workModels: prefs?.workModels,
        jobTypes: prefs?.jobTypes,
      );
      for (final row in rows) {
        _feedRows[row.jobId] = row;
      }

      var jobs = await _jobRepository
          .fetchJobsByIds([for (final r in rows) r.jobId]);
      if (minScore != null && minScore > 0 && jobs.isNotEmpty) {
        jobs = await _filterByMatchScore(jobs, minScore);
      }
      pageJobs = jobs;
      if (pageJobs.isNotEmpty || !pager.hasMore || attempts >= 5) break;
    }

    if (replaceJobs) {
      _jobs = pageJobs;
      _feedEpoch++;
    } else {
      _jobs = [..._jobs, ...pageJobs];
    }
    // Diagnóstico pros empty states: totais da 1ª página do RPC.
    // get_feed_page v1.3 (#5) retorna total_matching_catalog (matches
    // ignorando swipe) → distingue "esgotou" (>0 → A) de "filtros
    // restritivos" (0 → B), igual ao legacy. Null (página > 1ª) preserva
    // o valor já lido; -1 só se a 1ª página não trouxe (RPC antigo).
    _totalAfterFilters = pager.totalAfterFilters ?? _totalAfterFilters;
    _totalAvailable = pager.totalAvailable ?? _totalAvailable;
    _totalMatchingCatalog = pager.totalMatchingCatalog ?? _totalMatchingCatalog;
    _hasMorePages = pager.hasMore;
  }

  /// Scroll infinito do modo lista: appenda a próxima página.
  Future<void> loadMoreFeedPage() async {
    if (!feedRpcEnabled || !_rpcSessionActive) return;
    if (_isLoading || _isLoadingMore) return;
    if (!(_feedPager?.hasMore ?? false)) {
      _emitRpcExhaustedOnce();
      return;
    }
    _isLoadingMore = true;
    notifyListeners();
    try {
      await _fetchRpcPage(replaceJobs: false);
      if (!(_feedPager?.hasMore ?? false)) _emitRpcExhaustedOnce();
    } catch (e) {
      print('loadMoreFeedPage failed: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// `feed_exhausted` 1x por sessão de paginação RPC (aceite #6: exaustão
  /// medida por feed_mode).
  void _emitRpcExhaustedOnce() {
    if (_exhaustedEmittedRpc) return;
    _exhaustedEmittedRpc = true;
    // ignore: unawaited_futures
    Analytics.shared.feedExhausted(
      subTab: 'para_voce',
      jobsSeenInSession: _jobs.length,
      jobsSwipedInSession: _swipedIds.length,
      feedMode: feedMode,
    );
  }

  /// FASE 2 (T2.2): swipe a partir da CÉLULA da lista (sem CardSwiper /
  /// índice). MESMA semântica otimista de [onSwipe] — mantido separado de
  /// propósito pra não tocar o caminho do swiper (mudou lá → muda aqui).
  /// Devolve `true` se o swipe PERSISTIU (ou já estava swipado). `false` só
  /// quando o `recordSwipe` falhou e o estado otimista foi revertido — o
  /// assistente usa isso pra não dizer "salva" em cima de um erro. (Não dá pra
  /// checar `likedJobs.any(...)`: o `loadLikedJobs` roda sem await e a lista só
  /// atualiza depois — daria falso-negativo em toda vaga salva pelo card.)
  Future<bool> swipeJobFromList(Job job, String action) async {
    if (userId == null) return false;
    final already = _swipedIds.contains(job.id);
    // Dedup só corta caminho pra NÃO-'liked'. Um 'liked' precisa SEMPRE rodar o
    // recordSwipe (upsert onConflict user_id,job_id) — senão o assistente
    // dizia "salva" pra uma vaga que o user DESCARTOU antes (disliked também
    // entra em _swipedIds); agora o upsert converte disliked→liked de fato.
    if (action != 'liked' && already) return true;

    if (!already) {
      _swipedIds.add(job.id);
      _undoStack.add(job);
      notifyListeners();
    }

    try {
      await _swipeRepository.recordSwipe(userId!, job.id, action);
      if (action == 'liked') {
        loadLikedJobs(silent: true);
        if (job.applicationMethod == 'email') {
          unawaited(_notifyAutoApplySwipe(job));
        }
      }
      return true;
    } catch (e) {
      // Rollback otimista (espelho de onSwipe) — só reverte o que ESTA chamada
      // empilhou (não mexe num swipe anterior que já estava lá).
      print('Error recording swipe (list): $e');
      if (!already) {
        _swipedIds.remove(job.id);
        _undoStack.remove(job);
        notifyListeners();
      }
      return false;
    }
  }

  // ── FASE 2 (T2.4): holdout match_score_visibility_v1 (§5/D3) ────────
  // Resolvido 1× por sessão, APÓS profilePrefs carregar (a elegibilidade
  // é a MESMA confidence que decide se o número aparece hoje). Cacheado
  // pra não dar flicker por card; reset no signOut.
  String? _holdoutVariant;
  bool _holdoutResolved = false;

  /// 'percent' | 'hidden' | null (null = não-elegível, confidence low).
  String? get holdoutVariant => _holdoutVariant;

  /// O que o user vê pré-swipe (banda + chips). True até o holdout
  /// resolver (failure-safe = controle) e pra não-elegíveis.
  bool get matchScoreVisible =>
      !_holdoutResolved || scoreVisibleFor(_holdoutVariant);

  Future<void> resolveMatchScoreHoldout() async {
    if (_holdoutResolved) return;
    await ensureProfilePrefsLoaded();
    final confidence = MatchScoreCalculator.computeConfidence(
      prefs: _cachedProfilePrefs,
      skillsCount: _cachedProfileSkillsCount,
    ).level;
    _holdoutVariant = await resolveHoldoutVariant(
      confidence: confidence,
      getFlag: (key) => Analytics.shared.getFlag(key),
    );
    _holdoutResolved = true;
    notifyListeners();
  }

  // ── FASE 2 (T2.3): exaustão honesta + pedido de empresa ─────────────

  /// Expansão honesta do estado A: se o filtro de MODELO exclui remotas,
  /// 1 toque as inclui. (Se workModels está vazio, remotas JÁ passam —
  /// oferecer "incluir remotas" seria expansão de mentira.)
  bool get canExpandToRemote {
    final p = _preferences;
    return p != null &&
        p.workModels.isNotEmpty &&
        !p.workModels.contains('remoto');
  }

  Future<void> expandFiltersWithRemote() async {
    final p = _preferences;
    if (p == null || !canExpandToRemote) return;
    await savePreferences(
      p.copyWith(workModels: [...p.workModels, 'remoto']),
    );
  }

  /// Insere o pedido em `company_requests` (RLS own-insert) + evento R7.
  /// Retorna false em falha — a UI mostra erro e mantém o sheet aberto.
  Future<bool> submitCompanyRequest(String companyName, String? note) async {
    final uid = userId;
    final name = companyName.trim();
    if (uid == null || name.isEmpty) return false;
    try {
      await Supabase.instance.client.from('company_requests').insert({
        'user_id': uid,
        'company_name': name,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
      // ignore: unawaited_futures
      Analytics.shared.companyRequested(
        companyName: name,
        hasNote: note != null && note.trim().isNotEmpty,
        feedMode: feedMode,
      );
      return true;
    } catch (e) {
      print('submitCompanyRequest failed: $e');
      return false;
    }
  }

  // ── Modo do feed (swipe|lista), persistido por user ─────────────────
  static String _feedModeKey(String userId) => 'feed_mode_$userId';

  Future<void> _loadFeedMode(String uid) async {
    try {
      final sp = await SharedPreferences.getInstance();
      _feedModeRaw = sp.getString(_feedModeKey(uid)) ?? feedModeSwipe;
    } catch (_) {
      _feedModeRaw = feedModeSwipe; // failure-safe: padrão do fundador
    }
  }

  /// Toggle swipe↔lista (D-6: swipe é padrão, lista é opt-in). Persiste a
  /// escolha e reinicia a sessão de paginação no modo novo.
  Future<void> setFeedMode(String mode) async {
    if (mode != feedModeSwipe && mode != feedModeList) return;
    if (mode == _feedModeRaw) return;
    _feedModeRaw = mode;
    notifyListeners();
    // ignore: unawaited_futures
    Analytics.shared.feedModeToggled(mode: mode);
    final uid = userId;
    if (uid != null) {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_feedModeKey(uid), mode);
      } catch (e) {
        print('saveFeedMode failed: $e');
      }
    }
    await reloadJobs();
  }

  /// Aplica filtro de score mínimo in-memory.
  /// 1. Busca scores cacheados em batch (1 SQL select).
  /// 2. Busca `gamification_data` + snapshot das tabelas `profile_*` em
  ///    paralelo — assim o fallback determinístico seja IDÊNTICO ao
  ///    mostrado no card. Sem isso, o filtro divergia da UI (filtro dizia
  ///    75, card mostrava 30) e deixava passar vagas baixas.
  /// 3. Pra vagas sem cache IA, usa fallback determinístico com mesmo input
  ///    que o card calcula.
  /// 4. Retorna só vagas com score >= [minScore].
  ///
  /// Falha graciosa: se algo der errado, deixa todas as vagas passar (em vez
  /// de zerar feed).
  Future<List<Job>> _filterByMatchScore(List<Job> jobs, int minScore) async {
    final ids = jobs.map((j) => j.id).toList();

    // Pega cache de match (IA preciso) + gamification_data + pseudo-texto
    // das tabelas profile_* + identidade do Perfil em paralelo.
    Map<String, MatchResult> cached = const {};
    Map<String, dynamic>? gamificationData;
    String? profileText;
    UserJobPreferences? profilePrefs;
    try {
      final cachedFuture = _aiService.fetchCachedMatches(ids);
      final gamifFuture = _fetchGamificationData();
      final profileFuture = _fetchProfileText();
      final profilePrefsFuture = _loadProfilePrefs();
      cached = await cachedFuture;
      gamificationData = await gamifFuture;
      profileText = await profileFuture;
      profilePrefs = await profilePrefsFuture;
    } catch (e) {
      print('Match score filter: failed to load context, allowing all: $e');
      return jobs; // falha graciosa — não zera o feed
    }

    return jobs.where((job) {
      final aiScore = cached[job.id]?.score;
      if (aiScore != null && aiScore > 0) {
        return aiScore >= minScore;
      }
      // Fallback determinístico — usa identidade do Perfil (NÃO os filtros
      // temporários), pra que o filtro min_match_score concorde com o
      // score mostrado no card. Pós Passo 3 (2026-05-27), o card também
      // lê de profilePrefs (vide jobs_swipe_screen.dart).
      final fallback = MatchScoreCalculator.calculate(
        job: job,
        prefs: profilePrefs,
        gamificationData: gamificationData,
        profileText: profileText,
      );
      return fallback.score >= minScore;
    }).toList();
  }

  /// Lê `gamification_data` do user_profiles. Usado pra alinhar o fallback
  /// determinístico de match score com o que o card mostra (skills da trilha
  /// — `whoIAm.derived` — afetam o score). Cacheia em memória durante a
  /// sessão pra evitar refetch a cada filtro.
  Map<String, dynamic>? _cachedGamificationData;
  bool _gamificationDataLoaded = false;
  Future<Map<String, dynamic>?> _fetchGamificationData() async {
    if (_gamificationDataLoaded) return _cachedGamificationData;
    try {
      final row = await Supabase.instance.client
          .from('user_profiles')
          .select('gamification_data')
          .eq('id', userId!)
          .maybeSingle();
      _cachedGamificationData =
          row?['gamification_data'] as Map<String, dynamic>?;
    } catch (e) {
      print('fetchGamificationData failed: $e');
      _cachedGamificationData = null;
    } finally {
      _gamificationDataLoaded = true;
    }
    return _cachedGamificationData;
  }

  /// Reação a `ProfileEvents.changes`: recarrega `profilePrefs` (que acabou
  /// de ser invalidado pelo listener) e re-aplica filtros do feed se o user
  /// ainda não setou filtros locais. Cobre o cenário "user terminou
  /// onboarding e foi pra aba Vagas" — sem isso, o feed continuaria sem
  /// filtros até hot-restart.
  Future<void> _onProfileChanged() async {
    try {
      await _loadProfilePrefs();
      final uid = userId;
      if (uid == null) {
        notifyListeners();
        return;
      }
      // Se filtros locais ainda não existem, re-roda _performFetch pra
      // aplicar as prefs novas como default no feed. Guard `!_isLoading`
      // evita concorrer com init() já em curso.
      final localFilters = await _loadLocalFilters(uid);
      if ((localFilters == null || localFilters.isEmpty) && !_isLoading) {
        _isLoading = true;
        notifyListeners();
        try {
          await _performFetch();
        } finally {
          _isLoading = false;
          notifyListeners();
        }
      } else {
        // Filtros locais já existem — só notifica pra que widgets de match
        // re-busquem o profilePrefs atualizado.
        notifyListeners();
      }
    } catch (e) {
      // Não-fatal — user pode dar pull-to-refresh manual ou voltar à tab.
      print('onProfileChanged failed: $e');
    }
  }

  /// Preferências de IDENTIDADE do user (área, cidade, modelo, tipo) lidas
  /// diretamente das tabelas relacionais `profile_job_preferences`,
  /// `profile_desired_titles`, `profile_other_locations`. Usada pra alimentar
  /// o MatchScoreCalculator no fallback determinístico — separadas dos
  /// filtros temporários de feed (`_preferences`). Cacheado por sessão;
  /// invalida em [ProfileEvents.changes] e [signOut].
  UserJobPreferences? _cachedProfilePrefs;
  bool _profilePrefsLoaded = false;

  /// Contagem de skills do user em `profile_skills`. Carregada junto com
  /// profilePrefs (1 query extra). Usada pelo Passo 5 (confidence) — skills
  /// só "conta como dimensão preenchida" se >= 3 (1 ou 2 skills isoladas
  /// ainda deixam keyword overlap muito ruidoso pra ser sinal).
  int _cachedProfileSkillsCount = 0;
  int get profileSkillsCount => _cachedProfileSkillsCount;

  // ── FASE 2 fixes (#3): cache de RESULTADOS de match compartilhado ────
  // O mapa de resultados (jobId→MatchResult RAW, sem confidence) vive aqui
  // pra que TODAS as superfícies — card do swipe, célula da lista e o
  // DETALHE (aberto de qualquer ponto) — reusem o MESMO valor. Antes só o
  // swipe tinha cache local e o detalhe da lista/salvas abria sem match
  // (mostrava 0%). A sliding-window/prefetch e o _matchInflight FICAM
  // locais no JobsSwipeScreen — aqui mora SÓ o resultado. Invalida em
  // ProfileEvents.changes e signOut (prefs velhas = score velho).
  final Map<String, MatchResult> _matchResultCache = {};

  /// Mapa de resultados compartilhado (RAW, sem confidence). O swipe lê/grava
  /// direto aqui pra que o detalhe reuse o que o swipe já avaliou (e vice-versa).
  Map<String, MatchResult> get matchResultCache => _matchResultCache;

  /// Lê o resultado RAW cacheado (ou null). Confidence é aplicado no momento
  /// da leitura pelo caller (espelho de _resolveMatch do swipe).
  MatchResult? cachedMatch(String jobId) => _matchResultCache[jobId];

  /// Grava o resultado RAW no cache compartilhado.
  void cacheMatch(String jobId, MatchResult result) {
    _matchResultCache[jobId] = result;
  }

  /// Garante que `profilePrefs` está carregado do banco antes do caller
  /// chamar `MatchScoreCalculator.calculate` (que precisa de prefs sync via
  /// [profilePrefs] getter). Sem isso, há race condition após
  /// `ProfileEvents.changes`: cache é invalidado mas o caller pode ler
  /// `profilePrefs` antes do reload terminar → null → calculator retorna
  /// `MatchResult.unknown` e a vaga fica "travada" como sem perfil.
  ///
  /// Idempotente. Após retornar, [profilePrefs] está populado (ou null
  /// confirmado, se user de fato não tem nenhuma pref no relacional).
  Future<void> ensureProfilePrefsLoaded() => _loadProfilePrefs();
  Future<UserJobPreferences?> _loadProfilePrefs() async {
    if (_profilePrefsLoaded) return _cachedProfilePrefs;
    try {
      final uid = userId;
      if (uid == null) {
        _cachedProfilePrefs = null;
        _cachedProfileSkillsCount = 0;
      } else {
        final client = Supabase.instance.client;
        // Future.wait não infere tipo comum entre maybeSingle (Map?) e
        // select (List<Map>) — explicitamos `dynamic` e fazemos cast depois.
        final results = await Future.wait<dynamic>([
          client
              .from('profile_job_preferences')
              .select('*')
              .eq('user_id', uid)
              .maybeSingle(),
          client
              .from('profile_desired_titles')
              .select('title')
              .eq('user_id', uid),
          client
              .from('profile_other_locations')
              .select('city')
              .eq('user_id', uid),
          client.from('profile_skills').select('canonical_skill_id, name').eq('user_id', uid),
        ]);

        final jp = results[0] as Map<String, dynamic>?;
        final dtList = (results[1] as List).cast<dynamic>();
        final olList = (results[2] as List).cast<dynamic>();
        // Conta skills DISTINTAS por canônica (taxonomia P5): 3 grafias da
        // mesma skill = 1, não 3 — fragmentação para de inflar a confiança.
        // Sem canônica (cauda), cai no nome normalizado.
        final distinctSkills = <String>{};
        for (final row in (results[3] as List)) {
          final m = row as Map;
          final canon = m['canonical_skill_id']?.toString();
          final name = (m['name']?.toString() ?? '').trim().toLowerCase();
          if (canon != null && canon.isNotEmpty) {
            distinctSkills.add('c:$canon');
          } else if (name.isNotEmpty) {
            distinctSkills.add('n:$name');
          }
        }
        _cachedProfileSkillsCount = distinctSkills.length;

        final areas = dtList
            .map((row) => (row as Map)['title']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();

        final locations = <String>[];
        final primaryCity = jp?['primary_location_city']?.toString();
        if (primaryCity != null && primaryCity.isNotEmpty) {
          locations.add(primaryCity);
        }
        for (final loc in olList) {
          final c = (loc as Map)['city']?.toString();
          if (c != null && c.isNotEmpty) locations.add(c);
        }

        // Normaliza work_mode EN (relacional) → PT (formato que o
        // MatchScoreCalculator e job.workModelRaw usam).
        final workModesRaw = (jp?['work_mode'] as List?)?.cast<dynamic>() ?? [];
        final workModes = workModesRaw.map((wm) {
          final s = wm.toString();
          switch (s) {
            case 'remote':
              return 'remoto';
            case 'hybrid':
              return 'hibrido';
            case 'in_person':
              return 'presencial';
            default:
              return s; // já em PT ou desconhecido
          }
        }).toList();

        final jobTypes =
            (jp?['job_types'] as List?)
                ?.cast<dynamic>()
                .map((e) => e.toString())
                .toList() ??
            <String>[];

        // Cargo desejado: bônus no match (não cria prefs sozinho — só refina
        // quando já há dimensão de peso declarada).
        final desiredPosition =
            (jp?['desired_position']?.toString().trim().isNotEmpty ?? false)
                ? jp!['desired_position'].toString().trim()
                : null;

        if (areas.isEmpty &&
            locations.isEmpty &&
            workModes.isEmpty &&
            jobTypes.isEmpty) {
          _cachedProfilePrefs = null;
        } else {
          _cachedProfilePrefs = UserJobPreferences(
            userId: uid,
            areas: areas,
            locations: locations,
            workModels: workModes,
            jobTypes: jobTypes,
            desiredPosition: desiredPosition,
          );
        }
      }
    } catch (e) {
      print('loadProfilePrefs failed: $e');
      _cachedProfilePrefs = null;
    } finally {
      _profilePrefsLoaded = true;
    }
    return _cachedProfilePrefs;
  }

  /// FASE 2 fixes (#3): resolve o match de UMA vaga pro detalhe, em QUALQUER
  /// ponto de entrada (lista/salvas não passavam match → detalhe mostrava 0%).
  /// Reusa o cache compartilhado [_matchResultCache] (preenchido pelo swipe) e,
  /// só se necessário, o cache de IA em `match_analyses`; senão o determinístico
  /// — MESMO padrão de [_filterByMatchScore], MESMA precedência de [_resolveMatch]
  /// do swipe (noResume → cache → IA/determinístico).
  ///
  /// Precedência (sem N round-trips ao banco):
  ///   1. [cachedMatch] em memória → retorna na hora (card já visto no swipe,
  ///      ou 2ª abertura da mesma vaga).
  ///   2. `fetchCachedMatches` (1 SELECT) → se houver row de IA, cacheia e usa.
  ///   3. `MatchScoreCalculator.calculate` determinístico → cacheia e usa.
  ///
  /// [hasResume] vem do caller (UserViewModel.hasResume) — sem CV/trilha, mostrar
  /// % é mentira (Cenário C devolve 50 fixo), então retorna noResume (UI → CTA).
  /// Confidence é aplicado no retorno (resultado cacheado fica RAW).
  Future<MatchResult> resolveMatchForJob(
    Job job, {
    required bool hasResume,
  }) async {
    if (!hasResume) return const MatchResult.noResume();

    await ensureProfilePrefsLoaded();
    final conf = MatchScoreCalculator.computeConfidence(
      prefs: _cachedProfilePrefs,
      skillsCount: _cachedProfileSkillsCount,
    );

    // 1. Cache em memória compartilhado (swipe já avaliou, ou reabertura).
    final cached = _matchResultCache[job.id];
    if (cached != null) {
      return cached.withConfidence(conf.level, conf.missing);
    }

    // 2. Cache de IA em match_analyses (preciso). 1 SELECT, cacheado depois.
    try {
      final ai = (await _aiService.fetchCachedMatches([job.id]))[job.id];
      if (ai != null) {
        cacheMatch(job.id, ai);
        return ai.withConfidence(conf.level, conf.missing);
      }
    } catch (e) {
      print('resolveMatchForJob: fetchCachedMatches falhou, cai p/ determinístico: $e');
    }

    // 3. Fallback determinístico — mesmo input que o card/filtro usam.
    final gamificationData = await _fetchGamificationData();
    final profileText = await _fetchProfileText();
    final determ = MatchScoreCalculator.calculate(
      job: job,
      prefs: _cachedProfilePrefs,
      gamificationData: gamificationData,
      profileText: profileText,
    );
    cacheMatch(job.id, determ);
    return determ.withConfidence(conf.level, conf.missing);
  }

  // ── Filtros temporários de feed: persistência local ─────────────────
  // Após Passo 3 do plano match-score (2026-05-27), filtros viram TEMPORÁRIOS:
  // - Vivem em SharedPreferences local (key: 'job_filters_<userId>').
  // - Não escrevem mais em user_preferences (Supabase) via PreferencesRepository.
  // - Não afetam match score (que lê de [profilePrefs] = tabelas relacionais).
  // - Default ao abrir pela 1ª vez: cópia das prefs do Perfil (vide _performFetch).
  // - Quando o user limpa explicitamente, seta `_filtersClearedKey` pra que
  //   o fallback ao Perfil NÃO entre — senão "limpar" não tem efeito.
  static String _filtersKey(String userId) => 'job_filters_$userId';
  static String _filtersClearedKey(String userId) =>
      'job_filters_cleared_$userId';

  Future<UserJobPreferences?> _loadLocalFilters(String uid) async {
    try {
      final sp = await SharedPreferences.getInstance();
      // Marcador "user limpou explicitamente" — retorna prefs vazias (não
      // null) pra evitar fallback ao Perfil em _performFetch/loadPreferences.
      if (sp.getBool(_filtersClearedKey(uid)) == true) {
        return UserJobPreferences(userId: uid);
      }
      final raw = sp.getString(_filtersKey(uid));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      // user_id é obrigatório no factory — fallback pro uid atual.
      map['user_id'] = uid;
      return UserJobPreferences.fromJson(map);
    } catch (e) {
      print('loadLocalFilters failed: $e');
      return null;
    }
  }

  Future<void> _saveLocalFilters(String uid, UserJobPreferences prefs) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final json = jsonEncode(prefs.toJson());
      await sp.setString(_filtersKey(uid), json);
      // Salvar filtros customizados anula o estado "explicitamente limpo".
      await sp.remove(_filtersClearedKey(uid));
    } catch (e) {
      print('saveLocalFilters failed: $e');
    }
  }

  Future<void> _clearLocalFilters(String uid) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_filtersKey(uid));
      // Marca que o user limpou DE PROPÓSITO. Sem isso, _performFetch
      // não sabe distinguir "nunca configurou" (deve fazer fallback) de
      // "limpou explicitamente" (não deve fazer fallback).
      await sp.setBool(_filtersClearedKey(uid), true);
    } catch (e) {
      print('clearLocalFilters failed: $e');
    }
  }

  /// Carrega o pseudo-texto agregado das tabelas `profile_*` pra alimentar
  /// o keyword overlap do match score. Substitui o legacy
  /// `imported_resume.raw_text`. Cacheado por sessão.
  String? _cachedProfileText;
  bool _profileTextLoaded = false;
  final ProfileSnapshotService _profileSnapshotService =
      ProfileSnapshotService();
  Future<String?> _fetchProfileText() async {
    if (_profileTextLoaded) return _cachedProfileText;
    try {
      final uid = userId;
      if (uid == null) {
        _cachedProfileText = null;
      } else {
        final snapshot = await _profileSnapshotService.loadSnapshot(uid);
        final text = snapshot.toPseudoText().trim();
        _cachedProfileText = text.isEmpty ? null : text;
      }
    } catch (e) {
      print('fetchProfileText failed: $e');
      _cachedProfileText = null;
    } finally {
      _profileTextLoaded = true;
    }
    return _cachedProfileText;
  }

  /// Reload jobs (e.g. after changing preferences).
  Future<void> reloadJobs() async {
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    _currentPage = 0;
    _undoStack.clear();
    _swipedIds.clear();
    _autoReloadAttempted = false;
    // Invalida cache de gamification_data + profile_* + profilePrefs — pode
    // ter mudado (user importou CV, completou trilha, editou perfil ou prefs
    // via tab Perfil) e isso afeta o fallback do score.
    _gamificationDataLoaded = false;
    _cachedGamificationData = null;
    _profileTextLoaded = false;
    _cachedProfileText = null;
    _profilePrefsLoaded = false;
    _cachedProfilePrefs = null;
    _cachedProfileSkillsCount = 0;
    notifyListeners();

    try {
      final id = await _awaitUserId();
      if (id == null) {
        _errorMessage = 'Sessão expirada. Faça login novamente.';
        return;
      }
      await _performFetch();
    } catch (e) {
      _errorMessage = 'Erro ao carregar vagas. Tente novamente.';
      print('Error reloading jobs: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Marcador pra UI: o auto-reload já foi tentado e ainda assim o feed
  /// está vazio. Sem isso, UI ficava em loop tentando recarregar.
  bool _autoReloadAttempted = false;
  bool get autoReloadAttempted => _autoReloadAttempted;

  /// Chamado pela UI quando o user esgota o feed (`remainingCount == 0`).
  /// Tenta recarregar UMA vez por sessão pra capturar vagas que entraram
  /// via sync recente. Se ainda assim vier vazio, marca o flag pra UI
  /// mostrar o estado "esgotou tudo".
  Future<void> tryAutoReload() async {
    // FASE 2 (T2.2): no caminho RPC, esgotar o snapshot do swipe avança
    // pra PRÓXIMA página (D-6) — _jobs é substituído e a tela recria o
    // CardSwiper via feedEpoch. Sem guard de 1x: cada snapshot esgotado
    // avança de novo. Exaustão REAL (sem próxima página) cai no fluxo
    // legacy abaixo, que emite feed_exhausted e tenta 1 reload por sessão
    // (reload com flag ON reinicia a sessão RPC — pega vagas novas do sync).
    if (feedRpcEnabled && _rpcSessionActive && (_feedPager?.hasMore ?? false)) {
      if (_isLoading) return;
      _isLoading = true;
      notifyListeners();
      try {
        _swipedIds.clear();
        _undoStack.clear();
        await _fetchRpcPage(replaceJobs: true);
      } catch (e) {
        print('RPC page advance failed: $e');
      } finally {
        _isLoading = false;
        notifyListeners();
      }
      return;
    }

    if (_autoReloadAttempted) return;
    if (_isLoading) return;
    _autoReloadAttempted = true;
    // B.17 — feed_exhausted emitido AQUI (ponto real de exaustão: a UI chama
    // tryAutoReload quando remainingCount==0). O emissor antigo na tela
    // (`_currentIndex >= jobs.length`) nunca era atingido — a tela trocava pro
    // empty-state antes —, então feed_exhausted ficava 0 all-time. O guard
    // `_autoReloadAttempted` garante 1x por sessão.
    // ignore: unawaited_futures
    Analytics.shared.feedExhausted(
      subTab: 'para_voce',
      jobsSeenInSession: _jobs.length,
      jobsSwipedInSession: _swipedIds.length,
      feedMode: feedMode,
    );
    notifyListeners(); // pra UI saber que tentamos (evita re-trigger)

    try {
      final id = await _awaitUserId();
      if (id == null) return; // sem user, não tem o que carregar
      await _performFetch();
    } catch (e) {
      print('Auto-reload failed: $e');
    } finally {
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
        if (job.applicationMethod == 'email') {
          unawaited(_notifyAutoApplySwipe(job));
        }
      }
    } catch (e) {
      // Rollback otimista
      print('Error recording swipe: $e');
      _swipedIds.remove(job.id);
      _undoStack.removeLast();
      notifyListeners();
    }
  }

  /// Notifica operação/founder quando um user autoriza candidatura automática
  /// em vaga por email. Best-effort: falha de ntfy não desfaz o swipe.
  Future<void> _notifyAutoApplySwipe(Job job) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke('notify-auto-apply-swipe', body: {'job_id': job.id})
          .timeout(const Duration(seconds: 10));
      if (response.status < 200 || response.status >= 300) {
        print(
          '[notify-auto-apply-swipe] status=${response.status} data=${response.data}',
        );
      }
    } catch (e) {
      print('[notify-auto-apply-swipe] failed: $e');
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

      // Analytics: feature de undo existe na UI mas estava invisível na
      // telemetria. Sem isso não dá pra decidir manter/remover o feature.
      // match_score/match_source não estão acessíveis aqui (o cache fica
      // no widget de swipe) — passar null é aceitável, o sinal mais importante
      // é a contagem do action='undo'.
      // ignore: unawaited_futures
      Analytics.shared.jobSwiped(
        jobId: undoneJobId,
        action: 'undo',
        matchScore: null,
      );
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

  /// Carrega filtros temporários do feed (SharedPreferences local).
  /// Fallback ao Perfil quando local está vazio (1ª abertura após instalar
  /// a build nova). Depois disso, filtros são independentes do Perfil.
  Future<void> loadPreferences() async {
    final uid = userId;
    if (uid == null) return;
    _isPreferencesLoading = true;
    notifyListeners();

    try {
      // Só fallback ao Perfil quando filtros NUNCA foram configurados (null).
      // Quando user limpou explicitamente, _loadLocalFilters retorna vazio
      // (não null) — respeitar a escolha do user.
      _preferences = await _loadLocalFilters(uid) ?? await _loadProfilePrefs();
    } catch (e) {
      print('Error loading preferences: $e');
    } finally {
      _isPreferencesLoading = false;
      notifyListeners();
    }
  }

  /// Salva filtros temporários em SharedPreferences local. NÃO escreve no
  /// Supabase — filtros não afetam mais a identidade do user (que mora nas
  /// tabelas relacionais). Recarrega o feed com os filtros novos aplicados.
  Future<void> savePreferences(UserJobPreferences prefs) async {
    final uid = userId;
    if (uid == null) return;

    try {
      await _saveLocalFilters(uid, prefs);
      _preferences = prefs;
      // Bumpa o version pra que JobsSwipeScreen invalide o _matchCache em
      // memória. NOTA pós Passo 3: hoje filtros não afetam mais o match
      // (que lê de profilePrefs), então essa invalidação é defensiva — o
      // match cache só deveria invalidar quando profilePrefs muda. Mas
      // bumpar aqui é barato e cobre edge cases enquanto o refator
      // termina.
      _prefsVersion++;
      await reloadJobs();
    } catch (e) {
      print('Error saving preferences: $e');
      rethrow;
    }
  }

  /// Limpa filtros temporários (remove do SharedPreferences local).
  /// O Perfil NÃO é afetado.
  Future<void> clearPreferences() async {
    final uid = userId;
    if (uid == null) return;
    await _clearLocalFilters(uid);
    _preferences = UserJobPreferences(userId: uid);
    _prefsVersion++;
    await reloadJobs();
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
      // Fase 1: a fonte de verdade do "apliquei" é `applications` — o
      // `applied` que veio do join com swipe_actions é legacy e é
      // SOBRESCRITO aqui pelo estado da application (countsAsApplied).
      final apps = await _applicationsRepository.fetchForUser(userId!);
      _applicationsByJob = {
        for (final a in apps)
          if (a.jobId != null) a.jobId!: a,
      };
      // T3.3: manuais (job_id null) vivem soltas na aba.
      _manualApplications = apps.where((a) => a.jobId == null).toList();
      _likedJobs = _likedJobs.map((l) {
        final app = _applicationsByJob[l.job.id];
        final isApplied = app != null && app.status.countsAsApplied;
        return LikedJob(
          swipeId: l.swipeId,
          job: l.job,
          applied: isApplied,
          appliedAt: isApplied ? app.createdAt : null,
          likedAt: l.likedAt,
        );
      }).toList();
    } catch (e) {
      print('Error loading liked jobs: $e');
    } finally {
      _likedJobsLoading = false;
      notifyListeners();
    }
  }

  /// Remove uma vaga das salvas. Otimista: tira da lista antes do DB.
  /// Retorna `true` se removeu com sucesso (UI usa pra mostrar snackbar
  /// de "Desfazer"). O caller é responsável por chamar [restoreLikedJob]
  /// caso o user toque "Desfazer".
  Future<bool> removeLikedJob(String jobId) async {
    if (userId == null) return false;

    final idx = _likedJobs.indexWhere((l) => l.job.id == jobId);
    if (idx == -1) return false;

    final removed = _likedJobs.removeAt(idx);
    // Solta o swipedId pra que a vaga possa voltar ao feed em próximo reload.
    _swipedIds.remove(jobId);
    notifyListeners();

    try {
      await _swipeRepository.removeLike(userId!, jobId);
      // ignore: unawaited_futures
      Analytics.shared.track(evJobUnsaved, props: {'job_id': jobId});
      return true;
    } catch (e) {
      print('Error removing liked job: $e');
      // Rollback otimista
      _likedJobs.insert(idx, removed);
      _swipedIds.add(jobId);
      notifyListeners();
      return false;
    }
  }

  /// Des-salva por ID SEM depender de `_likedJobs` estar carregado (diferente do
  /// [removeLikedJob], que aborta se a vaga não está na lista em memória). O
  /// assistente salva a vaga pelo card mas a lista de likes pode não ter sido
  /// recarregada ainda — então apagamos o swipe direto no banco. Devolve true se
  /// removeu (idempotente: sem linha ⇒ removeLike não faz nada e retorna ok).
  Future<bool> unsaveJobFromList(String jobId) async {
    if (userId == null) return false;
    final idx = _likedJobs.indexWhere((l) => l.job.id == jobId);
    final LikedJob? removed = idx == -1 ? null : _likedJobs.removeAt(idx);
    _swipedIds.remove(jobId);
    notifyListeners();
    try {
      await _swipeRepository.removeLike(userId!, jobId);
      // ignore: unawaited_futures
      Analytics.shared.track(evJobUnsaved, props: {'job_id': jobId});
      return true;
    } catch (e) {
      print('Error unsaving job (list): $e');
      if (removed != null) _likedJobs.insert(idx, removed);
      _swipedIds.add(jobId);
      notifyListeners();
      return false;
    }
  }

  /// Desfaz o [removeLikedJob] — recria o registro com `created_at` original
  /// pra preservar a posição na lista. Chamado pela ação "Desfazer" do
  /// SnackBar mostrado após remoção.
  Future<void> restoreLikedJob(LikedJob liked) async {
    if (userId == null) return;

    try {
      // Fase 1: restore não escreve mais applied/applied_at (legacy) — o
      // estado de candidatura vive em `applications` e é re-derivado no
      // loadLikedJobs abaixo. Escrever applied=false aqui dispararia a
      // bridge de undo no banco indevidamente.
      await _swipeRepository.restoreLike(
        userId!,
        liked.job.id,
        createdAt: liked.likedAt,
      );
      // Recarrega pra puxar o swipeId novo (gerado pelo DB no upsert) e
      // manter consistência com a próxima sessão.
      await loadLikedJobs(silent: true);
      _swipedIds.add(liked.job.id);
      notifyListeners();
    } catch (e) {
      print('Error restoring liked job: $e');
    }
  }

  /// Marca/desmarca vaga como aplicada. Otimista: atualiza UI antes do DB.
  ///
  /// Fase 1: escreve em `applications` (cria `external_confirmed` ou move
  /// pra `withdrawn`) — NÃO escreve mais `swipe_actions.applied` (legacy;
  /// builds antigas continuam via bridge do banco). Re-marcar uma vaga cuja
  /// application estava withdrawn/rejected REABRE a row existente.
  /// Marca/desmarca a vaga como aplicada.
  ///
  /// Devolve `true` só quando a escrita REALMENTE persistiu. Antes era
  /// `Future<void>` e engolia a exceção fazendo rollback interno, então a
  /// tela mostrava "Movida para Enviadas" mesmo com a rede fora — e, pior,
  /// podia reposicionar a aba para um segmento vazio. Achado do review de 27/07.
  Future<bool> setApplied(String jobId, bool applied) async {
    if (userId == null) return false;

    final idx = _likedJobs.indexWhere((l) => l.job.id == jobId);
    if (idx == -1) return false;

    final old = _likedJobs[idx];
    _likedJobs[idx] = LikedJob(
      swipeId: old.swipeId,
      job: old.job,
      applied: applied,
      appliedAt: applied ? DateTime.now() : null,
      likedAt: old.likedAt,
    );
    notifyListeners();

    try {
      if (applied) {
        final result = await _applicationsRepository.markApplied(
          userId: userId!,
          jobId: jobId,
          applicationMethod: old.job.applicationMethod,
        );
        _applicationsByJob[jobId] = result.application;
        if (result.reopened) {
          // ignore: unawaited_futures
          Analytics.shared.applicationReopened(
            applicationId: result.application.id,
            applicationType: result.application.type.db,
            jobId: jobId,
          );
        } else {
          // ignore: unawaited_futures
          Analytics.shared.applicationCreated(
            applicationId: result.application.id,
            applicationType: result.application.type.db,
            jobId: jobId,
            applicationMethod: old.job.applicationMethod,
          );
        }
      } else {
        final prev = _applicationsByJob[jobId];
        final app = await _applicationsRepository.withdraw(
          userId: userId!,
          jobId: jobId,
        );
        if (app != null) {
          _applicationsByJob[jobId] = app;
          // ignore: unawaited_futures
          Analytics.shared.applicationStateChanged(
            applicationId: app.id,
            applicationType: app.type.db,
            fromStatus: prev?.status.db ?? ApplicationStatus.submitted.db,
            toStatus: app.status.db,
            jobId: jobId,
          );
        }
      }
      // O `notifyListeners()` de cima roda ANTES do await, quando
      // `_applicationsByJob[jobId]` ainda é null — ou seja, o frame publicado
      // mostra o card ainda em "Salvas", com o CTA de aplicar. Sem este segundo
      // notify a UI nunca via a application criada: o card ficava no segmento
      // errado e as contagens desatualizadas até um refresh não relacionado.
      notifyListeners();
      return true;
    } catch (e) {
      // Rollback otimista, por ID e nunca pelo índice capturado antes do await
      // — mesma razão de `updateManualApplicationStatus`: `loadLikedJobs`
      // SUBSTITUI `_likedJobs` inteira e `removeLikedJob` faz `removeAt`
      // síncrono, ambos alcançáveis nesta tela enquanto o request está no ar
      // (pull-to-refresh e "Remover" do menu "···"). Com o índice velho, o
      // rollback escrevia em cima da vaga errada ou estourava RangeError DE
      // DENTRO do catch — a exceção escapava do `Future<bool>`, o chamador
      // nunca recebia `false` e o card seguia exibido como aplicado sem nada
      // ter persistido.
      print('Error setting applied: $e');
      final at = _likedJobs.indexWhere((l) => l.job.id == jobId);
      if (at != -1) _likedJobs[at] = old;
      notifyListeners();
      return false;
    }
  }

  /// Fase 3 (T3.1): a application atrelada a uma vaga (ou null se a vaga foi só
  /// salva, nunca aplicada). Fonte da aba Candidaturas pra segmentar e mostrar
  /// status.
  Application? applicationForJob(String jobId) => _applicationsByJob[jobId];

  /// Fase 3 (T3.2): "Sim" no prompt de retorno → cria/reabre a application
  /// external_confirmed. Não depende de `_likedJobs` estar carregado (o prompt
  /// dispara no foreground, em qualquer aba) — diferente de [setApplied].
  Future<void> markAppliedFromPrompt(String jobId) async {
    if (userId == null) return;
    try {
      final result = await _applicationsRepository.markApplied(
        userId: userId!,
        jobId: jobId,
      );
      _applicationsByJob[jobId] = result.application;
      if (result.reopened) {
        // ignore: unawaited_futures
        Analytics.shared.applicationReopened(
          applicationId: result.application.id,
          applicationType: result.application.type.db,
          jobId: jobId,
        );
      } else {
        // ignore: unawaited_futures
        Analytics.shared.applicationCreated(
          applicationId: result.application.id,
          applicationType: result.application.type.db,
          jobId: jobId,
        );
      }
      _reflectAppliedFromApplication(jobId);
      notifyListeners();
    } catch (e) {
      print('Error markAppliedFromPrompt: $e');
    }
  }

  /// Fase 3 (T3.3): cria uma candidatura manual (FAB da aba). Retorna false se
  /// falhou. Emite application_created (application_type='manual', R7).
  Future<bool> createManualApplication({
    required String company,
    required String title,
    String? url,
    ApplicationStatus status = ApplicationStatus.submitted,
  }) async {
    if (userId == null) return false;
    try {
      final app = await _applicationsRepository.createManual(
        userId: userId!,
        externalCompany: company,
        externalTitle: title,
        externalUrl: url,
        status: status,
      );
      _manualApplications = [app, ..._manualApplications];
      // ignore: unawaited_futures
      Analytics.shared.applicationCreated(
        applicationId: app.id,
        applicationType: app.type.db,
      );
      notifyListeners();
      return true;
    } catch (e) {
      print('Error createManualApplication: $e');
      return false;
    }
  }

  /// Fase 3 (T3.3): move o status de uma application MANUAL (sem job_id) — a
  /// versão por job_id de [updateApplicationStatus] não cobre manuais.
  Future<bool> updateManualApplicationStatus({
    required Application app,
    required ApplicationStatus newStatus,
  }) async {
    if (app.status == newStatus || !app.type.userEditableStatus) return false;
    final idx = _manualApplications.indexWhere((a) => a.id == app.id);
    if (idx == -1) return false;
    final prev = _manualApplications[idx];
    _manualApplications[idx] = prev.copyWith(status: newStatus);
    notifyListeners();
    try {
      final updated = await _applicationsRepository.updateStatus(
        applicationId: app.id,
        status: newStatus,
      );
      // Re-localiza por ID: `loadLikedJobs` e `createManualApplication`
      // SUBSTITUEM a lista inteira, então o índice capturado antes do await
      // pode apontar para outra candidatura — escrever por ele sobrescreveria
      // a errada. Achado do review de 27/07.
      final at = _manualApplications.indexWhere((a) => a.id == app.id);
      if (at != -1) _manualApplications[at] = updated;
      // ignore: unawaited_futures
      Analytics.shared.applicationStateChanged(
        applicationId: updated.id,
        applicationType: updated.type.db,
        fromStatus: prev.status.db,
        toStatus: updated.status.db,
      );
      notifyListeners();
      return true;
    } catch (e) {
      print('Error updateManualApplicationStatus: $e');
      // Mesma razão: rollback por ID, nunca por índice velho.
      final at = _manualApplications.indexWhere((a) => a.id == app.id);
      if (at != -1) _manualApplications[at] = prev;
      notifyListeners();
      return false;
    }
  }

  /// Fase 3 (T3.1): move o status de uma application na aba Candidaturas.
  /// Só pra type manual/external_confirmed (stage é read-only). Otimista, com
  /// rollback; emite application_state_changed (R7). Retorna false se falhou.
  Future<bool> updateApplicationStatus({
    required String jobId,
    required ApplicationStatus newStatus,
  }) async {
    if (userId == null) return false;
    final prev = _applicationsByJob[jobId];
    if (prev == null || prev.status == newStatus) return false;
    if (!prev.type.userEditableStatus) return false;

    // Otimista.
    _applicationsByJob[jobId] = prev.copyWith(status: newStatus);
    _reflectAppliedFromApplication(jobId);
    notifyListeners();

    try {
      final updated = await _applicationsRepository.updateStatus(
        applicationId: prev.id,
        status: newStatus,
      );
      _applicationsByJob[jobId] = updated;
      _reflectAppliedFromApplication(jobId);
      // ignore: unawaited_futures
      Analytics.shared.applicationStateChanged(
        applicationId: updated.id,
        applicationType: updated.type.db,
        fromStatus: prev.status.db,
        toStatus: updated.status.db,
        jobId: jobId,
      );
      notifyListeners();
      return true;
    } catch (e) {
      print('Error updating application status: $e');
      _applicationsByJob[jobId] = prev; // rollback
      _reflectAppliedFromApplication(jobId);
      notifyListeners();
      return false;
    }
  }

  /// Mantém `LikedJob.applied` em sincronia com a application após mudança de
  /// status (countsAsApplied — withdrawn/expired desmarcam).
  void _reflectAppliedFromApplication(String jobId) {
    final idx = _likedJobs.indexWhere((l) => l.job.id == jobId);
    if (idx == -1) return;
    final app = _applicationsByJob[jobId];
    final isApplied = app != null && app.status.countsAsApplied;
    final old = _likedJobs[idx];
    _likedJobs[idx] = LikedJob(
      swipeId: old.swipeId,
      job: old.job,
      applied: isApplied,
      appliedAt: isApplied ? (app.createdAt) : null,
      likedAt: old.likedAt,
    );
  }
}
