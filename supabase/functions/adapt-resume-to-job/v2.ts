// adapt-resume-to-job — V2 (Semana 3 Bloco C)
//
// Path paralelo que lê do schema relacional `profile_*` em vez de
// `gamification_data` JSONB. Mantém v1 intocado em `index.ts` — a serve()
// principal decide qual path usar via `isV2EnabledForUser`.
//
// Decisões de design (acordadas com founder em 2026-05-23):
//
// 1. Feature flag SERVER-SIDE. Cliente não decide v1/v2 — apenas chama o
//    endpoint. Servidor consulta `app_feature_flags` + computa hash do
//    user_id (SHA-256 → primeiro byte → mod 100) consistente entre runs.
//    Vantagem: fonte única, instant kill switch via SQL update.
//
// 2. Output mantém `description: string` (backward compat com templates
//    v1) MAS adiciona `bullets: AdaptedBullet[]` por experience com
//    `_source_bullet_id` (uuid do profile_bullets ou null se sintetizado)
//    + `_action` ('kept' | 'rewritten' | 'synthesized'). Hallucination
//    detection vira filter no client: `bullets.filter(b => b._action ===
//    'synthesized')`. `description` é derivado server-side do `bullets[]`
//    pra garantir consistência.
//
// 3. PROMPT_VERSION v2 = 'v15-v2'. Cache em `adapted_resumes` discrimina
//    v1 vs v2 via `prompt_version`. Flip do flag → próxima leitura
//    recalcula. Custo aceito pelo founder (~$4 ao longo do rollout).
//
// 4. Fallback automático ao v1: se `profile_personal IS NULL` OU
//    `(experiences.length === 0 && education.length === 0)`, retornamos
//    null no loader e o serve() cai pra v1. Mesma regra do
//    ProfilePdfData.load (consistência intencional).

import { createClient } from 'supabase'
import {
  eqInstitutional,
  flatten,
  jaroWinklerSimilarity,
  normalize,
  tokenize,
} from '../_shared/cv_text.ts'
import { captureEvent, trackAIGeneration } from '../_shared/posthog.ts'

// ────────────────────────────────────────────────────────────────────────────
// Constants
// ────────────────────────────────────────────────────────────────────────────

// v15.1-v2 (2026-05-23): reforça regra de cardinalidade exata de experiences/
// education. GPT estava inventando experiences extras em CVs onde
// extract-profile só conseguiu pegar 1 (CV do Gabriel: 1 exp em prof_*,
// 3.901 chars em raw_text). Sem bump no cache rows v2 ainda é 0.
// v15.2-v2 (2026-05-24): preserva idioma do input (detectCvLanguage server-side).
// Antes hardcoded em PT-BR — GPT traduzia CVs em inglês violando validador
// anti-invenção. + valida tamanho do bullet rewritten em vez de palavra-por-palavra.
// v15.3-v2 (2026-05-24): user prompt INTEIRO no idioma detectado. Antes só o
// header dizia "OUTPUT LANGUAGE: English" mas resto do prompt em PT — GPT
// pegava o tom PT e traduzia. Headers + TAREFA + CHECKLIST agora em EN
// quando input é EN (e equivalente PT quando PT). Sem sinal misto.
// v16-v2 (2026-05-24): expansão massiva do schema input/output (Tier 1 do
// plano "1000x melhor"). InputResumeV2 agora carrega education completa
// (gpa, majors, minors, activities), languages, tools, streetAddress,
// headline, linkedin. JSON_SCHEMA_V2 retorna esses campos. Prompts EN/PT
// listam tudo + checklist exige preservação. Validador exige preservação
// anti-invenção em cada nova seção. Resolve issues do CV Gabriel: LinkedIn,
// GPA 8.9, Minor, Class Rep, Languages, Tools.
// v27-v2: Phase 2 do sistema adaptativo. Detecta densidade do perfil
// (small/medium/large) via counts diretos do profile relacional e
// ramifica TRIM RULE + CONCISION RULE + SUMMARY OUTPUT em 3 variantes:
//   - small:  SEM trim, summary verboso (4-5 frases, ~400 chars),
//             certs verbosas. Fillers ("comprehensive", "throughout
//             the year") ficam pra preencher página com elegância.
//   - medium: TRIM moderado, summary 3-4 frases (~320 chars), certs OK.
//   - large:  TRIM agressivo (atual), summary 3 frases (~240 chars),
//             concision em certs >70 chars. Aperta pra caber 1 página.
// Server-side detection — client não envia hint (mais robusto).
// Combina com Phase 1 (loop adaptativo client-side de CSS tiers).
// v26-v2: SUMMARY OUTPUT max 3 sentences (~240 chars). Antes summary
// gerava 4 linhas no PDF A4 10pt, deixando 1 linha extra de overflow.
// Drop conectores redundantes ("Experience in" → "experience in",
// "Leadership experience in X" se X já coberto por experience entry).
// v25-v2: encurta TRIM RULE e CONCISION RULE em ~50% — v24 fez prompt
// crescer pra 12K chars causando timeout 50s no OpenAI. Mesmas regras
// (preserve facts, drop fillers), mas em texto mais compacto. Combinado
// com timeout 50→75s no index.ts.
// v24-v2: TRIM RULE em bullets/summary. GPT remove fillers ("comprehensive",
// "detailed", "throughout the year", "showcasing analytical capabilities")
// preservando todos os fatos (verbos, números, nomes próprios, lugares,
// tech). Target: bullets 1-2 linhas em A4 11pt. Action=kept fica intacto.
// v23-v2: CONCISION RULE nas certifications. Se cert >70 chars, GPT encurta
// preservando institution+program core+year+location, removendo qualifiers
// redundantes ("In-person executive program, held in", "Online course",
// etc). Sem mexer em conteúdo factual. Economia ~1 linha por cert longo.
// v22-v2: refator do validator de skills — usa CONTAGEM (unmatched <=
// extraSkills.length) em vez de token overlap + whitelist.
// v21-v2: validator aceita traduções de extra_skills (token overlap + whitelist) — quebrava em pares sem overlap.
// v20-v2: refina instrução de tradução das extra_skills (BEFORE add, BOTH skills+summary).
// v19-v2: extra_skills em PT traduzidas pro idioma do CV (tentativa 1).
// v18-v2: períodos formatados no idioma do CV (Aug/Dec em EN, Ago/Dez em PT).
// v17-v2: injeta `language` no resume_data output (fix mistura PT/EN no PDF).
// v16-v2: prompt v2 baseline com preservação de Languages/Tools/Education
// detalhada (gpa, majors, minors, activities, linkedin, streetAddress).
import { experienceClaimMessage, findUnsupportedExperienceClaims } from './experience_claim.ts'

// v28-v2 (02/08/2026): "Changes: máximo 6" virou teto explícito com proibição
// de registrar não-mudanças — o modelo vinha completando a cota com entradas
// cujo before == after. Bump obriga recomputo do cache (R5), que aqui é o
// efeito desejado: os 31 currículos já adaptados regeneram sem o inflado.
export const PROMPT_VERSION_V2 = 'v28-v2'
export const MODEL_V2_DRAFT = 'gpt-4o-mini'
export const MODEL_V2_REFINE = 'gpt-4o'

// ────────────────────────────────────────────────────────────────────────────
// Feature flag gating (server-side)
// ────────────────────────────────────────────────────────────────────────────

/**
 * SHA-256(user_id) → bucket 0..99. Determinístico e estável entre sessões.
 * Não é o mesmo hash que `FeatureFlagsService` do Flutter (que usa
 * `String.hashCode`) — adapt_v2 é decidido SÓ server-side, então não
 * precisa sincronizar. Templates_v2 fica client-only.
 */
async function userBucket(userId: string): Promise<number> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(userId))
  const bytes = new Uint8Array(buf)
  // 4 bytes → uint32 → mod 100 (mantém positivo via & 0x7FFFFFFF)
  const n = ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) >>> 0
  return (n & 0x7FFFFFFF) % 100
}

/**
 * Decide se este user entra no rollout v2. Lê tabela `app_feature_flags`
 * (chave `adapt_v2_enabled`) e compara o bucket do user com `rollout_pct`.
 *
 * Falha silenciosa: se a query falhar ou a flag não existir, retorna
 * `false` (cai pro v1). Failure-safe.
 */
export async function isV2EnabledForUser(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
): Promise<boolean> {
  try {
    const { data } = await supabaseAdmin
      .from('app_feature_flags')
      .select('enabled, rollout_pct')
      .eq('feature_key', 'adapt_v2_enabled')
      .maybeSingle()
    if (!data) return false
    const enabled = data.enabled === true
    const pct = typeof data.rollout_pct === 'number' ? data.rollout_pct : 0
    if (!enabled) return false
    if (pct >= 100) return true
    if (pct <= 0) return false
    const bucket = await userBucket(userId)
    return bucket < pct
  } catch (_e) {
    return false
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Profile loader (schema relacional)
// ────────────────────────────────────────────────────────────────────────────

export interface ProfileRelational {
  personal: any // profile_personal row
  experiences: Array<any & { profile_bullets: any[] }>
  education: Array<any & {
    profile_education_majors: any[]
    profile_education_minors: any[]
    profile_education_activities: any[]
  }>
  languages: any[]
  skills: any[]
  certifications: any[]
  projects: Array<any & { profile_project_bullets: any[] }>
  interests: any[]
  awards: any[]
}

/**
 * Carrega 9 tabelas relacionais em paralelo via service-role (RLS
 * bypassed). Retorna `null` quando o perfil estruturado está vazio
 * (sem `profile_personal` OU sem experiences+education) — caller deve
 * cair pra v1.
 *
 * Mesmo critério usado por `ProfilePdfData.load` no Flutter.
 */
export async function loadProfileV2(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
): Promise<ProfileRelational | null> {
  const personalR = await supabaseAdmin
    .from('profile_personal')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle()
  if (personalR.error || !personalR.data) {
    console.log(`[adapt-v2] no profile_personal for user=${userId.slice(0, 8)} → fallback v1`)
    return null
  }

  const [expR, eduR, langR, skillR, certR, projR, intR, awdR] = await Promise.all([
    supabaseAdmin.from('profile_experiences')
      .select('*, profile_bullets(*)')
      .eq('user_id', userId)
      .order('order_index'),
    supabaseAdmin.from('profile_education')
      .select('*, profile_education_majors(*), profile_education_minors(*), profile_education_activities(*)')
      .eq('user_id', userId)
      .order('order_index'),
    supabaseAdmin.from('profile_languages').select('*').eq('user_id', userId).order('order_index'),
    supabaseAdmin.from('profile_skills').select('*').eq('user_id', userId).order('order_index'),
    supabaseAdmin.from('profile_certifications').select('*').eq('user_id', userId).order('order_index'),
    supabaseAdmin.from('profile_projects')
      .select('*, profile_project_bullets(*)')
      .eq('user_id', userId)
      .order('order_index'),
    supabaseAdmin.from('profile_interests').select('*').eq('user_id', userId).order('order_index'),
    supabaseAdmin.from('profile_awards').select('*').eq('user_id', userId).order('order_index'),
  ])

  const experiences = expR.data ?? []
  const education = eduR.data ?? []
  const projects = projR.data ?? []

  // Critério de "tem material narrativo suficiente pra adaptar CV":
  // exige experiência OU projeto OU educação (com ou sem conteúdo
  // descritivo — IA pode sintetizar bullets a partir de degree+major).
  // Skills/summary/interests isolados NÃO bastam — adaptação reescreve
  // bullets e sem bullets a IA não tem o que reformular.
  //
  // Calouros sem experiência prévia podem cadastrar projetos pessoais/
  // acadêmicos (profile_projects) pra entrar no v2 path. Antes do
  // 2026-05-26 só exp+edu eram aceitos, deixando calouros caindo no v1
  // legacy (que retornava profile_incomplete por raw_text vazio).
  if (experiences.length === 0 && education.length === 0 && projects.length === 0) {
    console.log(`[adapt-v2] empty profile (no exp+edu+proj) for user=${userId.slice(0, 8)} → fallback v1`)
    return null
  }

  return {
    personal: personalR.data,
    experiences,
    education,
    languages: langR.data ?? [],
    skills: skillR.data ?? [],
    certifications: certR.data ?? [],
    projects,
    interests: intR.data ?? [],
    awards: awdR.data ?? [],
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Input shape (rica em IDs pra preservar referências aos bullets originais)
// ────────────────────────────────────────────────────────────────────────────

export interface InputBulletV2 {
  id: string // uuid do profile_bullets — é o que GPT precisa preservar
  text: string
}

export interface InputExperienceV2 {
  id: string
  role: string
  company: string
  period: string
  location: string
  bullets: InputBulletV2[]
}

export interface InputEducationV2 {
  id: string
  degree: string
  institution: string
  period: string
  location: string
  // Detalhes acadêmicos PRESERVADOS (Tier 1 — antes v2 só lia majors[0]).
  // Cada um vira validação anti-invenção: GPT não pode inventar GPA, e
  // se input tem Minor, output DEVE ter o mesmo Minor.
  majors: string[]      // ex: ["Business Administration"]
  minors: string[]      // ex: ["Finance & Entrepreneurship"]
  activities: string[]  // ex: ["Class Representative", "Honors..."]
  gpa: string           // ex: "8.9/10.0" ou "8.9" ou "" se ausente
}

export interface InputLanguageV2 {
  name: string         // "English", "Portuguese"
  proficiency: string  // "Native", "Fluent", "Advanced", "Intermediate", "Basic"
}

export interface InputResumeV2 {
  userId: string
  fullName: string
  email: string
  phone: string
  linkedin: string
  location: string       // city, state, country (resumido)
  streetAddress: string  // rua + bairro completo (preservado separado pra header)
  headline: string       // 1-line summary que aparece sob o nome (ex: "Business Admin student preparing for IB career")
  language: string
  summary: string
  skills: string[]       // técnicas (Accounting, Corporate Finance...)
  tools: string[]        // tools/programs separados (MS Office, Power BI...)
  experiences: InputExperienceV2[]
  education: InputEducationV2[]
  languages: InputLanguageV2[]
  achievements: string[]
  interests: string[]
  certifications: string[]
  // keywordPool pro validador anti-invenção
  keywordPool: Set<string>
}

function formatMonthYear(d: Date, lang: 'pt' | 'en'): string {
  const monthsPt = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
                    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez']
  const monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
  const months = lang === 'en' ? monthsEn : monthsPt
  return `${months[d.getMonth()]} ${d.getFullYear()}`
}

function periodFromExp(exp: any, lang: 'pt' | 'en'): string {
  if (!exp.start_date) return ''
  const s = formatMonthYear(new Date(exp.start_date), lang)
  const current = lang === 'en' ? 'Present' : 'Atual'
  if (exp.is_current) return `${s} - ${current}`
  if (!exp.end_date) return s
  return `${s} - ${formatMonthYear(new Date(exp.end_date), lang)}`
}

function periodFromEdu(edu: any, lang: 'pt' | 'en'): string {
  const current = lang === 'en' ? 'Present' : 'Atual'
  const s = edu.start_date ? formatMonthYear(new Date(edu.start_date), lang) : ''
  const e = edu.end_date ? formatMonthYear(new Date(edu.end_date), lang) : current
  if (!s) return e
  return `${s} - ${e}`
}

function fullName(p: any): string {
  const f = (p.first_name ?? '').trim()
  const l = (p.last_name ?? '').trim()
  if (!f && !l) return ''
  return [f, l].filter(Boolean).join(' ')
}

/**
 * Detecta idioma do CV de forma robusta. Vasculha bullets + summary +
 * headline somando sinais de PT-BR (acentos + endings -ção/-mente/-ões)
 * vs EN (endings -tion/-ness/-ly + artigos "the"/"and"/"of"). Default
 * PT quando ambíguo (maioria dos users do Stage é Brasil).
 */
function detectCvLanguage(opts: {
  summary?: string
  headline?: string
  bullets: string[]
}): 'pt' | 'en' {
  const corpus = [
    opts.summary ?? '',
    opts.headline ?? '',
    ...opts.bullets,
  ].join(' ').toLowerCase()
  if (corpus.length < 50) return 'pt' // sem dado suficiente → default

  let ptScore = 0
  let enScore = 0

  // Acentos PT-BR (raríssimos em inglês)
  const accentMatches = corpus.match(/[ãõçéáíóúâêô]/g)
  if (accentMatches) ptScore += accentMatches.length * 2

  // Endings PT
  const ptEndings = corpus.match(/\b\w+(ção|ções|mente|dade|agem)\b/g)
  if (ptEndings) ptScore += ptEndings.length * 3

  // Endings EN
  const enEndings = corpus.match(/\b\w+(tion|ness|ment|ity|ive|ize)\b/g)
  if (enEndings) enScore += enEndings.length * 3

  // Artigos/preposições EN comuns
  const enWords = corpus.match(/\b(the|and|with|through|across|during|for|of)\b/g)
  if (enWords) enScore += enWords.length

  // Artigos/preposições PT comuns
  const ptWords = corpus.match(/\b(da|do|dos|das|por|com|para|através|durante|que|uma|um)\b/g)
  if (ptWords) ptScore += ptWords.length

  return enScore > ptScore ? 'en' : 'pt'
}

function formatLocation(p: any): string {
  // Deduplica city == state (case-insensitive). Comum em cidades-estado
  // brasileiras como São Paulo (city) + São Paulo (state). Evita output
  // tipo "São Paulo, São Paulo, Brazil" no header do CV adaptado.
  const parts = [p.location_city, p.location_state, p.location_country]
    .map((x) => (x ? String(x).trim() : ''))
    .filter((x) => x.length > 0)
  const seen = new Set<string>()
  const dedup: string[] = []
  for (const part of parts) {
    const key = part.toLowerCase()
    if (seen.has(key)) continue
    seen.add(key)
    dedup.push(part)
  }
  return dedup.join(', ')
}

// Categorias que vira "tools" (separado de skills técnicas). extract-profile
// preenche profile_skills.category quando classifica tools/programs.
const TOOL_CATEGORIES = new Set([
  'tool', 'tools', 'program', 'programs', 'programa', 'programas',
  'software', 'application', 'applications', 'apps',
])

/** Converte enum 'native'/'fluent'/... no label localizado pro idioma. */
function proficiencyLabel(p: string | null | undefined, language: 'pt' | 'en'): string {
  const k = (p ?? '').toLowerCase().trim()
  const ptLabels: Record<string, string> = {
    native: 'Nativo',
    fluent: 'Fluente',
    advanced: 'Avançado',
    intermediate: 'Intermediário',
    basic: 'Básico',
  }
  const enLabels: Record<string, string> = {
    native: 'Native',
    fluent: 'Fluent',
    advanced: 'Advanced',
    intermediate: 'Intermediate',
    basic: 'Basic',
  }
  const map = language === 'pt' ? ptLabels : enLabels
  return map[k] ?? ''
}

/**
 * Converte ProfileRelational → InputResumeV2 com bullet IDs preservados.
 * Cada bullet vira `{id, text}` e o GPT é instruído a referenciar o `id`
 * no output (`_source_bullet_id`). Bullets sintetizados terão
 * `_source_bullet_id: null` + `_action: 'synthesized'`.
 */
export function buildInputResumeV2(profile: ProfileRelational): InputResumeV2 {
  const p = profile.personal

  // Separa skills "técnicas" de tools/programs. Antes de Tier 1 tudo virava
  // skills, perdendo a seção "Tools" do CV (Microsoft Office, Power BI etc).
  const skillsAll = profile.skills.map((s) => ({
    name: ((s.name as string) ?? '').trim(),
    category: ((s.category as string) ?? '').toLowerCase().trim(),
  })).filter((s) => s.name.length > 0)

  const tools: string[] = skillsAll
    .filter((s) => TOOL_CATEGORIES.has(s.category))
    .map((s) => s.name)
  const skillNames: string[] = skillsAll
    .filter((s) => !TOOL_CATEGORIES.has(s.category))
    .map((s) => s.name)

  // Detecta idioma ANTES de formatar periods (precisa propagar pro
  // formatMonthYear). Pra detectar, coletamos os bullets crus do profile
  // sem ainda transformá-los em InputBulletV2 — só precisamos do texto.
  const rawBullets: string[] = []
  for (const exp of profile.experiences) {
    for (const b of (exp.profile_bullets as any[] ?? [])) {
      if (b && typeof b.text === 'string' && b.text.trim().length > 0) {
        rawBullets.push(b.text.trim())
      }
    }
  }
  const language: 'pt' | 'en' = detectCvLanguage({
    summary: p.summary as string | undefined,
    headline: p.headline as string | undefined,
    bullets: rawBullets,
  })

  const experiences: InputExperienceV2[] = profile.experiences.map((exp) => ({
    id: exp.id as string,
    role: (exp.title as string) ?? '',
    company: (exp.company as string) ?? '',
    period: periodFromExp(exp, language),
    location: (exp.location as string) ?? '',
    bullets: ((exp.profile_bullets as any[]) ?? [])
      .filter((b) => b && typeof b.text === 'string' && b.text.trim().length > 0)
      .sort((a, b) => (a.order_index ?? 0) - (b.order_index ?? 0))
      .map((b) => ({ id: b.id as string, text: (b.text as string).trim() })),
  }))

  // Education COMPLETA — majors, minors, activities, gpa (Tier 1.1).
  // Antes só era enviado majors[0]; agora o GPT recebe tudo e o validador
  // exige preservação anti-invenção.
  const education: InputEducationV2[] = profile.education.map((edu) => {
    const sortOI = <T extends { order_index?: number | null }>(arr: T[]) =>
      arr.slice().sort((a, b) => (a.order_index ?? 0) - (b.order_index ?? 0))
    const majors = sortOI((edu.profile_education_majors as any[]) ?? [])
      .map((m) => (m.name as string).trim()).filter(Boolean)
    const minors = sortOI((edu.profile_education_minors as any[]) ?? [])
      .map((m) => (m.name as string).trim()).filter(Boolean)
    const activities = sortOI((edu.profile_education_activities as any[]) ?? [])
      .map((a) => (a.text as string).trim()).filter(Boolean)
    const gpaNum = edu.gpa
    const maxNum = edu.max_gpa
    const gpa = gpaNum != null
      ? (maxNum != null ? `${gpaNum}/${maxNum}` : String(gpaNum))
      : ''
    return {
      id: edu.id as string,
      degree: (edu.degree as string) ?? '',
      institution: (edu.institution as string) ?? '',
      period: periodFromEdu(edu, language),
      location: (edu.location as string) ?? '',
      majors,
      minors,
      activities,
      gpa,
    }
  })

  // Languages (Tier 1.1) — antes loadProfileV2 carregava mas
  // buildInputResumeV2 ignorava, dropando idiomas no fluxo.
  const languages: InputLanguageV2[] = (profile.languages ?? [])
    .filter((l: any) => l && typeof l.name === 'string' && l.name.trim().length > 0)
    .map((l: any) => ({
      name: (l.name as string).trim(),
      proficiency: proficiencyLabel(l.proficiency as string, language),
    }))

  // Certifications formato Harvard ("Nome - Issuer - Ano")
  const certifications: string[] = profile.certifications.map((c) => {
    const name = (c.name as string) ?? ''
    const issuer = (c.issuer as string) ?? ''
    const year = c.date ? new Date(c.date).getFullYear().toString() : ''
    return [name, issuer, year].filter(Boolean).join(' - ')
  })

  // Achievements: projects + awards agregados pro shape v1
  const achievements: string[] = []
  for (const pr of profile.projects) {
    const name = (pr.name as string) ?? ''
    const role = (pr.role as string) ?? ''
    if (!name) continue
    achievements.push(role ? `${name} — ${role}` : name)
  }
  for (const aw of profile.awards) {
    const name = (aw.name as string) ?? ''
    if (name) achievements.push(name)
  }

  const interests: string[] = profile.interests
    .map((i) => (i.name as string).trim())
    .filter(Boolean)

  // KeywordPool pra validador. Inclui skills, tools, summary, headline,
  // bullets, names próprios, education details, languages.
  const keywordPool = new Set<string>()
  const feed = (s: string | null | undefined) => {
    if (!s) return
    tokenize(s).forEach((t) => keywordPool.add(t))
  }
  feed(p.summary)
  feed(p.headline)
  skillNames.forEach(feed)
  tools.forEach(feed)
  interests.forEach(feed)
  for (const exp of experiences) {
    feed(exp.role); feed(exp.company); feed(exp.location)
    exp.bullets.forEach((b) => feed(b.text))
  }
  for (const edu of education) {
    feed(edu.degree); feed(edu.institution); feed(edu.location); feed(edu.gpa)
    edu.majors.forEach(feed)
    edu.minors.forEach(feed)
    edu.activities.forEach(feed)
  }
  for (const lang of languages) { feed(lang.name); feed(lang.proficiency) }
  certifications.forEach(feed)
  achievements.forEach(feed)

  // Phone format — preserva formatação se vier do extract-profile (Tier 3.1).
  // Pre-Tier 3: extract-profile faz .replace(/\D/g, '') em phone_number, então
  // aqui vai vir só dígitos. Pós-Tier 3.1: pode vir com parênteses/hífens.
  const cc = (p.phone_country_code ?? '').trim()
  const num = (p.phone_number ?? '').trim()
  const phone = cc && num ? `${cc} ${num}` : (cc || num)

  return {
    userId: p.user_id as string,
    fullName: fullName(p),
    email: (p.email as string) ?? '',
    phone,
    // Pre-Tier 2.4: profile_personal não tem coluna linkedin_url. Pós-migration:
    // ler `p.linkedin_url`. Hoje mantém vazio (Tier 2 popula).
    linkedin: ((p as any).linkedin_url as string ?? '').trim(),
    location: formatLocation(p),
    streetAddress: ((p.location_street_address as string) ?? '').trim(),
    headline: ((p.headline as string) ?? '').trim(),
    language,
    summary: (p.summary as string) ?? '',
    skills: skillNames,
    tools,
    experiences,
    education,
    languages,
    achievements,
    interests,
    certifications,
    keywordPool,
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Hashing pra cache (mesma estratégia do v1 — campos canônicos do input)
// ────────────────────────────────────────────────────────────────────────────

function normH(s: string | null | undefined): string {
  return normalize(s ?? '').replace(/\s+/g, ' ').trim()
}

export function pickInputForHashV2(input: InputResumeV2): string {
  return JSON.stringify({
    fullName: normH(input.fullName),
    email: normH(input.email),
    linkedin: normH(input.linkedin),
    streetAddress: normH(input.streetAddress),
    headline: normH(input.headline),
    summary: normH(input.summary),
    skills: input.skills.map(normH).sort(),
    tools: input.tools.map(normH).sort(),
    expIds: input.experiences.map((e) => e.id).sort(),
    bulletIds: input.experiences.flatMap((e) => e.bullets.map((b) => b.id)).sort(),
    eduIds: input.education.map((e) => e.id).sort(),
    eduDetails: input.education.map((e) => ({
      majors: e.majors.map(normH).sort(),
      minors: e.minors.map(normH).sort(),
      activities: e.activities.map(normH).sort(),
      gpa: normH(e.gpa),
    })),
    languages: input.languages
      .map((l) => `${normH(l.name)}:${normH(l.proficiency)}`)
      .sort(),
    certs: input.certifications.map(normH).sort(),
    interests: input.interests.map(normH).sort(),
  })
}

// ────────────────────────────────────────────────────────────────────────────
// Prompt + JSON schema v2
// ────────────────────────────────────────────────────────────────────────────

export const SYSTEM_PROMPT_V2 = `Você adapta currículos brasileiros pra vagas específicas. Sua tarefa: REORDENAR e REFORMULAR conteúdo destacando o que é relevante pra vaga. NUNCA adicione informação que não esteja no input.

REGRAS INVIOLÁVEIS:
1. NÃO INVENTE NADA. Se não está nos dados do candidato, NÃO existe.
2. Nome, email, telefone, LinkedIn, localização: copie EXATAMENTE.
3. Empresas, cargos, instituições, diplomas, períodos: copie EXATAMENTE.
4. Skills: pode REORDENAR e REMOVER. Não pode ADICIONAR skill fora do pool.
5. Resumo profissional: pode reescrever pra destacar fit, só com informação do input.
6. Cada substantivo concreto no resumo (área, tecnologia, ferramenta, indústria, idioma) precisa aparecer textualmente no input.
7. NÃO TRADUZA O CURRÍCULO. Output deve estar na MESMA LÍNGUA do input. CV em inglês → output em inglês ("Supported deal origination..."). CV em português → output em português ("Apoiei a originação..."). NUNCA traduza bullets, summary ou skills entre línguas.
7b. Stack tecnológico / área de formação: copie exato (não traduza nem reinterprete).

REGRA CRÍTICA DE CARDINALIDADE (NÃO VIOLE):
8. O número de experiences no OUTPUT precisa ser EXATAMENTE IGUAL ao número de experiences no INPUT. NUNCA adicione experience que não está listada. Se o input tem 1 experience, output TEM que ter 1. Se o input tem 3, output tem 3. NUNCA invente uma 2ª, 3ª ou 4ª experience pra "completar o CV" — currículo com 1 experience real é melhor que 3 inventadas.
9. O número de education no OUTPUT precisa ser EXATAMENTE IGUAL ao número de education no INPUT.
10. PRESERVE TODAS as experiences e education listadas — adapte cada uma, mas não remova nenhuma.

REGRA DE PRESERVAÇÃO INTEGRAL DE SEÇÕES (Tier 1):
11. PRESERVE TODAS as seções abaixo. Se input traz, output DEVE trazer:
    - Languages (lista de {name, proficiency}) — se input tem ["English: Native", "Portuguese: Native"], output DEVE conter os 2.
    - Tools (lista separada de skills técnicas) — MS Office, Power BI, etc. Se input tem 3 tools, output tem AS MESMAS 3 (pode reordenar).
    - Education details:
      • gpa: se input tem "8.9/10.0", output DEVE ter "8.9/10.0" (NÃO invente, NÃO mude).
      • majors: copie array IDÊNTICO (mesma ordem permitida).
      • minors: copie array IDÊNTICO.
      • activities: copie cada activity (pode reformular leve, mas o FATO de cada uma DEVE estar presente).
    - linkedin, streetAddress, headline: copie EXATAMENTE como vêm. Se input está vazio, output vazio. NUNCA invente URL/endereço/headline.
12. Esses campos NÃO são "decorativos" — são identidade do candidato. Currículo recrutador-friendly precisa de GPA, Minor, languages, etc. NUNCA dropa por achar que "não cabe" na vaga.

BULLETS — REGRA NOVA E CRÍTICA (V2):
Cada bullet adaptado precisa ter:
  - text: o bullet (pode ser reformulado em relação ao original)
  - _source_bullet_id: o uuid do bullet original cujo FATO está sendo descrito (ou null se for novo)
  - _action: 'kept' | 'rewritten' | 'synthesized'

REGRAS DE _action:
- 'kept'        : texto idêntico ao original (whitespace pode variar). _source_bullet_id é OBRIGATÓRIO.
- 'rewritten'   : reformula o MESMO fato do bullet original com palavras diferentes. _source_bullet_id é OBRIGATÓRIO. Não pode trocar fato; só verbo, ordem, ênfase.
- 'synthesized' : bullet completamente novo, sem fonte direta. PROIBIDO em V2 — só use se você está combinando dois fatos REAIS de bullets do MESMO experience_id. _source_bullet_id deve ser null.

LIMITES:
- Bullets por experience: NUNCA mais que o número original. Pode ter MENOS (omitir bullets fracos).
- Skills: máximo 12.
- Changes: liste APENAS mudanças REAIS, no máximo 6. Este é um TETO, não uma meta:
  se você mudou só uma coisa, liste UMA. NUNCA registre algo que ficou igual —
  'before' e 'after' idênticos não é mudança, e justificativa do tipo "preservado
  conforme solicitado", "não há X no input" ou "não possui bullets para adaptar"
  descreve uma NÃO-mudança e não deve virar entrada. Zero mudanças é resposta
  válida e honesta.

OUTPUT JSON ESTRITO conforme schema. Bullets na MESMA LÍNGUA do input (ver instrução de OUTPUT LANGUAGE no user prompt), método Harvard (verbo ação + impacto/contexto).`

interface JobContextV2 {
  title: string
  company: string
  area: string
  jobType: string
  workModel: string
  location: string
  description: string
  requirements: string[]
}

export { type JobContextV2 }

/**
 * Densidade do perfil — usado pra ajustar regras de TRIM/CONCISION/SUMMARY
 * no prompt v2. CVs pequenos precisam de conteúdo mais verboso pra preencher
 * a página com elegância; CVs grandes precisam de bullets concisos pra
 * caber em 1 página.
 *
 * Detectado server-side em handleAdaptV2 após loadProfileV2, baseado em
 * counts diretos do profile (não confia em hint do client).
 */
export type ProfileDensity = 'small' | 'medium' | 'large'

/**
 * Classifica o perfil por volume de conteúdo. Regras:
 * - `large`: ≥3 experiences OU (≥2 experiences + ≥3 certifications) OU
 *            (≥2 experiences + leadership/projects)
 * - `small`: 1 experience E ≤2 certifications E sem projects/awards
 * - `medium`: restante
 *
 * Conta tudo que aparece no prompt — experiences inclui voluntary/leadership
 * que vão pra `profile_experiences` (extracurriculares).
 */
export function detectProfileDensity(profile: ProfileRelational): ProfileDensity {
  const exps = profile.experiences?.length ?? 0
  const certs = profile.certifications?.length ?? 0
  const projs = profile.projects?.length ?? 0
  const awards = profile.awards?.length ?? 0

  // Large: muito conteúdo
  if (exps >= 3) return 'large'
  if (exps >= 2 && certs >= 3) return 'large'
  if (exps >= 2 && (projs + awards) >= 2) return 'large'

  // Small: conteúdo mínimo
  if (exps <= 1 && certs <= 2 && projs === 0 && awards === 0) return 'small'

  // Medium: resto
  return 'medium'
}

export function buildUserPromptV2(
  input: InputResumeV2,
  job: JobContextV2,
  extraSkills: string[] = [],
  density: ProfileDensity = 'large',
): string {
  // Quando input é EN, o user prompt inteiro vai em EN — headers, tarefa,
  // checklist. Sem isso, GPT vê o tom PT do prompt + system_prompt e
  // traduz a saída. Mistura de línguas no contexto é o sinal mais forte
  // que GPT segue.
  return input.language === 'en'
    ? _buildUserPromptEN(input, job, extraSkills, density)
    : _buildUserPromptPT(input, job, extraSkills, density)
}

function _buildUserPromptEN(
  input: InputResumeV2,
  job: JobContextV2,
  extraSkills: string[],
  density: ProfileDensity,
): string {
  const lines: string[] = []

  lines.push('## 🚨 OUTPUT LANGUAGE: English')
  lines.push('The CV below is in English. ALL fields in your output (bullets, summary, skills, changes.reason) MUST be in English.')
  lines.push('DO NOT translate to Portuguese. NEVER write "Apoiei", "Realizei", "Preparei" — keep "Supported", "Conducted", "Prepared".')
  lines.push('')
  lines.push('## ORIGINAL CV (source of truth)')
  lines.push('')
  lines.push('### Personal info (IMMUTABLE — copy exactly)')
  lines.push(`Name: ${input.fullName}`)
  if (input.email) lines.push(`Email: ${input.email}`)
  if (input.phone) lines.push(`Phone: ${input.phone}`)
  // LinkedIn / address / headline são preservados literalmente — campos
  // novos no schema_output (linkedin, streetAddress, headline). Se input
  // está vazio, output FICA VAZIO. NUNCA inventar URL/endereço.
  lines.push(`LinkedIn: ${input.linkedin || '(empty — leave empty in output, do NOT invent)'}`)
  if (input.streetAddress) lines.push(`Street address: ${input.streetAddress}`)
  if (input.location) lines.push(`Location (city/state/country): ${input.location}`)
  if (input.headline) lines.push(`Headline (1-line under name): ${input.headline}`)

  if (input.summary) {
    lines.push('')
    lines.push('### Current summary')
    lines.push(input.summary)
    lines.push('')
    // Density-aware: small CVs precisam summary mais verboso pra preencher
    // a página sem deixar branco; large CVs precisam conciso pra caber 1 página.
    const summaryRule = density === 'small'
        ? 'SUMMARY OUTPUT: 4-5 sentences, ~320-400 chars (4-5 lines in A4). ' +
          'Keep details rich — describe interests deeply, areas of focus, target career path, ' +
          'and what makes the candidate distinct. PRESERVE all factual nouns from input.'
        : density === 'medium'
            ? 'SUMMARY OUTPUT: 3-4 sentences, ~280-320 chars (3-4 lines in A4 10pt). ' +
              'Keep core facts: degree, school, core interests/focus area, key experience type, and target career.'
            : 'SUMMARY OUTPUT: max 3 sentences, ~240 chars total (3 lines in A4 10pt). ' +
              'Drop redundant connectors: "Experience in" → "experience in"; "Leadership experience in X initiatives" ' +
              'if X is already covered by an experience entry → omit. Keep core facts: degree, school, ' +
              'core interests/focus area, key experience type, and target career.'
    lines.push(summaryRule)
  }

  if (input.skills.length > 0) {
    lines.push('')
    lines.push('### Current skills — TECHNICAL (you may reorder/remove, NOT add new outside pool)')
    lines.push(input.skills.join(' | '))
  }

  if (input.tools.length > 0) {
    lines.push('')
    lines.push(`### Tools / Programs — PRESERVE ALL ${input.tools.length} (this is a DEDICATED section, separate from skills)`)
    input.tools.forEach((t) => lines.push(`- ${t}`))
  }

  if (input.languages.length > 0) {
    lines.push('')
    lines.push(`### Languages — PRESERVE ALL ${input.languages.length} (each {name, proficiency} preserved exactly)`)
    input.languages.forEach((l) => lines.push(`- ${l.name}: ${l.proficiency}`))
  }

  if (input.experiences.length > 0) {
    lines.push('')
    lines.push(`### Experience (EXACTLY ${input.experiences.length} entr${input.experiences.length === 1 ? 'y' : 'ies'} — output MUST have THIS number, do NOT invent more)`)
    lines.push('IDs in brackets are immutable — use them as _source_bullet_id.')
    for (const exp of input.experiences) {
      lines.push(`[${exp.id}] ${exp.role} @ ${exp.company} (${exp.period}${exp.location ? ', ' + exp.location : ''})`)
      for (const b of exp.bullets) {
        lines.push(`  • [bullet_id=${b.id}] ${b.text}`)
      }
    }
  } else {
    lines.push('')
    lines.push('### Experience')
    lines.push('NO experience entries. Output MUST have empty experiences array []. NEVER invent.')
  }

  // Education COMPLETA (Tier 1.3) — antes só `degree @ institution (period)`,
  // agora exibe GPA, majors, minors, activities. GPT recebe tudo e PRECISA
  // preservar no output (schema education tem campos pra cada).
  if (input.education.length > 0) {
    lines.push('')
    lines.push(`### Education (EXACTLY ${input.education.length} entr${input.education.length === 1 ? 'y' : 'ies'} — do NOT invent more, PRESERVE all details)`)
    for (const e of input.education) {
      lines.push(`[${e.id}] ${e.degree} @ ${e.institution} (${e.period}${e.location ? ', ' + e.location : ''})`)
      if (e.gpa) lines.push(`  GPA: ${e.gpa}  ← preserve in output.education[i].gpa`)
      if (e.majors.length > 0) lines.push(`  Majors: ${e.majors.join(', ')}  ← preserve in output.education[i].majors`)
      if (e.minors.length > 0) lines.push(`  Minors: ${e.minors.join(', ')}  ← preserve in output.education[i].minors`)
      if (e.activities.length > 0) {
        lines.push('  Activities (preserve ALL in output.education[i].activities — may reformulate slightly):')
        e.activities.forEach((a) => lines.push(`    • ${a}`))
      }
    }
  } else {
    lines.push('')
    lines.push('### Education')
    lines.push('NO education entries. Output MUST have empty education array []. NEVER invent.')
  }

  if (input.certifications.length > 0) {
    lines.push('')
    lines.push('### Certifications (preserve ALL — format "Name - Institution - Year")')
    input.certifications.forEach((c) => lines.push(`- ${c}`))
    lines.push('')
    if (density !== 'small') {
      lines.push(
        'CONCISION: If cert >70 chars, shorten by removing qualifiers ' +
        '("In-person", "Online", "Executive program", "held in", "self-paced course"). ' +
        'PRESERVE: institution (full), program core, year, location. ' +
        'NEVER: create unknown acronyms; drop institution/year/program. ' +
        'Ex: "Search Funds Institute - Entrepreneurship through Acquisition: In-person executive program, held in Madrid - 2025" → ' +
        '"Search Funds Institute - Entrepreneurship through Acquisition (Madrid, 2025)".',
      )
    } else {
      // Small density: NO concision — keep certs verbose to fill page.
      lines.push(
        'CERT VERBOSITY: KEEP all certification details verbose. ' +
        'Preserve qualifiers ("In-person", "executive program", "held in Madrid"). ' +
        'This profile has minimal content — verbose certs help fill the page elegantly.',
      )
    }
  }

  if (input.achievements.length > 0) {
    lines.push('')
    lines.push('### Achievements / Projects (may reorder / omit)')
    input.achievements.forEach((a) => lines.push(`- ${a}`))
  }

  if (input.interests.length > 0) {
    lines.push('')
    lines.push(`### Interests: ${input.interests.join(', ')}`)
  }

  lines.push('')
  lines.push('## TARGET JOB')
  lines.push(`Title: ${job.title}`)
  lines.push(`Company: ${job.company}`)
  lines.push(`Area: ${job.area}`)
  lines.push(`Type: ${job.jobType}`)
  lines.push(`Model: ${job.workModel}`)
  if (job.location) lines.push(`Location: ${job.location}`)
  if (job.requirements.length > 0) {
    lines.push('Requirements:')
    job.requirements.slice(0, 12).forEach((r) => lines.push(`  - ${r}`))
  }
  if (job.description) {
    lines.push('Description (summary):')
    lines.push(job.description.slice(0, 1500))
  }
  lines.push('')
  lines.push('NOTE: The target job description may be in Portuguese (Brazilian market). Your output stays in ENGLISH regardless — only use the job text to inform WHICH bullets to reformulate, never to translate the candidate CV.')

  if (extraSkills.length > 0) {
    lines.push('')
    lines.push('## SKILLS CONFIRMED BY CANDIDATE (not yet in CV)')
    extraSkills.forEach((s) => lines.push(`- ${s}`))
    lines.push(
      'These OVERRIDE the "skills must appear in CV" rule. ' +
      'BEFORE adding to output, TRANSLATE each Portuguese skill to English when there is a clear, common English equivalent. ' +
      'Examples of REQUIRED translation: ' +
      '"Engenharia Agrícola" → "Agricultural Engineering"; ' +
      '"Engenharia Civil" → "Civil Engineering"; ' +
      '"Engenharia Mecânica" → "Mechanical Engineering"; ' +
      '"Manutenção elétrica" → "Electrical Maintenance"; ' +
      '"Análise de dados" → "Data Analysis"; ' +
      '"Atendimento ao cliente" → "Customer Service"; ' +
      '"Orçamento" → "Budgeting"; ' +
      '"Vendas" → "Sales"; ' +
      '"Gestão de projetos" → "Project Management". ' +
      'Then put the TRANSLATED form in BOTH `resume.skills` (the array — appears in PDF Technical Skills line) AND any mention in `resume.summary`. ' +
      'KEEP in Portuguese ONLY when no clean English equivalent exists or term is Brazilian-specific (e.g. "Operação de caixa"); ' +
      'product/tool names stay as-is ("Power BI", "SQL", "Excel"). ' +
      'When in doubt, TRANSLATE. The output `resume.skills` array MUST be in the same language as the rest of the CV (English).',
    )
  }

  lines.push('')
  // Density-aware TRIM:
  //   - small: NO TRIM — bullets verbosos OK ("comprehensive", "throughout the year"
  //     ficam) pra preencher página com elegância
  //   - medium: TRIM moderado — só remove fillers super-óbvios
  //   - large: TRIM agressivo (atual) — remove tudo decorativo pra caber 1 página
  if (density === 'small') {
    lines.push('## VERBOSITY RULE — bullets/summary')
    lines.push(
      'For _action="rewritten": KEEP detail-rich phrasing. Preserve qualifiers ' +
      '("comprehensive", "detailed", "throughout the year", "showcasing X") if natural. ' +
      'This profile has minimal content — verbose bullets fill the page elegantly. ' +
      'Still: NEVER add facts not in input. _action="kept" stays byte-identical.',
    )
  } else if (density === 'medium') {
    lines.push('## TRIM RULE — bullets/summary (moderate)')
    lines.push(
      'For _action="rewritten": LIGHT trim — remove only super-obvious fillers ' +
      '("comprehensive", "throughout the year"). KEEP most descriptive phrasing ' +
      '("strategic", "detailed", "showcasing X" OK). Preserve facts. _action="kept" byte-identical.',
    )
  } else {
    lines.push('## TRIM RULE — bullets/summary (aggressive)')
    lines.push(
      'For _action="rewritten" only: TRIM fillers, PRESERVE facts. ' +
      'KEEP: verbs, numbers ("100+ hours"), names (Embraer, Stanford), places, tech, products. ' +
      'DROP: "comprehensive", "detailed", "potential", "throughout the year", "showcasing X", ' +
      '"demonstrating X", "which strengthened X", "in order to". ' +
      'Ex: "Conducted comprehensive market analysis to identify potential targets and enhance pipeline" → ' +
      '"Conducted market analysis to identify targets, supporting pipeline". ' +
      'NEVER trim if result loses a fact. _action="kept" stays byte-identical.',
    )
  }
  lines.push('')
  lines.push('## TASK')
  lines.push(
    'Adapt the candidate CV to this job. Reorder skills (most relevant first). ' +
    'Reformulate bullets (_action="rewritten") with _source_bullet_id pointing to the original — ' +
    'apply the TRIM RULE above to keep bullets concise (target 1-2 lines each in A4 with 11pt font). ' +
    'Unchanged bullets: _action="kept" — text MUST be byte-identical to the original. ' +
    'List at most 6 changes in "changes" array.',
  )
  lines.push('')
  lines.push('## MANDATORY CHECKLIST BEFORE RESPONDING')
  lines.push(`  ☐ All bullets/summary/skills/changes.reason are in English (NOT Portuguese)`)
  lines.push(`  ☐ resume.experiences.length === ${input.experiences.length} (NOT more, NOT less)`)
  lines.push(`  ☐ resume.education.length === ${input.education.length} (NOT more, NOT less)`)
  lines.push('  ☐ Bullets with _action="kept" have text byte-identical to the original (translation is NOT "kept", use "rewritten")')
  if (extraSkills.length > 0) {
    lines.push(`  ☐ Every Portuguese extra_skill ${extraSkills.map((s) => `"${s}"`).join(', ')} has been TRANSLATED to English in resume.skills array (e.g. "Engenharia Civil" → "Civil Engineering", NOT kept raw)`)
  }
  lines.push('  ☐ Every bullet has _source_bullet_id (uuid from input) OR is _action="synthesized" with null')
  lines.push(`  ☐ resume.linkedin === "${input.linkedin}" (copied exactly; empty stays empty — NEVER invent URL)`)
  lines.push(`  ☐ resume.streetAddress === "${input.streetAddress}" (copied exactly)`)
  lines.push(`  ☐ resume.headline === "${input.headline}" (copied exactly)`)
  lines.push(`  ☐ resume.tools has the SAME ${input.tools.length} entries as input.tools (may reorder, must include all)`)
  lines.push(`  ☐ resume.languages has the SAME ${input.languages.length} entries with preserved name+proficiency`)
  for (let i = 0; i < input.education.length; i++) {
    const e = input.education[i]
    const parts: string[] = []
    if (e.gpa) parts.push(`gpa="${e.gpa}"`)
    if (e.majors.length > 0) parts.push(`majors=[${e.majors.length}]`)
    if (e.minors.length > 0) parts.push(`minors=[${e.minors.length}]`)
    if (e.activities.length > 0) parts.push(`activities=[${e.activities.length}]`)
    if (parts.length > 0) {
      lines.push(`  ☐ resume.education[${i}] preserves: ${parts.join(', ')}`)
    }
  }
  lines.push('Return ONLY the JSON per the schema.')

  return lines.join('\n')
}

function _buildUserPromptPT(
  input: InputResumeV2,
  job: JobContextV2,
  extraSkills: string[],
  density: ProfileDensity,
): string {
  const lines: string[] = []

  lines.push('## 🚨 IDIOMA DO OUTPUT: Português (PT-BR)')
  lines.push('O CV abaixo está em português. TODOS os campos do output (bullets, summary, skills, changes.reason) DEVEM estar em português.')
  lines.push('NÃO traduza pra inglês. NUNCA escreva "Supported", "Conducted" — mantenha "Apoiei", "Realizei".')
  lines.push('')
  lines.push('## CURRÍCULO ORIGINAL DO CANDIDATO (fonte de verdade)')
  lines.push('')
  lines.push('### Dados pessoais (IMUTÁVEIS — copie exato)')
  lines.push(`Nome: ${input.fullName}`)
  if (input.email) lines.push(`Email: ${input.email}`)
  if (input.phone) lines.push(`Telefone: ${input.phone}`)
  lines.push(`LinkedIn: ${input.linkedin || '(vazio — deixe vazio no output, NÃO invente URL)'}`)
  if (input.streetAddress) lines.push(`Endereço (rua/bairro): ${input.streetAddress}`)
  if (input.location) lines.push(`Localização (cidade/estado/país): ${input.location}`)
  if (input.headline) lines.push(`Headline (linha sob o nome): ${input.headline}`)

  if (input.summary) {
    lines.push('')
    lines.push('### Resumo atual')
    lines.push(input.summary)
    lines.push('')
    // Density-aware (PT mirror)
    const summaryRulePt = density === 'small'
        ? 'SUMMARY OUTPUT: 4-5 frases, ~320-400 chars (4-5 linhas em A4). ' +
          'Mantenha detalhes ricos — descreva interesses em profundidade, áreas de foco, ' +
          'carreira alvo, e o que torna o candidato distinto. PRESERVE todos os substantivos factuais.'
        : density === 'medium'
            ? 'SUMMARY OUTPUT: 3-4 frases, ~280-320 chars (3-4 linhas em A4 10pt). ' +
              'Mantenha fatos essenciais: curso, instituição, áreas de interesse, tipo de experiência, carreira alvo.'
            : 'SUMMARY OUTPUT: máx 3 frases, ~240 chars total (3 linhas em A4 10pt). ' +
              'Corte conectores redundantes: "Experiência em" → "experiência em"; "Experiência de liderança em X iniciativas" ' +
              'se X já está coberto por uma experience entry → omita. Mantenha fatos essenciais: ' +
              'curso, instituição, áreas de interesse, tipo de experiência principal, e carreira alvo.'
    lines.push(summaryRulePt)
  }

  if (input.skills.length > 0) {
    lines.push('')
    lines.push('### Skills TÉCNICAS (pode reordenar/remover, NÃO adicionar fora do pool)')
    lines.push(input.skills.join(' | '))
  }

  if (input.tools.length > 0) {
    lines.push('')
    lines.push(`### Tools / Programas — PRESERVE TODAS as ${input.tools.length} (seção DEDICADA separada de skills)`)
    input.tools.forEach((t) => lines.push(`- ${t}`))
  }

  if (input.languages.length > 0) {
    lines.push('')
    lines.push(`### Idiomas — PRESERVE TODOS os ${input.languages.length} (cada {name, proficiency} igual ao input)`)
    input.languages.forEach((l) => lines.push(`- ${l.name}: ${l.proficiency}`))
  }

  if (input.experiences.length > 0) {
    lines.push('')
    lines.push(`### Experiências (EXATAMENTE ${input.experiences.length} experience${input.experiences.length === 1 ? '' : 's'} — output DEVE ter ESSE número, NÃO invente outras)`)
    lines.push('IDs em colchetes são imutáveis — use no _source_bullet_id.')
    for (const exp of input.experiences) {
      lines.push(`[${exp.id}] ${exp.role} @ ${exp.company} (${exp.period}${exp.location ? ', ' + exp.location : ''})`)
      for (const b of exp.bullets) {
        lines.push(`  • [bullet_id=${b.id}] ${b.text}`)
      }
    }
  } else {
    lines.push('')
    lines.push('### Experiências')
    lines.push('NENHUMA experience cadastrada. Output DEVE ter array experiences vazio []. NUNCA invente.')
  }

  // Education COMPLETA (Tier 1.3 PT mirror)
  if (input.education.length > 0) {
    lines.push('')
    lines.push(`### Formação (EXATAMENTE ${input.education.length} education${input.education.length === 1 ? '' : 's'} — NÃO invente, PRESERVE todos os detalhes)`)
    for (const e of input.education) {
      lines.push(`[${e.id}] ${e.degree} @ ${e.institution} (${e.period}${e.location ? ', ' + e.location : ''})`)
      if (e.gpa) lines.push(`  GPA: ${e.gpa}  ← preserve em output.education[i].gpa`)
      if (e.majors.length > 0) lines.push(`  Majors: ${e.majors.join(', ')}  ← preserve em output.education[i].majors`)
      if (e.minors.length > 0) lines.push(`  Minors: ${e.minors.join(', ')}  ← preserve em output.education[i].minors`)
      if (e.activities.length > 0) {
        lines.push('  Atividades (PRESERVE TODAS em output.education[i].activities — pode reformular leve):')
        e.activities.forEach((a) => lines.push(`    • ${a}`))
      }
    }
  } else {
    lines.push('')
    lines.push('### Formação')
    lines.push('NENHUMA education cadastrada. Output DEVE ter array education vazio []. NUNCA invente.')
  }

  if (input.certifications.length > 0) {
    lines.push('')
    lines.push('### Certificações (preserve TODAS — formato "Nome - Instituição - Ano")')
    input.certifications.forEach((c) => lines.push(`- ${c}`))
    lines.push('')
    if (density !== 'small') {
      lines.push(
        'CONCISÃO: Se cert >70 chars, encurte removendo qualifiers ' +
        '("Presencial", "Online", "Programa executivo", "realizado em", "Curso"). ' +
        'PRESERVE: instituição (full), nome do programa, ano, local. ' +
        'NUNCA: crie siglas desconhecidas; tire instituição/ano/programa. ' +
        'Ex: "Search Funds Institute - ETA: Programa executivo presencial, realizado em Madrid - 2025" → ' +
        '"Search Funds Institute - ETA (Madrid, 2025)".',
      )
    } else {
      lines.push(
        'VERBOSIDADE EM CERTIFICAÇÕES: MANTENHA todos os detalhes verbosos. ' +
        'Preserve qualifiers ("Presencial", "Programa executivo", "realizado em Madrid"). ' +
        'Esse perfil tem pouco conteúdo — certs verbosas ajudam a preencher a página.',
      )
    }
  }

  if (input.achievements.length > 0) {
    lines.push('')
    lines.push('### Conquistas/Projetos (pode reordenar/omitir)')
    input.achievements.forEach((a) => lines.push(`- ${a}`))
  }

  if (input.interests.length > 0) {
    lines.push('')
    lines.push(`### Interesses: ${input.interests.join(', ')}`)
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

  if (extraSkills.length > 0) {
    lines.push('')
    lines.push('## SKILLS CONFIRMADAS PELO CANDIDATO (esqueceu de escrever no CV)')
    extraSkills.forEach((s) => lines.push(`- ${s}`))
    lines.push(
      'Inclua cada uma em `resume.skills`. Estas SOBREPÕEM a regra "skills devem aparecer no CV".',
    )
  }

  lines.push('')
  // Density-aware (PT mirror)
  if (density === 'small') {
    lines.push('## REGRA DE VERBOSIDADE — bullets/summary')
    lines.push(
      'Para action=rewritten: MANTENHA frases ricas em detalhes. Preserve qualifiers ' +
      '("abrangente", "detalhado", "ao longo do ano") quando soarem naturais. ' +
      'Esse perfil tem pouco conteúdo — bullets verbosos preenchem a página com elegância. ' +
      'Ainda assim: NUNCA invente fatos. action=kept fica idêntico.',
    )
  } else if (density === 'medium') {
    lines.push('## REGRA DE CONCISÃO — bullets/summary (moderada)')
    lines.push(
      'Para action=rewritten: TRIM leve — corte só fillers super-óbvios ' +
      '("abrangente", "ao longo do ano"). MANTENHA maior parte da descrição ' +
      '("estratégico", "detalhado", "demonstrando X" OK). Preserve fatos. action=kept idêntico.',
    )
  } else {
    lines.push('## REGRA DE CONCISÃO — bullets/summary (agressiva)')
    lines.push(
      'Para action=rewritten apenas: CORTE fillers, PRESERVE fatos. ' +
      'MANTENHA: verbos, números ("100+ horas"), nomes (Embraer, Stanford), locais, tech. ' +
      'CORTE: "abrangente", "detalhado", "potencial", "ao longo do ano", "demonstrando X", ' +
      '"evidenciando X", "que fortaleceu X", "a fim de". ' +
      'Ex: "Realizei análise abrangente de mercado para identificar potenciais alvos e fortalecer pipeline" → ' +
      '"Realizei análise de mercado para identificar alvos, apoiando pipeline". ' +
      'NUNCA corte se perder fato. action=kept fica idêntico.',
    )
  }
  lines.push('')
  lines.push('## TAREFA')
  lines.push(
    'Adapte o currículo do candidato pra essa vaga. Reordene skills colocando as relevantes primeiro. ' +
    'Reformule bullets (action=rewritten) com _source_bullet_id apontando pro bullet original — ' +
    'aplique a REGRA DE CONCISÃO acima pra manter bullets concisos (target 1-2 linhas cada em A4 11pt). ' +
    'Bullets sem mudança: action=kept — texto DEVE ser idêntico ao original (tradução NÃO é "kept", use "rewritten"). ' +
    'Liste em "changes" no máximo 6 mudanças.',
  )
  lines.push('')
  lines.push('## CHECKLIST OBRIGATÓRIO ANTES DE RESPONDER')
  lines.push('  ☐ Todos bullets/summary/skills/changes.reason em português (NÃO inglês)')
  lines.push(`  ☐ resume.experiences.length === ${input.experiences.length} (NÃO mais, NÃO menos)`)
  lines.push(`  ☐ resume.education.length === ${input.education.length} (NÃO mais, NÃO menos)`)
  lines.push('  ☐ Bullets com _action="kept" têm texto idêntico ao original (tradução NÃO é "kept")')
  lines.push('  ☐ Cada bullet tem _source_bullet_id (uuid do input) OU é synthesized com fonte clara')
  lines.push(`  ☐ resume.linkedin === "${input.linkedin}" (copie exato; vazio fica vazio — NUNCA invente URL)`)
  lines.push(`  ☐ resume.streetAddress === "${input.streetAddress}" (copie exato)`)
  lines.push(`  ☐ resume.headline === "${input.headline}" (copie exato)`)
  lines.push(`  ☐ resume.tools tem AS MESMAS ${input.tools.length} entries do input.tools (pode reordenar, deve incluir todas)`)
  lines.push(`  ☐ resume.languages tem AS MESMAS ${input.languages.length} entries com nome+proficiência preservadas`)
  for (let i = 0; i < input.education.length; i++) {
    const e = input.education[i]
    const parts: string[] = []
    if (e.gpa) parts.push(`gpa="${e.gpa}"`)
    if (e.majors.length > 0) parts.push(`majors=[${e.majors.length}]`)
    if (e.minors.length > 0) parts.push(`minors=[${e.minors.length}]`)
    if (e.activities.length > 0) parts.push(`activities=[${e.activities.length}]`)
    if (parts.length > 0) {
      lines.push(`  ☐ resume.education[${i}] preserva: ${parts.join(', ')}`)
    }
  }
  lines.push('Retorne APENAS o JSON conforme o schema.')

  return lines.join('\n')
}

export const JSON_SCHEMA_V2 = {
  name: 'adapted_resume_v2',
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
        // Strict mode do OpenAI exige `required` listar TODAS as properties.
        required: [
          'fullName', 'email', 'phone', 'linkedin', 'location', 'streetAddress',
          'headline', 'language', 'summary',
          'skills', 'tools', 'languages',
          'experiences', 'education',
          'achievements', 'interests', 'certifications',
        ],
        properties: {
          fullName: { type: 'string' },
          email: { type: 'string' },
          phone: { type: 'string' },
          linkedin: { type: 'string' },
          location: { type: 'string' },
          streetAddress: { type: 'string' },
          headline: { type: 'string' },
          language: { type: 'string' },
          summary: { type: 'string' },
          skills: { type: 'array', items: { type: 'string' } },
          // Tools/programs (MS Office, Power BI, etc) — preservados sempre.
          tools: { type: 'array', items: { type: 'string' } },
          // Languages — seção dedicada (idioma + proficiência).
          languages: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['name', 'proficiency'],
              properties: {
                name: { type: 'string' },
                proficiency: { type: 'string' },
              },
            },
          },
          experiences: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['role', 'company', 'period', 'location', 'bullets'],
              properties: {
                role: { type: 'string' },
                company: { type: 'string' },
                period: { type: 'string' },
                location: { type: 'string' },
                bullets: {
                  type: 'array',
                  items: {
                    type: 'object',
                    additionalProperties: false,
                    required: ['text', '_source_bullet_id', '_action'],
                    properties: {
                      text: { type: 'string' },
                      _source_bullet_id: { type: ['string', 'null'] },
                      _action: { type: 'string', enum: ['kept', 'rewritten', 'synthesized'] },
                    },
                  },
                },
              },
            },
          },
          // Education expandida (Tier 1.2): GPA, majors, minors, activities
          // anti-invenção. Antes só `details: string` (majors[0]) — agora
          // GPT retorna tudo separado, validador exige preservação.
          education: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: [
                'degree', 'institution', 'period', 'details', 'location',
                'gpa', 'majors', 'minors', 'activities',
              ],
              properties: {
                degree: { type: 'string' },
                institution: { type: 'string' },
                period: { type: 'string' },
                // details = primeiro major (backward compat com template v1).
                // Pode ser duplicado em majors[0] — não problema.
                details: { type: 'string' },
                location: { type: 'string' },
                // "8.9/10.0", "8.9", ou "" se ausente. Strict: nunca null.
                gpa: { type: 'string' },
                majors: { type: 'array', items: { type: 'string' } },
                minors: { type: 'array', items: { type: 'string' } },
                activities: { type: 'array', items: { type: 'string' } },
              },
            },
          },
          achievements: { type: 'array', items: { type: 'string' } },
          interests: { type: 'array', items: { type: 'string' } },
          certifications: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  },
} as const

// ────────────────────────────────────────────────────────────────────────────
// Validator V2 — anti-invenção + check de bullet IDs
// ────────────────────────────────────────────────────────────────────────────

export class ValidationErrorV2 extends Error {
  constructor(public field: string, message: string) {
    super(message)
    this.name = 'ValidationErrorV2'
  }
}

const MAX_BULLET_INFLATION = 1.3

/**
 * Valida que a adaptação v2:
 *   - Preserva identidade (nome, email, telefone, location)
 *   - Empresas/instituições/cargos/periodos imutáveis (eqInstitutional)
 *   - Bullets:
 *      • action='kept'        → text bate com o bullet original (após normalize)
 *      • action='rewritten'   → _source_bullet_id existe no input do mesmo experience
 *      • action='synthesized' → _source_bullet_id null + cada palavra concreta presente
 *                                no keywordPool do input
 *   - Inflation: não mais bullets que o original * 1.3
 *   - Skills: só skills que estavam no input
 */
export function validateAdaptationV2(
  input: InputResumeV2,
  parsed: any,
  _job?: JobContextV2,
  extraSkills: string[] = [],
): void {
  const r = parsed?.resume
  if (!r || typeof r !== 'object') {
    throw new ValidationErrorV2('resume', 'resume missing or not object')
  }

  // 1. Identidade (imutáveis)
  const identityChecks: Array<[string, string, string]> = [
    ['fullName', input.fullName, String(r.fullName ?? '')],
    ['email', input.email, String(r.email ?? '')],
  ]
  for (const [field, inVal, outVal] of identityChecks) {
    if (inVal && !eqInstitutional(inVal, outVal)) {
      throw new ValidationErrorV2(field, `${field} mudou: "${inVal}" → "${outVal}"`)
    }
  }

  // 2. Experiences — empresas/cargos/períodos imutáveis + bullets
  const expsIn = input.experiences
  const expsOut = Array.isArray(r.experiences) ? r.experiences : []
  // Não pode haver MAIS experiences que o original.
  if (expsOut.length > expsIn.length) {
    throw new ValidationErrorV2('experiences', `output tem ${expsOut.length} experiences, input tem ${expsIn.length}`)
  }

  // Mapeia experiences do output pra experiences do input via match
  // company+role. Isso permite reordenamento mas detecta criação fake.
  const inputBulletsById = new Map<string, { text: string; experienceId: string }>()
  for (const exp of expsIn) {
    for (const b of exp.bullets) {
      inputBulletsById.set(b.id, { text: b.text, experienceId: exp.id })
    }
  }

  for (let i = 0; i < expsOut.length; i++) {
    const eo = expsOut[i]
    // Match best input experience
    const matchedIn = expsIn.find((e) =>
      eqInstitutional(e.company, eo.company) && eqInstitutional(e.role, eo.role)
    )
    if (!matchedIn) {
      throw new ValidationErrorV2(
        `experiences[${i}]`,
        `experience adapted "${eo.role} @ ${eo.company}" não casa com nenhuma original`,
      )
    }
    // Período imutável (jaro-winkler 0.85)
    const periodIn = normalize(matchedIn.period)
    const periodOut = normalize(eo.period ?? '')
    if (periodIn && periodOut && jaroWinklerSimilarity(periodIn, periodOut) < 0.85) {
      throw new ValidationErrorV2(
        `experiences[${i}].period`,
        `período mudou: "${matchedIn.period}" → "${eo.period}"`,
      )
    }

    // Bullets v2
    const bulletsOut = Array.isArray(eo.bullets) ? eo.bullets : []
    const maxAllowed = Math.ceil(matchedIn.bullets.length * MAX_BULLET_INFLATION)
    if (bulletsOut.length > maxAllowed) {
      throw new ValidationErrorV2(
        `experiences[${i}].bullets`,
        `${bulletsOut.length} bullets > max ${maxAllowed} (original=${matchedIn.bullets.length})`,
      )
    }

    for (let j = 0; j < bulletsOut.length; j++) {
      const bo = bulletsOut[j]
      const action = bo?._action
      const srcId = bo?._source_bullet_id
      const text = String(bo?.text ?? '').trim()
      if (!text) {
        throw new ValidationErrorV2(`experiences[${i}].bullets[${j}]`, 'text vazio')
      }

      if (action === 'kept') {
        if (!srcId || !inputBulletsById.has(srcId)) {
          throw new ValidationErrorV2(
            `experiences[${i}].bullets[${j}]`,
            `_action=kept exige _source_bullet_id válido (recebi "${srcId}")`,
          )
        }
        const src = inputBulletsById.get(srcId)!
        if (src.experienceId !== matchedIn.id) {
          throw new ValidationErrorV2(
            `experiences[${i}].bullets[${j}]`,
            `_source_bullet_id pertence a outro experience (cross-contamination)`,
          )
        }
        // 'kept' = texto deve ser idêntico após normalize
        if (flatten(text) !== flatten(src.text)) {
          throw new ValidationErrorV2(
            `experiences[${i}].bullets[${j}]`,
            `_action=kept mas texto difere: "${src.text}" vs "${text}"`,
          )
        }
      } else if (action === 'rewritten') {
        if (!srcId || !inputBulletsById.has(srcId)) {
          throw new ValidationErrorV2(
            `experiences[${i}].bullets[${j}]`,
            `_action=rewritten exige _source_bullet_id válido (recebi "${srcId}")`,
          )
        }
        const src = inputBulletsById.get(srcId)!
        if (src.experienceId !== matchedIn.id) {
          throw new ValidationErrorV2(
            `experiences[${i}].bullets[${j}]`,
            `_source_bullet_id pertence a outro experience (cross-contamination)`,
          )
        }
        // Tradução EN↔PT é operação legítima de adaptação. Quando o input
        // está em inglês ("Supported deal origination...") e o output em
        // PT-BR ("Apoiei a originação..."), checar palavra-por-palavra dá
        // falso-positivo. Confiamos no _source_bullet_id como âncora.
        //
        // Defesa contra invenção que sobra: limite de tamanho — bullet
        // rewritten não pode ser drasticamente maior que o source (heurística
        // pra detectar quando GPT enxerta fatos extras sob pretexto de "rewrite").
        const srcLen = src.text.length
        if (srcLen > 0 && text.length > srcLen * 2.5 && text.length - srcLen > 80) {
          throw new ValidationErrorV2(
            `experiences[${i}].bullets[${j}]`,
            `bullet rewritten cresceu ${text.length} chars vs source ${srcLen} (possível enxerto de fatos extras)`,
          )
        }
      } else if (action === 'synthesized') {
        // synthesized é caro: cada palavra concreta DEVE estar no keywordPool
        if (srcId !== null) {
          throw new ValidationErrorV2(
            `experiences[${i}].bullets[${j}]`,
            `_action=synthesized exige _source_bullet_id=null (recebi "${srcId}")`,
          )
        }
        const concreteWords = tokenize(text).filter((w) => !/^\d+$/.test(w) && w.length >= 4)
        for (const w of concreteWords) {
          if (input.keywordPool.has(w)) continue
          throw new ValidationErrorV2(
            `experiences[${i}].bullets[${j}]`,
            `palavra inventada em synthesized: "${w}"`,
          )
        }
      } else {
        throw new ValidationErrorV2(
          `experiences[${i}].bullets[${j}]`,
          `_action inválido: "${action}"`,
        )
      }
    }
  }

  // 3. Education — institution+degree+period+gpa+majors+minors+activities
  // imutáveis (Tier 1.4 expansão massiva). Antes só institution+degree.
  const edusIn = input.education
  const edusOut = Array.isArray(r.education) ? r.education : []
  if (edusOut.length > edusIn.length) {
    throw new ValidationErrorV2('education', `output tem ${edusOut.length} education, input tem ${edusIn.length}`)
  }
  for (let i = 0; i < edusOut.length; i++) {
    const eo = edusOut[i]
    const matched = edusIn.find((e) =>
      eqInstitutional(e.institution, eo.institution) && eqInstitutional(e.degree, eo.degree)
    )
    if (!matched) {
      throw new ValidationErrorV2(
        `education[${i}]`,
        `education "${eo.degree} @ ${eo.institution}" não casa com original`,
      )
    }

    // 3a. GPA preservado se input tem.
    const inGpa = (matched.gpa ?? '').trim()
    const outGpa = String(eo.gpa ?? '').trim()
    if (inGpa) {
      if (!outGpa) {
        throw new ValidationErrorV2(
          `education[${i}].gpa`,
          `input tem GPA "${inGpa}" mas output omitiu — preserve sempre`,
        )
      }
      // Normalize remove case + acentos. Aceita formato "8.9/10.0" ou só "8.9".
      // Anti-invenção: GPT NÃO pode inventar GPA (se input vazio, output vazio).
      if (normalize(outGpa) !== normalize(inGpa) &&
          jaroWinklerSimilarity(normalize(outGpa), normalize(inGpa)) < 0.9) {
        throw new ValidationErrorV2(
          `education[${i}].gpa`,
          `GPA mudou: "${inGpa}" → "${outGpa}"`,
        )
      }
    } else {
      if (outGpa) {
        throw new ValidationErrorV2(
          `education[${i}].gpa`,
          `output inventou GPA "${outGpa}" — input não tem`,
        )
      }
    }

    // 3b. Majors preservados (set match normalizado, mesma cardinalidade).
    const inMajors = (matched.majors ?? []).map((m) => normalize(m))
    const outMajorsRaw = Array.isArray(eo.majors) ? eo.majors : []
    const outMajors = outMajorsRaw.map((m: any) => normalize(String(m ?? '')))
    if (outMajors.length > inMajors.length) {
      throw new ValidationErrorV2(
        `education[${i}].majors`,
        `output inventou major (${outMajorsRaw.length} > input ${inMajors.length})`,
      )
    }
    for (const m of outMajors) {
      if (!inMajors.includes(m)) {
        throw new ValidationErrorV2(
          `education[${i}].majors`,
          `major inventado: "${m}"`,
        )
      }
    }

    // 3c. Minors — mesma lógica.
    const inMinors = (matched.minors ?? []).map((m) => normalize(m))
    const outMinorsRaw = Array.isArray(eo.minors) ? eo.minors : []
    const outMinors = outMinorsRaw.map((m: any) => normalize(String(m ?? '')))
    if (outMinors.length > inMinors.length) {
      throw new ValidationErrorV2(
        `education[${i}].minors`,
        `output inventou minor (${outMinorsRaw.length} > input ${inMinors.length})`,
      )
    }
    for (const m of outMinors) {
      if (!inMinors.includes(m)) {
        throw new ValidationErrorV2(
          `education[${i}].minors`,
          `minor inventado: "${m}"`,
        )
      }
    }

    // 3d. Activities — pode reformular leve, mas FATO de cada uma deve
    // estar presente. Heurística: aceita activity de output se ≥70% das
    // suas palavras concretas (≥4 chars, não-numéricas) aparecem em alguma
    // activity do input. Anti-invenção: nenhuma activity totalmente nova.
    const inActivitiesNorm = (matched.activities ?? []).map((a) => tokenize(a))
    const outActivitiesRaw = Array.isArray(eo.activities) ? eo.activities : []
    if (outActivitiesRaw.length > inActivitiesNorm.length) {
      throw new ValidationErrorV2(
        `education[${i}].activities`,
        `output inventou activity (${outActivitiesRaw.length} > input ${inActivitiesNorm.length})`,
      )
    }
    for (let j = 0; j < outActivitiesRaw.length; j++) {
      const outTokens = tokenize(String(outActivitiesRaw[j] ?? ''))
        .filter((w) => !/^\d+$/.test(w) && w.length >= 4)
      if (outTokens.length === 0) continue // activity de uma palavra curta → aceita
      const bestMatchRatio = inActivitiesNorm
        .map((inTokens) => {
          const inSet = new Set(inTokens)
          const hits = outTokens.filter((t) => inSet.has(t)).length
          return outTokens.length > 0 ? hits / outTokens.length : 0
        })
        .reduce((a, b) => (b > a ? b : a), 0)
      if (bestMatchRatio < 0.5) {
        throw new ValidationErrorV2(
          `education[${i}].activities[${j}]`,
          `activity "${outActivitiesRaw[j]}" não casa com nenhuma do input (match ratio=${bestMatchRatio.toFixed(2)})`,
        )
      }
    }
  }

  // 4. Skills — só do pool, com slots de tradução pras extra_skills.
  //
  // Quando user confirma uma extra_skill em PT mas o CV é EN, o prompt
  // instrui GPT a traduzir ("Engenharia Civil" → "Civil Engineering",
  // "Documentação técnica" → "Technical Documentation"). Validator precisa
  // aceitar essas traduções sem rejeitar como "skill inventada".
  //
  // Heurística (refatorada v21+): contagem em vez de token overlap.
  // - Skills do CV original: exact-match estrito (a fonte de verdade).
  // - Skills do output que NÃO batem com CV nem com extra raw: presumidas
  //   traduções. Aceitas até `extraSkills.length` de slots. Acima disso é
  //   invenção real.
  //
  // Caso edge: GPT pode gerar 1 "tradução" + 1 invenção real quando
  // extraSkills.length=2. Esse caso passa, mas é raro e o limite de
  // 12 skills total já mitiga. False positives anteriores (rejeitar
  // tradução legítima) eram MUITO mais frequentes que esse edge case.
  const skillsOut = Array.isArray(r.skills) ? r.skills : []
  if (skillsOut.length > 12) {
    throw new ValidationErrorV2('skills', `${skillsOut.length} skills > max 12`)
  }
  const extraSkillsNorm = new Set(extraSkills.map((s) => normalize(s)))
  // CV-original = input.skills MENOS o que veio de extra_skills (pushed
  // antes da chamada OpenAI em main()).
  const cvOriginalNorm = new Set(
    input.skills.map(normalize).filter((s) => !extraSkillsNorm.has(s)),
  )
  const translationSlots = extraSkills.length
  let unmatchedCount = 0
  const unmatchedNames: string[] = []
  for (const s of skillsOut) {
    const ns = normalize(String(s ?? ''))
    if (cvOriginalNorm.has(ns)) continue       // skill original do CV
    if (extraSkillsNorm.has(ns)) continue      // extra mantida na forma raw
    // Não bate exato com nada → consome um slot de tradução
    unmatchedCount++
    unmatchedNames.push(String(s ?? ''))
    if (unmatchedCount > translationSlots) {
      throw new ValidationErrorV2(
        'skills',
        `skill inventada: "${s}" (${unmatchedCount} unmatched > ${translationSlots} translation slots ` +
        `for extras=[${extraSkills.join(', ')}])`,
      )
    }
  }

  // 5. Tools — preserve all (set match, sem invenção). Antes: NENHUM check.
  const toolsOut = Array.isArray(r.tools) ? r.tools : []
  const inToolsNorm = new Set(input.tools.map((t) => normalize(t)))
  // Permite output omitir alguns tools (ex: se rolar over 12 e GPT cortar),
  // mas NÃO permite inventar tool fora do pool.
  for (const t of toolsOut) {
    const tn = normalize(String(t ?? ''))
    if (!inToolsNorm.has(tn)) {
      throw new ValidationErrorV2('tools', `tool inventada: "${t}"`)
    }
  }
  // Verifica preservação mínima — se input tem 1+ tools, output deve ter ≥1.
  if (input.tools.length > 0 && toolsOut.length === 0) {
    throw new ValidationErrorV2(
      'tools',
      `input tem ${input.tools.length} tools mas output dropou todas`,
    )
  }

  // 6. Languages — preserva nome de cada language do input (sem invenção).
  // Proficiency pode mudar se for ajuste idiomático (ex: PT input "Avançado"
  // pode virar EN output "Advanced" quando idioma do CV é EN).
  const langsOut = Array.isArray(r.languages) ? r.languages : []
  const inLangNames = new Set(input.languages.map((l) => normalize(l.name)))
  const outLangNames = new Set(
    langsOut.map((l: any) => normalize(String(l?.name ?? ''))),
  )
  for (const ln of outLangNames) {
    if (!inLangNames.has(ln)) {
      throw new ValidationErrorV2(
        'languages',
        `language inventada: "${ln}"`,
      )
    }
  }
  if (input.languages.length > 0 && langsOut.length === 0) {
    throw new ValidationErrorV2(
      'languages',
      `input tem ${input.languages.length} languages mas output dropou todas`,
    )
  }

  // 7. LinkedIn / streetAddress / headline — copia exata (incluindo vazio).
  // Anti-invenção: se input vazio, output DEVE estar vazio (não pode gerar URL fake).
  const fieldChecks: Array<[string, string, string]> = [
    ['linkedin', input.linkedin, String(r.linkedin ?? '')],
    ['streetAddress', input.streetAddress, String(r.streetAddress ?? '')],
    ['headline', input.headline, String(r.headline ?? '')],
  ]
  for (const [field, inVal, outVal] of fieldChecks) {
    if (!inVal && outVal.trim().length > 0) {
      throw new ValidationErrorV2(
        field,
        `${field} inventado: input vazio mas output retornou "${outVal}"`,
      )
    }
    if (inVal && outVal.trim().length === 0) {
      throw new ValidationErrorV2(
        field,
        `${field} dropado: input "${inVal}" mas output vazio`,
      )
    }
    // Se ambos têm valor, exige similaridade jaro-winkler ≥ 0.8 (tolera
    // espaçamento/acento, mas detecta substituição completa).
    if (inVal && outVal &&
        jaroWinklerSimilarity(normalize(inVal), normalize(outVal)) < 0.8) {
      throw new ValidationErrorV2(
        field,
        `${field} mudou: "${inVal}" → "${outVal}"`,
      )
    }
  }

  // 8. Summary — não pode ALEGAR experiência profissional que o perfil não tem.
  assertSummaryDoesNotClaimExperience(input, r)
}

/**
 * Revisão UX 28/07 (P0). Com `input.experiences` VAZIO, o modelo devolveu:
 *
 *   "Estudante de Engenharia de Produção COM EXPERIÊNCIA EM elaboração de
 *    relatórios e cotações com fornecedores."
 *
 * As duas coisas vieram de checkboxes de `extra_skills` — a folha pergunta o que
 * a pessoa SABE ("Marque o que você tem mas não escreveu no CV"), não onde ela
 * já trabalhou. O rodapé da tela promete "Nenhuma informação foi inventada" e o
 * texto vai para o PDF que o recrutador lê.
 *
 * As checagens 1–7 cobrem LISTAS (skills, tools, experiences, majors…); a prosa
 * do `summary` passava livre. Aqui fechamos só o caso inequívoco: zero
 * experiências no input + afirmação de experiência no output.
 *
 * Frases de BUSCA continuam passando ("buscando experiência em Suprimentos",
 * "primeira experiência", "sem experiência prévia") — são legítimas e são
 * exatamente o que um CV de estudante deve dizer.
 */
function assertSummaryDoesNotClaimExperience(input: InputResumeV2, r: any): void {
  const claims = findUnsupportedExperienceClaims(
    input.experiences.length,
    r?.summary,
    Array.isArray(r?.experiences) ? r.experiences.length : 0,
  )
  if (claims.length === 0) return
  throw new ValidationErrorV2(
    claims[0].field,
    experienceClaimMessage(claims[0], input.experiences.length),
  )
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers de output (deriva description backward-compat do bullets[])
// ────────────────────────────────────────────────────────────────────────────

/**
 * Pós-processamento: deriva `description: string` (junção dos bullets por
 * \n) em cada experience pra manter shape compatível com templates v1 que
 * consomem `resume_data`. Cliente moderno usa `bullets[]` direto.
 *
 * Também garante education.details preenchido (backward compat:
 * `details = majors[0]` se vazio).
 *
 * Aplica IN PLACE no parsed.resume.
 */
export function deriveDescriptionsFromBullets(parsed: any): void {
  const exps = parsed?.resume?.experiences
  if (Array.isArray(exps)) {
    for (const exp of exps) {
      const bs = Array.isArray(exp?.bullets) ? exp.bullets : []
      exp.description = bs
        .map((b: any) => String(b?.text ?? '').trim())
        .filter((t: string) => t.length > 0)
        .join('\n')
    }
  }
  // Education: garante `details` populado pra templates v1 que esperam string.
  // Se GPT já retornou details, mantém. Senão, usa majors[0].
  const edus = parsed?.resume?.education
  if (Array.isArray(edus)) {
    for (const e of edus) {
      const currentDetails = String(e?.details ?? '').trim()
      if (currentDetails) continue
      const majors = Array.isArray(e?.majors) ? e.majors : []
      if (majors.length > 0) e.details = String(majors[0] ?? '')
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Orquestrador V2 — ponto único de entrada chamado pelo serve() do index.ts
// ────────────────────────────────────────────────────────────────────────────

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

type CallOpenAI = (
  systemPrompt: string,
  userPrompt: string,
  opts?: { schema?: any },
) => Promise<{ content: string; inputTokens: number; outputTokens: number; totalTokens: number; latencyMs: number }>

export interface HandleAdaptV2Opts {
  supabaseAdmin: ReturnType<typeof createClient>
  supabaseClient: ReturnType<typeof createClient>
  userId: string
  userEmail: string
  jobId: string
  job: JobContextV2
  extraSkillsClean: string[]
  force: boolean
  fnStart: number
  callOpenAI: CallOpenAI
}

type AdaptResponse = {
  status: number
  body: Record<string, unknown>
}

/**
 * Handler v2 completo. Retorna `null` se:
 *   - Feature flag desligada pra este user
 *   - Profile relacional vazio
 *   - Erro inesperado (caller cai pro v1)
 *
 * Caso contrário retorna `AdaptResponse` que o caller transforma em
 * `Response` HTTP. Não devolve Response direto pra não acoplar v2 ao
 * `jsonResponse` helper do index.ts.
 */
export async function handleAdaptV2(opts: HandleAdaptV2Opts): Promise<AdaptResponse | null> {
  const {
    supabaseAdmin, supabaseClient, userId, jobId, job, extraSkillsClean,
    force, fnStart, callOpenAI,
  } = opts

  // 1. Gate: feature flag + perfil relacional disponível
  const v2On = await isV2EnabledForUser(supabaseAdmin, userId)
  if (!v2On) return null
  const profile = await loadProfileV2(supabaseAdmin, userId)
  if (!profile) return null

  // Phase 2: detecta densidade do perfil pra ajustar regras de TRIM/CONCISION/
  // SUMMARY no prompt. small → conteúdo verboso pra preencher; large → trim
  // agressivo pra caber 1 página.
  const density = detectProfileDensity(profile)

  console.log(`[adapt-v2] activating v2 path for user=${userId.slice(0, 8)} job=${jobId.slice(0, 8)} density=${density}`)

  // 2. Build input + inject extra_skills
  const input = buildInputResumeV2(profile)
  if (extraSkillsClean.length > 0) {
    for (const s of extraSkillsClean) {
      const sNorm = normalize(s)
      if (!input.skills.some((x) => normalize(x) === sNorm)) input.skills.push(s)
      tokenize(s).forEach((t) => input.keywordPool.add(t))
    }
  }

  // 3. Cache lookup (prompt_version='v15-v2' isola do cache v1)
  const sourceHash = await sha256Hex(
    pickInputForHashV2(input) + '|' + jobId + '|extras:' + extraSkillsClean.join(','),
  )

  if (!force) {
    const { data: cachedRow } = await supabaseAdmin
      .from('adapted_resumes')
      .select('changes, resume_data, match_score_before, match_score_after, source_hash, prompt_version, model_used')
      .eq('user_id', userId)
      .eq('job_id', jobId)
      .maybeSingle()

    if (
      cachedRow &&
      cachedRow.source_hash === sourceHash &&
      cachedRow.prompt_version === PROMPT_VERSION_V2
    ) {
      trackAIGeneration({
        userId,
        generationType: 'cv_adaptation',
        model: cachedRow.model_used ?? MODEL_V2_DRAFT,
        inputTokens: 0,
        outputTokens: 0,
        latencyMs: 0,
        cached: true,
      }).catch(() => {})
      return {
        status: 200,
        body: {
          changes: cachedRow.changes,
          resume_data: cachedRow.resume_data,
          match_score_before: cachedRow.match_score_before,
          match_score_after: cachedRow.match_score_after,
          cached: true,
          model_used: cachedRow.model_used,
          extra_skills_used: extraSkillsClean,
          version_used: 'v2',
        },
      }
    }
  }

  // 4. Call OpenAI com 1 retry em validation fail
  const userPromptInitial = buildUserPromptV2(input, job, extraSkillsClean, density)
  console.log(`[adapt-v2] calling OpenAI (prompt ${userPromptInitial.length} chars, density=${density})`)

  let parsed: any = null
  let lastErr: ValidationErrorV2 | null = null
  let attempts = 0
  let userPrompt = userPromptInitial
  let tokensUsedTotal = 0

  while (attempts < 2 && parsed === null) {
    attempts++
    const ai = await callOpenAI(SYSTEM_PROMPT_V2, userPrompt, { schema: JSON_SCHEMA_V2 })
    tokensUsedTotal += ai.totalTokens
    console.log(`[adapt-v2] OpenAI responded attempt=${attempts} tokens=${ai.totalTokens}`)

    trackAIGeneration({
      userId,
      generationType: 'cv_adaptation',
      model: MODEL_V2_DRAFT,
      inputTokens: ai.inputTokens,
      outputTokens: ai.outputTokens,
      latencyMs: ai.latencyMs,
      cached: false,
      extra: {
        prompt_chars: userPrompt.length,
        attempt: attempts,
        function_ms_so_far: Date.now() - fnStart,
        version_used: 'v2',
      },
    }).catch(() => {})

    let candidate: any
    try {
      candidate = JSON.parse(ai.content)
    } catch (_e) {
      console.error('[adapt-v2] JSON.parse fail:', ai.content.slice(0, 500))
      return { status: 502, body: { error: 'ai_response_invalid', detail: 'JSON parse failed', version_used: 'v2' } }
    }

    try {
      validateAdaptationV2(input, candidate, job, extraSkillsClean)
      parsed = candidate
    } catch (e) {
      lastErr = e as ValidationErrorV2
      console.warn(`[adapt-v2] validation failed attempt=${attempts}: ` +
        `field=${lastErr.field} message=${lastErr.message}`)
      // DEBUG: serializa um diff curto do candidate vs input pra diagnosticar
      // padrões de hallucination (quais campos GPT está inventando).
      try {
        const summary = {
          input_exp_count: input.experiences.length,
          input_edu_count: input.education.length,
          input_skills_count: input.skills.length,
          input_skills: input.skills.slice(0, 10),
          input_companies: input.experiences.map((e) => e.company),
          input_bullet_ids_count: input.experiences.reduce((n, e) => n + e.bullets.length, 0),
          output_exp_count: Array.isArray(candidate?.resume?.experiences) ? candidate.resume.experiences.length : 0,
          output_edu_count: Array.isArray(candidate?.resume?.education) ? candidate.resume.education.length : 0,
          output_skills_count: Array.isArray(candidate?.resume?.skills) ? candidate.resume.skills.length : 0,
          output_skills: Array.isArray(candidate?.resume?.skills) ? candidate.resume.skills.slice(0, 10) : [],
          output_companies: Array.isArray(candidate?.resume?.experiences)
            ? candidate.resume.experiences.map((e: any) => e?.company ?? '')
            : [],
          output_bullets_first_exp: Array.isArray(candidate?.resume?.experiences) && candidate.resume.experiences[0]?.bullets
            ? candidate.resume.experiences[0].bullets.slice(0, 3).map((b: any) => ({
                action: b?._action,
                src: b?._source_bullet_id,
                text_preview: String(b?.text ?? '').slice(0, 80),
              }))
            : [],
        }
        console.warn(`[adapt-v2] failure_diff attempt=${attempts}: ${JSON.stringify(summary)}`)
      } catch (_e) { /* ignora */ }
      if (attempts < 2) {
        userPrompt = userPromptInitial +
          `\n\n[REJEITADO NA TENTATIVA ${attempts}] Sua resposta violou: ` +
          `${lastErr.field} → ${lastErr.message}. ` +
          `Refaça respeitando integridade dos dados originais.`
      }
    }
  }

  if (parsed === null) {
    const ve = lastErr!
    console.warn(
      `[adapt-v2] rejected after retry user=${userId} job=${jobId} ` +
      `field=${ve.field} message=${ve.message}`,
    )
    return {
      status: 422,
      body: {
        error: 'adaptation_rejected',
        detail: 'A adaptação não passou na verificação de integridade. Tente novamente.',
        field: ve.field,
        field_detail: ve.message,
        version_used: 'v2',
      },
    }
  }

  // 5. Deriva `description` (backward compat com templates v1)
  deriveDescriptionsFromBullets(parsed)

  // 5b. Injeta `language` no resume_data pra o cliente Flutter renderizar
  // headers + glue words no idioma correto. Sem isso, adapted_resume.dart
  // cai no fallback 'pt' e renderiza "SUMÁRIO/EXPERIÊNCIA PROFISSIONAL"
  // sobre conteúdo em EN — Frankenstein PT/EN. O idioma já foi detectado
  // do CV original em `input.language` (linha ~406) e usado pra escolher
  // o prompt EN vs PT — agora propagamos pro output também.
  if (parsed?.resume && typeof parsed.resume === 'object') {
    parsed.resume.language = input.language
  }

  // 6. Match score: pega do cache de match_analyses pra "before".
  // V2 não computa upgrade (computeMatchUpgrade é do v1 e usa bigrams da
  // description string). Por ora retorna before=after=cached. Próxima
  // iteração pode portar essa lógica pro v2.
  const matchR = await supabaseAdmin
    .from('match_analyses')
    .select('score')
    .eq('user_id', userId)
    .eq('job_id', jobId)
    .maybeSingle()
  const realMatchScore = (matchR.data?.score as number | undefined) ?? null
  const matchBefore = realMatchScore
  const matchAfter = realMatchScore

  // 6.9. Descarta "mudanças" que não mudaram nada.
  //
  // O modelo documenta NÃO-mudanças como mudanças, e as próprias justificativas
  // denunciam: "Preservado conforme solicitado", "Não há idiomas listados no
  // input", "A experiência não possui bullets para serem adaptados". Um caso
  // real trazia field=skills com razão "Reordenei as skills para destacar a
  // mais relevante" sobre uma lista de UM item, onde reordenar é impossível.
  //
  // Medido em 02/08/2026: 14 de 129 ajustes reportados (10,9%) eram no-op, em
  // 5 de 31 currículos — e 12 dos 14 estavam em respostas que bateram no teto
  // de 6, o que sugere que o "máximo 6" do prompt vinha sendo lido como meta.
  // O cliente anunciava "6 ajustes aplicados" tendo aplicado 1.
  //
  // Filtra ANTES do upsert de propósito: o que for gravado em `adapted_resumes`
  // já vai limpo, então o cache não perpetua o inflado. (O cliente também
  // filtra, para os registros gravados antes desta correção.)
  const rawChangeCount = parsed.changes?.length ?? 0
  parsed.changes = (parsed.changes ?? []).filter(
    (c) => (c.before ?? '').trim() !== (c.after ?? '').trim(),
  )
  const droppedChanges = rawChangeCount - parsed.changes.length
  if (droppedChanges > 0) {
    console.log(`[adapt-v2] no-op descartadas: ${droppedChanges}/${rawChangeCount} ` +
      `user=${userId} job=${jobId}`)
  }

  // 7. Persist cache
  const upsertR = await supabaseAdmin.from('adapted_resumes').upsert(
    {
      user_id: userId,
      job_id: jobId,
      changes: parsed.changes,
      resume_data: parsed.resume,
      match_score_before: matchBefore,
      match_score_after: matchAfter,
      source_hash: sourceHash,
      prompt_version: PROMPT_VERSION_V2,
      model_used: MODEL_V2_DRAFT,
      computed_at: new Date().toISOString(),
      // F7 quality_score: v2 ainda não computa — null aceito pela coluna.
      quality_score: null,
    },
    { onConflict: 'user_id,job_id' },
  )
  if (upsertR.error) {
    console.error('[adapt-v2] upsert failed:', upsertR.error)
  }

  await supabaseClient.from('ai_generation_logs').insert({
    user_id: userId,
    generation_type: 'resume_adaptation',
    tokens_used: tokensUsedTotal,
  })

  // 8. Telemetria de comparação v1 vs v2 — alimenta dashboard PostHog
  // Bloco F.2 (cv_adapted dashboard). Properties novos do Tier 1 marcam
  // preservação de campos críticos (LinkedIn, GPA, languages, tools).
  const outRes: any = parsed.resume ?? {}
  const outEdu: any[] = Array.isArray(outRes.education) ? outRes.education : []
  captureEvent({
    event: 'cv_adapted',
    distinctId: userId,
    properties: {
      job_id: jobId,
      version_used: 'v2',
      prompt_version: PROMPT_VERSION_V2,
      model_used: MODEL_V2_DRAFT,
      profile_density: density,  // Phase 2: small/medium/large
      validator_retries: Math.max(0, attempts - 1),
      tokens_used: tokensUsedTotal,
      input_experiences: input.experiences.length,
      input_education: input.education.length,
      input_bullets: input.experiences.reduce((n, e) => n + e.bullets.length, 0),
      input_has_linkedin: input.linkedin.length > 0,
      input_has_street_address: input.streetAddress.length > 0,
      input_has_headline: input.headline.length > 0,
      input_languages_count: input.languages.length,
      input_tools_count: input.tools.length,
      input_education_with_gpa: input.education.filter((e) => e.gpa.length > 0).length,
      input_education_with_minors: input.education.filter((e) => e.minors.length > 0).length,
      input_education_with_activities: input.education.filter((e) => e.activities.length > 0).length,
      adapted_experiences: Array.isArray(outRes.experiences) ? outRes.experiences.length : 0,
      output_has_linkedin: String(outRes.linkedin ?? '').length > 0,
      output_has_headline: String(outRes.headline ?? '').length > 0,
      output_languages_count: Array.isArray(outRes.languages) ? outRes.languages.length : 0,
      output_tools_count: Array.isArray(outRes.tools) ? outRes.tools.length : 0,
      output_education_with_gpa: outEdu.filter((e: any) => String(e?.gpa ?? '').length > 0).length,
      output_education_with_minors: outEdu.filter((e: any) => Array.isArray(e?.minors) && e.minors.length > 0).length,
      // Hallucination metric: quantos bullets vieram como synthesized
      synthesized_bullets: countSynthesized(parsed),
      function_ms: Date.now() - fnStart,
    },
  }).catch(() => {})

  console.log(`[adapt-v2] SUCCESS user=${userId} job=${jobId} ` +
    `changes=${parsed.changes?.length ?? 0} synthesized=${countSynthesized(parsed)}`)

  return {
    status: 200,
    body: {
      changes: parsed.changes,
      resume_data: parsed.resume,
      match_score_before: matchBefore,
      match_score_after: matchAfter,
      cached: false,
      model_used: MODEL_V2_DRAFT,
      extra_skills_used: extraSkillsClean,
      version_used: 'v2',
    },
  }
}

function countSynthesized(parsed: any): number {
  let n = 0
  const exps = parsed?.resume?.experiences
  if (!Array.isArray(exps)) return 0
  for (const exp of exps) {
    const bs = Array.isArray(exp?.bullets) ? exp.bullets : []
    for (const b of bs) {
      if (b?._action === 'synthesized') n++
    }
  }
  return n
}
