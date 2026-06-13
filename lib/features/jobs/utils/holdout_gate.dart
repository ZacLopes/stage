import 'match_score.dart';

/// FASE 2 (T2.4, §5/D3 do PLANO-FASE-2): gate de elegibilidade do holdout
/// `match_score_visibility_v1` (PostHog id 693925, variantes percent/hidden).
///
/// Responde "o match do pitch é verdade?": 20% dos ELEGÍVEIS deixam de ver
/// banda/chips pré-swipe; se o gap de save-rate alta−baixa colapsar no
/// grupo hidden, a exibição pré-swipe é ancoragem, não sinal.
///
/// Elegibilidade = confidence ∈ {high, medium} — EXATAMENTE o gate que
/// decide se o número aparece hoje. Randomizar sobre todos contaminaria:
/// os ~28% sem score são selecionados por completude de perfil, não
/// aleatórios. `low` → NÃO avalia a flag (não entra no experimento).
///
/// Failure-safe: erro/null na flag = controle ('percent', score visível).
const String kMatchVisibilityFlag = 'match_score_visibility_v1';

Future<String?> resolveHoldoutVariant({
  required MatchConfidence confidence,
  required Future<String?> Function(String flagKey) getFlag,
}) async {
  if (confidence == MatchConfidence.low) return null; // não-elegível
  try {
    return await getFlag(kMatchVisibilityFlag) ?? 'percent';
  } catch (_) {
    return 'percent'; // failure-safe = controle
  }
}

/// O que o user VÊ pré-swipe dado a variante ('hidden' esconde banda e
/// chips; null = não-elegível, comportamento atual = visível-se-confidence).
bool scoreVisibleFor(String? variant) => variant != 'hidden';
