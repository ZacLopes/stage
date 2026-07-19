// Gate 3.0I — mapeia UMA linha de conflito revisada (aceita) para o objeto
// `{kind, …}` do RPC `apply_reviewed_conflicts_and_promote`.
//
// FUNÇÃO PURA (sem I/O, sem fiação): converte `ConflictRow` + valor efetivo no
// formato EXATO por kind. Fail-closed: retorna null quando a linha não pode ser
// mapeada com segurança (falta chave de vínculo) — nunca inventa um choice.
// Verificado contra o RPC REAL: as formas batem 1:1 com as validadas no
// promote test (inclui `lang_level` aplicado/stale).

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
      // Conflito de NÍVEL: `lang_level`. `name` = idioma (chave de vínculo com o
      // perfil vivo e o payload) → o nome ORIGINAL (`row.value`), nunca editado.
      // `expected` = id do nível OBSERVADO (token do CAS); o nível NOVO vem do
      // payload vinculado, não do cliente. Fail-closed se faltar a chave.
      if (row.value.isEmpty) return null;
      return {
        'kind': 'lang_level',
        'name': row.value,
        'expected': row.observedLevelId,
      };

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
