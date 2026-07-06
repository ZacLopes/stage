import { serve } from 'std/http/server';
import {
  adminCorsHeaders,
  audit,
  errorResponse,
  jsonResponse,
  requireAdmin,
} from '../_shared/admin.ts';

async function countRows(
  supabase: any,
  table: string,
  filters: Array<(q: any) => any> = [],
): Promise<number> {
  let q = supabase.from(table).select('*', { count: 'exact', head: true });
  for (const filter of filters) q = filter(q);
  const { count, error } = await q;
  if (error) {
    console.error(`[admin-overview] count ${table} failed:`, error.message);
    return 0;
  }
  return count ?? 0;
}

function dateKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function lastNDays(days: number): string[] {
  const keys: string[] = [];
  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(today);
    d.setUTCDate(today.getUTCDate() - i);
    keys.push(dateKey(d));
  }
  return keys;
}

function increment(map: Map<string, number>, key: string | null | undefined): void {
  const safe = key && key.trim() ? key.trim() : 'sem_info';
  map.set(safe, (map.get(safe) ?? 0) + 1);
}

function topN(map: Map<string, number>, n: number): Array<{ key: string; count: number }> {
  return Array.from(map.entries())
    .map(([key, count]) => ({ key, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, n);
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: adminCorsHeaders });

  try {
    const ctx = await requireAdmin(req);
    const supabase = ctx.supabase;
    const since = new Date();
    since.setUTCDate(since.getUTCDate() - 13);
    since.setUTCHours(0, 0, 0, 0);
    const sinceIso = since.toISOString();

    const [
      totalUsers,
      completeProfiles,
      activeJobs,
      totalJobs,
      totalLikes,
      totalApplies,
      adaptedResumes,
      grantedConsents,
      pendingConsents,
    ] = await Promise.all([
      countRows(supabase, 'user_profiles'),
      countRows(supabase, 'profile_personal', [(q) => q.gte('completeness_score', 60)]),
      countRows(supabase, 'jobs', [(q) => q.eq('is_active', true)]),
      countRows(supabase, 'jobs'),
      countRows(supabase, 'swipe_actions', [(q) => q.eq('action', 'liked')]),
      // Fonte: applications (verdade viva), NÃO swipe_actions.applied (DEPRECATED,
      // só builds ≤2.2.0 escrevem). countsAsApplied = qualquer status exceto
      // withdrawn/expired (espelha applications.dart). Fase 7 Onda 1.
      countRows(supabase, 'applications', [
        (q) => q.neq('status', 'withdrawn').neq('status', 'expired'),
      ]),
      countRows(supabase, 'adapted_resumes'),
      countRows(supabase, 'candidate_data_sharing_consents', [(q) => q.eq('status', 'granted')]),
      countRows(supabase, 'candidate_data_sharing_consents', [(q) => q.eq('status', 'not_asked')]),
    ]);

    const [
      { data: recentUsers },
      { data: recentSwipes },
      { data: recentApplications },
      { data: jobsByAreaRows },
    ] = await Promise
      .all([
        supabase
          .from('user_profiles')
          .select('created_at')
          .gte('created_at', sinceIso)
          .limit(50000),
        supabase
          .from('swipe_actions')
          .select('created_at, action')
          .gte('created_at', sinceIso)
          .limit(50000),
        // Série de candidaturas: applications (created_at = quando aplicou; o
        // backfill/bridge preservam o applied_at histórico), não a coluna
        // DEPRECATED swipe_actions.applied. Fase 7 Onda 1.
        supabase
          .from('applications')
          .select('created_at, status')
          .gte('created_at', sinceIso)
          .limit(50000),
        supabase
          .from('jobs')
          .select('area, source, work_model, job_type')
          .eq('is_active', true)
          .limit(50000),
      ]);

    const dayKeys = lastNDays(14);
    const usersByDay = new Map(dayKeys.map((key) => [key, 0]));
    const likesByDay = new Map(dayKeys.map((key) => [key, 0]));
    const appliesByDay = new Map(dayKeys.map((key) => [key, 0]));

    for (const row of recentUsers ?? []) {
      const key = dateKey(new Date(row.created_at));
      if (usersByDay.has(key)) usersByDay.set(key, (usersByDay.get(key) ?? 0) + 1);
    }
    for (const row of recentSwipes ?? []) {
      const key = dateKey(new Date(row.created_at));
      if (row.action === 'liked' && likesByDay.has(key)) {
        likesByDay.set(key, (likesByDay.get(key) ?? 0) + 1);
      }
    }
    for (const row of recentApplications ?? []) {
      // countsAsApplied: exclui withdrawn/expired (espelha applications.dart).
      if (row.status === 'withdrawn' || row.status === 'expired') continue;
      const key = dateKey(new Date(row.created_at));
      if (appliesByDay.has(key)) appliesByDay.set(key, (appliesByDay.get(key) ?? 0) + 1);
    }

    const areaMap = new Map<string, number>();
    const sourceMap = new Map<string, number>();
    const workModelMap = new Map<string, number>();
    const jobTypeMap = new Map<string, number>();
    for (const row of jobsByAreaRows ?? []) {
      increment(areaMap, row.area);
      increment(sourceMap, row.source);
      increment(workModelMap, row.work_model);
      increment(jobTypeMap, row.job_type);
    }

    await audit(ctx, req, { action: 'admin_overview_viewed', entityType: 'overview' });

    return jsonResponse({
      kpis: {
        totalUsers,
        completeProfiles,
        activeJobs,
        totalJobs,
        totalLikes,
        totalApplies,
        adaptedResumes,
        grantedConsents,
        pendingConsents,
        profileCompletionRate: totalUsers > 0 ? completeProfiles / totalUsers : 0,
        applyRate: totalLikes > 0 ? totalApplies / totalLikes : 0,
      },
      series: dayKeys.map((day) => ({
        day,
        users: usersByDay.get(day) ?? 0,
        likes: likesByDay.get(day) ?? 0,
        applies: appliesByDay.get(day) ?? 0,
      })),
      jobs: {
        byArea: topN(areaMap, 10),
        bySource: topN(sourceMap, 10),
        byWorkModel: topN(workModelMap, 10),
        byJobType: topN(jobTypeMap, 10),
      },
    });
  } catch (error) {
    return errorResponse(error);
  }
});
