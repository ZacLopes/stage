// Edge Function: extract-job-skills
//
// Extrai skills atômicas dos requisitos+descrição de uma vaga via GPT-4o-mini
// e cruza contra o CV do user pra marcar `in_cv: bool` e contra
// `confirmed_skills` do user pra marcar `pre_confirmed: bool`.
//
// Usado pela tela de "confirmação de skills antes da adaptação": user vê a
// lista, confirma quais sabe mas esqueceu de colocar no CV. Essas skills
// confirmadas são passadas pro `adapt-resume-to-job` via `extra_skills`.
//
// Input:  { job_id: uuid }
// Output: { skills: [{name, in_cv, pre_confirmed, source}], total, in_cv_count }
//
// Cache: tabela `jobs_skill_extraction` POR VAGA (não por user). `in_cv` e
// `pre_confirmed` são calculados em runtime usando o CV do user atual — o
// cache contém só `[{name, source}]`.
//
// Custo: ~$0.0003 por extração (cache miss). Cache hit é grátis.
// Rate limit: 50/dia/user (cache hits NÃO contam — só calls de IA reais).

import { serve } from 'std/http/server'
import { createClient } from 'supabase'
import { trackAIGeneration } from '../_shared/posthog.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MODEL = 'gpt-4o-mini'
const PROMPT_VERSION = 'v1'
const CACHE_TTL_DAYS = 30
const RATE_LIMIT_PER_DAY = 50
const OPENAI_TIMEOUT_MS = 10000
const MAX_SKILLS_OUT = 12

// ────────────────────────────────────────────────────────────────────────────
// Helpers (mesma família dos de adapt-resume-to-job — duplicados aqui porque
// Edge Functions em Deno não compartilham imports facilmente)
// ────────────────────────────────────────────────────────────────────────────

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

/** Normaliza string pra comparação (lower + remove acentos + trim). */
function normalize(s: string | null | undefined): string {
  if (!s) return ''
  return s
    .toLowerCase()
    .trim()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
}

/** Flatten: normalize + colapsa whitespace múltiplo. Pra match contra raw_text. */
function flatten(s: string | null | undefined): string {
  return normalize(s).replace(/\s+/g, ' ').trim()
}

/**
 * Sinônimos básicos pra match in_cv. Lista pequena e curada — não é NLP, é
 * só pra cobrir os casos mais óbvios que falham em substring (MS Excel vs
 * Excel, etc.). Expandir com dados conforme uso real.
 *
 * Mapeia variantes → forma canônica. Usado em ambos os lados (skill da vaga
 * e tokens do CV) — normalize tudo pra forma canônica e compara.
 */
const SYNONYMS: Record<string, string> = {
  'ms excel': 'excel',
  'microsoft excel': 'excel',
  'ms office': 'office',
  'microsoft office': 'office',
  'pacote office': 'office',
  'ms powerpoint': 'powerpoint',
  'power point': 'powerpoint',
  'ppt': 'powerpoint',
  'ms word': 'word',
  'g suite': 'google workspace',
  'google docs': 'google workspace',
  'js': 'javascript',
  'ts': 'typescript',
  'react.js': 'react',
  'reactjs': 'react',
  'node.js': 'node',
  'nodejs': 'node',
  'vue.js': 'vue',
  'vuejs': 'vue',
  'photoshop ps': 'photoshop',
  'adobe photoshop': 'photoshop',
  'adobe illustrator': 'illustrator',
  'adobe xd': 'xd',
  'power bi': 'powerbi',
  'powerbi': 'powerbi',
  'sql server': 'sql',
  'mysql': 'sql',
  'postgres': 'postgresql',
  'postgresql': 'postgresql',
  'ingles': 'inglês',
  'english': 'inglês',
  'espanhol': 'espanhol',
  'spanish': 'espanhol',
}

function canonical(s: string): string {
  const n = normalize(s)
  return SYNONYMS[n] ?? n
}

/**
 * Checa se uma skill está "no CV" do user. Combina 3 estratégias:
 * 1. Match exato canônico contra cada skill estruturada do CV (parsed.skills)
 * 2. Substring no raw_text (flatten — cobre PDF quebrado em linhas)
 * 3. Match canônico (sinônimos) contra parsed.skills
 *
 * NOTA: aceita falsos negativos (skill realmente no CV mas escrita diferente
 * que o map de sinônimos não cobre) — user pode marcar manualmente. Falsos
 * positivos (in_cv: true quando não está) seriam piores porque escondem
 * skills que o user quer confirmar.
 */
function isSkillInCv(skill: string, parsedSkills: string[], rawCvFlat: string): boolean {
  const skillCanon = canonical(skill)
  const skillFlat = flatten(skill)
  if (!skillFlat) return false

  // 1. Match canônico contra parsed.skills
  for (const s of parsedSkills) {
    if (canonical(s) === skillCanon) return true
  }

  // 2. Substring em parsed.skills (cobre "Excel avançado" no CV vs "Excel" na vaga)
  for (const s of parsedSkills) {
    const sFlat = flatten(s)
    if (sFlat && (sFlat.includes(skillFlat) || skillFlat.includes(sFlat))) return true
  }

  // 3. Substring no raw_text
  if (rawCvFlat && rawCvFlat.includes(skillFlat)) return true

  // 4. Match canônico via sinônimos: tenta a versão canonical no raw_text
  if (rawCvFlat && skillCanon !== skillFlat && rawCvFlat.includes(skillCanon)) return true

  return false
}

/** Dedup case-insensitive preservando ordem do primeiro avistamento. */
function dedupCaseInsensitive(arr: string[]): string[] {
  const seen = new Set<string>()
  const out: string[] = []
  for (const s of arr) {
    const k = normalize(s)
    if (!k || seen.has(k)) continue
    seen.add(k)
    out.push(s)
  }
  return out
}

// ────────────────────────────────────────────────────────────────────────────
// Prompt
// ────────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `Você é um extrator de skills de vagas. Sua tarefa: dada a descrição de uma vaga (título + requisitos + descrição), extraia ATÉ ${MAX_SKILLS_OUT} skills/competências ATÔMICAS que o candidato precisa ter.

DEFINIÇÃO DE "ATÔMICA":
- Uma unidade indivisível de habilidade.
- "Excel e Power BI avançados" → ["Excel", "Power BI"] (2 skills atômicas)
- "Comunicação verbal e escrita" → ["Comunicação"] (1 skill — verbal e escrita são modalidades da mesma)
- "Inglês intermediário" → ["Inglês intermediário"] (nível faz parte da skill quando muda o significado)

REGRAS:
1. Cada skill em até 4 palavras (máximo). Prefira 1-2 palavras quando possível.
2. Use português (mesmo idioma da vaga). NÃO traduza.
3. Skills concretas e verificáveis. NÃO inclua "vontade de aprender", "atitude positiva", "dinamismo" etc — são qualidades subjetivas, não skills.
4. NÃO inclua área geral ("Marketing", "Vendas") — só ferramentas, técnicas, idiomas, conhecimentos específicos.
5. Ferramentas/softwares: nome canônico (ex: "Photoshop", "Figma", "SQL", "Excel").
6. Idiomas: incluir nível quando mencionado ("Inglês intermediário", "Espanhol fluente").
7. Para cada skill, indique a "source": "requirements" (veio da lista de requisitos) ou "description" (mencionada na descrição livre).
8. Ordene por relevância: as mais críticas primeiro.

OUTPUT JSON ESTRITO:
{"skills": [{"name": "...", "source": "requirements" | "description"}, ...]}

NÃO retorne nada fora do JSON. NÃO use fences markdown.`

function buildUserPrompt(job: {
  title: string
  area?: string
  requirements: string[]
  description: string
}): string {
  const lines: string[] = []
  lines.push('## VAGA')
  lines.push(`Título: ${job.title}`)
  if (job.area) lines.push(`Área: ${job.area}`)
  if (job.requirements.length > 0) {
    lines.push('')
    lines.push('### Requisitos listados:')
    job.requirements.slice(0, 20).forEach((r) => lines.push(`- ${r}`))
  }
  if (job.description) {
    lines.push('')
    lines.push('### Descrição:')
    lines.push(job.description.slice(0, 2000))
  }
  lines.push('')
  lines.push(`Extraia até ${MAX_SKILLS_OUT} skills atômicas. Retorne APENAS o JSON.`)
  return lines.join('\n')
}

// ────────────────────────────────────────────────────────────────────────────
// OpenAI
// ────────────────────────────────────────────────────────────────────────────

interface AiSkill {
  name: string
  source: 'requirements' | 'description'
}

async function callOpenAI(systemPrompt: string, userPrompt: string): Promise<{
  skills: AiSkill[]
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
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
        temperature: 0.1,
        max_tokens: 500,
        response_format: { type: 'json_object' },
      }),
    })
    if (!resp.ok) {
      const errText = await resp.text()
      throw new Error(`OpenAI ${resp.status}: ${errText.slice(0, 300)}`)
    }
    const data = await resp.json()
    const content = data.choices[0].message.content as string
    const parsed = JSON.parse(content)
    const rawSkills = Array.isArray(parsed.skills) ? parsed.skills : []
    const skills: AiSkill[] = rawSkills.slice(0, MAX_SKILLS_OUT).map((s: any) => ({
      name: String(s?.name ?? '').trim().slice(0, 60),
      source: (s?.source === 'description' ? 'description' : 'requirements') as 'requirements' | 'description',
    })).filter((s: AiSkill) => s.name.length > 0)
    return {
      skills,
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

    // 3. Fetch em paralelo: job + perfil
    const [jobR, profileR] = await Promise.all([
      supabaseClient
        .from('jobs')
        .select('id, title, area, requirements, description')
        .eq('id', jobId)
        .maybeSingle(),
      supabaseClient
        .from('user_profiles')
        .select('gamification_data')
        .eq('id', user.id)
        .maybeSingle(),
    ])
    if (jobR.error || !jobR.data) return jsonResponse({ error: 'job_not_found' }, 404)
    const job = jobR.data
    const gamificationData = profileR.data?.gamification_data ?? {}
    const importedResume = gamificationData?.imported_resume ?? {}
    const parsedSkillsRaw: string[] = Array.isArray(importedResume?.parsed?.skills)
      ? importedResume.parsed.skills.map((s: any) => String(s)).filter(Boolean)
      : []
    const whoIAm = gamificationData?.whoIAm?.derived ?? {}
    if (whoIAm.skills && typeof whoIAm.skills === 'string') {
      whoIAm.skills.split(/[,;\n]/).map((s: string) => s.trim()).filter(Boolean)
        .forEach((s: string) => parsedSkillsRaw.push(s))
    }
    const parsedSkills = dedupCaseInsensitive(parsedSkillsRaw)
    const rawCvFlat = flatten(
      typeof importedResume?.raw_text === 'string'
        ? importedResume.raw_text.slice(0, 8000)
        : '',
    )
    const confirmedSkills: string[] = Array.isArray(gamificationData?.confirmed_skills)
      ? gamificationData.confirmed_skills.map((s: any) => String(s)).filter(Boolean)
      : []
    const confirmedCanon = new Set(confirmedSkills.map((s) => canonical(s)))

    // 4. Cache lookup (por job_id — skills da vaga são as mesmas pra qualquer user)
    const cacheCutoff = new Date(Date.now() - CACHE_TTL_DAYS * 86400_000).toISOString()
    const { data: cachedRow } = await supabaseClient
      .from('jobs_skill_extraction')
      .select('skills, computed_at, prompt_version')
      .eq('job_id', jobId)
      .maybeSingle()

    let extractedSkills: AiSkill[] | null = null
    if (
      cachedRow &&
      cachedRow.prompt_version === PROMPT_VERSION &&
      cachedRow.computed_at >= cacheCutoff &&
      Array.isArray(cachedRow.skills)
    ) {
      extractedSkills = (cachedRow.skills as AiSkill[]).slice(0, MAX_SKILLS_OUT)
    }

    // 5. Cache miss → rate limit + chama OpenAI
    if (!extractedSkills) {
      const today = new Date()
      today.setHours(0, 0, 0, 0)
      const { count: rlCount } = await supabaseClient
        .from('ai_generation_logs')
        .select('*', { count: 'exact', head: true })
        .eq('user_id', user.id)
        .eq('generation_type', 'skill_extraction')
        .gte('created_at', today.toISOString())
      if (rlCount && rlCount >= RATE_LIMIT_PER_DAY) {
        return jsonResponse({
          error: `Rate limit exceeded. Maximum ${RATE_LIMIT_PER_DAY} skill extractions per day.`,
        }, 429)
      }

      const requirements: string[] = Array.isArray(job.requirements) ? job.requirements : []
      const description = String(job.description ?? '')
      // Sem requisitos NEM descrição → não há o que extrair. Retorna vazio sem
      // chamar IA. Frontend trata como "auto-skip".
      if (requirements.length === 0 && description.trim().length < 50) {
        return jsonResponse({
          skills: [],
          total: 0,
          in_cv_count: 0,
        })
      }

      const userPrompt = buildUserPrompt({
        title: String(job.title ?? ''),
        area: job.area ? String(job.area) : undefined,
        requirements,
        description,
      })

      let aiResult
      try {
        aiResult = await callOpenAI(SYSTEM_PROMPT, userPrompt)
        trackAIGeneration({
          userId: user.id,
          generationType: 'skill_extraction',
          model: MODEL,
          inputTokens: aiResult.inputTokens,
          outputTokens: aiResult.outputTokens,
          latencyMs: aiResult.latencyMs,
        }).catch(() => {})
      } catch (e) {
        console.error('OpenAI call failed:', (e as Error).message)
        trackAIGeneration({
          userId: user.id,
          generationType: 'skill_extraction',
          model: MODEL,
          inputTokens: 0,
          outputTokens: 0,
          latencyMs: 0,
          isError: true,
        }).catch(() => {})
        return jsonResponse({ error: 'ai_failed', detail: (e as Error).message.slice(0, 200) }, 502)
      }

      // Dedup canônico (IA pode retornar "React" e "React.js")
      const seen = new Set<string>()
      const deduped: AiSkill[] = []
      for (const s of aiResult.skills) {
        const k = canonical(s.name)
        if (!k || seen.has(k)) continue
        seen.add(k)
        deduped.push(s)
      }
      extractedSkills = deduped

      // 6. Upsert cache + log
      await supabaseClient.from('jobs_skill_extraction').upsert({
        job_id: jobId,
        skills: extractedSkills,
        prompt_version: PROMPT_VERSION,
        model_used: MODEL,
        computed_at: new Date().toISOString(),
      }, { onConflict: 'job_id' })

      await supabaseClient.from('ai_generation_logs').insert({
        user_id: user.id,
        generation_type: 'skill_extraction',
        tokens_used: aiResult.totalTokens,
      })
    }

    // 7. Cruza com CV do user → in_cv + pre_confirmed
    const outSkills = extractedSkills.map((s) => {
      const inCv = isSkillInCv(s.name, parsedSkills, rawCvFlat)
      const preConfirmed = !inCv && confirmedCanon.has(canonical(s.name))
      return {
        name: s.name,
        source: s.source,
        in_cv: inCv,
        pre_confirmed: preConfirmed,
      }
    })

    const inCvCount = outSkills.filter((s) => s.in_cv).length

    return jsonResponse({
      skills: outSkills,
      total: outSkills.length,
      in_cv_count: inCvCount,
    })
  } catch (err) {
    const msg = (err as Error).message || 'unknown'
    console.error('extract-job-skills error:', msg)
    const status = msg.includes('AbortError') || msg.includes('aborted') ? 504 : 500
    return jsonResponse({ error: 'internal', detail: msg.slice(0, 300) }, status)
  }
})
