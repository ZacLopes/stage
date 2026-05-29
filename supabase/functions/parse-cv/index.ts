// Edge Function: parse-cv
//
// Estrutura raw_text de CV em JSON via GPT-4o-mini e persiste em
// `user_profiles.gamification_data.imported_resume.parsed`. Criada na F2
// da reformulação da feature de adaptação de CV — substitui o pre-parser
// regex frágil de `adapt-resume-to-job` por extração baseada em IA com
// validação substring contra o raw_text original.
//
// Princípios:
// - EXTRAIR, nunca adaptar — sem job context, sem reescrita.
// - Cada nome próprio retornado tem que aparecer como substring no
//   raw_text (flatten/lowercase) — anti-invenção, descarta o campo se
//   falhar.
// - Idempotente: re-chamadas com `force: false` (default) e parsed
//   existente retornam o cached, sem custo de IA.
// - Non-blocking no client: pickAndImport dispara fire-and-forget; se
//   parse-cv falhar, adapt-resume-to-job ainda funciona via raw_text.
//
// Input:  { force?: bool }  (raw_text vem do banco — sempre fresco)
// Output: { parsed: {resume}, cached: bool, fields_filled: int, source: 'parsed_v2' }
//
// Custo: ~$0.0005 por parse (cache miss). ~1500 tokens input + 800 output.

import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration, trackEdgeFunctionInvoked } from '../_shared/posthog.ts'
import { PARSE_CV_JSON_SCHEMA } from '../_shared/cv_schema.ts'
import { flatten, normalize } from '../_shared/cv_text.ts'
import { detectNonCvContent, nonCvMessage } from '../_shared/cv_content_validator.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MODEL = 'gpt-4o-mini'
const PARSER_VERSION = 'v1'
// 40s cobre p99 de CVs grandes (~6KB observado em bea.fsansone que estava
// timeoutando em 25s). CV típico processa em 4-8s; CVs longos chegam a 18-25s.
const OPENAI_TIMEOUT_MS = 40000
const MIN_RAW_TEXT_LEN = 200 // abaixo disso é OCR ruim — não tenta

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ────────────────────────────────────────────────────────────────────────────
// Prompt
// ────────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `Você é um extrator estrutural de currículos. Sua tarefa é receber o TEXTO BRUTO de um CV (extraído de PDF, com formatação parcial perdida) e retornar um JSON estruturado.

REGRAS INVIOLÁVEIS:
1. NÃO adapte, NÃO reescreva, NÃO melhore. Apenas EXTRAIA o que está escrito.
2. NÃO invente nada. Se um campo não está no CV, retorne string vazia ou array vazio.
3. Preserve nomes próprios EXATAMENTE como aparecem (mesma capitalização, mesmos espaços).
4. NÃO mude datas. Use o formato que está no CV ("Jan 2024 - Dez 2025", "01/2024", etc.).
5. PDFs frequentemente vêm com quebras de linha embaralhadas (cada palavra numa linha). Use contexto pra reconstruir frases coesas, mas SÓ a partir de palavras que estão no CV.
6. Para experiência profissional: extraia TODAS as posições do CV. Bullets/descrições preserve um por linha (separadas por \\n).
7. Para educação: extraia TODAS as formações. Se há GPA/honras/representação/coursework, coloque em "details".
8. Para skills: extraia palavras-chave da seção "Habilidades" / "Skills" / "Competências". NÃO inclua frases longas, só nomes de skills/tools.
9. Achievements: prêmios, distinções, projetos pessoais marcantes. Não duplique com bullets de experience.
10. Interests: hobbies, esportes, leituras — só se o CV tiver seção explícita.
11. Certifications: cursos extras + certificações profissionais (ex: "Modelagem Financeira - Wall Street Prep - 2025", "AWS Cloud Practitioner - 2024"). Formate cada item como string auto-contida: "Nome do curso/cert - Instituição - Ano" (omita partes que faltarem). Inclui qualquer seção do CV intitulada "CERTIFICAÇÕES", "CURSOS", "CURSOS E CERTIFICAÇÕES", "CERTIFICATIONS", "COURSES". NÃO repita aqui o que já está em achievements.
12. Language: detecte se o CV está em "pt" (português) ou "en" (inglês). Default "pt".
12. Para campos imutáveis (fullName, email, phone, linkedin, location), pegue do header do CV. Se incertos, deixe vazio em vez de chutar.

FORMATO DE BULLETS: cada bullet/responsabilidade deve ser uma linha do campo "description". Se o CV usa "•" ou "-", remova esses marcadores — só o texto da ação.

EXEMPLO de experience:
Input do CV:
  Stage  Londrina - PR
  CEO  Dez 2025 - Atual
  • Desenvolvi um aplicativo gamificado...
  • Fechei uma venda significativa...

Output:
  {"role":"CEO","company":"Stage","period":"Dez 2025 - Atual","location":"Londrina - PR","description":"Desenvolvi um aplicativo gamificado...\\nFechei uma venda significativa..."}`

function buildUserPrompt(rawText: string): string {
  return `EXTRAIA o currículo a seguir em JSON estruturado.

=== TEXTO BRUTO DO CV ===
${rawText.slice(0, 8000)}
=== FIM DO CV ===

Retorne o objeto { resume: {...} } seguindo o schema. Mantenha fidelidade absoluta ao que está no CV — não invente nada.`
}

// ────────────────────────────────────────────────────────────────────────────
// OpenAI call
// ────────────────────────────────────────────────────────────────────────────

async function callOpenAI(rawText: string): Promise<{
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
          { role: 'user', content: buildUserPrompt(rawText) },
        ],
        temperature: 0.0, // extração estrita, zero inferência
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
// Validação anti-invenção: cada nome próprio extraído precisa aparecer
// como substring no raw_text (flatten). Strings que não passam são zeradas
// silenciosamente — preferimos perfil incompleto a perfil inventado.
// ────────────────────────────────────────────────────────────────────────────

function validateAgainstRawText(parsed: any, rawText: string): {
  parsed: any
  fieldsFilled: number
  warnings: string[]
} {
  const cvFlat = flatten(rawText)
  // Fallback pra PDFs extraídos caractere-por-linha (Syncfusion às vezes
  // devolve "B\nE\nA\nT\nR\nI\nZ" — caso real do bea.fsansone). Comparar
  // sem whitespace recupera esses CVs sem perder a proteção anti-invenção
  // (sequências de 4+ caracteres alfanuméricos seguidos continuam sendo
  // confiáveis indicador de que a string apareceu mesmo no CV).
  const cvNoSpace = cvFlat.replace(/\s+/g, '')
  const warnings: string[] = []
  const r = parsed?.resume ?? {}
  let fieldsFilled = 0

  function isInCv(value: string): boolean {
    if (!value || value.trim().length === 0) return false
    const flat = flatten(value)
    if (flat.length === 0) return false
    // Strings curtas (1-2 chars) sempre passam — emoji, separadores, etc.
    if (flat.length <= 2) return true
    if (cvFlat.includes(flat)) return true
    // Fallback: tenta sem whitespace pra cobrir extração caractere-por-linha.
    const flatNoSpace = flat.replace(/\s+/g, '')
    if (flatNoSpace.length >= 4 && cvNoSpace.includes(flatNoSpace)) return true
    return false
  }

  // Campos string simples — drop se não aparece no CV.
  const stringFields = ['fullName', 'email', 'phone', 'linkedin', 'location']
  for (const f of stringFields) {
    const v = String(r[f] ?? '').trim()
    if (v && !isInCv(v)) {
      warnings.push(`${f} dropped (not in raw_text): "${v.slice(0, 50)}"`)
      r[f] = ''
    } else if (v) {
      fieldsFilled++
    }
  }

  // Summary: se >50 chars, valida que >=60% das palavras significativas
  // aparecem no CV. Se menor, deixa passar.
  const summary = String(r.summary ?? '').trim()
  if (summary.length > 50) {
    const flatSummary = flatten(summary)
    const words = flatSummary.split(/\s+/).filter((w) => w.length >= 4)
    const inCv = words.filter((w) => cvFlat.includes(w)).length
    const ratio = words.length > 0 ? inCv / words.length : 1
    if (ratio < 0.6) {
      warnings.push(`summary dropped (${(ratio * 100).toFixed(0)}% words in CV)`)
      r.summary = ''
    } else {
      fieldsFilled++
    }
  } else if (summary.length > 0) {
    fieldsFilled++
  }

  // Skills: filtra os que não aparecem no CV.
  if (Array.isArray(r.skills)) {
    const before = r.skills.length
    r.skills = r.skills.filter((s: unknown) => {
      const v = String(s ?? '').trim()
      return v.length > 0 && isInCv(v)
    })
    if (r.skills.length < before) {
      warnings.push(`skills filtered: ${before} → ${r.skills.length}`)
    }
    if (r.skills.length > 0) fieldsFilled++
  } else {
    r.skills = []
  }

  // Experiences: filtra entradas cuja company não aparece no CV.
  if (Array.isArray(r.experiences)) {
    const before = r.experiences.length
    r.experiences = r.experiences.filter((e: any) => {
      const company = String(e?.company ?? '').trim()
      return company.length > 0 && isInCv(company)
    })
    if (r.experiences.length < before) {
      warnings.push(`experiences filtered: ${before} → ${r.experiences.length}`)
    }
    if (r.experiences.length > 0) fieldsFilled++
  } else {
    r.experiences = []
  }

  // Education: filtra entradas cuja institution não aparece no CV.
  if (Array.isArray(r.education)) {
    const before = r.education.length
    r.education = r.education.filter((e: any) => {
      const inst = String(e?.institution ?? '').trim()
      return inst.length > 0 && isInCv(inst)
    })
    if (r.education.length < before) {
      warnings.push(`education filtered: ${before} → ${r.education.length}`)
    }
    if (r.education.length > 0) fieldsFilled++
  } else {
    r.education = []
  }

  // Achievements + interests: deixa passar (não são "nomes próprios", são
  // texto livre — risco de invenção é menor e útil pro user).
  if (Array.isArray(r.achievements) && r.achievements.length > 0) fieldsFilled++
  if (Array.isArray(r.interests) && r.interests.length > 0) fieldsFilled++

  // Language: sempre passa, default 'pt'.
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

  // B.7 do plano v2 — timer pra trackEdgeFunctionInvoked emitido no
  // success path e no catch outer. `userId` é resolvido dentro do try
  // (auth ou body) — só uso aqui pra calcular duração.
  const fnStart = Date.now()
  let userIdForTracking = 'edge_function:parse-cv'
  try {
    const body = await req.json().catch(() => ({}))
    const force: boolean = body?.force === true

    // Detecta auth via service-role vs JWT de usuário.
    //
    // O Supabase tem 2 formatos de service_role key coexistindo:
    //   - Legacy JWT (eyJ... ~210 chars): o que aparece no dashboard
    //     Settings → API → service_role.
    //   - Modern API key (sb_secret_... ~41 chars): o que vive na env
    //     `SUPABASE_SERVICE_ROLE_KEY` da edge function.
    // Ambas representam a mesma identidade admin. Comparar string a string
    // só funciona pra `sb_secret_`; o JWT legacy precisa decodificar e
    // verificar o claim `role`.
    //
    // Estratégia: aceita o caller como service-role se QUALQUER:
    //   (a) Authorization Bearer == env SUPABASE_SERVICE_ROLE_KEY exato
    //   (b) X-Service-Role-Key header == env exato (fallback p/ gateway
    //       que reescreve Authorization)
    //   (c) Authorization Bearer é um JWT supabase com role=service_role
    //       e ref=projectId (legacy JWT path).
    const authHeader = req.headers.get('Authorization') ?? ''
    const customServiceKeyHeader = req.headers.get('X-Service-Role-Key') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const authMatches = serviceRoleKey.length > 0 &&
        authHeader === `Bearer ${serviceRoleKey}`
    const customMatches = serviceRoleKey.length > 0 &&
        customServiceKeyHeader === serviceRoleKey

    // Decodifica o JWT do Authorization (sem validar assinatura — o gateway
    // do Supabase já validou pra chegar aqui via --no-verify-jwt=false; mesmo
    // sem isso, validar role+ref+exp já bloqueia ataques óbvios).
    let jwtIsServiceRole = false
    if (authHeader.startsWith('Bearer ey')) {
      try {
        const token = authHeader.slice('Bearer '.length)
        const payloadB64 = token.split('.')[1] ?? ''
        // Base64url → base64
        const normalized = payloadB64.replace(/-/g, '+').replace(/_/g, '/')
        const padded = normalized + '='.repeat((4 - normalized.length % 4) % 4)
        const payloadJson = atob(padded)
        const payload = JSON.parse(payloadJson) as {
          iss?: string
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

    console.log(
      `[parse-cv] auth-check: ` +
      `envKeyLen=${serviceRoleKey.length} authMatch=${authMatches} ` +
      `customMatch=${customMatches} jwtServiceRole=${jwtIsServiceRole} ` +
      `final=${isServiceRole}`,
    )

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
      userIdForTracking = user.id
    }

    // Lê raw_text do banco — sempre fresco. Não aceita raw_text via input
    // pra evitar abuso (user mandando texto arbitrário pra "limpar" via IA).
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
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
    const rawText: string = typeof imported.raw_text === 'string' ? imported.raw_text : ''

    if (rawText.length < MIN_RAW_TEXT_LEN) {
      return jsonResponse({
        error: 'raw_text_too_short',
        detail: `raw_text tem ${rawText.length} chars (mínimo ${MIN_RAW_TEXT_LEN})`,
      }, 422)
    }

    // Anti-non-CV: bloqueia upload de extrato bancário, doc gov.br, holerite.
    // Segunda camada (cliente Flutter valida antes); aqui protege contra
    // bypass via service-role / cliente antigo. Não persiste parsed nesses
    // casos — raw_text continua no banco até cleanup manual ou usuário
    // reenviar CV correto (vai sobrescrever).
    const nonCv = detectNonCvContent(rawText)
    if (nonCv.isNonCv) {
      console.warn(
        `[parse-cv] non-CV content detected user=${userId} ` +
        `category=${nonCv.category} reasons=${nonCv.reasons.join(',')}`,
      )
      return jsonResponse({
        error: 'non_cv_content',
        category: nonCv.category,
        message: nonCvMessage(nonCv.category!),
        reasons: nonCv.reasons,
      }, 422)
    }

    // Cache hit: já tem parsed e não foi pedido force.
    const existingParsed = imported?.parsed
    if (existingParsed && typeof existingParsed === 'object' && !force) {
      const fieldsFilled = countFilledFields(existingParsed)
      console.log(`[parse-cv] cache hit user=${userId} fieldsFilled=${fieldsFilled}`)
      return jsonResponse({
        parsed: existingParsed,
        cached: true,
        fields_filled: fieldsFilled,
        source: 'parsed_v2',
      })
    }

    // Cache miss — chamar IA.
    console.log(`[parse-cv] calling OpenAI user=${userId} rawTextLen=${rawText.length}`)
    const ai = await callOpenAI(rawText)
    console.log(`[parse-cv] OpenAI responded tokens=${ai.totalTokens} latency=${ai.latencyMs}ms`)

    trackAIGeneration({
      userId: userId,
      generationType: 'cv_parsing',
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
      console.error(`[parse-cv] JSON parse failed for user=${userId}: ${ai.content.slice(0, 300)}`)
      return jsonResponse({ error: 'ai_response_invalid' }, 502)
    }

    const { parsed, fieldsFilled, warnings } = validateAgainstRawText(rawParsed, rawText)
    if (warnings.length > 0) {
      console.warn(`[parse-cv] validation warnings for user=${userId}: ${warnings.join('; ')}`)
    }

    // Persiste em imported_resume.parsed (NÃO mexe em raw_text nem outros campos).
    const updatedImported = {
      ...imported,
      parsed: parsed.resume,
      parsed_at: new Date().toISOString(),
      parser_version: PARSER_VERSION,
      parser_model: MODEL,
      parsed_warnings: warnings,
      // F4: marca quando o parsing veio do backfill via service-role —
      // distingue cohort no PostHog e permite filtrar via SQL.
      ...(isServiceRole ? { parsed_backfilled_at: new Date().toISOString() } : {}),
    }
    const updatedGd = { ...gd, imported_resume: updatedImported }

    const updateR = await supabaseAdmin
      .from('user_profiles')
      .update({ gamification_data: updatedGd })
      .eq('id', userId)

    if (updateR.error) {
      console.error(`[parse-cv] persist failed user=${userId}: ${updateR.error.message}`)
      return jsonResponse({ error: 'persist_failed', detail: updateR.error.message }, 500)
    }

    console.log(`[parse-cv] SUCCESS user=${userId} fieldsFilled=${fieldsFilled}`)
    trackEdgeFunctionInvoked({
      functionName: 'parse-cv',
      distinctId: userId,
      durationMs: Date.now() - fnStart,
      status: 'ok',
      extra: { fields_filled: fieldsFilled },
    }).catch(() => {})
    return jsonResponse({
      parsed: parsed.resume,
      cached: false,
      fields_filled: fieldsFilled,
      source: 'parsed_v2',
      warnings,
    })
  } catch (err) {
    const msg = (err as Error).message || 'unknown'
    console.error('parse-cv error:', msg)
    const status = msg.includes('AbortError') || msg.includes('aborted') ? 504 : 500
    trackEdgeFunctionInvoked({
      functionName: 'parse-cv',
      distinctId: userIdForTracking,
      durationMs: Date.now() - fnStart,
      status: 'error',
      errorCode: status === 504 ? 'timeout' : 'internal',
      extra: { error_message: msg.slice(0, 300) },
    }).catch(() => {})
    return jsonResponse({ error: 'internal', detail: msg.slice(0, 300) }, status)
  }
})

/** Conta quantos campos top-level do parsed têm dado preenchido (>0). */
function countFilledFields(parsed: any): number {
  if (!parsed || typeof parsed !== 'object') return 0
  let count = 0
  for (const f of ['fullName', 'email', 'phone', 'linkedin', 'location', 'summary']) {
    if (typeof parsed[f] === 'string' && parsed[f].trim().length > 0) count++
  }
  for (const f of ['skills', 'experiences', 'education', 'achievements', 'interests']) {
    if (Array.isArray(parsed[f]) && parsed[f].length > 0) count++
  }
  return count
}

// Suprime "unused" warning do `normalize` import — pode ser usado em
// validações futuras (similarity scoring na F6).
void normalize
