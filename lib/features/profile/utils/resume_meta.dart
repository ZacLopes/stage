// =============================================================================
// resume_meta.dart — funções PURAS da biblioteca de currículos.
//
// Tudo aqui é testável sem widget, sem rede e sem Supabase. O molde é
// `lib/features/jobs/utils/original_source.dart`, que já é 100% coberto por
// `test/features/jobs/original_source_test.dart`.
//
// A regra central é `resolveActiveResume`: qual currículo o app considera "em
// uso". Ela existe porque NUNCA pode existir o estado "nenhum em uso" — o
// usuário que nunca escolheu nada precisa ver um check azul no primeiro acesso,
// senão a tela pergunta uma coisa que ele não sabe responder.
//
// ⚠️ Quando a coluna `is_active_for_apply` existir (fatia 3), o backfill SQL
// tem que implementar EXATAMENTE esta mesma precedência. Se cliente e servidor
// discordarem, o herói pisca de um currículo pro outro no primeiro refresh.
// =============================================================================

import '../../../data/models/models.dart';

/// Precedência do "currículo em uso". Do mais explícito ao mais implícito:
///
/// 0. o que o usuário escolheu de propósito (fatia 3 — ainda não existe);
/// 1. a linha legada que preencheu o perfil (`is_latest_legacy_source`);
/// 2. o mais recente entre os elegíveis.
///
/// `adapted` nunca é elegível: currículo adaptado é POR VAGA, não é o
/// documento geral da pessoa. `general` não chega aqui (o filtro da biblioteca
/// já o remove), mas a guarda é defensiva.
SavedResume? resolveActiveResume(List<SavedResume> resumes) {
  final elegiveis = resumes.where(isEligibleAsActive).toList()
    ..sort(compareByRecency);

  if (elegiveis.isEmpty) return null;

  for (final r in elegiveis) {
    if (r.isLatestLegacySource) return r;
  }

  return elegiveis.first;
}

/// Um currículo pode virar "em uso"? Adaptados não — eles pertencem a uma vaga.
bool isEligibleAsActive(SavedResume r) =>
    r.source != SavedResumeSource.adapted &&
    r.source != SavedResumeSource.general;

/// Mais recente primeiro. Desempate por `id` pra ordem ser TOTAL — sem isso,
/// dois imports no mesmo segundo (existem: 38 de 60 pares estão a menos de 10
/// minutos um do outro) trocam de posição entre rebuilds.
int compareByRecency(SavedResume a, SavedResume b) {
  final byDate = b.createdAt.compareTo(a.createdAt);
  if (byDate != 0) return byDate;
  return b.id.compareTo(a.id);
}

/// Rótulo de origem, na voz do estudante — não na do banco.
///
/// O mapa `_kSourceMeta` de `profile_screen.dart` diz "Fonte importada", que é
/// vocabulário de sistema. Aqui a frase completa o metadado: "Importado · 14 de
/// agosto".
String describeSource(SavedResumeSource source) => switch (source) {
      SavedResumeSource.imported => 'Importado',
      SavedResumeSource.manual => 'Feito no Stage',
      SavedResumeSource.trail => 'Feito no Stage',
      SavedResumeSource.adapted => 'Adaptado',
      SavedResumeSource.general => 'Currículo geral',
    };

const List<String> _kMeses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

/// "14 de agosto" — e "14 de agosto de 2025" quando o ano não é [now].
///
/// Omitir o ano corrente é o que mantém a linha de metadado curta o bastante
/// pra caber nos 234pt de texto da linha da lista.
String formatShortDate(DateTime date, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final local = date.toLocal();
  final mes = _kMeses[local.month - 1];
  if (local.year == ref.year) return '${local.day} de $mes';
  return '${local.day} de $mes de ${local.year}';
}

/// "180 KB" / "1,2 MB". Vírgula decimal — o público é brasileiro.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.round()} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// "1 página" / "3 páginas".
String formatPages(int pages) => pages == 1 ? '1 página' : '$pages páginas';

/// Monta a linha de metadado juntando só o que já se sabe.
///
/// Chamada em todo rebuild enquanto os fatos assíncronos (páginas, tamanho)
/// chegam. A ordem é fixa e os campos ausentes somem sem deixar separador
/// órfão — por isso o join em vez de interpolação.
String buildMetaLine({
  required SavedResumeSource source,
  required DateTime createdAt,
  int? pages,
  int? bytes,
  DateTime? now,
}) {
  final partes = <String>[
    describeSource(source),
    formatShortDate(createdAt, now: now),
    if (pages != null) formatPages(pages),
    if (bytes != null) formatBytes(bytes),
  ];
  return partes.join(' · ');
}

/// Agrupa currículos que parecem ser o MESMO arquivo enviado duas vezes.
///
/// Por que isto existe: 68 dos 125 usuários com 2+ currículos (54%) têm pelo
/// menos um par de arquivos com tamanho em bytes idêntico — 82 arquivos
/// redundantes na base. Miniatura não resolve (são visualmente iguais) e nome
/// não resolve (687 linhas se chamam "Meu Currículo"). Só o metadado resolve.
///
/// Critério deliberadamente CONSERVADOR: mesmo tamanho em bytes E mesmo número
/// de páginas. Nunca afirma "é cópia" — a UI diz "parece cópia" e nunca apaga
/// sozinha. Um falso positivo aqui custa um aviso ignorável; um falso negativo
/// custa nada. Arquivos sem fatos carregados nunca entram.
Set<String> findLikelyDuplicates(
  List<SavedResume> resumes,
  Map<String, ResumeFileFacts> facts,
) {
  final porAssinatura = <String, List<SavedResume>>{};

  for (final r in resumes) {
    final f = facts[r.id];
    if (f == null || f.bytes == null || f.pages == null) continue;
    final chave = '${f.bytes}:${f.pages}';
    porAssinatura.putIfAbsent(chave, () => []).add(r);
  }

  final duplicados = <String>{};
  for (final grupo in porAssinatura.values) {
    if (grupo.length < 2) continue;
    for (final r in grupo) {
      duplicados.add(r.id);
    }
  }
  return duplicados;
}

/// Fatos que só se descobrem baixando o arquivo. Todos opcionais: a linha
/// renderiza completa sem nenhum deles e vai preenchendo conforme chegam.
class ResumeFileFacts {
  const ResumeFileFacts({
    this.bytes,
    this.pages,
    this.tooLargeToPreview = false,
    this.failed = false,
  });

  final int? bytes;
  final int? pages;

  /// Acima do teto de render. Continua elegível como currículo em uso — o
  /// problema é de renderização, não do arquivo.
  final bool tooLargeToPreview;

  /// O download ou o raster falhou. Erro é POR ITEM, nunca de tela: o metadado
  /// veio do banco e continua válido.
  final bool failed;

  ResumeFileFacts copyWith({
    int? bytes,
    int? pages,
    bool? tooLargeToPreview,
    bool? failed,
  }) =>
      ResumeFileFacts(
        bytes: bytes ?? this.bytes,
        pages: pages ?? this.pages,
        tooLargeToPreview: tooLargeToPreview ?? this.tooLargeToPreview,
        failed: failed ?? this.failed,
      );
}

/// Um título que não colide com nenhum outro da lista: "Meu Currículo (2)".
///
/// Necessário porque 687 linhas de produção já se chamam "Meu Currículo" — sem
/// isto, renomear produz mais colisão em vez de menos.
String resolveUniqueTitle(String desejado, List<String> existentes) {
  final limpo = desejado.trim();
  if (limpo.isEmpty) return limpo;

  final usados = existentes.map((t) => t.trim().toLowerCase()).toSet();
  if (!usados.contains(limpo.toLowerCase())) return limpo;

  for (var i = 2; i < 100; i++) {
    final tentativa = '$limpo ($i)';
    if (!usados.contains(tentativa.toLowerCase())) return tentativa;
  }
  return limpo;
}
