// Edge Function: extract-profile
//
// Sucessor de parse-cv-pdf na arquitetura profile-first (Semana 1). Faz a
// extração estruturada do CV usando GPT-4o + Structured Outputs (PROFILE_JSON_SCHEMA
// em _shared/profile_schema.ts) e dual-write SÍNCRONO:
//   1. user_profiles.gamification_data.imported_resume.parsed (formato legacy)
//   2. 18 tabelas relacionais (via save-profile → save_profile_from_json RPC)
//
// Cache via parser_source === CURRENT_EXTRACTOR_VERSION. Pra invalidar quando
// prompt evoluir, bumpe a versão (extract-profile-v1.0 → v1.1, etc).
//
// Failure handling dev vs prod controlado por ENV var ENVIRONMENT:
//   - ENVIRONMENT=production → falha em save-profile loga + alarma PostHog +
//     retorna 200 (JSONB legacy preserva UX)
//   - default (dev/staging) → retorna 500 pra detectar bugs cedo
//
// Matriz de estados de falha documentada em docs/profile_architecture.md
// (Seção "Observabilidade") e implementada literalmente abaixo nos branches
// de erro.

import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration, captureEvent, withEdgeAnalytics } from '../_shared/posthog.ts'
import { PROFILE_JSON_SCHEMA, PROFILE_SYSTEM_PROMPT, toLegacyResume } from '../_shared/profile_schema.ts'
import { flatten } from '../_shared/cv_text.ts'
import { detectNonCvContent, nonCvMessage } from '../_shared/cv_content_validator.ts'
import { resolveImportedContactEmail } from '../_shared/contact_email.ts'

const CURRENT_EXTRACTOR_VERSION = 'extract-profile-v1.0'
const MODEL = 'gpt-4o'
const OPENAI_TIMEOUT_MS = 45000
const MAX_PDF_SIZE_BYTES = 10_000_000

// Risco 2 (decidido 2026-05-22): threshold de anti-invenção crítico relaxado
// de 3 → 4 pra reduzir falsos positivos em CVs com OCR ruim ou acentos
// quebrados. Monitorar via status='partial' em profile_extraction_logs;
// se >5% das extrações caem aqui, revisar.
const ANTI_INVENTION_CRITICAL_THRESHOLD = 4

// Risco 4 (decidido 2026-05-22): retry simples 1x em save-profile com
// 2s de delay. Se ambas tentativas falham, JSONB legacy permanece
// consistente e alarme via ntfy + PostHog dispara.
const SAVE_PROFILE_RETRY_DELAY_MS = 2000

// Risco 3 (decidido 2026-05-22): alarme via ntfy em save_profile_failed
// só em produção (em dev/staging o PostHog basta). Reusa NTFY_TOPIC_REPORT
// do daily-report (mesmo tópico do fundador).
const NTFY_HOST = Deno.env.get('NTFY_HOST') ?? 'https://ntfy.sh'
const NTFY_TOPIC_REPORT = Deno.env.get('NTFY_TOPIC_REPORT') ?? ''

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

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return Array.from(new Uint8Array(buf))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')
}

// Risco 3 — alarme ntfy quando save-profile falha em produção.
// Mesmo padrão JSON do daily-report (suporta unicode no título).
async function sendNtfyAlert(title: string, message: string): Promise<void> {
  if (!NTFY_TOPIC_REPORT) return
  try {
    await fetch(NTFY_HOST, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        topic: NTFY_TOPIC_REPORT,
        title,
        message,
        priority: 4, // > daily-report (3) pra destacar como incidente
        tags: ['warning', 'extract_profile'],
      }),
    })
  } catch (e) {
    console.error(`[extract-profile] ntfy failed: ${(e as Error).message}`)
  }
}

// ────────────────────────────────────────────────────────────────────────────
// OpenAI call
// ────────────────────────────────────────────────────────────────────────────

interface OpenAICallResult {
  content: string
  totalTokens: number
  inputTokens: number
  outputTokens: number
  latencyMs: number
}

async function callOpenAI(pdfBase64: string): Promise<OpenAICallResult> {
  const ctrl = new AbortController()
  const timeout = setTimeout(() => ctrl.abort(), OPENAI_TIMEOUT_MS)
  const start = Date.now()

  try {
    const resp = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      signal: ctrl.signal,
      headers: {
        'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MODEL,
        messages: [
          { role: 'system', content: PROFILE_SYSTEM_PROMPT },
          {
            role: 'user',
            content: [
              {
                type: 'file',
                file: {
                  filename: 'cv.pdf',
                  file_data: `data:application/pdf;base64,${pdfBase64}`,
                },
              },
              {
                type: 'text',
                text: 'EXTRAIA o currículo deste PDF em JSON estruturado seguindo o schema. Leia coluna por coluna. Mantenha fidelidade absoluta.',
              },
            ],
          },
        ],
        temperature: 0.0,
        max_tokens: 4000,
        response_format: { type: 'json_schema', json_schema: PROFILE_JSON_SCHEMA },
      }),
    })

    if (!resp.ok) {
      const errText = await resp.text()
      throw new Error(`OpenAI ${resp.status}: ${errText.slice(0, 400)}`)
    }
    const data = await resp.json()
    return {
      content: data.choices[0].message.content,
      totalTokens: data.usage?.total_tokens ?? 0,
      inputTokens: data.usage?.prompt_tokens ?? 0,
      outputTokens: data.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    }
  } finally {
    clearTimeout(timeout)
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Pós-processamento determinístico + anti-invenção
// ────────────────────────────────────────────────────────────────────────────

function postProcess(data: any): any {
  const personal = data.personal ?? {}
  if (typeof personal.email === 'string') {
    personal.email = personal.email.trim().toLowerCase()
  }
  // Tier 3.1 (2026-05-24): preservar formatação ORIGINAL do telefone como
  // veio do CV (ex: "+55 (11) 98216-4700"). Antes destruíamos com
  // `.replace(/\D/g, '')` — adapt v2 mostrava número feio no PDF adaptado.
  // Dígitos puros agora ficam em `phone_number_e164` (trigger DB) pra uso
  // por OneSignal/sync.
  if (typeof personal.phone_number === 'string') {
    personal.phone_number = personal.phone_number.trim()
  }
  data.personal = personal

  data.projects = (data.projects ?? []).map((p: any) => {
    if (p.website && typeof p.website === 'string' && !/^https?:\/\//i.test(p.website)) {
      p.website = 'https://' + p.website
    }
    return p
  })

  data.experiences = (data.experiences ?? []).map((exp: any) => {
    if (exp.end_date && exp.start_date && exp.end_date < exp.start_date) {
      exp.confidence = Math.min(typeof exp.confidence === 'number' ? exp.confidence : 1, 0.4)
    }
    return exp
  })

  if (Array.isArray(data.skills)) {
    const seen = new Set<string>()
    data.skills = data.skills.filter((s: any) => {
      if (!s?.name || typeof s.name !== 'string') return false
      const key = s.name.toLowerCase().trim()
      if (seen.has(key) || key.length === 0) return false
      seen.add(key)
      return true
    })
  }

  return data
}

interface AntiInventionResult {
  data: any
  lowConfidenceFields: string[]
  criticalFails: number
}

function antiInvention(data: any, rawText: string): AntiInventionResult {
  const lowConfidenceFields: string[] = []
  let criticalFails = 0

  if (!rawText || rawText.length === 0) {
    // Sem texto de referência, não podemos checar — retornamos como está.
    return { data, lowConfidenceFields, criticalFails }
  }

  const cvFlat = flatten(rawText)
  const isInCv = (value: string | null | undefined): boolean => {
    if (!value || value.trim().length === 0) return false
    const f = flatten(value)
    if (f.length === 0) return false
    if (f.length <= 2) return true
    return cvFlat.includes(f)
  }

  const personal = data.personal ?? {}
  const checks: Array<{ field: string; value: string | null | undefined; critical: boolean }> = [
    { field: 'personal.first_name+last_name', value: [personal.first_name, personal.last_name].filter(Boolean).join(' '), critical: true },
    { field: 'personal.email', value: personal.email, critical: true },
    { field: 'personal.phone_number', value: personal.phone_number, critical: false },
  ]

  // Primeiro título e primeira instituição
  const firstExp = (data.experiences ?? [])[0]
  if (firstExp?.title) {
    checks.push({ field: 'experiences[0].title', value: firstExp.title, critical: true })
  }
  if (firstExp?.company) {
    checks.push({ field: 'experiences[0].company', value: firstExp.company, critical: true })
  }
  const firstEdu = (data.education ?? [])[0]
  if (firstEdu?.institution) {
    checks.push({ field: 'education[0].institution', value: firstEdu.institution, critical: true })
  }

  for (const c of checks) {
    if (c.value && !isInCv(c.value)) {
      lowConfidenceFields.push(c.field)
      if (c.critical) criticalFails++
    }
  }

  // Rebaixa confidence dos itens cujo campo crítico falhou
  if (firstExp && (lowConfidenceFields.includes('experiences[0].title') ||
                   lowConfidenceFields.includes('experiences[0].company'))) {
    firstExp.confidence = Math.min(firstExp.confidence ?? 1, 0.4)
  }
  if (firstEdu && lowConfidenceFields.includes('education[0].institution')) {
    firstEdu.confidence = Math.min(firstEdu.confidence ?? 1, 0.4)
  }

  // Confidences explícitas baixas também contam
  ;(data.experiences ?? []).forEach((exp: any, i: number) => {
    if (typeof exp.confidence === 'number' && exp.confidence < 0.7) {
      const path = `experiences[${i}]`
      if (!lowConfidenceFields.includes(path)) lowConfidenceFields.push(path)
    }
  })
  ;(data.education ?? []).forEach((edu: any, i: number) => {
    if (typeof edu.confidence === 'number' && edu.confidence < 0.7) {
      const path = `education[${i}]`
      if (!lowConfidenceFields.includes(path)) lowConfidenceFields.push(path)
    }
  })

  return { data, lowConfidenceFields, criticalFails }
}

function computeConfidenceGlobal(data: any): number {
  const all: number[] = []
  for (const e of data.experiences ?? []) {
    if (typeof e.confidence === 'number') all.push(e.confidence)
  }
  for (const e of data.education ?? []) {
    if (typeof e.confidence === 'number') all.push(e.confidence)
  }
  if (all.length === 0) return 0.5
  return all.reduce((a, b) => a + b, 0) / all.length
}

function computeCompleteness(data: any): number {
  let score = 0
  const p = data.personal ?? {}
  if (p.first_name) score += 5
  if (p.last_name) score += 5
  if (p.email) score += 5
  if (p.phone_number) score += 5
  if (p.location_city) score += 5
  if (p.headline || p.summary) score += 5
  if ((data.experiences ?? []).length > 0) score += 15
  if ((data.experiences ?? []).length > 1) score += 15
  if ((data.education ?? []).length > 0) score += 20
  if ((data.skills ?? []).length >= 3) score += 10
  if ((data.languages ?? []).length > 0) score += 10
  return Math.min(score, 100)
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers de logging — implementa a matriz de observabilidade
// ────────────────────────────────────────────────────────────────────────────

interface LogExtractionParams {
  // deno-lint-ignore no-explicit-any
  supabaseAdmin: any
  userId: string
  aiGenerationLogId: string | null
  status: 'success' | 'partial' | 'failed'
  rawJsonOutput: any
  confidenceGlobal: number | null
  lowConfidenceFields: string[]
  rawTextInputHash: string | null
  errorMessage: string | null
}

async function logExtraction(p: LogExtractionParams) {
  const { error } = await p.supabaseAdmin.from('profile_extraction_logs').insert({
    user_id: p.userId,
    ai_generation_log_id: p.aiGenerationLogId,
    status: p.status,
    raw_json_output: p.rawJsonOutput,
    confidence_global: p.confidenceGlobal,
    low_confidence_fields: p.lowConfidenceFields.length > 0 ? p.lowConfidenceFields : null,
    raw_text_input_hash: p.rawTextInputHash,
    error_message: p.errorMessage,
  })
  if (error) {
    console.error(`[extract-profile] failed to write profile_extraction_logs: ${error.message}`)
  }
}

interface LogAIGenerationParams {
  // deno-lint-ignore no-explicit-any
  supabaseAdmin: any
  userId: string
  inputTokens: number
  outputTokens: number
}

async function logAIGeneration(p: LogAIGenerationParams): Promise<string | null> {
  // Schema real em prod: id, user_id, generation_type, tokens_used, created_at.
  // (Tabela criada antes do versionamento; sem CREATE TABLE no repo.)
  // model_used vai como property em $ai_generation (PostHog LLM Analytics).
  const totalTokens = p.inputTokens + p.outputTokens
  const { data, error } = await p.supabaseAdmin
    .from('ai_generation_logs')
    .insert({
      user_id: p.userId,
      generation_type: 'profile_extraction',
      tokens_used: totalTokens,
    })
    .select('id')
    .single()
  if (error) {
    console.error(`[extract-profile] failed to write ai_generation_logs: ${error.message}`)
    return null
  }
  return (data as { id: string }).id
}

// ────────────────────────────────────────────────────────────────────────────
// Main
// ────────────────────────────────────────────────────────────────────────────

serve(withEdgeAnalytics('extract-profile', async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const startTime = Date.now()
  const isProduction = Deno.env.get('ENVIRONMENT') === 'production'

  try {
    const body = await req.json().catch(() => ({}))
    const force: boolean = body?.force === true
    // DRY-RUN (widget de conflito de import): save:false PARSEIA e DEVOLVE o
    // profile_data SEM gravar (nem o JSONB legacy, nem a RPC relacional). Assim
    // o cliente vira dono do apply (aceita/rejeita/edita por campo) em vez de a
    // RPC preserve-mode decidir sozinha. Default true = comportamento de sempre.
    const save: boolean = body?.save !== false
    const pdfBase64: string = typeof body?.pdf_base64 === 'string' ? body.pdf_base64 : ''
    const rawTextFallback: string = typeof body?.raw_text_fallback === 'string'
      ? body.raw_text_fallback
      : ''

    if (pdfBase64.length === 0) {
      return jsonResponse({ error: 'pdf_base64 required' }, 400)
    }
    const approxBytes = (pdfBase64.length * 3) / 4
    if (approxBytes > MAX_PDF_SIZE_BYTES) {
      return jsonResponse({
        error: 'pdf_too_large',
        detail: `PDF com ${(approxBytes / 1_000_000).toFixed(1)}MB excede ${MAX_PDF_SIZE_BYTES / 1_000_000}MB`,
      }, 400)
    }

    // Non-CV detection (mesmo padrão de parse-cv-pdf)
    if (rawTextFallback.length >= 200) {
      const nonCv = detectNonCvContent(rawTextFallback)
      if (nonCv.isNonCv) {
        console.warn(
          `[extract-profile] non-CV content detected ` +
          `category=${nonCv.category} reasons=${nonCv.reasons.join(',')}`,
        )
        return jsonResponse({
          error: 'non_cv_content',
          category: nonCv.category,
          message: nonCvMessage(nonCv.category!),
          reasons: nonCv.reasons,
        }, 422)
      }
    }

    // Auth (service-role ou JWT)
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

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      serviceRoleKey,
    )

    // Cache check
    const profileR = await supabaseAdmin
      .from('user_profiles')
      .select('gamification_data')
      .eq('id', userId)
      .maybeSingle()

    if (profileR.error || !profileR.data) {
      return jsonResponse({ error: 'profile_not_found' }, 404)
    }

    const gd = (profileR.data.gamification_data as any) ?? {}
    const imported = gd?.imported_resume ?? {}

    if (imported?.parser_source === CURRENT_EXTRACTOR_VERSION && imported?.parsed && !force) {
      console.log(`[extract-profile] cache hit user=${userId} version=${CURRENT_EXTRACTOR_VERSION}`)
      return jsonResponse({
        parsed: imported.parsed,
        cached: true,
        extraction_meta: {
          confidence_global: imported.confidence_global ?? null,
          low_confidence_fields: imported.low_confidence_fields ?? [],
          status: 'success',
          extractor_version: CURRENT_EXTRACTOR_VERSION,
        },
      })
    }

    captureEvent({
      event: 'profile_extraction_attempted',
      distinctId: userId,
      properties: {
        raw_text_length: rawTextFallback.length,
        pdf_bytes: Math.round(approxBytes),
        extractor_version: CURRENT_EXTRACTOR_VERSION,
      },
    }).catch(() => {})

    const rawTextHash = rawTextFallback.length > 0 ? await sha256Hex(rawTextFallback) : null

    // ──────────────────────────────────────────────────────────────────────
    // CHAMADA OPENAI — linha 1 da matriz (network/timeout/non-2xx)
    // ──────────────────────────────────────────────────────────────────────
    let ai: OpenAICallResult
    try {
      ai = await callOpenAI(pdfBase64)
    } catch (err) {
      const errMsg = (err as Error).message || 'unknown'
      const isTimeout = errMsg.includes('AbortError') || errMsg.includes('aborted')
      console.error(`[extract-profile] OpenAI call failed user=${userId}: ${errMsg}`)

      trackAIGeneration({
        userId,
        generationType: 'profile_extraction',
        model: MODEL,
        inputTokens: 0,
        outputTokens: 0,
        latencyMs: Date.now() - startTime,
        isError: true,
        extra: { error_stage: 'openai', extractor_version: CURRENT_EXTRACTOR_VERSION },
      }).catch(() => {})

      await logExtraction({
        supabaseAdmin,
        userId,
        aiGenerationLogId: null,
        status: 'failed',
        rawJsonOutput: null,
        confidenceGlobal: null,
        lowConfidenceFields: [],
        rawTextInputHash: rawTextHash,
        errorMessage: errMsg.slice(0, 500),
      })

      captureEvent({
        event: 'profile_extraction_failed',
        distinctId: userId,
        properties: {
          error_stage: 'openai',
          error_reason: isTimeout ? 'timeout' : 'api_error',
          error_message: errMsg.slice(0, 200),
        },
      }).catch(() => {})

      return jsonResponse({ error: 'openai_failed', detail: errMsg.slice(0, 300) }, isTimeout ? 504 : 502)
    }

    // Log de LLM (sucesso na chamada — tem tokens válidos)
    const aiGenerationLogId = await logAIGeneration({
      supabaseAdmin,
      userId,
      inputTokens: ai.inputTokens,
      outputTokens: ai.outputTokens,
    })

    trackAIGeneration({
      userId,
      generationType: 'profile_extraction',
      model: MODEL,
      inputTokens: ai.inputTokens,
      outputTokens: ai.outputTokens,
      latencyMs: ai.latencyMs,
      cached: false,
      extra: { extractor_version: CURRENT_EXTRACTOR_VERSION },
    }).catch(() => {})

    // ──────────────────────────────────────────────────────────────────────
    // JSON PARSE — linha 2 da matriz (resposta válida mas JSON quebrado)
    // ──────────────────────────────────────────────────────────────────────
    let rawParsed: any
    try {
      rawParsed = JSON.parse(ai.content)
    } catch (_e) {
      const truncated = ai.content?.slice(0, 1000) ?? ''
      console.error(`[extract-profile] JSON parse failed user=${userId}: ${truncated}`)

      await logExtraction({
        supabaseAdmin,
        userId,
        aiGenerationLogId,
        status: 'failed',
        rawJsonOutput: { raw_content: truncated },
        confidenceGlobal: null,
        lowConfidenceFields: [],
        rawTextInputHash: rawTextHash,
        errorMessage: 'json_parse',
      })

      captureEvent({
        event: 'profile_extraction_failed',
        distinctId: userId,
        properties: { error_stage: 'json_parse', extractor_version: CURRENT_EXTRACTOR_VERSION },
      }).catch(() => {})

      return jsonResponse({ error: 'ai_response_invalid' }, 502)
    }

    // ──────────────────────────────────────────────────────────────────────
    // PÓS-PROCESSAMENTO + ANTI-INVENÇÃO — linha 3 da matriz
    // (>= 3 falhas críticas = status partial, retorna 422)
    // ──────────────────────────────────────────────────────────────────────
    let profileData = postProcess(rawParsed)
    const inv = antiInvention(profileData, rawTextFallback)
    profileData = inv.data

    // Anti-invenção: agora SOFT GATE (não bloqueia, só logra + alarma).
    // Calibração inicial (threshold=4) bloqueava ~40% dos CVs brasileiros reais
    // por causa de fragmentação do raw_text vinda do Syncfusion (acentos quebrados,
    // multi-coluna, phone com formatação). Decisão Semana 1: registrar mas seguir.
    // Telas da Semana 2 usam `low_confidence_fields` pra destacar campos suspeitos
    // pro usuário revisar.
    const antiInventionFlag = inv.criticalFails >= ANTI_INVENTION_CRITICAL_THRESHOLD
    if (antiInventionFlag) {
      console.warn(`[extract-profile] anti-invention critical (${inv.criticalFails} fails) user=${userId} — proceeding anyway (soft gate)`)
      captureEvent({
        event: 'profile_extraction_anti_invention_warning',
        distinctId: userId,
        properties: {
          critical_fails: inv.criticalFails,
          low_confidence_fields: inv.lowConfidenceFields,
          extractor_version: CURRENT_EXTRACTOR_VERSION,
        },
      }).catch(() => {})
    }

    // Preserva contato profissional manual. O e-mail extraído só preenche
    // perfil vazio/relay e nunca introduz um identificador privado de login.
    // Em erro de leitura, omite o importado e deixa o COALESCE do RPC preservar.
    if (save) {
      profileData.personal = profileData.personal ?? {}
      const existingContactR = await supabaseAdmin
        .from('profile_personal')
        .select('email')
        .eq('user_id', userId)
        .maybeSingle()
      if (existingContactR.error) {
        console.warn(`[extract-profile] existing contact lookup failed user=${userId}: ${existingContactR.error.message}`)
        delete profileData.personal.email
      } else {
        const resolvedEmail = resolveImportedContactEmail(
          existingContactR.data?.email,
          profileData.personal.email,
        )
        if (resolvedEmail) profileData.personal.email = resolvedEmail
        else delete profileData.personal.email
      }
    }

    // Cálculos finais
    const confidenceGlobal = computeConfidenceGlobal(profileData)
    const completeness = computeCompleteness(profileData)
    profileData.personal = profileData.personal ?? {}
    profileData.personal.completeness_score = completeness
    profileData.personal.profile_source = 'imported'

    // ──────────────────────────────────────────────────────────────────────
    // PERSISTÊNCIA JSONB LEGACY (sempre acontece)
    // ──────────────────────────────────────────────────────────────────────
    const legacyResume = toLegacyResume(profileData)

    const updatedImported = {
      ...imported,
      parsed: legacyResume,
      parsed_at: new Date().toISOString(),
      parser_version: CURRENT_EXTRACTOR_VERSION,
      parser_model: MODEL,
      parser_source: CURRENT_EXTRACTOR_VERSION,
      parsed_warnings: inv.lowConfidenceFields,
      confidence_global: confidenceGlobal,
      low_confidence_fields: inv.lowConfidenceFields,
      ...(isServiceRole ? { parsed_backfilled_at: new Date().toISOString() } : {}),
    }
    const updatedGd = { ...gd, imported_resume: updatedImported }

    // DRY-RUN: pula TODA a persistência (JSONB + relacional). Só parseia e devolve.
    if (save) {
      const updateR = await supabaseAdmin
        .from('user_profiles')
        .update({ gamification_data: updatedGd })
        .eq('id', userId)

      if (updateR.error) {
        console.error(`[extract-profile] persist JSONB failed user=${userId}: ${updateR.error.message}`)
        // Não logamos em profile_extraction_logs como sucesso aqui — falha
        // em persistir o JSONB é falha terminal mesmo, e a transação nas
        // tabelas relacionais também não rodou.
        await logExtraction({
          supabaseAdmin,
          userId,
          aiGenerationLogId,
          status: 'failed',
          rawJsonOutput: profileData,
          confidenceGlobal,
          lowConfidenceFields: inv.lowConfidenceFields,
          rawTextInputHash: rawTextHash,
          errorMessage: `jsonb_persist_failed: ${updateR.error.message}`,
        })
        return jsonResponse({ error: 'persist_failed', detail: updateR.error.message }, 500)
      }
    }

    // ──────────────────────────────────────────────────────────────────────
    // CHAMA SAVE-PROFILE — linha 4 da matriz (JSONB ok, mas relacional pode falhar)
    // Risco 4: retry simples 1x com 2s delay. Se ambas falham, mantém o
    //   comportamento da matriz (alarme via ntfy + PostHog, JSONB consistente).
    // Risco 3: alarme ntfy em produção quando ambas tentativas falham.
    // Dev: retorna 500 / Prod: loga e retorna 200
    // ──────────────────────────────────────────────────────────────────────
    let saveProfileStatus: 'success' | 'failed' | 'skipped' = save ? 'success' : 'skipped'
    let saveErrorMessage: string | null = null
    let saveAttempts = 0

    // Chama save_profile_from_json direto via RPC. Razão: o gateway do
    // Supabase tem verify_jwt=true por default em edge functions novas,
    // rejeitando o service_role JWT no formato gateway-to-gateway (erro
    // UNAUTHORIZED_INVALID_JWT_FORMAT). RPC direto via supabaseAdmin
    // (service_role client) bypassa o gateway e chama o Postgres
    // diretamente. A função save_profile_from_json é SECURITY DEFINER +
    // GRANT TO service_role, então tem permissão correta.
    //
    // O wrapper edge function save-profile foi deletado em 2026-05-27 —
    // ficou órfão (zero invocações em 14d). Se precisar rollback, restaurar
    // via git history.
    // DRY-RUN (save:false): pula a RPC — o cliente aplica o merge seletivo.
    if (save) {
      for (let attempt = 1; attempt <= 2; attempt++) {
        saveAttempts = attempt
        try {
          const { error: rpcError } = await supabaseAdmin.rpc('save_profile_from_json', {
            p_user_id: userId,
            p_data: profileData,
          })
          if (!rpcError) {
            saveProfileStatus = 'success'
            saveErrorMessage = null
            break
          }
          saveProfileStatus = 'failed'
          saveErrorMessage = `rpc: ${rpcError.message || 'unknown'}`
          console.error(`[extract-profile] save_profile_from_json attempt ${attempt} failed user=${userId}: ${saveErrorMessage}`)
        } catch (e) {
          saveProfileStatus = 'failed'
          saveErrorMessage = `rpc_exception: ${(e as Error).message}`
          console.error(`[extract-profile] save_profile_from_json attempt ${attempt} exception user=${userId}: ${saveErrorMessage}`)
        }
        if (attempt < 2) {
          await new Promise(r => setTimeout(r, SAVE_PROFILE_RETRY_DELAY_MS))
        }
      }
    }

    if (saveProfileStatus === 'failed') {
      captureEvent({
        event: 'save_profile_failed',
        distinctId: userId,
        properties: {
          error: saveErrorMessage,
          attempts: saveAttempts,
          extractor_version: CURRENT_EXTRACTOR_VERSION,
          environment: isProduction ? 'production' : 'dev',
        },
      }).catch(() => {})

      if (isProduction) {
        // Risco 3 — alarme ntfy só em prod. Fire-and-forget pra não bloquear response.
        sendNtfyAlert(
          'Stage: save-profile falhou (relacional out-of-sync)',
          `user_id: ${userId}\nversion: ${CURRENT_EXTRACTOR_VERSION}\nerror: ${saveErrorMessage}\n\n` +
          `JSONB legacy ESTÁ consistente; 18 tabelas relacionais ficaram stale ` +
          `pra este usuário. Investigar profile_extraction_logs.`,
        ).catch(() => {})
      }
    }

    // ──────────────────────────────────────────────────────────────────────
    // LOG FINAL — sucesso (mesmo quando save-profile falha em prod, o
    // status é 'success' porque JSONB foi gravado; o save_profile_failed
    // já foi capturado via captureEvent acima).
    // ──────────────────────────────────────────────────────────────────────
    // Quando save-profile falha mas JSONB legacy foi gravado, marcamos como
    // 'partial' (não 'success'). Observabilidade fica clara: status='partial'
    // = "metade do dual-write foi". Investigação via error_message.
    await logExtraction({
      supabaseAdmin,
      userId,
      aiGenerationLogId,
      // 'partial' SÓ quando a RPC FALHOU. Dry-run (save:false) tem status
      // 'skipped' e NÃO é 'partial' — senão todo preview de conflito inflaria o
      // monitor de partial-rate (alarme >5%) com falso positivo.
      status: saveProfileStatus === 'failed' ? 'partial' : 'success',
      rawJsonOutput: profileData,
      confidenceGlobal,
      lowConfidenceFields: inv.lowConfidenceFields,
      rawTextInputHash: rawTextHash,
      errorMessage: saveErrorMessage,
    })

    captureEvent({
      event: 'profile_extraction_completed',
      distinctId: userId,
      properties: {
        confidence_global: confidenceGlobal,
        low_confidence_count: inv.lowConfidenceFields.length,
        anti_invention_flag: antiInventionFlag,
        anti_invention_critical_fails: inv.criticalFails,
        experiences_count: (profileData.experiences ?? []).length,
        education_count: (profileData.education ?? []).length,
        skills_count: (profileData.skills ?? []).length,
        completeness_score: completeness,
        duration_ms: Date.now() - startTime,
        save_profile_status: saveProfileStatus,
        save_attempts: saveAttempts,
        extractor_version: CURRENT_EXTRACTOR_VERSION,
      },
    }).catch(() => {})

    // Dev: se save-profile falhou (mesmo após retry), retorna 500 pra detectar bugs cedo
    if (saveProfileStatus === 'failed' && !isProduction) {
      return jsonResponse({
        error: 'save-profile failed after retry (dev mode)',
        detail: saveErrorMessage,
        attempts: saveAttempts,
        parsed: legacyResume,
        profile_data: profileData,
      }, 500)
    }

    console.log(`[extract-profile] SUCCESS user=${userId} save=${saveProfileStatus} confidence=${confidenceGlobal.toFixed(2)}`)

    return jsonResponse({
      parsed: legacyResume,
      profile_data: profileData,
      extraction_meta: {
        confidence_global: confidenceGlobal,
        low_confidence_fields: inv.lowConfidenceFields,
        status: 'success',
        save_profile_status: saveProfileStatus,
        extractor_version: CURRENT_EXTRACTOR_VERSION,
      },
      cached: false,
    })
  } catch (err) {
    const msg = (err as Error).message || 'unknown'
    console.error('[extract-profile] internal error:', msg)
    return jsonResponse({ error: 'internal', detail: msg.slice(0, 300) }, 500)
  }
}))
