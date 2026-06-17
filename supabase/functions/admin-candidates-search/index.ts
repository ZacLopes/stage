// Edge Function: admin-candidates-search (Fase 1 T1.8)
//
// Busca de candidatos para a operação comercial (shortlists concierge):
//  - action 'search': filtros de perfil → página de candidatos hidratados
//    (nome, curso, cidade, skills, instituições, completeness, consent).
//  - action 'save_list': seleção manual → candidate_list_requests + items
//    (status 'pending' — o fluxo existente de aprovação/export do
//    admin-candidate-lists assume daqui: aprovar → exportar, consent-gated).
//
// Padrão admin (_shared/admin.ts): requireAdmin + audit em admin_audit_log.
// Eventos server-side (R7): candidate_search_performed, candidate_list_created
// via _shared/posthog.ts captureEvent.

import { serve } from 'std/http/server';
import {
  AdminHttpError,
  adminCorsHeaders,
  audit,
  errorResponse,
  jsonResponse,
  readJson,
  requireAdmin,
} from '../_shared/admin.ts';
import { captureEvent, withEdgeAnalytics } from '../_shared/posthog.ts';

interface SearchFilters {
  course?: string;
  institutionId?: string;
  institutionText?: string;
  city?: string;
  skills?: string[];
  skillIds?: string[]; // skills canônicas (skills_catalog.id) — faceta limpa, AND
  minCompleteness?: number;
  activeWithinDays?: number;
  hasCv?: boolean;
}

interface SearchBody {
  action?: 'search' | 'save_list' | 'skills_catalog';
  filters?: SearchFilters;
  limit?: number;
  offset?: number;
  // save_list
  title?: string;
  area?: string;
  notes?: string;
  userIds?: string[];
}

function ilike(term: string): string {
  return `%${term.replaceAll('%', '').replaceAll(',', ' ').trim()}%`;
}

/// Interseção progressiva de conjuntos de user_id, um por filtro ativo.
/// Base ~2k users — queries paralelas + interseção em memória são baratas
/// e evitam SQL dinâmico.
async function resolveCandidateIds(
  supabase: AdminSupabase,
  f: SearchFilters,
): Promise<string[]> {
  const sets: Array<Set<string>> = [];

  // Base: todo mundo com perfil relacional (profile_personal).
  let base = supabase.from('profile_personal').select('user_id');
  if (f.city && f.city.trim()) base = base.ilike('location_city', ilike(f.city));
  if (typeof f.minCompleteness === 'number' && f.minCompleteness > 0) {
    base = base.gte('completeness_score', f.minCompleteness);
  }
  const baseR = await base;
  if (baseR.error) throw new AdminHttpError(500, 'search_base_failed', baseR.error.message);
  sets.push(new Set((baseR.data ?? []).map((r: { user_id: string }) => r.user_id)));

  if (f.course && f.course.trim()) {
    const [up, edu] = await Promise.all([
      supabase.from('user_profiles').select('id').ilike('course', ilike(f.course)),
      supabase.from('profile_education_majors')
        .select('name, profile_education(user_id)')
        .ilike('name', ilike(f.course)),
    ]);
    const ids = new Set<string>();
    for (const r of up.data ?? []) ids.add((r as { id: string }).id);
    for (const r of (edu.data ?? []) as Array<{ profile_education: { user_id: string } | null }>) {
      if (r.profile_education?.user_id) ids.add(r.profile_education.user_id);
    }
    sets.push(ids);
  }

  if (f.institutionId || (f.institutionText && f.institutionText.trim())) {
    let q = supabase.from('profile_education').select('user_id');
    if (f.institutionId) q = q.eq('institution_id', f.institutionId);
    else q = q.ilike('institution', ilike(f.institutionText!));
    const r = await q;
    if (r.error) throw new AdminHttpError(500, 'search_institution_failed', r.error.message);
    sets.push(new Set((r.data ?? []).map((row: { user_id: string }) => row.user_id)));
  }

  // Skills canônicas (faceta): semântica AND — bate TODAS as skills escolhidas.
  // Filtra por canonical_skill_id, então "Excel" pega todas as grafias.
  for (const sid of f.skillIds ?? []) {
    if (!sid) continue;
    const r = await supabase.from('profile_skills').select('user_id').eq('canonical_skill_id', sid);
    if (r.error) throw new AdminHttpError(500, 'search_skill_ids_failed', r.error.message);
    sets.push(new Set((r.data ?? []).map((row: { user_id: string }) => row.user_id)));
  }

  // Skills texto-livre (legacy/cauda fora do catálogo): AND por substring.
  for (const term of f.skills ?? []) {
    if (!term.trim()) continue;
    const r = await supabase.from('profile_skills').select('user_id').ilike('name', ilike(term));
    if (r.error) throw new AdminHttpError(500, 'search_skills_failed', r.error.message);
    sets.push(new Set((r.data ?? []).map((row: { user_id: string }) => row.user_id)));
  }

  if (typeof f.activeWithinDays === 'number' && f.activeWithinDays > 0) {
    const cutoff = new Date(Date.now() - f.activeWithinDays * 86_400_000).toISOString();
    // Proxy de atividade: swipou recentemente (decisão do plano — eventos
    // PostHog não são consultáveis daqui).
    const r = await supabase.from('swipe_actions').select('user_id').gte('created_at', cutoff);
    if (r.error) throw new AdminHttpError(500, 'search_activity_failed', r.error.message);
    sets.push(new Set((r.data ?? []).map((row: { user_id: string }) => row.user_id)));
  }

  if (f.hasCv) {
    const [resumes, exps] = await Promise.all([
      supabase.from('saved_resumes').select('user_id'),
      supabase.from('profile_experiences').select('user_id'),
    ]);
    const ids = new Set<string>();
    for (const r of resumes.data ?? []) ids.add((r as { user_id: string }).user_id);
    for (const r of exps.data ?? []) ids.add((r as { user_id: string }).user_id);
    sets.push(ids);
  }

  let result = sets[0];
  for (const s of sets.slice(1)) {
    result = new Set([...result].filter((id) => s.has(id)));
  }
  return [...result];
}

// deno-lint-ignore no-explicit-any
type AdminSupabase = any;

async function hydrate(supabase: AdminSupabase, ids: string[]) {
  if (ids.length === 0) return [];
  const [profilesR, personalR, skillsR, eduR, consentsR] = await Promise.all([
    supabase.from('user_profiles').select('id, name, email, course, semester').in('id', ids),
    supabase.from('profile_personal')
      .select('user_id, location_city, location_state, completeness_score, onboarding_completed_at')
      .in('user_id', ids),
    supabase.from('profile_skills')
      .select('user_id, name, skills_catalog(canonical_name, category)')
      .in('user_id', ids),
    supabase.from('profile_education').select('user_id, institution, education_level').in('user_id', ids),
    supabase.from('candidate_data_sharing_consents').select('user_id, status').in('user_id', ids),
  ]);

  const personal = new Map((personalR.data ?? []).map((r: { user_id: string }) => [r.user_id, r]));
  const consent = new Map((consentsR.data ?? []).map(
    (r: { user_id: string; status: string }) => [r.user_id, r.status],
  ));
  const skills = new Map<string, string[]>();
  const canonicalSkills = new Map<string, Array<{ name: string; category: string }>>();
  for (
    const r of (skillsR.data ?? []) as Array<
      { user_id: string; name: string; skills_catalog: { canonical_name: string; category: string } | null }
    >
  ) {
    const list = skills.get(r.user_id) ?? [];
    if (list.length < 6) list.push(r.name);
    skills.set(r.user_id, list);
    if (r.skills_catalog) {
      const cl = canonicalSkills.get(r.user_id) ?? [];
      if (!cl.some((x) => x.name === r.skills_catalog!.canonical_name)) {
        cl.push({ name: r.skills_catalog.canonical_name, category: r.skills_catalog.category });
      }
      canonicalSkills.set(r.user_id, cl);
    }
  }
  const institutions = new Map<string, string[]>();
  for (const r of (eduR.data ?? []) as Array<{ user_id: string; institution: string }>) {
    const list = institutions.get(r.user_id) ?? [];
    if (r.institution && !list.includes(r.institution)) list.push(r.institution);
    institutions.set(r.user_id, list);
  }

  return ((profilesR.data ?? []) as Array<Record<string, unknown>>).map((p) => {
    const uid = p.id as string;
    const pp = personal.get(uid) as Record<string, unknown> | undefined;
    return {
      userId: uid,
      name: p.name ?? '',
      email: p.email ?? '',
      course: p.course ?? '',
      semester: p.semester ?? '',
      city: pp?.location_city ?? null,
      state: pp?.location_state ?? null,
      completeness: pp?.completeness_score ?? 0,
      onboardingCompletedAt: pp?.onboarding_completed_at ?? null,
      skills: skills.get(uid) ?? [],
      canonicalSkills: canonicalSkills.get(uid) ?? [],
      institutions: institutions.get(uid) ?? [],
      consentStatus: consent.get(uid) ?? 'not_asked',
    };
  });
}

serve(withEdgeAnalytics('admin-candidates-search', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: adminCorsHeaders });
  try {
    const ctx = await requireAdmin(req);
    const body = await readJson<SearchBody>(req);
    const action = body.action ?? 'search';

    if (action === 'search') {
      const filters = body.filters ?? {};
      const ids = await resolveCandidateIds(ctx.supabase, filters);
      const limit = Math.min(Math.max(body.limit ?? 25, 1), 100);
      const offset = Math.max(body.offset ?? 0, 0);
      const page = ids.slice(offset, offset + limit);
      const candidates = await hydrate(ctx.supabase, page);

      await audit(ctx, req, {
        action: 'admin_candidates_searched',
        metadata: { filters, total: ids.length },
      });
      captureEvent({
        event: 'candidate_search_performed',
        distinctId: ctx.userId,
        properties: {
          result_count: ids.length,
          filters_used: Object.entries(filters)
            .filter(([, v]) => v !== undefined && v !== null && v !== '' &&
              !(Array.isArray(v) && v.length === 0) && v !== false)
            .map(([k]) => k),
        },
      }).catch(() => {});

      return jsonResponse({ total: ids.length, offset, limit, candidates });
    }

    if (action === 'skills_catalog') {
      // Alimenta a faceta de skill canônica do picker. Ordenado por categoria
      // e nome (técnicas — hard/tool — primeiro, depois soft/idioma).
      const r = await ctx.supabase
        .from('skills_catalog')
        .select('id, canonical_name, category');
      if (r.error) throw new AdminHttpError(500, 'skills_catalog_failed', r.error.message);
      const order: Record<string, number> = { hard: 0, tool: 1, language: 2, soft: 3 };
      const catalog = ((r.data ?? []) as Array<{ id: string; canonical_name: string; category: string }>)
        .map((c) => ({ id: c.id, name: c.canonical_name, category: c.category }))
        .sort((a, b) =>
          (order[a.category] ?? 9) - (order[b.category] ?? 9) || a.name.localeCompare(b.name)
        );
      return jsonResponse({ catalog });
    }

    if (action === 'save_list') {
      const userIds = (body.userIds ?? []).filter(Boolean);
      if (!body.title?.trim() || userIds.length === 0) {
        return jsonResponse({ error: 'missing_title_or_candidates' }, 400);
      }
      const { data: request, error: reqError } = await ctx.supabase
        .from('candidate_list_requests')
        .insert({
          title: body.title.trim(),
          area: body.area ?? null,
          description: body.notes ?? 'Criada pela busca de candidatos (Fase 1)',
          min_score: 0,
          status: 'review',
          created_by: ctx.email,
        })
        .select()
        .single();
      if (reqError) {
        return jsonResponse({ error: 'request_insert_failed', message: reqError.message }, 500);
      }
      const rows = userIds.map((uid, index) => ({
        request_id: request.id,
        user_id: uid,
        rank: index + 1,
        // Lista da busca é seleção manual (concierge), não tem match score.
        // A coluna é NOT NULL + CHECK (0..100); 0 = "não pontuado".
        score: 0,
        status: 'pending',
      }));
      const { error: itemsError } = await ctx.supabase.from('candidate_list_items').insert(rows);
      if (itemsError) {
        return jsonResponse({ error: 'items_insert_failed', message: itemsError.message }, 500);
      }

      await audit(ctx, req, {
        action: 'admin_candidate_list_created_from_search',
        entityType: 'candidate_list_request',
        entityId: request.id,
        metadata: { size: rows.length },
      });
      captureEvent({
        event: 'candidate_list_created',
        distinctId: ctx.userId,
        properties: { request_id: request.id, size: rows.length },
      }).catch(() => {});

      return jsonResponse({ request, itemCount: rows.length });
    }

    return jsonResponse({ error: 'unknown_action' }, 400);
  } catch (error) {
    return errorResponse(error);
  }
}));
