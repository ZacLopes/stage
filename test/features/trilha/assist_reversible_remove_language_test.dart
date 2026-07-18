import 'package:career_gamification/features/profile/domain/entities/entities.dart';
import 'package:career_gamification/features/profile/domain/repositories/profile_repository.dart';
import 'package:career_gamification/features/trilha/application/trilha_session.dart';
import 'package:career_gamification/features/trilha/domain/guided_language_write.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLangRepo implements ProfileRepository {
  _FakeLangRepo(this.languages);
  final List<Language> languages;

  @override
  Future<List<Language>> getLanguages(String userId) async => languages;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('repo tocado: ${invocation.memberName}');
}

class _SpyLangWriter implements GuidedLanguageWriter {
  _SpyLangWriter({this.removeOutcome = 'applied', this.removedLevel});
  final String removeOutcome; // 'applied' | 'stale' | 'not_found'
  final String? removedLevel;
  final List<List<String>> merged = [];
  final List<(String, String?, String)> levels = [];
  final List<(String, String?)> removes = [];

  @override
  Future<GuidedLanguageMergeReceipt> mergeLanguages({
    required String userId,
    required List<String> names,
  }) async {
    merged.add(List<String>.from(names));
    return GuidedLanguageMergeReceipt.fromRpc(<String, dynamic>{
      'status': 'applied',
      'inserted': names.length,
      'updated': 0,
      'changed': names.length,
    });
  }

  @override
  Future<GuidedLanguageLevelReceipt> setLevel({
    required String userId,
    required String name,
    required String? expectedLevel,
    required String newLevel,
  }) async {
    levels.add((name, expectedLevel, newLevel));
    return GuidedLanguageLevelReceipt.fromRpc(
      const <String, dynamic>{'status': 'applied'},
    );
  }

  @override
  Future<GuidedLanguageRemoveReceipt> removeLanguage({
    required String userId,
    required String name,
    required String? expectedLevel,
  }) async {
    removes.add((name, expectedLevel));
    return GuidedLanguageRemoveReceipt.fromRpc(switch (removeOutcome) {
      'stale' => <String, dynamic>{'status': 'stale', 'live_level': 'fluent'},
      'not_found' => const <String, dynamic>{'status': 'not_found'},
      _ => <String, dynamic>{'status': 'applied', 'level': removedLevel},
    });
  }
}

void main() {
  group('assistReversibleRemove(language) — Gate 3.0F CAS/undo', () {
    test('applied → remove com expected=nível observado; undo re-add+restaura',
        () async {
      final repo = _FakeLangRepo([
        const Language(
          id: '1',
          userId: 'u1',
          name: 'Inglês',
          proficiency: LanguageProficiency.advanced,
        ),
      ]);
      final w = _SpyLangWriter(removedLevel: 'advanced');

      final restore = await assistReversibleRemove(
        'u1',
        'language',
        'inglês', // casa case-insensitive; usa o nome armazenado
        repository: repo,
        languageWriter: w,
      );
      expect(restore, isNotNull);
      expect(w.removes, [('Inglês', 'advanced')]); // CAS vs nível observado

      await restore!();
      expect(w.merged, [
        ['Inglês']
      ]); // undo re-adiciona
      expect(w.levels, [('Inglês', null, 'advanced')]); // e restaura o nível
    });

    test('applied sem nível → undo só re-add (sem setLevel)', () async {
      final repo = _FakeLangRepo([
        const Language(id: '1', userId: 'u1', name: 'Inglês'),
      ]);
      final w = _SpyLangWriter(removedLevel: null);

      final restore = await assistReversibleRemove(
        'u1',
        'language',
        'Inglês',
        repository: repo,
        languageWriter: w,
      );
      expect(restore, isNotNull);
      expect(w.removes, [('Inglês', null)]);

      await restore!();
      expect(w.merged, [
        ['Inglês']
      ]);
      expect(w.levels, isEmpty);
    });

    test('idioma ausente → null, sem removeLanguage', () async {
      final repo = _FakeLangRepo([
        const Language(id: '1', userId: 'u1', name: 'Francês'),
      ]);
      final w = _SpyLangWriter();
      final restore = await assistReversibleRemove(
        'u1',
        'language',
        'Inglês',
        repository: repo,
        languageWriter: w,
      );
      expect(restore, isNull);
      expect(w.removes, isEmpty);
    });

    test('remove stale → null (sem falso sucesso), sem undo', () async {
      final repo = _FakeLangRepo([
        const Language(id: '1', userId: 'u1', name: 'Inglês'),
      ]);
      final w = _SpyLangWriter(removeOutcome: 'stale');
      final restore = await assistReversibleRemove(
        'u1',
        'language',
        'Inglês',
        repository: repo,
        languageWriter: w,
      );
      expect(restore, isNull);
      expect(w.removes.length, 1);
      expect(w.merged, isEmpty);
    });

    test('remove not_found → null', () async {
      final repo = _FakeLangRepo([
        const Language(id: '1', userId: 'u1', name: 'Inglês'),
      ]);
      final w = _SpyLangWriter(removeOutcome: 'not_found');
      final restore = await assistReversibleRemove(
        'u1',
        'language',
        'Inglês',
        repository: repo,
        languageWriter: w,
      );
      expect(restore, isNull);
    });

    test('sem writer (flag OFF) → null (nunca remove por nome)', () async {
      final repo = _FakeLangRepo([
        const Language(id: '1', userId: 'u1', name: 'Inglês'),
      ]);
      final restore = await assistReversibleRemove(
        'u1',
        'language',
        'Inglês',
        repository: repo,
        languageWriter: null,
      );
      expect(restore, isNull);
    });
  });
}
