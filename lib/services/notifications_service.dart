import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wrapper único pra OneSignal. Centraliza init, login/logout (associa
/// device ↔ supabase user.id) e request de permissão.
///
/// Sem ONESIGNAL_APP_ID no .env, todas as chamadas viram no-op silencioso
/// — não quebra o app em dev local sem credencial.
class NotificationsService {
  NotificationsService._();
  static final NotificationsService shared = NotificationsService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final appId = dotenv.env['ONESIGNAL_APP_ID'];
    if (appId == null || appId.isEmpty) return;

    try {
      OneSignal.Debug.setLogLevel(OSLogLevel.warn);
      OneSignal.initialize(appId);
      _initialized = true;
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
