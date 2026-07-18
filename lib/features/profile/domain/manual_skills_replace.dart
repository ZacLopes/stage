// Gate 3.0D — contrato tipado do cutover do replace MANUAL de skills (Perfil)
// para `replace_profile_skills_atomic_v1`.
//
// Fail-closed: uma resposta ausente, malformada ou internamente incoerente
// NUNCA pode ser lida como sucesso. O contrato SQL faz replace atômico
// (preservando IDs/metadados dos itens retidos) e retorna {status, count},
// onde count é a quantidade de nomes distintos desejados.

/// Exceção fail-closed do contrato de replace manual de skills.
class ManualSkillsReplaceContractException implements Exception {
  const ManualSkillsReplaceContractException(this.code);

  final String code;

  @override
  String toString() => 'ManualSkillsReplaceContractException($code)';
}

enum ManualSkillsReplaceOutcome { applied, noop }

/// Recibo tipado de `replace_profile_skills_atomic_v1`.
class ManualSkillsReplaceReceipt {
  const ManualSkillsReplaceReceipt._({
    required this.outcome,
    required this.count,
  });

  final ManualSkillsReplaceOutcome outcome;

  /// Quantidade de skills distintas no estado final desejado.
  final int count;

  /// [expectedMax] é a quantidade de nomes normalizados enviados. O replace
  /// deduplica mas nunca inventa: o servidor não pode reportar mais itens do
  /// que recebeu.
  factory ManualSkillsReplaceReceipt.fromRpc(
    Object? raw, {
    required int expectedMax,
  }) {
    if (raw is! Map) {
      throw const ManualSkillsReplaceContractException('receipt_not_object');
    }
    final status = raw['status'];
    if (status != 'applied' && status != 'noop') {
      throw const ManualSkillsReplaceContractException('invalid_status');
    }
    final count = raw['count'];
    if (count is! int || count < 0 || count > expectedMax) {
      throw const ManualSkillsReplaceContractException('invalid_count');
    }
    return ManualSkillsReplaceReceipt._(
      outcome: status == 'applied'
          ? ManualSkillsReplaceOutcome.applied
          : ManualSkillsReplaceOutcome.noop,
      count: count,
    );
  }
}
