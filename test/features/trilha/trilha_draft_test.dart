import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_gamification/features/trilha/application/trilha_draft.dart';

/// Persistência local do rascunho de item (resumabilidade por passo).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save/load round-trip + upsert por kind (substitui o do mesmo tipo)',
      () async {
    final store = TrilhaDraftStore();
    await store.save(
        'u1',
        const TrilhaItemDraft(
            kind: 'experience',
            itemIndex: 0,
            lastStepId: 'exp.0.start',
            fields: {'company': 'Magalu'}));
    var got = await store.load('u1');
    expect(got, hasLength(1));
    expect(got.first.fields['company'], 'Magalu');

    await store.save(
        'u1',
        const TrilhaItemDraft(
            kind: 'experience',
            itemIndex: 0,
            lastStepId: 'exp.0.role',
            fields: {'company': 'Magalu', 'role': 'Estágio'}));
    got = await store.load('u1');
    expect(got, hasLength(1)); // não duplica o kind
    expect(got.first.lastStepId, 'exp.0.role');
  });

  test('drafts de kinds diferentes coexistem; delete só remove o seu', () async {
    final store = TrilhaDraftStore();
    await store.save(
        'u1',
        const TrilhaItemDraft(
            kind: 'project', itemIndex: 0, lastStepId: 'project.0.did', fields: {}));
    await store.save(
        'u1',
        const TrilhaItemDraft(
            kind: 'education',
            itemIndex: 0,
            lastStepId: 'gap.edu.institution',
            fields: {'moment': 'in_college'}));
    expect(await store.load('u1'), hasLength(2));
    await store.delete('u1', 'project');
    final got = await store.load('u1');
    expect(got.map((d) => d.kind), ['education']);
  });

  test('isolado por usuário', () async {
    final store = TrilhaDraftStore();
    await store.save(
        'u1',
        const TrilhaItemDraft(
            kind: 'experience', itemIndex: 0, lastStepId: 'exp.0.start', fields: {}));
    expect(await store.load('u2'), isEmpty);
  });
}
