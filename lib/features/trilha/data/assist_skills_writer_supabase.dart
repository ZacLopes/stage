import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/domain/skill_name_normalizer.dart';
import '../domain/assist_skills_write.dart';

typedef AssistSkillsRpcCall =
    Future<Object?> Function(String function, Map<String, dynamic> params);

class AssistSkillsWriterSupabase implements AssistSkillsWriter {
  AssistSkillsWriterSupabase({
    SupabaseClient? client,
    AssistSkillsRpcCall? rpcCall,
  }) : _rpcCall =
           rpcCall ??
           ((function, params) => (client ?? Supabase.instance.client).rpc(
             function,
             params: params,
           ));

  final AssistSkillsRpcCall _rpcCall;

  @override
  Future<AssistSkillsOpenReceipt> open({
    required String userId,
    required String operationId,
  }) async {
    _validateRequest(
      userId: userId,
      operationId: operationId,
      expectedCount: 0,
      desiredCount: 0,
    );
    final raw = await _rpcCall('open_assist_skills_edit_v1', <String, dynamic>{
      'p_user_id': userId,
      'p_operation_id': operationId,
    });
    final receipt = AssistSkillsOpenReceipt.fromRpc(raw);
    if (receipt.operationId != operationId) {
      throw const AssistSkillsWriteContractException('operation_id_mismatch');
    }
    if (receipt.baseline.length > 50) {
      throw const AssistSkillsWriteContractException('baseline_too_large');
    }
    return receipt;
  }

  @override
  Future<AssistSkillsApplyReceipt> apply({
    required String userId,
    required String operationId,
    required List<String> expected,
    required List<String> desired,
  }) async {
    final normalizedExpected = normalizeSkillNames(expected);
    final normalizedDesired = normalizeSkillNames(desired);
    _validateRequest(
      userId: userId,
      operationId: operationId,
      expectedCount: normalizedExpected.length,
      desiredCount: normalizedDesired.length,
    );
    final raw = await _rpcCall('apply_assist_skills_edit_v1', <String, dynamic>{
      'p_user_id': userId,
      'p_operation_id': operationId,
      'p_expected_names': normalizedExpected,
      'p_names': normalizedDesired,
    });
    final receipt = AssistSkillsApplyReceipt.fromRpc(raw);
    if (receipt.operationId != operationId) {
      throw const AssistSkillsWriteContractException('operation_id_mismatch');
    }
    final liveMatchesDesired = _sameOrderedSkills(
      receipt.live,
      normalizedDesired,
    );
    final resultingMatchesDesired = _sameOrderedSkills(
      receipt.resulting,
      normalizedDesired,
    );
    switch (receipt.outcome) {
      case AssistSkillsApplyOutcome.applied:
      case AssistSkillsApplyOutcome.noop:
        if (!resultingMatchesDesired ||
            (!receipt.replayed && !liveMatchesDesired) ||
            (receipt.canUndo && !liveMatchesDesired)) {
          throw const AssistSkillsWriteContractException(
            'confirmed_live_mismatch',
          );
        }
        break;
      case AssistSkillsApplyOutcome.stale:
        // CAS integral também observa identidade/metadados. Um stale pode ter
        // os mesmos NOMES de expected ou desired; o receipt tipado do servidor
        // continua autoritativo e o cliente não tenta reconstituir row equality.
        break;
      case AssistSkillsApplyOutcome.undone:
        if (!receipt.replayed || !resultingMatchesDesired) {
          throw const AssistSkillsWriteContractException(
            'undone_live_mismatch',
          );
        }
        break;
    }
    return receipt;
  }

  @override
  Future<AssistSkillsUndoReceipt> undo({
    required String userId,
    required String operationId,
    required List<String> expectedRestored,
  }) async {
    final normalizedExpected = normalizeSkillNames(expectedRestored);
    _validateRequest(
      userId: userId,
      operationId: operationId,
      expectedCount: normalizedExpected.length,
      desiredCount: 0,
    );
    final raw = await _rpcCall('undo_assist_skills_edit_v1', <String, dynamic>{
      'p_user_id': userId,
      'p_operation_id': operationId,
    });
    final receipt = AssistSkillsUndoReceipt.fromRpc(raw);
    if (receipt.operationId != operationId) {
      throw const AssistSkillsWriteContractException('operation_id_mismatch');
    }
    if (!_sameOrderedSkills(receipt.resulting, normalizedExpected) ||
        (!receipt.replayed &&
            receipt.outcome == AssistSkillsUndoOutcome.undone &&
            !_sameOrderedSkills(receipt.live, normalizedExpected))) {
      throw const AssistSkillsWriteContractException(
        'restored_result_mismatch',
      );
    }
    return receipt;
  }

  static void _validateRequest({
    required String userId,
    required String operationId,
    required int expectedCount,
    required int desiredCount,
  }) {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'required');
    }
    if (!_uuidPattern.hasMatch(operationId)) {
      throw ArgumentError.value(operationId, 'operationId', 'invalid_uuid');
    }
    if (expectedCount > 50 || desiredCount > kMaxProfileSkills) {
      throw ArgumentError('skills_limit_exceeded');
    }
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
  r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

bool _sameOrderedSkills(Iterable<String> left, Iterable<String> right) {
  final a = left.map(foldSkillName).toList(growable: false);
  final b = right.map(foldSkillName).toList(growable: false);
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
