// Montagem da sessão da trilha (PLANO-FASE-6 T6.3, Increment 2c + fix memória).
//
// Junta as peças: carrega o perfil real + os trechos já abordados (memória) →
// calcula as lacunas → monta o plano adaptativo (sem re-perguntar o que já foi
// abordado) → cria o ConversationController com o write-back plugado (grava em
// profile_* e marca cada trecho como abordado).

import '../../../services/analytics_events.dart';
import '../../../services/analytics_service.dart';
import '../../../services/profile_snapshot_service.dart';
import '../../profile/application/profile_gaps.dart';
import '../../profile/data/repositories/profile_repository_supabase.dart';
import '../../profile/domain/repositories/profile_repository.dart';
import 'conversation_controller.dart';
import 'conversation_plan.dart';
import 'trilha_progress.dart';
import 'trilha_writeback.dart';

/// Constrói o controller da trilha para [userId]. Pula trechos já abordados
/// (memória [TrilhaProgress]) — então skills/experiência não são re-perguntados
/// toda vez. Se não há nada novo, o controller vem com 0 passos.
Future<ConversationController> buildTrilhaController(
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

  final gaps = profileGapsFromData(
    snapshot: snapshot,
    prefs: prefs,
    desiredTitles: desired,
  );
  final plan = buildConversationPlan(gaps, addressed: addressed);
  final writeback = TrilhaWriteback(repo, userId);

  return ConversationController(plan, onAnswer: (answer) async {
    await writeback.save(answer);
    // Marca o trecho como abordado pra não re-perguntar nas próximas aberturas.
    await prog.markFromStep(userId, answer.stepId);
    // Telemetria (5c): conta os trechos respondidos.
    final segment = TrilhaProgress.segmentForStep(answer.stepId);
    if (segment != null) {
      // ignore: unawaited_futures
      Analytics.shared
          .track(evTrilhaColetaStepAnswered, props: {'segment': segment});
    }
  });
}
