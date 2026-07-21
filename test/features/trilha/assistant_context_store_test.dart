import 'dart:convert';

import 'package:career_gamification/features/trilha/application/assistant_context_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 7, 17, 12);

  SharedPreferencesAssistantContextStore buildStore() =>
      SharedPreferencesAssistantContextStore(now: () => now);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'round-trip mantém apenas os 3 turnos concluídos mais recentes',
    () async {
      final store = buildStore();
      await store.save('user-a', [
        const AssistantContextTurn(userText: 'u1', assistantText: 'a1'),
        const AssistantContextTurn(userText: 'u2', assistantText: 'a2'),
        const AssistantContextTurn(userText: 'u3', assistantText: 'a3'),
        const AssistantContextTurn(userText: 'u4', assistantText: 'a4'),
      ]);

      final loaded = await store.load('user-a');

      expect(loaded.turns, hasLength(3));
      expect(loaded.turns.map((turn) => turn.userText), ['u2', 'u3', 'u4']);
      expect(loaded.turns.map((turn) => turn.assistantText), [
        'a2',
        'a3',
        'a4',
      ]);
    },
  );

  test('chave local isola usuários diferentes', () async {
    final store = buildStore();
    await store.save('user-a', const [
      AssistantContextTurn(userText: 'pergunta A', assistantText: 'resposta A'),
    ]);
    await store.save('user-b', const [
      AssistantContextTurn(userText: 'pergunta B', assistantText: 'resposta B'),
    ]);

    expect((await store.load('user-a')).turns.single.userText, 'pergunta A');
    expect((await store.load('user-b')).turns.single.userText, 'pergunta B');
    expect(
      SharedPreferencesAssistantContextStore.storageKeyForUser('user-a'),
      isNot(SharedPreferencesAssistantContextStore.storageKeyForUser('user-b')),
    );
  });

  test('TTL, versão desconhecida e JSON corrompido falham fechados', () async {
    final prefs = await SharedPreferences.getInstance();
    final key = SharedPreferencesAssistantContextStore.storageKeyForUser(
      'user-a',
    );
    final store = buildStore();

    await prefs.setString(key, '{corrompido');
    expect((await store.load('user-a')).isEmpty, isTrue);
    expect(prefs.containsKey(key), isFalse);

    await prefs.setString(
      key,
      jsonEncode({
        'version': 999,
        'updated_at': now.toIso8601String(),
        'turns': [
          {'user': 'u', 'assistant': 'a'},
        ],
      }),
    );
    expect((await store.load('user-a')).isEmpty, isTrue);
    expect(prefs.containsKey(key), isFalse);

    await prefs.setString(
      key,
      jsonEncode({
        'version': SharedPreferencesAssistantContextStore.schemaVersion,
        'updated_at': now.subtract(const Duration(days: 8)).toIso8601String(),
        'turns': [
          {'user': 'u', 'assistant': 'a'},
        ],
      }),
    );
    expect((await store.load('user-a')).isEmpty, isTrue);
    expect(prefs.containsKey(key), isFalse);
  });

  test('normaliza, redige PII e respeita limites de texto/envelope', () async {
    final store = buildStore();
    final long = List.filled(900, '🧠').join();
    final pii =
        '\u0000  Meu e-mail é pessoa@exemplo.com, CPF 123.456.789-09, '
        'telefone +55 (11) 98765-4321 e https://example.com/me  ';
    final sanitized = SharedPreferencesAssistantContextStore.sanitizeText(pii);
    expect(sanitized, contains('[e-mail]'));
    expect(sanitized, contains('[CPF]'));
    expect(sanitized, contains('[telefone]'));
    expect(sanitized, contains('[link]'));
    expect(sanitized, isNot(contains('\u0000')));
    await store.save('user-a', [
      AssistantContextTurn(userText: pii, assistantText: long),
      AssistantContextTurn(userText: long, assistantText: long),
      AssistantContextTurn(userText: long, assistantText: long),
    ]);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      SharedPreferencesAssistantContextStore.storageKeyForUser('user-a'),
    )!;
    final loaded = await store.load('user-a');

    expect(utf8.encode(raw).length, lessThanOrEqualTo(8 * 1024));
    for (final turn in loaded.turns) {
      expect(turn.userText.runes.length, lessThanOrEqualTo(800));
      expect(turn.assistantText.runes.length, lessThanOrEqualTo(800));
    }
    expect(raw, isNot(contains('pessoa@exemplo.com')));
    expect(raw, isNot(contains('123.456.789-09')));
    expect(raw, isNot(contains('98765-4321')));
    expect(raw, isNot(contains('https://example.com/me')));
  });

  test('JSON gravado aceita somente envelope e pares textuais', () async {
    final store = buildStore();
    await store.save('user-a', const [
      AssistantContextTurn(userText: 'Quero ajuda', assistantText: 'Vamos lá'),
    ]);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      SharedPreferencesAssistantContextStore.storageKeyForUser('user-a'),
    )!;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final turn = (decoded['turns'] as List).single as Map<String, dynamic>;

    expect(decoded.keys.toSet(), {'version', 'updated_at', 'turns'});
    expect(turn.keys.toSet(), {'user', 'assistant'});
    for (final prohibited in const [
      'card',
      'tool',
      'args',
      'grounding',
      'snapshot',
      'guided_answer',
      'filename',
      'conflict',
      'callback',
      'pending',
      'running',
      'undo',
    ]) {
      expect(raw, isNot(contains('"$prohibited"')));
    }
  });
}
