import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wrapper único pro Facebook App Events SDK. Centraliza init, request de
/// ATT (App Tracking Transparency da Apple) e helpers pros eventos padrão
/// que o Meta Ads usa pra otimização de campanha.
///
/// Eventos disparados:
/// - `CompletedRegistration` — user finaliza cadastro (1x por user)
/// - `SubmittedApplication` — user toca "Aplicar" e abre site externo
/// - `Lead` — user finaliza onboarding completo (1x por user). Sinal de
///   "user qualificado" mais forte que registration sozinho.
/// - `ViewContent` — user toca em "Ver detalhes" duma vaga (intent forte)
/// - `AddToWishlist` — user dá swipe right (curte/salva) numa vaga
///   (1x por user+jobId, dedupado em SharedPreferences)
///
/// Advanced Matching: `setUserDataForMatching()` populariza email/phone/
/// name etc no SDK depois do login. O SDK hasheia automaticamente em SHA256
/// antes de mandar pro Meta — aumenta EMQ score e atribuição pós-ATT.
///
/// Init/ATT/eventos rodam só em iOS por enquanto. Android é cross-platform
/// no plugin mas exige config separada no Gradle/manifest (fora do escopo
/// dessa iteração — adicionar quando lançar Android).
class FacebookEventsService {
  FacebookEventsService._();
  static final FacebookEventsService shared = FacebookEventsService._();

  final FacebookAppEvents _fb = FacebookAppEvents();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isIOS) {
      // ignore: avoid_print
      print('[FBEvents] init skipped: not iOS');
      return;
    }

    try {
      // Auto-log de eventos do app (Install, Activate) já vem habilitado via
      // Info.plist key `FacebookAutoLogAppEventsEnabled=true`. Aqui só
      // garantimos o estado inicial via setAutoLogAppEventsEnabled.
      // Advertiser ID Collection começa OFF — ATT vai habilitar depois se
      // o user autorizar (Apple exige consentimento explícito antes de IDFA).
      await _fb.setAutoLogAppEventsEnabled(true);
      await _fb.setAdvertiserTracking(enabled: false, collectId: false);
      _initialized = true;
      // ignore: avoid_print
      print('[FBEvents] init SUCCESS — SDK initialized');
    } catch (e) {
      // ignore: avoid_print
      print('[FBEvents] init FAILED: $e');
    }
  }

  /// Pede permissão ATT (App Tracking Transparency) — exigido pelo Apple
  /// pra usar IDFA. Pode chamar 1x na vida do app. Se o user negar, Apple
  /// não mostra de novo (precisa ir em Settings).
  ///
  /// Resultado:
  /// - `authorized` → habilita coleta IDFA → Meta consegue atribuir melhor
  /// - `denied` / `restricted` → SDK não coleta IDFA, atribuição via
  ///   SKAdNetwork (que é mais limitada)
  ///
  /// Comportamento por OS:
  /// - iOS 14.5+ → mostra prompt nativo
  /// - iOS < 14 → ATT não existe, libera tracking direto (pula prompt)
  /// - Não-iOS → no-op
  Future<void> requestAttIfNeeded() async {
    if (!_initialized) return;
    if (!Platform.isIOS) return;

    try {
      final current = await AppTrackingTransparency.trackingAuthorizationStatus;
      // Se já foi decidido (authorized/denied/restricted), não pede de novo.
      if (current != TrackingStatus.notDetermined) {
        await _applyTrackingStatus(current);
        return;
      }

      final result = await AppTrackingTransparency.requestTrackingAuthorization();
      await _applyTrackingStatus(result);
    } catch (_) {}
  }

  Future<void> _applyTrackingStatus(TrackingStatus status) async {
    final granted = status == TrackingStatus.authorized;
    try {
      // Único método que controla ambos: advertiser tracking + collectId.
      // Apple exige que collectId=true só seja chamado após ATT authorized,
      // senão SDK loga erro em runtime e quebra atribuição.
      await _fb.setAdvertiserTracking(enabled: granted, collectId: granted);
    } catch (_) {}
  }

  /// Dispara `CompletedRegistration` no máximo 1x por user (flag em
  /// SharedPreferences). Usado nos 3 fluxos de signup: email, Apple, Google.
  /// O flag previne dispatch duplicado em re-logins.
  ///
  /// `method` deve ser 'email', 'apple' ou 'google' — passado como parâmetro
  /// `registrationMethod` no evento (Meta usa em insights pra segmentar).
  Future<void> logCompletedRegistrationOnce({
    required String? userId,
    required String method,
  }) async {
    if (!_initialized) return;
    if (!Platform.isIOS) return;
    if (userId == null || userId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'fb_registration_logged_$userId';
      if (prefs.getBool(key) == true) return;
      await prefs.setBool(key, true);

      await _fb.logCompletedRegistration(registrationMethod: method);
      // Flush imediato — CompletedRegistration é 1x na vida do user.
      await _fb.flush();
    } catch (_) {}
  }

  /// Dispara `SubmittedApplication` quando user toca "Aplicar" e abre o
  /// site da empresa. Sem dedupe — cada candidatura é evento legítimo
  /// (Meta otimiza por volume de conversão).
  Future<void> logSubmittedApplication({required String jobId}) async {
    if (!_initialized) return;
    if (!Platform.isIOS) return;

    try {
      await _fb.logEvent(
        name: 'SubmittedApplication',
        parameters: {
          'job_id': jobId,
        },
      );
      // Flush imediato — conversão de maior valor (job application).
      await _fb.flush();
    } catch (_) {}
  }

  /// Dispara `Lead` no máximo 1x por user — quando o user finaliza o
  /// onboarding completo (toca "Começar" no OnboardingComplete). É um
  /// sinal mais valioso que `CompletedRegistration` porque indica
  /// "user qualificado, perfil populado, pronto pra receber vagas".
  ///
  /// É evento padrão da Meta (`fb_mobile_lead` no SDK iOS), então pode
  /// ser usado como objetivo de conversão direto no Ads Manager.
  Future<void> logLeadOnce({required String? userId}) async {
    // ignore: avoid_print
    print('[FBEvents] logLeadOnce called: userId=$userId, initialized=$_initialized, isIOS=${Platform.isIOS}');
    if (!_initialized) return;
    if (!Platform.isIOS) return;
    if (userId == null || userId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'fb_lead_logged_$userId';
      final alreadyLogged = prefs.getBool(key) == true;
      // ignore: avoid_print
      print('[FBEvents] Lead dedupe check: alreadyLogged=$alreadyLogged');
      if (alreadyLogged) return;
      await prefs.setBool(key, true);

      // facebook_app_events não tem helper dedicado pro Lead — manda
      // como custom event com o nome padrão da Meta.
      await _fb.logEvent(name: 'Lead');
      // Flush imediato — Lead é evento crítico (1x na vida do user),
      // não pode ficar buffered no SDK e perder se o user fechar o app.
      await _fb.flush();
      // ignore: avoid_print
      print('[FBEvents] Lead DISPATCHED + FLUSHED');
    } catch (e) {
      // ignore: avoid_print
      print('[FBEvents] Lead FAILED: $e');
    }
  }

  /// Dispara `ViewContent` quando user toca em "Ver detalhes" duma vaga.
  /// Indica intent forte (não é só ver o card no swipe deck — é mergulhar
  /// no conteúdo). Sem dedupe — mesmo job pode ser visto várias vezes,
  /// cada view é sinal de interesse contínuo.
  Future<void> logViewContent({
    required String jobId,
    String? jobTitle,
    String? company,
  }) async {
    // ignore: avoid_print
    print('[FBEvents] logViewContent called: jobId=$jobId, initialized=$_initialized, isIOS=${Platform.isIOS}');
    if (!_initialized) return;
    if (!Platform.isIOS) return;

    try {
      await _fb.logEvent(
        name: 'fb_mobile_content_view',
        parameters: {
          'fb_content_type': 'job',
          'fb_content_id': jobId,
          if (jobTitle != null) 'fb_content_name': jobTitle,
          if (company != null) 'company': company,
        },
      );
      // Flush imediato pra evitar perda em fechamento de app.
      await _fb.flush();
      // ignore: avoid_print
      print('[FBEvents] ViewContent DISPATCHED + FLUSHED: jobId=$jobId');
    } catch (e) {
      // ignore: avoid_print
      print('[FBEvents] ViewContent FAILED: $e');
    }
  }

  /// Dispara `AddToWishlist` no primeiro swipe right (curtir) por
  /// combinação (user, jobId). Dedupado em SharedPreferences pra evitar
  /// inflar volume — depois que user curte uma vaga, removeu e curtiu
  /// de novo (caso raro) NÃO dispara de novo.
  ///
  /// Mantém o mesmo dataset pequeno: cada AddToWishlist = user_id × job_id
  /// único.
  Future<void> logAddToWishlistFirstTime({
    required String? userId,
    required String jobId,
  }) async {
    // ignore: avoid_print
    print('[FBEvents] logAddToWishlistFirstTime called: userId=$userId, jobId=$jobId, initialized=$_initialized, isIOS=${Platform.isIOS}');
    if (!_initialized) return;
    if (!Platform.isIOS) return;
    if (userId == null || userId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'fb_wishlist_${userId}_$jobId';
      final alreadyLogged = prefs.getBool(key) == true;
      // ignore: avoid_print
      print('[FBEvents] AddToWishlist dedupe check: alreadyLogged=$alreadyLogged');
      if (alreadyLogged) return;
      await prefs.setBool(key, true);

      await _fb.logEvent(
        name: 'fb_mobile_add_to_wishlist',
        parameters: {
          'fb_content_type': 'job',
          'fb_content_id': jobId,
        },
      );
      // Flush imediato — AddToWishlist é 1x por (user, jobId), não pode perder.
      await _fb.flush();
      // ignore: avoid_print
      print('[FBEvents] AddToWishlist DISPATCHED + FLUSHED: jobId=$jobId');
    } catch (e) {
      // ignore: avoid_print
      print('[FBEvents] AddToWishlist FAILED: $e');
    }
  }

  /// Configura Advanced Matching no SDK — passa email/phone/nome etc do
  /// user pra que o Meta consiga matchear com a pessoa que clicou no ad
  /// (mesmo após ATT deny). O SDK faz SHA256 internamente; aqui mandamos
  /// plain text já normalizado (lowercase, sem espaços, telefone só dígitos).
  ///
  /// Chamar UMA vez depois de cada login bem-sucedido. Email é obrigatório
  /// pra ter sinal mínimo; outros campos opcionais aumentam EMQ score.
  ///
  /// O `externalId` é o user_id do Stage — útil pra correlacionar com
  /// audiências custom (Lookalike a partir de users que já aplicaram).
  Future<void> setUserDataForMatching({
    required String email,
    String? phone,
    String? firstName,
    String? lastName,
    String? externalId,
  }) async {
    if (!_initialized) return;
    if (!Platform.isIOS) return;
    if (email.trim().isEmpty) return;

    try {
      await _fb.setUserData(
        email: email.trim().toLowerCase(),
        phone: phone?.replaceAll(RegExp(r'\D'), ''),
        firstName: firstName?.trim().toLowerCase(),
        lastName: lastName?.trim().toLowerCase(),
      );
      if (externalId != null && externalId.isNotEmpty) {
        await _fb.setUserID(externalId);
      }
    } catch (_) {}
  }

  /// Limpa user data do SDK no logout — evita que próximo user que logar
  /// no mesmo device herde os dados do anterior.
  Future<void> clearUserData() async {
    if (!_initialized) return;
    if (!Platform.isIOS) return;
    try {
      await _fb.clearUserData();
      await _fb.clearUserID();
    } catch (_) {}
  }
}
