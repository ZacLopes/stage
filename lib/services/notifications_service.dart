import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

/// Wrapper único pra OneSignal. Centraliza init, login/logout (associa
/// device ↔ supabase user.id) e request de permissão.
///
/// Sem ONESIGNAL_APP_ID no .env, todas as chamadas viram no-op silencioso
/// — não quebra o app em dev local sem credencial.
class NotificationsService {
  NotificationsService._();
  static final NotificationsService shared = NotificationsService._();

  bool _initialized = false;
  bool? _lastKnownPermission;

  // SharedPrefs keys pra estado persistente do push lifecycle.
  static const String _kAskCountKey = 'push_permission_ask_count';
  static const String _kLastKnownPermissionKey = 'push_permission_last_known';
  static const String _kPermissionGrantedAtKey = 'push_permission_granted_at';

  Future<void> init() async {
    if (_initialized) return;
    final appId = dotenv.env['ONESIGNAL_APP_ID'];
    if (appId == null || appId.isEmpty) return;

    try {
      OneSignal.Debug.setLogLevel(OSLogLevel.warn);
      OneSignal.initialize(appId);
      _initialized = true;
      _bindAnalyticsListeners();
    } catch (_) {}
  }

  /// Liga os 3 listeners OneSignal v5 a typed methods do AnalyticsService
  /// (B.10 do plano v2). Idempotência: chamado uma única vez em [init].
  ///
  /// Sem isso, `push_displayed`/`push_opened`/`push_permission_*` ficavam
  /// invisíveis no PostHog — reativação por push era caixa-preta (audit).
  void _bindAnalyticsListeners() {
    try {
      // Foreground delivery: notificação chegou com app aberto.
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        final n = event.notification;
        final data = n.additionalData ?? const {};
        final campaignId = (data['campaign'] ?? data['campaign_id'] ?? n.notificationId).toString();
        final type = (data['type'] ?? 'unknown').toString();
        // ignore: unawaited_futures
        Analytics.shared.pushDisplayed(campaignId: campaignId, type: type);
      });

      // User tocou na notificação (foreground OU background).
      OneSignal.Notifications.addClickListener((event) {
        final n = event.notification;
        final data = n.additionalData ?? const {};
        final campaignId = (data['campaign'] ?? data['campaign_id'] ?? n.notificationId).toString();
        final type = (data['type'] ?? 'unknown').toString();
        // Edge function que envia push opcionalmente coloca `sent_at` ISO
        // em additionalData — calculamos o tempo até o tap em ms.
        int? timeFromSendMs;
        final sentAtRaw = data['sent_at'];
        if (sentAtRaw is String) {
          final sentAt = DateTime.tryParse(sentAtRaw);
          if (sentAt != null) {
            timeFromSendMs = DateTime.now().difference(sentAt).inMilliseconds;
          }
        }
        // ignore: unawaited_futures
        Analytics.shared.pushOpened(
          campaignId: campaignId,
          type: type,
          timeFromSendMs: timeFromSendMs,
        );
      });

      // Observer de permission state — dispara em iOS quando user volta
      // de Settings.app, e na 1ª resposta ao prompt nativo.
      OneSignal.Notifications.addPermissionObserver((permission) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final previous = _lastKnownPermission
              ?? (prefs.getBool(_kLastKnownPermissionKey));
          _lastKnownPermission = permission;
          await prefs.setBool(_kLastKnownPermissionKey, permission);

          if (permission) {
            // Granted (1ª vez OU re-granted após Settings).
            await prefs.setInt(
              _kPermissionGrantedAtKey,
              DateTime.now().millisecondsSinceEpoch,
            );
            // ignore: unawaited_futures
            Analytics.shared.pushPermissionGranted();
          } else {
            if (previous == true) {
              // Tinha permission, virou false → revoked via Settings.
              final grantedAt = prefs.getInt(_kPermissionGrantedAtKey);
              final days = grantedAt != null
                  ? DateTime.now()
                      .difference(DateTime.fromMillisecondsSinceEpoch(grantedAt))
                      .inDays
                  : null;
              // ignore: unawaited_futures
              Analytics.shared.pushPermissionRevokedDetected(
                daysSinceGrant: days,
              );
            } else {
              // Foi negado (primeira vez OU continuou negado).
              final askCount = prefs.getInt(_kAskCountKey) ?? 0;
              // ignore: unawaited_futures
              Analytics.shared.pushPermissionDenied(askCount: askCount);
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[NotificationsService] permission observer failed: $e');
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NotificationsService] _bindAnalyticsListeners failed: $e');
      }
    }
  }

  /// Incrementa o contador persistente de "quantas vezes pedimos permission"
  /// e emite o evento `push_permission_requested` com source_screen.
  /// Chamar dos pontos que efetivamente acionam o prompt nativo iOS.
  Future<void> _trackPermissionRequested(String sourceScreen) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = (prefs.getInt(_kAskCountKey) ?? 0) + 1;
      await prefs.setInt(_kAskCountKey, next);
      // ignore: unawaited_futures
      Analytics.shared.pushPermissionRequested(sourceScreen: sourceScreen);
    } catch (_) {}
  }

  /// Associa o device ao user logado. Idempotente — pode chamar várias vezes
  /// pra o mesmo uid sem efeito colateral.
  Future<void> login(String userId) async {
    if (!_initialized || userId.isEmpty) return;
    try {
      await OneSignal.login(userId);
    } catch (_) {}
  }

  Future<void> logout() async {
    if (!_initialized) return;
    try {
      await OneSignal.logout();
    } catch (_) {}
  }

  /// Mostra o prompt nativo iOS de "Allow Notifications". `fallbackToSettings`
  /// = true significa que se o user já negou antes, abre Settings.app pra ele
  /// reativar manualmente (caso contrário o prompt não reaparece).
  Future<bool> requestPermission({bool fallbackToSettings = true}) async {
    if (!_initialized) return false;
    try {
      // ignore: unawaited_futures
      _trackPermissionRequested('direct');
      return await OneSignal.Notifications.requestPermission(fallbackToSettings);
    } catch (_) {
      return false;
    }
  }

  bool get hasPermission {
    if (!_initialized) return false;
    try {
      return OneSignal.Notifications.permission;
    } catch (_) {
      return false;
    }
  }

  /// Chama o prompt nativo iOS no máximo 1x por user (flag persistida).
  /// Usado em 2 lugares: HomeScreen pra novos signups, jobs_swipe pra users
  /// existentes no primeiro swipe. O flag previne re-prompt — se o user
  /// negou, iOS não mostra de novo mesmo se a gente chamar, então não
  /// adianta tentar.
  ///
  /// `fallbackToSettings: false` deliberado: não abre Settings.app se o user
  /// já negou. Negativa é negativa — Settings.app pop-up só faz user travar.
  Future<bool> requestPermissionIfNotShown(String? userId) async {
    if (!_initialized) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = userId != null && userId.isNotEmpty
          ? 'push_prompt_shown_$userId'
          : 'push_prompt_shown_global';
      if (prefs.getBool(key) == true) return false;

      // Set flag ANTES do prompt — evita double-prompt em race condition
      // (ex: home + swipe disparando juntos).
      await prefs.setBool(key, true);

      // ignore: unawaited_futures
      _trackPermissionRequested('first_session');
      final granted = await OneSignal.Notifications.requestPermission(false);
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// True quando OneSignal tem subscription ativa (push token registrado +
  /// opted-in). Diferente de [hasPermission] (que reflete só o estado iOS).
  /// Pode ser true mesmo sem token registrado ainda — OneSignal considera
  /// "opt-in" intent, não confirma entrega.
  ///
  /// Use pra decidir se mostra "Reativar notificações" na UI.
  bool get isOptedIn {
    if (!_initialized) return false;
    try {
      return OneSignal.User.pushSubscription.optedIn ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Status detalhado pra UI mostrar a mensagem certa:
  ///   - 'subscribed'     → push funcionando, tudo ok
  ///   - 'denied'         → user negou no iOS (precisa abrir Settings.app)
  ///   - 'never_prompted' → user nunca foi perguntado (precisa do prompt)
  ///   - 'unknown'        → SDK não inicializado ou erro
  Future<String> pushStatus() async {
    if (!_initialized) return 'unknown';
    try {
      final permission = OneSignal.Notifications.permission;
      final optedIn = OneSignal.User.pushSubscription.optedIn ?? false;
      if (permission && optedIn) return 'subscribed';
      if (!permission) {
        // iOS nunca foi perguntado OU user negou. Distinguir requer flag
        // local — se a gente já chamou requestPermission antes, é 'denied';
        // senão é 'never_prompted'.
        final prefs = await SharedPreferences.getInstance();
        final uid = OneSignal.User.pushSubscription.id;
        final keys = [
          if (uid != null) 'push_prompt_shown_$uid',
          'push_prompt_shown_global',
        ];
        final everPrompted = keys.any((k) => prefs.getBool(k) == true);
        return everPrompted ? 'denied' : 'never_prompted';
      }
      // permission true mas optedIn false = user fez optOut programaticamente
      return 'denied';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Tenta reativar push de qualquer estado:
  ///   - never_prompted → mostra prompt iOS pela primeira vez
  ///   - denied         → abre Settings.app na seção do Stage (fallbackToSettings:true)
  ///   - subscribed     → no-op
  ///
  /// Usado pelo botão "Reativar notificações" em Settings. Limpa a flag
  /// local de "já promptei" pra garantir que o SDK tenta de novo mesmo
  /// se a gente cravou ela errado antes.
  Future<bool> reactivatePush({String? userId}) async {
    if (!_initialized) return false;
    try {
      // Limpa TODAS as flags possíveis (current user + legado global) pra
      // garantir que o próximo call NÃO toma early return.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('push_prompt_shown_global');
      if (userId != null && userId.isNotEmpty) {
        await prefs.remove('push_prompt_shown_$userId');
      }
      final oneSignalId = OneSignal.User.pushSubscription.id;
      if (oneSignalId != null) {
        await prefs.remove('push_prompt_shown_$oneSignalId');
      }

      // fallbackToSettings:true — se iOS já tem permissão negada, abre
      // Settings.app na seção do Stage automaticamente pro user reativar.
      // ignore: unawaited_futures
      _trackPermissionRequested('settings_reactivate');
      final granted = await OneSignal.Notifications.requestPermission(true);

      // Força optIn no caso de user ter sido optedOut programaticamente.
      try {
        OneSignal.User.pushSubscription.optIn();
      } catch (_) {}

      return granted;
    } catch (_) {
      return false;
    }
  }
}
