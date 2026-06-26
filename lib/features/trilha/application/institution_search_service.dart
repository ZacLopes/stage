// Busca no catálogo `institutions` (95 IES, Fase 1 T1.6) por nome/normalized_name
// (PLANO-FASE-6 — canonização). Espelha a query que o InstitutionTypeaheadField
// já usa no onboarding/perfil, como função reutilizável pela trilha.
// Failure-safe: erro/sem catálogo ⇒ lista vazia (UI cai no texto livre).

import 'package:supabase_flutter/supabase_flutter.dart';

class InstitutionOption {
  final String id;
  final String name;
  const InstitutionOption({required this.id, required this.name});
}

Future<List<InstitutionOption>> searchInstitutions(String query) async {
  final q = query.trim();
  if (q.length < 2) return const [];
  try {
    final sanitized = q.replaceAll('%', '').replaceAll(',', ' ');
    final rows = await Supabase.instance.client
        .from('institutions')
        .select('id, name')
        .or('name.ilike.%$sanitized%,normalized_name.ilike.%$sanitized%')
        .limit(6);
    return (rows as List)
        .map((r) => InstitutionOption(
              id: r['id'] as String,
              name: r['name'] as String,
            ))
        .toList();
  } catch (_) {
    return const [];
  }
}
