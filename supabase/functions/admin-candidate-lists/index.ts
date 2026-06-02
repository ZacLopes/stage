import { serve } from 'std/http/server';
import {
  adminCorsHeaders,
  AdminHttpError,
  audit,
  csvEscape,
  errorResponse,
  jsonResponse,
  normalizeText,
  parsePagination,
  readJson,
  requireAdmin,
  tokenize,
} from '../_shared/admin.ts';

interface CandidateListsRequest {
  action?: 'list' | 'detail' | 'create' | 'generate' | 'update_item' | 'export';
  id?: string;
  itemId?: string;
  page?: number;
  pageSize?: number;
  request?: {
    clientId?: string | null;
    sourceJobId?: string | null;
    title?: string;
    area?: string | null;
    description?: string | null;
    requirements?: string[];
    locationCity?: string | null;
    locationState?: string | null;
    workModel?: string | null;
    jobType?: string | null;
    minScore?: number;
  };
  item?: {
    status?: 'pending' | 'approved' | 'rejected' | 'exported';
    notes?: string | null;
  };
}

interface CandidateProfile {
  userId: string;
  name: string;
  email: string;
  phone: string;
  city: string;
  state: string;
  headline: string;
  summary: string;
  completenessScore: number;
  skills: string[];
  desiredTitles: string[];
  education: string[];
  workModes: string[];
  jobTypes: string[];
  otherLocations: string[];
  likes: number;
  applies: number;
  consentStatus: string;
  createdAt: string;
}

function text(value: unknown): string {
  return String(value ?? '').trim();
}

function relationObject(value: unknown): Record<string, unknown> | null {
  if (Array.isArray(value)) return value[0] as Record<string, unknown> | null;
  return value && typeof value === 'object' ? value as Record<string, unknown> : null;
}

function maskEmail(value: string): string {
  const [local, domain] = value.split('@');
  if (!local || !domain) return '';
  return `${local.slice(0, 2)}***@${domain}`;
}

function maskName(value: string): string {
  return value
    .split(/\s+/)
    .filter(Boolean)
    .map((part) => `${part[0]?.toUpperCase() ?? ''}.`)
    .join(' ');
}

function normalizeWorkMode(value: string): string {
  switch (value) {
    case 'remote':
      return 'remoto';
    case 'hybrid':
      return 'hibrido';
    case 'in_person':
      return 'presencial';
    default:
      return value;
  }
}

function normalizeJobType(value: string): string {
  switch (value) {
    case 'internship':
      return 'estagio';
    case 'full_time':
      return 'clt_junior';
    case 'contract':
      return 'temporario';
    case 'part_time':
      return 'temporario';
    default:
      return value;
  }
}

function hasTokenOverlap(a: string[], b: string[]): boolean {
  const set = new Set(a);
  return b.some((token) => set.has(token));
}

function scoreCandidate(request: any, candidate: CandidateProfile) {
  const breakdown: Array<{ label: string; points: number; detail: string }> = [];
  let score = 0;

  const reqTitleTokens = tokenize(`${request.title ?? ''} ${request.area ?? ''}`);
  const candidateTitleTokens = tokenize([
    ...candidate.desiredTitles,
    candidate.headline,
    candidate.summary,
  ].join(' '));
  const titleMatched = hasTokenOverlap(reqTitleTokens, candidateTitleTokens);
  if (titleMatched) score += 25;
  breakdown.push({
    label: 'Cargo/area',
    points: titleMatched ? 25 : 0,
    detail: titleMatched
      ? 'Cargo desejado ou resumo profissional conversa com a vaga.'
      : 'Nao ha sinal claro de cargo/area desejada para essa vaga.',
  });

  const reqSkillTokens = tokenize([
    request.description,
    ...(Array.isArray(request.requirements) ? request.requirements : []),
  ].join(' '));
  const candidateSkillTokens = tokenize([
    ...candidate.skills,
    candidate.summary,
    candidate.headline,
    ...candidate.education,
  ].join(' '));
  const reqSet = new Set(reqSkillTokens);
  const overlap = Array.from(new Set(candidateSkillTokens)).filter((token) => reqSet.has(token));
  const skillRatio = reqSet.size > 0 ? Math.min(1, overlap.length / Math.min(reqSet.size, 8)) : 0;
  const skillPoints = Math.round(skillRatio * 25);
  score += skillPoints;
  breakdown.push({
    label: 'Skills',
    points: skillPoints,
    detail: overlap.length > 0
      ? `Sobreposicao detectada: ${overlap.slice(0, 5).join(', ')}.`
      : 'Nao houve sobreposicao relevante de skills/requisitos.',
  });

  const requestCity = normalizeText(request.location_city);
  const requestState = normalizeText(request.location_state);
  const candidateLocations = [
    candidate.city,
    candidate.state,
    ...candidate.otherLocations,
  ].map(normalizeText).filter(Boolean);
  const locationMatched = normalizeText(request.work_model) === 'remoto' ||
    !requestCity && !requestState ||
    (requestCity && candidateLocations.includes(requestCity)) ||
    (requestState && candidateLocations.includes(requestState));
  if (locationMatched) score += 15;
  breakdown.push({
    label: 'Localizacao',
    points: locationMatched ? 15 : 0,
    detail: locationMatched
      ? 'Localizacao ou remoto parece compativel.'
      : 'Localizacao declarada nao bate com a vaga.',
  });

  const requestWorkModel = normalizeWorkMode(text(request.work_model));
  const candidateWorkModes = candidate.workModes.map(normalizeWorkMode);
  const workMatched = !requestWorkModel || candidateWorkModes.length === 0 ||
    candidateWorkModes.includes(requestWorkModel);
  if (workMatched) score += 10;
  breakdown.push({
    label: 'Modelo',
    points: workMatched ? 10 : 0,
    detail: workMatched
      ? 'Modelo de trabalho compativel.'
      : 'Modelo de trabalho nao declarado como preferido.',
  });

  const requestJobType = normalizeJobType(text(request.job_type));
  const candidateJobTypes = candidate.jobTypes.map(normalizeJobType);
  const typeMatched = !requestJobType || candidateJobTypes.length === 0 ||
    candidateJobTypes.includes(requestJobType);
  if (typeMatched) score += 10;
  breakdown.push({
    label: 'Tipo',
    points: typeMatched ? 10 : 0,
    detail: typeMatched
      ? 'Tipo/nivel de vaga compativel.'
      : 'Tipo de vaga nao bate com a preferencia.',
  });

  let readiness = 0;
  if (candidate.completenessScore >= 60) readiness += 8;
  if (candidate.skills.length >= 3) readiness += 3;
  if (candidate.education.length > 0) readiness += 2;
  if (candidate.likes > 0 || candidate.applies > 0) readiness += 2;
  score += readiness;
  breakdown.push({
    label: 'Prontidao',
    points: readiness,
    detail: 'Pontua perfil completo, skills, formacao e atividade no app.',
  });

  return { score: Math.max(0, Math.min(100, score)), breakdown };
}

async function buildCandidateProfiles(supabase: any): Promise<CandidateProfile[]> {
  const { data: users, error } = await supabase
    .from('user_profiles')
    .select('id, name, email, phone, created_at')
    .order('created_at', { ascending: false })
    .limit(5000);
  if (error) throw new AdminHttpError(500, 'candidate_pool_failed', error.message);

  const userIds = (users ?? []).map((row: any) => row.id);
  if (userIds.length === 0) return [];

  const [personalR, skillsR, titlesR, eduR, prefsR, otherLocsR, swipesR, consentsR] = await Promise
    .all([
      supabase.from('profile_personal').select('*').in('user_id', userIds),
      supabase.from('profile_skills').select('user_id, name').in('user_id', userIds),
      supabase.from('profile_desired_titles').select('user_id, title').in('user_id', userIds),
      supabase
        .from('profile_education')
        .select('user_id, institution, degree, profile_education_majors(name)')
        .in('user_id', userIds),
      supabase.from('profile_job_preferences').select('*').in('user_id', userIds),
      supabase.from('profile_other_locations').select('user_id, city, state, country').in(
        'user_id',
        userIds,
      ),
      supabase.from('swipe_actions').select('user_id, action, applied').in('user_id', userIds)
        .limit(100000),
      supabase.from('candidate_data_sharing_consents').select('user_id, status').in(
        'user_id',
        userIds,
      ),
    ]);

  const personal = new Map<string, any>(
    (personalR.data ?? []).map((row: any) => [row.user_id, row]),
  );
  const prefs = new Map<string, any>((prefsR.data ?? []).map((row: any) => [row.user_id, row]));
  const consent = new Map((consentsR.data ?? []).map((row: any) => [row.user_id, row.status]));
  const skills = new Map<string, string[]>();
  const titles = new Map<string, string[]>();
  const education = new Map<string, string[]>();
  const otherLocations = new Map<string, string[]>();
  const activity = new Map<string, { likes: number; applies: number }>();

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
  for (const row of eduR.data ?? []) {
    const values = education.get(row.user_id) ?? [];
    values.push(text(row.institution));
    values.push(text(row.degree));
    for (const major of row.profile_education_majors ?? []) values.push(text(major.name));
    education.set(row.user_id, values.filter(Boolean));
  }
  for (const row of otherLocsR.data ?? []) {
    const values = otherLocations.get(row.user_id) ?? [];
    values.push(text(row.city));
    values.push(text(row.state));
    values.push(text(row.country));
    otherLocations.set(row.user_id, values.filter(Boolean));
  }
  for (const row of swipesR.data ?? []) {
    const current = activity.get(row.user_id) ?? { likes: 0, applies: 0 };
    if (row.action === 'liked') current.likes++;
    if (row.applied === true) current.applies++;
    activity.set(row.user_id, current);
  }

  return (users ?? []).map((user: any) => {
    const p = personal.get(user.id);
    const pref = prefs.get(user.id);
    const act = activity.get(user.id) ?? { likes: 0, applies: 0 };
    return {
      userId: user.id,
      name: [p?.first_name, p?.last_name].filter(Boolean).join(' ') || user.name || '',
      email: p?.email || user.email || '',
      phone: p?.phone_number_e164 || p?.phone_number || user.phone || '',
      city: p?.location_city ?? '',
      state: p?.location_state ?? '',
      headline: p?.headline ?? '',
      summary: p?.summary ?? '',
      completenessScore: p?.completeness_score ?? 0,
      skills: skills.get(user.id) ?? [],
      desiredTitles: titles.get(user.id) ?? [],
      education: education.get(user.id) ?? [],
      workModes: Array.isArray(pref?.work_mode) ? pref.work_mode : [],
      jobTypes: Array.isArray(pref?.job_types) ? pref.job_types : [],
      otherLocations: otherLocations.get(user.id) ?? [],
      likes: act.likes,
      applies: act.applies,
      consentStatus: consent.get(user.id) ?? 'not_asked',
      createdAt: user.created_at,
    };
  });
}

async function requestPayloadFromInput(
  supabase: any,
  input: CandidateListsRequest['request'],
  adminEmail: string,
) {
  if (!input) {
    throw new AdminHttpError(400, 'missing_request', 'Missing candidate list request payload');
  }
  let job: any = null;
  if (input.sourceJobId) {
    const { data, error } = await supabase
      .from('jobs')
      .select('*')
      .eq('id', input.sourceJobId)
      .maybeSingle();
    if (error) throw new AdminHttpError(500, 'source_job_failed', error.message);
    if (!data) throw new AdminHttpError(404, 'source_job_not_found', 'Source job not found');
    job = data;
  }
  const title = text(input.title) || text(job?.title);
  if (!title) throw new AdminHttpError(400, 'missing_title', 'Candidate list title is required');

  return {
    client_id: input.clientId ?? null,
    source_job_id: input.sourceJobId ?? null,
    title,
    area: input.area ?? job?.area ?? null,
    description: input.description ?? job?.description ?? null,
    requirements: input.requirements ?? job?.requirements ?? [],
    location_city: input.locationCity ?? job?.location_city ?? null,
    location_state: input.locationState ?? job?.location_state ?? null,
    work_model: input.workModel ?? job?.work_model ?? null,
    job_type: input.jobType ?? job?.job_type ?? null,
    min_score: input.minScore ?? 60,
    created_by: adminEmail,
  };
}

async function loadRequest(supabase: any, requestId: string) {
  const { data, error } = await supabase
    .from('candidate_list_requests')
    .select('*, employer_clients(*)')
    .eq('id', requestId)
    .maybeSingle();
  if (error) throw new AdminHttpError(500, 'request_load_failed', error.message);
  if (!data) throw new AdminHttpError(404, 'request_not_found', 'Candidate list request not found');
  return data;
}

async function loadItems(supabase: any, requestId: string) {
  const { data: items, error } = await supabase
    .from('candidate_list_items')
    .select('*')
    .eq('request_id', requestId)
    .order('rank', { ascending: true })
    .limit(500);
  if (error) throw new AdminHttpError(500, 'items_load_failed', error.message);

  const userIds = (items ?? []).map((row: any) => row.user_id);
  const profiles = new Map(
    (await buildCandidateProfiles(supabase))
      .filter((profile) => userIds.includes(profile.userId))
      .map((profile) => [profile.userId, profile]),
  );

  return (items ?? []).map((item: any) => {
    const profile = profiles.get(item.user_id);
    return {
      id: item.id,
      userId: item.user_id,
      rank: item.rank,
      score: item.score,
      scoreBreakdown: item.score_breakdown,
      status: item.status,
      notes: item.notes,
      exportable: profile?.consentStatus === 'granted',
      candidate: profile
        ? {
          name: maskName(profile.name),
          email: maskEmail(profile.email),
          city: profile.city,
          state: profile.state,
          headline: profile.headline,
          skills: profile.skills.slice(0, 10),
          desiredTitles: profile.desiredTitles.slice(0, 8),
          consentStatus: profile.consentStatus,
        }
        : null,
    };
  });
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: adminCorsHeaders });

  try {
    const ctx = await requireAdmin(req);
    const body = await readJson<CandidateListsRequest>(req);
    const action = body.action ?? 'list';
    const supabase = ctx.supabase;

    if (action === 'create') {
      const payload = await requestPayloadFromInput(supabase, body.request, ctx.email);
      const { data, error } = await supabase
        .from('candidate_list_requests')
        .insert(payload)
        .select('*, employer_clients(*)')
        .single();
      if (error) {
        return jsonResponse({ error: 'request_create_failed', message: error.message }, 500);
      }
      await audit(ctx, req, {
        action: 'admin_candidate_list_created',
        entityType: 'candidate_list_request',
        entityId: data.id,
      });
      return jsonResponse({ request: data }, 201);
    }

    if (action === 'generate') {
      if (!body.id) return jsonResponse({ error: 'missing_id' }, 400);
      const requestRow = await loadRequest(supabase, body.id);
      const profiles = await buildCandidateProfiles(supabase);
      const scored = profiles
        .map((profile) => {
          const result = scoreCandidate(requestRow, profile);
          return { profile, ...result };
        })
        .filter((item) => item.score >= requestRow.min_score)
        .sort((a, b) => b.score - a.score)
        .slice(0, 100);

      await supabase.from('candidate_list_items').delete().eq('request_id', body.id);
      if (scored.length > 0) {
        const rows = scored.map((item, index) => ({
          request_id: body.id,
          user_id: item.profile.userId,
          score: item.score,
          rank: index + 1,
          score_breakdown: item.breakdown,
          status: 'pending',
        }));
        const { error } = await supabase.from('candidate_list_items').insert(rows);
        if (error) {
          return jsonResponse({ error: 'ranking_insert_failed', message: error.message }, 500);
        }
      }
      await supabase
        .from('candidate_list_requests')
        .update({ status: 'review' })
        .eq('id', body.id);
      await audit(ctx, req, {
        action: 'admin_candidate_list_generated',
        entityType: 'candidate_list_request',
        entityId: body.id,
        metadata: { candidates: scored.length },
      });
      return jsonResponse({ count: scored.length, items: await loadItems(supabase, body.id) });
    }

    if (action === 'update_item') {
      if (!body.itemId || !body.item) return jsonResponse({ error: 'missing_item_payload' }, 400);
      const payload: Record<string, unknown> = {};
      if (body.item.status) payload.status = body.item.status;
      if (body.item.notes !== undefined) payload.notes = body.item.notes;
      const { data, error } = await supabase
        .from('candidate_list_items')
        .update(payload)
        .eq('id', body.itemId)
        .select()
        .single();
      if (error) return jsonResponse({ error: 'item_update_failed', message: error.message }, 500);
      await audit(ctx, req, {
        action: 'admin_candidate_list_item_updated',
        entityType: 'candidate_list_item',
        entityId: body.itemId,
        metadata: payload,
      });
      return jsonResponse({ item: data });
    }

    if (action === 'export') {
      if (ctx.role !== 'owner') {
        throw new AdminHttpError(403, 'owner_required', 'Only owner admins can export');
      }
      if (!body.id) return jsonResponse({ error: 'missing_id' }, 400);
      const items = await loadItems(supabase, body.id);
      const approved = items.filter((item: any) => item.status === 'approved' && item.exportable);
      if (approved.length === 0) {
        return jsonResponse({
          error: 'no_exportable_candidates',
          message: 'No approved candidates with granted consent',
        }, 400);
      }

      const profiles = new Map(
        (await buildCandidateProfiles(supabase)).map((profile) => [profile.userId, profile]),
      );
      const rows = approved.map((item: any) => profiles.get(item.userId)).filter(
        Boolean,
      ) as CandidateProfile[];
      const headers = ['nome', 'email', 'telefone', 'cidade', 'estado', 'headline', 'skills'];
      const csv = [
        headers.map(csvEscape).join(','),
        ...rows.map((profile) =>
          [
            profile.name,
            profile.email,
            profile.phone,
            profile.city,
            profile.state,
            profile.headline,
            profile.skills.join('; '),
          ].map(csvEscape).join(',')
        ),
      ].join('\n');

      const { data: exportRow, error } = await supabase
        .from('candidate_list_exports')
        .insert({
          request_id: body.id,
          exported_by: ctx.email,
          format: 'csv',
          exported_fields: headers,
          candidate_count: rows.length,
        })
        .select()
        .single();
      if (error) return jsonResponse({ error: 'export_log_failed', message: error.message }, 500);

      await supabase
        .from('candidate_list_items')
        .update({ status: 'exported' })
        .in('id', approved.map((item: any) => item.id));
      await supabase
        .from('candidate_list_requests')
        .update({ status: 'exported' })
        .eq('id', body.id);
      await audit(ctx, req, {
        action: 'admin_candidate_list_exported',
        entityType: 'candidate_list_request',
        entityId: body.id,
        metadata: { count: rows.length, export_id: exportRow.id },
      });

      return jsonResponse({
        filename: `stage-candidate-list-${body.id}.csv`,
        count: rows.length,
        csv,
      });
    }

    if (action === 'detail') {
      if (!body.id) return jsonResponse({ error: 'missing_id' }, 400);
      const requestRow = await loadRequest(supabase, body.id);
      await audit(ctx, req, {
        action: 'admin_candidate_list_viewed',
        entityType: 'candidate_list_request',
        entityId: body.id,
      });
      return jsonResponse({ request: requestRow, items: await loadItems(supabase, body.id) });
    }

    const { page, pageSize } = parsePagination(body);
    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;
    const { data, error, count } = await supabase
      .from('candidate_list_requests')
      .select('*, employer_clients(*)', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (error) return jsonResponse({ error: 'requests_list_failed', message: error.message }, 500);
    await audit(ctx, req, {
      action: 'admin_candidate_lists_listed',
      entityType: 'candidate_list_request',
    });
    return jsonResponse({ requests: data ?? [], page, pageSize, total: count ?? 0 });
  } catch (error) {
    return errorResponse(error);
  }
});
