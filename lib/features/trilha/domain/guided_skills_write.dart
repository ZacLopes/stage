// Gate 3.0C — contrato tipado do cutover da escrita ADITIVA de skills da coleta
// guiada para `merge_guided_profile_list(section='skills')`.
//
// Espelha a filosofia fail-closed do editor visual 3.0B
// (`assist_skills_write.dart`): uma resposta ausente, malformada ou
// internamente contraditória NUNCA pode ser lida como sucesso. O merge é
// ADITIVO — só insere skills novas; nunca faz replace, UPDATE de linha ou
// remoção — portanto o recibo cobre apenas `applied`/`noop`.

/// Exceção fail-closed do contrato de merge guiado.
class GuidedProfileMergeContractException implements Exception {
  const GuidedProfileMergeContractException(this.code);

  final String code;

  @override
  String toString() => 'GuidedProfileMergeContractException($code)';
}

enum GuidedSkillsMergeOutcome { applied, noop }

/// Recibo tipado de `merge_guided_profile_list(section='skills')`.
///
/// O contrato SQL retorna `{status, inserted, updated, changed}`. Para skills o
/// caminho é aditivo puro: só há INSERT do que falta, então `updated` tem de
/// ser 0 e `changed == inserted`. Qualquer divergência falha fechado em vez de
/// virar um falso "aplicado".
class GuidedSkillsMergeReceipt {
  const GuidedSkillsMergeReceipt._({
    required this.outcome,
    required this.inserted,
  });

  final GuidedSkillsMergeOutcome outcome;

  /// Quantas skills novas foram efetivamente inseridas nesta operação.
  final int inserted;

  /// `true` somente quando o merge realmente adicionou algo. Um `noop`
  /// honesto (todas as skills já presentes) continua sendo sucesso para a
  /// coleta guiada, mas não anuncia adição.
  bool get changed => outcome == GuidedSkillsMergeOutcome.applied;

  factory GuidedSkillsMergeReceipt.fromRpc(Object? raw) {
    if (raw is! Map) {
      throw const GuidedProfileMergeContractException('receipt_not_object');
    }
    final status = raw['status'];
    if (status != 'applied' && status != 'noop') {
      throw const GuidedProfileMergeContractException('invalid_merge_status');
    }
    final inserted = raw['inserted'];
    final updated = raw['updated'];
    final changed = raw['changed'];
    if (inserted is! int ||
        inserted < 0 ||
        updated is! int ||
        updated < 0 ||
        changed is! int ||
        changed < 0) {
      throw const GuidedProfileMergeContractException('invalid_merge_counts');
    }
    // Skills nunca atualiza uma linha existente; só insere o que falta.
    if (updated != 0) {
      throw const GuidedProfileMergeContractException(
        'unexpected_skill_update',
      );
    }
    if (changed != inserted + updated) {
      throw const GuidedProfileMergeContractException(
        'inconsistent_merge_counts',
      );
    }
    final applied = status == 'applied';
    if (applied != (changed > 0)) {
      throw const GuidedProfileMergeContractException('status_count_mismatch');
    }
    return GuidedSkillsMergeReceipt._(
      outcome: applied
          ? GuidedSkillsMergeOutcome.applied
          : GuidedSkillsMergeOutcome.noop,
      inserted: inserted,
    );
  }
}

/// Escreve skills da COLETA GUIADA pelo contrato server-side aditivo e
/// idempotente. Substitui o caminho `get → replaceSkills` (TOCTOU) nos dois
/// callers aditivos incluídos no Gate 3.0C: [TrilhaWriteback] e
/// [TrailToProfileBridge]. NÃO faz replace, remoção nem undo (fora de escopo).
abstract interface class GuidedSkillsWriter {
  /// Garante que [names] estejam presentes em `profile_skills` (merge aditivo).
  /// Idempotente: um retry do mesmo passo termina como `applied`/`noop`, sem
  /// duplicar. Lança em resposta malformada, payload inválido ou estouro do
  /// limite server-side de 12 skills — nunca finge sucesso.
  Future<GuidedSkillsMergeReceipt> mergeSkills({
    required String userId,
    required List<String> names,
  });
}
