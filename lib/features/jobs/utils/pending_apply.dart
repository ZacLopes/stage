/// Estado e decisão do prompt de retorno pós-apply (FASE 3 T3.2).
///
/// Quando o usuário aplica (único call site: liked_jobs_screen::_openApplication),
/// gravamos um `pending_apply` único. No próximo foreground, o HomeScreen decide
/// se mostra o bottom sheet "Você se candidatou?". Lógica de decisão PURA aqui
/// (testável); persistência no JobSwipeContext.
library;

/// Janela em que o prompt dispara após o apply (decisão do arquiteto).
const Duration kPendingApplyWindow = Duration(minutes: 30);

/// Re-pergunta única após "Depois" (decisão do fundador: 24h, in-app — sem push).
const Duration kPendingApplyReaskAfter = Duration(hours: 24);

/// Janela de validade da re-pergunta: se o usuário não voltar em até 24h depois
/// do reask agendado, desiste (não mostra prompt stale dias depois).
const Duration kPendingApplyReaskWindow = Duration(hours: 24);

enum PendingApplyDecision {
  /// Mostrar o prompt agora.
  show,

  /// Ainda não — esperar (reask agendado pro futuro).
  wait,

  /// Passou da janela — limpar o pending sem perguntar.
  expired,
}

class PendingApply {
  final String jobId;
  final String title;
  final String company;

  /// Fonte da vaga (gupy/greenhouse/email/null) — alimenta o `job_source` do
  /// evento de abandono (fricção por fonte, o dado estratégico).
  final String? source;

  /// Epoch ms de quando aplicou.
  final int tsMs;

  /// Epoch ms a partir do qual a re-pergunta vale (setado quando o user toca
  /// "Depois"); null = ainda na 1ª janela.
  final int? reaskAfterMs;

  const PendingApply({
    required this.jobId,
    required this.title,
    required this.company,
    this.source,
    required this.tsMs,
    this.reaskAfterMs,
  });

  PendingApply withReask(int reaskAfterMs) => PendingApply(
        jobId: jobId,
        title: title,
        company: company,
        source: source,
        tsMs: tsMs,
        reaskAfterMs: reaskAfterMs,
      );

  Map<String, dynamic> toJson() => {
        'job_id': jobId,
        'title': title,
        'company': company,
        if (source != null) 'source': source,
        'ts': tsMs,
        if (reaskAfterMs != null) 'reask_after': reaskAfterMs,
      };

  static PendingApply? fromJson(Map<String, dynamic> json) {
    final jobId = json['job_id'];
    final ts = json['ts'];
    if (jobId is! String || ts is! int) return null;
    return PendingApply(
      jobId: jobId,
      title: (json['title'] as String?) ?? '',
      company: (json['company'] as String?) ?? '',
      source: json['source'] as String?,
      tsMs: ts,
      reaskAfterMs: json['reask_after'] is int ? json['reask_after'] as int : null,
    );
  }
}

/// Decide o que fazer com um `pending_apply` no foreground. Pura.
PendingApplyDecision pendingApplyDecision(PendingApply p, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  if (p.reaskAfterMs == null) {
    final age = nowMs - p.tsMs;
    if (age < 0) return PendingApplyDecision.wait; // clock skew → não some
    if (age <= kPendingApplyWindow.inMilliseconds) return PendingApplyDecision.show;
    return PendingApplyDecision.expired;
  }
  if (nowMs < p.reaskAfterMs!) return PendingApplyDecision.wait;
  if (nowMs <= p.reaskAfterMs! + kPendingApplyReaskWindow.inMilliseconds) {
    return PendingApplyDecision.show;
  }
  return PendingApplyDecision.expired;
}

/// Motivos de abandono (decisão do fundador: 4 chips fixos, sem "Outro").
/// O `id` é o valor estratégico (fricção por fonte); o label é a UI.
enum ApplyAbandonReason {
  processoLongo('processo_longo', 'Processo longo demais'),
  vagaFechada('vaga_fechada', 'Vaga já fechada'),
  pediramDemais('pediram_demais', 'Pediram coisas demais'),
  soOlhando('so_olhando', 'Só estava olhando');

  final String id;
  final String label;
  const ApplyAbandonReason(this.id, this.label);
}
