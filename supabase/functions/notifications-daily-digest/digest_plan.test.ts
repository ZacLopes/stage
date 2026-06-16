// Testes da lógica PURA do digest (FASE 3 T3.5). Roda com:
//   deno test supabase/functions/notifications-daily-digest/digest_plan.test.ts
//
// Foco: a DEDUPE (correção 2 do fundador) — verificada, não afirmada.
import {
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  deadlineVariant,
  type NudgeCandidate,
  pickVariant,
  planDigestPushes,
} from "./digest_plan.ts";

const nudge = (
  id: string,
  opts: Partial<Omit<NudgeCandidate, "id">> = {},
): NudgeCandidate => ({
  id,
  hasAdaptedNotExported: opts.hasAdaptedNotExported ?? false,
  hasCompletedPhase: opts.hasCompletedPhase ?? false,
});

// ── DEDUPE: usuário no cohort D+1 E com vaga expirando → 1 push, o de prazo ──
Deno.test("dedupe: D+1 + prazo → exatamente 1 push, intent saved_deadline_48h", () => {
  const plan = planDigestPushes(
    [nudge("u-both", { hasCompletedPhase: true })],
    [{ user_id: "u-both", n: 2 }],
  );
  const forUser = plan.filter((p) => p.userId === "u-both");
  assertEquals(forUser.length, 1);
  assertEquals(forUser[0].variant.intent, "saved_deadline_48h");
});

Deno.test("dedupe: cohort de prazo com id repetido não duplica", () => {
  const plan = planDigestPushes(
    [],
    [{ user_id: "u1", n: 1 }, { user_id: "u1", n: 3 }],
  );
  assertEquals(plan.length, 1);
  assertEquals(plan[0].variant.intent, "saved_deadline_48h");
});

Deno.test("prioridade: prazo vem antes do nudge na ordem do plano", () => {
  const plan = planDigestPushes(
    [nudge("u-nudge")],
    [{ user_id: "u-deadline", n: 1 }],
  );
  assertEquals(plan.length, 2);
  assertEquals(plan[0].userId, "u-deadline");
  assertEquals(plan[0].variant.intent, "saved_deadline_48h");
  assertEquals(plan[1].userId, "u-nudge");
  assertEquals(plan[1].variant.intent, "new_jobs");
});

Deno.test("sem cohort de prazo: nudge D+1 segue intacto", () => {
  const plan = planDigestPushes(
    [
      nudge("a", { hasAdaptedNotExported: true }),
      nudge("b", { hasCompletedPhase: true }),
      nudge("c"),
    ],
    [],
  );
  assertEquals(plan.map((p) => p.variant.intent), [
    "cv_adapted_pending_export",
    "phase_continue",
    "new_jobs",
  ]);
});

// ── Cópia das variantes ─────────────────────────────────────────────────────
Deno.test("deadlineVariant: plural vs singular", () => {
  assertEquals(deadlineVariant(1).title, "⏰ 1 vaga salva fecha em 48h");
  assertEquals(deadlineVariant(3).title, "⏰ 3 vagas salvas fecham em 48h");
  // guarda defensiva: n inválido cai em 1
  assertEquals(deadlineVariant(0).title, "⏰ 1 vaga salva fecha em 48h");
});

Deno.test("pickVariant: precedência adapted > phase > new_jobs", () => {
  assertEquals(
    pickVariant({ hasAdaptedNotExported: true, hasCompletedPhase: true }).intent,
    "cv_adapted_pending_export",
  );
  assertEquals(
    pickVariant({ hasAdaptedNotExported: false, hasCompletedPhase: true }).intent,
    "phase_continue",
  );
  assertEquals(
    pickVariant({ hasAdaptedNotExported: false, hasCompletedPhase: false }).intent,
    "new_jobs",
  );
});
