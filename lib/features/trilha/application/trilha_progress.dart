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
  /// controle, ex.: 'intro', 'exp.0.company') — passando a RESPOSTA pra
  /// distinguir "sim" (abre o texto, ainda não conta) de "não" (não tem aquilo).
  Future<void> markForAnswer(
      String userId, String stepId, Object? value) async {
    final segment = segmentToMark(stepId, value);
    if (segment != null) await mark(userId, segment);
  }

  /// Trecho a marcar como abordado dada a resposta. Um trecho conta quando:
  /// (a) tem DADO salvo — passo terminal/único ([segmentForStep]); OU
  /// (b) o usuário diz "não" no gate ([segmentForGateDecline]) — não tem aquilo.
  /// Dizer "sim" no gate (que só abre o texto) NÃO conta: se ele sair antes de
  /// escrever, a pergunta volta na próxima vez.
  static String? segmentToMark(String stepId, Object? value) {
    final terminal = segmentForStep(stepId);
    if (terminal != null) return terminal;
    // Educação: "Outro" no momento (já terminei / não estudo) marca o trecho
    // como abordado SEM gravar formação — não re-pergunta nem cria row vazia.
    if (stepId == 'gap.edu.moment' && value is List && value.contains('outro')) {
      return 'education';
    }
    final gate = segmentForGateDecline(stepId);
    if (gate != null && value is List && value.contains('no')) return gate;
    return null;
  }

  /// Passos TERMINAIS/únicos: quando respondidos, há dado salvo → trecho conta.
  /// (Os passos de save da experiência/projeto/cert são indexados.)
  static String? segmentForStep(String stepId) {
    switch (stepId) {
      case 'gap.area':
        return 'area';
      case 'gap.desired_position':
        return 'desired_position';
      case 'gap.workmode':
        return 'workmode';
      case 'gap.jobtype':
        return 'jobtype';
      case 'gap.city':
        return 'city';
      case 'gap.skills':
        return 'skills';
      // 'gap.languages' (o picker) NÃO marca mais: senão sair entre o picker e
      // os níveis deixava "Inglês" sem nível pra sempre. O trecho é gap-driven
      // agora — a lacuna só fecha quando todos os idiomas têm nível (Fase 7 +10
      // Tarefa 3), então a trilha volta a perguntar o nível que faltou.
      case 'gap.availability':
        return 'availability';
      case 'gap.interests':
        return 'interests';
      case 'gap.company_stage':
        return 'company_stage';
      case 'gap.work_environment':
        return 'work_environment';
      case 'gap.work_style':
        return 'work_style';
      // Educação: grava no último passo de cada ramo (faculdade=formatura,
      // ensino médio=ano). "Outro" é tratado no segmentToMark.
      case 'gap.edu.graduation':
      case 'gap.edu.schoolyear':
        return 'education';
      case 'linkedin.url':
        return 'linkedin';
    }
    // Passos de save indexados (exp.{n}.ofazia / project.{n}.link / cert.{n}.date).
    // Cada um conta no ÚLTIMO passo do item (onde é gravado atômico).
    if (stepId.endsWith('.ofazia')) return 'experience';
    if (stepId.startsWith('project.') && stepId.endsWith('.link')) {
      return 'projects';
    }
    if (stepId.startsWith('cert.') && stepId.endsWith('.date')) {
      return 'certifications';
    }
    if (stepId.startsWith('award.') && stepId.endsWith('.date')) {
      return 'awards';
    }
    return null;
  }

  /// Gates que, quando respondidos "não", marcam o trecho (o usuário não tem
  /// aquilo). Quando respondidos "sim", NÃO marcam (espera o dado ser salvo).
  static String? segmentForGateDecline(String stepId) {
    switch (stepId) {
      case 'exp.gate':
        return 'experience';
      case 'project.gate':
        return 'projects';
      case 'cert.gate':
        return 'certifications';
      case 'award.gate':
        return 'awards';
      case 'linkedin.gate':
        return 'linkedin';
      case 'interests.gate':
        return 'interests';
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
