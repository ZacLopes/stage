// Gate 3.0F — contrato tipado dos writers de idioma do Assistente:
//   add   → merge_guided_profile_list('languages')  (aditivo, insere só novos)
//   level → set_guided_language_level_cas            (CAS do nível; manual vence)
//   remove→ remove_guided_language_cas               (CAS do nível; devolve nível
//            removido p/ undo)
//
// Fail-closed: resposta ausente, malformada ou incoerente NUNCA vira sucesso.

const Set<String> kLanguageLevels = {
  'native',
  'fluent',
  'advanced',
  'intermediate',
  'basic',
};

class GuidedLanguageWriteException implements Exception {
  const GuidedLanguageWriteException(this.code);

  final String code;

  @override
  String toString() => 'GuidedLanguageWriteException($code)';
}

// ── add (merge aditivo) ─────────────────────────────────────────────────────

enum GuidedLanguageMergeOutcome { applied, noop }

class GuidedLanguageMergeReceipt {
  const GuidedLanguageMergeReceipt._({
    required this.outcome,
    required this.inserted,
  });

  final GuidedLanguageMergeOutcome outcome;
  final int inserted;

  bool get changed => outcome == GuidedLanguageMergeOutcome.applied;

  factory GuidedLanguageMergeReceipt.fromRpc(Object? raw) {
    if (raw is! Map) {
      throw const GuidedLanguageWriteException('merge_not_object');
    }
    final status = raw['status'];
    if (status != 'applied' && status != 'noop') {
      throw const GuidedLanguageWriteException('invalid_merge_status');
    }
    final inserted = raw['inserted'];
    final updated = raw['updated'];
    final changed = raw['changed'];
    if (inserted is! int ||
        inserted < 0 ||
        updated is! int ||
        updated < 0 ||
        changed is! int ||
        changed < 0) {
      throw const GuidedLanguageWriteException('invalid_merge_counts');
    }
    // Idiomas, como skills, só inserem no merge — nunca atualizam linha.
    if (updated != 0) {
      throw const GuidedLanguageWriteException('unexpected_language_update');
    }
    if (changed != inserted + updated) {
      throw const GuidedLanguageWriteException('inconsistent_merge_counts');
    }
    final applied = status == 'applied';
    if (applied != (changed > 0)) {
      throw const GuidedLanguageWriteException('merge_status_count_mismatch');
    }
    return GuidedLanguageMergeReceipt._(
      outcome: applied
          ? GuidedLanguageMergeOutcome.applied
          : GuidedLanguageMergeOutcome.noop,
      inserted: inserted,
    );
  }
}

// ── level (CAS) ─────────────────────────────────────────────────────────────

enum GuidedLanguageLevelOutcome { applied, noop, stale, notFound }

class GuidedLanguageLevelReceipt {
  const GuidedLanguageLevelReceipt._({required this.outcome, this.liveLevel});

  final GuidedLanguageLevelOutcome outcome;

  /// Nível vivo no servidor quando o resultado foi `stale` (pode ser null).
  final String? liveLevel;

  factory GuidedLanguageLevelReceipt.fromRpc(Object? raw) {
    if (raw is! Map) {
      throw const GuidedLanguageWriteException('level_not_object');
    }
    final outcome = switch (raw['status']) {
      'applied' => GuidedLanguageLevelOutcome.applied,
      'noop' => GuidedLanguageLevelOutcome.noop,
      'stale' => GuidedLanguageLevelOutcome.stale,
      'not_found' => GuidedLanguageLevelOutcome.notFound,
      _ => throw const GuidedLanguageWriteException('invalid_level_status'),
    };
    final live = _parseOptionalLevel(raw['live_level']);
    if (outcome != GuidedLanguageLevelOutcome.stale && raw['live_level'] != null) {
      throw const GuidedLanguageWriteException('unexpected_live_level');
    }
    return GuidedLanguageLevelReceipt._(outcome: outcome, liveLevel: live);
  }
}

// ── remove (CAS; devolve nível removido) ────────────────────────────────────

enum GuidedLanguageRemoveOutcome { applied, stale, notFound }

class GuidedLanguageRemoveReceipt {
  const GuidedLanguageRemoveReceipt._({
    required this.outcome,
    this.removedLevel,
    this.liveLevel,
  });

  final GuidedLanguageRemoveOutcome outcome;

  /// Nível do idioma removido (pode ser null) — usado para restaurar no undo.
  final String? removedLevel;

  /// Nível vivo quando o resultado foi `stale`.
  final String? liveLevel;

  factory GuidedLanguageRemoveReceipt.fromRpc(Object? raw) {
    if (raw is! Map) {
      throw const GuidedLanguageWriteException('remove_not_object');
    }
    switch (raw['status']) {
      case 'applied':
        if (raw['live_level'] != null) {
          throw const GuidedLanguageWriteException('unexpected_live_level');
        }
        return GuidedLanguageRemoveReceipt._(
          outcome: GuidedLanguageRemoveOutcome.applied,
          removedLevel: _parseOptionalLevel(raw['level']),
        );
      case 'stale':
        if (raw['level'] != null) {
          throw const GuidedLanguageWriteException('unexpected_removed_level');
        }
        return GuidedLanguageRemoveReceipt._(
          outcome: GuidedLanguageRemoveOutcome.stale,
          liveLevel: _parseOptionalLevel(raw['live_level']),
        );
      case 'not_found':
        return const GuidedLanguageRemoveReceipt._(
          outcome: GuidedLanguageRemoveOutcome.notFound,
        );
      default:
        throw const GuidedLanguageWriteException('invalid_remove_status');
    }
  }
}

String? _parseOptionalLevel(Object? raw) {
  if (raw == null) return null;
  if (raw is! String || !kLanguageLevels.contains(raw)) {
    throw const GuidedLanguageWriteException('invalid_level_value');
  }
  return raw;
}

/// Writers de idioma da coleta guiada/Assistente, pelo contrato server-side.
abstract interface class GuidedLanguageWriter {
  /// Garante que [names] estejam presentes (merge aditivo, nível null).
  Future<GuidedLanguageMergeReceipt> mergeLanguages({
    required String userId,
    required List<String> names,
  });

  /// CAS do nível: só aplica se o vivo == [expectedLevel] observado.
  Future<GuidedLanguageLevelReceipt> setLevel({
    required String userId,
    required String name,
    required String? expectedLevel,
    required String newLevel,
  });

  /// Remove [name] só se o nível vivo == [expectedLevel] observado; devolve o
  /// nível removido no recibo para o undo.
  Future<GuidedLanguageRemoveReceipt> removeLanguage({
    required String userId,
    required String name,
    required String? expectedLevel,
  });
}
