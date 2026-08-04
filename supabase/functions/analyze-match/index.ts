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
import {
  captureEvent,
  EV_MATCH_ANALYSIS_COMPLETED,
  trackAIGeneration,
  trackEdgeFunctionInvoked,
} from '../_shared/posthog.ts'
import { reconcileRemoteReasons, reconcileSkillsReason, normalizeWorkMode } from './reasons.ts'
import type { MatchReason } from './reasons.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MODEL = 'gpt-4o-mini'
const PROMPT_VERSION = 'v14' // bump quando alterar SYSTEM_PROMPT ou a DERIVAÇÃO do score (invalida cache); v11 = salário removido; v12 = skills técnicas vs soft; v13 = bônus de cargo desejado (+8); v14 = vaga remota deixa de perder ponto por cidade (P1-5, 2026-07-29)
const CACHE_TTL_DAYS = 30
// Subido de 100 → 300 em 2026-05-26 porque PROMPT_VERSION bumps em sequência
// (v5→v9) invalidaram cache de todos os jobs visíveis no app, forçando
// recálculo em massa que esgotava a cota numa única sessão de teste.
// Cliente dispara ~10 chamadas no boot da aba Vagas; cap original tolerava
// só ~10 sessões/dia, frágil em rollouts.
const RATE_LIMIT_PER_DAY = 300
const OPENAI_TIMEOUT_MS = 8000


interface MatchPayload {
  score: number
  reasons: MatchReason[]
  /// true quando o score que a IA retornou divergiu do score derivado das
  /// reasons (sinal de erro de aritmética do gpt). Só no caminho AI normal.
  divergence?: boolean
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
  return (
    (!Array.isArray(areas) || areas.length === 0) &&
    (!Array.isArray(locs) || locs.length === 0) &&
    (!Array.isArray(wm) || wm.length === 0) &&
    (!Array.isArray(jt) || jt.length === 0)
  )
}

async function pickPrefsForHash(
  prefs: any,
  gamificationData: any,
  profileText: string,
): Promise<string> {
  const safe = (v: any) => (v == null ? null : v)
  const whoIAm = (gamificationData?.whoIAm?.derived) || {}
  const imported = gamificationData?.imported_resume || {}
  // Hash do CV inteiro (não só primeiros 200 chars) — user que edita o miolo
  // do CV mantendo o cabeçalho intacto invalida cache corretamente agora.
  const cvText = imported.raw_text || ''
  const cvHash = cvText ? await sha256Hex(cvText) : ''
  // Hash do pseudo-texto agregado das tabelas profile_* — invalida cache
  // quando o user edita Profile Editor ou re-extrai CV.
  const profileHash = profileText ? await sha256Hex(profileText) : ''
  const canonical = {
    areas: safe(prefs?.areas),
    locations: safe(prefs?.locations),
    work_models: safe(prefs?.work_models),
    job_types: safe(prefs?.job_types),
    // Entra no hash pra que editar SÓ o cargo na trilha invalide o cache do
    // match (senão o +8 só apareceria após mexer noutra dimensão ou o TTL).
    desired_position: safe(prefs?.desired_position),
    skills: safe(whoIAm.skills),
    summary: safe(whoIAm.summary),
    interests: safe(whoIAm.interests),
    cv_text_len: cvText.length,
    cv_text_hash: cvHash,
    profile_text_len: profileText.length,
    profile_text_hash: profileHash,
  }
  return JSON.stringify(canonical)
}

/**
 * Carrega preferências de vaga lendo PRIMEIRO das tabelas relacionais
 * (`profile_job_preferences` + `profile_desired_titles` +
 * `profile_other_locations`), com fallback pro `user_preferences` legacy
 * quando o relacional está vazio.
 *
 * Por que: a aba Perfil → Preferências do app salva no relacional via
 * `PreferencesViewModel`. O filtro da aba Vagas (engrenagem) ainda salva
 * no legacy `user_preferences` via `JobsViewModel`. Sem ler de ambos,
 * mudanças via Perfil ficam invisíveis pro match score.
 *
 * Mapeamento (relacional → shape esperado pelo prompt):
 *   - desired_titles (rows)            → areas[]
 *   - primary_location_city + others   → locations[]
 *   - work_mode (text[])               → work_models[]
 *   - job_types (text[])               → job_types[]
 *
 * Retorna o mesmo shape que `user_preferences` pra não mudar o resto
 * da edge function.
 */

async function loadPrefs(client: any, userId: string): Promise<any> {
  try {
    const [jpR, dtR, olR, legacyR] = await Promise.all([
      client.from('profile_job_preferences').select('*').eq('user_id', userId).maybeSingle(),
      client.from('profile_desired_titles').select('title').eq('user_id', userId),
      client.from('profile_other_locations').select('city').eq('user_id', userId),
      client.from('user_preferences').select('*').eq('user_id', userId).maybeSingle(),
    ])

    const jp = jpR.data as any
    const desiredTitles = (dtR.data ?? []) as Array<{ title?: string }>
    const otherLocs = (olR.data ?? []) as Array<{ city?: string }>
    const legacy = (legacyR.data ?? {}) as any

    // Considera "relacional preenchido" se qualquer um dos 4 sinais tem dado.
    const relAreas = desiredTitles
      .map((d) => (d?.title ?? '').trim())
      .filter((s) => s.length > 0)
    const relWorkModes = Array.isArray(jp?.work_mode)
      ? jp.work_mode
          .filter((s: any) => typeof s === 'string' && s.length > 0)
          .map((s: string) => normalizeWorkMode(s))
      : []
    const relJobTypes = Array.isArray(jp?.job_types)
      ? jp.job_types.filter((s: any) => typeof s === 'string' && s.length > 0)
      : []
    // Inclui state como segundo elemento da location preferida quando o
    // user só preencheu state (sem city). Sem isso, user que mora em "MG"
    // sem cidade específica não casava com vagas em Belo Horizonte/MG.
    const relLocations: string[] = []
    if (jp?.primary_location_city) {
      relLocations.push(String(jp.primary_location_city))
    }
    if (jp?.primary_location_state) {
      relLocations.push(String(jp.primary_location_state))
    }
    for (const o of otherLocs) {
      const c = (o?.city ?? '').trim()
      if (c.length > 0) relLocations.push(c)
    }

    const hasRelational =
      relAreas.length > 0 ||
      relWorkModes.length > 0 ||
      relJobTypes.length > 0 ||
      relLocations.length > 0

    if (!hasRelational) {
      // Sem dados no relacional → usa legacy puro (cobre os ~381 users
      // pré-migração que só têm user_preferences). Mas preserva o cargo desejado
      // (só existe em profile_job_preferences) pro bônus valer no Cenário B (CV).
      const dp =
        typeof jp?.desired_position === 'string' &&
        jp.desired_position.trim().length > 0
          ? jp.desired_position.trim()
          : null
      return dp ? { ...legacy, desired_position: dp } : legacy
    }

    // Hidrata cada array preferindo o relacional; cai pro legacy quando o
    // relacional está vazio (user pode ter editado só uma seção).
    return {
      areas: relAreas.length > 0 ? relAreas : (legacy.areas ?? []),
      locations: relLocations.length > 0 ? relLocations : (legacy.locations ?? []),
      work_models: relWorkModes.length > 0 ? relWorkModes : (legacy.work_models ?? []),
      job_types: relJobTypes.length > 0 ? relJobTypes : (legacy.job_types ?? []),
      // Cargo desejado: bônus no match (+8) quando bate com o título da vaga.
      // Não conta como sinal relacional (não cria match sozinho); só refina.
      desired_position:
        typeof jp?.desired_position === 'string' &&
        jp.desired_position.trim().length > 0
          ? jp.desired_position.trim()
          : null,
      // min_match_score afeta filtro client-side, não o prompt. Passa adiante.
      min_match_score: legacy.min_match_score ?? null,
    }
  } catch (e) {
    console.error('loadPrefs failed, falling back to empty:', (e as Error).message)
    return {}
  }
}

/**
 * Carrega snapshot das tabelas profile_* e devolve um pseudo-texto
 * concatenado. Substitui `imported_resume.raw_text` como fonte primária do
 * perfil pós Fase 2 da migração profile-first. Cobre users do fluxo manual
 * (preencheram via Profile Editor sem importar CV) — antes esses caíam no
 * Cenário C "Sem perfil" porque whoIAm.derived + raw_text estavam vazios.
 *
 * Falhas individuais caem pra string vazia em vez de propagar — a função
 * é best-effort e o cenário fallback é o legacy.
 *
 * Devolve TAMBÉM a lista crua de skills declaradas (achado A4, 03/08/2026): a
 * reconciliação determinística de `reasons.ts` precisa saber se a pessoa tem
 * skills pra decidir se a frase "você não declarou skills" é mentira. Sai daqui
 * porque a consulta a `profile_skills` já é feita — abrir uma segunda query só
 * pra contar seria latência de graça.
 */
async function buildProfileText(
  client: any,
  userId: string,
): Promise<{ text: string; skills: string[] }> {
  try {
    const [
      personalR,
      experiencesR,
      educationR,
      skillsR,
      languagesR,
      certificationsR,
      projectsR,
      interestsR,
      awardsR,
      courseworkR,
    ] = await Promise.all([
      client.from('profile_personal').select('headline,summary,first_name,last_name').eq('user_id', userId).maybeSingle(),
      client.from('profile_experiences').select('title,company,location,profile_bullets(text)').eq('user_id', userId),
      client.from('profile_education').select('institution,degree,profile_education_majors(name),profile_education_minors(name),profile_education_activities(text)').eq('user_id', userId),
      client.from('profile_skills').select('name, skills_catalog(canonical_name, category)').eq('user_id', userId),
      client.from('profile_languages').select('name').eq('user_id', userId),
      client.from('profile_certifications').select('name,issuer').eq('user_id', userId),
      client.from('profile_projects').select('name,description,profile_project_bullets(text)').eq('user_id', userId),
      client.from('profile_interests').select('name').eq('user_id', userId),
      client.from('profile_awards').select('name').eq('user_id', userId),
      client.from('profile_coursework').select('name').eq('user_id', userId),
    ])

    const lines: string[] = []
    const p = personalR.data
    if (p) {
      if (p.headline) lines.push(String(p.headline))
      if (p.summary) lines.push(String(p.summary))
    }
    // Skills agrupadas por categoria canônica (taxonomia P5): técnicas
    // (hard+tool) e comportamentais (soft) saem ROTULADAS e separadas, pra IA
    // casar requisito técnico só contra as técnicas. Skill sem canônica (cauda)
    // entra em "outras" pra não perder o sinal de overlap com o CV.
    // Nomes como a PESSOA declarou (`profile_skills.name`), não a canônica: é o
    // que ela vê no editor e vai reconhecer no cartão. Cai pra canônica só se o
    // nome cru vier vazio. Alimenta `reconcileSkillsReason` (achado A4).
    const declaredSkills: string[] = []
    {
      const technical = new Set<string>()
      const soft = new Set<string>()
      const other: string[] = []
      for (const s of (skillsR.data ?? [])) {
        const cat = s?.skills_catalog?.category
        const canon = s?.skills_catalog?.canonical_name
        const shown = String(s?.name ?? canon ?? '').trim()
        if (shown && !declaredSkills.includes(shown)) declaredSkills.push(shown)
        if (canon && (cat === 'hard' || cat === 'tool')) technical.add(String(canon))
        else if (canon && cat === 'soft') soft.add(String(canon))
        else if (canon && cat === 'language') technical.add(String(canon))
        else if (s?.name) other.push(String(s.name))
      }
      if (technical.size > 0) lines.push(`Skills técnicas: ${[...technical].join(', ')}`)
      if (soft.size > 0) lines.push(`Skills comportamentais (soft): ${[...soft].join(', ')}`)
      if (other.length > 0) lines.push(`Outras skills declaradas: ${other.join(', ')}`)
    }
    for (const exp of (experiencesR.data ?? [])) {
      if (exp?.title) lines.push(String(exp.title))
      if (exp?.company) lines.push(String(exp.company))
      if (exp?.location) lines.push(String(exp.location))
      for (const b of (exp?.profile_bullets ?? [])) {
        if (b?.text) lines.push(String(b.text))
      }
    }
    for (const edu of (educationR.data ?? [])) {
      if (edu?.institution) lines.push(String(edu.institution))
      if (edu?.degree) lines.push(String(edu.degree))
      for (const m of (edu?.profile_education_majors ?? [])) {
        if (m?.name) lines.push(String(m.name))
      }
      for (const m of (edu?.profile_education_minors ?? [])) {
        if (m?.name) lines.push(String(m.name))
      }
      for (const a of (edu?.profile_education_activities ?? [])) {
        if (a?.text) lines.push(String(a.text))
      }
    }
    for (const c of (certificationsR.data ?? [])) {
      if (c?.name) lines.push(String(c.name))
      if (c?.issuer) lines.push(String(c.issuer))
    }
    for (const l of (languagesR.data ?? [])) {
      if (l?.name) lines.push(String(l.name))
    }
    for (const proj of (projectsR.data ?? [])) {
      if (proj?.name) lines.push(String(proj.name))
      if (proj?.description) lines.push(String(proj.description))
      for (const b of (proj?.profile_project_bullets ?? [])) {
        if (b?.text) lines.push(String(b.text))
      }
    }
    for (const i of (interestsR.data ?? [])) {
      if (i?.name) lines.push(String(i.name))
    }
    for (const a of (awardsR.data ?? [])) {
      if (a?.name) lines.push(String(a.name))
    }
    for (const c of (courseworkR.data ?? [])) {
      if (c?.name) lines.push(String(c.name))
    }

    return { text: lines.join('\n'), skills: declaredSkills }
  } catch (e) {
    console.error('buildProfileText failed (fallback to empty):', (e as Error).message)
    return { text: '', skills: [] }
  }
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

CENÁRIO A — candidato TEM preferências declaradas (áreas/cidades/modelo/tipo):
  Pesos: Área 30, Tipo 20, Localização 15, Modelo 15, Skills 10.
  BÔNUS opcional: Cargo desejado +8 (ver regra abaixo) — só some quando o cargo bate.
  Avalie SOMENTE contra os dados que o candidato declarou.
  (Salário NÃO é dimensão de match — o app não coleta expectativa salarial.)

CENÁRIO B — candidato SEM preferências MAS COM perfil (CV importado, skills, sobre, interesses):
  Use APENAS o CV/perfil como fonte de verdade do candidato.
  Pesos: Área (afinidade CV↔vaga) 40, Skills (sobreposição com requisitos) 40, Tipo 10, Modelo/Local 10.
  Do CV você pode extrair área de formação, skills, cidade, nível — desde que ESTEJA EXPLÍCITO no texto.

CENÁRIO C — candidato SEM preferências E SEM perfil (cadastro incompleto):
  CRITÉRIO ESTRITO PARA ATIVAR:
    - TODAS as preferências estão vazias: areas=[], locations=[], work_models=[], job_types=[]
    - E TODO o perfil está vazio: sem skills, sem summary, sem interesses, sem CV importado, sem perfil estruturado.
  Se QUALQUER uma das prefs OU do perfil tem valor (mesmo que só "Modelos preferidos: ['remote']"
  ou só "Skills: ['excel']"), você JÁ TEM dado — use CENÁRIO A.

  PARE só quando TUDO está vazio. Retorne EXATAMENTE:
  {"score": 50, "reasons": [{"label":"Sem perfil","matched":false,"weight":0,"detail":"Defina seus objetivos ou complete seu perfil para ter um match mais preciso."}]}
  Não tente analisar. Não tente inferir do título da vaga. PARE.

═══════════════════════════════════════════════════════════════════
COMO AVALIAR cada dimensão (Cenário A/B):

- matched=true: o dado DO CANDIDATO bate com o requisito da vaga. Some o weight.
- matched=false, weight=0: o candidato NÃO declarou esse dado (não penalize, mas também não some).
- matched=false, weight>0: o candidato declarou MAS não bate (raro — só quando há conflito explícito).

REGRA CRÍTICA — DIMENSÃO SKILLS (peso 10) É TÉCNICA:
A dimensão "Skills" compara as "Skills técnicas" do candidato (linguagens, ferramentas,
conhecimentos) com os requisitos TÉCNICOS da vaga. As "Skills comportamentais (soft)"
(ex.: comunicação, trabalho em equipe, proatividade, organização) são CONTEXTO —
NÃO contam como match de skill técnica e NÃO inflam o peso de Skills. Se o candidato
só tem soft skills e a vaga pede técnico, Skills matched=false, weight=0.

REGRA CRÍTICA — LISTAS DE PREFERÊNCIAS (areas/locations/work_models/job_types):
Quando o candidato declarou MÚLTIPLOS valores numa lista (ex: work_models=["remoto", "presencial"]),
isso significa que QUALQUER UM desses valores serve pra ele. NÃO é "indeciso" — é "aceita várias".

  Se o atributo da vaga está NA lista do candidato → matched=true (some o weight inteiro).
  Se NÃO está → matched=false (mesmo que o candidato tenha outras opções listadas).

  Exemplo: candidato work_models=["remoto", "presencial"], vaga work_model="presencial"
    → matched=TRUE (presencial está na lista), weight=15 contribui pro score.

  Exemplo: candidato work_models=["remoto"], vaga work_model="presencial"
    → matched=FALSE (presencial NÃO está na lista), weight=15 não contribui.

Aplica-se identicamente pra areas, locations, job_types.

REGRA — BÔNUS DE CARGO DESEJADO (opcional, +8):
Se o candidato declarou "Cargo/posição desejada" (ex.: "Desenvolvedor Front-end")
E ele bate com o título/função da vaga (mesmo cargo, sinônimo, ou variação de gênero/nível —
ex.: "Desenvolvedor Front-end" ↔ "Desenvolvedora Front-End Júnior"), ADICIONE uma reason EXTRA:
  {"label":"Cargo desejado","matched":true,"weight":8,"detail":"..."}
É um bônus PEQUENO que premia o alinhamento exato de cargo — NÃO substitui nem infla as 5 dimensões.
Se o candidato NÃO declarou cargo, OU o cargo NÃO bate com a vaga, NÃO inclua essa reason (sem bônus).
Nunca use weight diferente de 8 nessa reason; nunca a inclua com matched=false.

Seja generoso em afinidade SEMÂNTICA REAL (skills):
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
  {"label":"Skills","matched":false,"weight":0,"detail":"Você não declarou skills para comparação."}
]}
NOTA: 30+20 = 50. NÃO inflar para 70, 85 ou 100 só porque a única dimensão que existe bateu.

# Exemplo 3 — Cenário C, sem dado (ATIVAR APENAS quando TUDO vazio)
INPUT: areas=[], locations=[], work_models=[], job_types=[], sem whoIAm, sem skills, sem CV
       vaga: qualquer
OUTPUT (correto):
{"score": 50, "reasons": [
  {"label":"Sem perfil","matched":false,"weight":0,"detail":"Defina seus objetivos ou complete seu perfil para ter um match mais preciso."}
]}

# Exemplo 4 — Cenário A com SÓ 1 dimensão (NÃO é Cenário C!)
INPUT: areas=[], locations=[], work_models=["remoto"], job_types=[]
       perfil tem skills=["Excel"]
       vaga: "Estágio Marketing", modelo="presencial"
OUTPUT (correto — usa CENÁRIO A com SÓ as dimensões que existem):
{"score": 0, "reasons": [
  {"label":"Área","matched":false,"weight":0,"detail":"Você não declarou áreas de interesse."},
  {"label":"Tipo","matched":false,"weight":0,"detail":"Você não declarou tipo de vaga preferido."},
  {"label":"Localização","matched":false,"weight":0,"detail":"Você não declarou cidade preferida."},
  {"label":"Modelo","matched":false,"weight":15,"detail":"Você prefere remoto, mas a vaga é presencial."},
  {"label":"Skills","matched":false,"weight":10,"detail":"Excel não aparece nos requisitos desta vaga."}
]}
NOTA: 0 matched=true → score 0. NÃO retornar "Sem perfil" só porque a maioria está vazia — o user JÁ DECLAROU "remoto" e "Excel".

# Exemplo 5 — Cenário A com BÔNUS de cargo desejado
INPUT: candidato declarou areas=["Tecnologia"], job_types=["estagio"], Cargo/posição desejada="Desenvolvedor Front-end"
       vaga: "Estágio em Desenvolvimento Front-end", área="Tecnologia", tipo="estagio"
OUTPUT (correto):
{"score": 58, "reasons": [
  {"label":"Área","matched":true,"weight":30,"detail":"Tecnologia bate com seu interesse declarado."},
  {"label":"Tipo","matched":true,"weight":20,"detail":"Estágio é o tipo que você procura."},
  {"label":"Localização","matched":false,"weight":0,"detail":"Você não declarou cidade preferida."},
  {"label":"Modelo","matched":false,"weight":0,"detail":"Você não declarou modelo de trabalho."},
  {"label":"Skills","matched":false,"weight":0,"detail":"Você não declarou skills para comparar."},
  {"label":"Cargo desejado","matched":true,"weight":8,"detail":"A vaga é exatamente o cargo Front-end que você busca."}
]}
NOTA: 30+20+8 = 58. O bônus de cargo só entra porque o cargo declarado bate com a vaga.

═══════════════════════════════════════════════════════════════════
OUTPUT JSON ESTRITO:
{"score": <int 0..100, soma EXATA dos weights matched>, "reasons": [{"label": "...", "matched": <bool>, "weight": <int>, "detail": "..."}, ...]}

CADA reason.detail: máximo 150 chars, PT-BR, segunda pessoa ("sua área", "você tem...").
NÃO inclua texto fora do JSON. NÃO adicione fences markdown.`

function buildUserPrompt(opts: {
  job: any
  prefs: any
  gamificationData: any
  profileText: string
}): string {
  const { job, prefs, gamificationData, profileText } = opts
  const whoIAm = gamificationData?.whoIAm?.derived || {}
  const rawCv = gamificationData?.imported_resume?.raw_text
  const noPrefs = hasNoPrefs(prefs)
  const noStructuredProfile =
    !whoIAm.skills && !whoIAm.summary && !whoIAm.interests
  // Fonte primária do perfil pós Fase 2: pseudo-texto das tabelas profile_*.
  // Cobre o fluxo manual (Profile Editor sem upload de CV) que antes caía
  // em Cenário C "Sem perfil". Mantém raw_text legacy como fallback pros
  // users históricos que ainda não foram migrados.
  const hasProfileText = profileText.length > 0
  // Quando o perfil é a única fonte → mais espaço (3000 chars). Senão 1500.
  const profileBudget = noPrefs && noStructuredProfile && hasProfileText ? 3000 : 1500
  const profileSection = hasProfileText ? profileText.slice(0, profileBudget) : ''
  const cvBudget = noPrefs && noStructuredProfile && rawCv && !hasProfileText ? 3000 : 1500
  const cvSection = extractRelevantCvSection(rawCv, cvBudget)

  const lines: string[] = []

  // ── CANDIDATO ─────────────────────────────────────────────────────
  if (noPrefs && noStructuredProfile && (profileSection || cvSection)) {
    // CENÁRIO B: prefs vazias mas tem perfil (tabelas profile_* ou CV).
    // Profile_* é fonte de verdade quando presente; CV legacy só como fallback.
    lines.push('## CANDIDATO (sem preferências definidas — perfil EXTRAÍDO dos dados abaixo)')
    lines.push('')
    lines.push('Use o perfil abaixo como fonte de verdade pra inferir área de')
    lines.push('interesse, skills e experiência do candidato. Trate-o como CENÁRIO B')
    lines.push('do system prompt.')
    lines.push('')
    if (profileSection) {
      lines.push('### Perfil estruturado (skills, experiências, formação, etc):')
      lines.push(profileSection)
    } else if (cvSection) {
      lines.push('### CV importado (texto bruto):')
      lines.push(cvSection)
    }
  } else {
    // CENÁRIO A (com prefs) ou misto (prefs + perfil/CV).
    lines.push('## CANDIDATO')
    lines.push(`Áreas de interesse: ${JSON.stringify(prefs?.areas ?? [])}`)
    lines.push(`Cidades preferidas: ${JSON.stringify(prefs?.locations ?? [])}`)
    lines.push(`Modelos preferidos: ${JSON.stringify(prefs?.work_models ?? [])}`)
    lines.push(`Tipos preferidos: ${JSON.stringify(prefs?.job_types ?? [])}`)
    if (prefs?.desired_position) {
      lines.push(
        `Cargo/posição desejada: ${JSON.stringify(prefs.desired_position)}`,
      )
    }
    // whoIAm.derived legacy só entra se NÃO temos profile_text — o
    // profile_text das tabelas relacionais é fonte mais rica e atualizada.
    // Pra users históricos sem migração profile-first, whoIAm.derived ainda
    // é o melhor sinal disponível.
    if (hasProfileText) {
      lines.push(`Perfil estruturado (skills/experiências/formação):\n${profileSection}`)
    } else {
      if (whoIAm.skills) lines.push(`Skills (resumo): ${String(whoIAm.skills).slice(0, 500)}`)
      if (whoIAm.summary) lines.push(`Sobre mim: ${String(whoIAm.summary).slice(0, 300)}`)
      if (whoIAm.interests) lines.push(`Interesses: ${String(whoIAm.interests).slice(0, 300)}`)
    }
    if (cvSection) lines.push(`CV importado (trecho relevante):\n${cvSection}`)
  }

  lines.push('')
  lines.push('## VAGA')
  lines.push(`Título: ${job.title}`)
  lines.push(`Área: ${job.area || 'não informada'}`)
  lines.push(`Tipo: ${job.job_type}`)
  // Sanitiza location_city: ~23 vagas em prod têm city="Remoto"/"Brasil"
  // (vindas do sync que não conseguiu extrair cidade real). Isso confundia
  // a IA — "São Paulo" do user nunca casava com "Remoto" da vaga, mesmo
  // quando work_model='remoto' já cobria essa dimensão.
  const cityRaw = (job.location_city || '').trim()
  const isPseudoCity = /^(remoto|brasil|brazil|home[- ]?office)$/i.test(cityRaw)
  const cityForPrompt = isPseudoCity ? '' : cityRaw
  const stateForPrompt = (job.location_state || '').trim()
  const locParts = [cityForPrompt, stateForPrompt].filter((s) => s.length > 0)
  lines.push(`Localização: ${locParts.join(', ') || 'não informada'}`)
  lines.push(`Modelo: ${job.work_model}`)

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
        max_tokens: 800, // 5 dims + bônus de cargo (≤6 reasons) × ~250 chars + folga
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

function parseAndValidate(
  raw: string,
  job?: any,
  prefs?: any,
  declaredSkills: string[] = [],
): MatchPayload {
  // Strip ```json``` fences se existirem
  let text = raw.trim()
  if (text.startsWith('```json')) text = text.slice(7)
  if (text.startsWith('```')) text = text.slice(3)
  if (text.endsWith('```')) text = text.slice(0, -3)
  text = text.trim()

  const parsed = JSON.parse(text)

  const rawReasons = Array.isArray(parsed.reasons) ? parsed.reasons : []
  // Preserva a reason de bônus "Cargo desejado" (a IA a emite por último; se ela
  // emitir reasons extras antes, o slice(0,6) a cortaria e o +8 sumiria do score
  // E das reasons). Extrai por label e garante que entre nas 6 mantidas.
  const isCargoReason = (r: any) =>
    String(r?.label ?? '').toLowerCase().includes('cargo desejado')
  const cargoReason = rawReasons.find(isCargoReason)
  const baseReasons = rawReasons.filter((r: any) => !isCargoReason(r))
  const keptReasons = cargoReason
    ? [...baseReasons.slice(0, 5), cargoReason]
    : baseReasons.slice(0, 6)
  const parsedReasons: MatchReason[] = keptReasons.map((r: any) => ({
    label: String(r?.label ?? ''),
    matched: r?.matched === true,
    weight: Number.isFinite(Number(r?.weight)) ? Number(r.weight) : 0,
    detail: r?.detail ? String(r.detail).slice(0, 200) : undefined,
  }))

  // Correção determinística ANTES de derivar o score: razão e score precisam
  // contar a mesma história (há inclusive um alerta de divergência abaixo).
  const workModeFixed = job
    ? reconcileRemoteReasons(parsedReasons, job, prefs)
    : parsedReasons
  // A4: tira a negação falsa de skills. NÃO mexe em matched/weight, então o
  // score derivado logo abaixo é idêntico com e sem esta linha.
  const reasons = reconcileSkillsReason(workModeFixed, declaredSkills)

  // Detecta o "Cenário C" canônico (1 reason com label "Sem perfil") — o
  // prompt manda retornar score=50 explicitamente nesse caso, então
  // respeitamos. Em qualquer outro caso, IGNORAMOS o campo `score` da IA
  // e derivamos a partir das reasons. Por quê: GPT-4o-mini erra a
  // aritmética básica algumas vezes (ex: Skills matched=true weight=10,
  // mas retorna score=0). Calcular server-side garante consistência.
  const isScenarioC =
    reasons.length === 1 &&
    reasons[0].label === 'Sem perfil' &&
    !reasons[0].matched

  let finalScore: number
  if (isScenarioC) {
    finalScore = 50
  } else {
    // Soma EXATA dos weights onde matched=true.
    finalScore = reasons
      .filter((r) => r.matched)
      .reduce((sum, r) => sum + Math.max(0, r.weight), 0)
  }
  const clampedScore = Math.max(0, Math.min(100, Math.round(finalScore)))

  // Log se a IA divergiu do score derivado — sinal de regressão a investigar.
  const aiScore = Number(parsed.score)
  const divergence =
    Number.isFinite(aiScore) && Math.abs(aiScore - clampedScore) > 0
  if (divergence) {
    console.warn(
      `[analyze-match] score divergence: ai=${aiScore} derived=${clampedScore} reasons=${JSON.stringify(
        reasons.map((r) => ({ l: r.label, m: r.matched, w: r.weight })),
      )}`,
    )
  }

  return { score: clampedScore, reasons, divergence }
}


// ────────────────────────────────────────────────────────────────────────────
// Main handler
// ────────────────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // B.7 do plano v2 — timer pra trackEdgeFunctionInvoked emitido no
  // success path e no catch outer.
  const fnStart = Date.now()

  // Antes, das 6 saídas de erro só DUAS emitiam telemetria (sucesso e catch
  // outer). Como o catch outer só classifica timeout vs internal, o painel era
  // fisicamente incapaz de mostrar qualquer outra falha — e "100% dos erros
  // são timeout" virava conclusão circular. O 429 é o caso que mais doía:
  // usuário batendo no teto diário de análises não aparecia em lugar nenhum.
  const failWith = (
    errorCode: string,
    status: number,
    body: Record<string, unknown>,
    distinctId = `edge_function:analyze-match`,
  ) => {
    trackEdgeFunctionInvoked({
      functionName: 'analyze-match',
      distinctId,
      durationMs: Date.now() - fnStart,
      status: 'error',
      errorCode,
      extra: { http_status: status },
    }).catch(() => {})
    return jsonResponse(body, status)
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } },
    )

    // 1. Auth
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
    if (authError || !user) return failWith('unauthorized', 401, { error: 'Unauthorized' })

    // 2. Parse input
    const body = await req.json().catch(() => ({}))
    const jobId: string | undefined = body?.job_id
    if (!jobId || typeof jobId !== 'string') {
      return failWith('bad_request', 400, { error: 'job_id required' }, user.id)
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
      return failWith(
        'rate_limited',
        429,
        { error: `Rate limit exceeded. Maximum ${RATE_LIMIT_PER_DAY} match analyses per day.` },
        user.id,
      )
    }

    // 4. Fetch em paralelo: job, profile (legacy), prefs unificadas, profile_*
    // `loadPrefs` lê do relacional `profile_job_preferences` +
    // `profile_desired_titles` + `profile_other_locations` E faz fallback
    // pro `user_preferences` legacy. Sem isso, mudanças via aba Perfil →
    // Preferências (que escreve no relacional) ficam invisíveis pro match.
    const [jobR, profileR, prefs, profileSnapshot] = await Promise.all([
      supabaseClient.from('jobs').select('*').eq('id', jobId).maybeSingle(),
      supabaseClient.from('user_profiles').select('gamification_data').eq('id', user.id).maybeSingle(),
      loadPrefs(supabaseClient, user.id),
      buildProfileText(supabaseClient, user.id),
    ])
    // `text` segue sendo o pseudo-texto de sempre (hash de cache, bypass do
    // Cenário C, prompt); `skills` é novo e só alimenta a reconciliação do A4.
    const profileText = profileSnapshot.text
    const declaredSkills = profileSnapshot.skills

    if (jobR.error || !jobR.data) return failWith('job_not_found', 404, { error: 'job_not_found' }, user.id)
    const job = jobR.data
    const gamificationData = profileR.data?.gamification_data ?? {}

    // 5. Compute profile_hash + cache lookup
    const profileHash = await sha256Hex(await pickPrefsForHash(prefs, gamificationData, profileText))
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
      // Cache hit: emite com tokens=0 e cached=true pra alimentar dashboard
      // de cache hit rate (objetivo do plano F3.3).
      trackAIGeneration({
        userId: user.id,
        generationType: 'match_analysis',
        model: cachedRow.model_used ?? MODEL,
        inputTokens: 0,
        outputTokens: 0,
        latencyMs: 0,
        cached: true,
      }).catch(() => {})
      // Match v9 dashboard: saúde do sistema de match (model_used, cache_hit,
      // score_divergence). Fire-and-forget — nunca bloqueia/quebra a resposta.
      captureEvent({
        event: EV_MATCH_ANALYSIS_COMPLETED,
        distinctId: user.id,
        properties: {
          model_used: cachedRow.model_used ?? MODEL,
          cache_hit: true,
          score_divergence: false,
          scenario: 'cache',
        },
      }).catch(() => {})
      // O caminho de cache devolvia `reasons` CRU — a reconciliação só rodava
      // na geração (§ parseAndValidate). Resultado: uma análise gravada antes
      // da correção seguia servindo a penalidade falsa de vaga remota, de
      // graça, por até 30 dias.
      //
      // Re-derivar o score junto NÃO é opcional: reconciliar as razões e
      // devolver o score antigo faria razão e score contarem histórias
      // diferentes — a mesma classe de bug que a derivação server-side existe
      // para matar.
      const cachedReasons = Array.isArray(cachedRow.reasons) ? cachedRow.reasons : []
      const workModeFixed = job ? reconcileRemoteReasons(cachedReasons, job, prefs) : cachedReasons
      // A4: a mesma correção do caminho de geração roda aqui — é o que faz as
      // ~14 mil linhas JÁ GRAVADAS pararem de mentir sem precisar de bump de
      // PROMPT_VERSION (que invalidaria o cache inteiro e, pior, derrubaria o
      // cliente no motor determinístico enquanto `app_config` não acompanhasse).
      const fixedReasons = reconcileSkillsReason(workModeFixed, declaredSkills)
      const reasonsChanged = fixedReasons !== cachedReasons
      const fixedScore = reasonsChanged
        ? Math.max(0, Math.min(100, Math.round(
          fixedReasons.filter((r: MatchReason) => r.matched)
            .reduce((s: number, r: MatchReason) => s + Math.max(0, r.weight), 0),
        )))
        : cachedRow.score

      return jsonResponse({
        score: fixedScore,
        reasons: fixedReasons,
        cached: true,
        model_used: cachedRow.model_used,
      })
    }

    // 6a. BYPASS M3.4 (Passo 5 do plano match-score, 2026-05-27):
    // Quando o user é 100% fantasma (zero prefs E zero perfil), pula a
    // chamada de IA (que custaria $ e latência) e retorna direto o Cenário C.
    // Cliente já mapeia esse retorno pra MatchResult.unknown() — UX idêntica
    // ao fluxo anterior, sem custo extra. Economiza ~5-15% das chamadas
    // pra users novos antes de preencher o perfil.
    //
    // O check é mais estrito que `hasNoPrefs`: também exige que profileText
    // (snapshot relacional) E whoIAm (legacy) E raw_text (CV importado)
    // estejam vazios. Se houver QUALQUER sinal — incluindo 1 skill solta no
    // relacional ou um CV importado — IA é chamada normalmente.
    const whoIAm = gamificationData?.whoIAm?.derived ?? {}
    const rawCv = gamificationData?.imported_resume?.raw_text ?? ''
    const hasAnyProfile =
      profileText.length > 0 ||
      rawCv.length > 0 ||
      !!whoIAm.skills ||
      !!whoIAm.summary ||
      !!whoIAm.interests
    if (hasNoPrefs(prefs) && !hasAnyProfile) {
      const scenarioCPayload: MatchPayload = {
        score: 50,
        reasons: [
          {
            label: 'Sem perfil',
            matched: false,
            weight: 0,
            detail: 'Defina seus objetivos ou complete seu perfil para ter um match mais preciso.',
          },
        ],
      }
      // Persiste cache pra evitar nova chamada na próxima abertura do feed.
      await supabaseClient.from('match_analyses').upsert({
        user_id: user.id,
        job_id: jobId,
        score: scenarioCPayload.score,
        reasons: scenarioCPayload.reasons,
        model_used: 'bypass_scenario_c',
        prompt_version: PROMPT_VERSION,
        profile_hash: profileHash,
        computed_at: new Date().toISOString(),
      }, { onConflict: 'user_id,job_id' })

      console.log(`[analyze-match] bypass scenario_c user=${user.id} (zero prefs + zero profile)`)

      captureEvent({
        event: EV_MATCH_ANALYSIS_COMPLETED,
        distinctId: user.id,
        properties: {
          model_used: 'bypass_scenario_c',
          cache_hit: false,
          score_divergence: false,
          scenario: 'C',
        },
      }).catch(() => {})
      return jsonResponse({
        score: scenarioCPayload.score,
        reasons: scenarioCPayload.reasons,
        cached: false,
        model_used: 'bypass_scenario_c',
      })
    }

    // 6b. Call OpenAI (fluxo normal — user tem ao menos 1 sinal)
    const userPrompt = buildUserPrompt({ job, prefs, gamificationData, profileText })
    const aiStart = Date.now()
    const ai = await callOpenAI(SYSTEM_PROMPT, userPrompt)
    // PostHog LLM Analytics — habilita comparativo IA vs determinístico
    // (relatório mostrou like rate IA=16% vs determinístico=24%).
    trackAIGeneration({
      userId: user.id,
      generationType: 'match_analysis',
      model: MODEL,
      inputTokens: ai.inputTokens,
      outputTokens: ai.outputTokens,
      latencyMs: Date.now() - aiStart,
      cached: false,
    }).catch(() => {})

    let payload: MatchPayload
    try {
      payload = parseAndValidate(ai.content, job, prefs, declaredSkills)
    } catch (e) {
      console.error('Failed to parse AI output:', ai.content)
      return failWith(
        'ai_response_invalid',
        502,
        { error: 'ai_response_invalid', detail: (e as Error).message },
        user.id,
      )
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

    trackEdgeFunctionInvoked({
      functionName: 'analyze-match',
      distinctId: user.id,
      durationMs: Date.now() - fnStart,
      status: 'ok',
      promptVersion: PROMPT_VERSION,
    }).catch(() => {})
    captureEvent({
      event: EV_MATCH_ANALYSIS_COMPLETED,
      distinctId: user.id,
      properties: {
        model_used: MODEL,
        cache_hit: false,
        score_divergence: payload.divergence ?? false,
        scenario: 'ai',
      },
    }).catch(() => {})
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
    trackEdgeFunctionInvoked({
      functionName: 'analyze-match',
      distinctId: 'edge_function:analyze-match',
      durationMs: Date.now() - fnStart,
      status: 'error',
      errorCode: status === 504 ? 'timeout' : 'internal',
      extra: { error_message: msg.slice(0, 300) },
    }).catch(() => {})
    return jsonResponse({ error: 'internal', detail: msg.slice(0, 300) }, status)
  }
})
