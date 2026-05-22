// Edge Function: daily-report
//
// Roda diariamente via pg_cron (10h UTC = 7h BRT). Agrega métricas de
// usuários, vagas, engajamento e CVs adaptados, monta um email rico
// (Resend) e um teaser curto (ntfy.sh) e envia pro fundador.
//
// Modo semanal: aos domingos (UTC), inclui resumo dos últimos 7 dias com WoW.
//
// Acesso:
// - Header `x-cron-secret: <CRON_SECRET>` (pg_cron) OU Authorization Bearer JWT.
//
// Body (JSON, opcional):
// {
//   "dryRun": false,         // se true, não envia email/ntfy — só retorna o payload
//   "weeklyDigest": false,   // força modo semanal (default: auto-detecta domingo)
//   "targetEmail": "..."     // override do destinatário (útil pra teste)
// }
//
// Env vars (configurar via `supabase secrets set`):
//   CRON_SECRET                   ← já existe
//   RESEND_API_KEY                ← NOVO
//   REPORT_EMAIL_FROM             ← NOVO (ex: "Stage <reports@stage-app.com.br>")
//   REPORT_EMAIL_TO               ← NOVO (ex: "zackourilopes@outlook.com")
//   NTFY_TOPIC_REPORT             ← NOVO (pode ser o mesmo do signup)
//   NTFY_HOST                     ← opcional, default "https://ntfy.sh"
//   POSTHOG_API_KEY               ← opcional, pra captureEvent de telemetria
//   SUPABASE_URL                  (auto)
//   SUPABASE_SERVICE_ROLE_KEY     (auto)

import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { captureEvent } from '../_shared/posthog.ts'
import {
  computeGapBlock,
  computeWindow,
  fetchCvAdaptedBlock,
  fetchEngagementBlock,
  fetchHealthBlock,
  fetchJobsInsertedBlock,
  fetchJobsStockBlock,
  fetchMatchBlock,
  fetchUsersBlock,
  fetchUsersTotalBlock,
  fetchWeeklyBlock,
} from './queries.ts'
import { renderEmailHtml, renderNtfyText, type ReportPayload } from './html_template.ts'

const CRON_SECRET = Deno.env.get('CRON_SECRET') ?? ''
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const REPORT_EMAIL_FROM = Deno.env.get('REPORT_EMAIL_FROM') ?? 'Stage <onboarding@resend.dev>'
const REPORT_EMAIL_TO = Deno.env.get('REPORT_EMAIL_TO') ?? ''
const NTFY_TOPIC_REPORT = Deno.env.get('NTFY_TOPIC_REPORT') ?? ''
const NTFY_HOST = Deno.env.get('NTFY_HOST') ?? 'https://ntfy.sh'
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
  return (req.headers.get('Authorization') ?? '').startsWith('Bearer ')
}

async function sendEmail(html: string, subject: string, to: string): Promise<{ ok: boolean; status: number; body: string }> {
  if (!RESEND_API_KEY) {
    return { ok: false, status: 0, body: 'RESEND_API_KEY not set' }
  }
  const resp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: REPORT_EMAIL_FROM,
      to: [to],
      subject,
      html,
    }),
  })
  const text = await resp.text()
  return { ok: resp.ok, status: resp.status, body: text.slice(0, 500) }
}

async function sendNtfy(title: string, message: string): Promise<{ ok: boolean; status: number; body: string }> {
  if (!NTFY_TOPIC_REPORT) {
    return { ok: false, status: 0, body: 'NTFY_TOPIC_REPORT not set' }
  }
  // Mesmo padrão JSON do `notify-signup` pra suportar unicode no título.
  const resp = await fetch(NTFY_HOST, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      topic: NTFY_TOPIC_REPORT,
      title,
      message,
      priority: 3,
      tags: ['bar_chart', 'iphone'],
    }),
  })
  const text = await resp.text()
  return { ok: resp.ok, status: resp.status, body: text.slice(0, 300) }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (!isAuthorized(req)) {
    return jsonResponse({ error: 'unauthorized' }, 401)
  }

  const body = await req.json().catch(() => ({})) as {
    dryRun?: boolean
    weeklyDigest?: boolean
    targetEmail?: string
  }
  const dryRun = body.dryRun === true
  const targetEmail = body.targetEmail?.trim() || REPORT_EMAIL_TO

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  const win = computeWindow(new Date())
  const isWeekly = body.weeklyDigest === true || win.isSunday

  // Roda tudo em paralelo — independentes entre si.
  const [usersTotal, users, engagement, jobsInserted, jobsStock, match, cvAdapted, health, weekly] =
    await Promise.all([
      fetchUsersTotalBlock(supabase),
      fetchUsersBlock(supabase, win),
      fetchEngagementBlock(supabase, win),
      fetchJobsInsertedBlock(supabase, win),
      fetchJobsStockBlock(supabase),
      fetchMatchBlock(supabase, win),
      fetchCvAdaptedBlock(supabase, win),
      fetchHealthBlock(supabase, win),
      isWeekly ? fetchWeeklyBlock(supabase, win) : Promise.resolve(undefined),
    ])

  const gap = computeGapBlock(match.likesByArea, jobsStock.byArea)

  const payload: ReportPayload = {
    window: win,
    usersTotal,
    users,
    engagement,
    jobsInserted,
    jobsStock,
    match,
    cvAdapted,
    gap,
    health,
    weekly,
  }

  const html = renderEmailHtml(payload)
  const ntfy = renderNtfyText(payload)
  const subject = isWeekly
    ? `Stage — Relatório Diário + Semanal (${win.yesterday.label})`
    : `Stage — Relatório Diário (${win.yesterday.label})`

  if (dryRun) {
    return jsonResponse({
      mode: 'dryRun',
      window: win,
      isWeekly,
      summary: {
        newSignups: users.newSignups,
        newJobs: jobsInserted.total,
        likes: match.totalLikes,
        applies: match.totalApplies,
        dau: engagement.dau,
        cvAdapted: cvAdapted.total,
      },
      ntfy,
      htmlPreview: html.slice(0, 2000) + '...',
      htmlLength: html.length,
    })
  }

  if (!targetEmail) {
    return jsonResponse({ error: 'no_target_email', detail: 'set REPORT_EMAIL_TO env var or pass targetEmail in body' }, 400)
  }

  // Envia email e ntfy em paralelo — falha de um não bloqueia o outro.
  const [emailResult, ntfyResult] = await Promise.all([
    sendEmail(html, subject, targetEmail).catch((e) => ({
      ok: false,
      status: 500,
      body: String(e).slice(0, 300),
    })),
    sendNtfy(ntfy.title, ntfy.message).catch((e) => ({
      ok: false,
      status: 500,
      body: String(e).slice(0, 300),
    })),
  ])

  // Telemetria — fire-and-forget pro PostHog.
  captureEvent({
    event: 'daily_report_sent',
    distinctId: 'cron:daily-report',
    properties: {
      cron: 'daily-report',
      is_weekly: isWeekly,
      new_signups: users.newSignups,
      new_jobs: jobsInserted.total,
      likes: match.totalLikes,
      applies: match.totalApplies,
      dau: engagement.dau,
      cv_adapted: cvAdapted.total,
      email_status: emailResult.status,
      email_ok: emailResult.ok,
      ntfy_status: ntfyResult.status,
      ntfy_ok: ntfyResult.ok,
      status: emailResult.ok ? 'success' : 'failed',
    },
  }).catch(() => {})

  return jsonResponse({
    ok: emailResult.ok || ntfyResult.ok,
    isWeekly,
    window: { yesterday: win.yesterday.label, lastWeek: win.lastWeek.label },
    email: {
      to: targetEmail,
      ok: emailResult.ok,
      status: emailResult.status,
      response: emailResult.body,
    },
    ntfy: {
      ok: ntfyResult.ok,
      status: ntfyResult.status,
      response: ntfyResult.body,
    },
    summary: {
      newSignups: users.newSignups,
      newJobs: jobsInserted.total,
      likes: match.totalLikes,
      applies: match.totalApplies,
    },
  })
})
