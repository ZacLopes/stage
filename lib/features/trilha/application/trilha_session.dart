// Montagem da sessão da trilha (PLANO-FASE-6 T6.3, Increment 2c + fix memória).
//
// Junta as peças: carrega o perfil real + os trechos já abordados (memória) →
// calcula as lacunas → monta o plano adaptativo (sem re-perguntar o que já foi
// abordado) → cria o ConversationController com o write-back plugado (grava em
// profile_* e marca cada trecho como abordado).

import '../../../services/ai_service.dart';
import '../../../services/analytics_events.dart';
import '../../../services/analytics_service.dart';
import '../../../services/profile_snapshot_service.dart';
import '../../profile/application/profile_gaps.dart';
import '../../profile/data/repositories/profile_repository_supabase.dart';
import '../../profile/domain/repositories/profile_repository.dart';
import '../domain/conversation_step.dart' show PickSuggestion, StepAnswer;
import 'conversation_controller.dart';
import 'conversation_plan.dart';
import 'trilha_draft.dart';
import 'ibge_city_service.dart';
import 'institution_search_service.dart';
import 'skill_suggestions.dart';
import 'trilha_progress.dart';
import 'trilha_writeback.dart';

/// Cache do catálogo IBGE compartilhado entre aberturas da trilha na sessão.
final _ibge = IbgeCityService();

/// Uma sessão da trilha: o [controller] + o [saveAnswer] que grava em profile_*
/// e marca o trecho. O `saveAnswer` é exposto pra o chat v2 poder REGRAVAR um
/// campo na edição de card (idempotente) sem passar pelo fluxo do controller.
class TrilhaSession {
  final ConversationController controller;
  final Future<void> Function(StepAnswer answer) saveAnswer;
  const TrilhaSession({required this.controller, required this.saveAnswer});
}

/// Constrói o controller da trilha para [userId] (caminho antigo — pushado/dev).
/// Pula trechos já abordados (memória [TrilhaProgress]). Delega a
/// [buildTrilhaSession].
Future<ConversationController> buildTrilhaController(
  String userId, {
  ProfileRepository? repository,
  ProfileSnapshotService? snapshotService,
  TrilhaProgress? progress,
}) async {
  final s = await buildTrilhaSession(
    userId,
    repository: repository,
    snapshotService: snapshotService,
    progress: progress,
  );
  return s.controller;
}

/// Constrói a sessão (controller + saveAnswer). Recalcula lacunas a partir do
/// perfil FRESCO — é o que permite o re-planejamento após o import (basta
/// chamar de novo). Sem cache stale.
Future<TrilhaSession> buildTrilhaSession(
  String userId, {
  ProfileRepository? repository,
  ProfileSnapshotService? snapshotService,
  TrilhaProgress? progress,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final snapSvc = snapshotService ?? ProfileSnapshotService();
  // Híbrido: retomada entre devices via profile_guided_progress (failure-safe).
  final prog = progress ?? TrilhaProgress(repository: repo);

  final snapshot = await snapSvc.loadSnapshot(userId);
  final prefs = await repo.getJobPreferences(userId);
  final desired = await repo.getDesiredTitles(userId);
  final addressed = await prog.addressed(userId);
  // Rascunhos de item em construção (resumabilidade por passo, failure-safe).
  final draftStore = TrilhaDraftStore();
  final drafts = await draftStore.load(userId);

  final gaps = profileGapsFromData(
    snapshot: snapshot,
    prefs: prefs,
    desiredTitles: desired,
  );

  // Pro passo de skills: catálogo (typeahead) + sugestões pela área. Só busca o
  // catálogo se skills é mesmo uma lacuna a perguntar (evita round-trip à toa).
  final needsSkills =
      gaps.missing.any((l) => l.key == LacunaKey.skills) &&
          !addressed.contains('skills');
  final skillCatalog = needsSkills ? await _safeSkillCatalog(repo) : const <String>[];
  final skillSuggestions = needsSkills
      ? suggestedSkillsForAreas(desired.map((d) => d.title).toList())
      : const <String>[];

  final plan = buildConversationPlan(
    gaps,
    addressed: addressed,
    skillSuggestions: skillSuggestions,
    skillCatalog: skillCatalog,
    // Depois de marcar skills, a IA sugere mais algumas pelo perfil (opcional).
    skillSuggester:
        needsSkills ? () => AIService().suggestProfileSkills() : null,
    // Sugestões de skills pela ÁREA — lidas na hora do passo (capta a área
    // escolhida DENTRO da trilha, não só a do onboarding).
    skillSuggestionsLoader: needsSkills
        ? () async => suggestedSkillsForAreas(
              (await repo.getDesiredTitles(userId))
                  .map((d) => d.title)
                  .toList(),
            )
        : null,
    // Typeahead canônico: cidade (IBGE, com UF) e instituição (catálogo, fixa o
    // institution_id) — não polui os campos de filtro do admin. Lazy: só busca
    // quando o usuário chega no passo.
    citySearch: (q) async => (await _ibge.search(q))
        .map((c) => PickSuggestion(
              label: c.uf.isEmpty ? c.name : '${c.name} - ${c.uf}',
              value: c.uf.isEmpty ? c.name : '${c.name}|${c.uf}',
            ))
        .toList(),
    institutionSearch: (q) async => (await searchInstitutions(q))
        .map((i) => PickSuggestion(label: i.name, value: '${i.id}|${i.name}'))
        .toList(),
    drafts: drafts, // retoma o item parcial no passo onde parou
  );
  final writeback = TrilhaWriteback(repo, userId, draftStore: draftStore);
  // Reidrata os buffers do rascunho ANTES do controller — pra o save terminal
  // ver TODOS os campos (os de antes do abandono + os respondidos na retomada).
  writeback.seedFromDrafts(drafts);

  // Grava a resposta + marca o trecho. Reusado pelo fluxo (onAnswer) E pela
  // edição de card (re-save direto). Marca o trecho só quando há DADO salvo ou
  // gate "não" (ver segmentToMark) — "sim" sem escrever NÃO conta (a pergunta volta).
  Future<void> saveAnswer(StepAnswer answer) async {
    await writeback.save(answer);
    final segment =
        TrilhaProgress.segmentToMark(answer.stepId, answer.value);
    if (segment != null) {
      await prog.mark(userId, segment);
      // Telemetria (5c): conta os trechos efetivamente abordados.
      // ignore: unawaited_futures
      Analytics.shared
          .track(evTrilhaColetaStepAnswered, props: {'segment': segment});
    }
  }

  final controller = ConversationController(plan, onAnswer: saveAnswer);
  return TrilhaSession(controller: controller, saveAnswer: saveAnswer);
}

/// Lê os nomes canônicos do skills_catalog (fonte do typeahead). Failure-safe:
/// erro/sem rede ⇒ lista vazia (a busca fica sem catálogo, mas chips + texto
/// livre seguem funcionando).
Future<List<String>> _safeSkillCatalog(ProfileRepository repo) async {
  try {
    return await repo.getSkillCatalogNames();
  } catch (_) {
    return const [];
  }
}
