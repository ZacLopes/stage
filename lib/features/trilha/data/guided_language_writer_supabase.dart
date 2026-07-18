import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/guided_language_write.dart';

typedef GuidedLanguageRpcCall =
    Future<Object?> Function(String function, Map<String, dynamic> params);

/// Implementação Supabase de [GuidedLanguageWriter]. Injetável via [rpcCall]
/// (ou [client]) para testes com spy — não acopla o domínio ao singleton.
class GuidedLanguageWriterSupabase implements GuidedLanguageWriter {
  GuidedLanguageWriterSupabase({
    SupabaseClient? client,
    GuidedLanguageRpcCall? rpcCall,
  }) : _rpcCall =
           rpcCall ??
           ((function, params) => (client ?? Supabase.instance.client).rpc(
             function,
             params: params,
           ));

  final GuidedLanguageRpcCall _rpcCall;

  @override
  Future<GuidedLanguageMergeReceipt> mergeLanguages({
    required String userId,
    required List<String> names,
  }) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'required');
    }
    final normalized = _normalizeNames(names);
    if (normalized.isEmpty) {
      throw ArgumentError.value(names, 'names', 'no_valid_language');
    }
    if (normalized.length > _maxItems) {
      throw ArgumentError.value(normalized.length, 'names', 'too_many_items');
    }
    final raw = await _rpcCall('merge_guided_profile_list', <String, dynamic>{
      'p_user_id': userId,
      'p_section': 'languages',
      'p_items': normalized,
    });
    return GuidedLanguageMergeReceipt.fromRpc(raw);
  }

  @override
  Future<GuidedLanguageLevelReceipt> setLevel({
    required String userId,
    required String name,
    required String? expectedLevel,
    required String newLevel,
  }) async {
    final cleanName = _cleanName(name);
    if (userId.trim().isEmpty || cleanName.isEmpty) {
      throw ArgumentError('language_level_request_invalid');
    }
    _assertLevel(newLevel, 'newLevel');
    if (expectedLevel != null) _assertLevel(expectedLevel, 'expectedLevel');
    final raw = await _rpcCall(
      'set_guided_language_level_cas',
      <String, dynamic>{
        'p_user_id': userId,
        'p_name': cleanName,
        'p_expected_level': expectedLevel,
        'p_new_level': newLevel,
      },
    );
    return GuidedLanguageLevelReceipt.fromRpc(raw);
  }

  @override
  Future<GuidedLanguageRemoveReceipt> removeLanguage({
    required String userId,
    required String name,
    required String? expectedLevel,
  }) async {
    final cleanName = _cleanName(name);
    if (userId.trim().isEmpty || cleanName.isEmpty) {
      throw ArgumentError('language_remove_request_invalid');
    }
    if (expectedLevel != null) _assertLevel(expectedLevel, 'expectedLevel');
    final raw = await _rpcCall('remove_guided_language_cas', <String, dynamic>{
      'p_user_id': userId,
      'p_name': cleanName,
      'p_expected_level': expectedLevel,
    });
    return GuidedLanguageRemoveReceipt.fromRpc(raw);
  }

  static void _assertLevel(String level, String label) {
    if (!kLanguageLevels.contains(level)) {
      throw ArgumentError.value(level, label, 'invalid_language_level');
    }
  }
}

const int _maxItems = 50;

String _cleanName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

List<String> _normalizeNames(Iterable<String> names) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in names) {
    final name = _cleanName(raw);
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    if (!seen.add(key)) continue;
    result.add(name);
  }
  return result;
}
