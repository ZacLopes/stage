// Edge Function: notifications-broadcast
//
// Dispara push pra TODOS os users de um segmento OneSignal (ou pra todos
// com push ativo, por default). Diferente do `notifications-daily-digest`
// que é direcionado por janela D+1 + contextual, esta function é one-shot
// e o caller (você, via SQL ou cron) decide:
//   - O segmento (ex.: "Subscribed Users", "Active Users", ou custom criado no dashboard)
//   - O título e mensagem
//   - Quando disparar
//
// Uso típico:
//   - Anúncio de nova feature ("📬 Novas vagas em Marketing")
//   - Re-engajamento ("📊 Esta semana adicionamos 200 vagas pra você")
//   - Comunicado importante
//
// ⚠️ Frequência mata: cada push genérico reduz sua base alcançável pra
// sempre. Use com economia. Recomendado < 1x/semana pra audience ampla.
//
// Acesso:
// - Header `x-cron-secret: <CRON_SECRET>` (pg_cron) OU Authorization Bearer JWT.
//
// Body (JSON):
// {
//   "title": "🚀 Novas vagas",      // obrigatório, max ~50 chars (iOS)
//   "message": "Bora dar uma...",   // obrigatório, max ~200 chars
//   "segment": "Subscribed Users",  // opcional, default "Subscribed Users"
//   "data": { "intent": "..." },    // opcional, payload custom
//   "dryRun": false                 // opcional, true = não envia, só simula
// }
//
// Segmentos disponíveis (criados pelo OneSignal por default):
//   - "Subscribed Users" — TODOS com push ativo
//   - "Active Users"     — login nos últimos 7 dias
//   - "Engaged Users"    — abriu push recente
// Segmentos custom: criar via dashboard (Audience → Segments) primeiro.
//
// Env vars: ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY, CRON_SECRET.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

import {
  captureEvent,
  EV_PUSH_SEND_COMPLETED,
  EV_PUSH_SEND_INITIATED,
  trackEdgeFunctionInvoked,
} from '../_shared/posthog.ts'

const CRON_SECRET = Deno.env.get('CRON_SECRET') ?? ''
const ONESIGNAL_APP_ID = Deno.env.get('ONESIGNAL_APP_ID') ?? ''
const ONESIGNAL_REST_API_KEY = Deno.env.get('ONESIGNAL_REST_API_KEY') ?? ''

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

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const fnStart = Date.now()

  if (!isAuthorized(req)) {
    trackEdgeFunctionInvoked({
      functionName: 'notifications-broadcast',
      distinctId: 'edge_function:notifications-broadcast',
      durationMs: Date.now() - fnStart,
      status: 'unauthorized',
    }).catch(() => {})
    return jsonResponse({ error: 'unauthorized' }, 401)
  }

  if (!ONESIGNAL_APP_ID || !ONESIGNAL_REST_API_KEY) {
    return jsonResponse({ error: 'onesignal_not_configured' }, 500)
  }

  const body = await req.json().catch(() => ({})) as {
    title?: string
    message?: string
    segment?: string
    data?: Record<string, unknown>
    dryRun?: boolean
  }

  const title = (body.title ?? '').trim()
  const message = (body.message ?? '').trim()
  const segment = body.segment?.trim() || 'Subscribed Users'
  const dryRun = body.dryRun === true

  if (!title || !message) {
    return jsonResponse({
      error: 'missing_required_fields',
      detail: 'title and message are required',
    }, 400)
  }
  if (title.length > 100) {
    return jsonResponse({ error: 'title_too_long', max: 100 }, 400)
  }
  if (message.length > 500) {
    return jsonResponse({ error: 'message_too_long', max: 500 }, 400)
  }

  if (dryRun) {
    return jsonResponse({
      dryRun: true,
      preview: {
        title,
        message,
        segment,
        data: body.data ?? null,
      },
      note: 'Set dryRun=false to actually send.',
    })
  }

  // OneSignal payload — usa `included_segments` em vez de
  // `include_external_user_ids` pra broadcast eficiente (1 chamada =
  // entrega pra N users, sem loop por usuário).
  // `sent_at` em data permite o app client calcular `time_from_send_ms`
  // no `push_opened` (B.10 do plano v2 — fix do gap de attribution).
  const sentAtIso = new Date().toISOString()
  const onesignalPayload = {
    app_id: ONESIGNAL_APP_ID,
    included_segments: [segment],
    headings: { en: title, pt: title },
    contents: { en: message, pt: message },
    data: {
      ...(body.data ?? {}),
      source: 'broadcast',
      campaign: 'broadcast',
      type: 'broadcast',
      sent_at: sentAtIso,
    },
    // ttl 24h — broadcasts geralmente perdem valor depois de 1 dia.
    ttl: 86400,
  }

  // B.10 — push_send_initiated. Marca intenção antes da chamada OneSignal,
  // separado de push_send_completed pra detectar falhas pré-envio.
  captureEvent({
    event: EV_PUSH_SEND_INITIATED,
    distinctId: 'edge_function:notifications-broadcast',
    properties: {
      campaign: 'broadcast',
      segment,
      title_length: title.length,
      message_length: message.length,
    },
  }).catch(() => {})

  let resp: Response
  try {
    resp = await fetch('https://onesignal.com/api/v1/notifications', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
      },
      body: JSON.stringify(onesignalPayload),
    })
  } catch (e) {
    trackEdgeFunctionInvoked({
      functionName: 'notifications-broadcast',
      distinctId: 'edge_function:notifications-broadcast',
      durationMs: Date.now() - fnStart,
      status: 'error',
      errorCode: 'onesignal_fetch_failed',
      extra: { error_message: String(e).slice(0, 300) },
    }).catch(() => {})
    return jsonResponse({
      ok: false,
      error: 'onesignal_fetch_failed',
      detail: String(e).slice(0, 300),
    }, 500)
  }

  const onesignalText = await resp.text()
  let onesignalBody: unknown
  try {
    onesignalBody = JSON.parse(onesignalText)
  } catch {
    onesignalBody = onesignalText.slice(0, 500)
  }

  // B.10 — push_send_completed (status + recipients). OneSignal retorna
  // `recipients` quando ok=true; em erro retorna `errors[]`.
  const recipients =
    typeof onesignalBody === 'object' && onesignalBody !== null
      ? Number((onesignalBody as Record<string, unknown>).recipients ?? 0)
      : 0
  captureEvent({
    event: EV_PUSH_SEND_COMPLETED,
    distinctId: 'edge_function:notifications-broadcast',
    properties: {
      campaign: 'broadcast',
      segment,
      ok: resp.ok,
      http_status: resp.status,
      delivered_count: recipients,
      failed_count: resp.ok ? 0 : 1,
    },
  }).catch(() => {})

  trackEdgeFunctionInvoked({
    functionName: 'notifications-broadcast',
    distinctId: 'edge_function:notifications-broadcast',
    durationMs: Date.now() - fnStart,
    status: resp.ok ? 'ok' : 'error',
    ...(resp.ok ? {} : { errorCode: `onesignal_http_${resp.status}` }),
    extra: { delivered_count: recipients, segment },
  }).catch(() => {})

  return jsonResponse({
    ok: resp.ok,
    status: resp.status,
    segment,
    title,
    onesignal: onesignalBody,
  }, resp.ok ? 200 : 502)
})
