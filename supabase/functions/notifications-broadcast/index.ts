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

  if (!isAuthorized(req)) {
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
  const onesignalPayload = {
    app_id: ONESIGNAL_APP_ID,
    included_segments: [segment],
    headings: { en: title, pt: title },
    contents: { en: message, pt: message },
    data: {
      ...(body.data ?? {}),
      source: 'broadcast',
    },
    // ttl 24h — broadcasts geralmente perdem valor depois de 1 dia.
    ttl: 86400,
  }

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

  return jsonResponse({
    ok: resp.ok,
    status: resp.status,
    segment,
    title,
    onesignal: onesignalBody,
  }, resp.ok ? 200 : 502)
})
