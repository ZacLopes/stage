// Edge Function: sync-jobs-apify
//
// Roda o actor `zen-studio/gupy-jobs-scraper` (Apify) e popula as tabelas
// `companies` e `jobs` com vagas brasileiras de estágio/aprendiz/trainee.
//
// Acesso:
// - Header `x-cron-secret: <CRON_SECRET>` (usado pelo pg_cron) OU
// - Header `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>` (uso manual)
//
// Body (JSON, opcional):
// {
//   "maxResults": 200,                                  // default 200
//   "jobTypes": ["vacancy_type_internship", ...],       // default = estágio + aprendiz + trainee
//   "searchTerm": "estágio",                            // opcional
//   "state": "São Paulo"                                // opcional
// }
//
// Variáveis de ambiente esperadas (via supabase secrets):
//   APIFY_API_TOKEN
//   CRON_SECRET
//   SUPABASE_URL              (auto-injected)
//   SUPABASE_SERVICE_ROLE_KEY (auto-injected)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  corsHeaders,
  getOrCreateCompany,
  htmlToBullets,
  inferArea,
  isAuthorized,
  isCompanyNameBlacklisted,
  isTitleBlacklisted,
  jsonResponse,
  markStaleJobsInactive,
  safeJson,
  stripHtml,
} from "../_shared/jobs.ts";

interface GupyJob {
  id: number;
  name: string;
  jobUrl: string;
  description: string | null;
  descriptionPlainText: string | null;
  prerequisites: string | null;
  responsibilities: string | null;
  benefits: string | null;
  city: string | null;
  state: string | null;
  stateCode: string | null;
  country: string | null;
  countryCode: string | null;
  jobType: string;          // vacancy_type_internship | vacancy_type_apprentice | vacancy_type_trainee | ...
  workplaceType: string;    // remote | hybrid | on-site
  isRemoteWork: boolean;
  publishedAt: string | null;
  applicationDeadline: string | null;
  expiresAt: string | null;
  careerPageDisplayName: string | null;
  careerPageName: string | null;
  careerPageUrl: string | null;
  careerPageLogo: string | null;
  careerPageWebsite: string | null;
  careerPageAbout: string | null;
  companyId: number;
  companySubdomain: string;
  status: string;           // 'published'
  publicationType: string;  // 'external' | 'internal'
}

const APIFY_TOKEN = Deno.env.get("APIFY_API_TOKEN") ?? "";
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const SOURCE_NAME = "gupy";

// ── Mapas específicos do Gupy ────────────────────────────────────────────────

const JOB_TYPE_MAP: Record<string, string> = {
  vacancy_type_internship: "estagio",
  vacancy_type_apprentice: "estagio", // CHECK constraint só aceita 4 valores; aprendiz vai como estágio
  vacancy_type_trainee: "trainee",
  vacancy_type_effective: "clt_junior",
  vacancy_type_temporary: "temporario",
  vacancy_type_summer: "temporario",
  vacancy_type_intermittent: "temporario",
};

const WORK_MODEL_MAP: Record<string, string> = {
  "remote": "remoto",
  "hybrid": "hibrido",
  "on-site": "presencial",
};

// CompanySubdomain (Gupy) de empresas que >80% das vagas são operacionais/varejo
// de massa. Estágios nessas empresas raramente são "carreira corporativa" —
// são geralmente operação de loja.
const COMPANY_BLACKLIST = new Set<string>([
  "mcdonalds", "mcd", "burgerking", "bk", "subway", "kfc",
  "carrefour", "atacadao", "atacadão", "paodeacucar", "pão-de-açúcar", "extra",
  "casasbahia", "viavarejo", "magazineluiza-loja",
  "americanas", "lojasamericanas",
  "drogasil", "drogariaspacheco", "drogariasp", "raia",
  "marisa", "renner-loja", "ccaa", "centauro-loja",
  "habibs", "habib", "habibís",
  "cacau-show",
]);

function isCompanyBlacklisted(subdomain: string | null | undefined): boolean {
  if (!subdomain) return false;
  return COMPANY_BLACKLIST.has(subdomain.toLowerCase().trim());
}

/**
 * Bloqueia vagas fora do Brasil. Apify "proxyCountry: BR" só roteia o scraper
 * por proxy BR — não filtra o RESULTADO. Empresas multinacionais (ex: "Nexa
 * Peru") postam suas vagas latam no mesmo Gupy.
 */
function isOutsideBrazil(job: GupyJob): boolean {
  if (job.isRemoteWork) return false; // remoto passa, mesmo sem país explícito
  const country = (job.country ?? "").trim().toLowerCase();
  const countryCode = (job.countryCode ?? "").trim().toUpperCase();
  if (!country && !countryCode) return false; // sem info, assume BR (já vem do Gupy BR)
  if (country === "brasil" || country === "brazil") return false;
  if (countryCode === "BR" || countryCode === "BRA") return false;
  return true;
}

// ── Apify ────────────────────────────────────────────────────────────────────

async function runApify(input: Record<string, unknown>): Promise<GupyJob[]> {
  const url = `https://api.apify.com/v2/acts/zen-studio~gupy-jobs-scraper/run-sync-get-dataset-items?timeout=300&format=json`;
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

// ── Persistência ─────────────────────────────────────────────────────────────

async function upsertGupyCompany(
  supabase: SupabaseClient,
  job: GupyJob,
): Promise<string | null> {
  if (!job.companySubdomain) return null;
  const slug = `${SOURCE_NAME}:${job.companySubdomain.toLowerCase()}`;
  const name = job.careerPageDisplayName || job.careerPageName || job.companySubdomain;
  const description = job.careerPageAbout
    ? stripHtml(job.careerPageAbout).slice(0, 1000)
    : null;

  return await getOrCreateCompany(supabase, slug, name, SOURCE_NAME, {
    logo_url: job.careerPageLogo,
    website: job.careerPageWebsite,
    description,
  });
}

async function upsertJob(
  supabase: SupabaseClient,
  job: GupyJob,
  companyId: string,
): Promise<"inserted" | "error"> {
  const jobType = JOB_TYPE_MAP[job.jobType];
  if (!jobType) return "error";

  const workModel = WORK_MODEL_MAP[job.workplaceType] ?? "presencial";
  const requirements = htmlToBullets(job.prerequisites).slice(0, 20);
  const benefits = htmlToBullets(job.benefits).slice(0, 20);
  const responsibilities = htmlToBullets(job.responsibilities).slice(0, 20);

  const blocks: string[] = [];
  const baseDesc = stripHtml(job.descriptionPlainText || job.description);
  if (baseDesc) blocks.push(baseDesc);
  if (responsibilities.length > 0) {
    blocks.push("Responsabilidades:\n• " + responsibilities.join("\n• "));
  }
  const description = blocks.join("\n\n").slice(0, 8000);

  const deadline = job.applicationDeadline || job.expiresAt;
  const locationCity = job.city || (job.isRemoteWork ? "Remoto" : "Brasil");
  const locationState = job.stateCode || "BR";

  // inferArea aceita (title, contextHints) — concatena descrição como hint
  const areaHints = (job.descriptionPlainText ?? "").slice(0, 500);

  const payload = {
    company_id: companyId,
    title: job.name,
    description,
    requirements,
    benefits,
    location_city: locationCity,
    location_state: locationState,
    work_model: workModel,
    job_type: jobType,
    area: inferArea(job.name, areaHints),
    is_active: true,
    published_at: job.publishedAt || new Date().toISOString(),
    deadline: deadline ? new Date(deadline).toISOString() : null,
    source: SOURCE_NAME,
    external_id: String(job.id),
    external_url: job.jobUrl,
    last_seen_at: new Date().toISOString(),
    raw_payload: job,
  };

  const { error } = await supabase
    .from("jobs")
    .upsert(payload, { onConflict: "source,external_id" });

  if (error) {
    console.error(`Job upsert failed for ${job.id} (${job.name}):`, error.message);
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

  // 100 cabe no timeout de 150s do Edge Functions (200 dava timeout).
  const maxResults = (body.maxResults as number | undefined) ?? 100;
  // Default: estágio + trainee. Aprendiz é EM-only e dominado por varejo
  // operacional (atendente, caixa, operador) — fora do target do app.
  const jobTypes = (body.jobTypes as string[] | undefined) ?? [
    "vacancy_type_internship",
    "vacancy_type_trainee",
  ];
  const apifyInput: Record<string, unknown> = {
    jobTypes,
    sortBy: "newest",
    maxResults,
    proxyConfiguration: {
      useApifyProxy: true,
      apifyProxyGroups: ["RESIDENTIAL"],
      apifyProxyCountry: "BR",
    },
  };
  if (body.searchTerm) apifyInput.searchTerm = body.searchTerm;
  if (body.state) apifyInput.state = body.state;
  if (body.cities) apifyInput.cities = body.cities;
  if (body.workplaceTypes) apifyInput.workplaceTypes = body.workplaceTypes;

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const startedAt = Date.now();
  let items: GupyJob[];
  try {
    items = await runApify(apifyInput);
  } catch (e) {
    return jsonResponse({ error: "apify_failed", message: (e as Error).message }, 502);
  }

  let inserted = 0;
  let errors = 0;
  let skipped = 0;
  let filteredTitle = 0;
  let filteredCompany = 0;
  let filteredCountry = 0;
  let filteredCompanyName = 0;
  const companyCache = new Map<string, string>();

  for (const job of items) {
    if (job.status !== "published") { skipped++; continue; }
    if (!JOB_TYPE_MAP[job.jobType]) { skipped++; continue; }

    if (isTitleBlacklisted(job.name)) {
      filteredTitle++;
      continue;
    }
    if (isCompanyBlacklisted(job.companySubdomain)) {
      filteredCompany++;
      continue;
    }
    if (isOutsideBrazil(job)) {
      filteredCountry++;
      continue;
    }
    const candidateName = job.careerPageDisplayName || job.careerPageName || "";
    if (isCompanyNameBlacklisted(candidateName)) {
      filteredCompanyName++;
      continue;
    }

    let companyId = job.companySubdomain ? companyCache.get(job.companySubdomain) : undefined;
    if (!companyId) {
      const id = await upsertGupyCompany(supabase, job);
      if (!id) { errors++; continue; }
      if (job.companySubdomain) companyCache.set(job.companySubdomain, id);
      companyId = id;
    }

    const result = await upsertJob(supabase, job, companyId);
    if (result === "error") errors++;
    else inserted++;
  }

  const stale = await markStaleJobsInactive(supabase, SOURCE_NAME, 48);

  const durationMs = Date.now() - startedAt;
  return jsonResponse({
    ok: true,
    fetched: items.length,
    upserted: inserted,
    skipped,
    filteredTitle,
    filteredCompany,
    filteredCountry,
    filteredCompanyName,
    errors,
    markedStale: stale,
    durationMs,
    apifyInput,
  });
});
