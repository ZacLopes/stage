import 'package:career_gamification/features/gamification/services/trail_to_profile_bridge.dart';
import 'package:career_gamification/features/profile/domain/repositories/profile_repository.dart';
import 'package:career_gamification/features/trilha/domain/guided_skills_write.dart';
import 'package:flutter_test/flutter_test.dart';

/// Qualquer toque neste repo é uma regressão do cutover 3.0C: o ramo de skills
/// não pode mais fazer `getSkills`/`replaceSkills`.
class _ThrowingRepo implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('repo tocado: ${invocation.memberName}');
}

class _SpyGuidedSkillsWriter implements GuidedSkillsWriter {
  final List<List<String>> mergedNames = [];
  final List<String> mergedUserIds = [];
  Object? throwOnMerge;
  int calls = 0;

  @override
  Future<GuidedSkillsMergeReceipt> mergeSkills({
    required String userId,
    required List<String> names,
  }) async {
    calls++;
    mergedUserIds.add(userId);
    mergedNames.add(List<String>.from(names));
    if (throwOnMerge != null) throw throwOnMerge!;
    return GuidedSkillsMergeReceipt.fromRpc(<String, dynamic>{
      'status': names.isEmpty ? 'noop' : 'applied',
      'inserted': names.length,
      'updated': 0,
      'changed': names.length,
    });
  }
}

void main() {
  late _SpyGuidedSkillsWriter guided;
  late TrailToProfileBridge bridge;

  setUp(() {
    guided = _SpyGuidedSkillsWriter();
    bridge = TrailToProfileBridge(
      _ThrowingRepo(),
      guidedSkillsWriter: guided,
      currentUserId: () => 'user-a',
    );
  });

  test('m4.1 (skills) roteia pelo merge aditivo, sem tocar o repo', () async {
    await bridge.route(phaseId: 'm4.1', answer: ['Excel', 'Python']);
    expect(guided.mergedNames, [
      ['Excel', 'Python'],
    ]);
    expect(guided.mergedUserIds, ['user-a']); // userId vem do resolver injetado
  });

  test('resposta vazia de skills → não chama o writer', () async {
    await bridge.route(phaseId: 'm4.1', answer: <String>[]);
    expect(guided.calls, 0);
  });

  test(
    'bridge é defensiva: falha do merge NÃO derruba a trilha legacy',
    () async {
      guided.throwOnMerge = StateError('too_many_items');
      // route() engole o erro (contrato pré-existente) — não deve relançar.
      await bridge.route(phaseId: 'm4.1', answer: ['Excel']);
      expect(guided.calls, 1);
    },
  );

  test('sem usuário logado → no-op (não chama o writer)', () async {
    final b = TrailToProfileBridge(
      _ThrowingRepo(),
      guidedSkillsWriter: guided,
      currentUserId: () => null,
    );
    await b.route(phaseId: 'm4.1', answer: ['Excel']);
    expect(guided.calls, 0);
  });
}
