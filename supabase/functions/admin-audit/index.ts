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

interface AuditRequest {
  page?: number;
  pageSize?: number;
  action?: string;
  adminEmail?: string;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: adminCorsHeaders });

  try {
    const ctx = await requireAdmin(req, { ownerOnly: true });
    const body = await readJson<AuditRequest>(req);
    const { page, pageSize } = parsePagination(body);
    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;

    let query = ctx.supabase
      .from('admin_audit_log')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (body.action?.trim()) query = query.eq('action', body.action.trim());
    if (body.adminEmail?.trim()) query = query.eq('admin_email', body.adminEmail.trim());

    const { data, error, count } = await query;
    if (error) return jsonResponse({ error: 'audit_list_failed', message: error.message }, 500);
    await audit(ctx, req, { action: 'admin_audit_viewed', entityType: 'admin_audit_log' });
    return jsonResponse({
      entries: data ?? [],
      page,
      pageSize,
      total: count ?? 0,
    });
  } catch (error) {
    return errorResponse(error);
  }
});
