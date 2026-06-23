import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_gamification/features/profile/domain/repositories/profile_repository.dart';
import 'package:career_gamification/features/trilha/application/trilha_progress.dart';

/// Repo falso: só os 2 métodos de progresso; o resto lança via noSuchMethod.
class _FakeRepo implements ProfileRepository {
  final Set<String> server = {};
  bool fail = false;
  int markCalls = 0;

  @override
  Future<Set<String>> getGuidedProgress(String userId) async {
    if (fail) throw Exception('network');
    return {...server};
  }

  @override
  Future<void> markGuidedProgress(String userId, String segment) async {
    markCalls++;
    if (fail) throw Exception('network');
    server.add(segment);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} não deveria ser chamado');
}

/// Cobre a memória da trilha — o que impede re-perguntar skills/experiência.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('marca e lê trechos abordados, isolado por usuário', () async {
    final p = TrilhaProgress();
    expect(await p.addressed('u1'), isEmpty);

    await p.mark('u1', 'skills');
    await p.markFromStep('u1', 'exp.gate'); // → 'experience'

    expect(await p.addressed('u1'), containsAll(['skills', 'experience']));
    expect(await p.addressed('u2'), isEmpty); // outro usuário não é afetado
  });

  test('markFromStep ignora passos de controle (intro / internos)', () async {
    final p = TrilhaProgress();
    await p.markFromStep('u1', 'intro');
    await p.markFromStep('u1', 'exp.0.company');
    expect(await p.addressed('u1'), isEmpty);
  });

  test('segmentForStep mapeia só os passos-raiz (incluindo extras)', () {
    expect(TrilhaProgress.segmentForStep('gap.skills'), 'skills');
    expect(TrilhaProgress.segmentForStep('gap.area'), 'area');
    expect(TrilhaProgress.segmentForStep('gap.availability'), 'availability');
    expect(TrilhaProgress.segmentForStep('exp.gate'), 'experience');
    expect(TrilhaProgress.segmentForStep('linkedin.gate'), 'linkedin');
    expect(TrilhaProgress.segmentForStep('cert.gate'), 'certifications');
    expect(TrilhaProgress.segmentForStep('project.gate'), 'projects');
    expect(TrilhaProgress.segmentForStep('exp.0.ofazia'), isNull);
    expect(TrilhaProgress.segmentForStep('cert.0.name'), isNull);
    expect(TrilhaProgress.segmentForStep('intro'), isNull);
  });

  group('híbrido (retomada entre devices)', () {
    test('addressed une servidor + local e semeia o cache local', () async {
      SharedPreferences.setMockInitialValues({
        'trilha_addressed_u1': ['skills'],
      });
      final repo = _FakeRepo()..server.addAll({'area', 'experience'});
      final p = TrilhaProgress(repository: repo);

      final got = await p.addressed('u1');
      expect(got, containsAll(['skills', 'area', 'experience']));

      // O cache local foi semeado com o do servidor → um leitor local-only
      // (outro "device" no mesmo prefs) agora enxerga tudo.
      expect(await TrilhaProgress().addressed('u1'),
          containsAll(['skills', 'area', 'experience']));
    });

    test('mark grava no local E no servidor', () async {
      final repo = _FakeRepo();
      final p = TrilhaProgress(repository: repo);
      await p.mark('u1', 'skills');
      expect(repo.server, contains('skills'));
      expect(await TrilhaProgress().addressed('u1'), contains('skills'));
    });

    test('falha do servidor no addressed cai no cache local (não lança)',
        () async {
      SharedPreferences.setMockInitialValues({
        'trilha_addressed_u1': ['skills'],
      });
      final repo = _FakeRepo()..fail = true;
      final p = TrilhaProgress(repository: repo);
      expect(await p.addressed('u1'), ['skills']);
    });

    test('falha do servidor no mark ainda grava local (não lança)', () async {
      final repo = _FakeRepo()..fail = true;
      final p = TrilhaProgress(repository: repo);
      await p.mark('u1', 'skills');
      expect(await TrilhaProgress().addressed('u1'), contains('skills'));
      expect(repo.markCalls, 1); // tentou o servidor
    });
  });
}
