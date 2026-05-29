// Edge Function: parse-cv-pdf
//
// ⚠️ DEPRECATED (2026-05-22) — substituída por extract-profile na arquitetura
// profile-first (Semana 1). Esta função permanece no repo APENAS pra rollback
// rápido caso extract-profile precise ser revertida. Não chamar daqui em
// diante: o cliente Flutter (cv_import_service.dart) agora invoca extract-profile,
// que gera tanto o JSONB legacy (compatível com adapt-resume-to-job e
// generate-resume) quanto popula as 18 tabelas relacionais.
//
// Estrutura CV em JSON usando GPT-4o com suporte NATIVO a PDF (sem
// rasterização client-side). Substitui parse-cv-vision pra resolver:
//   1. parse-cv-vision rodava em 0.4-1.1% dos uploads — o gargalo era a
//      rasterização via Printing.raster no Flutter (falha silenciosa em
//      alguns devices iOS).
//   2. Permite backfill retroativo: edge function baixa PDF do Storage e
//      processa, sem depender de cliente rasterizar.
//
// Diferenças vs parse-cv-vision:
//   - Recebe `pdf_base64` em vez de `images_base64`
//   - Não tem limite de páginas a priori (PDF é muito mais compacto que
//     imagens 150 DPI)
//   - GPT-4o cobra ~32 tokens/página + alguns tokens das renders internas,
//     que dá ~250 tokens input pra um CV de 2 páginas vs ~2300 tokens em
//     imagens detail=high. ≈10x mais barato.
//
// Input:  { pdf_base64: string, raw_text_fallback?: string, user_id?: string, force?: bool }
// Output: { parsed: {resume}, cached: bool, fields_filled: int, source: 'pdf', warnings: [] }

import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration, withEdgeAnalytics } from '../_shared/posthog.ts'
import { PARSE_CV_JSON_SCHEMA } from '../_shared/cv_schema.ts'
import { flatten } from '../_shared/cv_text.ts'
import { detectNonCvContent, nonCvMessage } from '../_shared/cv_content_validator.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MODEL = 'gpt-4o'
const PARSER_VERSION = 'v1-pdf'
const OPENAI_TIMEOUT_MS = 45000
const MAX_PDF_SIZE_BYTES = 10_000_000 // 10MB após base64 decode (limite generoso)

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

const SYSTEM_PROMPT = `Você é um extrator de currículos. Recebe um PDF de um currículo e extrai estrutura JSON.

PRINCÍPIOS DE LEITURA:
1. Currículos brasileiros frequentemente usam DUAS COLUNAS. Leia COLUNA POR COLUNA, de cima para baixo, ESQUERDA antes da DIREITA.
2. Cabeçalho (nome + contatos) é sempre lido primeiro, mesmo que esteja centralizado.
3. Headers de seção (EXPERIÊNCIA, FORMAÇÃO, HABILIDADES) marcam o início de uma seção; o conteúdo abaixo pertence à seção até o próximo header.
4. Bullet points são caracteres • - * — preserve cada bullet como linha separada na "description" (separadas por \\n).
5. Datas e localizações geralmente ficam à DIREITA no mesmo bloco da empresa/instituição. NÃO confunda com seção separada.

REGRAS INVIOLÁVEIS:
1. EXTRAIA — não adapte, não reescreva, não corrija ortografia.
2. NÃO invente. Se um campo não está no CV, retorne string vazia.
3. Preserve nomes próprios EXATAMENTE como aparecem.
4. Para experiência: extraia TODAS as posições visíveis. Bullets preserve um por linha.
5. Para educação: extraia TODAS as formações. GPA/honras/coursework vão em "details".
6. Skills: extraia da seção "Habilidades"/"Skills"/"Competências". Só nomes/tools, não frases longas.
7. Certifications: extraia cursos+certificações de seções "CERTIFICAÇÕES", "CURSOS", "CURSOS E CERTIFICAÇÕES", "CERTIFICATIONS", "COURSES". Cada item é uma string auto-contida formatada como "Nome - Instituição - Ano" (omita partes ausentes). NÃO repita o que já está em achievements.
8. Language: detecte "pt" (português) ou "en" (inglês). Default "pt".

OUTPUT: { resume: {...} } seguindo o schema. Strict — nada além dos campos do schema.`

const USER_PROMPT = `EXTRAIA o currículo deste PDF em JSON estruturado seguindo o schema. Leia coluna por coluna. Mantenha fidelidade absoluta.`

async function callOpenAIPdf(pdfBase64: string): Promise<{
  content: string
  totalTokens: number
  inputTokens: number
  outputTokens: number
  latencyMs: number
}> {
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
          { role: 'system', content: SYSTEM_PROMPT },
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
              { type: 'text', text: USER_PROMPT },
            ],
          },
        ],
        temperature: 0.0,
        max_tokens: 3000,
        response_format: { type: 'json_schema', json_schema: PARSE_CV_JSON_SCHEMA },
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

// Validação anti-invenção — leniente como parse-cv-vision (PDF lê melhor
// que Syncfusion text extractor em colunas, então alguns campos podem
// não bater no raw_text_fallback). Strings que não aparecem ficam com
// warning, mas não são descartadas.
function validateAgainstFallback(parsed: any, rawTextFallback: string): {
  parsed: any
  fieldsFilled: number
  warnings: string[]
} {
  const cvFlat = flatten(rawTextFallback)
  const warnings: string[] = []
  const r = parsed?.resume ?? {}
  let fieldsFilled = 0

  function isInCv(value: string): boolean {
    if (!value || value.trim().length === 0) return false
    const flat = flatten(value)
    if (flat.length === 0) return false
    if (flat.length <= 2) return true
    return cvFlat.includes(flat)
  }

  for (const f of ['fullName', 'email', 'phone', 'linkedin', 'location']) {
    const v = String(r[f] ?? '').trim()
    if (v) {
      if (cvFlat && !isInCv(v)) {
        warnings.push(`${f} not in raw_text (kept anyway): "${v.slice(0, 30)}"`)
      }
      fieldsFilled++
    }
  }

  if (String(r.summary ?? '').trim().length > 30) fieldsFilled++

  for (const f of ['skills', 'experiences', 'education', 'achievements', 'interests']) {
    if (Array.isArray(r[f]) && r[f].length > 0) fieldsFilled++
  }

  r.language = ['pt', 'en'].includes(r.language) ? r.language : 'pt'

  return { parsed: { resume: r }, fieldsFilled, warnings }
}

serve(withEdgeAnalytics('parse-cv-pdf', async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await req.json().catch(() => ({}))
    const force: boolean = body?.force === true
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

    // Anti-non-CV: valida raw_text_fallback se vier (mesma defesa que parse-cv).
    if (rawTextFallback.length >= 200) {
      const nonCv = detectNonCvContent(rawTextFallback)
      if (nonCv.isNonCv) {
        console.warn(
          `[parse-cv-pdf] non-CV content detected ` +
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

    // Auth: aceita service-role (legacy JWT eyJ... OU modern sb_secret_)
    // ou JWT de usuário. Mesma estratégia das outras parse-cv functions.
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
      const supabaseClient = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_ANON_KEY') ?? '',
        { global: { headers: { Authorization: authHeader } } },
      )
      const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
      if (authError || !user) return jsonResponse({ error: 'Unauthorized' }, 401)
      userId = user.id
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      serviceRoleKey,
    )
    const profileR = await supabaseAdmin
      .from('user_profiles')
      .select('gamification_data')
      .eq('id', userId)
      .maybeSingle()

    if (profileR.error || !profileR.data) {
      return jsonResponse({ error: 'profile_not_found' }, 404)
    }

    const gd = profileR.data.gamification_data ?? {}
    const imported = gd?.imported_resume ?? {}

    // Cache hit: já tem parsed via pdf e não foi pedido force.
    const existingParser = imported?.parser_source
    if (existingParser === 'pdf' && imported?.parsed && !force) {
      console.log(`[parse-cv-pdf] cache hit user=${userId}`)
      return jsonResponse({
        parsed: imported.parsed,
        cached: true,
        fields_filled: 0,
        source: 'pdf',
      })
    }

    console.log(`[parse-cv-pdf] calling ${MODEL} user=${userId} pdfBytes=${approxBytes.toFixed(0)}`)
    const ai = await callOpenAIPdf(pdfBase64)
    console.log(`[parse-cv-pdf] ${MODEL} responded tokens=${ai.totalTokens} latency=${ai.latencyMs}ms`)

    trackAIGeneration({
      userId,
      generationType: 'cv_parsing_pdf',
      model: MODEL,
      inputTokens: ai.inputTokens,
      outputTokens: ai.outputTokens,
      latencyMs: ai.latencyMs,
      cached: false,
    }).catch(() => {})

    let rawParsed: any
    try {
      rawParsed = JSON.parse(ai.content)
    } catch (_e) {
      console.error(`[parse-cv-pdf] JSON parse failed for user=${userId}: ${ai.content.slice(0, 300)}`)
      return jsonResponse({ error: 'ai_response_invalid' }, 502)
    }

    const { parsed, fieldsFilled, warnings } = validateAgainstFallback(rawParsed, rawTextFallback)
    if (warnings.length > 0) {
      console.warn(`[parse-cv-pdf] validation warnings for user=${userId}: ${warnings.join('; ')}`)
    }

    // PDF tem precedência sobre vision e text-only (mais fiel ao layout).
    const updatedImported = {
      ...imported,
      parsed: parsed.resume,
      parsed_at: new Date().toISOString(),
      parser_version: PARSER_VERSION,
      parser_model: MODEL,
      parser_source: 'pdf',
      parsed_warnings: warnings,
      ...(isServiceRole ? { parsed_backfilled_at: new Date().toISOString() } : {}),
    }
    const updatedGd = { ...gd, imported_resume: updatedImported }

    const updateR = await supabaseAdmin
      .from('user_profiles')
      .update({ gamification_data: updatedGd })
      .eq('id', userId)

    if (updateR.error) {
      console.error(`[parse-cv-pdf] persist failed user=${userId}: ${updateR.error.message}`)
      return jsonResponse({ error: 'persist_failed', detail: updateR.error.message }, 500)
    }

    console.log(`[parse-cv-pdf] SUCCESS user=${userId} fieldsFilled=${fieldsFilled}`)
    return jsonResponse({
      parsed: parsed.resume,
      cached: false,
      fields_filled: fieldsFilled,
      source: 'pdf',
      warnings,
    })
  } catch (err) {
    const msg = (err as Error).message || 'unknown'
    console.error('parse-cv-pdf error:', msg)
    const status = msg.includes('AbortError') || msg.includes('aborted') ? 504 : 500
    return jsonResponse({ error: 'internal', detail: msg.slice(0, 300) }, status)
  }
}))
