import 'entities/entities.dart';
import 'profile_title.dart';
import 'skill_name_normalizer.dart';

class _AwardDraft {
  final String label;
  final String name;
  final int? year;

  const _AwardDraft({
    required this.label,
    required this.name,
    required this.year,
  });
}

_AwardDraft? _parseAwardLabel(String raw) {
  final label = cleanSkillName(raw);
  if (label.isEmpty) return null;

  final match = RegExp(r'^(.*?)\s*\((\d{4})\)\s*$').firstMatch(label);
  if (match == null) {
    final name = normalizeProfileTitle(label);
    return name.isEmpty
        ? null
        : _AwardDraft(label: label, name: name, year: null);
  }

  final name = normalizeProfileTitle(match.group(1) ?? '');
  final year = int.tryParse(match.group(2) ?? '');
  if (name.isEmpty || year == null || year < 1900 || year > 2200) {
    final fallback = normalizeProfileTitle(label);
    return fallback.isEmpty
        ? null
        : _AwardDraft(label: label, name: fallback, year: null);
  }
  return _AwardDraft(label: label, name: name, year: year);
}

/// Texto exibido pelo editor genérico. O ano fica separado do nome persistido.
String awardEditorLabel(Award award) => award.date == null
    ? award.name.trim()
    : '${award.name.trim()} (${award.date!.year})';

/// Converte os textos do editor de volta em entidades sem apagar UUID/data dos
/// itens que continuam na lista nem transformar "(2026)" em parte do nome.
///
/// Reconhece o label completo (inclusive após reordenação) para preservar a
/// identidade de itens inalterados. Um rótulo materialmente editado vira um
/// item novo: o editor genérico não informa se houve rename ou remove+add, e
/// adivinhar poderia transferir UUID/data de um prêmio para outro.
List<Award> reconcileAwardLabels({
  required String userId,
  required List<Award> current,
  required List<String> labels,
}) {
  final drafts = labels
      .map(_parseAwardLabel)
      .whereType<_AwardDraft>()
      .toList(growable: false);
  final matches = List<Award?>.filled(drafts.length, null);
  final usedIds = <String>{};

  for (var index = 0; index < drafts.length; index++) {
    final wanted = foldSkillName(drafts[index].label);
    for (final award in current) {
      if (usedIds.contains(award.id)) continue;
      if (foldSkillName(awardEditorLabel(award)) == wanted) {
        matches[index] = award;
        usedIds.add(award.id);
        break;
      }
    }
  }

  return [
    for (var index = 0; index < drafts.length; index++)
      _buildAward(
        userId: userId,
        draft: drafts[index],
        existing: matches[index],
        orderIndex: index,
      ),
  ];
}

Award _buildAward({
  required String userId,
  required _AwardDraft draft,
  required Award? existing,
  required int orderIndex,
}) {
  var date = existing?.date;
  if (draft.year != null && date?.year != draft.year) {
    date = DateTime(draft.year!, date?.month ?? 1, date?.day ?? 1);
  }
  date ??= draft.year == null ? null : DateTime(draft.year!);

  return Award(
    id: existing?.id ?? '',
    userId: userId,
    name: draft.name,
    date: date,
    orderIndex: orderIndex,
  );
}
