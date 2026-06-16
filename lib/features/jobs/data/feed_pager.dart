/// FASE 2 (T2.2): estado e parsing da paginação keyset do RPC `get_feed_page`.
///
/// Puro (sem Supabase): o transporte entra injetado via [FeedRpc], então
/// cursor/sentinela/dedup/totais são unit-testáveis com rows fake (R3 —
/// "unit do cursor/paginação com mock do rpc"). O JobsViewModel injeta
/// `JobRepository.callFeedPageRpc` como transporte real.
///
/// Contrato do RPC (migrations 20260612120000→140000):
/// - keyset `(rank_score DESC, id DESC)`; cursor = última row da página.
/// - `rank_score` chega quantizado em 6 casas (v1.2) — o roundtrip
///   JSON→double→toString é EXATO, então guardar double aqui é seguro.
/// - `p_frozen_at` fixo por sessão de paginação (D-7) — congela freshness
///   e jitter pra que o cursor não derive entre páginas.
/// - 1ª página carrega `total_after_filters`/`total_available` nas rows;
///   1ª página VAZIA vem como 1 row-sentinela com `job_id` null e os
///   totais (estado B da exaustão: after=0 com available>0 = "filtros
///   zeraram"; available=0 = catálogo esgotado).
library;

typedef FeedRpc = Future<List<dynamic>> Function(Map<String, dynamic> params);

/// Uma row do feed (id + score determinístico server + razões do ranking).
class FeedPageRow {
  final String jobId;
  final int score;
  final double rankScore;
  final bool reasonArea;
  final bool reasonLocation;
  final bool reasonWorkModel;
  final bool reasonJobType;
  final bool reasonSalary;

  const FeedPageRow({
    required this.jobId,
    required this.score,
    required this.rankScore,
    required this.reasonArea,
    required this.reasonLocation,
    required this.reasonWorkModel,
    required this.reasonJobType,
    required this.reasonSalary,
  });

  factory FeedPageRow.fromMap(Map<String, dynamic> m) => FeedPageRow(
        jobId: m['job_id'] as String,
        score: (m['score'] as num?)?.toInt() ?? 0,
        rankScore: (m['rank_score'] as num?)?.toDouble() ?? 0,
        reasonArea: (m['reason_area'] as bool?) ?? false,
        reasonLocation: (m['reason_location'] as bool?) ?? false,
        reasonWorkModel: (m['reason_work_model'] as bool?) ?? false,
        reasonJobType: (m['reason_job_type'] as bool?) ?? false,
        reasonSalary: (m['reason_salary'] as bool?) ?? false,
      );

  /// Labels das razões que CASARAM — chips da célula da lista.
  List<String> get matchedReasonLabels => [
        if (reasonArea) 'Área',
        if (reasonLocation) 'Local',
        if (reasonWorkModel) 'Modelo',
        if (reasonJobType) 'Tipo',
        if (reasonSalary) 'Salário',
      ];
}

class FeedPager {
  FeedPager(this._rpc, {this.pageSize = 20});

  final FeedRpc _rpc;
  final int pageSize;

  DateTime? _frozenAt;
  double? _cursorRank;
  String? _cursorId;
  bool _hasMore = true;
  bool _started = false;
  int? _totalAfterFilters;
  int? _totalAvailable;
  int? _totalMatchingCatalog;
  final Set<String> _seenIds = {};

  bool get hasMore => _hasMore;
  bool get started => _started;

  /// Totais da 1ª página (null antes dela chegar). Semântica do RPC:
  /// `totalAfterFilters` = pós-filtros de args; `totalAvailable` = pós
  /// exclusões básicas (swipes/deadline/ativa), PRÉ filtros;
  /// `totalMatchingCatalog` = bate com os filtros no catálogo INTEIRO
  /// (IGNORANDO swipe) — distingue "esgotou" (>0 → A) de "filtros
  /// restritivos" (0 → B). Adicionado no get_feed_page v1.3 (#5).
  int? get totalAfterFilters => _totalAfterFilters;
  int? get totalAvailable => _totalAvailable;
  int? get totalMatchingCatalog => _totalMatchingCatalog;

  /// Reinicia a sessão de paginação (pull-to-refresh, troca de filtros ou
  /// de modo). O próximo [fetchNext] congela um `p_frozen_at` novo.
  void reset() {
    _frozenAt = null;
    _cursorRank = null;
    _cursorId = null;
    _hasMore = true;
    _started = false;
    _totalAfterFilters = null;
    _totalAvailable = null;
    _totalMatchingCatalog = null;
    _seenIds.clear();
  }

  /// Busca a próxima página. Filtros = resolvidos pelo caller (locais SE
  /// existem, senão prefs do Perfil — D-8); listas vazias viram null
  /// (= sem filtro, espelho do isEmpty do client e do RPC).
  Future<List<FeedPageRow>> fetchNext({
    List<String>? areas,
    List<String>? locations,
    List<String>? workModels,
    List<String>? jobTypes,
    int? minSalary,
  }) async {
    if (!_hasMore) return const [];
    _frozenAt ??= DateTime.now().toUtc();
    _started = true;

    final params = <String, dynamic>{
      'p_limit': pageSize,
      'p_frozen_at': _frozenAt!.toIso8601String(),
      if (_cursorRank != null && _cursorId != null) ...{
        'p_cursor_rank': _cursorRank,
        'p_cursor_id': _cursorId,
      },
      if (areas != null && areas.isNotEmpty) 'p_filter_areas': areas,
      if (locations != null && locations.isNotEmpty)
        'p_filter_locations': locations,
      if (workModels != null && workModels.isNotEmpty)
        'p_filter_work_models': workModels,
      if (jobTypes != null && jobTypes.isNotEmpty)
        'p_filter_job_types': jobTypes,
      if (minSalary != null && minSalary > 0) 'p_min_salary': minSalary,
    };

    final raw = await _rpc(params);
    final out = <FeedPageRow>[];
    var nonSentinelRows = 0;

    for (final item in raw) {
      final m = Map<String, dynamic>.from(item as Map);
      final taf = (m['total_after_filters'] as num?)?.toInt();
      final tav = (m['total_available'] as num?)?.toInt();
      final tmc = (m['total_matching_catalog'] as num?)?.toInt();
      if (taf != null) _totalAfterFilters ??= taf;
      if (tav != null) _totalAvailable ??= tav;
      if (tmc != null) _totalMatchingCatalog ??= tmc;

      if (m['job_id'] == null) continue; // sentinela do estado B (só totais)
      nonSentinelRows++;

      final row = FeedPageRow.fromMap(m);
      _cursorRank = row.rankScore;
      _cursorId = row.jobId;
      // Dedup defensivo: cursor float-safe (v1.2) torna duplicata
      // improvável, mas uma repetida nunca deve duplicar célula/card.
      if (_seenIds.add(row.jobId)) out.add(row);
    }

    if (nonSentinelRows < pageSize) _hasMore = false;
    return out;
  }
}
