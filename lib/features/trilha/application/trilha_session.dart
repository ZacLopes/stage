// Montagem da sessão da trilha (PLANO-FASE-6 T6.3, Increment 2c).
//
// Junta as peças: carrega o perfil real do usuário → calcula as lacunas
// (cérebro de lacunas) → monta o plano adaptativo → cria o ConversationController
// já com o write-back plugado (grava em profile_* a cada resposta).

import '../../../services/profile_snapshot_service.dart';
import '../../profile/application/profile_gaps.dart';
import '../../profile/data/repositories/profile_repository_supabase.dart';
import '../../profile/domain/repositories/profile_repository.dart';
import 'conversation_controller.dart';
import 'conversation_plan.dart';
import 'trilha_writeback.dart';

/// Constrói o controller da trilha para [userId], carregando o perfil real e
/// montando o plano só com o que falta. O controller resultante grava cada
/// resposta em profile_* via [TrilhaWriteback]. Se o perfil já estiver completo
/// (dentro do que esta fase cobre), o controller vem com 0 passos.
Future<ConversationController> buildTrilhaController(
  String userId, {
  ProfileRepository? repository,
  ProfileSnapshotService? snapshotService,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final snapSvc = snapshotService ?? ProfileSnapshotService();

  final snapshot = await snapSvc.loadSnapshot(userId);
  final prefs = await repo.getJobPreferences(userId);
  final desired = await repo.getDesiredTitles(userId);

  final gaps = profileGapsFromData(
    snapshot: snapshot,
    prefs: prefs,
    desiredTitles: desired,
  );
  final plan = buildConversationPlan(gaps);
  final writeback = TrilhaWriteback(repo, userId);

  return ConversationController(plan, onAnswer: writeback.save);
}
