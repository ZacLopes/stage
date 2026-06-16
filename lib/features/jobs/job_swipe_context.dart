// JobSwipeContext — cache persistente de contexto por vaga.
//
// Mantém duas peças de informação por `job_id` que precisam sobreviver entre
// telas e cold starts (SharedPrefs):
//
//   1. `matchScore` no momento do swipe → resolve bug do `match_score=0` na
//      aba Curtidas. A tabela `jobs` no Supabase não tem match_score (é
//      computado por user×job), então o `LikedJob.job.matchScore` carregado
//      do DB chega zerado. Salvar o score no momento do swipe e ler de volta
//      no `_openJobDetails`/`_openApplication` preserva o número que sustenta
//      a tese B2B.
//
//   2. `wasAdapted` por job_id → resolve bug do `used_adapted_cv: null` no
//      apply. O `PendingAdaptedCvTracker` mantém só UMA adaptação (singular,
//      a mais recente) e é limpo no download. Pra saber "esse user já adaptou
//      CV pra essa vaga?" no momento do apply, precisa de um conjunto
//      persistente. Mark no `adapt_pdf_downloaded`, read no apply.
//
// Storage layout (SharedPrefs key `job_swipe_context_v1`):
//   {
//     "<job_id>": {"m": 73, "a": 1700000000, "d": 1700000050},  // m=match, a=adaptedAt epoch, d=swipedAt epoch
//     "<other>": {"m": 42}
//   }
//
// TTL: 30 dias por entrada (LRU implícita por epoch). Garbage collection
// roda no `_load` a cada inicialização — entradas stale somem sem
// administração manual.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/pending_apply.dart';

class JobSwipeContext {
  JobSwipeContext._();
  static final JobSwipeContext shared = JobSwipeContext._();

  static const _kStorageKey = 'job_swipe_context_v1';
  static const _kPendingApplyKey = 'pending_apply_v1';
  static const _kTtl = Duration(days: 30);

  Map<String, _Entry>? _cache;

  Future<Map<String, _Entry>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kStorageKey);
      if (raw == null || raw.isEmpty) {
        _cache = <String, _Entry>{};
        return _cache!;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _cache = <String, _Entry>{};
        return _cache!;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - _kTtl.inMilliseconds;
      final result = <String, _Entry>{};
      decoded.forEach((k, v) {
        if (k is! String || v is! Map) return;
        final entry = _Entry.fromJson(Map<String, dynamic>.from(v));
        // GC: descarta entradas onde tudo é mais velho que TTL
        final newest = [entry.adaptedAtMs, entry.swipedAtMs]
            .whereType<int>()
            .fold<int>(0, (a, b) => a > b ? a : b);
        if (newest == 0 || newest >= cutoff) {
          result[k] = entry;
        }
      });
      _cache = result;
      return _cache!;
    } catch (e) {
      if (kDebugMode) debugPrint('[JobSwipeContext] _load failed: $e');
      _cache = <String, _Entry>{};
      return _cache!;
    }
  }

  Future<void> _persist() async {
    final cache = _cache;
    if (cache == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStorageKey, jsonEncode(cache.map(
        (k, v) => MapEntry(k, v.toJson()),
      )));
    } catch (e) {
      if (kDebugMode) debugPrint('[JobSwipeContext] _persist failed: $e');
    }
  }

  /// Registra o `matchScore` da vaga no momento do swipe (qualquer direção).
  /// Sem isso, na aba Curtidas o `LikedJob.job.matchScore` carregado do DB
  /// vem 0 e quebra a correlação match × apply (audit fix do plano).
  /// Idempotente — chamadas subsequentes sobrescrevem.
  Future<void> recordSwipe(String jobId, int? matchScore) async {
    final cache = await _load();
    final prev = cache[jobId] ?? const _Entry();
    cache[jobId] = prev.copyWith(
      matchScore: matchScore ?? prev.matchScore,
      swipedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
  }

  /// Lê o `matchScore` registrado pro `jobId`, ou null se nunca foi swipado
  /// (ou se já passou da TTL).
  Future<int?> getMatchScore(String jobId) async {
    final cache = await _load();
    return cache[jobId]?.matchScore;
  }

  /// Marca que o user adaptou CV e baixou o PDF pra essa vaga. Chamar no
  /// `adapt_pdf_downloaded` — sustenta `used_adapted_cv: true` no
  /// `job_details_apply_clicked` posterior (tese B2B do pitch).
  Future<void> markAdapted(String jobId) async {
    final cache = await _load();
    final prev = cache[jobId] ?? const _Entry();
    cache[jobId] = prev.copyWith(
      adaptedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
  }

  /// True se o user já adaptou CV pra essa vaga (e o registro não é stale).
  /// Lido no `_openApplication` pra passar `usedAdaptedCv` correto.
  Future<bool> wasAdapted(String jobId) async {
    final cache = await _load();
    return cache[jobId]?.adaptedAtMs != null;
  }

  /// Epoch ms de quando o user adaptou+baixou o CV pra essa vaga (null se
  /// nunca). Read-only — usado p/ calcular `time_from_download_to_apply_ms`
  /// no evento `adapt_apply_used` (T2.3, fecha o funil adapt→apply).
  Future<int?> adaptedAtMs(String jobId) async {
    final cache = await _load();
    return cache[jobId]?.adaptedAtMs;
  }

  // ── FASE 3 (T3.2): pending_apply — slot único do prompt de retorno ────────
  // Slot separado do mapa por-vaga (key própria): é "o último apply aguardando
  // o prompt". Gravado no apply; lido no foreground; limpo após responder.

  /// Grava o pending_apply (sobrescreve um anterior — só o último importa).
  Future<void> recordPendingApply({
    required String jobId,
    required String title,
    required String company,
    String? source,
  }) async {
    final p = PendingApply(
      jobId: jobId,
      title: title,
      company: company,
      source: source,
      tsMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _writePendingApply(p);
  }

  /// Lê o pending_apply atual (ou null se não há / inválido).
  Future<PendingApply?> readPendingApply() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPendingApplyKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PendingApply.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      if (kDebugMode) debugPrint('[JobSwipeContext] readPendingApply failed: $e');
      return null;
    }
  }

  /// Limpa o pending_apply (após Sim/Não, ou quando expira).
  Future<void> clearPendingApply() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPendingApplyKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[JobSwipeContext] clearPendingApply failed: $e');
    }
  }

  /// "Depois": agenda a re-pergunta única pra +24h (mantém o resto do slot).
  Future<void> scheduleReask() async {
    final p = await readPendingApply();
    if (p == null) return;
    final reaskAfter = DateTime.now()
        .add(kPendingApplyReaskAfter)
        .millisecondsSinceEpoch;
    await _writePendingApply(p.withReask(reaskAfter));
  }

  Future<void> _writePendingApply(PendingApply p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPendingApplyKey, jsonEncode(p.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('[JobSwipeContext] writePendingApply failed: $e');
    }
  }
}

/// Entry interno. Use os métodos do [JobSwipeContext], não construa direto.
class _Entry {
  final int? matchScore;
  final int? swipedAtMs;
  final int? adaptedAtMs;

  const _Entry({this.matchScore, this.swipedAtMs, this.adaptedAtMs});

  _Entry copyWith({
    int? matchScore,
    int? swipedAtMs,
    int? adaptedAtMs,
  }) =>
      _Entry(
        matchScore: matchScore ?? this.matchScore,
        swipedAtMs: swipedAtMs ?? this.swipedAtMs,
        adaptedAtMs: adaptedAtMs ?? this.adaptedAtMs,
      );

  Map<String, dynamic> toJson() => {
        if (matchScore != null) 'm': matchScore,
        if (swipedAtMs != null) 's': swipedAtMs,
        if (adaptedAtMs != null) 'a': adaptedAtMs,
      };

  factory _Entry.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    return _Entry(
      matchScore: asInt(json['m']),
      swipedAtMs: asInt(json['s']),
      adaptedAtMs: asInt(json['a']),
    );
  }
}
