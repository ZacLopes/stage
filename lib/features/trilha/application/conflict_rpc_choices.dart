// Gate 3.0I — mapeia UMA linha de conflito revisada (aceita) para o objeto
// `{kind, …}` do RPC `apply_reviewed_conflicts_and_promote`.
//
// FUNÇÃO PURA (sem I/O, sem fiação): converte `ConflictRow` + valor efetivo no
// formato EXATO por kind. Fail-closed: retorna null quando a linha não pode ser
// mapeada com segurança (ex.: conflito de nível de idioma — ver LACUNA) — nunca
// inventa um choice. A verificação contra o RPC REAL (harness SQL) é o passo
// seguinte, antes de qualquer fiação.

import 'cv_conflict.dart';

/// Converte uma linha aceita no choice do RPC, ou null se não mapeável.
/// [effectiveValue] = valor a aplicar (editado pelo usuário ou o original).
Map<String, dynamic>? conflictRowToRpcChoice(
  ConflictRow row,
  String effectiveValue,
) {
  final value = effectiveValue;
  switch (row.section) {
    // Escalares/compostos — o RPC parte name/city/phone internamente
    // (_cas_write_personal_field). `expected` = valor observado (CAS).
    case ConflictSection.name:
    case ConflictSection.phone:
    case ConflictSection.city:
    case ConflictSection.summary:
    case ConflictSection.linkedin:
    case ConflictSection.website:
      return {
        'kind': 'personal',
        'field': row.field,
        'expected': row.currentText,
        'value': value,
      };

    // Adições de lista: o RPC LOCALIZA o item no payload por `source` (valor
    // ORIGINAL proposto) e preserva campos canônicos (award.date, projeto etc.).
    case ConflictSection.skill:
    case ConflictSection.interest:
    case ConflictSection.coursework:
    case ConflictSection.award:
    case ConflictSection.project:
      return {
        'kind': 'add',
        'section': row.section.name,
        'value': value,
        'source': row.value,
      };

    case ConflictSection.certification:
      return {
        'kind': 'add_cert',
        'name': value,
        if (row.extra.isNotEmpty) 'issuer': row.extra,
        'source': row.value,
      };

    case ConflictSection.language:
      if (row.kind == ConflictKind.addition) {
        // Nível vem do payload VINCULADO (não do cliente).
        return {'kind': 'add_lang', 'name': value, 'source': row.value};
      }
      // LACUNA (decisão pendente): o conflito de NÍVEL vira `lang_level` e o RPC
      // exige `expected` = ID do nível observado; a linha só tem o RÓTULO
      // (currentText) — não dá pra mapear com segurança ainda. Fail-closed.
      return null;

    case ConflictSection.experience:
      if (row.kind == ConflictKind.conflict) {
        return {
          'kind': 'item_field',
          'section': 'experience',
          'field': row.field,
          'expected': row.currentText,
          'value': value,
          'ref_id': row.refId,
        };
      }
      return {
        'kind': 'add_experience',
        'company': (row.cvItem['company'] ?? '').toString(),
        'title': (row.cvItem['title'] ?? '').toString(),
      };

    case ConflictSection.education:
      if (row.kind == ConflictKind.conflict) {
        return {
          'kind': 'item_field',
          'section': 'education',
          'field': row.field,
          'expected': row.currentText,
          'value': value,
          'ref_id': row.refId,
        };
      }
      return {
        'kind': 'add_education',
        'institution': (row.cvItem['institution'] ?? '').toString(),
        'degree': (row.cvItem['degree'] ?? '').toString(),
      };
  }
}
