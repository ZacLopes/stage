// Queries SQL agregadas pra montar o relatório diário (e semanal aos domingos).
//
// Convenção de janela: tudo é calculado em America/Sao_Paulo (BRT). A função
// computeWindow() devolve os timestamps ISO em UTC pra usar nas comparações.
//
// "Ontem" = ontem 00:00 BRT até hoje 00:00 BRT (no momento da execução).
// "Anteontem" = ontem -24h, mesma duração — usado pra calcular delta D-1.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export interface DateWindow {
  /// ISO UTC do início da janela.
  startISO: string;
  /// ISO UTC do fim da janela (exclusivo).
  endISO: string;
  /// Rótulo legível pra cabeçalho do email.
  label: string;
}

export interface ReportWindow {
  yesterday: DateWindow;
  dayBefore: DateWindow;
  lastWeek: DateWindow;
  previousWeek: DateWindow;
  /// `true` se hoje é domingo (UTC), gatilho do modo semanal.
  isSunday: boolean;
}

/// Calcula janelas BRT a partir do "agora" (UTC).
/// BRT é UTC-3 (sem DST desde 2019).
export function computeWindow(now: Date = new Date()): ReportWindow {
  const BRT_OFFSET_MS = 3 * 3600 * 1000;

  // "Hoje BRT 00:00" = agora UTC com horas/min/seg zeradas no horário BRT.
  const nowBrt = new Date(now.getTime() - BRT_OFFSET_MS);
  const todayBrtMidnight = new Date(
    Date.UTC(nowBrt.getUTCFullYear(), nowBrt.getUTCMonth(), nowBrt.getUTCDate()),
  );
  // Voltar pra UTC: hoje 00:00 BRT == hoje 03:00 UTC.
  const todayStartUtc = new Date(todayBrtMidnight.getTime() + BRT_OFFSET_MS);
  const yesterdayStartUtc = new Date(todayStartUtc.getTime() - 24 * 3600 * 1000);
  const dayBeforeStartUtc = new Date(yesterdayStartUtc.getTime() - 24 * 3600 * 1000);
  const lastWeekStartUtc = new Date(todayStartUtc.getTime() - 7 * 24 * 3600 * 1000);
  const prevWeekStartUtc = new Date(lastWeekStartUtc.getTime() - 7 * 24 * 3600 * 1000);

  const fmtDate = (d: Date) => {
    const brt = new Date(d.getTime() - BRT_OFFSET_MS);
    const dd = String(brt.getUTCDate()).padStart(2, '0');
    const mm = String(brt.getUTCMonth() + 1).padStart(2, '0');
    return `${dd}/${mm}`;
  };

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
  };
}

/// Conta linhas numa tabela dentro de uma janela.
async function countInWindow(
  sb: SupabaseClient,
  table: string,
  column: string,
  win: DateWindow,
): Promise<number> {
  const q = sb
    .from(table)
    .select('*', { count: 'exact', head: true })
    .gte(column, win.startISO)
    .lt(column, win.endISO);
  const { count, error } = await q;
  if (error) {
    console.error(`[queries] countInWindow ${table}.${column} failed:`, error.message);
    return 0;
  }
  return count ?? 0;
}

type DbObject = Record<string, unknown>;

function cleanText(value: unknown): string | null {
  const text = typeof value === 'string' ? value.trim() : '';
  return text.length > 0 ? text : null;
}

function norm(value: unknown): string {
  return cleanText(value) ?? 'sem_info';
}

function relationObject(value: unknown): DbObject | null {
  if (Array.isArray(value)) {
    const first = value[0];
    return first && typeof first === 'object' ? first as DbObject : null;
  }
  return value && typeof value === 'object' ? value as DbObject : null;
}

function relationArray(value: unknown): DbObject[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is DbObject => Boolean(item) && typeof item === 'object');
}

function textField(row: DbObject | null, key: string): string | null {
  return row ? cleanText(row[key]) : null;
}

function numericField(row: DbObject, key: string): number {
  const value = row[key];
  return typeof value === 'number' ? value : 0;
}

function chunked<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) chunks.push(items.slice(i, i + size));
  return chunks;
}

function topN(map: Map<string, number>, n: number): Array<{ key: string; count: number }> {
  return Array.from(map.entries())
    .map(([key, count]) => ({ key, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, n);
}

function increment(map: Map<string, number>, key: string | null): void {
  if (!key) return;
  map.set(key, (map.get(key) ?? 0) + 1);
}

interface EducationSummary {
  institution: string | null;
  course: string | null;
  semester: string | null;
}

function firstEducationMajor(row: DbObject): string | null {
  const majors = relationArray(row.profile_education_majors).sort(
    (a, b) => numericField(a, 'order_index') - numericField(b, 'order_index'),
  );
  return majors.map((m) => cleanText(m.name)).find((name) => Boolean(name)) ?? null;
}

function isSchoolEducation(row: DbObject): boolean {
  const level = cleanText(row.education_level)?.toLowerCase();
  const degree = cleanText(row.degree)?.toLowerCase();
  return level === 'school' ||
    degree === 'ensino medio' ||
    degree === 'ensino médio' ||
    degree === 'high school';
}

function educationPriority(row: DbObject): number {
  const level = cleanText(row.education_level)?.toLowerCase();
  if (level === 'college') return 0;
  if (isSchoolEducation(row)) return 3;
  if (firstEducationMajor(row)) return 1;
  return 2;
}

function semesterFromEducation(row: DbObject): string | null {
  const status = cleanText(row.education_status);
  const rawSemester = row.current_semester;
  const semester = typeof rawSemester === 'number'
    ? rawSemester
    : Number.parseInt(String(rawSemester ?? ''), 10);
  const hasSemester = Number.isFinite(semester) && semester > 0;

  switch (status) {
    case 'studying':
      return hasSemester ? `${semester} semestre` : null;
    case 'paused':
      return hasSemester ? `${semester} semestre (trancado)` : 'Trancado';
    case 'graduated':
      return 'Formado';
    case 'not_started':
      return 'Ainda não comecei';
    case 'not_in_college':
      return 'Não curso faculdade';
    case 'not_studying':
      return 'Não estou estudando';
    default:
      return hasSemester ? `${semester} semestre` : null;
  }
}

async function fetchEducationSummaries(
  sb: SupabaseClient,
  userIds: string[],
): Promise<Map<string, EducationSummary>> {
  const summaries = new Map<string, EducationSummary>();
  const uniqueIds = Array.from(new Set(userIds.filter(Boolean)));
  if (uniqueIds.length === 0) return summaries;

  for (const ids of chunked(uniqueIds, 300)) {
    const result = await sb
      .from('profile_education')
      .select(
        'id, user_id, institution, degree, order_index, education_level, education_status, current_semester, profile_education_majors(name, order_index)',
      )
      .in('user_id', ids);
    let data = result.data as DbObject[] | null;
    let error = result.error;

    if (error) {
      const fallback = await sb
        .from('profile_education')
        .select(
          'id, user_id, institution, degree, order_index, profile_education_majors(name, order_index)',
        )
        .in('user_id', ids);
      data = fallback.data as DbObject[] | null;
      error = fallback.error;
      if (error) {
        console.error('[queries] fetchEducationSummaries failed:', error.message);
        continue;
      }
    }

    const rowsByUser = new Map<string, DbObject[]>();
    for (const row of data ?? []) {
      const userId = cleanText(row.user_id);
      if (!userId) continue;
      const rows = rowsByUser.get(userId) ?? [];
      rows.push(row);
      rowsByUser.set(userId, rows);
    }

    for (const [userId, userRows] of rowsByUser.entries()) {
      if (summaries.has(userId)) continue;
      const rows = userRows.sort(
        (a, b) =>
          educationPriority(a) - educationPriority(b) ||
          numericField(a, 'order_index') - numericField(b, 'order_index'),
      );
      const row = rows.find((candidate) => educationPriority(candidate) < 3);
      if (!row) continue;

      const major = firstEducationMajor(row);
      const institution = cleanText(row.institution);
      const course = major ?? cleanText(row.degree);
      const semester = semesterFromEducation(row);

      if (institution || course || semester) {
        summaries.set(userId, { institution, course, semester });
      }
    }
  }

  return summaries;
}

async function fetchActivePhaseIds(sb: SupabaseClient): Promise<string[]> {
  const { data, error } = await sb.from('phases').select('id').order('order_index');

  if (error) {
    console.error('[queries] fetchActivePhaseIds failed:', error.message);
    return [];
  }

  return ((data ?? []) as DbObject[]).map((row) => cleanText(row.id)).filter(Boolean) as string[];
}

async function fetchCompletedProgressRows(
  sb: SupabaseClient,
  userIds: string[],
): Promise<DbObject[]> {
  const rows: DbObject[] = [];
  const uniqueIds = Array.from(new Set(userIds.filter(Boolean)));
  if (uniqueIds.length === 0) return rows;

  for (const ids of chunked(uniqueIds, 300)) {
    let from = 0;
    const pageSize = 1000;
    while (true) {
      const { data, error } = await sb
        .from('user_progress')
        .select('user_id, phase_id')
        .in('user_id', ids)
        .eq('completed', true)
        .range(from, from + pageSize - 1);

      if (error) {
        console.error('[queries] fetchCompletedProgressRows failed:', error.message);
        break;
      }

      const page = (data ?? []) as DbObject[];
      rows.push(...page);
      if (page.length < pageSize) break;
      from += pageSize;
      if (from > 200000) break;
    }
  }

  return rows;
}

async function fetchDistinctSwipeUserIds(sb: SupabaseClient): Promise<Set<string>> {
  const ids = new Set<string>();
  let from = 0;
  const pageSize = 1000;
  while (true) {
    const { data, error } = await sb
      .from('swipe_actions')
      .select('user_id')
      .range(from, from + pageSize - 1);

    if (error) {
      console.error('[queries] fetchDistinctSwipeUserIds failed:', error.message);
      break;
    }

    const page = (data ?? []) as DbObject[];
    for (const row of page) {
      const userId = cleanText(row.user_id);
      if (userId) ids.add(userId);
    }
    if (page.length < pageSize) break;
    from += pageSize;
    if (from > 200000) break;
  }
  return ids;
}

async function fetchCampaignUserIds(sb: SupabaseClient, userIds: string[]): Promise<Set<string>> {
  const campaignUserIds = new Set<string>();
  const uniqueIds = Array.from(new Set(userIds.filter(Boolean)));
  if (uniqueIds.length === 0) return campaignUserIds;

  for (const ids of chunked(uniqueIds, 300)) {
    const { data, error } = await sb
      .from('campaigns')
      .select('user_id')
      .in('user_id', ids);

    if (error) {
      console.error('[queries] fetchCampaignUserIds failed:', error.message);
      continue;
    }

    for (const row of (data ?? []) as DbObject[]) {
      const userId = cleanText(row.user_id);
      if (userId) campaignUserIds.add(userId);
    }
  }

  return campaignUserIds;
}

function calculateTrailCompletionRate(
  userIds: string[],
  progressRows: DbObject[],
  phaseIds: string[],
): number {
  const uniqueIds = Array.from(new Set(userIds.filter(Boolean)));
  if (uniqueIds.length === 0 || phaseIds.length === 0) return 0;

  const phasesByUser = new Map<string, Set<string>>();
  for (const row of progressRows) {
    const userId = cleanText(row.user_id);
    const phaseId = cleanText(row.phase_id);
    if (!userId || !phaseId) continue;
    const phases = phasesByUser.get(userId) ?? new Set<string>();
    phases.add(phaseId);
    phasesByUser.set(userId, phases);
  }

  let completedUsers = 0;
  for (const userId of uniqueIds) {
    const phases = phasesByUser.get(userId);
    if (phases && phaseIds.every((phaseId) => phases.has(phaseId))) completedUsers++;
  }

  return completedUsers / uniqueIds.length;
}

function groupRows<T>(
  rows: T[],
  accessor: (row: T) => string,
): Array<{ key: string; count: number }> {
  const counts = new Map<string, number>();
  for (const row of rows) increment(counts, accessor(row));
  return Array.from(counts.entries())
    .map(([key, count]) => ({ key, count }))
    .sort((a, b) => b.count - a.count);
}

// ============================================================================
// BLOCO 1 — Usuários novos
// ============================================================================

export interface UsersBlock {
  newSignups: number;
  newSignupsPrev: number;
  byUniversity: Array<{ key: string; count: number }>;
  byCourse: Array<{ key: string; count: number }>;
  bySemester: Array<{ key: string; count: number }>;
  aiConsentRate: number;
  phoneRate: number;
  onboardingCompletionRate: number;
  trailCompletionRate: number;
}

export async function fetchUsersBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<UsersBlock> {
  // Cadastros D-1 e D-2 — só conta.
  const [newSignups, newSignupsPrev] = await Promise.all([
    countInWindow(sb, 'user_profiles', 'created_at', win.yesterday),
    countInWindow(sb, 'user_profiles', 'created_at', win.dayBefore),
  ]);

  // Carrega os perfis criados ontem pra agrupar (uni / curso / semestre) e
  // calcular taxas (ai_consent, phone). Volume esperado: dezenas-centenas/dia,
  // dá pra fazer in-memory sem paginação.
  const { data: rows, error } = await sb
    .from('user_profiles')
    .select('course, semester, ai_consent, phone, gamification_data, id')
    .gte('created_at', win.yesterday.startISO)
    .lt('created_at', win.yesterday.endISO)
    .limit(5000);

  if (error) {
    console.error('[queries] fetchUsersBlock profiles failed:', error.message);
    return {
      newSignups,
      newSignupsPrev,
      byUniversity: [],
      byCourse: [],
      bySemester: [],
      aiConsentRate: 0,
      phoneRate: 0,
      onboardingCompletionRate: 0,
      trailCompletionRate: 0,
    };
  }

  const profiles = (rows ?? []) as DbObject[];
  const uniMap = new Map<string, number>();
  const courseMap = new Map<string, number>();
  const semMap = new Map<string, number>();
  let aiConsentCount = 0;
  let phoneCount = 0;
  const profileIds: string[] = [];

  for (const p of profiles) {
    if (p.ai_consent === true) aiConsentCount++;
    if (cleanText(p.phone)) phoneCount++;
    const id = cleanText(p.id);
    if (id) profileIds.push(id);
  }

  let educationByUser = new Map<string, EducationSummary>();
  let phaseIds: string[] = [];
  let progressRows: DbObject[] = [];
  let campaignUserIds = new Set<string>();
  if (profileIds.length > 0) {
    [educationByUser, phaseIds, progressRows, campaignUserIds] = await Promise.all([
      fetchEducationSummaries(sb, profileIds),
      fetchActivePhaseIds(sb),
      fetchCompletedProgressRows(sb, profileIds),
      fetchCampaignUserIds(sb, profileIds),
    ]);
  }

  for (const p of profiles) {
    const id = cleanText(p.id);
    const education = id ? educationByUser.get(id) : undefined;
    const gamificationData = relationObject(p.gamification_data);
    const university = education?.institution ?? textField(gamificationData, 'university');
    const course = education?.course ?? cleanText(p.course);
    const semester = education?.semester ?? cleanText(p.semester);

    increment(uniMap, university);
    increment(courseMap, course);
    increment(semMap, semester);
  }

  const onboardingCompletionRate = profileIds.length > 0
    ? campaignUserIds.size / profileIds.length
    : 0;
  const trailCompletionRate = calculateTrailCompletionRate(
    profileIds,
    progressRows,
    phaseIds,
  );

  return {
    newSignups,
    newSignupsPrev,
    byUniversity: topN(uniMap, 10),
    byCourse: topN(courseMap, 10),
    bySemester: topN(semMap, 12),
    aiConsentRate: profiles.length > 0 ? aiConsentCount / profiles.length : 0,
    phoneRate: profiles.length > 0 ? phoneCount / profiles.length : 0,
    onboardingCompletionRate,
    trailCompletionRate,
  };
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
  totalUsers: number;
  byUniversity: Array<{ key: string; count: number }>;
  byCourse: Array<{ key: string; count: number }>;
  bySemester: Array<{ key: string; count: number }>;
  byAgeBucket: Array<{ key: string; count: number }>;
  aiConsentRate: number;
  phoneRate: number;
  onboardingCompletionRate: number;
  trailCompletionRate: number;
  /// Quantos usuários têm pelo menos 1 swipe registrado (sinal de "ativaram").
  activatedRate: number;
}

export async function fetchUsersTotalBlock(sb: SupabaseClient): Promise<UsersTotalBlock> {
  // Paginação: PostgREST limita a 1000 rows/request por default. Vou puxar
  // em batches de 1000 até esgotar (volume atual ~520 users, sobra muito).
  const PAGE_SIZE = 1000;
  type Row = {
    id: string;
    course: string | null;
    semester: string | null;
    ai_consent: boolean | null;
    phone: string | null;
    age: number | null;
    gamification_data: Record<string, unknown> | null;
  };
  const all: Row[] = [];
  let from = 0;
  while (true) {
    const { data, error } = await sb
      .from('user_profiles')
      .select('id, course, semester, ai_consent, phone, age, gamification_data')
      .range(from, from + PAGE_SIZE - 1);
    if (error) {
      console.error('[queries] fetchUsersTotalBlock failed:', error.message);
      break;
    }
    const rows = (data ?? []) as Row[];
    all.push(...rows);
    if (rows.length < PAGE_SIZE) break;
    from += PAGE_SIZE;
    if (from > 50000) break; // safety cap — 50k users seria milestone
  }

  const uniMap = new Map<string, number>();
  const courseMap = new Map<string, number>();
  const semMap = new Map<string, number>();
  const ageMap = new Map<string, number>();
  let aiConsentCount = 0;
  let phoneCount = 0;
  const ids: string[] = [];

  const ageBucket = (age: number | null): string | null => {
    if (age == null) return null;
    if (age < 18) return '< 18';
    if (age <= 20) return '18-20';
    if (age <= 22) return '21-22';
    if (age <= 24) return '23-24';
    if (age <= 27) return '25-27';
    return '28+';
  };

  for (const p of all) {
    const bucket = ageBucket(p.age);
    if (bucket) ageMap.set(bucket, (ageMap.get(bucket) ?? 0) + 1);
    if (p.ai_consent) aiConsentCount++;
    if (p.phone && String(p.phone).trim()) phoneCount++;
    if (p.id) ids.push(p.id);
  }

  let educationByUser = new Map<string, EducationSummary>();
  let phaseIds: string[] = [];
  let progressRows: DbObject[] = [];
  let activatedSet = new Set<string>();
  let campaignUserIds = new Set<string>();
  if (ids.length > 0) {
    [educationByUser, phaseIds, progressRows, activatedSet, campaignUserIds] = await Promise.all([
      fetchEducationSummaries(sb, ids),
      fetchActivePhaseIds(sb),
      fetchCompletedProgressRows(sb, ids),
      fetchDistinctSwipeUserIds(sb),
      fetchCampaignUserIds(sb, ids),
    ]);
  }

  for (const p of all) {
    const education = educationByUser.get(p.id);
    const university = education?.institution ?? cleanText(p.gamification_data?.['university']);
    const course = education?.course ?? cleanText(p.course);
    const semester = education?.semester ?? cleanText(p.semester);

    increment(uniMap, university);
    increment(courseMap, course);
    increment(semMap, semester);
  }

  const onboardingRate = all.length > 0 ? campaignUserIds.size / all.length : 0;
  const trailRate = calculateTrailCompletionRate(ids, progressRows, phaseIds);

  // Semestres: ordena por número crescente (1º, 2º, 3º...) se for parseable,
  // senão por contagem desc. Fica mais legível pra entender distribuição.
  const semSorted = Array.from(semMap.entries())
    .map(([key, count]) => ({ key, count }))
    .sort((a, b) => {
      const na = parseInt(a.key, 10);
      const nb = parseInt(b.key, 10);
      if (!isNaN(na) && !isNaN(nb)) return na - nb;
      return b.count - a.count;
    });

  return {
    totalUsers: all.length,
    byUniversity: topN(uniMap, 15),
    byCourse: topN(courseMap, 15),
    bySemester: semSorted,
    byAgeBucket: Array.from(ageMap.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => {
        // Ordena: <18, 18-20, 21-22, 23-24, 25-27, 28+
        const order = ['< 18', '18-20', '21-22', '23-24', '25-27', '28+'];
        return order.indexOf(a.key) - order.indexOf(b.key);
      }),
    aiConsentRate: all.length > 0 ? aiConsentCount / all.length : 0,
    phoneRate: all.length > 0 ? phoneCount / all.length : 0,
    onboardingCompletionRate: onboardingRate,
    trailCompletionRate: trailRate,
    activatedRate: all.length > 0 ? activatedSet.size / all.length : 0,
  };
}

// ============================================================================
// BLOCO 2 — Engajamento (D-1)
// ============================================================================

/// "Conta como aplicada" — espelha applications.dart::countsAsApplied: qualquer
/// status vivo do pipeline EXCETO withdrawn/expired. A fonte de verdade de
/// "apliquei" migrou de swipe_actions.applied (DEPRECATED, só builds ≤2.2.0
/// escrevem) para a tabela applications; admin-overview e daily-report contam
/// esta tabela agora. (Fase 7 Onda 1.)
export function countsAsApplied(status: string | null | undefined): boolean {
  return status !== 'withdrawn' && status !== 'expired';
}

export interface EngagementBlock {
  /// DAU = users distintos com pelo menos 1 swipe_action ontem.
  dau: number;
  /// Users que adaptaram pelo menos 1 CV ontem.
  cvAdaptersYesterday: number;
  /// Users com >=1 candidatura viva (applications, countsAsApplied) criada ontem.
  appliersYesterday: number;
}

export async function fetchEngagementBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<EngagementBlock> {
  const [{ data: swipes }, { data: applies }] = await Promise.all([
    sb
      .from('swipe_actions')
      .select('user_id')
      .gte('created_at', win.yesterday.startISO)
      .lt('created_at', win.yesterday.endISO)
      .limit(50000),
    // Fonte: applications (verdade viva), não swipe_actions.applied (DEPRECATED).
    // created_at = quando a candidatura foi criada (backfill/bridge preservam o
    // applied_at histórico). countsAsApplied filtra em memória. Fase 7 Onda 1.
    sb
      .from('applications')
      .select('user_id, status')
      .gte('created_at', win.yesterday.startISO)
      .lt('created_at', win.yesterday.endISO)
      .limit(50000),
  ]);

  const dauSet = new Set<string>();
  const applierSet = new Set<string>();
  for (const s of swipes ?? []) {
    if (s.user_id) dauSet.add(s.user_id);
  }
  for (const a of applies ?? []) {
    if (a.user_id && countsAsApplied(a.status)) applierSet.add(a.user_id);
  }

  const { data: adapted } = await sb
    .from('adapted_resumes')
    .select('user_id')
    .gte('computed_at', win.yesterday.startISO)
    .lt('computed_at', win.yesterday.endISO)
    .limit(5000);
  const adapterSet = new Set((adapted ?? []).map((r) => r.user_id));

  return {
    dau: dauSet.size,
    cvAdaptersYesterday: adapterSet.size,
    appliersYesterday: applierSet.size,
  };
}

// ============================================================================
// BLOCO 3 — Vagas inseridas (D-1)
// ============================================================================

export interface JobsInsertedBlock {
  total: number;
  totalPrev: number;
  byArea: Array<{ key: string; count: number }>;
  bySource: Array<{ key: string; count: number }>;
  byCompany: Array<{ key: string; count: number }>;
  byWorkModel: Array<{ key: string; count: number }>;
  byJobType: Array<{ key: string; count: number }>;
  byCity: Array<{ key: string; count: number }>;
}

export async function fetchJobsInsertedBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<JobsInsertedBlock> {
  const [total, totalPrev] = await Promise.all([
    countInWindow(sb, 'jobs', 'created_at', win.yesterday),
    countInWindow(sb, 'jobs', 'created_at', win.dayBefore),
  ]);

  const { data: jobs } = await sb
    .from('jobs')
    .select('area, source, work_model, job_type, location_city, company_id, companies(name)')
    .gte('created_at', win.yesterday.startISO)
    .lt('created_at', win.yesterday.endISO)
    .limit(10000);

  const rows = (jobs ?? []) as DbObject[];
  return {
    total,
    totalPrev,
    byArea: groupRows(rows, (r) => norm(r.area)).slice(0, 15),
    bySource: groupRows(rows, (r) => norm(r.source)),
    byCompany: groupRows(rows, (r) => {
      // companies(name) vem como objeto ou array dependendo da relação. Trata os dois.
      const company = relationObject(r.companies);
      return norm(textField(company, 'name'));
    }).slice(0, 10),
    byWorkModel: groupRows(rows, (r) => norm(r.work_model)),
    byJobType: groupRows(rows, (r) => norm(r.job_type)),
    byCity: groupRows(rows, (r) => norm(r.location_city)).slice(0, 10),
  };
}

// ============================================================================
// BLOCO 4 — Estoque atual de vagas
// ============================================================================

export interface JobsStockBlock {
  activeTotal: number;
  byArea: Array<{ key: string; count: number }>;
  avgAgeDays: number;
  applyableRate: number;
}

export async function fetchJobsStockBlock(sb: SupabaseClient): Promise<JobsStockBlock> {
  const { count: activeTotal } = await sb
    .from('jobs')
    .select('*', { count: 'exact', head: true })
    .eq('is_active', true);

  const { data: rows } = await sb
    .from('jobs')
    .select('area, published_at, external_url, application_method, application_email')
    .eq('is_active', true)
    .limit(20000);

  const m = new Map<string, number>();
  let ageSum = 0;
  let ageCount = 0;
  let applyable = 0;
  const now = Date.now();
  for (const r of rows ?? []) {
    const k = r.area && r.area !== '' ? r.area : 'sem_info';
    m.set(k, (m.get(k) ?? 0) + 1);
    if (r.published_at) {
      ageSum += (now - new Date(r.published_at).getTime()) / (24 * 3600 * 1000);
      ageCount++;
    }
    const hasUrl = cleanText(r.external_url) != null;
    const hasEmailTarget = r.application_method === 'email' &&
      cleanText(r.application_email) != null;
    if (hasUrl || hasEmailTarget) applyable++;
  }

  return {
    activeTotal: activeTotal ?? 0,
    byArea: Array.from(m.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 10),
    avgAgeDays: ageCount > 0 ? ageSum / ageCount : 0,
    applyableRate: (rows ?? []).length > 0 ? applyable / (rows ?? []).length : 0,
  };
}

// ============================================================================
// BLOCO 5 — Match & engajamento com vagas (D-1)
// ============================================================================

export interface MatchBlock {
  totalLikes: number;
  totalApplies: number;
  swipeToApplyRate: number;
  likesByArea: Array<{ key: string; count: number }>;
  topLikedJobs: Array<{ title: string; company: string; count: number; url: string | null }>;
  topLikedCompanies: Array<{ key: string; count: number }>;
  avgMatchScore: number;
}

export async function fetchMatchBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<MatchBlock> {
  const [{ data: swipes }, { count: appliesCount }] = await Promise.all([
    sb
      .from('swipe_actions')
      .select('action, job_id, jobs(title, area, external_url, companies(name))')
      .gte('created_at', win.yesterday.startISO)
      .lt('created_at', win.yesterday.endISO)
      .eq('action', 'liked')
      .limit(50000),
    // Fonte: applications (countsAsApplied = exceto withdrawn/expired), não a
    // coluna DEPRECATED swipe_actions.applied. Fase 7 Onda 1.
    sb
      .from('applications')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', win.yesterday.startISO)
      .lt('created_at', win.yesterday.endISO)
      .neq('status', 'withdrawn')
      .neq('status', 'expired'),
  ]);

  const rows = (swipes ?? []) as DbObject[];
  const totalLikes = rows.length;
  const totalApplies = appliesCount ?? 0;

  const areaMap = new Map<string, number>();
  const companyMap = new Map<string, number>();
  const jobMap = new Map<
    string,
    { title: string; company: string; count: number; url: string | null }
  >();

  for (const r of rows) {
    const j = relationObject(r.jobs);
    const area = norm(j?.area);
    areaMap.set(area, (areaMap.get(area) ?? 0) + 1);

    const company = norm(textField(relationObject(j?.companies), 'name'));
    companyMap.set(company, (companyMap.get(company) ?? 0) + 1);

    const jobKey = cleanText(r.job_id) ?? 'unknown';
    const existing = jobMap.get(jobKey);
    if (existing) existing.count++;
    else {
      jobMap.set(jobKey, {
        title: textField(j, 'title') ?? '(sem título)',
        company,
        count: 1,
        url: textField(j, 'external_url'),
      });
    }
  }

  // Match score médio dos pares criados ontem.
  const { data: matches } = await sb
    .from('match_analyses')
    .select('score')
    .gte('computed_at', win.yesterday.startISO)
    .lt('computed_at', win.yesterday.endISO)
    .limit(50000);

  const scores = (matches ?? []).map((m) => m.score).filter((s): s is number =>
    typeof s === 'number'
  );
  const avgMatchScore = scores.length > 0 ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;

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
  };
}

// ============================================================================
// BLOCO 6 — CV adaptado (D-1)
// ============================================================================

export interface CvAdaptedBlock {
  total: number;
  byArea: Array<{ key: string; count: number }>;
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
    .limit(5000);

  const m = new Map<string, number>();
  for (const r of (data ?? []) as DbObject[]) {
    const job = relationObject(r.jobs);
    const area = norm(job?.area);
    m.set(area, (m.get(area) ?? 0) + 1);
  }

  return {
    total: (data ?? []).length,
    byArea: Array.from(m.entries())
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 10),
  };
}

// ============================================================================
// BLOCO 7 — Gap oferta vs demanda
// ============================================================================

export interface GapBlock {
  /// Áreas com muitos likes mas poucas vagas ativas (ratio alto = pouca oferta).
  underservedAreas: Array<{ area: string; likes: number; activeJobs: number; ratio: number }>;
}

export function computeGapBlock(
  likesByArea: Array<{ key: string; count: number }>,
  stockByArea: Array<{ key: string; count: number }>,
): GapBlock {
  const stockMap = new Map(stockByArea.map((s) => [s.key, s.count]));
  const underservedAreas = likesByArea
    .filter((l) => l.count >= 3) // ruído fora — precisa volume mínimo de demanda
    .map((l) => {
      const activeJobs = stockMap.get(l.key) ?? 0;
      const ratio = activeJobs > 0 ? l.count / activeJobs : l.count; // se 0 vagas, ratio = likes
      return { area: l.key, likes: l.count, activeJobs, ratio };
    })
    .sort((a, b) => b.ratio - a.ratio)
    .slice(0, 5);
  return { underservedAreas };
}

// ============================================================================
// BLOCO 8 — Saúde do sistema (D-1)
// ============================================================================

export interface HealthBlock {
  aiGenerations: number;
  /// Soma de tokens consumidos ontem (proxy de gasto).
  totalTokensUsed: number;
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
    .limit(50000);

  const rows = data ?? [];
  return {
    aiGenerations: rows.length,
    totalTokensUsed: rows.reduce((acc, r) => acc + (r.tokens_used ?? 0), 0),
  };
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
  d2Signups: number;
  d2SignupsReturnedD1: number;
  d1RetentionRate: number;

  /// DAU recorrente vs estreante.
  dau: number;
  dauNewToday: number;
  dauReturning: number;
  returningDauRate: number;

  /// Stickiness DAU/MAU.
  mau: number;
  stickiness: number;
}

export async function fetchRetentionBlock(
  sb: SupabaseClient,
  win: ReportWindow,
): Promise<RetentionBlock> {
  // Janela de 30d terminando no fim de ontem.
  const mauStartIso = new Date(
    new Date(win.yesterday.endISO).getTime() - 30 * 24 * 3600 * 1000,
  ).toISOString();

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
  ]);

  const d2Ids = new Set((d2SignupsRes.data ?? []).map((r) => r.id).filter(Boolean) as string[]);
  const d1NewIds = new Set((d1SignupsRes.data ?? []).map((r) => r.id).filter(Boolean) as string[]);

  const dauSet = new Set<string>();
  for (const s of yesterdaySwipesRes.data ?? []) {
    if (s.user_id) dauSet.add(s.user_id as string);
  }

  const mauSet = new Set<string>();
  for (const s of monthSwipesRes.data ?? []) {
    if (s.user_id) mauSet.add(s.user_id as string);
  }

  let d2Returned = 0;
  for (const uid of d2Ids) {
    if (dauSet.has(uid)) d2Returned++;
  }

  let dauNew = 0;
  for (const uid of dauSet) {
    if (d1NewIds.has(uid)) dauNew++;
  }
  const dauReturning = dauSet.size - dauNew;

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
  };
}

// ============================================================================
// BLOCO SEMANAL (domingo) — totais last7
// ============================================================================

export interface WeeklyBlock {
  newSignupsLastWeek: number;
  newSignupsPrevWeek: number;
  jobsLastWeek: number;
  jobsPrevWeek: number;
  likesLastWeek: number;
  likesPrevWeek: number;
  appliesLastWeek: number;
  appliesPrevWeek: number;
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
  ]);

  // Likes: swipe_actions.action='liked'. Applies: fonte migrada p/ applications
  // (countsAsApplied), não a coluna DEPRECATED swipe_actions.applied. Fase 7 Onda 1.
  const countLikes = async (w: DateWindow) => {
    const { count } = await sb
      .from('swipe_actions')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', w.startISO)
      .lt('created_at', w.endISO)
      .eq('action', 'liked');
    return count ?? 0;
  };
  const countApplies = async (w: DateWindow) => {
    const { count } = await sb
      .from('applications')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', w.startISO)
      .lt('created_at', w.endISO)
      .neq('status', 'withdrawn')
      .neq('status', 'expired');
    return count ?? 0;
  };

  const [likesLast, likesPrev, appliesLast, appliesPrev] = await Promise.all([
    countLikes(win.lastWeek),
    countLikes(win.previousWeek),
    countApplies(win.lastWeek),
    countApplies(win.previousWeek),
  ]);

  return {
    newSignupsLastWeek: signupsLast,
    newSignupsPrevWeek: signupsPrev,
    jobsLastWeek: jobsLast,
    jobsPrevWeek: jobsPrev,
    likesLastWeek: likesLast,
    likesPrevWeek: likesPrev,
    appliesLastWeek: appliesLast,
    appliesPrevWeek: appliesPrev,
  };
}
