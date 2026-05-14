// Edge Function: analyze-match
//
// Calcula score de match (0-100) entre uma vaga e o perfil do usuário usando
// GPT-4o-mini. Cache em `match_analyses` por (user_id, job_id) com invalidação
// via SHA-256 das prefs+gamification_data relevantes.
//
// Input:  { job_id: uuid }  (user_id vem do JWT)
// Output: { score, reasons, cached, model_used }  (status 200)
//         { error }  (4xx/5xx)
//
// Custo: ~$0.00027 por análise sem cache. Cache hit é grátis.
// Rate limit: 100 chamadas/dia/user (cache hits NÃO contam).

import { serve } from 'std/http/server'
import { createClient } from 'supabase'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MODEL = 'gpt-4o-mini'
const PROMPT_VERSION = 'v4' // bump quando alterar SYSTEM_PROMPT (invalida cache)
const CACHE_TTL_DAYS = 30
const RATE_LIMIT_PER_DAY = 100
const OPENAI_TIMEOUT_MS = 8000

interface MatchReason {
  label: string
  matched: boolean
  weight: number
  detail?: string
}

interface MatchPayload {
  score: number
  reasons: MatchReason[]
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

/**
 * Sanitiza CV bruto. Pega 1500 ou 3000 chars dependendo de quanto contexto
 * a IA precisa: 3000 quando o CV é a ÚNICA fonte do perfil (sem prefs nem
 * skills estruturadas), 1500 quando é só complemento.
 */
function extractRelevantCvSection(
  rawText: string | null | undefined,
  budgetChars: number,
): string {
  if (!rawText) return ''
  const cap = Math.min(rawText.length, 8000)
  const text = rawText.slice(0, cap)
  const re = /(habilidades|skills|tecnologias|ferramentas|competências|conhecimentos|experiência|formação)/i
  const match = text.match(re)
  if (match && match.index !== undefined) {
    const start = Math.max(0, match.index - 200)
    return text.slice(start, start + budgetChars)
  }
  return text.slice(0, budgetChars)
}

/**
 * Detecta se prefs estão TODAS vazias. Quando true + CV presente, usamos
 * estratégia "CV-first" no prompt.
 */
function hasNoPrefs(prefs: any): boolean {
  if (!prefs) return true
  const areas = prefs.areas
  const locs = prefs.locations
  const wm = prefs.work_models
  const jt = prefs.job_types
  const ms = prefs.min_salary
  return (
    (!Array.isArray(areas) || areas.length === 0) &&
    (!Array.isArray(locs) || locs.length === 0) &&
    (!Array.isArray(wm) || wm.length === 0) &&
    (!Array.isArray(jt) || jt.length === 0) &&
    (ms == null || ms === 0)
  )
}

async function pickPrefsForHash(prefs: any, gamificationData: any): Promise<string> {
  const safe = (v: any) => (v == null ? null : v)
  const whoIAm = (gamificationData?.whoIAm?.derived) || {}
  const imported = gamificationData?.imported_resume || {}
  // Hash do CV inteiro (não só primeiros 200 chars) — user que edita o miolo
  // do CV mantendo o cabeçalho intacto invalida cache corretamente agora.
  const cvText = imported.raw_text || ''
  const cvHash = cvText ? await sha256Hex(cvText) : ''
  const canonical = {
    areas: safe(prefs?.areas),
    locations: safe(prefs?.locations),
    work_models: safe(prefs?.work_models),
    job_types: safe(prefs?.job_types),
    min_salary: safe(prefs?.min_salary),
    skills: safe(whoIAm.skills),
    summary: safe(whoIAm.summary),
    interests: safe(whoIAm.interests),
    cv_text_len: cvText.length,
    cv_text_hash: cvHash,
  }
  return JSON.stringify(canonical)
}

// ────────────────────────────────────────────────────────────────────────────
// Prompt
// ────────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `Você analisa fit entre estudantes/juniores brasileiros e vagas de estágio/junior.

═══════════════════════════════════════════════════════════════════
REGRA #1 (CRÍTICA) — O SCORE É MATEMÁTICA EXATA:
  score = soma dos "weight" onde matched=true.
  Exemplo: matched em Área (30) + Tipo (20) = score 50. NÃO é 70, NÃO é 85.
  NUNCA arredonde pra cima. NUNCA infle. Soma exata, sempre.

REGRA #2 (CRÍTICA) — NÃO INVENTE DADOS DO CANDIDATO:
  Se o candidato não declarou "Jurídico" como interesse, ele NÃO tem interesse em Jurídico.
  O título da vaga é INFORMAÇÃO DA VAGA, não do candidato.
  Você NÃO pode inferir interesse do candidato a partir do título/descrição da vaga.
  Se o candidato não tem skill X declarada, ele NÃO tem skill X.

═══════════════════════════════════════════════════════════════════
ESTRATÉGIA (escolha o cenário ANTES de pontuar):

CENÁRIO A — candidato TEM preferências declaradas (áreas/cidades/modelo/tipo/salário):
  Pesos: Área 30, Tipo 20, Localização 15, Modelo 15, Salário 10, Skills 10.
  Avalie SOMENTE contra os dados que o candidato declarou.

CENÁRIO B — candidato SEM preferências MAS COM perfil (CV importado, skills, sobre, interesses):
  Use APENAS o CV/perfil como fonte de verdade do candidato.
  Pesos: Área (afinidade CV↔vaga) 40, Skills (sobreposição com requisitos) 40, Tipo 10, Modelo/Local 10.
  Do CV você pode extrair área de formação, skills, cidade, nível — desde que ESTEJA EXPLÍCITO no texto.

CENÁRIO C — candidato SEM preferências E SEM perfil (cadastro incompleto):
  PARE. Retorne EXATAMENTE:
  {"score": 50, "reasons": [{"label":"Sem perfil","matched":false,"weight":0,"detail":"Configure suas preferências ou suba seu CV para um match preciso."}]}
  Não tente analisar. Não tente inferir do título da vaga. PARE.

═══════════════════════════════════════════════════════════════════
COMO AVALIAR cada dimensão (Cenário A/B):

- matched=true: o dado DO CANDIDATO bate com o requisito da vaga. Some o weight.
- matched=false, weight=0: o candidato NÃO declarou esse dado (não penalize, mas também não some).
- matched=false, weight>0: o candidato declarou MAS não bate (raro — só quando há conflito explícito).

Seja generoso em afinidade SEMÂNTICA REAL:
  "Marketing Digital" ↔ "Designer com Photoshop" = match (Adobe compartilhado)
  "Excel avançado" ↔ "análise de dados" = match
  "Photoshop" ≈ "Adobe Creative" = match

NUNCA seja generoso INVENTANDO dado. Se candidato diz "Direito" e vaga é "Marketing", NÃO é match só porque ambos existem.

═══════════════════════════════════════════════════════════════════
EXEMPLOS:

# Exemplo 1 — Cenário A, fit alto
INPUT: candidato declarou areas=["Tecnologia"], locations=["São Paulo"], work_models=["remoto"], job_types=["estagio"]
       vaga: "Estágio Dev Frontend", área="Tecnologia", cidade="São Paulo", modelo="remoto", tipo="estagio"
OUTPUT (correto):
{"score": 80, "reasons": [
  {"label":"Área","matched":true,"weight":30,"detail":"Tecnologia bate exatamente com seu interesse declarado."},
  {"label":"Tipo","matched":true,"weight":20,"detail":"Estágio é o tipo que você procura."},
  {"label":"Localização","matched":true,"weight":15,"detail":"São Paulo é a cidade que você prefere."},
  {"label":"Modelo","matched":true,"weight":15,"detail":"Remoto bate com sua preferência."},
  {"label":"Salário","matched":false,"weight":0,"detail":"Você não definiu mínimo de salário."},
  {"label":"Skills","matched":false,"weight":0,"detail":"Você não declarou skills específicas para comparar."}
]}
NOTA: 30+20+15+15 = 80. NÃO arredondar pra 85 ou 90.

# Exemplo 2 — Cenário A, fit médio (apenas algumas dimensões batem)
INPUT: candidato declarou areas=["Jurídico"], nada mais
       vaga: "Estagiário Jurídico Imobiliário", área="Jurídico", cidade="São Paulo", modelo="híbrido", tipo="estagio"
OUTPUT (correto):
{"score": 50, "reasons": [
  {"label":"Área","matched":true,"weight":30,"detail":"Jurídico bate exatamente com seu interesse declarado."},
  {"label":"Tipo","matched":true,"weight":20,"detail":"Estágio é compatível."},
  {"label":"Localização","matched":false,"weight":0,"detail":"Você não declarou cidade preferida."},
  {"label":"Modelo","matched":false,"weight":0,"detail":"Você não declarou modelo de trabalho preferido."},
  {"label":"Salário","matched":false,"weight":0,"detail":"Você não definiu mínimo de salário."},
  {"label":"Skills","matched":false,"weight":0,"detail":"Você não declarou skills para comparação."}
]}
NOTA: 30+20 = 50. NÃO inflar para 70, 85 ou 100 só porque a única dimensão que existe bateu.

# Exemplo 3 — Cenário C, sem dado
INPUT: prefs vazias, sem whoIAm, sem CV importado
       vaga: qualquer
OUTPUT (correto):
{"score": 50, "reasons": [
  {"label":"Sem perfil","matched":false,"weight":0,"detail":"Configure suas preferências ou suba seu CV para um match preciso."}
]}

═══════════════════════════════════════════════════════════════════
OUTPUT JSON ESTRITO:
{"score": <int 0..100, soma EXATA dos weights matched>, "reasons": [{"label": "...", "matched": <bool>, "weight": <int>, "detail": "..."}, ...]}

CADA reason.detail: máximo 150 chars, PT-BR, segunda pessoa ("sua área", "você tem...").
NÃO inclua texto fora do JSON. NÃO adicione fences markdown.`

function buildUserPrompt(opts: {
  job: any
  prefs: any
  gamificationData: any
}): string {
  const { job, prefs, gamificationData } = opts
  const whoIAm = gamificationData?.whoIAm?.derived || {}
  const rawCv = gamificationData?.imported_resume?.raw_text
  const noPrefs = hasNoPrefs(prefs)
  const noStructuredProfile =
    !whoIAm.skills && !whoIAm.summary && !whoIAm.interests
  // CV é a única fonte → mais espaço pro CV (3000 chars). Senão 1500.
  const cvBudget = noPrefs && noStructuredProfile && rawCv ? 3000 : 1500
  const cvSection = extractRelevantCvSection(rawCv, cvBudget)

  const lines: string[] = []

  // ── CANDIDATO ─────────────────────────────────────────────────────
  if (noPrefs && noStructuredProfile && cvSection) {
    // CENÁRIO B (CV-only): prefs vazias mas tem CV. CV é a fonte de verdade.
    lines.push('## CANDIDATO (sem preferências definidas — perfil EXTRAÍDO do CV abaixo)')
    lines.push('')
    lines.push('Use o CV como fonte de verdade pra inferir área de interesse,')
    lines.push('skills e experiência do candidato. Trate-o como CENÁRIO B do system prompt.')
    lines.push('')
    lines.push('### CV importado (texto bruto):')
    lines.push(cvSection)
  } else {
    // CENÁRIO A (com prefs) ou misto (prefs + CV).
    lines.push('## CANDIDATO')
    lines.push(`Áreas de interesse: ${JSON.stringify(prefs?.areas ?? [])}`)
    lines.push(`Cidades preferidas: ${JSON.stringify(prefs?.locations ?? [])}`)
    lines.push(`Modelos preferidos: ${JSON.stringify(prefs?.work_models ?? [])}`)
    lines.push(`Tipos preferidos: ${JSON.stringify(prefs?.job_types ?? [])}`)
    if (prefs?.min_salary && prefs.min_salary > 0) {
      lines.push(`Salário mínimo: R$ ${(prefs.min_salary / 100).toFixed(0)}`)
    } else {
      lines.push('Salário mínimo: não definido')
    }
    if (whoIAm.skills) lines.push(`Skills (resumo): ${String(whoIAm.skills).slice(0, 500)}`)
    if (whoIAm.summary) lines.push(`Sobre mim: ${String(whoIAm.summary).slice(0, 300)}`)
    if (whoIAm.interests) lines.push(`Interesses: ${String(whoIAm.interests).slice(0, 300)}`)
    if (cvSection) lines.push(`CV importado (trecho relevante):\n${cvSection}`)
  }

  lines.push('')
  lines.push('## VAGA')
  lines.push(`Título: ${job.title}`)
  lines.push(`Área: ${job.area || 'não informada'}`)
  lines.push(`Tipo: ${job.job_type}`)
  lines.push(`Localização: ${job.location_city || ''}, ${job.location_state || ''}`)
  lines.push(`Modelo: ${job.work_model}`)
  if (job.salary_min || job.salary_max) {
    const min = job.salary_min ? `R$ ${(job.salary_min / 100).toFixed(0)}` : '?'
    const max = job.salary_max ? `R$ ${(job.salary_max / 100).toFixed(0)}` : ''
    lines.push(`Salário: ${min}${max ? ` - ${max}` : ''}`)
  } else {
    lines.push('Salário: a combinar')
  }

  const reqs = Array.isArray(job.requirements) ? job.requirements.slice(0, 10) : []
  lines.push(`Requisitos: ${JSON.stringify(reqs)}`)
  const desc = (job.description || '').slice(0, 1000)
  lines.push(`Descrição: ${desc}`)

  lines.push('')
  lines.push('Calcule o match seguindo as regras. Retorne APENAS o JSON.')
  return lines.join('\n')
}

// ────────────────────────────────────────────────────────────────────────────
// OpenAI
// ────────────────────────────────────────────────────────────────────────────

async function callOpenAI(systemPrompt: string, userPrompt: string): Promise<{
  content: string
  inputTokens: number
  outputTokens: number
  totalTokens: number
}> {
  const ctrl = new AbortController()
  const timeout = setTimeout(() => ctrl.abort(), OPENAI_TIMEOUT_MS)

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
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
        temperature: 0.2,
        max_tokens: 700, // 6 reasons × ~250 chars (label + detail 150 + json overhead) ≈ 600 tokens
        response_format: { type: 'json_object' },
      }),
    })

    if (!resp.ok) {
      const errText = await resp.text()
      throw new Error(`OpenAI ${resp.status}: ${errText.slice(0, 300)}`)
    }
    const data = await resp.json()
    return {
      content: data.choices[0].message.content,
      inputTokens: data.usage?.prompt_tokens ?? 0,
      outputTokens: data.usage?.completion_tokens ?? 0,
      totalTokens: data.usage?.total_tokens ?? 0,
    }
  } finally {
    clearTimeout(timeout)
  }
}

function parseAndValidate(raw: string): MatchPayload {
  // Strip ```json``` fences se existirem
  let text = raw.trim()
  if (text.startsWith('```json')) text = text.slice(7)
  if (text.startsWith('```')) text = text.slice(3)
  if (text.endsWith('```')) text = text.slice(0, -3)
  text = text.trim()

  const parsed = JSON.parse(text)
  const score = Number(parsed.score)
  if (!Number.isFinite(score)) throw new Error('score inválido')
  const clampedScore = Math.max(0, Math.min(100, Math.round(score)))

  const rawReasons = Array.isArray(parsed.reasons) ? parsed.reasons : []
  const reasons: MatchReason[] = rawReasons.slice(0, 6).map((r: any) => ({
    label: String(r?.label ?? ''),
    matched: r?.matched === true,
    weight: Number.isFinite(Number(r?.weight)) ? Number(r.weight) : 0,
    detail: r?.detail ? String(r.detail).slice(0, 200) : undefined,
  }))

  return { score: clampedScore, reasons }
}

// ────────────────────────────────────────────────────────────────────────────
// Main handler
// ────────────────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } },
    )

    // 1. Auth
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
    if (authError || !user) return jsonResponse({ error: 'Unauthorized' }, 401)

    // 2. Parse input
    const body = await req.json().catch(() => ({}))
    const jobId: string | undefined = body?.job_id
    if (!jobId || typeof jobId !== 'string') {
      return jsonResponse({ error: 'job_id required' }, 400)
    }

    // 3. Rate limit (cache hits NÃO contam — só calls de IA reais)
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const { count: rlCount } = await supabaseClient
      .from('ai_generation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .eq('generation_type', 'match_analysis')
      .gte('created_at', today.toISOString())

    if (rlCount && rlCount >= RATE_LIMIT_PER_DAY) {
      return jsonResponse({ error: `Rate limit exceeded. Maximum ${RATE_LIMIT_PER_DAY} match analyses per day.` }, 429)
    }

    // 4. Fetch em paralelo: job, profile, prefs
    const [jobR, profileR, prefsR] = await Promise.all([
      supabaseClient.from('jobs').select('*').eq('id', jobId).maybeSingle(),
      supabaseClient.from('user_profiles').select('gamification_data').eq('id', user.id).maybeSingle(),
      supabaseClient.from('user_preferences').select('*').eq('user_id', user.id).maybeSingle(),
    ])

    if (jobR.error || !jobR.data) return jsonResponse({ error: 'job_not_found' }, 404)
    const job = jobR.data
    const gamificationData = profileR.data?.gamification_data ?? {}
    const prefs = prefsR.data ?? {}

    // 5. Compute profile_hash + cache lookup
    const profileHash = await sha256Hex(await pickPrefsForHash(prefs, gamificationData))
    const cacheCutoff = new Date(Date.now() - CACHE_TTL_DAYS * 86400_000).toISOString()

    const { data: cachedRow } = await supabaseClient
      .from('match_analyses')
      .select('score, reasons, model_used, computed_at, profile_hash, prompt_version')
      .eq('user_id', user.id)
      .eq('job_id', jobId)
      .maybeSingle()

    if (
      cachedRow &&
      cachedRow.profile_hash === profileHash &&
      cachedRow.prompt_version === PROMPT_VERSION &&
      cachedRow.computed_at >= cacheCutoff
    ) {
      return jsonResponse({
        score: cachedRow.score,
        reasons: cachedRow.reasons,
        cached: true,
        model_used: cachedRow.model_used,
      })
    }

    // 6. Call OpenAI
    const userPrompt = buildUserPrompt({ job, prefs, gamificationData })
    const ai = await callOpenAI(SYSTEM_PROMPT, userPrompt)

    let payload: MatchPayload
    try {
      payload = parseAndValidate(ai.content)
    } catch (e) {
      console.error('Failed to parse AI output:', ai.content)
      return jsonResponse({ error: 'ai_response_invalid', detail: (e as Error).message }, 502)
    }

    // 7. Persist cache (upsert) + log
    await supabaseClient.from('match_analyses').upsert({
      user_id: user.id,
      job_id: jobId,
      score: payload.score,
      reasons: payload.reasons,
      model_used: MODEL,
      prompt_version: PROMPT_VERSION,
      profile_hash: profileHash,
      computed_at: new Date().toISOString(),
    }, { onConflict: 'user_id,job_id' })

    await supabaseClient.from('ai_generation_logs').insert({
      user_id: user.id,
      generation_type: 'match_analysis',
      tokens_used: ai.totalTokens,
    })

    return jsonResponse({
      score: payload.score,
      reasons: payload.reasons,
      cached: false,
      model_used: MODEL,
    })
  } catch (err) {
    const msg = (err as Error).message || 'unknown'
    console.error('analyze-match error:', msg)
    const status = msg.includes('AbortError') || msg.includes('aborted') ? 504 : 500
    return jsonResponse({ error: 'internal', detail: msg.slice(0, 300) }, status)
  }
})
