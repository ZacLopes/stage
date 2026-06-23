// Memória da trilha (PLANO-FASE-6 T6.3, fix de re-pergunta).
//
// A trilha é dirigida por lacunas, mas lacuna ≠ "ainda não perguntei". Sem
// memória, trechos que geram pouco/nenhum dado (ex.: 2 skills < limiar de 3, ou
// "não tenho experiência") seriam re-perguntados toda vez. Aqui guardamos, por
// usuário, quais TRECHOS já foram abordados — pra não repetir.
//
// Persistência local no device (SharedPreferences) como primeiro passo; o sync
// server-side (retomada entre devices) entra no Increment 6 (profile_guided_progress).

import 'package:shared_preferences/shared_preferences.dart';

class TrilhaProgress {
  static String _key(String userId) => 'trilha_addressed_$userId';

  /// Trechos já abordados por [userId].
  Future<Set<String>> addressed(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(userId)) ?? const <String>[]).toSet();
  }

  /// Marca um trecho como abordado.
  Future<void> mark(String userId, String segment) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_key(userId)) ?? <String>[]).toSet()
      ..add(segment);
    await prefs.setStringList(_key(userId), set.toList());
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
      case 'exp.gate':
        return 'experience';
    }
    return null;
  }
}
