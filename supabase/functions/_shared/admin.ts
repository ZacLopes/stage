import { createClient, type SupabaseClient } from 'supabase';

export const adminCorsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
};

export type AdminRole = 'owner' | 'analyst';

export interface AdminContext {
  email: string;
  role: AdminRole;
  userId: string;
  supabase: SupabaseClient;
}

export class AdminHttpError extends Error {
  status: number;
  code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...adminCorsHeaders, 'Content-Type': 'application/json' },
  });
}

export function errorResponse(error: unknown): Response {
  if (error instanceof AdminHttpError) {
    return jsonResponse({ error: error.code, message: error.message }, error.status);
  }
  console.error('[admin] unexpected error:', error);
  return jsonResponse({ error: 'internal_error', message: 'Unexpected admin function error' }, 500);
}

export async function readJson<T = Record<string, unknown>>(req: Request): Promise<T> {
  if (req.method === 'GET') return {} as T;
  const text = await req.text();
  if (!text.trim()) return {} as T;
  try {
    return JSON.parse(text) as T;
  } catch (_) {
    throw new AdminHttpError(400, 'invalid_json', 'Request body must be valid JSON');
  }
}

export async function requireAdmin(
  req: Request,
  opts: { ownerOnly?: boolean } = {},
): Promise<AdminContext> {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    throw new AdminHttpError(500, 'missing_config', 'Missing Supabase admin configuration');
  }

  const authorization = req.headers.get('Authorization');
  if (!authorization) {
    throw new AdminHttpError(401, 'unauthorized', 'Missing Authorization header');
  }

  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
  });
  const { data, error } = await authClient.auth.getUser();
  if (error || !data.user?.email) {
    throw new AdminHttpError(401, 'unauthorized', 'Invalid or expired Supabase session');
  }

  const email = data.user.email.trim();
  const normalizedEmail = email.toLowerCase();
  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: adminRows, error: adminError } = await serviceClient
    .from('admin_users')
    .select('email, role, is_active')
    .in('email', Array.from(new Set([email, normalizedEmail])));

  if (adminError) {
    console.error('[admin] admin lookup failed:', adminError.message);
    throw new AdminHttpError(500, 'admin_lookup_failed', 'Could not validate admin access');
  }

  const admin = (adminRows ?? []).find((row: { is_active?: boolean }) => row.is_active === true);
  if (!admin) {
    throw new AdminHttpError(403, 'forbidden', 'This account is not an active admin');
  }
  if (opts.ownerOnly && admin.role !== 'owner') {
    throw new AdminHttpError(403, 'owner_required', 'Only owner admins can perform this action');
  }

  return {
    email: String(admin.email),
    role: admin.role as AdminRole,
    userId: data.user.id,
    supabase: serviceClient,
  };
}

export async function audit(
  ctx: AdminContext,
  req: Request,
  params: {
    action: string;
    entityType?: string;
    entityId?: string;
    metadata?: Record<string, unknown>;
  },
): Promise<void> {
  const ip = req.headers.get('cf-connecting-ip') ??
    req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ??
    null;

  const { error } = await ctx.supabase.from('admin_audit_log').insert({
    admin_email: ctx.email,
    action: params.action,
    entity_type: params.entityType ?? null,
    entity_id: params.entityId ?? null,
    metadata: params.metadata ?? {},
    ip_address: ip,
    user_agent: req.headers.get('user-agent'),
  });
  if (error) {
    console.error('[admin] audit insert failed:', error.message);
  }
}

export function parsePagination(
  input: { page?: unknown; pageSize?: unknown },
): { page: number; pageSize: number } {
  const page = Math.max(1, Number(input.page ?? 1) || 1);
  const rawPageSize = Math.max(1, Number(input.pageSize ?? 25) || 25);
  return { page, pageSize: Math.min(rawPageSize, 100) };
}

export function csvEscape(value: unknown): string {
  const text = value == null ? '' : String(value);
  return `"${text.replaceAll('"', '""')}"`;
}

// Neutraliza injeção de fórmula (CSV/Excel): campos controlados pelo candidato
// (nome, headline, skills, resumo…) que começam com = + - @ ou TAB/CR podem
// executar como fórmula no Excel do RH. Prefixa com aspa simples, que o Excel
// trata como "texto literal". NÃO aplicar no telefone (sai como ="..." de
// propósito, pra preservar o + do E.164). Fase 7 Onda 2.
export function sanitizeCsvValue(value: unknown): string {
  const text = value == null ? '' : String(value);
  return /^[=+\-@\t\r]/.test(text) ? `'${text}` : text;
}

export function normalizeText(value: unknown): string {
  return String(value ?? '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim();
}

export function tokenize(value: unknown): string[] {
  const normalized = normalizeText(value).replace(/[^a-z0-9]+/g, ' ');
  return normalized
    .split(/\s+/)
    .map((s) => s.trim())
    .filter((s) => s.length >= 3);
}
