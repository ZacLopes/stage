// Lógica PURA do digest (FASE 3 T3.5) — variantes + planejamento com dedupe.
// Extraída do index.ts pra ser testável sem Supabase/OneSignal (R3): o ponto
// crítico é a DEDUPE — usuário no cohort D+1 E com vaga salva expirando recebe
// EXATAMENTE 1 push (o de prazo, prioridade). Ver digest_plan.test.ts.

export interface DigestVariant {
  title: string
  message: string
  /// `intent` vira tag na notificação (segmentação no PostHog opcional).
  intent:
    | 'cv_adapted_pending_export'
    | 'phase_continue'
    | 'new_jobs'
    | 'saved_deadline_48h'
}

export function pickVariant({
  hasAdaptedNotExported,
  hasCompletedPhase,
}: {
  hasAdaptedNotExported: boolean
  hasCompletedPhase: boolean
}): DigestVariant {
  if (hasAdaptedNotExported) {
    return {
      title: '📄 seu CV adaptado tá te esperando',
      message: 'Volta agora pra baixar antes que esfrie.',
      intent: 'cv_adapted_pending_export',
    }
  }
  if (hasCompletedPhase) {
    return {
      title: '🚀 sua trilha está esperando',
      message: 'Continua de onde parou e libera a próxima fase.',
      intent: 'phase_continue',
    }
  }
  return {
    title: '📬 vagas com match alto chegaram',
    message: 'Dá uma olhada nas que combinam com você.',
    intent: 'new_jobs',
  }
}

// T3.5: prazo de vaga salva em ≤48h. Mesmo canal/template OneSignal, só a intent
// nova — zero tipo de push novo nesta fase.
export function deadlineVariant(n: number): DigestVariant {
  const safeN = n > 0 ? n : 1
  return {
    title: safeN > 1
      ? `⏰ ${safeN} vagas salvas fecham em 48h`
      : '⏰ 1 vaga salva fecha em 48h',
    message: 'Não perca o prazo — aplique agora.',
    intent: 'saved_deadline_48h',
  }
}

export interface NudgeCandidate {
  id: string
  hasAdaptedNotExported: boolean
  hasCompletedPhase: boolean
}

export interface DeadlineCohortRow {
  user_id: string
  n: number
}

export interface PlannedPush {
  userId: string
  variant: DigestVariant
}

/// Planeja os pushes da rodada com DEDUPE + prioridade: o cohort de prazo
/// dispara primeiro e "trava" o usuário (1 push/dia); o nudge D+1 pula quem já
/// recebeu o de prazo. Pura — sem efeitos colaterais.
export function planDigestPushes(
  candidates: NudgeCandidate[],
  deadlineCohort: DeadlineCohortRow[],
): PlannedPush[] {
  const plan: PlannedPush[] = []
  const pushed = new Set<string>()
  for (const row of deadlineCohort) {
    if (pushed.has(row.user_id)) continue
    plan.push({ userId: row.user_id, variant: deadlineVariant(row.n) })
    pushed.add(row.user_id)
  }
  for (const u of candidates) {
    if (pushed.has(u.id)) continue // dedupe: já recebeu o de prazo (prioridade)
    plan.push({ userId: u.id, variant: pickVariant(u) })
    pushed.add(u.id)
  }
  return plan
}
