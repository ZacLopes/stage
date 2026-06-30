// Rascunho de ITEM multi-passo da trilha (PLANO-FASE-6 — resumabilidade por
// passo). Persiste o buffer em construção + o último passo respondido pra
// RETOMAR no ponto exato ao reabrir — sem gravar parcial em profile_* e sem
// re-perguntar o item inteiro. Ortogonal à memória por segmento (TrilhaProgress):
// o segmento só conta no passo terminal; o rascunho só existe enquanto o item
// está incompleto. Local-only por ora (failure-safe), espelhando o lado local
// do TrilhaProgress; cross-device pode somar depois.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TrilhaItemDraft {
  final String kind; // 'experience' | 'project' | 'education'
  final int itemIndex; // o {n} do item
  final String lastStepId; // último passo respondido (pra retomar no seguinte)
  final Map<String, dynamic> fields; // buffer serializado

  const TrilhaItemDraft({
    required this.kind,
    required this.itemIndex,
    required this.lastStepId,
    required this.fields,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'itemIndex': itemIndex,
        'lastStepId': lastStepId,
        'fields': fields,
      };

  static TrilhaItemDraft? fromJson(Map<String, dynamic> j) {
    final kind = j['kind'];
    final last = j['lastStepId'];
    if (kind is! String || last is! String) return null;
    return TrilhaItemDraft(
      kind: kind,
      itemIndex: (j['itemIndex'] as num?)?.toInt() ?? 0,
      lastStepId: last,
      fields: (j['fields'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// Persistência LOCAL dos rascunhos (no máx. 1 por kind), failure-safe.
class TrilhaDraftStore {
  static String _key(String userId) => 'trilha_drafts_$userId';

  Future<List<TrilhaItemDraft>> load(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => TrilhaItemDraft.fromJson(m.cast<String, dynamic>()))
          .whereType<TrilhaItemDraft>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Upsert por kind (substitui o rascunho do mesmo tipo).
  Future<void> save(String userId, TrilhaItemDraft draft) async {
    try {
      final all = await load(userId);
      final next = [...all.where((d) => d.kind != draft.kind), draft];
      await _write(userId, next);
    } catch (_) {/* ignora */}
  }

  Future<void> delete(String userId, String kind) async {
    try {
      final all = await load(userId);
      await _write(userId, all.where((d) => d.kind != kind).toList());
    } catch (_) {/* ignora */}
  }

  Future<void> _write(String userId, List<TrilhaItemDraft> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    if (drafts.isEmpty) {
      await prefs.remove(_key(userId));
    } else {
      await prefs.setString(
          _key(userId), jsonEncode(drafts.map((d) => d.toJson()).toList()));
    }
  }
}
