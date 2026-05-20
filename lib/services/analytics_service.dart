import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Inicializa o serviço. Chamado uma vez em `main()` após `WidgetsFlutterBinding.ensureInitialized()`.
  /// Sem isso, todos os `track()` viram no-op (loga warning em debug).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (kDebugMode) {
      debugPrint('[Analytics] init — debug mode, eventos visíveis no console PostHog');
    }
    // Race condition guard: se o user já está logado quando o Analytics
    // inicializa (cold start com session restaurada), identify imediatamente.
    // Sem isso, o evento `initialSession` do Supabase pode disparar ANTES do
    // PostHog estar pronto e a identificação se perde.
    await identifyIfLoggedIn();
  }

  /// Lê a sessão atual do Supabase e chama [identify] se houver user logado.
  /// Idempotente — pode ser chamado várias vezes.
  Future<void> identifyIfLoggedIn() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      await identify(user.id, properties: {
        if (user.email != null) 'email': user.email!,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] identifyIfLoggedIn failed: $e');
    }
  }

  /// Track de evento genérico. Use os helpers tipados abaixo sempre que possível.
  Future<void> track(String event, {Map<String, Object>? props}) async {
    if (!_initialized) {
      if (kDebugMode) debugPrint('[Analytics] WARN: track antes de init: $event');
      return;
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
  Future<void> identify(String userId, {Map<String, Object>? properties}) async {
    if (!_initialized) return;
    try {
      await Posthog().identify(userId: userId, userProperties: properties);
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
      await Posthog().capture(
        eventName: r'$exception',
        properties: {
          r'$exception_type': exceptionType,
          r'$exception_message': exceptionMessage,
          if (stackString.isNotEmpty) r'$exception_stack_trace_raw': stackString,
          r'$exception_personURL': '',
          r'$exception_handled': handled,
          if (extra != null) ...extra,
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] captureException failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Eventos tipados — adicionar novos aqui pra manter consistência.
  // ════════════════════════════════════════════════════════════════════

  // ── App lifecycle ───────────────────────────────────────────────────
  /// Dispara no boot do app (chamado em main.dart). Esse é o evento base
  /// pra calcular DAU/MAU — o auto-capture do PostHog Flutter é instável
  /// dependendo da versão, então emitimos manualmente.
  Future<void> appOpened() => track('app_opened');

  /// Dispara `$screen` com `screen_name` real. O `PosthogObserver` em
  /// main.dart só captura rotas nomeadas — como a navegação do Stage é
  /// 100% imperativa (Navigator.push sem RouteSettings.name), o observer
  /// cai sempre em `root('/')`. Por isso emitimos manualmente do initState
  /// de cada tela principal via [ScreenTrackingMixin].
  Future<void> screen(String name, {Map<String, Object>? properties}) async {
    if (!_initialized) return;
    try {
      await Posthog().screen(screenName: name, properties: properties);
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] screen failed: $e');
    }
  }

  // ── Auth & Onboarding ───────────────────────────────────────────────
  Future<void> signUpCompleted({required String method}) =>
      track('sign_up_completed', props: {'method': method});

  Future<void> loginCompleted({required String method}) =>
      track('login_completed', props: {'method': method});

  Future<void> logoutCompleted() => track('logout_completed');

  /// Disparado no início de `signInWithApple()`. Combinado com
  /// `apple_signin_failed` (catch) e `sign_up_completed`/`login_completed`
  /// (listener), dá pra calcular a taxa de abandono no flow Apple Sign-In.
  Future<void> appleSigninStarted() => track('apple_signin_started');

  /// `code`: 'cancelled', 'token_missing', 'unknown'. Diferencia abandono
  /// (cancelled pelo usuário no diálogo iOS) vs falha técnica.
  Future<void> appleSigninFailed({required String code}) =>
      track('apple_signin_failed', props: {'code': code});

  /// `step` é a ordem numérica (legacy, mantido pra continuidade de dashboards).
  /// `stepId` é o identificador semântico — sem ele não dá pra ler funil
  /// quando o onboarding tem ramos condicionais (caso da refator de 2026-05).
  /// Sempre passar ambos.
  Future<void> onboardingStepReached({
    required int step,
    String? stepId,
  }) =>
      track('onboarding_step_reached', props: {
        'step': step,
        if (stepId != null) 'step_id': stepId,
      });

  Future<void> onboardingCompleted() => track('onboarding_completed');

  Future<void> onboardingSkipped({required int atStep}) =>
      track('onboarding_skipped', props: {'at_step': atStep});

  // ── CV / Resume ─────────────────────────────────────────────────────
  Future<void> cvImportStarted() => track('cv_import_started');

  Future<void> cvImportSucceeded({required int extractedChars}) =>
      track('cv_import_succeeded', props: {'extracted_chars': extractedChars});

  Future<void> cvImportFailed({required String reason}) =>
      track('cv_import_failed', props: {'reason': reason});

  Future<void> cvExported({required String templateId}) =>
      track('cv_exported', props: {'template_id': templateId});

  Future<void> cvTemplateChanged({required String templateId}) =>
      track('cv_template_changed', props: {'template_id': templateId});

  /// Disparado quando o bottom-sheet de seleção de template abre. Combinado
  /// com `cv_template_changed`, dá pra medir taxa de troca de template e
  /// validar se o preview visual reduz tentativa-e-erro (hipótese da feature
  /// de thumbnails, baseada em feedback de usuário em 2026-05).
  Future<void> cvTemplateSelectorOpened({required String currentTemplateId}) =>
      track('cv_template_selector_opened', props: {
        'current_template_id': currentTemplateId,
      });

  // ── Trilha (gamificação) ────────────────────────────────────────────
  Future<void> trackPhaseStarted({required String phaseId}) =>
      track('phase_started', props: {'phase_id': phaseId});

  Future<void> trackPhaseCompleted({required String phaseId, required int xpEarned}) =>
      track('phase_completed', props: {'phase_id': phaseId, 'xp_earned': xpEarned});

  // ── Vagas ───────────────────────────────────────────────────────────
  Future<void> jobFeedOpened({required int jobsCount}) =>
      track('job_feed_opened', props: {'jobs_count': jobsCount});

  Future<void> jobSwiped({
    required String jobId,
    required String action, // 'like' | 'reject'
    required int? matchScore,
    String? matchSource, // 'ai' | 'fallback_deterministic' | 'unknown'
  }) =>
      track('job_swiped', props: {
        'job_id': jobId,
        'action': action,
        if (matchScore != null) 'match_score': matchScore,
        if (matchSource != null) 'match_source': matchSource,
      });

  Future<void> jobDetailsOpened({required String jobId}) =>
      track('job_details_opened', props: {'job_id': jobId});

  Future<void> jobShared({required String jobId}) =>
      track('job_shared', props: {'job_id': jobId});

  Future<void> jobApplyClicked({required String jobId}) =>
      track('job_apply_clicked', props: {'job_id': jobId});

  Future<void> jobFiltersApplied({
    required int areasCount,
    required int locationsCount,
    required int? minMatchScore,
    required int? minSalary,
  }) =>
      track('job_filters_applied', props: {
        'areas_count': areasCount,
        'locations_count': locationsCount,
        if (minMatchScore != null) 'min_match_score': minMatchScore,
        if (minSalary != null) 'min_salary': minSalary,
      });

  // ── Adaptação de CV (IA) ────────────────────────────────────────────
  Future<void> cvAdaptationStarted({required String jobId}) =>
      track('cv_adaptation_started', props: {'job_id': jobId});

  Future<void> cvAdaptationSucceeded({
    required String jobId,
    required int changesCount,
    required int? scoreBefore,
    required int? scoreAfter,
    required bool cached,
  }) =>
      track('cv_adaptation_succeeded', props: {
        'job_id': jobId,
        'changes_count': changesCount,
        if (scoreBefore != null) 'score_before': scoreBefore,
        if (scoreAfter != null) 'score_after': scoreAfter,
        'cached': cached,
      });

  Future<void> cvAdaptationFailed({required String jobId, required String code}) =>
      track('cv_adaptation_failed', props: {'job_id': jobId, 'code': code});

  Future<void> cvAdaptationPdfDownloaded({required String jobId}) =>
      track('cv_adaptation_pdf_downloaded', props: {'job_id': jobId});

  /// Disparado quando o usuário edita um campo do CV adaptado na tela de
  /// preview (F1 da reformulação). Sinal mais valioso pra entender onde a
  /// IA está errando segundo a percepção humana — alimenta o dashboard de
  /// quality_score (F7) e o validador semântico (F6).
  ///
  /// [field]: nome do campo editado (`summary`, `skills`, `experience.{i}.description`, ...).
  /// [editType]: `replace` (substituiu texto), `restore_original` (voltou ao original),
  ///             `clear` (esvaziou campo).
  /// [charDiff]: diferença em caracteres entre antes e depois (positiva = adicionou).
  Future<void> cvAdaptationUserEdited({
    required String jobId,
    required String field,
    required String editType,
    required int charDiff,
  }) =>
      track('cv_adaptation_user_edited', props: {
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
      track('skills_confirmation_opened', props: {
        'job_id': jobId,
        'total_skills': totalSkills,
        'missing_from_cv': missingFromCv,
      });

  Future<void> skillsConfirmationCompleted({
    required String jobId,
    required int confirmed,
    required bool skipped,
  }) =>
      track('skills_confirmation_completed', props: {
        'job_id': jobId,
        'confirmed': confirmed,
        'skipped': skipped,
      });

  /// `reason`: 'all_in_cv' | 'no_cv' | 'no_requirements' | 'extraction_failed'
  Future<void> skillsConfirmationAutoSkipped({
    required String jobId,
    required String reason,
  }) =>
      track('skills_confirmation_auto_skipped', props: {
        'job_id': jobId,
        'reason': reason,
      });

  // ── Feedback / Founders ─────────────────────────────────────────────
  Future<void> foundersContactOpened({required String channel}) =>
      track('founders_contact_opened', props: {'channel': channel});
}

/// Alias curto pra acesso global. Use `Analytics.shared.jobSwiped(...)`.
typedef Analytics = AnalyticsService;
