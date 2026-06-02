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

interface ClientsRequest {
  action?: 'list' | 'create' | 'update' | 'archive';
  id?: string;
  page?: number;
  pageSize?: number;
  search?: string;
  client?: {
    name?: string;
    website?: string | null;
    contactName?: string | null;
    contactEmail?: string | null;
    status?: 'prospect' | 'active' | 'paused' | 'archived';
    notes?: string | null;
  };
}

function mapClient(row: any) {
  return {
    id: row.id,
    name: row.name,
    website: row.website,
    contactName: row.contact_name,
    contactEmail: row.contact_email,
    status: row.status,
    notes: row.notes,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function clientPayload(body: ClientsRequest, createdBy?: string) {
  const input = body.client ?? {};
  const payload: Record<string, unknown> = {};
  if (input.name !== undefined) payload.name = input.name.trim();
  if (input.website !== undefined) payload.website = input.website;
  if (input.contactName !== undefined) payload.contact_name = input.contactName;
  if (input.contactEmail !== undefined) payload.contact_email = input.contactEmail;
  if (input.status !== undefined) payload.status = input.status;
  if (input.notes !== undefined) payload.notes = input.notes;
  if (createdBy) payload.created_by = createdBy;
  return payload;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: adminCorsHeaders });

  try {
    const ctx = await requireAdmin(req);
    const body = await readJson<ClientsRequest>(req);
    const action = body.action ?? 'list';
    const supabase = ctx.supabase;

    if (action === 'create') {
      const payload = clientPayload(body, ctx.email);
      if (!payload.name) return jsonResponse({ error: 'missing_name' }, 400);
      const { data, error } = await supabase
        .from('employer_clients')
        .insert(payload)
        .select()
        .single();
      if (error) {
        return jsonResponse({ error: 'client_create_failed', message: error.message }, 500);
      }
      await audit(ctx, req, {
        action: 'admin_client_created',
        entityType: 'employer_client',
        entityId: data.id,
      });
      return jsonResponse({ client: mapClient(data) }, 201);
    }

    if (action === 'update') {
      if (!body.id) return jsonResponse({ error: 'missing_id' }, 400);
      const payload = clientPayload(body);
      const { data, error } = await supabase
        .from('employer_clients')
        .update(payload)
        .eq('id', body.id)
        .select()
        .single();
      if (error) {
        return jsonResponse({ error: 'client_update_failed', message: error.message }, 500);
      }
      await audit(ctx, req, {
        action: 'admin_client_updated',
        entityType: 'employer_client',
        entityId: body.id,
      });
      return jsonResponse({ client: mapClient(data) });
    }

    if (action === 'archive') {
      if (!body.id) return jsonResponse({ error: 'missing_id' }, 400);
      const { data, error } = await supabase
        .from('employer_clients')
        .update({ status: 'archived' })
        .eq('id', body.id)
        .select()
        .single();
      if (error) {
        return jsonResponse({ error: 'client_archive_failed', message: error.message }, 500);
      }
      await audit(ctx, req, {
        action: 'admin_client_archived',
        entityType: 'employer_client',
        entityId: body.id,
      });
      return jsonResponse({ client: mapClient(data) });
    }

    const { page, pageSize } = parsePagination(body);
    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;
    let query = supabase
      .from('employer_clients')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (body.search?.trim()) {
      const safe = body.search.trim().replaceAll(',', ' ').slice(0, 80);
      query = query.or(
        `name.ilike.%${safe}%,contact_email.ilike.%${safe}%,contact_name.ilike.%${safe}%`,
      );
    }
    const { data, error, count } = await query;
    if (error) return jsonResponse({ error: 'client_list_failed', message: error.message }, 500);
    await audit(ctx, req, { action: 'admin_clients_listed', entityType: 'employer_client' });
    return jsonResponse({
      clients: (data ?? []).map(mapClient),
      page,
      pageSize,
      total: count ?? 0,
    });
  } catch (error) {
    return errorResponse(error);
  }
});
