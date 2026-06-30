import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_gamification/features/profile/domain/repositories/profile_repository.dart';
import 'package:career_gamification/features/trilha/application/trilha_reset.dart';

/// Repo falso: só registra clearGuidedProgress; o resto lança via noSuchMethod.
class _FakeRepo implements ProfileRepository {
  final List<String> cleared = [];
  bool fail = false;

  @override
  Future<void> clearGuidedProgress(String userId) async {
    if (fail) throw Exception('network');
    cleared.add(userId);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} não deveria ser chamado');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('limpa os 3 caches locais do usuário + chama clearGuidedProgress',
      () async {
    SharedPreferences.setMockInitialValues({
      'trilha_addressed_u1': ['skills', 'area'],
      'trilha_drafts_u1': '[]',
      'trilha_draft_exp.0.company': 'Acme',
      'trilha_addressed_u2': ['skills'], // outro usuário: NÃO mexe
      'unrelated_key': 'x',
    });
    final repo = _FakeRepo();

    await resetTrilhaProgress('u1', repository: repo);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('trilha_addressed_u1'), isNull);
    expect(prefs.getString('trilha_drafts_u1'), isNull);
    expect(prefs.getString('trilha_draft_exp.0.company'), isNull);
    // Isolamento: não toca outro usuário nem chaves não relacionadas.
    expect(prefs.getStringList('trilha_addressed_u2'), ['skills']);
    expect(prefs.getString('unrelated_key'), 'x');
    // Servidor chamado.
    expect(repo.cleared, ['u1']);
  });

  test('failure-safe: servidor offline não derruba o reset local', () async {
    SharedPreferences.setMockInitialValues({
      'trilha_addressed_u1': ['skills'],
    });
    final repo = _FakeRepo()..fail = true;

    await resetTrilhaProgress('u1', repository: repo); // não lança

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('trilha_addressed_u1'), isNull);
  });
}
