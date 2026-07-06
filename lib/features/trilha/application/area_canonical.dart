// Canonicalização de área — Fase 7 · gate-list +10 (Tarefa 2).
//
// O usuário pode adicionar QUALQUER área na trilha (texto livre / catálogo
// estendido). Mas as vagas, o match, o feed e a busca do admin só entendem as
// áreas CANÔNICAS. Pra o candidato não ficar invisível, cada área custom é
// mapeada "por trás" pra uma canônica (guardada como linha source='inferred',
// que o usuário não vê mas os readers consomem). A área que o usuário digitou
// é preservada como a escolha dele.
//
// [withInferredAreas] é o ponto único usado por cada save de áreas (trilha e
// editor do perfil), pra a canônica oculta ser sempre re-derivada e nunca
// perdida numa edição.
//
// A lista canônica espelha kJobAreas (lib/core/constants/job_areas.dart) —
// mantê-las em sincronia. 'Geral' é o catch-all (mesma semântica do fallback
// do inferArea das vagas): área desconhecida cai aqui, não some do funil.

import '../../profile/domain/entities/entities.dart';

const List<String> kCanonicalAreas = <String>[
  'Tecnologia',
  'Engenharia',
  'Design',
  'Produto',
  'Marketing',
  'Vendas',
  'Finanças',
  'Recursos Humanos',
  'Operações',
  'Jurídico',
  'Administrativo',
  'Saúde',
  'Geral',
];

// Áreas custom (catálogo estendido + comuns) → canônica. Chaves normalizadas
// (minúsculas, sem acento). Ajustável — são decisões de produto, não regra fixa.
const Map<String, String> _kAreaAliases = <String, String>{
  'comunicacao': 'Marketing',
  'logistica': 'Operações',
  'dados': 'Tecnologia',
  'data': 'Tecnologia',
  'ti': 'Tecnologia',
  'audiovisual': 'Design',
  'moda': 'Design',
  'eventos': 'Marketing',
  'consultoria': 'Administrativo',
  'publica': 'Administrativo',
  'construcao civil': 'Engenharia',
  'rh': 'Recursos Humanos',
  // Sem correspondência clara entre as 13 → catch-all 'Geral' (não some).
  'educacao': 'Geral',
  'agronegocio': 'Geral',
  'sustentabilidade': 'Geral',
  'meio ambiente': 'Geral',
  'pesquisa': 'Geral',
  'gastronomia': 'Geral',
  'turismo': 'Geral',
};

String _stripAccents(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf.toString();
}

String _norm(String s) => _stripAccents(s.toLowerCase().trim());

/// Mapeia QUALQUER área (custom/livre) pra uma das [kCanonicalAreas], pro
/// match/busca. Identidade se já for canônica. Ordem: canônica exata → alias →
/// contém nome de canônica ("Marketing Digital" → Marketing) → 'Geral'.
String canonicalArea(String input) {
  final n = _norm(input);
  if (n.isEmpty) return 'Geral';
  for (final c in kCanonicalAreas) {
    if (_norm(c) == n) return c;
  }
  final alias = _kAreaAliases[n];
  if (alias != null) return alias;
  for (final c in kCanonicalAreas) {
    if (c == 'Geral') continue;
    if (n.contains(_norm(c))) return c;
  }
  return 'Geral';
}

/// True quando [input] já é uma das canônicas (não precisa de linha inferida).
bool isCanonicalArea(String input) {
  final n = _norm(input);
  return kCanonicalAreas.any((c) => _norm(c) == n);
}

/// Ponto ÚNICO de derivação: recebe as áreas VISÍVEIS do usuário (o conjunto a
/// persistir) e devolve elas + a canônica oculta ('inferred') de cada área
/// custom. Idempotente e dedup por título. Precedência: uma área explícita do
/// usuário nunca é rebaixada a 'inferred'. Usado pela trilha E pelo editor do
/// perfil, pra a canônica nunca sumir numa edição.
List<DesiredTitle> withInferredAreas(
  String userId,
  List<DesiredTitle> userAreas,
) {
  final byKey = <String, DesiredTitle>{};
  void put(String rawTitle, DesiredTitleSource source) {
    final t = rawTitle.trim();
    if (t.isEmpty) return;
    final key = t.toLowerCase();
    final prev = byKey[key];
    if (prev == null) {
      byKey[key] = DesiredTitle(
        id: '',
        userId: userId,
        title: t,
        source: source,
        orderIndex: byKey.length,
      );
    } else if (prev.source == DesiredTitleSource.inferred &&
        source != DesiredTitleSource.inferred) {
      byKey[key] = prev.copyWith(source: source, title: t);
    }
  }

  // 1. Áreas do usuário (visíveis) primeiro — preservadas como vieram.
  for (final t in userAreas) {
    put(t.title, t.source ?? DesiredTitleSource.userAdded);
  }
  // 2. Canônica oculta pra cada área custom.
  for (final t in userAreas) {
    if (!isCanonicalArea(t.title)) {
      put(canonicalArea(t.title), DesiredTitleSource.inferred);
    }
  }
  return byKey.values.toList();
}
