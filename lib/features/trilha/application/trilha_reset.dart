// Reset do PROGRESSO da trilha de coleta (PLANO-FASE-6 — ferramenta [DEV]).
//
// Limpa SÓ o progresso (o que faz a trilha re-perguntar as lacunas), MANTENDO
// os dados já coletados em profile_*. O progresso vive em dois lugares (híbrido):
//
//   LOCAL (SharedPreferences — fonte autoritativa do "abordado"):
//     - trilha_addressed_<uid>  : segmentos abordados
//     - trilha_drafts_<uid>     : rascunhos de itens multi-passo (exp/projeto/edu)
//     - trilha_draft_<stepId>   : autosave de texto guiado (por passo)
//   SERVIDOR:
//     - profile_guided_progress : segmentos abordados (retomada cross-device)
//
// Limpar só o servidor NÃO basta: `TrilhaProgress.addressed` faz local ∪ server,
// então o cache local manteria os segmentos. Por isso limpamos os dois.

import 'package:shared_preferences/shared_preferences.dart';

import '../../profile/data/repositories/profile_repository_supabase.dart';
import '../../profile/domain/repositories/profile_repository.dart';

/// Reseta o progresso da trilha de [userId] (local + servidor). Failure-safe no
/// servidor: offline → limpa só o local e segue (não bloqueia o reset).
Future<void> resetTrilhaProgress(
  String userId, {
  ProfileRepository? repository,
}) async {
  final prefs = await SharedPreferences.getInstance();

  // Cache LOCAL.
  await prefs.remove('trilha_addressed_$userId');
  await prefs.remove('trilha_drafts_$userId');
  // Autosaves de texto guiado (chaveados por stepId — prefixo trilha_draft_).
  final autosaves =
      prefs.getKeys().where((k) => k.startsWith('trilha_draft_')).toList();
  for (final k in autosaves) {
    await prefs.remove(k);
  }

  // Servidor (profile_guided_progress) — não derruba o reset se falhar.
  final repo = repository ?? ProfileRepositorySupabase();
  try {
    await repo.clearGuidedProgress(userId);
  } catch (_) {/* offline: o local já foi limpo; segue */}
}
