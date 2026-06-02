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

interface UsersRequest {
  action?: 'list' | 'detail' | 'update_consent';
  id?: string;
  revealPii?: boolean;
  page?: number;
  pageSize?: number;
  filters?: {
    search?: string;
    city?: string;
    state?: string;
    university?: string;
    course?: string;
    semester?: string;
    skill?: string;
    desiredTitle?: string;
    consentStatus?: 'not_asked' | 'granted' | 'denied' | 'revoked';
  };
  consent?: {
    status: 'not_asked' | 'granted' | 'denied' | 'revoked';
    reason?: string;
  };
}

function maskEmail(value: unknown): string {
  const email = String(value ?? '');
  const [local, domain] = email.split('@');
  if (!local || !domain) return '';
  return `${local.slice(0, 2)}***@${domain}`;
}

function maskPhone(value: unknown): string {
  const digits = String(value ?? '').replace(/\D/g, '');
  if (digits.length < 4) return '';
  return `***${digits.slice(-4)}`;
}

function maskName(value: unknown): string {
  const parts = String(value ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '';
  return parts.map((p) => `${p[0]?.toUpperCase() ?? ''}.`).join(' ');
}

function intersect(current: Set<string> | null, next: string[]): Set<string> {
  const nextSet = new Set(next);
  if (current == null) return nextSet;
  return new Set(Array.from(current).filter((id) => nextSet.has(id)));
}

async function candidateIdsForFilters(supabase: any, filters: UsersRequest['filters']) {
  if (!filters) return null;
  let ids: Set<string> | null = null;

  if (filters.skill?.trim()) {
    const { data } = await supabase
      .from('profile_skills')
      .select('user_id')
      .ilike('name', `%${filters.skill.trim()}%`)
      .limit(50000);
    ids = intersect(ids, (data ?? []).map((row: any) => row.user_id));
  }

  if (filters.desiredTitle?.trim()) {
    const { data } = await supabase
      .from('profile_desired_titles')
      .select('user_id')
      .ilike('title', `%${filters.desiredTitle.trim()}%`)
      .limit(50000);
    ids = intersect(ids, (data ?? []).map((row: any) => row.user_id));
  }

  if (filters.city?.trim() || filters.state?.trim()) {
    let q = supabase.from('profile_personal').select('user_id').limit(50000);
    if (filters.city?.trim()) q = q.ilike('location_city', `%${filters.city.trim()}%`);
    if (filters.state?.trim()) q = q.ilike('location_state', `%${filters.state.trim()}%`);
    const { data } = await q;
    ids = intersect(ids, (data ?? []).map((row: any) => row.user_id));
  }

  if (filters.university?.trim() || filters.course?.trim()) {
    let q = supabase.from('profile_education').select('user_id').limit(50000);
    if (filters.university?.trim()) q = q.ilike('institution', `%${filters.university.trim()}%`);
    if (filters.course?.trim()) q = q.ilike('degree', `%${filters.course.trim()}%`);
    const { data } = await q;
    ids = intersect(ids, (data ?? []).map((row: any) => row.user_id));
  }

  if (filters.consentStatus && filters.consentStatus !== 'not_asked') {
    const { data } = await supabase
      .from('candidate_data_sharing_consents')
      .select('user_id')
      .eq('status', filters.consentStatus)
      .limit(50000);
    ids = intersect(ids, (data ?? []).map((row: any) => row.user_id));
  }

  return ids;
}

async function loadUserFacts(supabase: any, userIds: string[]) {
  if (userIds.length === 0) {
    return {
      personal: new Map(),
      skills: new Map(),
      titles: new Map(),
      education: new Map(),
      consents: new Map(),
      swipes: new Map(),
    };
  }

  const [personalR, skillsR, titlesR, educationR, consentsR, swipesR] = await Promise.all([
    supabase.from('profile_personal').select('*').in('user_id', userIds),
    supabase.from('profile_skills').select('user_id, name').in('user_id', userIds),
    supabase.from('profile_desired_titles').select('user_id, title').in('user_id', userIds),
    supabase
      .from('profile_education')
      .select('user_id, institution, degree, order_index, education_level, current_semester')
      .in('user_id', userIds),
    supabase.from('candidate_data_sharing_consents').select('*').in('user_id', userIds),
    supabase.from('swipe_actions').select('user_id, action, applied').in('user_id', userIds).limit(
      50000,
    ),
  ]);

  const personal = new Map((personalR.data ?? []).map((row: any) => [row.user_id, row]));
  const consents = new Map((consentsR.data ?? []).map((row: any) => [row.user_id, row]));
  const skills = new Map<string, string[]>();
  const titles = new Map<string, string[]>();
  const education = new Map<string, any>();
  const swipes = new Map<string, { likes: number; rejects: number; applies: number }>();

  for (const row of skillsR.data ?? []) {
    const values = skills.get(row.user_id) ?? [];
    values.push(row.name);
    skills.set(row.user_id, values);
  }
  for (const row of titlesR.data ?? []) {
    const values = titles.get(row.user_id) ?? [];
    values.push(row.title);
    titles.set(row.user_id, values);
  }
  for (
    const row of (educationR.data ?? []).sort((a: any, b: any) =>
      (a.order_index ?? 0) - (b.order_index ?? 0)
    )
  ) {
    if (!education.has(row.user_id)) education.set(row.user_id, row);
  }
  for (const row of swipesR.data ?? []) {
    const current = swipes.get(row.user_id) ?? { likes: 0, rejects: 0, applies: 0 };
    if (row.action === 'liked') current.likes++;
    if (row.action === 'rejected') current.rejects++;
    if (row.applied === true) current.applies++;
    swipes.set(row.user_id, current);
  }

  return { personal, skills, titles, education, consents, swipes };
}

function mapUser(row: any, facts: any, revealPii: boolean) {
  const personal = facts.personal.get(row.id);
  const fullName = [personal?.first_name, personal?.last_name].filter(Boolean).join(' ') ||
    row.name || '';
  const email = personal?.email || row.email || '';
  const phone = personal?.phone_number_e164 || personal?.phone_number || row.phone || '';
  const consent = facts.consents.get(row.id);
  const education = facts.education.get(row.id);

  return {
    id: row.id,
    name: revealPii ? fullName : maskName(fullName),
    email: revealPii ? email : maskEmail(email),
    phone: revealPii ? phone : maskPhone(phone),
    piiRevealed: revealPii,
    city: personal?.location_city ?? null,
    state: personal?.location_state ?? null,
    headline: personal?.headline ?? null,
    summary: personal?.summary ?? null,
    completenessScore: personal?.completeness_score ?? 0,
    profileSource: personal?.profile_source ?? null,
    aiConsent: row.ai_consent === true,
    dataSharingConsent: consent?.status ?? 'not_asked',
    education: education
      ? {
        institution: education.institution,
        degree: education.degree,
        level: education.education_level,
        currentSemester: education.current_semester,
      }
      : null,
    course: row.course,
    semester: row.semester,
    age: row.age,
    skills: (facts.skills.get(row.id) ?? []).slice(0, 12),
    desiredTitles: (facts.titles.get(row.id) ?? []).slice(0, 8),
    activity: facts.swipes.get(row.id) ?? { likes: 0, rejects: 0, applies: 0 },
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: adminCorsHeaders });

  try {
    const ctx = await requireAdmin(req);
    const body = await readJson<UsersRequest>(req);
    const action = body.action ?? 'list';
    const supabase = ctx.supabase;

    if (action === 'update_consent') {
      if (!body.id || !body.consent?.status) {
        return jsonResponse({ error: 'missing_consent_payload' }, 400);
      }
      const now = new Date().toISOString();
      const { data, error } = await supabase
        .from('candidate_data_sharing_consents')
        .upsert({
          user_id: body.id,
          status: body.consent.status,
          status_reason: body.consent.reason ?? null,
          granted_at: body.consent.status === 'granted' ? now : null,
          revoked_at: body.consent.status === 'revoked' ? now : null,
          updated_by_admin: ctx.email,
          updated_at: now,
        }, { onConflict: 'user_id' })
        .select()
        .single();
      if (error) {
        return jsonResponse({ error: 'consent_update_failed', message: error.message }, 500);
      }
      await audit(ctx, req, {
        action: 'admin_candidate_consent_updated',
        entityType: 'user',
        entityId: body.id,
        metadata: { status: body.consent.status },
      });
      return jsonResponse({ consent: data });
    }

    if (action === 'detail') {
      if (!body.id) return jsonResponse({ error: 'missing_id' }, 400);
      const { data, error } = await supabase.from('user_profiles').select('*').eq('id', body.id)
        .maybeSingle();
      if (error) return jsonResponse({ error: 'user_detail_failed', message: error.message }, 500);
      if (!data) return jsonResponse({ error: 'not_found' }, 404);
      const facts = await loadUserFacts(supabase, [body.id]);
      await audit(ctx, req, {
        action: body.revealPii ? 'admin_user_pii_revealed' : 'admin_user_viewed',
        entityType: 'user',
        entityId: body.id,
      });
      return jsonResponse({ user: mapUser(data, facts, body.revealPii === true) });
    }

    const { page, pageSize } = parsePagination(body);
    const filters = body.filters ?? {};
    const filteredIds = await candidateIdsForFilters(supabase, filters);
    if (filteredIds && filteredIds.size === 0) {
      return jsonResponse({ users: [], page, pageSize, total: 0 });
    }

    let query = supabase
      .from('user_profiles')
      .select('id, name, email, course, semester, age, phone, ai_consent, created_at, updated_at', {
        count: 'exact',
      })
      .order('created_at', { ascending: false });

    if (filteredIds) query = query.in('id', Array.from(filteredIds));
    if (filters.search?.trim()) {
      const safe = filters.search.trim().replaceAll(',', ' ').slice(0, 80);
      query = query.or(`name.ilike.%${safe}%,email.ilike.%${safe}%,course.ilike.%${safe}%`);
    }
    if (filters.course?.trim()) query = query.ilike('course', `%${filters.course.trim()}%`);
    if (filters.semester?.trim()) query = query.ilike('semester', `%${filters.semester.trim()}%`);

    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;
    const { data, error, count } = await query.range(from, to);
    if (error) return jsonResponse({ error: 'user_list_failed', message: error.message }, 500);

    const ids = (data ?? []).map((row: any) => row.id);
    const facts = await loadUserFacts(supabase, ids);
    await audit(ctx, req, {
      action: 'admin_users_listed',
      entityType: 'user',
      metadata: { page, pageSize, filters },
    });

    return jsonResponse({
      users: (data ?? []).map((row: any) => mapUser(row, facts, false)),
      page,
      pageSize,
      total: count ?? 0,
    });
  } catch (error) {
    return errorResponse(error);
  }
});
