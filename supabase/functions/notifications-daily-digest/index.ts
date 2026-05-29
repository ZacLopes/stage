// Edge Function: notifications-daily-digest
//
// Roda diariamente (via pg_cron / cron-job.org) e envia 1 push de retenção
// pra cada user que está em "janela D+1" (signed up entre 22h e 26h atrás).
// Mensagem é contextual ao estado do user:
//   - Se adaptou CV mas não exportou → "📄 seu CV adaptado tá esperando"
//   - Senão se completou alguma fase  → "🚀 desbloqueie a próxima fase"
//   - Senão                            → "📬 novas vagas com match alto chegaram"
//
// Pré-fix: D1 retention = 6-12%, 91% dos usuários D1-only. Sem trigger
// externo, app evapora.
//
// Acesso:
// - Header `x-cron-secret: <CRON_SECRET>` (pg_cron) OU Authorization Bearer JWT.
//
// Body (JSON, opcional):
// {
//   "windowHoursStart": 22,   // default 22h atrás
//   "windowHoursEnd": 26,     // default 26h atrás
//   "dryRun": false           // se true, só lista candidatos sem mandar push
// }
//
// Env vars:
//   ONESIGNAL_APP_ID
//   ONESIGNAL_REST_API_KEY   ← novo, configurar via `supabase secrets set`
//   CRON_SECRET
//   SUPABASE_URL              (auto)
//   SUPABASE_SERVICE_ROLE_KEY (auto)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { captureEvent, withEdgeAnalytics } from '../_shared/posthog.ts'

const CRON_SECRET = Deno.env.get('CRON_SECRET') ?? ''
const ONESIGNAL_APP_ID = Deno.env.get('ONESIGNAL_APP_ID') ?? ''
const ONESIGNAL_REST_API_KEY = Deno.env.get('ONESIGNAL_REST_API_KEY') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, x-cron-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function isAuthorized(req: Request): boolean {
  const cronHeader = req.headers.get('x-cron-secret') ?? ''
  if (CRON_SECRET && cronHeader === CRON_SECRET) return true
  // Fallback: qualquer Bearer JWT válido (gateway Supabase valida).
  return (req.headers.get('Authorization') ?? '').startsWith('Bearer ')
}

interface DigestVariant {
  title: string
  message: string
  /// `intent` vira tag na notificação (segmentação no PostHog opcional).
  intent: 'cv_adapted_pending_export' | 'phase_continue' | 'new_jobs'
}

function pickVariant({
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

async function sendOneSignalPush(
  externalUserId: string,
  variant: DigestVariant,
): Promise<{ ok: boolean; status: number; body: string }> {
  const resp = await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
    },
    body: JSON.stringify({
      app_id: ONESIGNAL_APP_ID,
      include_external_user_ids: [externalUserId],
      channel_for_external_user_ids: 'push',
      headings: { en: variant.title, pt: variant.title },
      contents: { en: variant.message, pt: variant.message },
      data: { intent: variant.intent, source: 'daily_digest_d1' },
      // ttl curto — push de retenção perde valor depois de 24h.
      ttl: 86400,
    }),
  })
  const text = await resp.text()
  return { ok: resp.ok, status: resp.status, body: text.slice(0, 300) }
}

serve(withEdgeAnalytics('notifications-daily-digest', async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (!isAuthorized(req)) {
    return jsonResponse({ error: 'unauthorized' }, 401)
  }

  if (!ONESIGNAL_APP_ID || !ONESIGNAL_REST_API_KEY) {
    return jsonResponse({ error: 'onesignal_not_configured' }, 500)
  }

  const body = await req.json().catch(() => ({})) as {
    windowHoursStart?: number
    windowHoursEnd?: number
    dryRun?: boolean
    /// Override de teste: ignora a janela D+1 e dispara só pra esses emails.
    /// Útil pra dev/QA validar a function antes do cron real. Aceita 1+ emails.
    targetEmails?: string[]
  }
  const windowHoursStart = body.windowHoursStart ?? 22
  const windowHoursEnd = body.windowHoursEnd ?? 26
  const dryRun = body.dryRun === true
  const targetEmails = Array.isArray(body.targetEmails)
    ? body.targetEmails.map((e) => String(e).trim().toLowerCase()).filter((e) => e.length > 0)
    : []

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  // 1. Lista users — modo teste (targetEmails) ou modo prod (janela D+1).
  const { data: usersPage, error: listErr } = await supabase.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  })
  if (listErr) {
    return jsonResponse({ error: 'list_users_failed', detail: listErr.message }, 500)
  }

  let candidates
  if (targetEmails.length > 0) {
    // Modo teste: matchea por email exato (case-insensitive)
    candidates = (usersPage?.users ?? []).filter((u) => {
      const email = (u.email ?? '').toLowerCase()
      return targetEmails.includes(email)
    })
    if (candidates.length === 0) {
      return jsonResponse({
        sent: 0,
        candidates: 0,
        mode: 'targetEmails',
        targetEmails,
        note: 'no users matched targetEmails',
      })
    }
  } else {
    // Modo prod: janela D+1 (22-26h atrás por default)
    const now = Date.now()
    const startedAfter = new Date(now - windowHoursEnd * 3600 * 1000).toISOString()
    const startedBefore = new Date(now - windowHoursStart * 3600 * 1000).toISOString()
    candidates = (usersPage?.users ?? []).filter((u) => {
      const created = new Date(u.created_at ?? 0).toISOString()
      return created >= startedAfter && created < startedBefore
    })
    if (candidates.length === 0) {
      return jsonResponse({
        sent: 0,
        candidates: 0,
        windowHoursStart,
        windowHoursEnd,
        note: 'no users in window',
      })
    }
  }

  const candidateIds = candidates.map((u) => u.id)

  // 2. Estado de cada candidato — uma query por tabela, em batch.
  // Heurística D+1: se tem row em adapted_resumes mas não exportou,
  // provavelmente esqueceu — dispara o push do CV adaptado.
  // saved_resumes NÃO ajuda a decidir "exportou" porque ela também guarda
  // CVs IMPORTADOS pelo picker (o schema conflate import e save). Sem flag
  // was_exported no DB, o melhor sinal disponível é "tem adapted_resume".
  const { data: adaptedRows } = await supabase
    .from('adapted_resumes')
    .select('user_id')
    .in('user_id', candidateIds)
  const adaptedSet = new Set((adaptedRows ?? []).map((r) => r.user_id))

  // Tabela correta é `user_progress` (não user_phase_progress). Confirmado
  // em lib/data/supabase_repository.dart:322 (markPhaseCompleted).
  const { data: phaseRows } = await supabase
    .from('user_progress')
    .select('user_id')
    .in('user_id', candidateIds)
    .eq('completed', true)
  const completedPhaseSet = new Set((phaseRows ?? []).map((r) => r.user_id))

  // 3. Pra cada candidato, escolhe variante e envia.
  const results: Array<{
    userId: string
    intent: string
    status: number | 'dry_run'
    ok: boolean
    onesignalResponse?: string
  }> = []

  for (const u of candidates) {
    const hasAdaptedNotExported = adaptedSet.has(u.id)
    const hasCompletedPhase = completedPhaseSet.has(u.id)
    const variant = pickVariant({ hasAdaptedNotExported, hasCompletedPhase })

    if (dryRun) {
      results.push({
        userId: u.id,
        intent: variant.intent,
        status: 'dry_run',
        ok: true,
      })
      continue
    }

    try {
      const r = await sendOneSignalPush(u.id, variant)
      results.push({
        userId: u.id,
        intent: variant.intent,
        status: r.status,
        ok: r.ok,
        // F: incluir response do OneSignal — sem isso fica impossível debugar
        // entrega (200 do OneSignal não garante recipient encontrado; precisa
        // ver `recipients` no body pra saber se push foi de fato endereçado).
        onesignalResponse: r.body,
      })
    } catch (e) {
      results.push({
        userId: u.id,
        intent: variant.intent,
        status: 500,
        ok: false,
        onesignalResponse: String(e).slice(0, 300),
      })
      console.error('OneSignal send failed for', u.id, e)
    }
  }

  const sent = results.filter((r) => r.ok && r.status !== 'dry_run').length
  const failed = results.filter((r) => !r.ok && r.status !== 'dry_run').length

  // Breakdown por variante — útil pra dashboard saber qual mensagem domina.
  const variantBreakdown: Record<string, number> = {}
  for (const r of results) {
    variantBreakdown[r.intent] = (variantBreakdown[r.intent] ?? 0) + 1
  }

  await captureEvent({
    event: 'notifications_digest_sent',
    distinctId: 'cron:notifications-daily-digest',
    properties: {
      cron: 'notifications-daily-digest',
      candidates: candidates.length,
      pushes_sent: sent,
      pushes_failed: failed,
      dry_run: dryRun,
      window_hours_start: windowHoursStart,
      window_hours_end: windowHoursEnd,
      variant_breakdown: variantBreakdown,
      status: failed > 0 ? (sent > 0 ? 'partial' : 'failed') : 'success',
    },
  }).catch(() => {})

  return jsonResponse({
    candidates: candidates.length,
    sent,
    dryRun,
    windowHoursStart,
    windowHoursEnd,
    results: results.slice(0, 100), // cap pra não ficar payload gigante
  })
}))
