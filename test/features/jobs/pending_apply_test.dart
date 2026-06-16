import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/jobs/utils/pending_apply.dart';

/// FASE 3 T3.2 (R3): decisão do prompt de retorno. Janela de 30min; "Depois"
/// agenda re-pergunta única em 24h (in-app, sem push); fora das janelas, expira.
void main() {
  PendingApply pending({int? reaskAfterMs, required DateTime ts}) => PendingApply(
        jobId: 'j1',
        title: 'Estágio X',
        company: 'Empresa Y',
        source: 'gupy',
        tsMs: ts.millisecondsSinceEpoch,
        reaskAfterMs: reaskAfterMs,
      );

  final now = DateTime(2026, 6, 16, 12, 0, 0);

  group('pendingApplyDecision — 1ª janela (sem reask)', () {
    test('dentro de 30min → show', () {
      final p = pending(ts: now.subtract(const Duration(minutes: 10)));
      expect(pendingApplyDecision(p, now), PendingApplyDecision.show);
    });

    test('exatamente no limite (30min) → show', () {
      final p = pending(ts: now.subtract(const Duration(minutes: 30)));
      expect(pendingApplyDecision(p, now), PendingApplyDecision.show);
    });

    test('passou de 30min → expired', () {
      final p = pending(ts: now.subtract(const Duration(minutes: 31)));
      expect(pendingApplyDecision(p, now), PendingApplyDecision.expired);
    });

    test('clock skew (ts no futuro) → wait (não some)', () {
      final p = pending(ts: now.add(const Duration(minutes: 5)));
      expect(pendingApplyDecision(p, now), PendingApplyDecision.wait);
    });
  });

  group('pendingApplyDecision — re-pergunta (Depois, +24h)', () {
    test('antes do reaskAfter → wait', () {
      final p = pending(
        ts: now.subtract(const Duration(hours: 2)),
        reaskAfterMs: now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      expect(pendingApplyDecision(p, now), PendingApplyDecision.wait);
    });

    test('depois do reaskAfter, dentro da janela de 24h → show', () {
      final p = pending(
        ts: now.subtract(const Duration(hours: 25)),
        reaskAfterMs: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      expect(pendingApplyDecision(p, now), PendingApplyDecision.show);
    });

    test('reask muito antigo (>24h depois) → expired', () {
      final p = pending(
        ts: now.subtract(const Duration(hours: 60)),
        reaskAfterMs: now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch,
      );
      expect(pendingApplyDecision(p, now), PendingApplyDecision.expired);
    });
  });

  group('PendingApply serialização', () {
    test('roundtrip preserva campos + reask', () {
      final p = pending(
        ts: now,
        reaskAfterMs: now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
      );
      final back = PendingApply.fromJson(p.toJson());
      expect(back, isNotNull);
      expect(back!.jobId, 'j1');
      expect(back.source, 'gupy');
      expect(back.reaskAfterMs, p.reaskAfterMs);
    });

    test('json inválido (sem job_id/ts) → null', () {
      expect(PendingApply.fromJson({'title': 'x'}), isNull);
    });
  });

  group('ApplyAbandonReason — 4 motivos fixos (decisão do fundador)', () {
    test('ids estratégicos esperados', () {
      expect(ApplyAbandonReason.values.map((r) => r.id).toList(), [
        'processo_longo',
        'vaga_fechada',
        'pediram_demais',
        'so_olhando',
      ]);
    });
  });
}
