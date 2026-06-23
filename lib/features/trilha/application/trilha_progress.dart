// Memória da trilha (PLANO-FASE-6 T6.3 + T6.6 Increment 6).
//
// A trilha é dirigida por lacunas, mas lacuna ≠ "ainda não perguntei". Sem
// memória, trechos que geram pouco/nenhum dado (ex.: 2 skills < limiar de 3, ou
// "não tenho experiência") seriam re-perguntados toda vez. Guardamos, por
// usuário, quais TRECHOS já foram abordados — pra não repetir.
//
// HÍBRIDO (Increment 6): o device-local (SharedPreferences) é a fonte
// failure-safe e instantânea; o servidor (profile_guided_progress) dá a
// retomada ENTRE devices. Regras:
//   - addressed: une local + servidor; semeia o cache local com o que veio do
//     servidor; se o servidor falhar, cai no local (nunca trava a trilha).
//   - mark: grava local primeiro (sempre), depois best-effort no servidor.
// Sem repositório injetado (testes/uso offline), funciona 100% local — igual
// ao comportamento anterior.

import 'package:shared_preferences/shared_preferences.dart';

import '../../profile/domain/repositories/profile_repository.dart';

class TrilhaProgress {
  /// Espelho server-side (retomada entre devices). Nulo ⇒ só local.
  final ProfileRepository? _repo;

  TrilhaProgress({ProfileRepository? repository}) : _repo = repository;

  static String _key(String userId) => 'trilha_addressed_$userId';

  /// Trechos já abordados por [userId] — união do cache local com o servidor.
  /// Failure-safe: erro de rede cai no cache local.
  Future<Set<String>> addressed(String userId) async {
    final local = await _localAddressed(userId);
    final repo = _repo;
    if (repo == null) return local;
    try {
      final server = await repo.getGuidedProgress(userId);
      final merged = {...local, ...server};
      // Semeia o cache local com o que veio do servidor (outros devices).
      if (merged.length != local.length) {
        await _writeLocal(userId, merged);
      }
      return merged;
    } catch (_) {
      return local; // failure-safe
    }
  }

  /// Marca um trecho como abordado: local primeiro (failure-safe), servidor
  /// best-effort (sincroniza entre devices quando a rede coopera).
  Future<void> mark(String userId, String segment) async {
    final local = await _localAddressed(userId);
    if (!local.contains(segment)) {
      await _writeLocal(userId, {...local, segment});
    }
    final repo = _repo;
    if (repo != null) {
      try {
        await repo.markGuidedProgress(userId, segment);
      } catch (_) {
        // Fica só no local deste device; sincroniza na próxima marcação online.
      }
    }
  }

  /// Marca o trecho correspondente ao passo respondido (no-op pra passos de
  /// controle, ex.: 'intro', 'exp.0.company').
  Future<void> markFromStep(String userId, String stepId) async {
    final segment = segmentForStep(stepId);
    if (segment != null) await mark(userId, segment);
  }

  /// Mapeia um passo → trecho. Só os passos que "abrem" um trecho contam
  /// (gate/pergunta-raiz); passos internos da experiência não.
  static String? segmentForStep(String stepId) {
    switch (stepId) {
      case 'gap.area':
        return 'area';
      case 'gap.workmode':
        return 'workmode';
      case 'gap.jobtype':
        return 'jobtype';
      case 'gap.city':
        return 'city';
      case 'gap.skills':
        return 'skills';
      case 'gap.languages':
        return 'languages';
      case 'gap.availability':
        return 'availability';
      case 'exp.gate':
        return 'experience';
      case 'linkedin.gate':
        return 'linkedin';
      case 'cert.gate':
        return 'certifications';
      case 'project.gate':
        return 'projects';
    }
    return null;
  }

  // ── Cache local (SharedPreferences) ──────────────────────────────────────
  Future<Set<String>> _localAddressed(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(userId)) ?? const <String>[]).toSet();
  }

  Future<void> _writeLocal(String userId, Set<String> set) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(userId), set.toList());
  }
}
