import 'package:career_gamification/services/feature_flags_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final flags = FeatureFlagsService.instance;

  setUp(flags.resetForTesting);
  tearDown(flags.resetForTesting);

  void setParent(bool enabled) {
    flags.setFlagForTesting(
      FeatureFlagKeys.trilhaColetaV1,
      enabled: enabled,
      rolloutPct: enabled ? 100 : 0,
    );
  }

  void setChild(bool enabled) {
    flags.setFlagForTesting(
      FeatureFlagKeys.trilhaAssistV1,
      enabled: enabled,
      rolloutPct: enabled ? 100 : 0,
    );
  }

  test('fica OFF por default quando as flags não foram carregadas', () {
    expect(flags.isTrilhaAssistEnabledForUser('user-1'), isFalse);
  });

  test('flag filha ON não contorna o gate pai OFF', () {
    setParent(false);
    setChild(true);

    expect(flags.isTrilhaAssistEnabledForUser('user-1'), isFalse);
  });

  test('gate pai ON não contorna a flag filha OFF', () {
    setParent(true);
    setChild(false);

    expect(flags.isTrilhaAssistEnabledForUser('user-1'), isFalse);
  });

  test('liga apenas quando pai e filha estão ON para o usuário', () {
    setParent(true);
    setChild(true);

    expect(flags.isTrilhaAssistEnabledForUser('user-1'), isTrue);
  });

  test('sem user id permanece OFF mesmo em rollout de 100%', () {
    setParent(true);
    setChild(true);

    expect(flags.isTrilhaAssistEnabledForUser(null), isFalse);
    expect(flags.isTrilhaAssistEnabledForUser(''), isFalse);
  });
}
