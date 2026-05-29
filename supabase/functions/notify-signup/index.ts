import { serve } from 'std/http/server'
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
    const name = (record.name ?? 'Usuário sem nome').toString().trim()
    const email = (record.email ?? 'email não informado').toString().trim()
    const course = (record.course ?? '').toString().trim()
    const semester = (record.semester ?? '').toString().trim()

    // Monta a mensagem em formato amigável
    const extra = [course, semester].filter(Boolean).join(' · ')
    const body = extra ? `${name}\n${email}\n${extra}` : `${name}\n${email}`

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
