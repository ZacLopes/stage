// Edge Function: notify-auto-apply-swipe
//
// Dispara uma notificação ntfy quando um usuário dá swipe right em uma vaga
// com candidatura por email, que no app é apresentada como aplicação
// automática/assistida por IA.
//
// Env vars:
// - NTFY_TOPIC_AUTO_APPLY: tópico específico para esses alertas
// - NTFY_TOPIC_REPORT ou NTFY_TOPIC: fallbacks, se o tópico específico não existir
// - NTFY_HOST: opcional, default "https://ntfy.sh"

import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { withEdgeAnalytics } from '../_shared/posthog.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function clean(value: unknown, fallback = ''): string {
  const s = (value ?? '').toString().trim()
  return s.length === 0 ? fallback : s
}

serve(withEdgeAnalytics('notify-auto-apply-swipe', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405)

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const supabaseAuth = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    )

    const { data: { user }, error: authError } = await supabaseAuth.auth.getUser()
    if (authError || !user) return jsonResponse({ error: 'unauthorized' }, 401)

    const body = await req.json().catch(() => ({}))
    const jobId = body?.job_id
    if (!jobId || typeof jobId !== 'string') {
      return jsonResponse({ error: 'job_id_required' }, 400)
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const { data: job, error: jobError } = await supabaseAdmin
      .from('jobs')
      .select('id, title, application_method, application_email, application_subject, companies(name)')
      .eq('id', jobId)
      .maybeSingle()

    if (jobError) return jsonResponse({ error: 'job_lookup_failed', message: jobError.message }, 500)
    if (!job) return jsonResponse({ error: 'job_not_found' }, 404)

    if (job.application_method !== 'email') {
      return jsonResponse({ ok: true, skipped: 'not_email_application' })
    }

    const [{ data: personal }, { data: legacy }] = await Promise.all([
      supabaseAdmin
        .from('profile_personal')
        .select('first_name, last_name, email, phone_country_code, phone_number')
        .eq('user_id', user.id)
        .maybeSingle(),
      supabaseAdmin
        .from('user_profiles')
        .select('name, email, phone')
        .eq('id', user.id)
        .maybeSingle(),
    ])

    const firstName = clean(personal?.first_name)
    const lastName = clean(personal?.last_name)
    const candidateName = clean(
      [firstName, lastName].filter(Boolean).join(' '),
      clean(legacy?.name, 'Usuário sem nome'),
    )
    const candidateEmail = clean(personal?.email, clean(legacy?.email, clean(user.email, 'email não informado')))
    const candidatePhone = clean(
      [personal?.phone_country_code, personal?.phone_number].filter(Boolean).join(' '),
      clean(legacy?.phone),
    )

    const companies = job.companies as { name?: string } | Array<{ name?: string }> | null
    const company = clean(Array.isArray(companies) ? companies[0]?.name : companies?.name, 'Empresa não informada')
    const applicationEmail = clean(job.application_email, 'email da vaga não informado')
    const applicationSubject = clean(job.application_subject)

    const topic = Deno.env.get('NTFY_TOPIC_AUTO_APPLY') ||
      Deno.env.get('NTFY_TOPIC_REPORT') ||
      Deno.env.get('NTFY_TOPIC') ||
      ''
    const host = Deno.env.get('NTFY_HOST') ?? 'https://ntfy.sh'

    if (!topic) {
      console.error('[notify-auto-apply-swipe] nenhum tópico ntfy configurado')
      return jsonResponse({ ok: false, reason: 'no_ntfy_topic' })
    }

    const message = [
      `${candidateName} deu swipe em aplicação por IA`,
      `${clean(job.title, 'Vaga sem título')} · ${company}`,
      `Enviar para: ${applicationEmail}`,
      applicationSubject ? `Assunto: ${applicationSubject}` : '',
      `Candidato: ${candidateEmail}`,
      candidatePhone ? `Telefone: ${candidatePhone}` : '',
      `Job ID: ${job.id}`,
      `User ID: ${user.id}`,
    ].filter(Boolean).join('\n')

    const ntfyRes = await fetch(host, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        topic,
        title: 'Nova aplicação por IA autorizada',
        message,
        priority: 4,
        tags: ['briefcase', 'robot'],
      }),
    })

    if (!ntfyRes.ok) {
      const detail = await ntfyRes.text().catch(() => '')
      console.error('[notify-auto-apply-swipe] ntfy retornou', ntfyRes.status, detail)
      return jsonResponse({ ok: false, ntfy_status: ntfyRes.status }, 502)
    }

    return jsonResponse({ ok: true })
  } catch (e) {
    console.error('[notify-auto-apply-swipe] erro:', e)
    return jsonResponse({ error: 'internal', message: String(e).slice(0, 300) }, 500)
  }
}))
