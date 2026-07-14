// Testes do critério countsAsApplied (Fase 7 Onda 1 — Tarefa 3, R3).
//   deno test supabase/functions/daily-report/queries.test.ts
//
// A fonte de "apliquei" migrou de swipe_actions.applied (DEPRECATED) para a
// tabela applications. "Conta como aplicada" = qualquer status EXCETO
// withdrawn/expired — espelha applications.dart::countsAsApplied (rejected
// conta: o candidato aplicou, o desfecho é que foi negativo).
import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import { countsAsApplied } from './queries.ts';

Deno.test('submitted conta como aplicada', () => {
  assertEquals(countsAsApplied('submitted'), true);
});

Deno.test('rejected conta (aplicou; desfecho negativo)', () => {
  assertEquals(countsAsApplied('rejected'), true);
});

Deno.test('estados vivos do pipeline contam', () => {
  for (const s of ['in_review', 'shortlisted', 'interview', 'offer', 'hired']) {
    assertEquals(countsAsApplied(s), true, s);
  }
});

Deno.test('withdrawn NÃO conta', () => {
  assertEquals(countsAsApplied('withdrawn'), false);
});

Deno.test('expired NÃO conta', () => {
  assertEquals(countsAsApplied('expired'), false);
});

Deno.test('null/undefined não estouram (status é NOT NULL na base, mas defesa)', () => {
  assertEquals(countsAsApplied(null), true);
  assertEquals(countsAsApplied(undefined), true);
});
