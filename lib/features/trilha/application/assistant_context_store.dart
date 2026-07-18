import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Um turno textual concluído do Assistente.
///
/// O contrato é propositalmente estreito: não existe campo para tool, args,
/// cards, callbacks ou snapshots. Assim esses dados não podem entrar no cache
/// local por acidente.
@immutable
class AssistantContextTurn {
  const AssistantContextTurn({
    required this.userText,
    required this.assistantText,
  });

  final String userText;
  final String assistantText;
}

@immutable
class AssistantContextSnapshot {
  AssistantContextSnapshot(Iterable<AssistantContextTurn> turns)
    : turns = List.unmodifiable(turns);

  const AssistantContextSnapshot.empty() : turns = const [];

  final List<AssistantContextTurn> turns;

  bool get isEmpty => turns.isEmpty;
}

/// Seam injetável usado pelo controller. Implementações devem manter os dados
/// isolados pelo [userId].
abstract interface class AssistantContextStore {
  Future<AssistantContextSnapshot> load(String userId);

  Future<void> save(String userId, List<AssistantContextTurn> turns);

  Future<void> clear(String userId);
}

typedef AssistantPreferencesLoader = Future<SharedPreferences> Function();

/// Cache local curto e versionado das últimas falas livres do Assistente.
///
/// Limites de privacidade/integridade:
/// - no máximo 3 turnos concluídos;
/// - no máximo 800 caracteres por fala;
/// - envelope UTF-8 de no máximo 8 KiB;
/// - expiração em 7 dias;
/// - normalização e redação best-effort antes de gravar e ao ler.
class SharedPreferencesAssistantContextStore implements AssistantContextStore {
  SharedPreferencesAssistantContextStore({
    AssistantPreferencesLoader? preferencesLoader,
    DateTime Function()? now,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;

  static const int schemaVersion = 1;
  static const int maxTurns = 3;
  static const int maxTextCharacters = 800;
  static const int maxEnvelopeBytes = 8 * 1024;
  static const Duration ttl = Duration(days: 7);

  static const String _keyPrefix = 'trilha_assistant_context_v1.';

  final AssistantPreferencesLoader _preferencesLoader;
  final DateTime Function() _now;

  @visibleForTesting
  static String storageKeyForUser(String userId) {
    final encoded = base64Url
        .encode(utf8.encode(userId.trim()))
        .replaceAll('=', '');
    return '$_keyPrefix$encoded';
  }

  static String sanitizeText(String value) {
    var text = value
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), ' ')
        .replaceAll(
          RegExp(r'(?:https?://|www\.)[^\s]+', caseSensitive: false),
          '[link]',
        )
        .replaceAll(
          RegExp(
            r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
            caseSensitive: false,
          ),
          '[e-mail]',
        )
        .replaceAll(RegExp(r'\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b'), '[CPF]')
        .replaceAll(
          RegExp(
            r'(?:\+?55[\s().-]*)?(?:\(?\d{2}\)?[\s.-]*)9?\d{4}[\s.-]?\d{4}',
          ),
          '[telefone]',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final runes = text.runes.toList(growable: false);
    if (runes.length > maxTextCharacters) {
      text = String.fromCharCodes(runes.take(maxTextCharacters));
    }
    return text;
  }

  @visibleForTesting
  static String? encodeForStorage(
    List<AssistantContextTurn> turns, {
    required DateTime updatedAt,
  }) {
    var bounded = _boundedTurns(turns);
    if (bounded.isEmpty) return null;

    // Três falas cheias em Unicode podem ultrapassar 8 KiB. Mantemos sempre
    // os turnos mais recentes e removemos o mais antigo até o envelope caber.
    while (bounded.isNotEmpty) {
      final encoded = jsonEncode({
        'version': schemaVersion,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'turns': [
          for (final turn in bounded)
            {'user': turn.userText, 'assistant': turn.assistantText},
        ],
      });
      if (utf8.encode(encoded).length <= maxEnvelopeBytes) return encoded;
      bounded = bounded.sublist(1);
    }
    return null;
  }

  static List<AssistantContextTurn> _boundedTurns(
    Iterable<AssistantContextTurn> turns,
  ) {
    final sanitized = <AssistantContextTurn>[];
    for (final turn in turns) {
      final user = sanitizeText(turn.userText);
      final assistant = sanitizeText(turn.assistantText);
      if (user.isEmpty || assistant.isEmpty) continue;
      sanitized.add(
        AssistantContextTurn(userText: user, assistantText: assistant),
      );
    }
    return sanitized.length <= maxTurns
        ? sanitized
        : sanitized.sublist(sanitized.length - maxTurns);
  }

  @override
  Future<AssistantContextSnapshot> load(String userId) async {
    if (userId.trim().isEmpty) return const AssistantContextSnapshot.empty();
    final key = storageKeyForUser(userId);
    SharedPreferences? preferences;
    try {
      preferences = await _preferencesLoader();
      final raw = preferences.getString(key);
      if (raw == null) return const AssistantContextSnapshot.empty();
      if (utf8.encode(raw).length > maxEnvelopeBytes) {
        await preferences.remove(key);
        return const AssistantContextSnapshot.empty();
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          !_hasOnlyKeys(decoded, const {'version', 'updated_at', 'turns'}) ||
          decoded['version'] != schemaVersion ||
          decoded['updated_at'] is! String ||
          decoded['turns'] is! List) {
        await preferences.remove(key);
        return const AssistantContextSnapshot.empty();
      }

      final updatedAt = DateTime.tryParse(decoded['updated_at'] as String);
      final now = _now().toUtc();
      if (updatedAt == null ||
          updatedAt.toUtc().isAfter(now.add(const Duration(minutes: 5))) ||
          now.difference(updatedAt.toUtc()) > ttl) {
        await preferences.remove(key);
        return const AssistantContextSnapshot.empty();
      }

      final turns = <AssistantContextTurn>[];
      for (final rawTurn in decoded['turns'] as List) {
        if (rawTurn is! Map<String, dynamic> ||
            !_hasOnlyKeys(rawTurn, const {'user', 'assistant'}) ||
            rawTurn['user'] is! String ||
            rawTurn['assistant'] is! String) {
          await preferences.remove(key);
          return const AssistantContextSnapshot.empty();
        }
        turns.add(
          AssistantContextTurn(
            userText: rawTurn['user'] as String,
            assistantText: rawTurn['assistant'] as String,
          ),
        );
      }

      final bounded = _boundedTurns(turns);
      if (bounded.isEmpty) {
        await preferences.remove(key);
        return const AssistantContextSnapshot.empty();
      }
      return AssistantContextSnapshot(bounded);
    } catch (_) {
      // O cache nunca pode impedir a abertura do Assistente.
      try {
        await preferences?.remove(key);
      } catch (_) {
        // Falha de limpeza também é failure-safe.
      }
      return const AssistantContextSnapshot.empty();
    }
  }

  @override
  Future<void> save(String userId, List<AssistantContextTurn> turns) async {
    if (userId.trim().isEmpty) return;
    final preferences = await _preferencesLoader();
    final key = storageKeyForUser(userId);
    final encoded = encodeForStorage(turns, updatedAt: _now());
    if (encoded == null) {
      await preferences.remove(key);
      return;
    }
    final saved = await preferences.setString(key, encoded);
    if (!saved) throw StateError('assistant context was not saved');
  }

  @override
  Future<void> clear(String userId) async {
    if (userId.trim().isEmpty) return;
    final preferences = await _preferencesLoader();
    await preferences.remove(storageKeyForUser(userId));
  }

  static bool _hasOnlyKeys(Map<String, dynamic> map, Set<String> allowed) =>
      map.keys.every(allowed.contains) && map.length == allowed.length;
}
