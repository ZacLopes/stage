/// Gate único da adaptação de currículo por vaga.
///
/// ## Por que existe (Bloqueador C do device-test, 24/07)
///
/// O pré-check do client e o validador anti-invenção da Edge **discordavam**:
///
/// - `ProfileSnapshot.canAdaptCv` exige material narrativo (experiência,
///   projeto, formação com conteúdo ou CV importado) e **nunca olha skills**.
/// - O validador (`v2.ts:1676-1698`) faz `translationSlots = extraSkills.length`
///   e rejeita qualquer skill de saída que não bata exato com a entrada. Com 0
///   skills no perfil e a folha de extras pulada, `translationSlots = 0` e
///   **qualquer** skill emitida derruba a adaptação no primeiro item.
///
/// Ou seja: o gate deixava entrar quem o validador ia expulsar — depois de
/// ~25 s de espera, com "Tente novamente" numa falha determinística.
///
/// Medido em produção (26/07): **745 de 1.530 usuários (48,7%)** que passavam
/// no gate tinham **zero** skills. O §11 do device-test provou o mecanismo em
/// experimento controlado: 0 → 3 skills, nada mais alterado, e a adaptação
/// passou.
///
/// ## O limiar
///
/// 3, por decisão do fundador (26/07). A distribuição em prod é **bimodal** —
/// 745 usuários com 0 skills, apenas **72** na faixa 1–2, e 713 com 3+ —, então
/// exigir 3 em vez de 1 barra só 72 pessoas a mais e garante uma seção de
/// habilidades apresentável no PDF.
library;

import '../../profile/domain/skill_name_normalizer.dart';

const int kMinSkillsToAdapt = 3;

/// Resultado do gate. Cada valor mapeia para uma copy e uma saída próprias
/// (ver `adaptation_error_copy.dart`).
enum AdaptGateResult {
  /// Tem material narrativo E skills suficientes.
  allowed,

  /// Falta material narrativo (experiência/projeto/formação/CV importado).
  /// Código de erro histórico: `profile_incomplete`.
  missingMaterial,

  /// Tem material, mas menos de [kMinSkillsToAdapt] skills. Código novo:
  /// `missing_skills`.
  missingSkills,
}

extension AdaptGateResultX on AdaptGateResult {
  /// Código usado em analytics (`adapt_failed.error_code`) e para escolher a
  /// copy. Mantém `profile_incomplete` para não quebrar a série histórica.
  String get errorCode => switch (this) {
        AdaptGateResult.allowed => '',
        AdaptGateResult.missingMaterial => 'profile_incomplete',
        AdaptGateResult.missingSkills => 'missing_skills',
      };
}

/// Avalia o gate. Função pura — sem Provider, sem rede, sem Supabase.
///
/// Ordem deliberada: material primeiro. Quem não tem nem experiência nem skills
/// recebe a mensagem do buraco maior, não a do menor.
///
/// [skillCountIsReliable] existe porque `ProfileSnapshotService.loadSnapshot` é
/// best-effort POR TABELA: se a consulta de `profile_skills` falhar sozinha, o
/// snapshot volta com `skills: []` e o resto carregado — indistinguível de quem
/// realmente não tem nenhuma. Bloquear nesse estado barraria alguém com 7
/// habilidades, com uma mensagem falsa e sem oferecer retry.
///
/// Na dúvida, **liberamos**: o custo de deixar passar é o comportamento
/// anterior à F6 (o servidor recusa em ~25 s); o custo de barrar errado é
/// mentir para quem fez tudo certo. Achado do code-review de 27/07.
AdaptGateResult evaluateAdaptGate({
  required bool hasNarrativeMaterial,
  required int skillCount,
  bool skillCountIsReliable = true,
}) {
  if (!hasNarrativeMaterial) return AdaptGateResult.missingMaterial;
  if (!skillCountIsReliable) return AdaptGateResult.allowed;
  if (skillCount < kMinSkillsToAdapt) return AdaptGateResult.missingSkills;
  return AdaptGateResult.allowed;
}

/// Quantas skills ainda faltam para destravar a adaptação. 0 quando já dá.
///
/// Existe para a copy poder dizer "faltam 2" a quem já começou, em vez de
/// tratar quem tem 1–2 skills como quem tem zero.
int missingSkillsToAdapt(int skillCount) {
  final missing = kMinSkillsToAdapt - skillCount;
  return missing > 0 ? missing : 0;
}

/// Copy do corpo da mensagem quando o gate barra por falta de skills.
String missingSkillsMessage(int skillCount) {
  final missing = missingSkillsToAdapt(skillCount);
  if (skillCount <= 0) {
    // O "(o ideal é de 6 a 12)" existe pra casar com o texto do editor de
    // habilidades, que recomenda essa faixa. Sem isso, a pessoa lia "pelo
    // menos 3" aqui e "priorize de 6 a 12" na tela seguinte, em menos de um
    // minuto — dois limiares diferentes pra mesma tarefa.
    // Revisão UX 28/07, achado P2-28.
    return 'Pra adaptar seu currículo pra uma vaga, preciso saber o que você '
        'sabe fazer. Adicione pelo menos $kMinSkillsToAdapt habilidades ao seu '
        'perfil (o ideal é de $kRecommendedMinProfileSkills a '
        '$kMaxProfileSkills) e eu cuido do resto.';
  }
  final plural = missing == 1 ? 'habilidade' : 'habilidades';
  return 'Você já tem $skillCount. Adicione mais $missing $plural ao seu perfil '
      'e eu consigo adaptar seu currículo pra esta vaga.';
}
