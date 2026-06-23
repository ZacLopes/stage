import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_gamification/features/trilha/application/trilha_progress.dart';

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

  test('segmentForStep mapeia só os passos-raiz', () {
    expect(TrilhaProgress.segmentForStep('gap.skills'), 'skills');
    expect(TrilhaProgress.segmentForStep('gap.area'), 'area');
    expect(TrilhaProgress.segmentForStep('exp.gate'), 'experience');
    expect(TrilhaProgress.segmentForStep('exp.0.ofazia'), isNull);
    expect(TrilhaProgress.segmentForStep('intro'), isNull);
  });
}
