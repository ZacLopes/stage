import 'package:shared_preferences/shared_preferences.dart';

/// Lembra qual sub-aba do Perfil (Informações = 0, Currículos = 1) o user viu
/// por último, por userId. Hidratado no _bootstrap do main.dart antes da
/// árvore widget montar — assim o initialIndex do TabController já tem o valor
/// sincronamente, sem flash visual da aba 0 → aba salva no cold start.
///
/// O prefixo da key tem sufixo `_v2` porque a ordem das abas foi invertida —
/// keys antigas (`_v1`) apontavam pra ordem [Currículos, Informações] e
/// ficaram semanticamente inválidas. Ignoramos elas e começamos fresco.
class ProfileTabPrefs {
  ProfileTabPrefs._();
  static final ProfileTabPrefs shared = ProfileTabPrefs._();

  static const String _keyPrefix = 'profile_tab_last_index_v2_';

  /// Aba atualmente lembrada. Default 0 (Informações).
  int lastIndex = 0;

  String _key(String userId) => '$_keyPrefix$userId';

  /// Lê a preferência salva pro user e popula [lastIndex]. Chamar no boot.
  /// Falha silenciosa — se o SharedPreferences não responder, fica em 0.
  Future<void> hydrate(String? userId) async {
    if (userId == null || userId.isEmpty) {
      lastIndex = 0;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getInt(_key(userId)) ?? 0;
      lastIndex = raw.clamp(0, 1);
    } catch (_) {
      lastIndex = 0;
    }
  }

  /// Salva a nova aba escolhida e atualiza [lastIndex] em memória.
  Future<void> save(String? userId, int index) async {
    final clamped = index.clamp(0, 1);
    lastIndex = clamped;
    if (userId == null || userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key(userId), clamped);
    } catch (_) {}
  }
}
