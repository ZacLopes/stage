// Edge Function: adapt-resume-to-job
//
// Adapta o currículo do usuário para uma vaga específica via GPT-4o-mini.
// PRINCÍPIO FUNDAMENTAL: zero invenção. O modelo só pode REORDENAR,
// REFORMULAR ou ENFATIZAR dados que já estão no input. Nome, email, datas,
// empresas, instituições e diplomas são imutáveis e validados pós-resposta.
//
// Input: { job_id: uuid, force?: boolean }
// Output: {
//   changes: [{ field, label, before, after, reason }, ...],
//   resume_data: { ...mesmo schema que ResumeData no client... },
//   match_score_before?: int,
//   match_score_after?: int,
//   cached: boolean,
//   model_used: string,
// }
//
// Cache: tabela adapted_resumes, único por (user, job). Invalida quando o
// usuário edita perfil ou currículo (via source_hash).
//
// Rate limit: 30 chamadas/dia por user. Cache hits NÃO contam.
// Custo: ~$0.001-0.003 por adaptação real.

import { serve } from 'std/http/server'
import { createClient } from 'supabase'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MODEL = 'gpt-4o-mini'
const PROMPT_VERSION = 'v1'
const RATE_LIMIT_PER_DAY = 30
const OPENAI_TIMEOUT_MS = 25000
const MAX_BULLET_INFLATION = 1.3 // adapt não pode > 1.3x bullets do original

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

/** Normaliza string pra comparação (lower + remove acentos + trim). */
function normalize(s: string | null | undefined): string {
  if (!s) return ''
  return s
    .toLowerCase()
    .trim()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
}

/** True se duas strings batem após normalização. */
function eq(a: string | null | undefined, b: string | null | undefined): boolean {
  return normalize(a) === normalize(b)
}

// ────────────────────────────────────────────────────────────────────────────
// Resume input building (lê do gamification_data + tabelas)
// ────────────────────────────────────────────────────────────────────────────

interface InputExperience {
  role: string
  company: string
  period: string
  description: string // bullets separados por \n
  location?: string
}

interface InputEducation {
  degree: string
  institution: string
  period: string
  details?: string
  location?: string
}

interface InputResume {
  fullName: string
  email: string
  phone: string
  linkedin: string
  location: string
  language: string
  summary: string
  skills: string[]
  experiences: InputExperience[]
  education: InputEducation[]
  achievements: string[]
  interests: string[]
  // Pool de palavras-chave do user (skills + CV importado tokenizado).
  // Usado pra validar que skills sugeridas pelo modelo NÃO foram inventadas.
  keywordPool: Set<string>
  // CV bruto (caso seja a única fonte). Não vai pro prompt cru — só pra
  // construir o keywordPool.
  importedCvText?: string
}

const STOP_WORDS = new Set<string>([
  'a', 'o', 'e', 'de', 'do', 'da', 'dos', 'das', 'em', 'no', 'na', 'um', 'uma',
  'para', 'por', 'com', 'sem', 'que', 'se', 'ou', 'mas', 'ser', 'ter', 'estar',
  'mais', 'menos', 'muito', 'pouco', 'também', 'já', 'sobre', 'após', 'antes',
  'the', 'and', 'or', 'of', 'to', 'in', 'for', 'on', 'at', 'by', 'with', 'as',
  'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
  'will', 'would', 'should', 'could',
])

function tokenize(text: string): string[] {
  if (!text) return []
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .split(/[\s,.;:!?()\[\]{}<>"/\\\-•|]+/)
    .filter((w) => w.length >= 3 && !STOP_WORDS.has(w) && !/^\d+$/.test(w))
}

/**
 * Lê dados do user e monta o InputResume canônico.
 *
 * Sources:
 * - user_profiles.gamification_data.imported_resume.parsed (se vier do parser)
 * - user_profiles.gamification_data.whoIAm.derived (skills/summary/interests)
 * - user_profiles (name, email, etc.)
 *
 * Se o user não tem nada (perfil vazio), retorna null.
 */
function buildInputResume(profile: any): InputResume | null {
  const gd = profile?.gamification_data ?? {}
  const whoIAm = gd?.whoIAm?.derived ?? {}
  const imported = gd?.imported_resume ?? {}
  const parsed = imported?.parsed ?? {}

  const fullName = String(parsed.fullName ?? profile?.name ?? '').trim()
  const email = String(parsed.email ?? profile?.email ?? '').trim()
  const phone = String(parsed.phone ?? profile?.phone ?? '').trim()
  const linkedin = String(parsed.linkedin ?? '').trim()
  const location = String(parsed.location ?? profile?.location ?? '').trim()
  const language = String(parsed.language ?? 'pt')

  // Resumo: prefere o do parser; fallback pro whoIAm.summary.
  const summary = String(parsed.summary ?? whoIAm.summary ?? '').trim().slice(0, 600)

  // Skills: junta as estruturadas (whoIAm) com as do parser, dedup.
  const skillsSet = new Set<string>()
  if (Array.isArray(parsed.skills)) parsed.skills.forEach((s: any) => s && skillsSet.add(String(s).trim()))
  if (whoIAm.skills) {
    String(whoIAm.skills)
      .split(/[,;\n]/)
      .map((s) => s.trim())
      .filter(Boolean)
      .forEach((s) => skillsSet.add(s))
  }
  const skills = Array.from(skillsSet).filter((s) => s.length > 0).slice(0, 30)

  const experiences: InputExperience[] = Array.isArray(parsed.experiences)
    ? parsed.experiences.map((e: any) => ({
        role: String(e?.role ?? '').trim(),
        company: String(e?.company ?? '').trim(),
        period: String(e?.period ?? '').trim(),
        description: String(e?.description ?? '').trim(),
        location: e?.location ? String(e.location).trim() : undefined,
      })).filter((e: InputExperience) => e.role && e.company)
    : []

  const education: InputEducation[] = Array.isArray(parsed.education)
    ? parsed.education.map((e: any) => ({
        degree: String(e?.degree ?? '').trim(),
        institution: String(e?.institution ?? '').trim(),
        period: String(e?.period ?? '').trim(),
        details: e?.details ? String(e.details).trim() : undefined,
        location: e?.location ? String(e.location).trim() : undefined,
      })).filter((e: InputEducation) => e.degree && e.institution)
    : []

  const achievements: string[] = Array.isArray(parsed.achievements)
    ? parsed.achievements.map((a: any) => String(a).trim()).filter(Boolean).slice(0, 10)
    : []

  const interestsRaw = parsed.interests ?? whoIAm.interests
  const interests: string[] = Array.isArray(interestsRaw)
    ? interestsRaw.map((s: any) => String(s).trim()).filter(Boolean)
    : (typeof interestsRaw === 'string'
        ? interestsRaw.split(/[,;\n]/).map((s: string) => s.trim()).filter(Boolean)
        : [])

  // Sanity: pra adaptar com qualidade, precisa ter NOME + alguma fonte de
  // conteúdo (experiência estruturada, skills, resumo, ou CV importado com
  // texto razoável). Só nome do auth não basta — a IA inventaria experiência
  // pra "preencher" e o validador rejeitaria. Melhor falhar cedo com
  // mensagem amigável.
  const rawCvLen = typeof imported.raw_text === 'string' ? imported.raw_text.length : 0
  const hasContent =
    experiences.length > 0 ||
    education.length > 0 ||
    skills.length >= 3 ||
    summary.length >= 50 ||
    rawCvLen >= 500
  const hasMinData = fullName.length > 0 && hasContent
  if (!hasMinData) return null

  // Keyword pool pra validar skills/conteúdo.
  const keywordPool = new Set<string>()
  for (const s of skills) tokenize(s).forEach((t) => keywordPool.add(t))
  for (const e of experiences) {
    tokenize(`${e.role} ${e.company} ${e.description}`).forEach((t) => keywordPool.add(t))
  }
  for (const e of education) {
    tokenize(`${e.degree} ${e.institution} ${e.details ?? ''}`).forEach((t) => keywordPool.add(t))
  }
  for (const a of achievements) tokenize(a).forEach((t) => keywordPool.add(t))
  if (summary) tokenize(summary).forEach((t) => keywordPool.add(t))
  if (typeof imported.raw_text === 'string') {
    tokenize(imported.raw_text.slice(0, 6000)).forEach((t) => keywordPool.add(t))
  }

  return {
    fullName,
    email,
    phone,
    linkedin,
    location,
    language,
    summary,
    skills,
    experiences,
    education,
    achievements,
    interests,
    keywordPool,
    importedCvText: typeof imported.raw_text === 'string' ? imported.raw_text : undefined,
  }
}

function pickInputForHash(input: InputResume): string {
  return JSON.stringify({
    n: input.fullName,
    e: input.email,
    sk: input.skills,
    sm: input.summary,
    ex: input.experiences.map((e) => ({ r: e.role, c: e.company, p: e.period, d: e.description })),
    ed: input.education.map((e) => ({ d: e.degree, i: e.institution, p: e.period })),
    ac: input.achievements,
    cvLen: input.importedCvText?.length ?? 0,
    cvHead: (input.importedCvText ?? '').slice(0, 200),
  })
}

// ────────────────────────────────────────────────────────────────────────────
// Prompt
// ────────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `Você é um especialista em adaptar currículos brasileiros para vagas específicas. Seu trabalho é REORDENAR e REFORMULAR conteúdo para destacar o que é mais relevante pra vaga — NUNCA adicionar informação que não esteja no input.

REGRAS INVIOLÁVEIS:
1. NÃO INVENTE NADA. Se não está nos dados do candidato, NÃO existe.
2. Nome, email, telefone, LinkedIn, localização: copie EXATAMENTE como está.
3. Empresas, cargos, instituições, diplomas, períodos: copie EXATAMENTE.
4. Bullets de experiência: você pode REFORMULAR pra destacar palavras-chave da vaga, mas o FATO descrito tem que vir do bullet original. Não invente métricas, projetos, ou tecnologias que não estavam lá.
5. Skills: você pode REORDENAR (pôr as relevantes pra vaga primeiro) e REMOVER irrelevantes. NÃO pode adicionar skill que não está no pool original.
6. Resumo profissional: pode reescrever pra destacar fit com a vaga, mas só usando informação do input (área de formação, experiências reais, skills reais).
7. ARRAYS VAZIOS PERMANECEM VAZIOS, EXCETO quando há CV bruto: se "Experiências/Skills atuais" estão vazios mas "CV importado (texto bruto)" foi fornecido, EXTRAIA de lá os dados (empresas, cargos, períodos, skills, formação). Se NEM os campos estruturados NEM o CV bruto trazem informação sobre algo, output desse campo = []. NUNCA invente.
8. Quando extrair do CV bruto: copie nomes de empresas, instituições e cargos EXATAMENTE como aparecem no CV. Não traduza, não abrevie. Períodos: copie no formato em que aparecem.
9. Se o input tem pouca informação, retorne o que TEM, sem completar. Currículo curto e honesto > currículo cheio e inventado.

LIMITES:
- Bullets por experiência: no máximo o mesmo número que o original (pode ser menos, nunca mais).
- Skills: máximo 12 (priorize as relevantes pra vaga).
- Mudanças explicáveis (campo "changes"): no máximo 6 — só as mais impactantes. Cada change tem reason curto (≤80 chars).

OUTPUT JSON ESTRITO conforme schema fornecido.

Tom: PT-BR profissional. Bullets em português, método Harvard (verbo no pretérito ou gerúndio + ação + impacto/contexto).`

interface JobContext {
  title: string
  company: string
  area: string
  jobType: string
  workModel: string
  location: string
  description: string
  requirements: string[]
}

function buildUserPrompt(input: InputResume, job: JobContext): string {
  const lines: string[] = []

  lines.push('## CURRÍCULO ORIGINAL DO CANDIDATO (fonte de verdade)')
  lines.push('')
  lines.push('### Dados pessoais (IMUTÁVEIS — copie exato)')
  lines.push(`Nome: ${input.fullName}`)
  if (input.email) lines.push(`Email: ${input.email}`)
  if (input.phone) lines.push(`Telefone: ${input.phone}`)
  if (input.linkedin) lines.push(`LinkedIn: ${input.linkedin}`)
  if (input.location) lines.push(`Localização: ${input.location}`)

  if (input.summary) {
    lines.push('')
    lines.push('### Resumo atual')
    lines.push(input.summary)
  }

  if (input.skills.length > 0) {
    lines.push('')
    lines.push('### Skills atuais (você pode reordenar/remover, NÃO adicionar)')
    lines.push(input.skills.join(' | '))
  }

  if (input.experiences.length > 0) {
    lines.push('')
    lines.push('### Experiências (datas/empresas/cargos IMUTÁVEIS — bullets podem ser reformulados)')
    for (let i = 0; i < input.experiences.length; i++) {
      const e = input.experiences[i]
      lines.push(`[${i}] ${e.role} @ ${e.company} (${e.period}${e.location ? ', ' + e.location : ''})`)
      if (e.description) {
        const bullets = e.description.split('\n').map((b) => b.trim()).filter(Boolean)
        bullets.forEach((b) => lines.push(`    • ${b}`))
      }
    }
  }

  if (input.education.length > 0) {
    lines.push('')
    lines.push('### Formação (IMUTÁVEL)')
    input.education.forEach((e) => {
      lines.push(`- ${e.degree} @ ${e.institution} (${e.period}${e.location ? ', ' + e.location : ''})`)
      if (e.details) lines.push(`  ${e.details}`)
    })
  }

  if (input.achievements.length > 0) {
    lines.push('')
    lines.push('### Conquistas (IMUTÁVEL — pode reordenar/omitir)')
    input.achievements.forEach((a) => lines.push(`- ${a}`))
  }

  if (input.interests.length > 0) {
    lines.push('')
    lines.push(`### Interesses: ${input.interests.join(', ')}`)
  }

  // CV importado bruto: incluímos quando os dados estruturados estão escassos
  // (typical: usuário fez upload de PDF mas não passou pela trilha — então
  // só temos raw_text). O modelo extrai experiências/educação/skills DO TEXTO
  // e adapta. Validador depois confirma que cada item retornado de fato
  // aparece no raw_text (substring normalizada).
  //
  // Quando o usuário TEM dados estruturados, não mandamos raw_text pra evitar
  // diluir o sinal e tentar invenção.
  const hasStructured =
    input.experiences.length > 0 ||
    input.education.length > 0 ||
    input.skills.length > 0
  if (!hasStructured && input.importedCvText && input.importedCvText.length > 100) {
    // Limita a 5000 chars (suficiente pra um CV completo, evita custo alto).
    const cv = input.importedCvText.slice(0, 5000)
    lines.push('')
    lines.push('### CV importado (texto bruto extraído do PDF — fonte de verdade)')
    lines.push('Os dados estruturados estão vazios; extraia experiências, educação e skills DESTE texto. Não invente nada que não esteja aqui.')
    lines.push('---')
    lines.push(cv)
    lines.push('---')
  }

  lines.push('')
  lines.push('## VAGA ALVO')
  lines.push(`Título: ${job.title}`)
  lines.push(`Empresa: ${job.company}`)
  lines.push(`Área: ${job.area}`)
  lines.push(`Tipo: ${job.jobType}`)
  lines.push(`Modelo: ${job.workModel}`)
  if (job.location) lines.push(`Localização: ${job.location}`)
  if (job.requirements.length > 0) {
    lines.push('Requisitos:')
    job.requirements.slice(0, 12).forEach((r) => lines.push(`  - ${r}`))
  }
  if (job.description) {
    lines.push('Descrição (resumida):')
    lines.push(job.description.slice(0, 1500))
  }

  lines.push('')
  lines.push('## TAREFA')
  lines.push(
    'Adapte o currículo do candidato pra essa vaga. Reordene skills colocando as mais relevantes primeiro. Reformule bullets de experiência destacando palavras-chave dos requisitos quando possível (sem inventar). Ajuste o resumo pra puxar pra área da vaga (sem inventar). Liste em "changes" no máximo 6 mudanças (apenas as mais impactantes), cada uma com {field, label, before, after, reason}.',
  )
  lines.push('Retorne APENAS o JSON conforme o schema.')

  return lines.join('\n')
}

// ────────────────────────────────────────────────────────────────────────────
// JSON schema (response_format)
// ────────────────────────────────────────────────────────────────────────────

const JSON_SCHEMA = {
  name: 'adapted_resume',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['changes', 'resume'],
    properties: {
      changes: {
        type: 'array',
        maxItems: 6,
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['field', 'label', 'before', 'after', 'reason'],
          properties: {
            field: { type: 'string' },
            label: { type: 'string' },
            before: { type: 'string' },
            after: { type: 'string' },
            reason: { type: 'string' },
          },
        },
      },
      resume: {
        type: 'object',
        additionalProperties: false,
        required: [
          'fullName', 'email', 'phone', 'linkedin', 'location', 'language',
          'summary', 'skills', 'experiences', 'education', 'achievements', 'interests',
        ],
        properties: {
          fullName: { type: 'string' },
          email: { type: 'string' },
          phone: { type: 'string' },
          linkedin: { type: 'string' },
          location: { type: 'string' },
          language: { type: 'string' },
          summary: { type: 'string' },
          skills: { type: 'array', items: { type: 'string' } },
          experiences: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['role', 'company', 'period', 'description', 'location'],
              properties: {
                role: { type: 'string' },
                company: { type: 'string' },
                period: { type: 'string' },
                description: { type: 'string' },
                location: { type: 'string' },
              },
            },
          },
          education: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['degree', 'institution', 'period', 'details', 'location'],
              properties: {
                degree: { type: 'string' },
                institution: { type: 'string' },
                period: { type: 'string' },
                details: { type: 'string' },
                location: { type: 'string' },
              },
            },
          },
          achievements: { type: 'array', items: { type: 'string' } },
          interests: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  },
} as const

// ────────────────────────────────────────────────────────────────────────────
// OpenAI call
// ────────────────────────────────────────────────────────────────────────────

async function callOpenAI(systemPrompt: string, userPrompt: string): Promise<{
  content: string
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
        temperature: 0.3,
        max_tokens: 2500,
        response_format: { type: 'json_schema', json_schema: JSON_SCHEMA },
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
    }
  } finally {
    clearTimeout(timeout)
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Validador anti-invenção
// ────────────────────────────────────────────────────────────────────────────

class ValidationError extends Error {
  constructor(public field: string, msg: string) {
    super(`${field}: ${msg}`)
  }
}

function bulletCount(description: string): number {
  return description.split('\n').map((s) => s.trim()).filter(Boolean).length
}

/**
 * Garante que a resposta da IA não inventou nada que comprometa a integridade
 * do currículo. Throws ValidationError no primeiro problema encontrado.
 */
function validateAdaptation(input: InputResume, parsed: any): void {
  const r = parsed?.resume
  if (!r || typeof r !== 'object') throw new ValidationError('resume', 'objeto ausente')

  // 1. Dados imutáveis batem 100% (não vazio quando original é não vazio,
  // valor exato quando presente).
  if (input.fullName && !eq(r.fullName, input.fullName)) {
    throw new ValidationError('fullName', `mudou: "${input.fullName}" → "${r.fullName}"`)
  }
  if (input.email && !eq(r.email, input.email)) {
    throw new ValidationError('email', `mudou`)
  }
  if (input.phone && !eq(r.phone, input.phone)) {
    throw new ValidationError('phone', `mudou`)
  }
  if (input.linkedin && !eq(r.linkedin, input.linkedin)) {
    throw new ValidationError('linkedin', `mudou`)
  }
  if (input.location && !eq(r.location, input.location)) {
    throw new ValidationError('location', `mudou`)
  }

  // Modo de validação:
  // - "structured": user tem experiências/educação estruturadas → matching
  //   estrito por (company, role) / (institution, degree).
  // - "cv-only": user só tem raw_text do CV → validamos que cada empresa /
  //   instituição da resposta APARECE como substring (normalizada) no CV.
  //   Isso evita invenção sem exigir parser perfeito.
  const cvNorm = input.importedCvText ? normalize(input.importedCvText) : ''
  const hasStructuredExperiences = input.experiences.length > 0
  const hasStructuredEducation = input.education.length > 0

  // 2. Experiências
  if (!Array.isArray(r.experiences)) {
    throw new ValidationError('experiences', 'não é array')
  }
  if (hasStructuredExperiences) {
    if (r.experiences.length > input.experiences.length) {
      throw new ValidationError(
        'experiences',
        `inventou: ${r.experiences.length} > ${input.experiences.length} originais`,
      )
    }
    for (const exp of r.experiences) {
      const found = input.experiences.find(
        (orig) => eq(orig.company, exp.company) && eq(orig.role, exp.role),
      )
      if (!found) {
        throw new ValidationError(
          'experiences',
          `experiência inventada: "${exp.role}" @ "${exp.company}"`,
        )
      }
      // Período: deve ser exatamente igual (datas não podem mudar).
      if (found.period && !eq(found.period, exp.period)) {
        throw new ValidationError(
          'experiences',
          `período de "${exp.company}" mudou: "${found.period}" → "${exp.period}"`,
        )
      }
      // Bullets: count <= original × MAX_BULLET_INFLATION.
      const origCount = bulletCount(found.description)
      const newCount = bulletCount(exp.description ?? '')
      if (origCount > 0 && newCount > Math.ceil(origCount * MAX_BULLET_INFLATION)) {
        throw new ValidationError(
          'experiences',
          `inflou bullets em "${exp.company}": ${origCount} → ${newCount}`,
        )
      }
    }
  } else if (cvNorm) {
    // Modo CV-only: cada experiência precisa ter empresa que apareça no CV.
    // Cap em 8 experiências (CV típico tem 1-5; 8 é generoso).
    if (r.experiences.length > 8) {
      throw new ValidationError('experiences', `excesso: ${r.experiences.length}`)
    }
    for (const exp of r.experiences) {
      const company = normalize(String(exp.company ?? ''))
      if (!company) continue
      if (!cvNorm.includes(company)) {
        throw new ValidationError(
          'experiences',
          `empresa "${exp.company}" não aparece no CV`,
        )
      }
    }
  } else if (r.experiences.length > 0) {
    // Sem dados estruturados nem CV bruto, qualquer experience é invenção.
    throw new ValidationError('experiences', 'sem fonte de dados')
  }

  // 3. Educação
  if (!Array.isArray(r.education)) {
    throw new ValidationError('education', 'não é array')
  }
  if (hasStructuredEducation) {
    if (r.education.length > input.education.length) {
      throw new ValidationError('education', 'inventou educação')
    }
    for (const ed of r.education) {
      const found = input.education.find(
        (orig) => eq(orig.institution, ed.institution) && eq(orig.degree, ed.degree),
      )
      if (!found) {
        throw new ValidationError(
          'education',
          `educação inventada: "${ed.degree}" @ "${ed.institution}"`,
        )
      }
    }
  } else if (cvNorm) {
    if (r.education.length > 5) {
      throw new ValidationError('education', `excesso: ${r.education.length}`)
    }
    for (const ed of r.education) {
      const inst = normalize(String(ed.institution ?? ''))
      if (!inst) continue
      if (!cvNorm.includes(inst)) {
        throw new ValidationError(
          'education',
          `instituição "${ed.institution}" não aparece no CV`,
        )
      }
    }
  } else if (r.education.length > 0) {
    throw new ValidationError('education', 'sem fonte de dados')
  }

  // 4. Skills: cada skill da resposta tem que estar no input OU no
  //    keyword pool (CV bruto + skills + experiências).
  if (!Array.isArray(r.skills)) throw new ValidationError('skills', 'não é array')
  if (r.skills.length > 15) {
    throw new ValidationError('skills', `excesso: ${r.skills.length} skills`)
  }
  const originalSkillsNorm = new Set(input.skills.map((s) => normalize(s)))
  for (const s of r.skills) {
    const sNorm = normalize(s)
    if (!sNorm) continue
    if (originalSkillsNorm.has(sNorm)) continue
    // Permite se cada token da skill está no pool.
    const tokens = tokenize(s)
    if (tokens.length === 0) continue
    const allInPool = tokens.every((t) => input.keywordPool.has(t))
    if (!allInPool) {
      throw new ValidationError('skills', `skill inventada: "${s}"`)
    }
  }

  // 5. Achievements: subset (case-insensível) ou reformulação que
  //    ainda esteja contida em algum original. Mantemos checagem
  //    leve aqui — não quero rejeitar reformulações legítimas.
  if (Array.isArray(r.achievements) && r.achievements.length > input.achievements.length + 1) {
    throw new ValidationError('achievements', 'inventou conquista')
  }

  // 6. Changes: array com no máximo 6.
  if (!Array.isArray(parsed.changes)) {
    throw new ValidationError('changes', 'não é array')
  }
  if (parsed.changes.length > 6) {
    throw new ValidationError('changes', 'excesso (>6)')
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Match score upgrade (best-effort, sem nova chamada IA)
// ────────────────────────────────────────────────────────────────────────────

/**
 * Estima upgrade de match: conta quantas palavras-chave dos requisitos da
 * vaga aparecem no resume original vs adaptado. Retorna {before, after} de
 * 0 a 100. Heurístico, mas dá um sinal motivacional ao user.
 */
function computeMatchUpgrade(
  input: InputResume,
  adapted: any,
  job: JobContext,
): { before: number; after: number } {
  const reqTokens = new Set<string>()
  for (const r of job.requirements) tokenize(r).forEach((t) => reqTokens.add(t))
  tokenize(job.description).forEach((t) => reqTokens.add(t))
  if (reqTokens.size === 0) return { before: 50, after: 50 }

  function countMatches(skills: string[], experiences: any[], summary: string): number {
    const text = [
      ...skills,
      ...experiences.map((e: any) => `${e.role} ${e.description ?? ''}`),
      summary,
    ].join(' ')
    const tokens = new Set(tokenize(text))
    let n = 0
    for (const t of reqTokens) if (tokens.has(t)) n++
    return n
  }

  const before = countMatches(input.skills, input.experiences, input.summary)
  const after = countMatches(
    adapted.skills ?? [],
    adapted.experiences ?? [],
    adapted.summary ?? '',
  )

  const beforePct = Math.min(100, Math.round((before / reqTokens.size) * 100) + 30)
  const afterPct = Math.min(100, Math.round((after / reqTokens.size) * 100) + 30)
  return { before: beforePct, after: Math.max(afterPct, beforePct) }
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

    // Service role pra escrever em adapted_resumes (RLS bloqueia user).
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // 1. Auth
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
    if (authError || !user) return jsonResponse({ error: 'Unauthorized' }, 401)

    // 2. Parse input
    const body = await req.json().catch(() => ({}))
    const jobId: string | undefined = body?.job_id
    const force: boolean = body?.force === true
    if (!jobId || typeof jobId !== 'string') {
      return jsonResponse({ error: 'job_id required' }, 400)
    }

    // 3. Rate limit (cache hits NÃO contam)
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const { count: rlCount } = await supabaseClient
      .from('ai_generation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .eq('generation_type', 'resume_adaptation')
      .gte('created_at', today.toISOString())

    if (rlCount && rlCount >= RATE_LIMIT_PER_DAY) {
      return jsonResponse(
        { error: `Rate limit exceeded. Maximum ${RATE_LIMIT_PER_DAY} adaptations per day.` },
        429,
      )
    }

    // 4. Fetch em paralelo: job + companies, profile
    const [jobR, profileR] = await Promise.all([
      supabaseClient
        .from('jobs')
        .select('*, companies(name)')
        .eq('id', jobId)
        .maybeSingle(),
      supabaseClient
        .from('user_profiles')
        .select('id, name, email, phone, location, gamification_data')
        .eq('id', user.id)
        .maybeSingle(),
    ])

    if (jobR.error || !jobR.data) return jsonResponse({ error: 'job_not_found' }, 404)

    const jobRow = jobR.data
    const job: JobContext = {
      title: String(jobRow.title ?? ''),
      company: String(jobRow.companies?.name ?? ''),
      area: String(jobRow.area ?? ''),
      jobType: String(jobRow.job_type ?? ''),
      workModel: String(jobRow.work_model ?? ''),
      location: [jobRow.location_city, jobRow.location_state].filter(Boolean).join(', '),
      description: String(jobRow.description ?? ''),
      requirements: Array.isArray(jobRow.requirements) ? jobRow.requirements : [],
    }

    // user_profiles é criado on-demand pelo Flutter (getUserProfile cria se
    // não existe). User pode ter logado e ido direto pra Vagas sem disparar
    // essa criação. Em vez de falhar com 404 técnico, montamos um perfil
    // mínimo a partir de auth.users e deixamos buildInputResume decidir se
    // tem dados suficientes — caindo no friendly "profile_incomplete".
    const profileFallback = profileR.data ?? {
      id: user.id,
      name: user.user_metadata?.name ?? '',
      email: user.email ?? '',
      phone: user.user_metadata?.phone ?? '',
      location: '',
      gamification_data: {},
    }

    const input = buildInputResume(profileFallback)
    if (!input) {
      return jsonResponse(
        {
          error: 'profile_incomplete',
          detail: 'Complete seu perfil ou suba seu currículo antes de adaptar.',
        },
        422,
      )
    }

    // 5. Cache lookup
    const sourceHash = await sha256Hex(pickInputForHash(input) + '|' + jobId)

    if (!force) {
      const { data: cachedRow } = await supabaseAdmin
        .from('adapted_resumes')
        .select('changes, resume_data, match_score_before, match_score_after, source_hash, prompt_version, model_used')
        .eq('user_id', user.id)
        .eq('job_id', jobId)
        .maybeSingle()

      if (
        cachedRow &&
        cachedRow.source_hash === sourceHash &&
        cachedRow.prompt_version === PROMPT_VERSION
      ) {
        return jsonResponse({
          changes: cachedRow.changes,
          resume_data: cachedRow.resume_data,
          match_score_before: cachedRow.match_score_before,
          match_score_after: cachedRow.match_score_after,
          cached: true,
          model_used: cachedRow.model_used,
        })
      }
    }

    // 6. Call OpenAI
    const userPrompt = buildUserPrompt(input, job)
    const ai = await callOpenAI(SYSTEM_PROMPT, userPrompt)

    let parsed: any
    try {
      parsed = JSON.parse(ai.content)
    } catch (_e) {
      console.error('Failed to JSON.parse AI output:', ai.content.slice(0, 500))
      return jsonResponse({ error: 'ai_response_invalid', detail: 'JSON parse failed' }, 502)
    }

    // 7. VALIDAÇÃO ANTI-INVENÇÃO
    try {
      validateAdaptation(input, parsed)
    } catch (e) {
      const ve = e as ValidationError
      console.warn(`adaptation rejected for user=${user.id} job=${jobId}: ${ve.message}`)
      return jsonResponse(
        {
          error: 'adaptation_rejected',
          detail: 'A adaptação não passou na verificação de integridade. Tente novamente.',
          field: ve.field,
        },
        422,
      )
    }

    // 8. Match score upgrade (heurístico)
    const matchUpgrade = computeMatchUpgrade(input, parsed.resume, job)

    // 9. Persiste cache (service role bypassa RLS)
    await supabaseAdmin.from('adapted_resumes').upsert(
      {
        user_id: user.id,
        job_id: jobId,
        changes: parsed.changes,
        resume_data: parsed.resume,
        match_score_before: matchUpgrade.before,
        match_score_after: matchUpgrade.after,
        source_hash: sourceHash,
        prompt_version: PROMPT_VERSION,
        model_used: MODEL,
        computed_at: new Date().toISOString(),
      },
      { onConflict: 'user_id,job_id' },
    )

    await supabaseClient.from('ai_generation_logs').insert({
      user_id: user.id,
      generation_type: 'resume_adaptation',
      tokens_used: ai.totalTokens,
    })

    return jsonResponse({
      changes: parsed.changes,
      resume_data: parsed.resume,
      match_score_before: matchUpgrade.before,
      match_score_after: matchUpgrade.after,
      cached: false,
      model_used: MODEL,
    })
  } catch (err) {
    const msg = (err as Error).message || 'unknown'
    console.error('adapt-resume-to-job error:', msg)
    const status = msg.includes('AbortError') || msg.includes('aborted') ? 504 : 500
    return jsonResponse({ error: 'internal', detail: msg.slice(0, 300) }, status)
  }
})
