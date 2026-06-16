/// FASE 2 fixes: decisão A/B do estado de exaustão do feed.
///
/// Bug corrigido (15/06): depois de swipar TODAS as vagas que batiam com os
/// filtros, o app concluía "filtros muito restritivos" (B) — porque os totais
/// eram calculados DEPOIS de excluir as swipadas, então os matches viravam 0.
/// O certo é "você viu as relevantes" (A): havia matches, você passou por todos.
///
/// A distinção honesta usa [totalMatchingCatalog] = nº de vagas ativas que
/// batem com os filtros IGNORANDO swipes:
///   - == 0  → nenhuma vaga do catálogo bate → filtros restritivos de verdade (B)
///   - >  0  → havia relevantes; feed vazio = você esgotou (A)
///   - <  0  → desconhecido (caminho RPC ainda não fornece) → degrada pra A
///
/// Pura → testável sem Supabase (R3).
bool feedFiltersTooRestrictive({
  required bool prefsActive,
  required int totalAvailable,
  required int totalMatchingCatalog,
}) {
  if (!prefsActive) return false;
  if (totalMatchingCatalog < 0) return false; // desconhecido → não afirma B
  return totalAvailable > 0 && totalMatchingCatalog == 0;
}
