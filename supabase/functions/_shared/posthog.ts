// PostHog LLM Analytics helper para Edge Functions Supabase (Deno).
//
// Por quê: pré-fix, 0 eventos $ai_* eram capturados apesar de 8+ Edge
// Functions usarem GPT-4o/4o-mini. Sem isso a equipe não tinha visibilidade
// de custo IA semanal, qual feature dominava gasto, cache hit rate, nem
// taxa de erro por modelo.
//
// Como usar (chamar uma vez ao redor de cada fetch da OpenAI):
//
//   import { trackAIGeneration } from '../_shared/posthog.ts';
//
//   const start = Date.now();
//   const response = await fetch('https://api.openai.com/v1/chat/completions', {...});
//   const data = await response.json();
//
//   // Fire-and-forget — não bloquear a resposta ao usuário.
//   trackAIGeneration({
//     userId: user.id,
//     generationType: 'cv_adaptation',
//     model: 'gpt-4o-mini',
//     inputTokens: data.usage?.prompt_tokens ?? 0,
//     outputTokens: data.usage?.completion_tokens ?? 0,
//     latencyMs: Date.now() - start,
//     isError: !response.ok,
//     cached: false,
//   }).catch(() => {});
//
// Requer env vars POSTHOG_API_KEY (project key, não personal) e opcional
// POSTHOG_HOST (default https://us.i.posthog.com). Configure via:
//   supabase secrets set POSTHOG_API_KEY=phc_xxx
//
// Sem POSTHOG_API_KEY, todas as chamadas viram no-op silencioso —
// não derruba a function nem o user.

const POSTHOG_HOST =
  Deno.env.get('POSTHOG_HOST') ?? 'https://us.i.posthog.com';
const POSTHOG_API_KEY = Deno.env.get('POSTHOG_API_KEY');

/// Preços por modelo em USD por milhão de tokens (input / output).
/// Atualizado em 2026-05. Quando ajustar preço da OpenAI, mexer aqui.
const MODEL_PRICING: Record<string, { input: number; output: number }> = {
  'gpt-4o': { input: 2.5, output: 10.0 },
  'gpt-4o-2024-08-06': { input: 2.5, output: 10.0 },
  'gpt-4o-mini': { input: 0.15, output: 0.6 },
  'gpt-4o-mini-2024-07-18': { input: 0.15, output: 0.6 },
};

function calculateCostUsd(
  model: string,
  inputTokens: number,
  outputTokens: number,
): number {
  const price = MODEL_PRICING[model];
  if (!price) return 0;
  return (
    (inputTokens / 1_000_000) * price.input +
    (outputTokens / 1_000_000) * price.output
  );
}

interface TrackAIGenerationParams {
  /// User Supabase ID. Vira o distinct_id no PostHog — sem isso o evento fica
  /// anônimo e não dá pra correlacionar com sessão do app.
  userId: string;

  /// Nome semântico da feature, em snake_case. Ex.: 'cv_adaptation',
  /// 'match_analysis', 'bullet_generation'. Usado pra agrupar custo no
  /// dashboard por feature.
  generationType: string;

  /// Nome do modelo OpenAI (ex.: 'gpt-4o-mini'). Calcula custo via tabela.
  model: string;

  inputTokens: number;
  outputTokens: number;
  latencyMs: number;

  /// `true` se a chamada à OpenAI falhou (response.ok=false ou exception).
  /// Distingue regressão de modelo vs. ruído de produção.
  isError?: boolean;

  /// `true` se a resposta veio de cache local (ex.: adapt-resume-to-job tem
  /// cache por hash de profile). Permite calcular cache hit rate no dashboard.
  cached?: boolean;

  /// `true` se o rate limit interno (por user/dia) recusou a chamada antes
  /// de chegar na OpenAI. Quando true, model/tokens ficam zero.
  rateLimited?: boolean;

  /// Trace ID opcional — agrupa múltiplas chamadas relacionadas (ex.: várias
  /// gerações no mesmo "adapt CV"). Se omitido, cada chamada vira trace só.
  traceId?: string;

  /// Properties extras opcionais. Não usar pra dado sensível (vai pra PostHog).
  extra?: Record<string, unknown>;
}

/// Posta um evento `$ai_generation` no PostHog seguindo o formato esperado
/// pelo produto LLM Analytics. Resolve sem erro mesmo se POSTHOG_API_KEY
/// não estiver setada (no-op) ou a request falhar (log + return).
export async function trackAIGeneration(
  params: TrackAIGenerationParams,
): Promise<void> {
  if (!POSTHOG_API_KEY) return;

  const costUsd = params.rateLimited
    ? 0
    : calculateCostUsd(params.model, params.inputTokens, params.outputTokens);

  const body = {
    api_key: POSTHOG_API_KEY,
    event: '$ai_generation',
    distinct_id: params.userId,
    timestamp: new Date().toISOString(),
    properties: {
      // Padrão PostHog LLM Analytics — não renomear estes.
      $ai_model: params.model,
      $ai_provider: 'openai',
      $ai_input_tokens: params.inputTokens,
      $ai_output_tokens: params.outputTokens,
      $ai_total_cost_usd: costUsd,
      $ai_latency: params.latencyMs / 1000, // segundos
      $ai_is_error: params.isError === true,
      $ai_cache_hit: params.cached === true,
      ...(params.traceId ? { $ai_trace_id: params.traceId } : {}),
      // Properties custom — usar pra segmentação no dashboard.
      generation_type: params.generationType,
      rate_limited: params.rateLimited === true,
      source: 'edge_function',
      ...(params.extra ?? {}),
    },
  };

  try {
    await fetch(`${POSTHOG_HOST}/capture/`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch (e) {
    // Nunca propagar — analytics não pode derrubar Edge Function.
    console.error('[PostHog] trackAIGeneration failed:', e);
  }
}

interface CaptureEventParams {
  /// Evento (snake_case). Ex.: 'job_sync_completed', 'notifications_digest_sent'.
  event: string;

  /// Distinct ID. Pra eventos de cron sem user, usar 'cron' ou o nome da
  /// função ('sync-jobs-apify') — não fica anônimo no PostHog.
  distinctId: string;

  /// Properties arbitrárias. Vão direto pro PostHog — não incluir dado sensível.
  properties?: Record<string, unknown>;
}

/// Captura genérico pra eventos que não seguem o formato $ai_generation.
/// Usado por crons (job_sync_completed, notifications_digest_sent) e qualquer
/// outro evento de Edge Function que não seja chamada de LLM.
///
/// Fire-and-forget. Sem POSTHOG_API_KEY vira no-op. Falhas só logam.
export async function captureEvent(params: CaptureEventParams): Promise<void> {
  if (!POSTHOG_API_KEY) return;

  const body = {
    api_key: POSTHOG_API_KEY,
    event: params.event,
    distinct_id: params.distinctId,
    timestamp: new Date().toISOString(),
    properties: {
      source: 'edge_function',
      ...(params.properties ?? {}),
    },
  };

  try {
    await fetch(`${POSTHOG_HOST}/capture/`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch (e) {
    console.error('[PostHog] captureEvent failed:', e);
  }
}

// ════════════════════════════════════════════════════════════════════
// Catálogo server-side (mirror parcial de lib/services/analytics_events.dart)
// pra eventos B.7 (backend/edge/LLM) do plano v2.
// ════════════════════════════════════════════════════════════════════

export const EV_EDGE_FUNCTION_INVOKED = 'edge_function_invoked';
export const EV_LLM_CALL_FAILED = 'llm_call_failed';
export const EV_LLM_RESPONSE_ANTI_INVENTION_FLAGGED =
  'llm_response_anti_invention_flagged';
export const EV_DB_QUERY_SLOW = 'db_query_slow';
export const EV_APIFY_SYNC_STARTED = 'apify_sync_started';
export const EV_APIFY_SYNC_COMPLETED = 'apify_sync_completed';
export const EV_APIFY_SYNC_FAILED = 'apify_sync_failed';
export const EV_DAILY_REPORT_SENT = 'daily_report_sent';
export const EV_PUSH_SEND_INITIATED = 'push_send_initiated';
export const EV_PUSH_SEND_COMPLETED = 'push_send_completed';
export const EV_WEBHOOK_RECEIVED = 'webhook_received';
export const EV_RATE_LIMIT_HIT = 'rate_limit_hit';
export const EV_PGCRON_JOB_EXECUTED = 'pgcron_job_executed';

// ════════════════════════════════════════════════════════════════════
// Typed helpers — preferir estes sobre captureEvent cru pra B.7.
// Cada helper enche as properties canônicas e marca `source: edge_function`.
// ════════════════════════════════════════════════════════════════════

interface TrackEdgeInvokedParams {
  functionName: string;
  durationMs: number;
  status: 'ok' | 'error' | 'unauthorized' | 'bad_request' | 'rate_limited';
  /// Distinct ID do user logado quando disponível; senão usar functionName.
  distinctId: string;
  /// Código de erro pequeno se status != ok (ex.: 'no_input', 'openai_500').
  errorCode?: string;
  /// Tamanho do body de resposta em bytes, opcional.
  responseSizeBytes?: number;
  /// Versão do prompt/lógica se aplicável (ex.: 'adapt_v2_15').
  promptVersion?: string;
  extra?: Record<string, unknown>;
}

/// Invocação de Edge Function — emite no final do handler com status + duração.
/// É o "request log" estruturado pra PostHog.
export function trackEdgeFunctionInvoked(
  params: TrackEdgeInvokedParams,
): Promise<void> {
  return captureEvent({
    event: EV_EDGE_FUNCTION_INVOKED,
    distinctId: params.distinctId,
    properties: {
      function: params.functionName,
      duration_ms: params.durationMs,
      status: params.status,
      ...(params.errorCode ? { error_code: params.errorCode } : {}),
      ...(params.responseSizeBytes
        ? { response_size_bytes: params.responseSizeBytes }
        : {}),
      ...(params.promptVersion
        ? { prompt_version: params.promptVersion }
        : {}),
      ...(params.extra ?? {}),
    },
  });
}

interface TrackLlmCallFailedParams {
  functionName: string;
  model: string;
  errorCode: string;
  /// Mensagem curta de erro (truncar pra <500 chars antes de chamar).
  errorMessage?: string;
  retryCount?: number;
  distinctId: string;
  promptVersion?: string;
}

/// Falha na chamada LLM (HTTP != 2xx ou exception). Distinto do
/// $ai_generation com isError=true: este evento é dedicado pra alertas
/// e agrupamento de falhas, sem custo/tokens (que ficam 0).
export function trackLlmCallFailed(
  params: TrackLlmCallFailedParams,
): Promise<void> {
  return captureEvent({
    event: EV_LLM_CALL_FAILED,
    distinctId: params.distinctId,
    properties: {
      function: params.functionName,
      model: params.model,
      error_code: params.errorCode,
      ...(params.errorMessage
        ? { error_message: params.errorMessage.slice(0, 500) }
        : {}),
      ...(params.retryCount !== undefined
        ? { retry_count: params.retryCount }
        : {}),
      ...(params.promptVersion
        ? { prompt_version: params.promptVersion }
        : {}),
    },
  });
}

interface TrackAntiInventionFlaggedParams {
  functionName: string;
  model: string;
  /// Campos onde o validador detectou invenção (ex.: ['experiences.0.bullets.2', 'skills']).
  fieldsFlagged: string[];
  distinctId: string;
  promptVersion?: string;
}

/// Validador semântico detectou invenção da IA (campo no output que não tinha
/// base no input). Sinal CRÍTICO de qualidade IA — alerta no dashboard.
export function trackLlmResponseAntiInventionFlagged(
  params: TrackAntiInventionFlaggedParams,
): Promise<void> {
  return captureEvent({
    event: EV_LLM_RESPONSE_ANTI_INVENTION_FLAGGED,
    distinctId: params.distinctId,
    properties: {
      function: params.functionName,
      model: params.model,
      fields_flagged: params.fieldsFlagged,
      fields_count: params.fieldsFlagged.length,
      ...(params.promptVersion
        ? { prompt_version: params.promptVersion }
        : {}),
    },
  });
}

interface GroupIdentifyParams {
  /// Tipo do group conforme A.14 do plano v2. Valores canônicos:
  /// 'company', 'university', 'ad_campaign', 'job', 'phase', 'prompt_version'.
  groupType: string;
  /// Identificador único do group (ex.: company_id no Supabase, job_id, etc).
  groupKey: string;
  /// Properties que descrevem o group. Vão direto pro PostHog Groups —
  /// não incluir PII de usuários individuais.
  groupProperties: Record<string, unknown>;
}

/// Server-side $groupidentify. PostHog auto-registra novo `groupType` ao
/// receber o primeiro evento desse tipo. Use ANTES de emitir eventos
/// associados àquele group pra garantir que as properties estejam
/// disponíveis na agregação. Idempotente — re-identifies sobrescrevem
/// properties (PATCH-like via $set).
export async function groupIdentify(params: GroupIdentifyParams): Promise<void> {
  if (!POSTHOG_API_KEY) return;

  const body = {
    api_key: POSTHOG_API_KEY,
    event: '$groupidentify',
    distinct_id: `edge_function:${params.groupType}_identify`,
    timestamp: new Date().toISOString(),
    properties: {
      $group_type: params.groupType,
      $group_key: params.groupKey,
      $group_set: params.groupProperties,
    },
  };

  try {
    await fetch(`${POSTHOG_HOST}/capture/`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch (e) {
    console.error('[PostHog] groupIdentify failed:', e);
  }
}

interface TrackRateLimitHitParams {
  /// Endpoint ou nome lógico do limit (ex.: 'adapt_per_user_daily').
  limitType: string;
  /// Distinct ID do user que bateu o limit.
  distinctId: string;
  functionName: string;
  /// Limite numérico se disponível.
  limit?: number;
  extra?: Record<string, unknown>;
}

/// Rate limiter recusou a chamada antes de chegar no backend pesado.
export function trackRateLimitHit(
  params: TrackRateLimitHitParams,
): Promise<void> {
  return captureEvent({
    event: EV_RATE_LIMIT_HIT,
    distinctId: params.distinctId,
    properties: {
      function: params.functionName,
      limit_type: params.limitType,
      ...(params.limit !== undefined ? { limit: params.limit } : {}),
      ...(params.extra ?? {}),
    },
  });
}

// ════════════════════════════════════════════════════════════════════
// Wrapper de handler — auto-instrumenta `edge_function_invoked` em
// success e error path. Uso:
//
//   serve(withEdgeAnalytics('my-func', async (req) => {
//     // ... seu handler
//     return jsonResponse({ ok: true });
//   }));
//
// Captura: duração total, status semântico, error_code se exception,
// status code HTTP. Distinct ID = `edge_function:<fn-name>` (cron-like)
// por default; pra ter user.id real, chamar trackEdgeFunctionInvoked
// manualmente DENTRO do handler quando tiver auth resolvido.
// ════════════════════════════════════════════════════════════════════

type EdgeHandler = (req: Request) => Promise<Response>;

/// Mapeia HTTP status pra status semântico do edge_function_invoked.
function statusFromHttpCode(
  code: number,
): 'ok' | 'error' | 'unauthorized' | 'bad_request' | 'rate_limited' {
  if (code >= 200 && code < 300) return 'ok';
  if (code === 401 || code === 403) return 'unauthorized';
  if (code === 400) return 'bad_request';
  if (code === 429) return 'rate_limited';
  return 'error';
}

/// Auto-wrap pra handlers de edge function. Emite `edge_function_invoked`
/// no final, com fallback em catch pra exceptions. NÃO substitui chamadas
/// manuais (use ambas quando precisar enrich com user.id).
export function withEdgeAnalytics(
  functionName: string,
  handler: EdgeHandler,
): EdgeHandler {
  return async (req) => {
    if (req.method === 'OPTIONS') {
      // CORS pre-flight — não conta como invocação de produto.
      return handler(req);
    }
    const fnStart = Date.now();
    try {
      const response = await handler(req);
      const status = statusFromHttpCode(response.status);
      trackEdgeFunctionInvoked({
        functionName,
        distinctId: `edge_function:${functionName}`,
        durationMs: Date.now() - fnStart,
        status,
        ...(status === 'ok' ? {} : { errorCode: `http_${response.status}` }),
      }).catch(() => {});
      return response;
    } catch (err) {
      const msg = (err as Error).message || 'unknown';
      const isTimeout = msg.includes('AbortError') || msg.includes('aborted');
      trackEdgeFunctionInvoked({
        functionName,
        distinctId: `edge_function:${functionName}`,
        durationMs: Date.now() - fnStart,
        status: 'error',
        errorCode: isTimeout ? 'timeout' : 'unhandled_exception',
        extra: { error_message: msg.slice(0, 300) },
      }).catch(() => {});
      throw err; // propaga pra Supabase Edge runtime tratar
    }
  };
}
