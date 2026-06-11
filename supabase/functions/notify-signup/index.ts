import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { withEdgeAnalytics } from '../_shared/posthog.ts'

/**
 * notify-signup Edge Function
 *
 * Recebe webhook do Supabase quando alguém é inserido em `user_profiles` e
 * dispara uma notificação formatada via ntfy.sh pro iPhone do fundador.
 *
 * Configurada via Database Webhook: Database > Webhooks > URL aponta pra
 * essa função (https://<project>.supabase.co/functions/v1/notify-signup).
 *
 * Env vars necessárias (set via `supabase secrets set`):
 *  - NTFY_TOPIC: topic secreto do ntfy.sh (ex: "stage-signups-xjsh17g691")
 *  - NTFY_HOST: opcional, default "https://ntfy.sh"
 *
 * Falhas no ntfy nunca propagam — webhook é fire-and-forget. Se quebrar,
 * loga e retorna 200 pra Supabase não retentar.
 */
serve(withEdgeAnalytics('notify-signup', async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  try {
    const payload = await req.json()
    // Payload do Supabase Database Webhook tem o formato:
    // { type: 'INSERT', table: 'user_profiles', record: {...}, schema: 'public' }
    const record = payload.record ?? {}

    // Fase 0 T0.3 (auditoria M4): tópico ntfy é canal best-effort de
    // terceiros — PII de usuário (nome/e-mail/curso) não transita mais
    // por aqui. O push vira contagem do dia + user_id truncado; o detalhe
    // completo o fundador consulta no admin dashboard.
    const userId8 = (record.id ?? '').toString().slice(0, 8) || 'desconhecido'

    // Contagem de cadastros do dia em America/Sao_Paulo (UTC-3 fixo, sem
    // DST desde 2019 — meia-noite SP == 03:00 UTC do mesmo dia SP).
    let countLabel = '?'
    try {
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      )
      const sp = new Date(Date.now() - 3 * 60 * 60 * 1000)
      const dayStartUtc = new Date(Date.UTC(
        sp.getUTCFullYear(), sp.getUTCMonth(), sp.getUTCDate(), 3, 0, 0,
      ))
      const { count } = await supabaseAdmin
        .from('user_profiles')
        .select('id', { count: 'exact', head: true })
        .gte('created_at', dayStartUtc.toISOString())
      if (typeof count === 'number') countLabel = String(count)
    } catch (countErr) {
      console.error('[notify-signup] count do dia falhou:', countErr)
    }

    const body = `Novo cadastro (#${countLabel} hoje) · User ${userId8}`

    const topic = Deno.env.get('NTFY_TOPIC') ?? ''
    const host = Deno.env.get('NTFY_HOST') ?? 'https://ntfy.sh'

    if (!topic) {
      console.error('[notify-signup] NTFY_TOPIC não configurado')
      return new Response(JSON.stringify({ ok: false, reason: 'no_topic' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Usa a API JSON do ntfy (POST em https://ntfy.sh/) pra suportar unicode
    // no título. A forma "POST /topic" com headers só aceita ASCII no Title,
    // o que quebra com emoji/acento.
    const ntfyRes = await fetch(host, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        topic,
        title: '🎉 Novo cadastro no Stage!',
        message: body,
        priority: 4,
        tags: ['tada', 'iphone'],
      }),
    })

    if (!ntfyRes.ok) {
      console.error('[notify-signup] ntfy retornou', ntfyRes.status, await ntfyRes.text())
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('[notify-signup] erro:', err)
    // Retorna 200 mesmo em erro pra Supabase não retentar — notif é
    // best-effort, perder uma é melhor do que ficar em loop.
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }
}))
