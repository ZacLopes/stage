// Edge Function: parse-cv-vision
//
// Estrutura CV em JSON usando GPT-4o Vision sobre páginas rasterizadas
// do PDF original. Criada na F3 da reformulação — resolve PDFs em
// coluna onde o text extractor do Syncfusion embaralha o conteúdo
// (caso real do Zac: experiences=0 detectadas num CV com 3 experiências
// em layout de 2 colunas).
//
// Fluxo:
// 1. Cliente rasteriza PDF em PNG/JPEG (1-3 páginas) via Printing.raster
//    no Flutter.
// 2. Envia imagens base64 + raw_text_fallback (texto Syncfusion bruto).
// 3. Aqui: chama gpt-4o Vision com as imagens + system prompt focado em
//    leitura de layout (coluna por coluna, header → seções → contatos).
// 4. Valida cada nome próprio extraído contra substring no raw_text
//    (mesma defesa anti-invenção do parse-cv text-only).
// 5. Persiste em imported_resume.parsed com parser_source='vision'.
//
// Custo: ~$0.005-0.01 por parse (gpt-4o full + imagens). Para ~100
// imports/mês = ~$1/mês.
//
// Input:  { images_base64: string[], raw_text_fallback?: string, user_id?: string, force?: bool }
// Output: { parsed: {resume}, cached: bool, fields_filled: int, source: 'vision' }

import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration } from '../_shared/posthog.ts'
import { PARSE_CV_JSON_SCHEMA } from '../_shared/cv_schema.ts'
import { flatten } from '../_shared/cv_text.ts'
import { detectNonCvContent, nonCvMessage } from '../_shared/cv_content_validator.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MODEL = 'gpt-4o'
const PARSER_VERSION = 'v1-vision'
const OPENAI_TIMEOUT_MS = 45000
const MAX_PAGES = 3
const MAX_IMAGE_SIZE_BYTES = 1_500_000 // 1.5MB por imagem após base64 decode

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

const SYSTEM_PROMPT = `Você é um extrator de currículos com VISÃO COMPUTACIONAL. Recebe IMAGENS de um currículo em PDF e extrai estrutura JSON.

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

const USER_PROMPT = `EXTRAIA o currículo das imagens acima em JSON estruturado seguindo o schema. Leia coluna por coluna. Mantenha fidelidade absoluta.`

async function callOpenAIVision(imagesBase64: string[]): Promise<{
  content: string
  totalTokens: number
  inputTokens: number
  outputTokens: number
  latencyMs: number
}> {
  const ctrl = new AbortController()
  const timeout = setTimeout(() => ctrl.abort(), OPENAI_TIMEOUT_MS)
  const start = Date.now()

  const contentArray: Array<{
    type: 'text' | 'image_url'
    text?: string
    image_url?: { url: string; detail?: string }
  }> = [{ type: 'text', text: USER_PROMPT }]

  for (const img of imagesBase64) {
    // MIME detectado por header do base64. PNG padrão (Printing.raster
    // do Flutter), JPEG aceito se cliente quiser comprimir.
    const mime = img.startsWith('iVBORw0KG') ? 'image/png' : 'image/jpeg'
    contentArray.push({
      type: 'image_url',
      image_url: {
        // GPT-4o aceita data URL com base64. detail=high pra resolução
        // máxima — CVs têm texto pequeno; auto/low embaralham.
        url: `data:${mime};base64,${img}`,
        detail: 'high',
      },
    })
  }

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
          { role: 'user', content: contentArray },
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

// ────────────────────────────────────────────────────────────────────────────
// Validação anti-invenção — mesma estratégia do parse-cv text-only, mas
// compara contra raw_text_fallback (do Syncfusion). Vision pode ler MELHOR
// que Syncfusion em colunas, então alguns campos podem não bater. Nesses
// casos deixamos passar com warning — Vision é a fonte de maior fidelidade
// pra layout.
// ────────────────────────────────────────────────────────────────────────────

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

  // Campos string — em vision é leniente: se NÃO aparece no raw_text,
  // só warning + manter (Vision pode ler melhor que Syncfusion).
  for (const f of ['fullName', 'email', 'phone', 'linkedin', 'location']) {
    const v = String(r[f] ?? '').trim()
    if (v) {
      if (cvFlat && !isInCv(v)) {
        warnings.push(`${f} not in raw_text (kept anyway): "${v.slice(0, 30)}"`)
      }
      fieldsFilled++
    }
  }

  // Summary leniente (texto livre — vision reescreve naturalmente).
  if (String(r.summary ?? '').trim().length > 30) fieldsFilled++

  // Skills, experiences, education: só conta se tem dado.
  for (const f of ['skills', 'experiences', 'education', 'achievements', 'interests']) {
    if (Array.isArray(r[f]) && r[f].length > 0) fieldsFilled++
  }

  r.language = ['pt', 'en'].includes(r.language) ? r.language : 'pt'

  return { parsed: { resume: r }, fieldsFilled, warnings }
}

// ────────────────────────────────────────────────────────────────────────────
// Main handler
// ────────────────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await req.json().catch(() => ({}))
    const force: boolean = body?.force === true
    const imagesBase64: string[] = Array.isArray(body?.images_base64) ? body.images_base64 : []
    const rawTextFallback: string = typeof body?.raw_text_fallback === 'string'
      ? body.raw_text_fallback
      : ''

    if (imagesBase64.length === 0) {
      return jsonResponse({ error: 'images_base64 required' }, 400)
    }
    if (imagesBase64.length > MAX_PAGES) {
      return jsonResponse({
        error: 'too_many_pages',
        detail: `máximo ${MAX_PAGES} páginas (recebido ${imagesBase64.length})`,
      }, 400)
    }
    // Sanity check: cada imagem deve ter tamanho razoável.
    for (const img of imagesBase64) {
      const approxBytes = (img.length * 3) / 4 // base64 → bytes
      if (approxBytes > MAX_IMAGE_SIZE_BYTES) {
        return jsonResponse({
          error: 'image_too_large',
          detail: `imagem com ${(approxBytes / 1_000_000).toFixed(1)}MB excede ${MAX_IMAGE_SIZE_BYTES / 1_000_000}MB`,
        }, 400)
      }
    }

    // Anti-non-CV: se vier raw_text_fallback (caminho normal do Flutter),
    // valida que não é extrato bancário / doc gov.br / holerite antes de
    // queimar tokens de Vision. Se fallback não vier (chamada direta sem
    // texto), pula a validação — Vision pode ler imagem que o text
    // extractor não conseguiu.
    if (rawTextFallback.length >= 200) {
      const nonCv = detectNonCvContent(rawTextFallback)
      if (nonCv.isNonCv) {
        console.warn(
          `[parse-cv-vision] non-CV content detected ` +
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
    // ou JWT de usuário. Veja parse-cv/index.ts pra detalhes da estratégia
    // de aceitar ambos formatos de service_role key.
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

    // Cache hit: já tem parsed via vision e não foi pedido force.
    const existingParser = imported?.parser_source
    if (
      existingParser === 'vision' &&
      imported?.parsed &&
      !force
    ) {
      console.log(`[parse-cv-vision] cache hit user=${userId}`)
      return jsonResponse({
        parsed: imported.parsed,
        cached: true,
        fields_filled: 0,
        source: 'vision',
      })
    }

    console.log(`[parse-cv-vision] calling ${MODEL} user=${userId} pages=${imagesBase64.length}`)
    const ai = await callOpenAIVision(imagesBase64)
    console.log(`[parse-cv-vision] ${MODEL} responded tokens=${ai.totalTokens} latency=${ai.latencyMs}ms`)

    trackAIGeneration({
      userId,
      generationType: 'cv_parsing_vision',
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
      console.error(`[parse-cv-vision] JSON parse failed for user=${userId}: ${ai.content.slice(0, 300)}`)
      return jsonResponse({ error: 'ai_response_invalid' }, 502)
    }

    const { parsed, fieldsFilled, warnings } = validateAgainstFallback(rawParsed, rawTextFallback)
    if (warnings.length > 0) {
      console.warn(`[parse-cv-vision] validation warnings for user=${userId}: ${warnings.join('; ')}`)
    }

    // Persiste — sobrescreve parsed (vision tem precedência sobre text-only).
    const updatedImported = {
      ...imported,
      parsed: parsed.resume,
      parsed_at: new Date().toISOString(),
      parser_version: PARSER_VERSION,
      parser_model: MODEL,
      parser_source: 'vision',
      parsed_warnings: warnings,
    }
    const updatedGd = { ...gd, imported_resume: updatedImported }

    const updateR = await supabaseAdmin
      .from('user_profiles')
      .update({ gamification_data: updatedGd })
      .eq('id', userId)

    if (updateR.error) {
      console.error(`[parse-cv-vision] persist failed user=${userId}: ${updateR.error.message}`)
      return jsonResponse({ error: 'persist_failed', detail: updateR.error.message }, 500)
    }

    console.log(`[parse-cv-vision] SUCCESS user=${userId} fieldsFilled=${fieldsFilled}`)
    return jsonResponse({
      parsed: parsed.resume,
      cached: false,
      fields_filled: fieldsFilled,
      source: 'vision',
      warnings,
    })
  } catch (err) {
    const msg = (err as Error).message || 'unknown'
    console.error('parse-cv-vision error:', msg)
    const status = msg.includes('AbortError') || msg.includes('aborted') ? 504 : 500
    return jsonResponse({ error: 'internal', detail: msg.slice(0, 300) }, status)
  }
})
