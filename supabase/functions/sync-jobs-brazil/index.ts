// Edge Function: sync-jobs-brazil
//
// Roda o actor `viralanalyzer/brazil-jobs-scraper` (Apify) que agrega 5 fontes
// BR (InfoJobs, Vagas.com, Gupy, APInfo, LinkedIn guest). Pra evitar duplicatas
// com o nosso sync-jobs-apify (Gupy exclusivo), aqui sempre EXCLUÍMOS `gupy`
// das sources solicitadas.
//
// Acesso:
// - Header `x-cron-secret: <CRON_SECRET>` (usado pelo pg_cron) OU
// - Header `Authorization: Bearer <JWT do projeto>` (manual via curl/Dashboard)
//
// Body (JSON, opcional):
// {
//   "maxListings": 200,                                    // default 50, hard cap 200
//   "keyword": "estagio",                                  // default "estagio"
//   "sources": "infojobs,vagascom,apinfo,linkedin",        // default todas exceto gupy
//   "state": "São Paulo",                                  // opcional
//   "city": "São Paulo",                                   // opcional
//   "includeDescription": true                             // default true
// }
//
// Variáveis de ambiente (via supabase secrets):
//   APIFY_API_TOKEN
//   CRON_SECRET
//   SUPABASE_URL              (auto-injected)
//   SUPABASE_SERVICE_ROLE_KEY (auto-injected)
//
// Pricing: $0.02/vaga (PPE). maxListings=50 ≈ $1/dia. Hard cap 200 = $4/dia max.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  corsHeaders,
  getOrCreateCompany,
  inferArea,
  inferJobType,
  isAuthorized,
  isCompanyNameBlacklisted,
  isEntryLevel,
  isTalentPoolDescription,
  isTitleBlacklisted,
  jsonResponse,
  markStaleJobsInactive,
  normalizeForDedup,
  parseSalary,
  safeJson,
  stripHtml,
} from "../_shared/jobs.ts";

interface BrazilJob {
  id: string;
  title: string;
  company: string;
  salaryMin?: number | null;
  salaryMax?: number | null;
  salaryFormatted?: string | null;
  currency?: string | null;
  location?: string | null;
  city?: string | null;
  state?: string | null;
  workModality?: "remote" | "hybrid" | "onsite" | null;
  experienceLevel?: string | null;
  education?: string | null;
  employmentType?: string | null;
  descriptionSnippet?: string | null;
  description?: string | null;
  benefits?: string | null;
  tags?: string[] | null;
  datePosted?: string | null;
  source: string; // "InfoJobs" | "Vagas.com" | "Gupy" | "APInfo" | "LinkedIn"
  url?: string | null;
  scrapedAt?: string | null;
}

const APIFY_TOKEN = Deno.env.get("APIFY_API_TOKEN") ?? "";
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const ACTOR_ID = "viralanalyzer/brazil-jobs-scraper";
const APIFY_ACTOR_URL_PART = ACTOR_ID.replace("/", "~");

// Hard cap absoluto pra proteger contra acidente (maxListings=0 = ilimitado no actor!)
const HARD_CAP_LISTINGS = 200;

// O actor só aceita 1 source enum por chamada: "all" | "infojobs" | "vagascom"
// | "gupy" | "apinfo" | "linkedin". Pra cobrir as 4 BR (excluindo Gupy que já
// vem pelo sync-jobs-apify), usamos "all" e filtramos Gupy no loop.
const DEFAULT_SOURCES = "all";

// WORK_MODE_MAP específico do brazil-jobs-scraper (keys em inglês minúsculo).
const WORK_MODE_MAP: Record<string, string> = {
  remote: "remoto",
  hybrid: "hibrido",
  onsite: "presencial",
  "on-site": "presencial",
};

// Source string do actor → source no DB (com prefixo brz_)
function sourceForDb(originalSource: string): string {
  const s = (originalSource ?? "").toLowerCase().trim();
  if (s.includes("infojobs")) return "brz_infojobs";
  if (s.includes("vagas")) return "brz_vagas";
  if (s.includes("apinfo")) return "brz_apinfo";
  if (s.includes("linkedin")) return "brz_linkedin";
  if (s.includes("gupy")) return "brz_gupy"; // não deveria chegar (excluído no input) mas defensivo
  return "brz_other";
}

// ── Apify call ───────────────────────────────────────────────────────────────

async function runActor(input: Record<string, unknown>): Promise<BrazilJob[]> {
  const url = `https://api.apify.com/v2/acts/${APIFY_ACTOR_URL_PART}/run-sync-get-dataset-items?timeout=600&format=json`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${APIFY_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(input),
  });
  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Apify error ${resp.status}: ${errText.slice(0, 500)}`);
  }
  return await resp.json();
}

// ── Dedup ────────────────────────────────────────────────────────────────────

/**
 * Verifica se já existe uma vaga ativa com título normalizado parecido + cidade
 * igual. Heurística: title contém substring + cidade igual + is_active.
 * Tolera falsos negativos (perde algumas dedups), evita falsos positivos.
 */
async function isDuplicate(
  supabase: SupabaseClient,
  title: string,
  city: string | null | undefined,
): Promise<boolean> {
  const titleNorm = normalizeForDedup(title);
  const cityNorm = normalizeForDedup(city);
  if (!titleNorm || titleNorm.length < 8) return false;

  const titleCore = titleNorm.slice(0, 30);

  let query = supabase
    .from("jobs")
    .select("id", { count: "exact", head: true })
    .eq("is_active", true)
    .ilike("title", `%${titleCore}%`);

  if (cityNorm) {
    query = query.ilike("location_city", `%${cityNorm}%`);
  }

  const { count } = await query;
  return (count ?? 0) > 0;
}

// ── Persistência ─────────────────────────────────────────────────────────────

async function upsertBrazilCompany(
  supabase: SupabaseClient,
  name: string,
  source: string,
): Promise<string | null> {
  // Brazil Jobs não fornece logo/website/about por empresa. Usa só o nome.
  const slug = `brz:${normalizeForDedup(name).replace(/\s+/g, "-").slice(0, 60)}`;
  return await getOrCreateCompany(supabase, slug, name, source);
}

async function upsertJob(
  supabase: SupabaseClient,
  job: BrazilJob,
  companyId: string,
): Promise<"inserted" | "error"> {
  const jobType = inferJobType(job.title, job.employmentType);

  const workModel = job.workModality && WORK_MODE_MAP[job.workModality]
    ? WORK_MODE_MAP[job.workModality]
    : "presencial";

  const salaryMin = parseSalary(job.salaryMin);
  const salaryMax = parseSalary(job.salaryMax);

  const rawDesc = job.description || job.descriptionSnippet || "";
  const description = stripHtml(rawDesc).slice(0, 8000);

  const benefits = (job.benefits ?? "")
    .split(/[,;\n•]+/)
    .map((s) => s.trim())
    .filter((s) => s.length > 2 && s.length < 200)
    .slice(0, 20);

  const tags = (job.tags ?? []).filter((t) => t && t.length > 0).slice(0, 10);

  const locationCity = job.city || job.location || (workModel === "remoto" ? "Remoto" : "Brasil");
  const locationState = job.state || "BR";

  const dbSource = sourceForDb(job.source);

  // inferArea aceita (title, contextHints) — concatena descrição + tags como hint
  const areaHints = `${(job.description ?? job.descriptionSnippet ?? "").slice(0, 500)} ${tags.join(" ")}`;

  const payload: Record<string, unknown> = {
    company_id: companyId,
    title: job.title,
    description,
    requirements: tags, // Brazil Jobs não separa requirements estruturalmente — usa tags
    benefits,
    location_city: locationCity,
    location_state: locationState,
    work_model: workModel,
    job_type: jobType,
    area: inferArea(job.title, areaHints),
    is_active: true,
    published_at: job.datePosted || new Date().toISOString(),
    source: dbSource,
    external_id: String(job.id),
    external_url: job.url ?? null,
    last_seen_at: new Date().toISOString(),
    raw_payload: job,
  };

  if (salaryMin != null) payload.salary_min = salaryMin * 100;
  if (salaryMax != null) payload.salary_max = salaryMax * 100;

  const { error } = await supabase
    .from("jobs")
    .upsert(payload, { onConflict: "source,external_id" });

  if (error) {
    console.error(`Job upsert failed for ${job.id} (${job.title}):`, error.message);
    return "error";
  }
  return "inserted";
}

// ── HTTP handler ─────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!isAuthorized(req, CRON_SECRET)) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  if (!APIFY_TOKEN) {
    return jsonResponse({ error: "missing_apify_token", message: "APIFY_API_TOKEN não configurada" }, 500);
  }

  const body = (await safeJson<Record<string, unknown>>(req)) ?? {};

  // Hard cap em 200 — protege contra `maxListings: 0` (ilimitado no actor!).
  const requestedMax = (body.maxListings as number | undefined) ?? 50;
  const maxListings = Math.min(Math.max(1, requestedMax), HARD_CAP_LISTINGS);

  const keyword = (body.keyword as string | undefined) ?? "estagio";
  const sources = (body.sources as string | undefined) ?? DEFAULT_SOURCES;
  const includeDescription = (body.includeDescription as boolean | undefined) ?? true;

  const apifyInput: Record<string, unknown> = {
    keyword,
    sources,
    includeDescription,
    maxListings,
    maxPages: 5,
  };
  if (body.state) apifyInput.state = body.state;
  if (body.city) apifyInput.city = body.city;
  if (body.workModality) apifyInput.workModality = body.workModality;

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const startedAt = Date.now();
  let items: BrazilJob[];
  try {
    items = await runActor(apifyInput);
  } catch (e) {
    return jsonResponse({ error: "apify_failed", message: (e as Error).message }, 502);
  }

  let inserted = 0;
  let errors = 0;
  let skippedNotEntryLevel = 0;
  let skippedTitleBlacklist = 0;
  let skippedCompanyBlacklist = 0;
  let skippedTalentPool = 0;
  let skippedDuplicate = 0;
  let skippedGupy = 0;
  let skippedNoId = 0;
  const companyCache = new Map<string, string>();
  const perSource: Record<string, number> = {};

  for (const job of items) {
    if (!job.id || !job.title || !job.company) {
      skippedNoId++;
      continue;
    }

    if (sourceForDb(job.source) === "brz_gupy") {
      skippedGupy++;
      continue;
    }

    if (!isEntryLevel(job.title, job.experienceLevel)) {
      skippedNotEntryLevel++;
      continue;
    }
    if (isTitleBlacklisted(job.title)) {
      skippedTitleBlacklist++;
      continue;
    }
    if (isCompanyNameBlacklisted(job.company)) {
      skippedCompanyBlacklist++;
      continue;
    }
    if (isTalentPoolDescription(job.description ?? job.descriptionSnippet)) {
      skippedTalentPool++;
      continue;
    }

    if (await isDuplicate(supabase, job.title, job.city)) {
      skippedDuplicate++;
      continue;
    }

    const companyKey = normalizeForDedup(job.company);
    let companyId = companyCache.get(companyKey);
    if (!companyId) {
      const id = await upsertBrazilCompany(supabase, job.company, sourceForDb(job.source));
      if (!id) { errors++; continue; }
      companyCache.set(companyKey, id);
      companyId = id;
    }

    const result = await upsertJob(supabase, job, companyId);
    if (result === "error") {
      errors++;
    } else {
      inserted++;
      const src = sourceForDb(job.source);
      perSource[src] = (perSource[src] ?? 0) + 1;
    }
  }

  const stale = await markStaleJobsInactive(supabase, "brz_%", 48);

  const durationMs = Date.now() - startedAt;
  return jsonResponse({
    ok: true,
    fetched: items.length,
    inserted,
    skippedNotEntryLevel,
    skippedTitleBlacklist,
    skippedCompanyBlacklist,
    skippedTalentPool,
    skippedDuplicate,
    skippedGupy,
    skippedNoId,
    errors,
    markedStale: stale,
    perSource,
    durationMs,
    apifyInput,
  });
});
