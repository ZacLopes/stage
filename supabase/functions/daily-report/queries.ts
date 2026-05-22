// Queries SQL agregadas pra montar o relatório diário (e semanal aos domingos).
//
// Convenção de janela: tudo é calculado em America/Sao_Paulo (BRT). A função
// computeWindow() devolve os timestamps ISO em UTC pra usar nas comparações.
//
// "Ontem" = ontem 00:00 BRT até hoje 00:00 BRT (no momento da execução).
// "Anteontem" = ontem -24h, mesma duração — usado pra calcular delta D-1.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export interface DateWindow {
  /// ISO UTC do início da janela.
  startISO: string
  /// ISO UTC do fim da janela (exclusivo).
  endISO: string
  /// Rótulo legível pra cabeçalho do email.
  label: string
}

export interface ReportWindow {
  yesterday: DateWindow
  dayBefore: DateWindow
  lastWeek: DateWindow
  previousWeek: DateWindow
  /// `true` se hoje é domingo (UTC), gatilho do modo semanal.
  isSunday: boolean
}

/// Calcula janelas BRT a partir do "agora" (UTC).
/// BRT é UTC-3 (sem DST desde 2019).
export function computeWindow(now: Date = new Date()): ReportWindow {
  const BRT_OFFSET_MS = 3 * 3600 * 1000

  // "Hoje BRT 00:00" = agora UTC com horas/min/seg zeradas no horário BRT.
  const nowBrt = new Date(now.getTime() - BRT_OFFSET_MS)
  const todayBrtMidnight = new Date(
    Date.UTC(nowBrt.getUTCFullYear(), nowBrt.getUTCMonth(), nowBrt.getUTCDate()),
  )
  // Voltar pra UTC: hoje 00:00 BRT == hoje 03:00 UTC.
  const todayStartUtc = new Date(todayBrtMidnight.getTime() + BRT_OFFSET_MS)
  const yesterdayStartUtc = new Date(todayStartUtc.getTime() - 24 * 3600 * 1000)
  const dayBeforeStartUtc = new Date(yesterdayStartUtc.getTime() - 24 * 3600 * 1000)
  const lastWeekStartUtc = new Date(todayStartUtc.getTime() - 7 * 24 * 3600 * 1000)
  const prevWeekStartUtc = new Date(lastWeekStartUtc.getTime() - 7 * 24 * 3600 * 1000)

  const fmtDate = (d: Date) => {
    const brt = new Date(d.getTime() - BRT_OFFSET_MS)
    const dd = String(brt.getUTCDate()).padStart(2, '0')
    const mm = String(brt.getUTCMonth() + 1).padStart(2, '0')
    return `${dd}/${mm}`
  }

  return {
    yesterday: {
      startISO: yesterdayStartUtc.toISOString(),
      endISO: todayStartUtc.toISOString(),
      label: fmtDate(yesterdayStartUtc),
    },
    dayBefore: {
      startISO: dayBeforeStartUtc.toISOString(),
      endISO: yesterdayStartUtc.toISOString(),
      label: fmtDate(dayBeforeStartUtc),
    },
    lastWeek: {
      startISO: lastWeekStartUtc.toISOString(),
      endISO: todayStartUtc.toISOString(),
      label: `${fmtDate(lastWeekStartUtc)} - ${fmtDate(new Date(todayStartUtc.getTime() - 1))}`,
    },
    previousWeek: {
      startISO: prevWeekStartUtc.toISOString(),
      endISO: lastWeekStartUtc.toISOString(),
      label: `${fmtDate(prevWeekStartUtc)} - ${fmtDate(new Date(lastWeekStartUtc.getTime() - 1))}`,
    },
    // getUTCDay: 0 = domingo. Usamos UTC pra evitar ambiguidade de timezone do servidor.
    isSunday: nowBrt.getUTCDay() === 0,
  }
}

/// Conta linhas numa tabela dentro de uma janela.
async function countInWindow(
  sb: SupabaseClient,
  table: string,
  column: string,
  win: DateWindow,
  extraFilter?: (q: any) => any,
): Promise<number> {
  let q = sb
    .from(table)
    .select('*', { count: 'exact', head: true })
    .gte(column, win.startISO)
    .lt(column, win.endISO)
  if (extraFilter) q = extraFilter(q)
  const { count, error } = await q
  if (error) {
    console.error(`[queries] countInWindow ${table}.${column} failed:`, error.message)
    return 0
  }
  return count ?? 0
}

/// Agrupa um campo (rola no client porque PostgREST não tem GROUP BY direto).
/// Carrega no máximo `limit` rows e agrega em memória.
async function groupCount(
  sb: SupabaseClient,
  table: string,
  selectCols: string,
  timeColumn: string,
  win: DateWindow,
  groupBy: (row: any) => string | null,
  rowLimit = 5000,
): Promise<Array<{ key: string; count: number }>> {
  const { data, error } = await sb
    .from(table)
    .select(selectCols)
    .gte(timeColumn, win.startISO)
    .lt(timeColumn, win.endISO)
    .limit(rowLimit)
  if (error) {
    console.error(`[queries] groupCount ${table} failed:`, error.message)
    return []
  }
  const map = new Map<string, number>()
  for (const row of data ?? []) {
    const key = groupBy(row)
    if (!key) continue
    map.set(key, (map.get(key) ?? 0) + 1)
  }
  return Array.from(map.entries())
    .map(([key, count]) => ({ key, count }))
    .sort((a, b) => b.count - a.count)
}

// ============================================================================
// BLOCO 1 — Usuários novos
// ============================================================================

export interface UsersBlock {
  newSignups: number
  newSignupsPrev: number
  byUniversity: Array<{ key: string; count: number }>
  byCourse: Array<{ key: string; count: number }>
  bySemester: Array<{ key: string; count: number }>
  aiConsentRate: number
  phoneRate: number
  onboardingCompletionRate: number
}

export async function fetchUsersBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<UsersBlock> {
  // Cadastros D-1 e D-2 — só conta.
  const [newSignups, newSignupsPrev] = await Promise.all([
    countInWindow(sb, 'user_profiles', 'created_at', win.yesterday),
    countInWindow(sb, 'user_profiles', 'created_at', win.dayBefore),
  ])

  // Carrega os perfis criados ontem pra agrupar (uni / curso / semestre) e
  // calcular taxas (ai_consent, phone). Volume esperado: dezenas-centenas/dia,
  // dá pra fazer in-memory sem paginação.
  const { data: rows, error } = await sb
    .from('user_profiles')
    .select('course, semester, ai_consent, phone, gamification_data, id')
    .gte('created_at', win.yesterday.startISO)
    .lt('created_at', win.yesterday.endISO)
    .limit(5000)

  if (error) {
    console.error('[queries] fetchUsersBlock profiles failed:', error.message)
    return {
      newSignups,
      newSignupsPrev,
      byUniversity: [],
      byCourse: [],
      bySemester: [],
      aiConsentRate: 0,
      phoneRate: 0,
      onboardingCompletionRate: 0,
    }
  }

  const profiles = rows ?? []
  const uniMap = new Map<string, number>()
  const courseMap = new Map<string, number>()
  const semMap = new Map<string, number>()
  let aiConsentCount = 0
  let phoneCount = 0
  const profileIds: string[] = []

  for (const p of profiles) {
    const uni = ((p.gamification_data as Record<string, unknown> | null)?.['university'] ?? null) as
      | string
      | null
    if (uni && uni.trim()) uniMap.set(uni.trim(), (uniMap.get(uni.trim()) ?? 0) + 1)
    if (p.course) courseMap.set(p.course, (courseMap.get(p.course) ?? 0) + 1)
    if (p.semester) semMap.set(p.semester, (semMap.get(p.semester) ?? 0) + 1)
    if (p.ai_consent) aiConsentCount++
    if (p.phone && String(p.phone).trim()) phoneCount++
    if (p.id) profileIds.push(p.id)
  }

  // Onboarding completion: heurística = tem pelo menos 1 row em user_progress
  // com completed=true (ou seja, completou pelo menos uma fase). Volume da
  // tabela user_progress é grande (480 rows globais), mas filtrando por user_id
  // dos perfis de ontem fica enxuto.
  let onboardingCompletionRate = 0
  if (profileIds.length > 0) {
    const { data: progressRows } = await sb
      .from('user_progress')
      .select('user_id')
      .in('user_id', profileIds)
      .eq('completed', true)
    const completedSet = new Set((progressRows ?? []).map((r) => r.user_id))
    onboardingCompletionRate = completedSet.size / profileIds.length
  }

  const topN = <T>(map: Map<string, number>, n: number) =>
    Array.from(map.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, n) as T

  return {
    newSignups,
    newSignupsPrev,
    byUniversity: topN<Array<{ key: string; count: number }>>(uniMap, 10),
    byCourse: topN<Array<{ key: string; count: number }>>(courseMap, 10),
    bySemester: topN<Array<{ key: string; count: number }>>(semMap, 12),
    aiConsentRate: profiles.length > 0 ? aiConsentCount / profiles.length : 0,
    phoneRate: profiles.length > 0 ? phoneCount / profiles.length : 0,
    onboardingCompletionRate,
  }
}

// ============================================================================
// BLOCO 1B — Perfil dos usuários (TOTAL no app, all-time)
// ============================================================================
//
// Diferente do Bloco 1 que é só D-1, esse aqui mostra a foto agregada do
// projeto inteiro: total de cadastrados desde sempre, top faculdades/cursos
// históricos, distribuição global de semestre/idade, taxas globais.
//
// Útil pra responder "qual minha base hoje?", "quais faculdades dominam?",
// "estou pegando mais 2º ou 4º semestre?".

export interface UsersTotalBlock {
  totalUsers: number
  byUniversity: Array<{ key: string; count: number }>
  byCourse: Array<{ key: string; count: number }>
  bySemester: Array<{ key: string; count: number }>
  byAgeBucket: Array<{ key: string; count: number }>
  aiConsentRate: number
  phoneRate: number
  onboardingCompletionRate: number
  /// Quantos usuários têm pelo menos 1 swipe registrado (sinal de "ativaram").
  activatedRate: number
}

export async function fetchUsersTotalBlock(sb: SupabaseClient): Promise<UsersTotalBlock> {
  // Paginação: PostgREST limita a 1000 rows/request por default. Vou puxar
  // em batches de 1000 até esgotar (volume atual ~520 users, sobra muito).
  const PAGE_SIZE = 1000
  type Row = {
    id: string
    course: string | null
    semester: string | null
    ai_consent: boolean | null
    phone: string | null
    age: number | null
    gamification_data: Record<string, unknown> | null
  }
  const all: Row[] = []
  let from = 0
  while (true) {
    const { data, error } = await sb
      .from('user_profiles')
      .select('id, course, semester, ai_consent, phone, age, gamification_data')
      .range(from, from + PAGE_SIZE - 1)
    if (error) {
      console.error('[queries] fetchUsersTotalBlock failed:', error.message)
      break
    }
    const rows = (data ?? []) as Row[]
    all.push(...rows)
    if (rows.length < PAGE_SIZE) break
    from += PAGE_SIZE
    if (from > 50000) break // safety cap — 50k users seria milestone
  }

  const uniMap = new Map<string, number>()
  const courseMap = new Map<string, number>()
  const semMap = new Map<string, number>()
  const ageMap = new Map<string, number>()
  let aiConsentCount = 0
  let phoneCount = 0
  const ids: string[] = []

  const ageBucket = (age: number | null): string | null => {
    if (age == null) return null
    if (age < 18) return '< 18'
    if (age <= 20) return '18-20'
    if (age <= 22) return '21-22'
    if (age <= 24) return '23-24'
    if (age <= 27) return '25-27'
    return '28+'
  }

  for (const p of all) {
    const uni = (p.gamification_data?.['university'] ?? null) as string | null
    if (uni && uni.trim()) uniMap.set(uni.trim(), (uniMap.get(uni.trim()) ?? 0) + 1)
    if (p.course) courseMap.set(p.course, (courseMap.get(p.course) ?? 0) + 1)
    if (p.semester) semMap.set(p.semester, (semMap.get(p.semester) ?? 0) + 1)
    const bucket = ageBucket(p.age)
    if (bucket) ageMap.set(bucket, (ageMap.get(bucket) ?? 0) + 1)
    if (p.ai_consent) aiConsentCount++
    if (p.phone && String(p.phone).trim()) phoneCount++
    if (p.id) ids.push(p.id)
  }

  // Onboarding completion: pelo menos 1 user_progress.completed=true.
  // Activated: pelo menos 1 swipe_action.
  let onboardingCompletedSet = new Set<string>()
  let activatedSet = new Set<string>()
  if (ids.length > 0) {
    const [{ data: progressRows }, { data: swipeRows }] = await Promise.all([
      sb.from('user_progress').select('user_id').eq('completed', true),
      sb.from('swipe_actions').select('user_id').limit(50000),
    ])
    onboardingCompletedSet = new Set((progressRows ?? []).map((r) => r.user_id))
    activatedSet = new Set((swipeRows ?? []).map((r) => r.user_id))
  }

  const topN = (m: Map<string, number>, n: number) =>
    Array.from(m.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, n)

  // Semestres: ordena por número crescente (1º, 2º, 3º...) se for parseable,
  // senão por contagem desc. Fica mais legível pra entender distribuição.
  const semSorted = Array.from(semMap.entries())
    .map(([key, count]) => ({ key, count }))
    .sort((a, b) => {
      const na = parseInt(a.key, 10)
      const nb = parseInt(b.key, 10)
      if (!isNaN(na) && !isNaN(nb)) return na - nb
      return b.count - a.count
    })

  return {
    totalUsers: all.length,
    byUniversity: topN(uniMap, 15),
    byCourse: topN(courseMap, 15),
    bySemester: semSorted,
    byAgeBucket: Array.from(ageMap.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => {
        // Ordena: <18, 18-20, 21-22, 23-24, 25-27, 28+
        const order = ['< 18', '18-20', '21-22', '23-24', '25-27', '28+']
        return order.indexOf(a.key) - order.indexOf(b.key)
      }),
    aiConsentRate: all.length > 0 ? aiConsentCount / all.length : 0,
    phoneRate: all.length > 0 ? phoneCount / all.length : 0,
    onboardingCompletionRate: all.length > 0 ? onboardingCompletedSet.size / all.length : 0,
    activatedRate: all.length > 0 ? activatedSet.size / all.length : 0,
  }
}

// ============================================================================
// BLOCO 2 — Engajamento (D-1)
// ============================================================================

export interface EngagementBlock {
  /// DAU = users distintos com pelo menos 1 swipe_action ontem.
  dau: number
  /// Users que adaptaram pelo menos 1 CV ontem.
  cvAdaptersYesterday: number
  /// Users que aplicaram (applied=true) pelo menos 1 vaga ontem.
  appliersYesterday: number
}

export async function fetchEngagementBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<EngagementBlock> {
  const { data: swipes } = await sb
    .from('swipe_actions')
    .select('user_id, applied, applied_at, created_at')
    .gte('created_at', win.yesterday.startISO)
    .lt('created_at', win.yesterday.endISO)
    .limit(50000)

  const dauSet = new Set<string>()
  const applierSet = new Set<string>()
  for (const s of swipes ?? []) {
    if (s.user_id) dauSet.add(s.user_id)
    if (s.applied && s.user_id) applierSet.add(s.user_id)
  }

  const { data: adapted } = await sb
    .from('adapted_resumes')
    .select('user_id')
    .gte('computed_at', win.yesterday.startISO)
    .lt('computed_at', win.yesterday.endISO)
    .limit(5000)
  const adapterSet = new Set((adapted ?? []).map((r) => r.user_id))

  return {
    dau: dauSet.size,
    cvAdaptersYesterday: adapterSet.size,
    appliersYesterday: applierSet.size,
  }
}

// ============================================================================
// BLOCO 3 — Vagas inseridas (D-1)
// ============================================================================

export interface JobsInsertedBlock {
  total: number
  totalPrev: number
  byArea: Array<{ key: string; count: number }>
  bySource: Array<{ key: string; count: number }>
  byCompany: Array<{ key: string; count: number }>
  byWorkModel: Array<{ key: string; count: number }>
  byJobType: Array<{ key: string; count: number }>
  byCity: Array<{ key: string; count: number }>
}

export async function fetchJobsInsertedBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<JobsInsertedBlock> {
  const [total, totalPrev] = await Promise.all([
    countInWindow(sb, 'jobs', 'created_at', win.yesterday),
    countInWindow(sb, 'jobs', 'created_at', win.dayBefore),
  ])

  const { data: jobs } = await sb
    .from('jobs')
    .select('area, source, work_model, job_type, location_city, company_id, companies(name)')
    .gte('created_at', win.yesterday.startISO)
    .lt('created_at', win.yesterday.endISO)
    .limit(10000)

  const norm = (v: unknown) => (v == null || v === '' ? 'sem_info' : String(v))
  const groupBy = <T extends { [k: string]: any }>(
    rows: T[],
    accessor: (r: T) => string,
  ): Array<{ key: string; count: number }> => {
    const m = new Map<string, number>()
    for (const r of rows) {
      const k = accessor(r)
      m.set(k, (m.get(k) ?? 0) + 1)
    }
    return Array.from(m.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => b.count - a.count)
  }

  const rows = jobs ?? []
  return {
    total,
    totalPrev,
    byArea: groupBy(rows, (r) => norm(r.area)).slice(0, 15),
    bySource: groupBy(rows, (r) => norm(r.source)),
    byCompany: groupBy(rows, (r) => {
      // companies(name) vem como objeto ou array dependendo da relação. Trata os dois.
      const c = (r as any).companies
      if (Array.isArray(c)) return norm(c[0]?.name)
      return norm(c?.name)
    }).slice(0, 10),
    byWorkModel: groupBy(rows, (r) => norm(r.work_model)),
    byJobType: groupBy(rows, (r) => norm(r.job_type)),
    byCity: groupBy(rows, (r) => norm(r.location_city)).slice(0, 10),
  }
}

// ============================================================================
// BLOCO 4 — Estoque atual de vagas
// ============================================================================

export interface JobsStockBlock {
  activeTotal: number
  byArea: Array<{ key: string; count: number }>
  avgAgeDays: number
  withExternalUrlRate: number
}

export async function fetchJobsStockBlock(sb: SupabaseClient): Promise<JobsStockBlock> {
  const { count: activeTotal } = await sb
    .from('jobs')
    .select('*', { count: 'exact', head: true })
    .eq('is_active', true)

  const { data: rows } = await sb
    .from('jobs')
    .select('area, published_at, external_url')
    .eq('is_active', true)
    .limit(20000)

  const m = new Map<string, number>()
  let ageSum = 0
  let ageCount = 0
  let withUrl = 0
  const now = Date.now()
  for (const r of rows ?? []) {
    const k = r.area && r.area !== '' ? r.area : 'sem_info'
    m.set(k, (m.get(k) ?? 0) + 1)
    if (r.published_at) {
      ageSum += (now - new Date(r.published_at).getTime()) / (24 * 3600 * 1000)
      ageCount++
    }
    if (r.external_url && String(r.external_url).trim()) withUrl++
  }

  return {
    activeTotal: activeTotal ?? 0,
    byArea: Array.from(m.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 10),
    avgAgeDays: ageCount > 0 ? ageSum / ageCount : 0,
    withExternalUrlRate: (rows ?? []).length > 0 ? withUrl / (rows ?? []).length : 0,
  }
}

// ============================================================================
// BLOCO 5 — Match & engajamento com vagas (D-1)
// ============================================================================

export interface MatchBlock {
  totalLikes: number
  totalApplies: number
  swipeToApplyRate: number
  likesByArea: Array<{ key: string; count: number }>
  topLikedJobs: Array<{ title: string; company: string; count: number; url: string | null }>
  topLikedCompanies: Array<{ key: string; count: number }>
  avgMatchScore: number
}

export async function fetchMatchBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<MatchBlock> {
  const { data: swipes } = await sb
    .from('swipe_actions')
    .select('action, applied, job_id, jobs(title, area, external_url, companies(name))')
    .gte('created_at', win.yesterday.startISO)
    .lt('created_at', win.yesterday.endISO)
    .eq('action', 'liked')
    .limit(50000)

  const rows = swipes ?? []
  const totalLikes = rows.length
  const totalApplies = rows.filter((r) => r.applied).length

  const areaMap = new Map<string, number>()
  const companyMap = new Map<string, number>()
  const jobMap = new Map<
    string,
    { title: string; company: string; count: number; url: string | null }
  >()

  for (const r of rows) {
    const job = (r as any).jobs
    const j = Array.isArray(job) ? job[0] : job
    const area = j?.area && j.area !== '' ? j.area : 'sem_info'
    areaMap.set(area, (areaMap.get(area) ?? 0) + 1)

    const c = j?.companies
    const company = (Array.isArray(c) ? c[0]?.name : c?.name) ?? 'sem_info'
    companyMap.set(company, (companyMap.get(company) ?? 0) + 1)

    const jobKey = r.job_id ?? 'unknown'
    const existing = jobMap.get(jobKey)
    if (existing) existing.count++
    else
      jobMap.set(jobKey, {
        title: j?.title ?? '(sem título)',
        company,
        count: 1,
        url: j?.external_url ?? null,
      })
  }

  // Match score médio dos pares criados ontem.
  const { data: matches } = await sb
    .from('match_analyses')
    .select('score')
    .gte('computed_at', win.yesterday.startISO)
    .lt('computed_at', win.yesterday.endISO)
    .limit(50000)

  const scores = (matches ?? []).map((m) => m.score).filter((s): s is number => typeof s === 'number')
  const avgMatchScore = scores.length > 0 ? scores.reduce((a, b) => a + b, 0) / scores.length : 0

  return {
    totalLikes,
    totalApplies,
    swipeToApplyRate: totalLikes > 0 ? totalApplies / totalLikes : 0,
    likesByArea: Array.from(areaMap.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 10),
    topLikedJobs: Array.from(jobMap.values())
      .sort((a, b) => b.count - a.count)
      .slice(0, 5),
    topLikedCompanies: Array.from(companyMap.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 5),
    avgMatchScore,
  }
}

// ============================================================================
// BLOCO 6 — CV adaptado (D-1)
// ============================================================================

export interface CvAdaptedBlock {
  total: number
  byArea: Array<{ key: string; count: number }>
}

export async function fetchCvAdaptedBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<CvAdaptedBlock> {
  const { data } = await sb
    .from('adapted_resumes')
    .select('jobs(area)')
    .gte('computed_at', win.yesterday.startISO)
    .lt('computed_at', win.yesterday.endISO)
    .limit(5000)

  const m = new Map<string, number>()
  for (const r of data ?? []) {
    const j = (r as any).jobs
    const area = (Array.isArray(j) ? j[0]?.area : j?.area) ?? 'sem_info'
    m.set(area, (m.get(area) ?? 0) + 1)
  }

  return {
    total: (data ?? []).length,
    byArea: Array.from(m.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 10),
  }
}

// ============================================================================
// BLOCO 7 — Gap oferta vs demanda
// ============================================================================

export interface GapBlock {
  /// Áreas com muitos likes mas poucas vagas ativas (ratio alto = pouca oferta).
  underservedAreas: Array<{ area: string; likes: number; activeJobs: number; ratio: number }>
}

export function computeGapBlock(
  likesByArea: Array<{ key: string; count: number }>,
  stockByArea: Array<{ key: string; count: number }>,
): GapBlock {
  const stockMap = new Map(stockByArea.map((s) => [s.key, s.count]))
  const underservedAreas = likesByArea
    .filter((l) => l.count >= 3) // ruído fora — precisa volume mínimo de demanda
    .map((l) => {
      const activeJobs = stockMap.get(l.key) ?? 0
      const ratio = activeJobs > 0 ? l.count / activeJobs : l.count // se 0 vagas, ratio = likes
      return { area: l.key, likes: l.count, activeJobs, ratio }
    })
    .sort((a, b) => b.ratio - a.ratio)
    .slice(0, 5)
  return { underservedAreas }
}

// ============================================================================
// BLOCO 8 — Saúde do sistema (D-1)
// ============================================================================

export interface HealthBlock {
  aiGenerations: number
  /// Soma de tokens consumidos ontem (proxy de gasto).
  totalTokensUsed: number
}

export async function fetchHealthBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<HealthBlock> {
  const { data } = await sb
    .from('ai_generation_logs')
    .select('tokens_used')
    .gte('created_at', win.yesterday.startISO)
    .lt('created_at', win.yesterday.endISO)
    .limit(50000)

  const rows = data ?? []
  return {
    aiGenerations: rows.length,
    totalTokensUsed: rows.reduce((acc, r) => acc + (r.tokens_used ?? 0), 0),
  }
}

// ============================================================================
// BLOCO 2.5 — Retenção (D-1)
// ============================================================================
//
// Três métricas de retenção lidas em conjunto:
//
// 1. D1 retention dos novos: dos usuários cadastrados em D-2, quantos voltaram
//    em D-1 (1+ swipe). É o KPI clássico de early-stage.
// 2. % DAU recorrente: dos ativos de ontem, quantos NÃO se cadastraram ontem
//    (já tinham conta). Mostra se a base ativa é nova ou fiel.
// 3. Stickiness (DAU/MAU): % do MAU (últimos 30d) que esteve ativo ontem.

export interface RetentionBlock {
  /// D1 retention dos cadastros de D-2.
  d2Signups: number
  d2SignupsReturnedD1: number
  d1RetentionRate: number

  /// DAU recorrente vs estreante.
  dau: number
  dauNewToday: number
  dauReturning: number
  returningDauRate: number

  /// Stickiness DAU/MAU.
  mau: number
  stickiness: number
}

export async function fetchRetentionBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<RetentionBlock> {
  // Janela de 30d terminando no fim de ontem.
  const mauStartIso = new Date(
    new Date(win.yesterday.endISO).getTime() - 30 * 24 * 3600 * 1000,
  ).toISOString()

  const [d2SignupsRes, d1SignupsRes, yesterdaySwipesRes, monthSwipesRes] = await Promise.all([
    sb
      .from('user_profiles')
      .select('id')
      .gte('created_at', win.dayBefore.startISO)
      .lt('created_at', win.dayBefore.endISO),
    sb
      .from('user_profiles')
      .select('id')
      .gte('created_at', win.yesterday.startISO)
      .lt('created_at', win.yesterday.endISO),
    sb
      .from('swipe_actions')
      .select('user_id')
      .gte('created_at', win.yesterday.startISO)
      .lt('created_at', win.yesterday.endISO)
      .limit(50000),
    sb
      .from('swipe_actions')
      .select('user_id')
      .gte('created_at', mauStartIso)
      .lt('created_at', win.yesterday.endISO)
      .limit(200000),
  ])

  const d2Ids = new Set((d2SignupsRes.data ?? []).map((r) => r.id).filter(Boolean) as string[])
  const d1NewIds = new Set((d1SignupsRes.data ?? []).map((r) => r.id).filter(Boolean) as string[])

  const dauSet = new Set<string>()
  for (const s of yesterdaySwipesRes.data ?? []) {
    if (s.user_id) dauSet.add(s.user_id as string)
  }

  const mauSet = new Set<string>()
  for (const s of monthSwipesRes.data ?? []) {
    if (s.user_id) mauSet.add(s.user_id as string)
  }

  let d2Returned = 0
  for (const uid of d2Ids) {
    if (dauSet.has(uid)) d2Returned++
  }

  let dauNew = 0
  for (const uid of dauSet) {
    if (d1NewIds.has(uid)) dauNew++
  }
  const dauReturning = dauSet.size - dauNew

  return {
    d2Signups: d2Ids.size,
    d2SignupsReturnedD1: d2Returned,
    d1RetentionRate: d2Ids.size > 0 ? d2Returned / d2Ids.size : 0,
    dau: dauSet.size,
    dauNewToday: dauNew,
    dauReturning,
    returningDauRate: dauSet.size > 0 ? dauReturning / dauSet.size : 0,
    mau: mauSet.size,
    stickiness: mauSet.size > 0 ? dauSet.size / mauSet.size : 0,
  }
}

// ============================================================================
// BLOCO SEMANAL (domingo) — totais last7
// ============================================================================

export interface WeeklyBlock {
  newSignupsLastWeek: number
  newSignupsPrevWeek: number
  jobsLastWeek: number
  jobsPrevWeek: number
  likesLastWeek: number
  likesPrevWeek: number
  appliesLastWeek: number
  appliesPrevWeek: number
}

export async function fetchWeeklyBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<WeeklyBlock> {
  const [signupsLast, signupsPrev, jobsLast, jobsPrev] = await Promise.all([
    countInWindow(sb, 'user_profiles', 'created_at', win.lastWeek),
    countInWindow(sb, 'user_profiles', 'created_at', win.previousWeek),
    countInWindow(sb, 'jobs', 'created_at', win.lastWeek),
    countInWindow(sb, 'jobs', 'created_at', win.previousWeek),
  ])

  // Likes / applies: precisa filtrar action e applied, então é mais simples
  // contar manual via head:false e contagem em memória de só job_id (campo curto).
  const countLikes = async (w: DateWindow) => {
    const { count } = await sb
      .from('swipe_actions')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', w.startISO)
      .lt('created_at', w.endISO)
      .eq('action', 'liked')
    return count ?? 0
  }
  const countApplies = async (w: DateWindow) => {
    const { count } = await sb
      .from('swipe_actions')
      .select('*', { count: 'exact', head: true })
      .gte('applied_at', w.startISO)
      .lt('applied_at', w.endISO)
      .eq('applied', true)
    return count ?? 0
  }

  const [likesLast, likesPrev, appliesLast, appliesPrev] = await Promise.all([
    countLikes(win.lastWeek),
    countLikes(win.previousWeek),
    countApplies(win.lastWeek),
    countApplies(win.previousWeek),
  ])

  return {
    newSignupsLastWeek: signupsLast,
    newSignupsPrevWeek: signupsPrev,
    jobsLastWeek: jobsLast,
    jobsPrevWeek: jobsPrev,
    likesLastWeek: likesLast,
    likesPrevWeek: likesPrev,
    appliesLastWeek: appliesLast,
    appliesPrevWeek: appliesPrev,
  }
}
