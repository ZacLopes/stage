import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wrapper único pro Facebook App Events SDK. Centraliza init, request de
/// ATT (App Tracking Transparency da Apple) e helpers pros eventos padrão
/// que o Meta Ads usa pra otimização de campanha.
///
/// Eventos disparados:
/// - `CompletedRegistration` — quando user finaliza cadastro (1x por user)
/// - `SubmittedApplication` — quando user clica "Aplicar" e abre site externo
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
    if (!Platform.isIOS) return;

    try {
      // Auto-log de eventos do app (Install, Activate) já vem habilitado via
      // Info.plist key `FacebookAutoLogAppEventsEnabled=true`. Aqui só
      // garantimos o estado inicial via setAutoLogAppEventsEnabled.
      // Advertiser ID Collection começa OFF — ATT vai habilitar depois se
      // o user autorizar (Apple exige consentimento explícito antes de IDFA).
      await _fb.setAutoLogAppEventsEnabled(true);
      await _fb.setAdvertiserTracking(enabled: false, collectId: false);
      _initialized = true;
    } catch (_) {}
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
    } catch (_) {}
  }
}
