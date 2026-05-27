import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/ai_service.dart';
import '../../services/analytics_service.dart';
import '../../services/profile_events.dart';
import '../../services/profile_snapshot_service.dart';
import 'data/job_repository.dart';
import 'data/swipe_repository.dart';
import 'data/preferences_repository.dart';
import 'models/job.dart';
import 'models/user_preferences.dart';
import 'utils/match_score.dart';

class JobsViewModel extends ChangeNotifier {
  final JobRepository _jobRepository;
  final SwipeRepository _swipeRepository;
  /// @deprecated Mantido no construtor por compatibilidade durante a migração
  /// pra fonte única (tabelas relacionais `profile_*`). Após Passo 3 do plano
  /// match-score (2026-05-27), JobsViewModel NÃO chama mais este repo — filtros
  /// vão pra SharedPreferences local e identidade vem das tabelas relacionais.
  /// Remover no Passo 6 (pós-release) junto com o cleanup do legacy.
  // ignore: unused_field
  final PreferencesRepository _preferencesRepository;
  final AIService _aiService;

  /// Listener pra mudanças no auth Supabase. Garante que `init()` rode
  /// assim que o user logar (caso o widget tenha sido construído antes
  /// da sessão estar pronta — race condition que bloqueava o feed até
  /// hot-restart).
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<void>? _profileEventsSub;

  JobsViewModel(
    this._jobRepository,
    this._swipeRepository,
    this._preferencesRepository,
    this._aiService,
  ) {
    // Invalida cache de profileText E profilePrefs quando o user edita o
    // perfil — sem isso, adicionar skill via Profile Editor ou mudar
    // preferências via tab Perfil não reflete no match score determinístico
    // até hot-restart.
    _profileEventsSub = ProfileEvents.instance.changes.listen((_) {
      _profileTextLoaded = false;
      _cachedProfileText = null;
      _profilePrefsLoaded = false;
      _cachedProfilePrefs = null;
      notifyListeners();
    });
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          // Session passou a estar disponível. Se ainda não temos vagas
          // E não estamos carregando, dispara o init. Idempotente —
          // init() faz no-op se já tem dados.
          if (_jobs.isEmpty && !_isLoading) {
            init();
          }
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
          _totalAvailable = 0;
          _totalAfterFilters = 0;
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

  /// Verdadeiro quando há vagas no banco mas os filtros do user excluíram
  /// todas. UI usa pra mostrar "afrouxe os filtros" em vez de "explorou tudo".
  bool get filtersAreTooRestrictive =>
      _totalAvailable > 0 &&
      _totalAfterFilters == 0 &&
      _preferences != null &&
      !_preferences!.isEmpty;

  String? get userId => Supabase.instance.client.auth.currentUser?.id;

  /// Aguarda o auth ficar pronto com short-poll. Retorna o user_id se aparecer
  /// dentro do timeout, null caso contrário. Usado pra mitigar a race entre o
  /// widget montar e a sessão Supabase restaurar do storage local (cold start
  /// do app pode levar 100-500ms).
  Future<String?> _awaitUserId({Duration timeout = const Duration(seconds: 3)}) async {
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
      return; // no-op: já inicializado, mantém ordem atual dos cards
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Espera o auth ficar pronto se ainda não estiver (race condition no
      // cold start). Sem isso, init() rodando antes da sessão restaurar
      // travava o feed até hot-restart.
      final id = await _awaitUserId();
      if (id == null) {
        // Realmente sem user — provavelmente deslogou. UI mostra estado vazio.
        return;
      }
      await _performFetch();
    } catch (e) {
      _errorMessage = 'Erro ao carregar vagas. Tente novamente.';
      print('Error initializing jobs: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _performFetch() async {
    // 1) Carrega FILTROS temporários do feed (local). Se não existem,
    //    default = identidade do Perfil (tabelas relacionais), pra que o
    //    user na 1ª abertura veja feed filtrado por área/cidade declaradas.
    //    User pode mexer nos filtros depois sem afetar o Perfil.
    final uid = userId!;
    _preferences = await _loadLocalFilters(uid);
    if (_preferences == null || _preferences!.isEmpty) {
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
      _cachedGamificationData = row?['gamification_data'] as Map<String, dynamic>?;
    } catch (e) {
      print('fetchGamificationData failed: $e');
      _cachedGamificationData = null;
    } finally {
      _gamificationDataLoaded = true;
    }
    return _cachedGamificationData;
  }

  /// Preferências de IDENTIDADE do user (área, cidade, modelo, tipo) lidas
  /// diretamente das tabelas relacionais `profile_job_preferences`,
  /// `profile_desired_titles`, `profile_other_locations`. Usada pra alimentar
  /// o MatchScoreCalculator no fallback determinístico — separadas dos
  /// filtros temporários de feed (`_preferences`). Cacheado por sessão;
  /// invalida em [ProfileEvents.changes] e [signOut].
  UserJobPreferences? _cachedProfilePrefs;
  bool _profilePrefsLoaded = false;
  Future<UserJobPreferences?> _loadProfilePrefs() async {
    if (_profilePrefsLoaded) return _cachedProfilePrefs;
    try {
      final uid = userId;
      if (uid == null) {
        _cachedProfilePrefs = null;
      } else {
        final client = Supabase.instance.client;
        // Future.wait não infere tipo comum entre maybeSingle (Map?) e
        // select (List<Map>) — explicitamos `dynamic` e fazemos cast depois.
        final results = await Future.wait<dynamic>([
          client.from('profile_job_preferences').select('*').eq('user_id', uid).maybeSingle(),
          client.from('profile_desired_titles').select('title').eq('user_id', uid),
          client.from('profile_other_locations').select('city').eq('user_id', uid),
        ]);

        final jp = results[0] as Map<String, dynamic>?;
        final dtList = (results[1] as List).cast<dynamic>();
        final olList = (results[2] as List).cast<dynamic>();

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
            case 'remote': return 'remoto';
            case 'hybrid': return 'hibrido';
            case 'in_person': return 'presencial';
            default: return s; // já em PT ou desconhecido
          }
        }).toList();

        final jobTypes = (jp?['job_types'] as List?)
            ?.cast<dynamic>()
            .map((e) => e.toString())
            .toList() ?? <String>[];

        if (areas.isEmpty && locations.isEmpty && workModes.isEmpty && jobTypes.isEmpty) {
          _cachedProfilePrefs = null;
        } else {
          _cachedProfilePrefs = UserJobPreferences(
            userId: uid,
            areas: areas,
            locations: locations,
            workModels: workModes,
            jobTypes: jobTypes,
            // min_salary não existe em profile_job_preferences (decisão founder
            // 2026-05-27). Salário fica fora da identidade; se o user quiser
            // filtrar por salário, usa filtros temporários do feed.
            minSalary: null,
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

  // ── Filtros temporários de feed: persistência local ─────────────────
  // Após Passo 3 do plano match-score (2026-05-27), filtros viram TEMPORÁRIOS:
  // - Vivem em SharedPreferences local (key: 'job_filters_<userId>').
  // - Não escrevem mais em user_preferences (Supabase) via PreferencesRepository.
  // - Não afetam match score (que lê de [profilePrefs] = tabelas relacionais).
  // - Default ao abrir pela 1ª vez: cópia das prefs do Perfil (vide _performFetch).
  static String _filtersKey(String userId) => 'job_filters_$userId';

  Future<UserJobPreferences?> _loadLocalFilters(String uid) async {
    try {
      final sp = await SharedPreferences.getInstance();
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
    } catch (e) {
      print('saveLocalFilters failed: $e');
    }
  }

  Future<void> _clearLocalFilters(String uid) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_filtersKey(uid));
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
    if (_autoReloadAttempted) return;
    if (_isLoading) return;
    _autoReloadAttempted = true;
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
      _preferences = await _loadLocalFilters(uid);
      if (_preferences == null || _preferences!.isEmpty) {
        _preferences = await _loadProfilePrefs();
      }
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
      Analytics.shared.track('job_unsaved', props: {'job_id': jobId});
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

  /// Desfaz o [removeLikedJob] — recria o registro com `created_at` original
  /// pra preservar a posição na lista. Chamado pela ação "Desfazer" do
  /// SnackBar mostrado após remoção.
  Future<void> restoreLikedJob(LikedJob liked) async {
    if (userId == null) return;

    try {
      await _swipeRepository.restoreLike(
        userId!,
        liked.job.id,
        createdAt: liked.likedAt,
        applied: liked.applied,
        appliedAt: liked.appliedAt,
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
