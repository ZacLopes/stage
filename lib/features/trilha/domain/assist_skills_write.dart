import 'dart:math';

import '../../profile/domain/skill_name_normalizer.dart';

enum AssistSkillsApplyOutcome { applied, noop, stale, undone }

enum AssistSkillsUndoOutcome { undone, stale }

class AssistSkillsOpenReceipt {
  const AssistSkillsOpenReceipt._({
    required this.replayed,
    required this.operationId,
    required this.baseline,
    required this.count,
  });

  final bool replayed;
  final String operationId;
  final List<String> baseline;
  final int count;

  factory AssistSkillsOpenReceipt.fromRpc(Object? raw) {
    final map = _receiptMap(raw);
    final status = map['status'];
    if (status != 'opened' && status != 'replay') {
      throw const AssistSkillsWriteContractException('invalid_open_status');
    }
    final common = _parseNamedList(map, listKey: 'baseline', countKey: 'count');
    return AssistSkillsOpenReceipt._(
      replayed: status == 'replay',
      operationId: common.operationId,
      baseline: common.values,
      count: common.count,
    );
  }
}

class AssistSkillsApplyReceipt {
  const AssistSkillsApplyReceipt._({
    required this.outcome,
    required this.replayed,
    required this.operationId,
    required this.live,
    required this.resulting,
    required this.count,
    required this.canUndo,
  });

  final AssistSkillsApplyOutcome outcome;
  final bool replayed;
  final String operationId;
  final List<String> live;

  /// Estado imutável imediatamente após a operação original. Em replay,
  /// [live] pode conter uma edição manual posterior; autoria/diff usam isto.
  final List<String> resulting;
  final int count;
  final bool canUndo;

  bool get confirmed =>
      outcome == AssistSkillsApplyOutcome.applied ||
      outcome == AssistSkillsApplyOutcome.noop;

  factory AssistSkillsApplyReceipt.fromRpc(Object? raw) {
    final map = _receiptMap(raw);
    final status = map['status'];
    final outcomeRaw = map['outcome'];
    final replayed = status == 'replay';
    if (!replayed &&
        status != 'applied' &&
        status != 'noop' &&
        status != 'stale') {
      throw const AssistSkillsWriteContractException('invalid_apply_status');
    }
    final outcome = switch (outcomeRaw) {
      'applied' => AssistSkillsApplyOutcome.applied,
      'noop' => AssistSkillsApplyOutcome.noop,
      'stale' => AssistSkillsApplyOutcome.stale,
      'undone' => AssistSkillsApplyOutcome.undone,
      _ => throw const AssistSkillsWriteContractException(
        'invalid_apply_outcome',
      ),
    };
    if (!replayed && status != outcomeRaw) {
      throw const AssistSkillsWriteContractException(
        'apply_status_outcome_mismatch',
      );
    }
    if (!replayed && outcome == AssistSkillsApplyOutcome.undone) {
      throw const AssistSkillsWriteContractException(
        'unexpected_undone_outcome',
      );
    }
    final canUndo = map['can_undo'];
    if (canUndo is! bool ||
        (outcome != AssistSkillsApplyOutcome.applied && canUndo) ||
        (!replayed &&
            outcome == AssistSkillsApplyOutcome.applied &&
            !canUndo)) {
      throw const AssistSkillsWriteContractException('invalid_can_undo');
    }
    final common = _parseCommon(map);
    final resulting = _parseSkillValues(map['resulting']);
    return AssistSkillsApplyReceipt._(
      outcome: outcome,
      replayed: replayed,
      operationId: common.operationId,
      live: common.live,
      resulting: resulting,
      count: common.count,
      canUndo: canUndo,
    );
  }
}

class AssistSkillsUndoReceipt {
  const AssistSkillsUndoReceipt._({
    required this.outcome,
    required this.replayed,
    required this.operationId,
    required this.live,
    required this.resulting,
    required this.count,
  });

  final AssistSkillsUndoOutcome outcome;
  final bool replayed;
  final String operationId;
  final List<String> live;

  /// Baseline que a operação de undo pretendia restaurar. Em replay,
  /// [live] pode conter uma edição posterior e não deve ser atribuída ao card.
  final List<String> resulting;
  final int count;

  factory AssistSkillsUndoReceipt.fromRpc(Object? raw) {
    final map = _receiptMap(raw);
    final status = map['status'];
    final outcomeRaw = map['outcome'];
    final replayed = status == 'replay';
    if (!replayed && status != 'undone' && status != 'stale') {
      throw const AssistSkillsWriteContractException('invalid_undo_status');
    }
    final outcome = switch (outcomeRaw) {
      'undone' => AssistSkillsUndoOutcome.undone,
      'stale' => AssistSkillsUndoOutcome.stale,
      _ => throw const AssistSkillsWriteContractException(
        'invalid_undo_outcome',
      ),
    };
    if (!replayed && status != outcomeRaw) {
      throw const AssistSkillsWriteContractException(
        'undo_status_outcome_mismatch',
      );
    }
    if (replayed && outcome != AssistSkillsUndoOutcome.undone) {
      throw const AssistSkillsWriteContractException('invalid_undo_replay');
    }
    final common = _parseCommon(map);
    final resulting = _parseSkillValues(map['resulting']);
    return AssistSkillsUndoReceipt._(
      outcome: outcome,
      replayed: replayed,
      operationId: common.operationId,
      live: common.live,
      resulting: resulting,
      count: common.count,
    );
  }
}

class AssistSkillsWriteContractException implements Exception {
  const AssistSkillsWriteContractException(this.code);

  final String code;

  @override
  String toString() => 'AssistSkillsWriteContractException($code)';
}

abstract interface class AssistSkillsWriter {
  Future<AssistSkillsOpenReceipt> open({
    required String userId,
    required String operationId,
  });

  Future<AssistSkillsApplyReceipt> apply({
    required String userId,
    required String operationId,
    required List<String> expected,
    required List<String> desired,
  });

  Future<AssistSkillsUndoReceipt> undo({
    required String userId,
    required String operationId,
    required List<String> expectedRestored,
  });
}

final Random _operationRandom = Random.secure();

/// UUID v4 sem dependência externa. É criado uma vez com o card e reutilizado
/// em todo retry, permitindo que o servidor devolva o recibo original.
String newAssistSkillsOperationId() {
  final bytes = List<int>.generate(16, (_) => _operationRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

Map<Object?, Object?> _receiptMap(Object? raw) {
  if (raw is! Map) {
    throw const AssistSkillsWriteContractException('receipt_not_object');
  }
  return raw;
}

({String operationId, List<String> live, int count}) _parseCommon(
  Map<Object?, Object?> map,
) {
  final parsed = _parseNamedList(
    map,
    listKey: 'live',
    countKey: 'count',
    allowEquivalentDuplicates: true,
  );
  return (
    operationId: parsed.operationId,
    live: parsed.values,
    count: parsed.count,
  );
}

({String operationId, List<String> values, int count}) _parseNamedList(
  Map<Object?, Object?> map, {
  required String listKey,
  required String countKey,
  bool allowEquivalentDuplicates = false,
}) {
  final operationId = map['operation_id'];
  final valuesRaw = map[listKey];
  final countRaw = map[countKey];
  if (operationId is! String ||
      operationId.isEmpty ||
      valuesRaw is! List ||
      valuesRaw.any((value) => value is! String) ||
      countRaw is! int ||
      countRaw < 0) {
    throw const AssistSkillsWriteContractException('invalid_payload');
  }
  final values = List<String>.unmodifiable(valuesRaw.cast<String>());
  if (allowEquivalentDuplicates) {
    // `live` é observação, não payload de escrita: um writer legado pode
    // ter criado blanks, whitespace ou duplicatas depois da abertura. O recibo
    // precisa preservar esse estado honestamente para o controller recarregar.
    if (values.length > _maxLiveReceiptItems) {
      throw const AssistSkillsWriteContractException('live_too_large');
    }
  } else {
    _parseSkillValues(values);
  }
  if (countRaw != values.length) {
    throw const AssistSkillsWriteContractException('inconsistent_payload');
  }
  return (operationId: operationId, values: values, count: countRaw);
}

List<String> _parseSkillValues(Object? raw) {
  if (raw is! List || raw.any((value) => value is! String)) {
    throw const AssistSkillsWriteContractException('invalid_skill_list');
  }
  final values = List<String>.unmodifiable(raw.cast<String>());
  if (values.any(
        (value) =>
            cleanSkillName(value) != value || foldSkillName(value).isEmpty,
      ) ||
      normalizeSkillNames(values).length != values.length) {
    throw const AssistSkillsWriteContractException('inconsistent_skill_list');
  }
  return values;
}

const int _maxLiveReceiptItems = 200;
