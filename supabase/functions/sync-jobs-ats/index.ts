// Edge Function: sync-jobs-ats
//
// Orquestrador único de todas as fontes ATS com API pública. Cada ATS tem
// seu adapter isolado em `sources/{ats}.ts` exportando `sync(supabase, src)`.
// O contrato está em `sources/types.ts`. Helpers em `../_shared/jobs.ts`.
//
// Fluxo: lista `external_job_sources` ativas (ordenadas por last_synced_at
// ASC NULLS FIRST — quem ficou de fora antes vem primeiro), opcionalmente
// filtra por `body.ats[]`, chama o adapter de cada uma com try/catch, e
// marca jobs stale por source ao final.
//
// Acesso:
// - Header `x-cron-secret: <CRON_SECRET>` (pg_cron) OU
// - Header `Authorization: Bearer <JWT>` (manual via Dashboard/curl)
//
// Body (opcional):
// {
//   "ats": ["greenhouse", "ashby"]   // se omitido, roda todas as ats ativas
// }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  corsHeaders,
  isAuthorized,
  jsonResponse,
  markExpiredJobsInactive,
  markStaleJobsInactive,
  safeJson,
} from "../_shared/jobs.ts";
import { captureEvent, withEdgeAnalytics } from "../_shared/posthog.ts";
import type { SourceAdapter, SourceRow, SyncStats } from "./sources/types.ts";
import * as greenhouse from "./sources/greenhouse.ts";
import * as lever from "./sources/lever.ts";
import * as inhire from "./sources/inhire.ts";

const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Cutoff total: 120s deixa folga ante o limite de 150s do Edge Function. Quem
// ficar de fora será priorizado na próxima run via ORDER BY last_synced_at.
const TOTAL_BUDGET_MS = 120_000;

// Registry: ats string (coluna `external_job_sources.ats`) → adapter
const SOURCE_ADAPTERS: Record<string, { name: string; sync: SourceAdapter }> = {
  greenhouse: { name: greenhouse.SOURCE_NAME, sync: greenhouse.sync },
  lever: { name: lever.SOURCE_NAME, sync: lever.sync },
  inhire: { name: inhire.SOURCE_NAME, sync: inhire.sync },
};

serve(withEdgeAnalytics('sync-jobs-ats', async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!isAuthorized(req, CRON_SECRET)) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  const body = await safeJson<{ ats?: string[] }>(req);
  const atsFilter = Array.isArray(body?.ats) && body!.ats.length > 0
    ? new Set(body!.ats.map((s) => s.toLowerCase()))
    : null;

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const sourcesQuery = supabase
    .from("external_job_sources")
    .select("id, ats, company_slug, display_name")
    .eq("is_active", true)
    .order("last_synced_at", { ascending: true, nullsFirst: true });

  const { data: sourcesRaw, error: srcErr } = await sourcesQuery;
  if (srcErr) return jsonResponse({ error: "list_sources_failed", message: srcErr.message }, 500);

  const sources = (sourcesRaw ?? []).filter((s) => !atsFilter || atsFilter.has(s.ats));

  const startedAt = Date.now();
  const summary: Record<string, SyncStats> = {};
  const sourceNamesSynced = new Set<string>();
  const deferredSources: string[] = [];
  let totalInserted = 0;
  let totalErrors = 0;

  for (const src of sources) {
    const key = `${src.ats}:${src.company_slug}`;

    // Reserva budget — se já estouramos 120s, deixa o resto pra próxima run
    // (priorizada via ORDER BY last_synced_at ASC NULLS FIRST).
    if (Date.now() - startedAt > TOTAL_BUDGET_MS) {
      deferredSources.push(key);
      continue;
    }

    const adapter = SOURCE_ADAPTERS[src.ats];
    let stats: SyncStats;
    if (!adapter) {
      stats = { inserted: 0, skipped: 0, errors: 1 };
      console.error(`No adapter registered for ats="${src.ats}"`);
    } else {
      try {
        stats = await adapter.sync(supabase, src as SourceRow);
        sourceNamesSynced.add(adapter.name);
      } catch (e) {
        console.error(`Unexpected error syncing ${key}:`, (e as Error).message);
        stats = { inserted: 0, skipped: 0, errors: 1 };
      }
    }

    summary[key] = stats;
    totalInserted += stats.inserted;
    totalErrors += stats.errors;
  }

  // Marca stale apenas pra sources que efetivamente rodaram nesta execução,
  // pra não desativar vagas só porque a próxima run vai pegá-las.
  const markedStale: Record<string, number> = {};
  for (const name of sourceNamesSynced) {
    // Silêncio (respeitando prazo) + prazo vencido. Greenhouse e InHire não
    // trazem `deadline`, então o segundo é no-op nelas — está aqui para o dia
    // em que um adapter novo trouxer prazo.
    markedStale[name] = await markStaleJobsInactive(supabase, name, 48);
    markedStale[name] += await markExpiredJobsInactive(supabase, name);
  }

  // Emite 1 evento POR ATS (greenhouse, lever, ...) pra o dashboard fazer
  // breakdown por fonte. Agrega o summary `ats:company_slug` por ats.
  const perAts: Record<string, { inserted: number; errors: number; companies: number }> = {};
  for (const [key, stats] of Object.entries(summary)) {
    const ats = key.split(":")[0];
    if (!perAts[ats]) perAts[ats] = { inserted: 0, errors: 0, companies: 0 };
    perAts[ats].inserted += stats.inserted;
    perAts[ats].errors += stats.errors;
    perAts[ats].companies += 1;
  }
  const totalDurationMs = Date.now() - startedAt;
  const startedAtIso = new Date(startedAt).toISOString();
  await Promise.all(
    Object.entries(perAts).map(async ([ats, stats]) => {
      // Conta vagas REALMENTE novas (INSERT real). `stats.inserted` conta
      // upserts (insert + update de last_seen_at). Query de delta por
      // created_at separa um do outro.
      const { count: trulyNew } = await supabase
        .from("jobs")
        .select("id", { count: "exact", head: true })
        .eq("source", ats)
        .gte("created_at", startedAtIso);

      return captureEvent({
        event: 'job_sync_completed',
        distinctId: 'cron:sync-jobs-ats',
        properties: {
          cron: 'sync-jobs-ats',
          source: `ats_${ats}`,
          new_jobs: trulyNew ?? 0,         // INSERT reais
          upserted_jobs: stats.inserted,    // INSERT + UPDATE (saúde do scraper)
          deactivated_jobs: markedStale[ats] ?? 0,
          errors_count: stats.errors,
          companies_synced: stats.companies,
          duration_ms: totalDurationMs,
          cost_usd: 0, // ATS público — sem custo
          status: stats.errors > 0
            ? (stats.inserted > 0 ? 'partial' : 'failed')
            : 'success',
        },
      }).catch(() => {});
    }),
  );

  return jsonResponse({
    ok: true,
    sources: sources.length,
    processed: Object.keys(summary).length,
    deferred: deferredSources.length,
    deferredSources,
    totalInserted,
    totalErrors,
    markedStale,
    durationMs: Date.now() - startedAt,
    detail: summary,
  });
}));
