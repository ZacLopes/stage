import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/domain/skill_name_normalizer.dart';
import '../domain/guided_skills_write.dart';

typedef GuidedProfileMergeRpcCall =
    Future<Object?> Function(String function, Map<String, dynamic> params);

/// Implementação Supabase de [GuidedSkillsWriter]. Chama
/// `merge_guided_profile_list(section='skills')`. Injetável via [rpcCall] (ou
/// [client]) para testes com spy — não acopla o domínio ao singleton Supabase.
class GuidedSkillsWriterSupabase implements GuidedSkillsWriter {
  GuidedSkillsWriterSupabase({
    SupabaseClient? client,
    GuidedProfileMergeRpcCall? rpcCall,
  }) : _rpcCall =
           rpcCall ??
           ((function, params) => (client ?? Supabase.instance.client).rpc(
             function,
             params: params,
           ));

  final GuidedProfileMergeRpcCall _rpcCall;

  @override
  Future<GuidedSkillsMergeReceipt> mergeSkills({
    required String userId,
    required List<String> names,
  }) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'required');
    }
    // Normaliza (trim/colapso/dobra de acento) e remove duplicatas
    // equivalentes preservando ordem e grafia — o servidor dedup de novo sob
    // lock, mas mandar payload limpo mantém o recibo honesto.
    final normalized = normalizeSkillNames(names);
    if (normalized.isEmpty) {
      throw ArgumentError.value(names, 'names', 'no_valid_skill');
    }
    // Limite de array do contrato SQL (`jsonb_array_length > 50` falha).
    // Falhar aqui evita um round-trip que o servidor recusaria de qualquer
    // forma. O limite de 12 skills totais é aplicado no servidor (aditivo,
    // contra o estado vivo) e volta como erro do RPC — nunca como sucesso.
    if (normalized.length > _maxMergeItems) {
      throw ArgumentError.value(normalized.length, 'names', 'too_many_items');
    }
    final raw = await _rpcCall('merge_guided_profile_list', <String, dynamic>{
      'p_user_id': userId,
      'p_section': 'skills',
      'p_items': normalized,
    });
    return GuidedSkillsMergeReceipt.fromRpc(raw);
  }
}

const int _maxMergeItems = 50;
