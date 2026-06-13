import { serve } from 'std/http/server';
import {
  adminCorsHeaders,
  audit,
  errorResponse,
  jsonResponse,
  parsePagination,
  readJson,
  requireAdmin,
} from '../_shared/admin.ts';

interface JobsRequest {
  action?: 'list' | 'detail' | 'company_requests';
  id?: string;
  page?: number;
  pageSize?: number;
  filters?: {
    search?: string;
    status?: 'all' | 'active' | 'inactive';
    area?: string;
    source?: string;
    workModel?: string;
    jobType?: string;
  };
}

function relationObject(value: unknown): Record<string, unknown> | null {
  if (Array.isArray(value)) return value[0] as Record<string, unknown> | null;
  return value && typeof value === 'object' ? value as Record<string, unknown> : null;
}

async function loadJobMetrics(supabase: any, jobIds: string[]) {
  const metrics = new Map<string, { likes: number; applies: number; avgScore: number }>();
  if (jobIds.length === 0) return metrics;

  for (const id of jobIds) metrics.set(id, { likes: 0, applies: 0, avgScore: 0 });

  const { data, error } = await supabase.rpc('admin_job_metrics', { p_job_ids: jobIds });
  if (error) {
    console.warn('admin_job_metrics_failed', error.message);
    return metrics;
  }

  for (const row of data ?? []) {
    metrics.set(String(row.job_id), {
      likes: Number(row.likes ?? 0),
      applies: Number(row.applies ?? 0),
      avgScore: Number(row.avg_score ?? 0),
    });
  }
  return metrics;
}

function mapJob(
  row: Record<string, unknown>,
  metric?: { likes: number; applies: number; avgScore: number },
) {
  const company = relationObject(row.companies);
  const publishedAt = row.published_at ? new Date(String(row.published_at)) : null;
  const ageDays = publishedAt
    ? Math.max(0, Math.round((Date.now() - publishedAt.getTime()) / (24 * 3600 * 1000)))
    : null;

  return {
    id: row.id,
    title: row.title,
    company: company
      ? {
        id: company.id,
        name: company.name,
        logoUrl: company.logo_url,
        website: company.website,
        description: company.description,
      }
      : null,
    area: row.area,
    locationCity: row.location_city,
    locationState: row.location_state,
    workModel: row.work_model,
    jobType: row.job_type,
    salaryMin: row.salary_min,
    salaryMax: row.salary_max,
    isActive: row.is_active,
    source: row.source,
    externalUrl: row.external_url,
    applicationMethod: row.application_method,
    applicationEmail: row.application_email,
    applicationSubject: row.application_subject,
    publishedAt: row.published_at,
    deadline: row.deadline,
    createdAt: row.created_at,
    ageDays,
    description: row.description,
    descriptionHtml: row.description_html,
    requirements: row.requirements ?? [],
    benefits: row.benefits ?? [],
    metrics: metric ?? { likes: 0, applies: 0, avgScore: 0 },
  };
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: adminCorsHeaders });

  try {
    const ctx = await requireAdmin(req);
    const body = await readJson<JobsRequest>(req);
    const action = body.action ?? 'list';
    const supabase = ctx.supabase;

    // FASE 2 (T2.3): pedidos de empresa do estado de exaustão do feed
    // (tabela company_requests, RLS own-* — admin lê via service role aqui).
    if (action === 'company_requests') {
      const { page, pageSize } = parsePagination(body);
      const from = (page - 1) * pageSize;
      const to = from + pageSize - 1;
      const { data, error, count } = await supabase
        .from('company_requests')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })
        .range(from, to);
      if (error) {
        return jsonResponse({ error: 'company_requests_failed', message: error.message }, 500);
      }

      // hidrata nome/email do solicitante (user_profiles é public)
      const userIds = [
        ...new Set((data ?? []).map((r: Record<string, unknown>) => String(r.user_id))),
      ];
      const profiles = new Map<string, { name?: string; email?: string }>();
      if (userIds.length > 0) {
        const { data: rows } = await supabase
          .from('user_profiles')
          .select('id, name, email')
          .in('id', userIds);
        for (const p of rows ?? []) {
          profiles.set(String(p.id), {
            name: p.name ?? undefined,
            email: p.email ?? undefined,
          });
        }
      }

      await audit(ctx, req, {
        action: 'admin_company_requests_listed',
        entityType: 'company_request',
        metadata: { page, pageSize },
      });

      return jsonResponse({
        requests: (data ?? []).map((r: Record<string, unknown>) => ({
          id: r.id,
          companyName: r.company_name,
          note: r.note,
          createdAt: r.created_at,
          userId: r.user_id,
          user: profiles.get(String(r.user_id)) ?? null,
        })),
        page,
        pageSize,
        total: count ?? 0,
      });
    }

    if (action === 'detail') {
      if (!body.id) return jsonResponse({ error: 'missing_id' }, 400);
      const { data, error } = await supabase
        .from('jobs')
        .select('*, companies(*)')
        .eq('id', body.id)
        .maybeSingle();
      if (error) return jsonResponse({ error: 'job_detail_failed', message: error.message }, 500);
      if (!data) return jsonResponse({ error: 'not_found' }, 404);
      const metrics = await loadJobMetrics(supabase, [body.id]);
      await audit(ctx, req, { action: 'admin_job_viewed', entityType: 'job', entityId: body.id });
      return jsonResponse({ job: mapJob(data, metrics.get(body.id)) });
    }

    const { page, pageSize } = parsePagination(body);
    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;
    const filters = body.filters ?? {};

    let query = supabase
      .from('jobs')
      .select('*, companies(id, name, logo_url, website, description)', { count: 'exact' })
      .order('published_at', { ascending: false })
      .range(from, to);

    if (filters.status === 'active') query = query.eq('is_active', true);
    if (filters.status === 'inactive') query = query.eq('is_active', false);
    if (filters.area) query = query.eq('area', filters.area);
    if (filters.source) query = query.eq('source', filters.source);
    if (filters.workModel) query = query.eq('work_model', filters.workModel);
    if (filters.jobType) query = query.eq('job_type', filters.jobType);
    if (filters.search?.trim()) {
      const safe = filters.search.trim().replaceAll(',', ' ').slice(0, 80);
      query = query.or(`title.ilike.%${safe}%,description.ilike.%${safe}%`);
    }

    const { data, error, count } = await query;
    if (error) return jsonResponse({ error: 'job_list_failed', message: error.message }, 500);

    const ids = (data ?? []).map((row: Record<string, unknown>) => String(row.id));
    const metrics = await loadJobMetrics(supabase, ids);

    await audit(ctx, req, {
      action: 'admin_jobs_listed',
      entityType: 'job',
      metadata: { page, pageSize, filters },
    });

    return jsonResponse({
      jobs: (data ?? []).map((row: Record<string, unknown>) =>
        mapJob(row, metrics.get(String(row.id)))
      ),
      page,
      pageSize,
      total: count ?? 0,
    });
  } catch (error) {
    return errorResponse(error);
  }
});
