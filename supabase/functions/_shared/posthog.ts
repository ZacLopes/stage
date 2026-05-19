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
