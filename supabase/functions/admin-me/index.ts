import { serve } from 'std/http/server';
import {
  adminCorsHeaders,
  audit,
  errorResponse,
  jsonResponse,
  requireAdmin,
} from '../_shared/admin.ts';

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: adminCorsHeaders });

  try {
    const ctx = await requireAdmin(req);
    await audit(ctx, req, {
      action: 'admin_me_viewed',
      entityType: 'admin_user',
      entityId: ctx.email,
    });
    return jsonResponse({ email: ctx.email, role: ctx.role });
  } catch (error) {
    return errorResponse(error);
  }
});
