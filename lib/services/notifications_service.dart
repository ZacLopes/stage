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
}
