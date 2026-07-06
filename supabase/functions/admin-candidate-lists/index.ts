import { serve } from 'std/http/server';
import {
  adminCorsHeaders,
  AdminHttpError,
  audit,
  csvEscape,
  errorResponse,
  jsonResponse,
  parsePagination,
  readJson,
  requireAdmin,
} from '../_shared/admin.ts';
import { publicContactEmailOrEmpty } from '../_shared/contact_email.ts';
// Scoring puro do auto-rank (extraído p/ ser testável — index.ts chama serve()
// no top-level e não pode ser importado por deno test). Fase 7 Onda 1.
import { type CandidateProfile, scoreCandidate, text } from './scoring.ts';
import {
  EXPORT_HEADERS,
  exportRowCells,
  isInternalAccount,
  isSyntheticEmail,
  LANG_LEVEL_PT,
} from './export_csv.ts';

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
    // Resultado por candidato entregue (Fase 7 Onda 2 · T-C3).
    outcome?: 'interviewing' | 'interviewed' | 'hired' | 'not_selected' | 'no_response' | null;
    outcomeNote?: string | null;
  };
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

async function buildCandidateProfiles(
  supabase: any,
  restrictUserIds?: string[],
): Promise<CandidateProfile[]> {
  // Quando é pra hidratar itens de uma lista específica (loadItems), buscar SÓ
  // esses user_ids. Sem isso o pool cai no teto de 1000 linhas do PostgREST
  // (ordenado por created_at desc) e candidatos mais antigos somem, virando
  // candidate:null (UUID no nome, consent "not_asked", e nunca exportável).
  // Sem restrição, mantém o pool completo pro 'generate'.
  let poolQuery = supabase
    .from('user_profiles')
    .select('id, name, phone, created_at');
  poolQuery = restrictUserIds && restrictUserIds.length > 0
    ? poolQuery.in('id', restrictUserIds)
    : poolQuery.order('created_at', { ascending: false }).limit(5000);
  const { data: users, error } = await poolQuery;
  if (error) throw new AdminHttpError(500, 'candidate_pool_failed', error.message);

  const userIds = (users ?? []).map((row: any) => row.id);
  if (userIds.length === 0) return [];

  const [
    personalR,
    skillsR,
    titlesR,
    eduR,
    prefsR,
    otherLocsR,
    swipesR,
    consentsR,
    langsR,
    resumesR,
  ] = await Promise.all([
    supabase.from('profile_personal').select('*').in('user_id', userIds),
    supabase.from('profile_skills').select('user_id, name').in('user_id', userIds),
    supabase.from('profile_desired_titles').select('user_id, title').in('user_id', userIds),
    supabase
      .from('profile_education')
      .select(
        'user_id, institution, degree, current_semester, education_level, education_status, end_date, profile_education_majors(name)',
      )
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
    supabase.from('profile_languages').select('user_id, name, proficiency').in('user_id', userIds),
    // CSV v2 (Fase 7 Onda 2): link do CV. order desc → 1ª por user = mais recente.
    supabase.from('saved_resumes').select('user_id, file_path, created_at').in('user_id', userIds)
      .order('created_at', { ascending: false }),
  ]);

  const personal = new Map<string, any>(
    (personalR.data ?? []).map((row: any) => [row.user_id, row]),
  );
  const prefs = new Map<string, any>((prefsR.data ?? []).map((row: any) => [row.user_id, row]));
  const consent = new Map((consentsR.data ?? []).map((row: any) => [row.user_id, row.status]));
  const skills = new Map<string, string[]>();
  const titles = new Map<string, string[]>();
  const education = new Map<string, string[]>();
  const eduStructured = new Map<string, any>();
  const languages = new Map<string, string>();
  const cvPaths = new Map<string, string>();
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
    // Estruturado p/ o CSV v2: prefere a formação de faculdade; senão a 1ª vista.
    const existing = eduStructured.get(row.user_id);
    const isCollege = row.education_level === 'college';
    if (!existing || (isCollege && existing.level !== 'college')) {
      const major = (row.profile_education_majors ?? [])[0]?.name;
      const gradYear = row.end_date ? Number(String(row.end_date).slice(0, 4)) : NaN;
      eduStructured.set(row.user_id, {
        institution: text(row.institution),
        course: text(major) || text(row.degree),
        semester: row.current_semester ?? null,
        graduation: Number.isFinite(gradYear) ? gradYear : null,
        level: text(row.education_level),
      });
    }
  }
  for (const row of langsR.data ?? []) {
    const level = row.proficiency ? (LANG_LEVEL_PT[row.proficiency] ?? row.proficiency) : '';
    const label = level ? `${row.name} (${level})` : row.name;
    const prev = languages.get(row.user_id) ?? '';
    languages.set(row.user_id, prev ? `${prev}, ${label}` : label);
  }
  for (const row of resumesR.data ?? []) {
    if (!cvPaths.has(row.user_id) && row.file_path) cvPaths.set(row.user_id, row.file_path);
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
    const edu = eduStructured.get(user.id);
    const email = p?.email || user.email || '';
    return {
      userId: user.id,
      name: [p?.first_name, p?.last_name].filter(Boolean).join(' ') || user.name || '',
      email: publicContactEmailOrEmpty(p?.email),
      phone: p?.phone_number_e164 || p?.phone_number || user.phone || '',
      city: p?.location_city ?? '',
      // Cidade só em JP (176 candidatos legacy): entra no COALESCE de
      // Localização (score) e no CSV. profile_job_preferences já é carregado
      // acima (prefsR). Fase 7 Onda 1.
      primaryLocationCity: pref?.primary_location_city ?? '',
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
      // ── CSV v2 (Fase 7 Onda 2) — estruturado p/ o entregável, não p/ o rank ──
      institution: edu?.institution ?? '',
      course: edu?.course ?? '',
      semester: edu?.semester ?? null,
      graduationYear: edu?.graduation ?? null,
      educationLevel: edu?.level ?? '',
      languages: languages.get(user.id) ?? '',
      linkedin: p?.linkedin_url ?? '',
      availability: p?.availability ?? '',
      desiredPosition: pref?.desired_position ?? '',
      cvPath: cvPaths.get(user.id) ?? '',
      isSyntheticEmail: isSyntheticEmail(email),
      isInternal: isInternalAccount(email),
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

  // Fase 7 Onda 2 (T-C2): cliente é obrigatório — sem isso não há rastreabilidade
  // de PARA QUEM a PII foi, nem métrica de recompra por empresa.
  if (!input.clientId) {
    throw new AdminHttpError(
      400,
      'missing_client',
      'Selecione (ou cadastre) uma empresa cliente para criar a lista',
    );
  }

  return {
    client_id: input.clientId,
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
    (await buildCandidateProfiles(supabase, userIds))
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
      outcome: item.outcome ?? null,
      outcomeNote: item.outcome_note ?? null,
      // Fase 7 Onda 2: export IGNORA consent; `exportable` só informa o status
      // (a UI pode exibir), não bloqueia mais o export.
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
      // Fase 7 Onda 2 (T-C3): resultado do candidato entregue à empresa.
      if (body.item.outcome !== undefined) {
        payload.outcome = body.item.outcome;
        payload.outcome_at = body.item.outcome ? new Date().toISOString() : null;
      }
      if (body.item.outcomeNote !== undefined) payload.outcome_note = body.item.outcomeNote;
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
      const requestRow = await loadRequest(supabase, body.id);
      const items = await loadItems(supabase, body.id);
      // Fase 7 Onda 2: o export IGNORA o consent (decisão do fundador — é teste
      // do modelo, não produção comercial). Exporta os itens APROVADOS; exclui
      // apenas a(s) conta(s) de teste interna(s).
      const approved = items.filter((item: any) => item.status === 'approved');

      const profiles = new Map(
        (await buildCandidateProfiles(supabase, approved.map((item: any) => item.userId)))
          .map((profile) => [profile.userId, profile]),
      );
      const exportRows = approved
        .map((item: any) => ({ item, profile: profiles.get(item.userId) as CandidateProfile }))
        .filter((r: any) => r.profile && !r.profile.isInternal);
      if (exportRows.length === 0) {
        return jsonResponse({
          error: 'no_exportable_candidates',
          message: 'Nenhum candidato aprovado para exportar',
        }, 400);
      }

      // Link assinado do CV (bucket `resumes`, expira em 14 dias). Best-effort:
      // sem CV acessível → coluna vazia, não derruba o export.
      const cvUrls = new Map<string, string>();
      await Promise.all(exportRows.map(async (r: any) => {
        if (!r.profile.cvPath) return;
        try {
          const { data } = await supabase.storage
            .from('resumes')
            .createSignedUrl(r.profile.cvPath, 60 * 60 * 24 * 14);
          if (data?.signedUrl) cvUrls.set(r.profile.userId, data.signedUrl);
        } catch (_) { /* ignora — coluna vazia */ }
      }));

      // Delimitador ';' (Excel pt-BR usa ',' como decimal). Cada célula passa por
      // csvEscape (aspas) e os campos de texto do candidato por sanitizeCsvValue
      // (anti-injeção de fórmula) dentro de exportRowCells. CRLF + BOM completam.
      const csv = [
        EXPORT_HEADERS.map(csvEscape).join(';'),
        ...exportRows.map((r: any) =>
          exportRowCells(
            r.profile,
            { score: r.item.score, scoreBreakdown: r.item.scoreBreakdown },
            cvUrls.get(r.profile.userId) ?? '',
          ).map(csvEscape).join(';')
        ),
      ].join('\r\n');

      const { data: exportRow, error } = await supabase
        .from('candidate_list_exports')
        .insert({
          request_id: body.id,
          client_id: requestRow.client_id ?? null,
          exported_by: ctx.email,
          format: 'csv',
          exported_fields: EXPORT_HEADERS,
          candidate_count: exportRows.length,
        })
        .select()
        .single();
      if (error) return jsonResponse({ error: 'export_log_failed', message: error.message }, 500);

      await supabase
        .from('candidate_list_items')
        .update({ status: 'exported' })
        .in('id', exportRows.map((r: any) => r.item.id));
      await supabase
        .from('candidate_list_requests')
        .update({ status: 'exported' })
        .eq('id', body.id);
      await audit(ctx, req, {
        action: 'admin_candidate_list_exported',
        entityType: 'candidate_list_request',
        entityId: body.id,
        metadata: {
          count: exportRows.length,
          export_id: exportRow.id,
          client_id: requestRow.client_id ?? null,
        },
      });

      return jsonResponse({
        filename: `stage-candidate-list-${body.id}.csv`,
        count: exportRows.length,
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
