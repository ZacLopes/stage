// Gate 3.0I — agregado HONESTO do `apply_reviewed_conflicts_and_promote`.
//
// O RPC devolve `{applied, stale, rejected, failed, promoted}` (arrays de
// rótulos + flag). Este tipo faz o parsing fail-closed e expõe contagens/estado
// pro card refletir a VERDADE — nunca um "aplicado" cego numa falha parcial:
//   - applied  : escolhas gravadas
//   - stale    : você já tinha editado desde a leitura → o manual venceu (CAS)
//   - rejected : não deu pra casar/validar (data/campo inválido, item ruim)
//   - failed   : rollback GLOBAL (só em erro inesperado; nada foi aplicado)
//   - promoted : a candidata virou a fonte atual (só quando failed está vazio)
//
// Invariante do servidor: failed≠[] ⟺ promoted=false (rollback total).

class ImportApplyOutcome {
  final List<String> applied;
  final List<String> stale;
  final List<String> rejected;
  final List<String> failed;
  final bool promoted;

  const ImportApplyOutcome({
    this.applied = const [],
    this.stale = const [],
    this.rejected = const [],
    this.failed = const [],
    this.promoted = false,
  });

  int get appliedCount => applied.length;
  int get staleCount => stale.length;
  int get rejectedCount => rejected.length;

  /// Falha dura: rollback global, nada aplicado, não promoveu.
  bool get isHardFailure => !promoted && failed.isNotEmpty;

  /// Tudo aplicou e promoveu, sem manter-manual nem rejeição.
  bool get isCleanSuccess =>
      promoted && failed.isEmpty && stale.isEmpty && rejected.isEmpty;

  /// Promoveu, mas parte foi mantida (manual venceu) ou rejeitada.
  bool get isPartial =>
      promoted && (stale.isNotEmpty || rejected.isNotEmpty);

  /// Parsing fail-closed do retorno do RPC. Qualquer coisa que não seja um mapa
  /// reconhecível vira uma falha dura (promoted:false, failed com um marcador) —
  /// nunca um sucesso otimista.
  factory ImportApplyOutcome.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const ImportApplyOutcome(failed: ['malformed_result']);
    }
    return ImportApplyOutcome(
      applied: _strList(raw['applied']),
      stale: _strList(raw['stale']),
      rejected: _strList(raw['rejected']),
      failed: _strList(raw['failed']),
      promoted: raw['promoted'] == true,
    );
  }

  static List<String> _strList(dynamic v) {
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e != null) e.toString(),
    ];
  }
}
