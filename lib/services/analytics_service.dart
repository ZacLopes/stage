import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_events.dart';

/// Service centralizado de analytics. Wrapper sobre PostHog pra:
/// - Manter nomes de eventos tipados (evita typo em string solta no app)
/// - Centralizar enable/disable (dev vs prod)
/// - Adicionar properties globais (versão do app, etc) automaticamente
/// - Trocar de provider depois sem refactor do app (só edita esse arquivo)
///
/// Eventos seguem padrão `<objeto>_<acao>` (object-action). Exemplos:
///   `job_swiped`, `cv_exported`, `founders_contact_opened`.
class AnalyticsService {
  /// Singleton — uma instância pro app inteiro. Acesso via `Analytics.shared`.
  static final AnalyticsService shared = AnalyticsService._();
  AnalyticsService._();

  bool _initialized = false;

  // ── Cutover infrastructure (release 2026-05/06) ─────────────────────
  /// Uma vez setado, o alias do cutover não roda novamente nesse device.
  /// v2 (2026-05-30): bump força o bloco de marcação a re-rodar UMA vez por
  /// device pra corrigir `is_pre_cutover_user` na base existente (backfill via
  /// app) — a lógica antiga marcava errado/de menos.
  static const String _kCutoverAliasDoneKey = 'analytics_cutover_alias_done_v2';
  /// Flag manual "esse device é interno". Toggleável via tela de devmode.
  /// Quando true, todos os eventos carregam `is_internal: true` (super property)
  /// e a person é marcada com `is_internal: true` (cohort de filtro).
  static const String _kIsInternalKey = 'analytics_is_internal_user';
  /// Timestamp epoch ms do `onboarding_started`. Resolvido pelo
  /// `onboarding_completed`/`_abandoned` pra calcular `total_duration_ms`
  /// sem caller precisar manter state.
  static const String _kOnboardingStartedAtKey =
      'analytics_onboarding_started_at';
  /// Door escolhida em TwoDoorsScreen ('upload_cv'|'trail'|'from_scratch').
  /// Resolvida no `OnboardingCompleteScreen._handleFinish` pra evitar
  /// hardcode/race condition.
  static const String _kOnboardingDoorKey = 'analytics_onboarding_door';

  String? _appVersion;
  String? _appBuildNumber;
  bool _isInternal = false;

  // ── Session lifecycle (B.6) ─────────────────────────────────────────
  /// Sessão corrente. Novo ID por cold start E por warm start após >5min
  /// no background. Registrado como super property `session_id` em todo
  /// evento subsequente.
  String? _sessionId;
  DateTime? _sessionStartedAt;
  DateTime? _backgroundedAt;
  static const Duration _kSessionTimeout = Duration(minutes: 5);
  _AnalyticsLifecycleObserver? _lifecycleObserver;
  final Random _random = Random.secure();

  // ── Error Tracking context (A.10) ───────────────────────────────────
  /// Último nome de evento capturado — preenchido em [track]. Anexado a
  /// `$exception` em [captureException] pra dar contexto do que o user
  /// fazia no momento do crash. Sem isso, stack traces sozinhos não
  /// reconstruem o flow.
  String? _lastEvent;
  DateTime? _lastEventAt;
  /// Última tela vista — preenchido em [screen]. Idem [_lastEvent].
  String? _lastScreen;

  /// Inicializa o serviço. Chamado uma vez em `main()` após `WidgetsFlutterBinding.ensureInitialized()`.
  /// Sem isso, todos os `track()` viram no-op (loga warning em debug).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (kDebugMode) {
      debugPrint('[Analytics] init — debug mode, eventos visíveis no console PostHog');
    }
    // Super properties: carregadas e registradas ANTES de qualquer evento
    // (incluindo `app_opened` que dispara logo em seguida em main.dart).
    // PostHog injeta essas props automaticamente em todo evento subsequente.
    await _loadAndRegisterSuperProperties();
    // Race condition guard: se o user já está logado quando o Analytics
    // inicializa (cold start com session restaurada), identify imediatamente.
    // Combinado com lógica de cutover alias — pre-cutover users são detectados
    // e marcados (is_pre_cutover_user=true) na primeira boot pós-release.
    await identifyIfLoggedIn();
  }

  /// Re-registra todas as super properties (app_version, app_build_number,
  /// is_internal, flow_version) no PostHog. Chamar SEMPRE após qualquer
  /// `Posthog().reset()` (que apaga super properties no SDK iOS) — tipicamente
  /// no callback `signedIn` do auth listener, pra garantir que eventos pós-
  /// logout/signup novo continuem carregando essas props. Sem isso, todos os
  /// eventos pós-logout viam `app_version: null` e `is_internal: null`,
  /// quebrando filtros e cohorts.
  ///
  /// Idempotente: pode ser chamado várias vezes sem efeito colateral —
  /// register() sobrescreve no SDK. Wrapper público do método privado abaixo
  /// pra manter convenção de underscore-prefix no setup interno do init().
  Future<void> refreshSuperProperties() => _loadAndRegisterSuperProperties();

  /// Carrega app version + build + flag is_internal de SharedPrefs e registra
  /// como super properties no PostHog. Super properties são injetadas
  /// automaticamente em TODO evento subsequente até reset/close. Esse é o
  /// primeiro passo pra cumprir o princípio "is_internal em todo evento" do
  /// plano de instrumentação v2.
  Future<void> _loadAndRegisterSuperProperties() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      _appVersion = pkg.version;
      _appBuildNumber = pkg.buildNumber;
      final prefs = await SharedPreferences.getInstance();
      _isInternal = prefs.getBool(_kIsInternalKey) ?? false;
      await Posthog().register('app_version', _appVersion!);
      await Posthog().register('app_build_number', _appBuildNumber!);
      // Padrão "presence = true": registra `is_internal` SOMENTE quando
      // for true. Quando false, unregister. O iOS native do PostHog
      // dropa boolean falsy ao serializar (QA Dia 6: super property
      // aparece como `None`). Cohort "Internal users" filtra por person
      // property (set em setInternalUser via identify) — não quebra.
      if (_isInternal) {
        await Posthog().register('is_internal', true);
      } else {
        await Posthog().unregister('is_internal');
      }
      // flow_version: hardcoded — toda build a partir do cutover é profile_first.
      // Mantido como super property pra futuros forks/legacy paths.
      await Posthog().register('flow_version', 'profile_first');
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] _loadAndRegisterSuperProperties failed: $e');
    }
  }

  /// $groupidentify client-side (A.14 do plano v2). Use ANTES de emitir
  /// eventos que devem ser agregados por esse group. PostHog auto-registra
  /// novo `groupType` no primeiro use. Idempotente — calls subsequentes
  /// sobrescrevem properties.
  ///
  /// Tipos canônicos (case-sensitive):
  /// - `company` — empresas das vagas (key = company_id).
  /// - `university` — universidade do usuário (key = nome).
  /// - `ad_campaign` — campanha de aquisição (key = campaign_id).
  /// - `job` — vaga individual (key = job_id). **Atenção volume.**
  /// - `phase` — fase da trilha (key = phase_id).
  /// - `prompt_version` — versão de prompt IA (key = function:version).
  Future<void> groupIdentify({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) async {
    if (!_initialized) return;
    try {
      await Posthog().group(
        groupType: groupType,
        groupKey: groupKey,
        groupProperties: groupProperties,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] groupIdentify failed: $e');
    }
  }

  /// Liga/desliga o flag is_internal pra esse device. Quando ligado:
  /// 1. Property `is_internal: true` vira super property em todo evento futuro.
  /// 2. Person property `is_internal: true` é setada via $set.
  /// O cohort "Internal users" no PostHog usa essas propriedades pra filtrar
  /// fundadores e testers fora das métricas de produto.
  Future<void> setInternalUser(bool value) async {
    _isInternal = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIsInternalKey, value);
      // "Presence = true" pattern — ver comentário em
      // _loadAndRegisterSuperProperties. Evita ambiguidade do native SDK
      // dropando boolean falsy.
      if (value) {
        await Posthog().register('is_internal', true);
      } else {
        await Posthog().unregister('is_internal');
      }
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Person property continua bool (cohort exige exact match).
        await Posthog().identify(
          userId: user.id,
          userProperties: {'is_internal': value},
        );
      }
      if (kDebugMode) debugPrint('[Analytics] setInternalUser: $value');
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] setInternalUser failed: $e');
    }
  }

  /// Retorna o estado atual do flag `is_internal` (do SharedPrefs).
  bool get isInternalUser => _isInternal;

  // ── B.6 Session lifecycle ───────────────────────────────────────────

  /// Liga o observer de lifecycle (AppLifecycleState) ao Analytics. Chamar
  /// uma vez no main.dart após `init()`. Idempotente. Inicia a primeira
  /// sessão (cold start) e passa a emitir `app_backgrounded`,
  /// `app_foregrounded`, `session_started`, `session_ended` nos pontos
  /// certos.
  ///
  /// Regra de boundary: ficar >5 min no background fecha a sessão e
  /// abre uma nova ao foregroundar. Padrão da indústria mobile pra
  /// definir "uma sessão" semanticamente.
  Future<void> bindLifecycle() async {
    if (_lifecycleObserver != null) return;
    _lifecycleObserver = _AnalyticsLifecycleObserver(this);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
    await _startNewSession(coldStart: true);
  }

  Future<void> _startNewSession({required bool coldStart}) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final lastEndedMillis = prefs.getInt(_kLastSessionEndedAtKey);
    final timeSinceLastSessionMs = lastEndedMillis != null
        ? now.millisecondsSinceEpoch - lastEndedMillis
        : null;

    _sessionId = _generateSessionId();
    _sessionStartedAt = now;
    try {
      await Posthog().register('session_id', _sessionId!);
    } catch (_) {}

    await track(evSessionStarted, props: {
      'cold_vs_warm': coldStart ? 'cold' : 'warm',
      if (timeSinceLastSessionMs != null)
        'time_since_last_session_ms': timeSinceLastSessionMs,
    });
  }

  Future<void> _endCurrentSession({required String exitType}) async {
    final start = _sessionStartedAt;
    if (start == null) return;
    final duration = DateTime.now().difference(start).inMilliseconds;
    await track(evSessionEnded, props: {
      'duration_ms': duration,
      'exit_type': exitType,
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastSessionEndedAtKey, DateTime.now().millisecondsSinceEpoch);
    _sessionId = null;
    _sessionStartedAt = null;
  }

  /// Chamado pelo observer quando o app vai pra background.
  Future<void> _onBackgrounded() async {
    _backgroundedAt = DateTime.now();
    final start = _sessionStartedAt;
    final durationInForeground = start != null
        ? DateTime.now().difference(start).inMilliseconds
        : 0;
    await track(evAppBackgrounded, props: {
      'duration_in_foreground_ms': durationInForeground,
    });
  }

  /// Chamado pelo observer quando o app volta pro foreground. Se ficou
  /// no background além do timeout, encerra a sessão anterior e abre uma
  /// nova; senão é só `app_foregrounded` (continuação).
  Future<void> _onForegrounded() async {
    final backgroundedAt = _backgroundedAt;
    final now = DateTime.now();
    final durationInBackgroundMs = backgroundedAt != null
        ? now.difference(backgroundedAt).inMilliseconds
        : 0;
    _backgroundedAt = null;

    await track(evAppForegrounded, props: {
      'duration_in_background_ms': durationInBackgroundMs,
    });

    if (backgroundedAt != null &&
        now.difference(backgroundedAt) > _kSessionTimeout) {
      // Sessão estourou o timeout — fecha a anterior e abre nova.
      await _endCurrentSession(exitType: 'session_timeout');
      await _startNewSession(coldStart: false);
    }
  }

  /// Chamado pelo observer quando o engine vai ser detached (kill iminente).
  /// Em alguns devices/ios esse callback nem dispara — sessão fica pendurada
  /// até o próximo boot, quando `_startNewSession` lê `time_since_last_session_ms`
  /// e detecta o gap.
  Future<void> _onAppTerminated() async {
    await _endCurrentSession(exitType: 'detached');
  }

  String _generateSessionId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rnd = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '${ts}_$rnd';
  }

  static const String _kLastSessionEndedAtKey = 'analytics_last_session_ended_at';

  /// Lê a sessão atual do Supabase e chama [identify] se houver user logado.
  /// Idempotente — pode ser chamado várias vezes.
  ///
  /// **Cutover (release 2026-05/06):** na PRIMEIRA chamada pós-instalação da
  /// nova build com user JÁ logado, faz duas coisas extras:
  /// 1. `posthog.alias(user.id)` — liga o distinct_id anônimo atual ao user_id
  ///    Supabase, preservando continuidade de identidade entre versões do app.
  /// 2. Marca a person com `is_pre_cutover_user` (true/false) com base na DATA
  ///    DE CRIAÇÃO DA CONTA Supabase (criada antes do release = pré-cutover). O
  ///    cohort "Pre-cutover users" usa essa flag pra separar histórico velho do
  ///    dado limpo pós-release. O pitch do Demo Day usa "Post-cutover users".
  /// A flag fica em SharedPrefs (`_kCutoverAliasDoneKey`) pra não rodar de novo.
  Future<void> identifyIfLoggedIn() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final cutoverAliasDone = prefs.getBool(_kCutoverAliasDoneKey) ?? false;

      if (!cutoverAliasDone) {
        await Posthog().alias(alias: user.id);
        // is_pre_cutover_user vem da DATA DE CRIAÇÃO DA CONTA (Supabase), não da
        // "primeira boot". Conta criada antes do release da build nova de
        // instrumentação = usuário do tempo antigo (pré-cutover); depois =
        // pós-release. Vai em userProperties ($set, sobrescreve) — não set_once —
        // pra corrigir valores marcados errado pela lógica antiga. Ajuste a data
        // abaixo se o release de produção tiver sido outro dia.
        final cutoverDate = DateTime.parse('2026-05-30T03:00:00Z'); // 00:00 BRT 30/05
        final createdAt = DateTime.tryParse(user.createdAt);
        final isPreCutover = createdAt != null && createdAt.isBefore(cutoverDate);
        await Posthog().identify(
          userId: user.id,
          userProperties: {
            if (user.email != null) 'email': user.email!,
            if (_isInternal) 'is_internal': true,
            'is_pre_cutover_user': isPreCutover,
          },
          userPropertiesSetOnce: {
            'cutover_alias_at': DateTime.now().toIso8601String(),
          },
        );
        await prefs.setBool(_kCutoverAliasDoneKey, true);
        if (kDebugMode) {
          debugPrint('[Analytics] cutover alias done for user ${user.id}');
        }
      } else {
        // Boot subsequente: identify normal (sem re-alias, sem re-marcar).
        await Posthog().identify(
          userId: user.id,
          userProperties: {
            if (user.email != null) 'email': user.email!,
            if (_isInternal) 'is_internal': true,
          },
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] identifyIfLoggedIn failed: $e');
    }
  }

  /// Track de evento genérico. Use os helpers tipados abaixo sempre que possível.
  ///
  /// **Allowlist (debug only):** em debug mode, eventos não-catalogados em
  /// `kAllowedEventNames` (ver `analytics_events.dart`) logam warning. Em
  /// release, passam silenciosamente — analytics nunca pode quebrar o app.
  /// O objetivo é forçar disciplina de taxonomia no dev: todo evento novo
  /// passa pelo catálogo antes de ser emitido.
  Future<void> track(String event, {Map<String, Object>? props}) async {
    if (!_initialized) {
      if (kDebugMode) debugPrint('[Analytics] WARN: track antes de init: $event');
      return;
    }
    if (kDebugMode && !kAllowedEventNames.contains(event)) {
      debugPrint('[Analytics] WARN: evento "$event" não está em kAllowedEventNames — adicionar a analytics_events.dart');
    }
    // Cacheia pra enriquecimento posterior do $exception (A.10).
    // Eventos $exception não atualizam pra não sobrescrever o contexto
    // do evento que precedeu o crash.
    if (!event.startsWith(r'$')) {
      _lastEvent = event;
      _lastEventAt = DateTime.now();
    }
    try {
      await Posthog().capture(eventName: event, properties: props);
    } catch (e) {
      // Analytics nunca pode quebrar o app. Loga só em debug.
      if (kDebugMode) debugPrint('[Analytics] capture failed: $e');
    }
  }

  /// Identifica o user logado. Chamado após login/signup e quando user logado
  /// abre o app. Vincula eventos futuros a esse user no dashboard.
  ///
  /// [properties] vira `$set` (sobrescreve a cada call). [propertiesSetOnce]
  /// vira `$set_once` (só seta se a property ainda não existe na person).
  /// Use `propertiesSetOnce` pra "first_signup_date", "first_install_source",
  /// "is_pre_cutover_user" etc — coisas que descrevem o nascimento do user.
  Future<void> identify(
    String userId, {
    Map<String, Object>? properties,
    Map<String, Object>? propertiesSetOnce,
  }) async {
    if (!_initialized) return;
    try {
      await Posthog().identify(
        userId: userId,
        userProperties: properties,
        userPropertiesSetOnce: propertiesSetOnce,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] identify failed: $e');
    }
  }

  /// Limpa identificação (logout). Eventos futuros viram anônimos.
  Future<void> reset() async {
    if (!_initialized) return;
    try {
      await Posthog().reset();
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] reset failed: $e');
    }
  }

  /// Lê uma feature flag. Retorna a string da variante (ex.: 'ai_match_v1',
  /// 'deterministic_v1') ou null se a flag não existe / PostHog não está
  /// inicializado. Use em decisões de produto, NÃO em fluxos que precisam de
  /// resposta síncrona — esta chamada faz round-trip pra cache do SDK.
  ///
  /// Pra A/B test, use `getFeatureFlag(key)` no PostHog e mapeie as variantes:
  ///   - flag enabled (true)  → variante padrão
  ///   - string específica    → variante nomeada (multivariate)
  Future<String?> getFlag(String key) async {
    if (!_initialized) return null;
    try {
      final v = await Posthog().getFeatureFlag(key);
      if (v == null) return null;
      if (v is bool) return v ? 'true' : 'false';
      return v.toString();
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] getFlag failed: $e');
      return null;
    }
  }

  /// Captura uma exception como evento `$exception`. posthog_flutter 4.11 não
  /// tem `captureException` nativo, então emitimos manualmente no formato que
  /// o produto Error Tracking do PostHog reconhece. `handled=false` indica
  /// crash não tratado (FlutterError/runZonedGuarded); `true` indica try-catch
  /// onde decidimos reportar.
  ///
  /// **Enrichment (A.10 do plano v2):** anexa contexto do que o user
  /// fazia no momento — `last_screen`, `last_event`, `ms_since_last_event`,
  /// `session_id`, `is_pre_cutover_user`. Sem isso, debugar issue no
  /// Error Tracking é caça ao tesouro (audit fix).
  Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
    bool handled = true,
    Map<String, Object>? extra,
  }) async {
    if (!_initialized) return;
    try {
      final exceptionType = error.runtimeType.toString();
      final exceptionMessage = error.toString();
      final stackString = stackTrace?.toString() ?? '';
      final msSinceLastEvent = _lastEventAt != null
          ? DateTime.now().difference(_lastEventAt!).inMilliseconds
          : null;
      await Posthog().capture(
        eventName: r'$exception',
        properties: {
          r'$exception_type': exceptionType,
          r'$exception_message': exceptionMessage,
          if (stackString.isNotEmpty) r'$exception_stack_trace_raw': stackString,
          r'$exception_personURL': '',
          r'$exception_handled': handled,
          // Contexto do que o user fazia (A.10):
          if (_lastScreen != null) 'last_screen': _lastScreen!,
          if (_lastEvent != null) 'last_event': _lastEvent!,
          if (msSinceLastEvent != null) 'ms_since_last_event': msSinceLastEvent,
          if (_sessionId != null) 'session_id': _sessionId!,
          if (_appVersion != null) 'app_version_at_crash': _appVersion!,
          if (extra != null) ...extra,
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] captureException failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Eventos tipados — toda emissão usa constants de `analytics_events.dart`
  // (BLOCO B do plano v2, taxonomia ratificada no cutover).
  // Nomes de método em camelCase Dart; nomes de evento em snake_case são
  // mantidos como string apenas dentro das constants.
  // ════════════════════════════════════════════════════════════════════

  // ── App lifecycle ───────────────────────────────────────────────────
  /// Dispara no boot do app (chamado em main.dart). Base pra DAU/MAU.
  /// Super properties (is_internal, flow_version, app_version) já vão
  /// injetadas automaticamente — ver `_loadAndRegisterSuperProperties`.
  Future<void> appOpened() => track(evAppOpened);

  /// Tempo do início do `main()` até o primeiro frame renderizado.
  /// Métrica UX percebida — se >3s, splash screen acima do tolerável.
  /// Captura via `WidgetsBinding.instance.addPostFrameCallback` no main.
  Future<void> appColdStart({required int durationMs}) =>
      track(evAppColdStart, props: {'duration_ms': durationMs});

  /// Mesma ideia de [appColdStart] mas pra warm starts (foreground após
  /// background). Capturado automaticamente pelo session lifecycle no
  /// boundary <5min (ver `_onForegrounded`).
  Future<void> appWarmStart({required int durationMs}) =>
      track(evAppWarmStart, props: {'duration_ms': durationMs});

  /// Version gate detectou que a build do user está abaixo da requerida.
  /// Dispara antes da força-update screen aparecer.
  Future<void> appVersionOutdated({
    required String currentVersion,
    required String requiredVersion,
  }) =>
      track(evAppVersionOutdated, props: {
        'current_version': currentVersion,
        'required_version': requiredVersion,
      });

  /// Dispara `$screen` com `screen_name` real. `PosthogObserver` foi
  /// removido no cutover (release 2026-05/06) por sempre cair em
  /// `root('/')` — emitir manualmente do initState via
  /// [ScreenTrackingMixin] é agora a única fonte de screen_name.
  Future<void> screen(String name, {Map<String, Object>? properties}) async {
    if (!_initialized) return;
    _lastScreen = name;
    try {
      await Posthog().screen(screenName: name, properties: properties);
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] screen failed: $e');
    }
  }

  // ── Auth & Onboarding ───────────────────────────────────────────────

  /// Tela de signup ficou visível. Antes do método escolhido.
  Future<void> authSignupLandingShown({String? variant}) =>
      track(evAuthSignupLandingShown, props: {
        if (variant != null) 'variant': variant,
      });

  /// Usuário escolheu o método (apple/email/phone). Disparado ANTES de
  /// auth_signup_started (que marca início do fluxo real). [attempt] = N
  /// quando user troca de método.
  Future<void> authSignupMethodChosen({
    required String method,
    int? attempt,
  }) =>
      track(evAuthSignupMethodChosen, props: {
        'method': method,
        if (attempt != null) 'attempt': attempt,
      });

  /// Início efetivo do fluxo de signup (após método escolhido). Pareado
  /// com auth_signup_completed/_failed pra calcular dropout.
  Future<void> authSignupStarted({required String method}) =>
      track(evAuthSignupStarted, props: {'method': method});

  Future<void> signUpCompleted({required String method}) =>
      track(evAuthSignupCompleted, props: {'method': method});

  /// Par que faltava de [authSignupStarted]. A constante existia desde sempre
  /// em `analytics_events.dart` e NUNCA tinha emissor — catálogo morto, que a
  /// R7 proíbe. Sem ela, apertar a política de senha no servidor seria mexer
  /// no funil de entrada às cegas: um cadastro que passa a falhar não aparece
  /// em painel nenhum, só na queda de contas criadas semanas depois.
  ///
  /// [errorCode] vem de `authFailureCode` — rótulo fechado, nunca a mensagem
  /// do servidor (muda entre versões, tem cardinalidade alta e pode carregar
  /// dado de quem tentou entrar).
  Future<void> authSignupFailed({
    required String method,
    required String errorCode,
  }) =>
      track(evAuthSignupFailed, props: {
        'method': method,
        'error_code': errorCode,
      });

  /// Falha ao ENTRAR (não ao criar). Separado de [authSignupFailed] de
  /// propósito: na tela de telefone, que é login e cadastro na mesma porta,
  /// misturar os dois tornaria a métrica de cadastro ilegível.
  Future<void> authLoginFailed({
    required String method,
    required String errorCode,
  }) =>
      track(evAuthLoginFailed, props: {
        'method': method,
        'error_code': errorCode,
      });

  Future<void> loginCompleted({required String method}) =>
      track(evAuthLoginSucceeded, props: {'method': method});

  Future<void> logoutCompleted() => track(evAuthLogout);

  /// Disparado no início de `signInWithApple()` — válido tanto pra signup
  /// novo quanto login retornante (Apple não distingue antes do callback).
  /// Mapeado pra `auth_login_attempt` com method='apple'. Combinado com
  /// `appleSigninFailed` e `signUpCompleted`/`loginCompleted` dá taxa de
  /// abandono no flow Apple Sign-In.
  Future<void> appleSigninStarted() =>
      track(evAuthLoginAttempt, props: {'method': 'apple'});

  /// `code`: 'cancelled', 'token_missing', 'unknown'. Diferencia abandono
  /// (cancelled pelo usuário no diálogo iOS) vs falha técnica.
  Future<void> appleSigninFailed({required String code}) =>
      track(evAuthLoginFailed, props: {'method': 'apple', 'error_code': code});

  /// `step` é a ordem numérica (legacy, mantido pra continuidade de dashboards).
  /// `stepId` é o identificador semântico — sem ele não dá pra ler funil
  /// quando o onboarding tem ramos condicionais (caso da refator de 2026-05).
  /// Sempre passar ambos.
  Future<void> onboardingStepReached({
    required int step,
    String? stepId,
  }) =>
      track(evOnboardingStepReached, props: {
        'step': step,
        if (stepId != null) 'step_id': stepId,
      });

  /// Entry do fluxo profile-first. Persiste o timestamp em SharedPrefs
  /// pra que [onboardingCompleted]/[onboardingAbandoned] resolvam
  /// `total_duration_ms` automaticamente sem caller precisar passar.
  Future<void> onboardingStarted({String flowVersion = 'profile_first'}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _kOnboardingStartedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
    return track(evOnboardingStarted, props: {'flow_version': flowVersion});
  }

  /// TwoDoorsScreen ficou visível.
  Future<void> onboardingTwoDoorsShown({String flowVersion = 'profile_first'}) =>
      track(evOnboardingTwoDoorsShown, props: {'flow_version': flowVersion});

  /// Door escolhida. [door] é o critério mais importante de segmentação
  /// downstream — valores válidos: 'upload_cv', 'from_scratch', 'trail'.
  /// (trail = começa pelo CV via gamificação, descoberto no QA Dia 6.)
  /// Persiste a door em SharedPrefs pra que [onboardingCompleted] resolva
  /// automaticamente no final do fluxo (sem caller passar de novo).
  Future<void> onboardingDoorChosen({
    required String door,
    required int timeToDecideMs,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kOnboardingDoorKey, door);
    } catch (_) {}
    return track(evOnboardingDoorChosen, props: {
      'door': door,
      'time_to_decide_ms': timeToDecideMs,
    });
  }

  /// Lê a door persistida pelo [onboardingDoorChosen]. Null se TwoDoors
  /// ainda não foi visto (race condition / fluxo legacy sem TwoDoors).
  Future<String?> resolveOnboardingDoor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kOnboardingDoorKey);
    } catch (_) {
      return null;
    }
  }

  /// Tela de revisão de dados pessoais visível.
  Future<void> onboardingPersonalReviewShown({int? editsPrefilledCount}) =>
      track(evOnboardingPersonalReviewShown, props: {
        if (editsPrefilledCount != null)
          'edits_prefilled_count': editsPrefilledCount,
      });

  /// Campo da revisão pessoal foi editado.
  Future<void> onboardingPersonalFieldEdited({
    required String field,
    int? charDelta,
  }) =>
      track(evOnboardingPersonalFieldEdited, props: {
        'field': field,
        if (charDelta != null) 'char_delta': charDelta,
      });

  Future<void> onboardingPersonalReviewConfirmed({
    required int editsCount,
    required int timeOnScreenMs,
  }) =>
      track(evOnboardingPersonalReviewConfirmed, props: {
        'edits_count': editsCount,
        'time_on_screen_ms': timeOnScreenMs,
      });

  /// Tela de revisão do CV (estrutura completa) visível.
  Future<void> onboardingCvReviewShown({int? sectionsCount}) =>
      track(evOnboardingCvReviewShown, props: {
        if (sectionsCount != null) 'sections_count': sectionsCount,
      });

  Future<void> onboardingCvSectionEdited({
    required String section,
    String? field,
    int? charDelta,
  }) =>
      track(evOnboardingCvSectionEdited, props: {
        'section': section,
        if (field != null) 'field': field,
        if (charDelta != null) 'char_delta': charDelta,
      });

  Future<void> onboardingCvReviewConfirmed({
    required int editsCount,
    required int timeOnScreenMs,
  }) =>
      track(evOnboardingCvReviewConfirmed, props: {
        'edits_count': editsCount,
        'time_on_screen_ms': timeOnScreenMs,
      });

  /// Step de prefs (1..7) visível. [stepName] = chave semântica do step
  /// (work_mode/desired_titles/location/job_types/work_locations/cities/
  /// countries/experience_level).
  Future<void> onboardingPrefStepShown({
    required int step,
    required String stepName,
  }) =>
      track(evOnboardingPrefStepShown, props: {
        'step': step,
        'step_name': stepName,
      });

  Future<void> onboardingPrefStepAnswered({
    required int step,
    required String stepName,
    required int valuesCount,
    int? timeMs,
  }) =>
      track(evOnboardingPrefStepAnswered, props: {
        'step': step,
        'step_name': stepName,
        'values_count': valuesCount,
        if (timeMs != null) 'time_ms': timeMs,
      });

  Future<void> onboardingPrefStepSkipped({
    required int step,
    required String stepName,
  }) =>
      track(evOnboardingPrefStepSkipped, props: {
        'step': step,
        'step_name': stepName,
      });

  /// Tela "All set" (celebração final) visível.
  Future<void> onboardingAllSetShown({
    required int totalDurationMs,
    int? stepsSkipped,
  }) =>
      track(evOnboardingAllSetShown, props: {
        'total_duration_ms': totalDurationMs,
        if (stepsSkipped != null) 'steps_skipped': stepsSkipped,
      });

  /// Onboarding concluído. **ENRIQUECIDO QA Dia 6:** door obrigatório
  /// ('upload_cv'|'from_scratch'|'trail'). `total_duration_ms` é
  /// resolvido automaticamente lendo timestamp persistido por
  /// [onboardingStarted] (sem caller precisar manter state).
  /// `flow_version` default = profile_first (mudou? passar explicitamente).
  Future<void> onboardingCompleted({
    required String door,
    int? editsTotal,
    int? stepsSkipped,
    String flowVersion = 'profile_first',
  }) async {
    final totalDurationMs = await resolveOnboardingDurationMs();
    return track(evOnboardingCompleted, props: {
      'door': door,
      if (totalDurationMs != null) 'total_duration_ms': totalDurationMs,
      'flow_version': flowVersion,
      if (editsTotal != null) 'edits_total': editsTotal,
      if (stepsSkipped != null) 'steps_skipped': stepsSkipped,
    });
  }

  /// User abandonou o onboarding (app fechado/bg/back mid-fluxo).
  /// `time_in_flow_ms` resolvido automaticamente.
  Future<void> onboardingAbandoned({
    required String lastStep,
    String? exitType,
  }) async {
    final timeInFlowMs = await resolveOnboardingDurationMs();
    return track(evOnboardingAbandoned, props: {
      'last_step': lastStep,
      if (timeInFlowMs != null) 'time_in_flow_ms': timeInFlowMs,
      if (exitType != null) 'exit_type': exitType,
    });
  }

  /// Lê o timestamp salvo pelo [onboardingStarted] e calcula a duração
  /// até agora. Retorna null se não houver registro (uso pré-cutover ou
  /// race condition). Público pra que telas intermediárias (All Set, por
  /// exemplo) possam ler a duração corrente sem duplicar o cálculo.
  Future<int?> resolveOnboardingDurationMs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final startedAt = prefs.getInt(_kOnboardingStartedAtKey);
      if (startedAt == null) return null;
      return DateTime.now().millisecondsSinceEpoch - startedAt;
    } catch (_) {
      return null;
    }
  }

  /// Marca milestone de ativação. **Idempotente** — só dispara 1x por
  /// device/milestone (guard em SharedPrefs). Callers podem chamar todo
  /// dia sem risco de duplicar evento. [milestone]:
  /// 'first_swipe', 'first_apply', 'first_adapt', 'first_phase'.
  /// Também propaga `<milestone>_at` na person via $set_once.
  Future<void> activationMilestoneHit({required String milestone}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'analytics_milestone_$milestone';
      if (prefs.getBool(key) == true) return;
      await prefs.setBool(key, true);
      await track(evActivationMilestoneHit, props: {'milestone': milestone});
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Posthog().identify(
          userId: user.id,
          userPropertiesSetOnce: {
            '${milestone}_at': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] activationMilestoneHit failed: $e');
    }
  }

  // ── CV / Resume ─────────────────────────────────────────────────────
  /// Upload de CV iniciado (file picker confirmado).
  ///
  /// [source] diz de QUAL porta o import partiu. Sem ele os 4 call sites
  /// emitiam o mesmo evento indistinguível, e não havia como responder "a
  /// porta nova foi usada?" — a única medição possível seria uma query
  /// point-in-time no banco, que atrasa o sinal. Opcional para não tocar os
  /// call sites existentes (R6).
  Future<void> cvImportStarted({String? source}) => track(
        evOnboardingCvUploadStarted,
        props: source == null ? null : {'source': source},
      );

  /// Upload de CV concluído. `extractedChars` indica quanto texto foi
  /// extraído do PDF antes do parse-cv estruturado (B.7) entrar.
  Future<void> cvImportSucceeded({required int extractedChars}) =>
      track(evOnboardingCvUploadCompleted, props: {'extracted_chars': extractedChars});

  Future<void> cvImportFailed({required String reason}) =>
      track(evOnboardingCvUploadFailed, props: {'reason': reason});

  /// Disparado após `parse-cv` estruturar o raw_text via IA. Sinal
  /// principal pra medir se o parser estruturado está cobrindo bem os
  /// CVs importados — `fields_filled` próximo de 11 (max) indica extração
  /// completa; baixo indica que o pre-parser legacy ainda é necessário.
  Future<void> cvImportParsed({
    required int fieldsFilled,
    required bool cached,
    required bool hasExperiences,
    required bool hasEducation,
  }) =>
      track(evOnboardingProfileExtractionSucceeded, props: {
        'fields_filled': fieldsFilled,
        'cached': cached,
        'has_experiences': hasExperiences,
        'has_education': hasEducation,
      });

  /// Disparado quando uma das chamadas em background (parse-cv ou
  /// parse-cv-vision) falha. `stage` (rasterize / invoke / response) e
  /// `source` (text / vision) dão triagem rápida no PostHog.
  Future<void> cvParserFailed({
    required String source,
    required String stage,
    required String reason,
  }) =>
      track(evOnboardingProfileExtractionFailed, props: {
        'source': source,
        'stage': stage,
        'reason': reason,
      });

  /// Usuário abandonou o caminho IMPORTAR CV no onboarding antes de concluir
  /// o upload/extração. `reason`: 'picker_cancelled' (fechou o seletor de
  /// arquivo), 'file_invalid' (arquivo sem bytes), 'preview_dismissed' (fechou
  /// a prévia sem confirmar). Alimenta o insight "por que param na importação".
  Future<void> onboardingCvImportAbandoned({required String reason}) =>
      track(evOnboardingCvImportAbandoned, props: {'reason': reason});

  /// CV base (resume tab) exportado em PDF. Distinto de
  /// [adaptPdfDownloaded] que é CV adaptado pra vaga específica.
  Future<void> cvExported({required String templateId}) =>
      track(evCvExported, props: {'template_id': templateId});

  /// Versão persistida do Currículo geral salva no export (F4.3). [status] =
  /// 'applied' | 'noop' | 'failed'.
  Future<void> generalResumeVersionSaved({
    required String status,
    required String templateId,
  }) =>
      track(evGeneralResumeVersionSaved,
          props: {'status': status, 'template_id': templateId});

  /// Template trocado na resume tab (CV base).
  Future<void> cvTemplateChanged({required String templateId}) =>
      track(evCvTemplateChanged, props: {'template_id': templateId});

  /// Bottom-sheet de seleção de template do CV base aberto.
  Future<void> cvTemplateSelectorOpened({required String currentTemplateId}) =>
      track(evCvTemplateSelectorOpened, props: {
        'current_template_id': currentTemplateId,
      });

  // ── Senha (settings) ────────────────────────────────────────────────
  Future<void> passwordChanged() => track(evAuthPasswordChanged);

  /// `reason`: `wrong_current`, `weak`, `same`, `reauth_network`,
  /// `update_400`, etc.
  Future<void> passwordChangeFailed({required String reason}) =>
      track(evAuthPasswordChangeFailed, props: {'reason': reason});

  // ── Migração OAuth (users legados de email+senha) ───────────────────
  Future<void> oauthMigrationStarted({required String provider}) =>
      track(evAuthOauthMigrationStarted, props: {'provider': provider});

  Future<void> oauthMigrationCompleted({required String provider}) =>
      track(evAuthOauthMigrationCompleted, props: {'provider': provider});

  Future<void> oauthMigrationFailed({
    required String provider,
    required String reason,
  }) =>
      track(evAuthOauthMigrationFailed, props: {
        'provider': provider,
        'reason': reason,
      });

  // ── Trilha (gamificação) ────────────────────────────────────────────
  // Props extras (phase_title, track_id/title, ordinais, métricas) tornam
  // os eventos legíveis em dashboards sem precisar de lookup table por
  // phase_id. Identificado no QA do Fluxo 6 (2026-05-28): só `phase_id`
  // = "t1_p3" inviabilizava "% conclusão por trilha" e "tempo médio por
  // fase". Todos os params extras são opcionais — callers legados (se
  // houver) seguem funcionando.
  Future<void> trackPhaseStarted({
    required String phaseId,
    String? phaseTitle,
    String? trackId,
    String? trackTitle,
    int? phaseOrderIndex,
  }) =>
      track(evPhaseStarted, props: {
        'phase_id': phaseId,
        if (phaseTitle != null) 'phase_title': phaseTitle,
        if (trackId != null) 'track_id': trackId,
        if (trackTitle != null) 'track_title': trackTitle,
        if (phaseOrderIndex != null) 'phase_order_index': phaseOrderIndex,
      });

  /// XP foi removido do app em 2026-05-06. Param `xpEarned` foi descartado
  /// nesse refactor pra eliminar property zumbi `xp_earned` (anti-padrão
  /// #2 do plano v2).
  ///
  /// `timeSpentMs` = duração desde `phase_started`. `questionsTotal` =
  /// número de steps. `questionsAnswered` = quantos foram respondidos
  /// (= total quando a fase é completada por inteiro; menor quando há
  /// abandono parcial seguido de retorno — caso o `_finishPhase` venha
  /// a permitir isso).
  Future<void> trackPhaseCompleted({
    required String phaseId,
    String? phaseTitle,
    String? trackId,
    String? trackTitle,
    int? phaseOrderIndex,
    int? timeSpentMs,
    int? questionsTotal,
    int? questionsAnswered,
  }) =>
      track(evPhaseCompleted, props: {
        'phase_id': phaseId,
        if (phaseTitle != null) 'phase_title': phaseTitle,
        if (trackId != null) 'track_id': trackId,
        if (trackTitle != null) 'track_title': trackTitle,
        if (phaseOrderIndex != null) 'phase_order_index': phaseOrderIndex,
        if (timeSpentMs != null) 'time_spent_ms': timeSpentMs,
        if (questionsTotal != null) 'questions_total': questionsTotal,
        if (questionsAnswered != null) 'questions_answered': questionsAnswered,
      });

  // ── Vagas ───────────────────────────────────────────────────────────
  /// Mapeado pra `feed_opened` (B.17) com sub_tab="para_voce" por default.
  /// Pra abas diferentes, usar [feedOpened] direto.
  Future<void> jobFeedOpened({required int jobsCount}) => track(evFeedOpened, props: {
        'sub_tab': 'para_voce',
        'jobs_count': jobsCount,
      });

  /// Feed aberto com sub-tab explícita (`para_voce` | `curtidas`).
  Future<void> feedOpened({required String subTab, required int jobsInBuffer}) =>
      track(evFeedOpened, props: {
        'sub_tab': subTab,
        'jobs_in_buffer': jobsInBuffer,
      });

  Future<void> jobSwiped({
    required String jobId,
    required String action, // 'like' | 'reject'
    required int? matchScore,
    String? matchSource, // 'ai' | 'fallback_deterministic' | 'unknown'
    String? matchConfidence, // 'low' | 'medium' | 'high' (MatchConfidence.name)
    String? applicationMethod, // 'email' | 'url' — método de candidatura da vaga
    int? positionInFeed,
    String? companyId,
    String? companyName,
    String? modality,
    String? salaryBucket,
    String? locationBucket,
    int? timeOnCardMs,
    String? feedMode, // 'swipe' | 'list' (Fase 2: save-rate por modo)
    bool? scoreVisible, // T2.4: o que o user VIU (pós-flag e pós-confidence)
    String? holdoutVariant, // T2.4: 'percent'|'hidden'|null (não-elegível)
  }) =>
      track(evJobSwiped, props: {
        'job_id': jobId,
        // Emitimos AMBAS as chaves de direção: 'action' (compat com os ~28k
        // job_swiped históricos e o slide de pitch MJzpsoib) e 'direction'
        // (taxonomia v2). Sem 'action', swipe-right-rate por bucket zera no
        // cutover. Ver memória posthog-audit-remediation (action vs direction).
        'action': action,
        'direction': action,
        if (matchScore != null) 'match_score': matchScore,
        if (matchSource != null) 'match_source': matchSource,
        if (matchConfidence != null) 'match_confidence': matchConfidence,
        if (applicationMethod != null) 'application_method': applicationMethod,
        if (positionInFeed != null) 'position_in_feed': positionInFeed,
        if (companyId != null) 'company_id': companyId,
        // company_name (T3 B2B): permite o slide "Pipeline B2B" mostrar nomes
        // de empresa, não IDs. Só flui pós-build (build antiga não setava).
        if (companyName != null) 'company_name': companyName,
        if (modality != null) 'modality': modality,
        if (salaryBucket != null) 'salary_bucket': salaryBucket,
        if (locationBucket != null) 'location_bucket': locationBucket,
        if (timeOnCardMs != null) 'time_on_card_ms': timeOnCardMs,
        if (feedMode != null) 'feed_mode': feedMode,
        if (scoreVisible != null) 'score_visible': scoreVisible,
        if (holdoutVariant != null) 'holdout_variant': holdoutVariant,
      });

  Future<void> jobDetailsOpened({required String jobId, int? matchScore}) =>
      track(evJobDetailsOpened, props: {
        'job_id': jobId,
        if (matchScore != null) 'match_score': matchScore,
      });

  Future<void> jobShared({required String jobId}) =>
      track(evJobDetailsShareClicked, props: {'job_id': jobId});

  /// **Crítico (audit fix):** carrega `match_score` agora — sem isso, não
  /// dá pra correlacionar bucket de match com conversão (tese B2B).
  /// Callers devem passar o match_score do JobMatchResult do contexto.
  Future<void> jobApplyClicked({
    required String jobId,
    int? matchScore,
    bool? usedAdaptedCv,
    String? applicationMethod, // 'email' | 'url' — método de candidatura da vaga
  }) =>
      track(evJobDetailsApplyClicked, props: {
        'job_id': jobId,
        if (matchScore != null) 'match_score': matchScore,
        if (usedAdaptedCv != null) 'used_adapted_cv': usedAdaptedCv,
        if (applicationMethod != null) 'application_method': applicationMethod,
      });

  /// Fase 3 (T3.4, R7): o browser externo abriu de fato (launchUrl==true) num
  /// apply http(s) — o clique de saída deixa de morrer no PostHog. Reusa a
  /// constante do catálogo que estava sem emissor; mailto NÃO emite (não há
  /// link externo a decorar/rastrear).
  Future<void> jobApplyExternalOpened({
    required String jobId,
    String? jobSource,
  }) =>
      track(evJobDetailsApplyExternalOpened, props: {
        'job_id': jobId,
        if (jobSource != null) 'job_source': jobSource,
      });

  // ── Fase 3 (T3.2): prompt de retorno pós-apply (R7) ─────────────────

  /// Foreground detectou um apply pendente — reusa a constante morta do
  /// catálogo (sem emissor até agora).
  Future<void> jobApplyReturned({required String jobId}) =>
      track(evJobDetailsApplyReturned, props: {'job_id': jobId});

  /// Bottom sheet "Você se candidatou?" exibido.
  Future<void> applyPromptShown({
    required String jobId,
    required bool isReask,
  }) =>
      track(evApplyPromptShown, props: {'job_id': jobId, 'is_reask': isReask});

  /// "Sim" — confirmou a candidatura externa (a application_created é emitida
  /// pela criação no markApplied; este é o marcador do funil do prompt).
  Future<void> applyConfirmed({required String jobId}) =>
      track(evApplyConfirmed, props: {'job_id': jobId});

  /// "Não" + motivo — o dado estratégico de fricção por fonte.
  Future<void> applyAbandonReason({
    required String jobId,
    required String reason,
    String? jobSource,
  }) =>
      track(evApplyAbandonReason, props: {
        'job_id': jobId,
        'reason': reason,
        if (jobSource != null) 'job_source': jobSource,
      });

  // ── Fase 1 — applications (R7: catálogo + emissor no mesmo PR) ──────

  Future<void> applicationCreated({
    required String applicationId,
    required String applicationType, // 'external_confirmed' | 'manual'
    String? jobId,
    String? applicationMethod,
  }) =>
      track(evApplicationCreated, props: {
        'application_id': applicationId,
        'application_type': applicationType,
        if (jobId != null) 'job_id': jobId,
        if (applicationMethod != null) 'application_method': applicationMethod,
      });

  Future<void> applicationStateChanged({
    required String applicationId,
    required String applicationType,
    required String fromStatus,
    required String toStatus,
    String? jobId,
  }) =>
      track(evApplicationStateChanged, props: {
        'application_id': applicationId,
        'application_type': applicationType,
        'from_status': fromStatus,
        'to_status': toStatus,
        if (jobId != null) 'job_id': jobId,
      });

  Future<void> applicationReopened({
    required String applicationId,
    required String applicationType,
    String? jobId,
  }) =>
      track(evApplicationReopened, props: {
        'application_id': applicationId,
        'application_type': applicationType,
        if (jobId != null) 'job_id': jobId,
      });

  /// Mapeado pra `filter_applied` (B.13) com screen="jobs_feed".
  Future<void> jobFiltersApplied({
    required int areasCount,
    required int locationsCount,
    required int? minMatchScore,
  }) =>
      track(evFilterApplied, props: {
        'screen': 'jobs_feed',
        'areas_count': areasCount,
        'locations_count': locationsCount,
        if (minMatchScore != null) 'min_match_score': minMatchScore,
      });

  // ── Adaptação de CV (IA) ────────────────────────────────────────────
  Future<void> cvAdaptationStarted({required String jobId}) =>
      track(evAdaptStarted, props: {'job_id': jobId});

  Future<void> cvAdaptationSucceeded({
    required String jobId,
    required int changesCount,
    required int? scoreBefore,
    required int? scoreAfter,
    required bool cached,
    int? latencyMs,
    String? modelUsed,
  }) =>
      track(evAdaptSucceeded, props: {
        'job_id': jobId,
        'changes_count': changesCount,
        if (scoreBefore != null) 'score_before': scoreBefore,
        if (scoreAfter != null) 'score_after': scoreAfter,
        'cached': cached,
        // latency_ms: round-trip do client (stopwatch). cost_usd fica em
        // $ai_generation (fonte canônica) — não duplicamos aqui.
        if (latencyMs != null) 'latency_ms': latencyMs,
        if (modelUsed != null) 'model_used': modelUsed,
      });

  Future<void> cvAdaptationFailed({required String jobId, required String code}) =>
      track(evAdaptFailed, props: {'job_id': jobId, 'error_code': code});

  Future<void> cvAdaptationPdfDownloaded({required String jobId}) =>
      track(evAdaptPdfDownloaded, props: {'job_id': jobId});

  /// Save no library falhou. Não-fatal (user ainda recebe PDF via share)
  /// mas indica que o histórico não vai aparecer na biblioteca.
  Future<void> cvLibrarySaveFailed({
    required String jobId,
    required String error,
  }) =>
      track(evCvLibrarySaveFailed, props: {
        'job_id': jobId,
        'error': error.length > 200 ? error.substring(0, 200) : error,
      });

  /// **Sinal crítico de qualidade IA:** usuário editou o CV adaptado pós-IA.
  /// Alta taxa de edit = IA fraca. Mapeado pra `adapt_section_edited_manually`.
  ///
  /// [field]: `summary`, `skills`, `experience.{i}.description`, etc.
  /// [editType]: `replace` (substituiu texto), `restore_original` (voltou ao
  ///   original), `clear` (esvaziou campo).
  /// [charDiff]: diferença em caracteres entre antes e depois.
  Future<void> cvAdaptationUserEdited({
    required String jobId,
    required String field,
    required String editType,
    required int charDiff,
  }) =>
      track(evAdaptSectionEditedManually, props: {
        'job_id': jobId,
        'field': field,
        'edit_type': editType,
        'char_diff': charDiff,
      });

  // ── Confirmação de skills antes da adaptação ────────────────────────
  Future<void> skillsConfirmationOpened({
    required String jobId,
    required int totalSkills,
    required int missingFromCv,
  }) =>
      track(evAdaptSkillsConfirmationShown, props: {
        'job_id': jobId,
        'total_skills': totalSkills,
        'missing_from_cv': missingFromCv,
      });

  Future<void> skillsConfirmationCompleted({
    required String jobId,
    required int confirmed,
    required bool skipped,
  }) =>
      track(evAdaptSkillsConfirmationCompleted, props: {
        'job_id': jobId,
        'confirmed': confirmed,
        'skipped': skipped,
      });

  /// `reason`: 'all_in_cv' | 'no_cv' | 'no_requirements' | 'extraction_failed'
  Future<void> skillsConfirmationAutoSkipped({
    required String jobId,
    required String reason,
  }) =>
      track(evAdaptSkillsConfirmationAutoSkipped, props: {
        'job_id': jobId,
        'reason': reason,
      });

  // ── Feedback / Founders ─────────────────────────────────────────────
  Future<void> foundersContactOpened({required String channel}) =>
      track(evFoundersContactOpened, props: {'channel': channel});

  // ── Swipe granular (B.14) ───────────────────────────────────────────

  /// Vaga entrou na tela do feed (revealed preference). Distinto de
  /// `job_swiped` — captura exposição mesmo sem decisão. Audit fix
  /// crítico: sem isso, "vagas vistas mas não swipadas" era invisível.
  Future<void> jobCardShown({
    required String jobId,
    required int matchScore,
    required int positionInFeed,
    String? companyId,
    String? area,
    String? modality,
    String? salaryBucket,
    String? locationBucket,
    String? feedMode, // 'swipe' | 'list' (Fase 2: exposição por modo)
    bool? scoreVisible, // T2.4: o que o user VIU (pós-flag e pós-confidence)
    String? holdoutVariant, // T2.4: 'percent'|'hidden'|null (não-elegível)
  }) =>
      track(evJobCardShown, props: {
        'job_id': jobId,
        'match_score': matchScore,
        'position_in_feed': positionInFeed,
        if (companyId != null) 'company_id': companyId,
        if (area != null) 'area': area,
        if (modality != null) 'modality': modality,
        if (salaryBucket != null) 'salary_bucket': salaryBucket,
        if (locationBucket != null) 'location_bucket': locationBucket,
        if (feedMode != null) 'feed_mode': feedMode,
        if (scoreVisible != null) 'score_visible': scoreVisible,
        if (holdoutVariant != null) 'holdout_variant': holdoutVariant,
      });

  /// Pareado com [jobCardDwellEnded]. Marca instante em que card entrou.
  Future<void> jobCardDwellStarted({required String jobId}) =>
      track(evJobCardDwellStarted, props: {'job_id': jobId});

  /// Card saiu da tela (swiped ou tap em detalhes). [decision]:
  /// 'swipe_left', 'swipe_right', 'tap_details', 'skip_no_action'.
  Future<void> jobCardDwellEnded({
    required String jobId,
    required int durationMs,
    required String decision,
  }) =>
      track(evJobCardDwellEnded, props: {
        'job_id': jobId,
        'duration_ms': durationMs,
        'decision': decision,
      });

  /// Burst de swipes — >X em janela curta. Sinal de "esmagador"
  /// (provavelmente uso não-engajado, candidato pra exclusão de cohort
  /// power user).
  Future<void> jobBulkSwipeBurst({
    required int swipesCount,
    required int windowMs,
    double? avgVelocity,
  }) =>
      track(evJobBulkSwipeBurst, props: {
        'swipes_count': swipesCount,
        'window_ms': windowMs,
        if (avgVelocity != null) 'avg_velocity': avgVelocity,
      });

  /// Vaga revisitada na aba Curtidas após salvamento. Interesse latente.
  Future<void> jobRevisitedFromCurtidas({
    required String jobId,
    required int viewCountTotal,
    int? daysSinceFirstSave,
  }) =>
      track(evJobRevisitedFromCurtidas, props: {
        'job_id': jobId,
        'view_count_total': viewCountTotal,
        if (daysSinceFirstSave != null)
          'days_since_first_save': daysSinceFirstSave,
      });

  Future<void> jobSwipeUndo({
    required String jobId,
    required String directionUndone,
    int? timeToUndoMs,
  }) =>
      track(evJobSwipeUndo, props: {
        'job_id': jobId,
        'direction_undone': directionUndone,
        if (timeToUndoMs != null) 'time_to_undo_ms': timeToUndoMs,
      });

  // ── Adapt granular (B.15) — eventos faltando além dos já existentes ─

  /// Diff entre CV original e adaptado visível na tela. Pareado com
  /// `adapt_diff_scroll_progress` (não implementado por ora — precisa
  /// instrumentação no widget de diff).
  Future<void> adaptIntentClicked({
    required String jobId,
    required int matchScore,
    String? source,
  }) =>
      track(evAdaptIntentClicked, props: {
        'job_id': jobId,
        'match_score': matchScore,
        if (source != null) 'source': source,
      });

  Future<void> adaptDiffShown({
    required String jobId,
    required int bulletsChangedCount,
    int? additionsCount,
  }) =>
      track(evAdaptDiffShown, props: {
        'job_id': jobId,
        'bullets_changed_count': bulletsChangedCount,
        if (additionsCount != null) 'additions_count': additionsCount,
      });

  Future<void> adaptDiffScrollProgress({
    required String jobId,
    required int maxScrollPct,
    int? timeMs,
  }) =>
      track(evAdaptDiffScrollProgress, props: {
        'job_id': jobId,
        'max_scroll_pct': maxScrollPct,
        if (timeMs != null) 'time_ms': timeMs,
      });

  /// Skill confirmation modal mostrado. Pareado com accept/reject.
  Future<void> adaptSkillsConfirmationShown({
    required String jobId,
    required int suggestionsCount,
  }) =>
      track(evAdaptSkillsConfirmationShown, props: {
        'job_id': jobId,
        'suggestions_count': suggestionsCount,
      });

  /// User aceitou uma skill sugerida pela IA. Pareado com [adaptSkillRejected]
  /// e [adaptSkillAddedManually] pra construir o funil de skills.
  Future<void> adaptSkillAccepted({
    required String jobId,
    required String skillName,
  }) =>
      track(evAdaptSkillAccepted, props: {
        'job_id': jobId,
        'skill_name': skillName,
      });

  /// User rejeitou skill sugerida = sinal forte de invenção da IA.
  /// Métrica crítica de qualidade.
  Future<void> adaptSkillRejected({
    required String jobId,
    required String skillName,
  }) =>
      track(evAdaptSkillRejected, props: {
        'job_id': jobId,
        'skill_name': skillName,
      });

  Future<void> adaptSkillAddedManually({
    required String jobId,
    required String skillName,
  }) =>
      track(evAdaptSkillAddedManually, props: {
        'job_id': jobId,
        'skill_name': skillName,
      });

  /// User abandonou o fluxo de adapt sem completar (back/bg/kill).
  Future<void> adaptAbandoned({
    required String jobId,
    required String lastStep,
    int? timeInFlowMs,
  }) =>
      track(evAdaptAbandoned, props: {
        'job_id': jobId,
        'last_step': lastStep,
        if (timeInFlowMs != null) 'time_in_flow_ms': timeInFlowMs,
      });

  /// Apply na vaga após adapt — fecha o loop adapt→apply (métrica
  /// principal do funil B.15).
  Future<void> adaptApplyUsed({
    required String jobId,
    required int timeFromDownloadToApplyMs,
  }) =>
      track(evAdaptApplyUsed, props: {
        'job_id': jobId,
        'time_from_download_to_apply_ms': timeFromDownloadToApplyMs,
      });

  // ── Trilha granular (B.16) — gap crítico do audit ───────────────────
  // Antes do cutover, trilha era caixa-preta: só phase_started/completed,
  // invisível o "minuto 4 da fase 3 onde a maioria larga".

  /// Mapa da trilha (5 fases) renderizado.
  Future<void> trilhaMapShown({
    required int phasesCompleted,
    required int phasesTotal,
  }) =>
      track(evTrilhaMapShown, props: {
        'phases_completed': phasesCompleted,
        'phases_total': phasesTotal,
      });

  /// User tocou em fase bloqueada — curiosidade OU frustração.
  Future<void> trilhaPhaseLockedTapped({required String phaseId}) =>
      track(evTrilhaPhaseLockedTapped, props: {'phase_id': phaseId});

  /// Step dentro de uma fase apareceu. Granular = visibilidade real.
  /// [stepIndex] 0-based; [stepType]: 'content', 'quiz', 'action'.
  Future<void> phaseStepShown({
    required String phaseId,
    required String stepId,
    required int stepIndex,
    String? stepType,
  }) =>
      track(evPhaseStepShown, props: {
        'phase_id': phaseId,
        'step_id': stepId,
        'step_index': stepIndex,
        if (stepType != null) 'step_type': stepType,
      });

  /// Step completado (user avançou pro próximo).
  Future<void> phaseStepCompleted({
    required String phaseId,
    required String stepId,
    required int durationMs,
  }) =>
      track(evPhaseStepCompleted, props: {
        'phase_id': phaseId,
        'step_id': stepId,
        'duration_ms': durationMs,
      });

  /// User saiu da fase no meio de um step (background/back/kill).
  /// [lastPct]: % do step que viu antes de sair.
  Future<void> phaseStepAbandoned({
    required String phaseId,
    required String stepId,
    int? lastPct,
    int? durationMs,
  }) =>
      track(evPhaseStepAbandoned, props: {
        'phase_id': phaseId,
        'step_id': stepId,
        if (lastPct != null) 'last_pct': lastPct,
        if (durationMs != null) 'duration_ms': durationMs,
      });

  /// Quiz answered, [correct] = user acertou na primeira tentativa.
  Future<void> phaseQuizAnswered({
    required String phaseId,
    required String quizId,
    required int qIndex,
    required bool correct,
    int? attempt,
  }) =>
      track(evPhaseQuizAnswered, props: {
        'phase_id': phaseId,
        'quiz_id': quizId,
        'q_index': qIndex,
        'correct': correct,
        if (attempt != null) 'attempt': attempt,
      });

  /// Trilha 100% concluída (passou pela última fase).
  Future<void> trilhaCompleted({
    required int totalDays,
    required int phasesCount,
  }) =>
      track(evTrilhaCompleted, props: {
        'total_days': totalDays,
        'phases_count': phasesCount,
      });

  /// CV final (extraído da última fase) baixado.
  Future<void> trilhaCvFinalDownloaded({
    required String template,
    double? completenessScore,
  }) =>
      track(evTrilhaCvFinalDownloaded, props: {
        'template': template,
        if (completenessScore != null) 'completeness_score': completenessScore,
      });

  // ── Feed gerais (B.17) ──────────────────────────────────────────────

  /// Feed terminou de carregar (com sub_tab + duration + cache hit).
  /// [subTab]: 'para_voce' | 'curtidas'.
  /// (REV-1) [feedSource] 'rpc'|'legacy': sem ela o aceite P50 da Fase 2
  /// não filtra rota nova×antiga ([feedMode] distingue lista×swipe, e o
  /// swipe com flag ON também usa RPC).
  Future<void> feedLoaded({
    required String subTab,
    required int jobsCount,
    int? loadDurationMs,
    bool? cacheHit,
    String? feedSource, // 'rpc' | 'legacy'
    String? feedMode, // 'swipe' | 'list'
  }) =>
      track(evFeedLoaded, props: {
        'sub_tab': subTab,
        'jobs_count': jobsCount,
        if (loadDurationMs != null) 'load_duration_ms': loadDurationMs,
        if (cacheHit != null) 'cache_hit': cacheHit,
        if (feedSource != null) 'feed_source': feedSource,
        if (feedMode != null) 'feed_mode': feedMode,
      });

  /// Feed falhou em carregar.
  Future<void> feedLoadFailed({
    required String subTab,
    required String errorCode,
    int? retry,
  }) =>
      track(evFeedLoadFailed, props: {
        'sub_tab': subTab,
        'error_code': errorCode,
        if (retry != null) 'retry': retry,
      });

  /// User chegou ao fim do feed (acabaram as vagas pra hoje).
  Future<void> feedExhausted({
    required String subTab,
    required int jobsSeenInSession,
    int? jobsSwipedInSession,
    String? feedMode, // 'swipe' | 'list' (Fase 2: aceite #6, exaustão por modo)
  }) =>
      track(evFeedExhausted, props: {
        'sub_tab': subTab,
        'jobs_seen_in_session': jobsSeenInSession,
        if (jobsSwipedInSession != null)
          'jobs_swiped_in_session': jobsSwipedInSession,
        if (feedMode != null) 'feed_mode': feedMode,
      });

  /// FASE 2 (T2.2): toggle swipe↔lista da aba Vagas (flag feed_list_v1).
  Future<void> feedModeToggled({required String mode}) =>
      track(evFeedModeToggled, props: {'mode': mode});

  /// FASE 2 (T2.3): pedido de empresa no estado de exaustão do feed.
  Future<void> companyRequested({
    required String companyName,
    required bool hasNote,
    required String feedMode,
  }) =>
      track(evCompanyRequested, props: {
        'company_name': companyName,
        'has_note': hasNote,
        'feed_mode': feedMode,
      });

  /// User puxou pra atualizar.
  Future<void> feedRefreshPulled({
    required String subTab,
    int? timeSinceLastLoadMs,
  }) =>
      track(evFeedRefreshPulled, props: {
        'sub_tab': subTab,
        if (timeSinceLastLoadMs != null)
          'time_since_last_load_ms': timeSinceLastLoadMs,
      });

  // ── Aquisição & atribuição (B.8) ────────────────────────────────────

  /// Captura de install attribution. Disparar 1x no $set_once do primeiro
  /// boot. Sem isso, ROI Meta/PUC é cego.
  Future<void> installAttributed({
    String? utmSource,
    String? utmMedium,
    String? utmCampaign,
    String? utmContent,
    String? utmTerm,
    String? referrer,
  }) =>
      track(evInstallAttributed, props: {
        if (utmSource != null) 'utm_source': utmSource,
        if (utmMedium != null) 'utm_medium': utmMedium,
        if (utmCampaign != null) 'utm_campaign': utmCampaign,
        if (utmContent != null) 'utm_content': utmContent,
        if (utmTerm != null) 'utm_term': utmTerm,
        if (referrer != null) 'referrer': referrer,
      });

  Future<void> deepLinkOpened({
    required String url,
    String? sourceApp,
    String? targetScreen,
  }) =>
      track(evDeepLinkOpened, props: {
        'url': url,
        if (sourceApp != null) 'source_app': sourceApp,
        if (targetScreen != null) 'target_screen': targetScreen,
      });

  Future<void> deepLinkFailedToResolve({
    required String url,
    required String error,
  }) =>
      track(evDeepLinkFailedToResolve, props: {
        'url': url,
        'error': error,
      });

  /// QR code scaneado (cartazes PUC, materiais físicos, etc).
  /// [sourceLabel] identifica o cartaz (`puc_cartaz_a4_v1`, `ad_meta_01`).
  Future<void> qrCodeScanned({required String sourceLabel}) =>
      track(evQrCodeScanned, props: {'source_label': sourceLabel});

  Future<void> firstSessionAttribution({
    required String channel,
    String? campaign,
  }) =>
      track(evFirstSessionAttribution, props: {
        'channel': channel,
        if (campaign != null) 'campaign': campaign,
      });

  // ── Share & viralidade (B.9) ────────────────────────────────────────

  /// Sheet nativa de share aberta. [contentType] = job/cv/app/trilha_completed.
  Future<void> shareSheetOpened({
    required String contentType,
    String? sourceScreen,
  }) =>
      track(evShareSheetOpened, props: {
        'content_type': contentType,
        if (sourceScreen != null) 'source_screen': sourceScreen,
      });

  /// Share completou efetivamente (callback do sheet). [method]: whatsapp,
  /// copy, sms, email, instagram, other.
  Future<void> shareCompleted({
    required String contentType,
    required String method,
  }) =>
      track(evShareCompleted, props: {
        'content_type': contentType,
        'method': method,
      });

  Future<void> shareCancelled({
    required String contentType,
    String? sourceScreen,
    int? timeOpenMs,
  }) =>
      track(evShareCancelled, props: {
        'content_type': contentType,
        if (sourceScreen != null) 'source_screen': sourceScreen,
        if (timeOpenMs != null) 'time_open_ms': timeOpenMs,
      });

  /// Deep link de convite gerado e copiado/compartilhado. Pareado com
  /// `invite_link_opened_inbound` no destinatário pra calcular k-factor.
  Future<void> inviteLinkGenerated({
    required String inviteId,
    required String contentType,
  }) =>
      track(evInviteLinkGenerated, props: {
        'invite_id': inviteId,
        'content_type': contentType,
      });

  Future<void> inviteLinkOpenedInbound({
    required String inviteId,
    required bool receiverFirstOpen,
  }) =>
      track(evInviteLinkOpenedInbound, props: {
        'invite_id': inviteId,
        'receiver_first_open': receiverFirstOpen,
      });

  // ── Tutorial & discovery (B.11) ─────────────────────────────────────

  Future<void> tutorialStarted({required String flow}) =>
      track(evTutorialStarted, props: {'flow': flow});

  Future<void> tutorialStepShown({
    required String flow,
    required int step,
    String? targetId,
  }) =>
      track(evTutorialStepShown, props: {
        'flow': flow,
        'step': step,
        if (targetId != null) 'target_id': targetId,
      });

  Future<void> tutorialStepDismissed({
    required String flow,
    required int step,
  }) =>
      track(evTutorialStepDismissed, props: {'flow': flow, 'step': step});

  Future<void> tutorialCompleted({
    required String flow,
    required int durationMs,
    String? nextAction,
  }) =>
      track(evTutorialCompleted, props: {
        'flow': flow,
        'duration_ms': durationMs,
        if (nextAction != null) 'next_action': nextAction,
      });

  Future<void> tutorialSkipped({
    required String flow,
    String? skipMethod,
  }) =>
      track(evTutorialSkipped, props: {
        'flow': flow,
        if (skipMethod != null) 'skip_method': skipMethod,
      });

  /// Disparar 1x ($set_once) na primeira vez que o usuário usa uma feature.
  /// [featureId]: 'adapt', 'trilha_phase_1', 'cv_export', etc.
  Future<void> featureFirstUsed({
    required String featureId,
    int? daysSinceSignup,
  }) =>
      track(evFeatureFirstUsed, props: {
        'feature_id': featureId,
        if (daysSinceSignup != null) 'days_since_signup': daysSinceSignup,
      });

  Future<void> helpLinkClicked({
    required String sourceScreen,
    required String linkTarget,
  }) =>
      track(evHelpLinkClicked, props: {
        'source_screen': sourceScreen,
        'link_target': linkTarget,
      });

  Future<void> feedbackFormOpened({required String sourceScreen}) =>
      track(evFeedbackFormOpened, props: {'source_screen': sourceScreen});

  /// NPS proxy. [rating] 0-10; [hasEmail] true se user deixou contato.
  Future<void> feedbackSubmitted({
    required int rating,
    required int charCount,
    required bool hasEmail,
  }) =>
      track(evFeedbackSubmitted, props: {
        'rating': rating,
        'char_count': charCount,
        'has_email': hasEmail,
      });

  // ── Monetização proativa B2B (B.12) ─────────────────────────────────
  // Stubs sem caller hoje. Existem pra capturar instintos futuros (paywall,
  // pricing, b2b_dashboard) sem precisar mexer na taxonomia.

  Future<void> b2bCompanyRegistered({
    required String companyId,
    String? source,
  }) =>
      track(evB2bCompanyRegistered, props: {
        'company_id': companyId,
        if (source != null) 'source': source,
      });

  Future<void> b2bJobPublished({
    required String companyId,
    required String jobId,
  }) =>
      track(evB2bJobPublished, props: {
        'company_id': companyId,
        'job_id': jobId,
      });

  Future<void> b2bCandidateViewed({
    required String companyId,
    required String candidateId,
    int? matchScore,
  }) =>
      track(evB2bCandidateViewed, props: {
        'company_id': companyId,
        'candidate_id': candidateId,
        if (matchScore != null) 'match_score': matchScore,
      });

  Future<void> b2bCandidateContacted({
    required String companyId,
    required String candidateId,
    required String channel,
  }) =>
      track(evB2bCandidateContacted, props: {
        'company_id': companyId,
        'candidate_id': candidateId,
        'channel': channel,
      });

  // ── Navegação & UI granular (B.13) ──────────────────────────────────

  /// Substituiu o legacy `profile_tab_changed` no cutover. Tab=índice
  /// numérico OU nome semântico (preferir nome).
  Future<void> navTabSwitched({
    required String fromTab,
    required String toTab,
    int? durationOnFromMs,
  }) =>
      track(evNavTabSwitched, props: {
        'from_tab': fromTab,
        'to_tab': toTab,
        if (durationOnFromMs != null) 'duration_on_from_ms': durationOnFromMs,
      });

  Future<void> modalOpened({
    required String modalId,
    String? source,
  }) =>
      track(evModalOpened, props: {
        'modal_id': modalId,
        if (source != null) 'source': source,
      });

  Future<void> modalClosed({
    required String modalId,
    int? durationMs,
    String? method,
  }) =>
      track(evModalClosed, props: {
        'modal_id': modalId,
        if (durationMs != null) 'duration_ms': durationMs,
        if (method != null) 'method': method,
      });

  // ── Push lifecycle (B.10) ───────────────────────────────────────────
  // OneSignal Flutter SDK v5 expõe 3 callbacks úteis:
  //   - addForegroundWillDisplayListener → `push_displayed` (foreground)
  //   - addClickListener → `push_opened` (foreground+background)
  //   - addPermissionObserver → permission state change
  // NÃO há callback Flutter pra notification chegando em background (iOS
  // entrega nativamente sem rodar Dart); `push_received_background` fica
  // de fora até termos extensão nativa. `push_dismissed` idem.

  /// Notificação foi exibida na tela (foreground delivery do OneSignal).
  Future<void> pushDisplayed({
    required String campaignId,
    required String type,
  }) =>
      track(evPushDisplayed, props: {
        'campaign_id': campaignId,
        'type': type,
      });

  /// Usuário tocou na notificação (foreground ou background). Audit fix
  /// crítico — sem isso, reativação por push era caixa-preta.
  /// [timeFromSendMs] pode ser null se o payload não trouxer `sentAt`.
  Future<void> pushOpened({
    required String campaignId,
    required String type,
    int? timeFromSendMs,
  }) =>
      track(evPushOpened, props: {
        'campaign_id': campaignId,
        'type': type,
        if (timeFromSendMs != null) 'time_from_send_ms': timeFromSendMs,
      });

  /// Prompt nativo iOS/Android foi solicitado pelo app.
  Future<void> pushPermissionRequested({required String sourceScreen}) =>
      track(evPushPermissionRequested, props: {'source_screen': sourceScreen});

  /// Permission concedida (transição → granted).
  Future<void> pushPermissionGranted() => track(evPushPermissionGranted);

  /// Permission negada (transição → denied). [askCount] = quantas vezes
  /// já mostramos o prompt antes (lido de SharedPrefs).
  Future<void> pushPermissionDenied({int? askCount}) =>
      track(evPushPermissionDenied, props: {
        if (askCount != null) 'ask_count': askCount,
      });

  /// Permission tinha sido granted, virou denied (revogada via Settings.app).
  Future<void> pushPermissionRevokedDetected({int? daysSinceGrant}) =>
      track(evPushPermissionRevokedDetected, props: {
        if (daysSinceGrant != null) 'days_since_grant': daysSinceGrant,
      });
}

/// Alias curto pra acesso global. Use `Analytics.shared.jobSwiped(...)`.
typedef Analytics = AnalyticsService;

/// Observer privado que escuta mudanças de `AppLifecycleState` e
/// delega pros handlers de [AnalyticsService]. Permite que o
/// AnalyticsService permaneça uma classe regular (não-mixin) enquanto
/// ainda participa do ciclo de vida do app.
class _AnalyticsLifecycleObserver with WidgetsBindingObserver {
  final AnalyticsService _service;
  // iOS dispara didChangeAppLifecycleState DUAS vezes na transição
  // foreground → background (uma com `hidden`, outra com `paused`, ~2ms
  // apart). Sem guard, `app_backgrounded` virava duplicado em produção.
  // Flag reseta no próximo `resumed` pra próximo ciclo emitir normal.
  bool _isBackgrounded = false;
  _AnalyticsLifecycleObserver(this._service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_isBackgrounded) break;
        _isBackgrounded = true;
        // ignore: unawaited_futures
        _service._onBackgrounded();
        break;
      case AppLifecycleState.resumed:
        _isBackgrounded = false;
        // ignore: unawaited_futures
        _service._onForegrounded();
        break;
      case AppLifecycleState.detached:
        // ignore: unawaited_futures
        _service._onAppTerminated();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }
}
