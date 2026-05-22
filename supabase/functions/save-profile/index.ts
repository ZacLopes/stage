// Edge Function: save-profile
//
// Persiste o JSON estruturado (saída do extract-profile, conforme PROFILE_JSON_SCHEMA)
// nas 18 tabelas relacionais via RPC pra função SQL save_profile_from_json
// (migration 20260522000011). Toda a persistência ocorre numa transaction
// dentro do Postgres.
//
// Auth: aceita service-role (chamada interna do extract-profile) ou JWT
// de usuário. Em service-role, exige user_id no body.
//
// Não emite telemetria adicional — extract-profile já registra
// profile_extraction_completed/save_profile_failed.

import { serve } from 'std/http/server'
import { createClient } from 'supabase'

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

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await req.json().catch(() => ({}))
    const profileData = body?.profile_data
    if (!profileData || typeof profileData !== 'object') {
      return jsonResponse({ error: 'profile_data required (object)' }, 400)
    }

    // Auth: detecta service-role (Bearer legacy JWT, sb_secret_, ou X-Service-Role-Key)
    // ou JWT de user. Mesma estratégia das demais edge functions (ex.: parse-cv-pdf).
    const authHeader = req.headers.get('Authorization') ?? ''
    const customServiceKeyHeader = req.headers.get('X-Service-Role-Key') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    const authMatches = serviceRoleKey.length > 0 &&
      authHeader === `Bearer ${serviceRoleKey}`
    const customMatches = serviceRoleKey.length > 0 &&
      customServiceKeyHeader === serviceRoleKey

    let jwtIsServiceRole = false
    if (authHeader.startsWith('Bearer ey')) {
      try {
        const token = authHeader.slice('Bearer '.length)
        const payloadB64 = token.split('.')[1] ?? ''
        const normalized = payloadB64.replace(/-/g, '+').replace(/_/g, '/')
        const padded = normalized + '='.repeat((4 - normalized.length % 4) % 4)
        const payload = JSON.parse(atob(padded)) as {
          ref?: string
          role?: string
          exp?: number
        }
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
        const expectedRef = supabaseUrl.match(/https:\/\/([^.]+)\./)?.[1] ?? ''
        const nowSec = Math.floor(Date.now() / 1000)
        jwtIsServiceRole = payload.role === 'service_role' &&
          (payload.ref === expectedRef || expectedRef.length === 0) &&
          (payload.exp == null || payload.exp > nowSec)
      } catch (_e) {
        jwtIsServiceRole = false
      }
    }

    const isServiceRole = authMatches || customMatches || jwtIsServiceRole

    let userId: string
    if (isServiceRole) {
      const bodyUserId = typeof body?.user_id === 'string' ? body.user_id.trim() : ''
      if (bodyUserId.length === 0) {
        return jsonResponse({ error: 'user_id required for service-role calls' }, 400)
      }
      userId = bodyUserId
    } else {
      const userClient = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_ANON_KEY') ?? '',
        { global: { headers: { Authorization: authHeader } } },
      )
      const { data: { user }, error: authError } = await userClient.auth.getUser()
      if (authError || !user) return jsonResponse({ error: 'Unauthorized' }, 401)
      userId = user.id
    }

    // RPC com service_role (a função save_profile_from_json é SECURITY DEFINER
    // e tem GRANT só pra service_role).
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      serviceRoleKey,
    )

    const { data, error } = await supabaseAdmin.rpc('save_profile_from_json', {
      p_user_id: userId,
      p_data: profileData,
    })

    if (error) {
      console.error(`[save-profile] rpc failed user=${userId}: ${error.message}`)
      return jsonResponse({ error: 'rpc_failed', detail: error.message }, 500)
    }

    console.log(`[save-profile] SUCCESS user=${userId}`)
    return jsonResponse({ status: 'success', result: data })
  } catch (err) {
    const msg = (err as Error).message || 'unknown'
    console.error('save-profile error:', msg)
    return jsonResponse({ error: 'internal', detail: msg.slice(0, 300) }, 500)
  }
})
