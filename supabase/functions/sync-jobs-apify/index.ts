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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isAuthorized(req: Request): boolean {
  const cronHeader = req.headers.get("x-cron-secret");
  if (CRON_SECRET && cronHeader === CRON_SECRET) return true;
  const auth = req.headers.get("authorization");
  if (SUPABASE_SERVICE_ROLE_KEY && auth === `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) return true;
  return false;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function stripHtml(html: string | null | undefined): string {
  if (!html) return "";
  return html
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function htmlToBullets(html: string | null | undefined): string[] {
  if (!html) return [];

  // 1ª escolha: <li>...</li>
  const liMatches = html.match(/<li[^>]*>([\s\S]*?)<\/li>/gi);
  if (liMatches && liMatches.length > 0) {
    return liMatches.map((li) => stripHtml(li)).filter((s) => s.length > 2);
  }

  // 2ª escolha: <p>...</p> múltiplos
  const pMatches = html.match(/<p[^>]*>([\s\S]*?)<\/p>/gi);
  if (pMatches && pMatches.length > 1) {
    return pMatches.map((p) => stripHtml(p)).filter((s) => s.length > 2);
  }

  // Normaliza separadores antes de strip: <br>, </p>, novas linhas → \n
  const normalized = (html || "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<\/?div[^>]*>/gi, "\n");

  const text = stripHtml(normalized);

  // Split por novas linhas, ; ou •
  let parts = text
    .split(/[\n•;]+/)
    .map((s) => s.trim())
    .filter((s) => s.length > 2);

  if (parts.length > 1) return parts;

  // Última tentativa: split por emojis seguidas de espaço (padrão comum em
  // benefícios do Gupy, ex: "🎯 Bonus 🏥 Saúde 💼 VR" → 3 itens)
  const emojiSplit = text.split(/(?=\s*\p{Extended_Pictographic})/u)
    .map((s) => s.trim())
    .filter((s) => s.length > 3);
  if (emojiSplit.length > 1) return emojiSplit;

  // Caiu aqui = string única longa. Retorna como 1 item — UI do app trata
  // benefícios longos com layout full-width.
  return text.length > 2 ? [text] : [];
}

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

function inferArea(job: GupyJob): string {
  // Tenta inferir área pelo título — fallback "Geral"
  const title = (job.name ?? "").toLowerCase();
  const desc = (job.descriptionPlainText ?? "").toLowerCase().slice(0, 500);
  const text = `${title} ${desc}`;

  const rules: Array<[string, string]> = [
    ["Tecnologia", "(engenharia de software|desenvolved|software engineer|backend|frontend|full[- ]?stack|dados|data|machine learning|ml|devops|sre|cloud|infraestrutura|qa|testes?|cybersecurity|segurança da informação|tech|tecnologia|programa|sistemas)"],
    ["Marketing", "(marketing|growth|crm|mídia|branding|comunicação|publicidade|social media)"],
    ["Vendas", "(vendas|sales|comercial|account exec|consultor comercial|business development|bdr|sdr)"],
    ["Finanças", "(finanças|financeir|controladoria|tesouraria|fp&a|contábil|accounting|treasury|investimento)"],
    ["Recursos Humanos", "(recursos humanos|rh|gente|people|talent|recruiter|treinamento)"],
    ["Operações", "(operações|operations|logística|supply chain|cs|customer success|atendimento|suporte)"],
    ["Produto", "(produto|product manager|pm|design de produto|ux|ui|design)"],
    ["Engenharia", "(engenharia(?! de software)|engenheir(?!o de software))"],
    ["Jurídico", "(jurídico|legal|advogad|compliance)"],
    ["Administrativo", "(administrativ|administração|secretaria)"],
  ];

  for (const [area, pattern] of rules) {
    if (new RegExp(pattern, "i").test(text)) return area;
  }
  return "Geral";
}

// ── Main ─────────────────────────────────────────────────────────────────────

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

async function upsertCompany(
  supabase: SupabaseClient,
  job: GupyJob,
): Promise<string | null> {
  const slug = job.companySubdomain
    ? `gupy:${job.companySubdomain.toLowerCase()}`
    : null;
  if (!slug) return null;

  const name = job.careerPageDisplayName || job.careerPageName || job.companySubdomain;
  const description = job.careerPageAbout
    ? stripHtml(job.careerPageAbout).slice(0, 1000)
    : null;

  const { data, error } = await supabase
    .from("companies")
    .upsert(
      {
        slug,
        name,
        logo_url: job.careerPageLogo,
        website: job.careerPageWebsite,
        description,
        source: "gupy",
      },
      { onConflict: "slug" },
    )
    .select("id")
    .single();

  if (error) {
    console.error(`Company upsert failed for ${slug}:`, error.message);
    return null;
  }
  return data.id as string;
}

async function upsertJob(
  supabase: SupabaseClient,
  job: GupyJob,
  companyId: string,
): Promise<"inserted" | "updated" | "error"> {
  const jobType = JOB_TYPE_MAP[job.jobType];
  if (!jobType) return "error"; // tipo não mapeado — pula

  const workModel = WORK_MODEL_MAP[job.workplaceType] ?? "presencial";
  const requirements = htmlToBullets(job.prerequisites).slice(0, 20);
  const benefits = htmlToBullets(job.benefits).slice(0, 20);
  const responsibilities = htmlToBullets(job.responsibilities).slice(0, 20);

  // Description: junta os blocos em texto limpo
  const blocks: string[] = [];
  const baseDesc = stripHtml(job.descriptionPlainText || job.description);
  if (baseDesc) blocks.push(baseDesc);
  if (responsibilities.length > 0) {
    blocks.push("Responsabilidades:\n• " + responsibilities.join("\n• "));
  }
  const description = blocks.join("\n\n").slice(0, 8000); // cap

  const deadline = job.applicationDeadline || job.expiresAt;
  // Mapeia "Nacional" / null como BR genérico
  const locationCity = job.city || (job.isRemoteWork ? "Remoto" : "Brasil");
  const locationState = job.stateCode || "BR";

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
    area: inferArea(job),
    is_active: true,
    published_at: job.publishedAt || new Date().toISOString(),
    deadline: deadline ? new Date(deadline).toISOString() : null,
    source: "gupy",
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

async function markStaleJobsInactive(
  supabase: SupabaseClient,
  cutoffHours: number,
): Promise<number> {
  const cutoff = new Date(Date.now() - cutoffHours * 60 * 60 * 1000).toISOString();
  const { error, count } = await supabase
    .from("jobs")
    .update({ is_active: false }, { count: "exact" })
    .eq("source", "gupy")
    .eq("is_active", true)
    .lt("last_seen_at", cutoff);

  if (error) {
    console.error("markStaleJobsInactive failed:", error.message);
    return 0;
  }
  return count ?? 0;
}

// ── HTTP handler ─────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!isAuthorized(req)) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  if (!APIFY_TOKEN) {
    return jsonResponse({ error: "missing_apify_token", message: "APIFY_API_TOKEN não configurada" }, 500);
  }

  let body: Record<string, unknown> = {};
  if (req.method === "POST") {
    try { body = await req.json(); } catch (_) { body = {}; }
  }

  const maxResults = (body.maxResults as number | undefined) ?? 200;
  const jobTypes = (body.jobTypes as string[] | undefined) ?? [
    "vacancy_type_internship",
    "vacancy_type_apprentice",
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
  const companyCache = new Map<string, string>(); // companySubdomain → company_id

  for (const job of items) {
    if (job.status !== "published") { skipped++; continue; }
    if (!JOB_TYPE_MAP[job.jobType]) { skipped++; continue; }

    let companyId = job.companySubdomain ? companyCache.get(job.companySubdomain) : undefined;
    if (!companyId) {
      const id = await upsertCompany(supabase, job);
      if (!id) { errors++; continue; }
      if (job.companySubdomain) companyCache.set(job.companySubdomain, id);
      companyId = id;
    }

    const result = await upsertJob(supabase, job, companyId);
    if (result === "error") errors++;
    else inserted++;
  }

  const stale = await markStaleJobsInactive(supabase, 48);

  const durationMs = Date.now() - startedAt;
  return jsonResponse({
    ok: true,
    fetched: items.length,
    upserted: inserted,
    skipped,
    errors,
    markedStale: stale,
    durationMs,
    apifyInput,
  });
});
