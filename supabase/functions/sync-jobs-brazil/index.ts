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
//   "includeDescription": true                             // default true (precisamos da descrição)
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
// vem pelo sync-jobs-apify), usamos "all" e filtramos Gupy no loop (custa
// ~10-30% de overhead em vagas Gupy retornadas + descartadas — aceitável).
const DEFAULT_SOURCES = "all";

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
  // Mesmo padrão do sync-jobs-apify: cron secret OU JWT Bearer válido
  // (gateway já valida JWT antes da função receber).
  const cronHeader = req.headers.get("x-cron-secret");
  if (CRON_SECRET && cronHeader === CRON_SECRET) return true;
  const auth = req.headers.get("authorization");
  if (auth && /^Bearer\s+\S+/.test(auth)) return true;
  return false;
}

// ── Helpers (compartilhados em filosofia com sync-jobs-apify) ────────────────

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

/**
 * Normaliza string pra comparação fuzzy de dedup:
 * - lowercase
 * - remove acentos (NFD + filtra marks)
 * - colapsa whitespace
 * - tira pontuação básica
 */
function normalizeForDedup(s: string | null | undefined): string {
  if (!s) return "";
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // remove combining marks
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Parse "Salário R$ 2.500,00" → 2500 (BRL number). Best-effort. */
function parseSalary(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return null;
  const digits = value.replace(/[^\d]/g, "");
  if (!digits) return null;
  const n = parseInt(digits, 10);
  return Number.isFinite(n) ? n : null;
}

const WORK_MODE_MAP: Record<string, string> = {
  remote: "remoto",
  hybrid: "hibrido",
  onsite: "presencial",
  "on-site": "presencial",
};

const JOB_TYPE_KEYWORDS: Array<[RegExp, string]> = [
  // Cobre: estagio, estágio, estagiario, estagiaria, estagiário, estagiária,
  // estagiárias, estagiários. O `[áa]` precisa estar em TODAS as posições
  // onde pode haver acento — "estagiária" tem á na sílaba tônica.
  [/est[aá]gi(?:o|os|[aá]ri[oa]s?)|^intern$|internship/i, "estagio"],
  [/trainee/i, "trainee"],
  [/temporári[oa]|tempor[aá]rio/i, "temporario"],
  // Default: junior CLT
];

function inferJobType(title: string, employmentType?: string | null): string {
  const text = `${title} ${employmentType ?? ""}`;
  for (const [re, type] of JOB_TYPE_KEYWORDS) {
    if (re.test(text)) return type;
  }
  return "clt_junior";
}

const ENTRY_LEVEL_PATTERN =
  /est[áa]gi|estagi[áa]ri|^intern$| intern | internship|trainee|j[úu]nior| jr | jr\.|jr,|aprendiz|associate|entry[ -]?level|rec[ée]m[ -]?formad|primeiro emprego|1[ºo] emprego|analyst i$|analyst i,|analyst i |analyst ii$|analyst ii,|analyst ii |jovem aprendiz/i;

function isEntryLevel(title: string, experienceLevel?: string | null): boolean {
  if (ENTRY_LEVEL_PATTERN.test(title)) return true;
  if (experienceLevel && ENTRY_LEVEL_PATTERN.test(experienceLevel)) return true;
  return false;
}

// Áreas — mesma lógica do sync-jobs-apify
function inferArea(job: BrazilJob): string {
  const title = (job.title ?? "").toLowerCase();
  const desc = (job.description ?? job.descriptionSnippet ?? "").toLowerCase().slice(0, 500);
  const tags = (job.tags ?? []).join(" ").toLowerCase();
  const text = `${title} ${desc} ${tags}`;

  const rules: Array<[string, string]> = [
    ["Jurídico", "(jur[íi]dic|direito|advog|advocacia|legal|compliance|contencioso|tribut[áa]rio|paralegal|direito (?:empresarial|trabalhista|c[íi]vel|tribut[áa]rio|penal|consumidor)|escrit[óo]rio de advocacia)"],
    ["Tecnologia", "(engenharia de software|desenvolved|software engineer|backend|frontend|full[- ]?stack|dados|data|machine learning|ml|devops|sre|cloud|infraestrutura|qa|testes?|cybersecurity|segurança da informação|tech|tecnologia|program(?:a[cdr]|ação|ador)|sistemas)"],
    ["Marketing", "(marketing|growth|crm|mídia|branding|comunicação|publicidade|social media)"],
    ["Vendas", "(vendas|sales|comercial|account exec|consultor comercial|business development|bdr|sdr)"],
    ["Finanças", "(finanças|financeir|controladoria|tesouraria|fp&a|contábil|accounting|treasury|investimento)"],
    ["Recursos Humanos", "(recursos humanos|rh|gente|people|talent|recruiter|treinamento)"],
    ["Operações", "(operações|operations|logística|supply chain|cs|customer success|atendimento|suporte)"],
    ["Produto", "(produto|product manager|pm|design de produto|ux|ui|design)"],
    ["Engenharia", "(engenharia(?! de software)|engenheir(?!o de software))"],
    ["Administrativo", "(administrativ|administração|secretaria)"],
  ];

  for (const [area, pattern] of rules) {
    if (new RegExp(pattern, "i").test(text)) return area;
  }
  return "Geral";
}

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

// ── Filtros de qualidade (mesma filosofia do sync-jobs-apify) ────────────────

const TITLE_BLACKLIST_REGEXES: RegExp[] = [
  /\batendente\b/i,
  /\bbalconist[ao]\b/i,
  /\boperador(a)? de caix[ao]\b/i,
  /\boperador(a)? de loja\b/i,
  /\bcaixa de loja\b/i,
  /\baux(iliar)? de cozinha\b/i,
  /\baux(iliar)? de loja\b/i,
  /\baux(iliar)? de limpeza\b/i,
  /\baux(iliar)? de produ[cç][aã]o\b/i,
  /\baux(iliar)? log[íi]stico\b/i,
  /\baux(iliar)? de servi[cç]os gerais\b/i,
  /\bservi[cç]os gerais\b/i,
  /\brepositor(a)?\b/i,
  /\bempacotador(a)?\b/i,
  /\bestoquista\b/i,
  /\boperador(a)? de telemarketing\b/i,
  /\bteleoperador(a)?\b/i,
  /\bvendedor(a)? de loja\b/i,
  /\bpromotor(a)? de vendas?\b/i,
  /\bdemonstrador(a)?\b/i,
  /\bvigilante\b/i,
  /\bporteiro(a)?\b/i,
  /\bmotoboy\b/i,
  /\bmotorista\b/i,
  /\bentregador(a)?\b/i,
  /\boperador(a)? de produ[cç][aã]o\b/i,
  /\boperador(a)? de m[áa]quinas?\b/i,
  /\bsoldador(a)?\b/i,
  /\bcosturei[rt][ao]\b/i,
  /\bcamareir[ao]\b/i,
  /\bgar[cç]on(ete)?\b/i,
  /\bcopeiro(a)?\b/i,
  /\bpadeiro(a)?\b/i,
  /\baçougueiro(a)?\b/i,
  /\bconfeiteiro(a)?\b/i,
  /\binstrutor(a)? de muscula[cç][aã]o\b/i,
  /\bpersonal trainer\b/i,
  // Discriminatórias (gênero/etnia/orientação) — ilegal pela CLT
  /\b(estagi[aá]ri[ao]|vaga)\s+(feminin|masculin)/i,
  /\bsomente\s+(mulher|homem|feminin|masculin)/i,
  /\bexclusiv[oa]\s+para\s+(mulher|homem)/i,
];

const COMPANY_NAME_BLACKLIST_REGEXES: RegExp[] = [
  /^programa de est[áa]gio$/i,
  /vagas de est[áa]gio\?? *temos/i,
  /[\u{1F300}-\u{1FAFF}]/u,
  /^confidencial$/i,
  /^empresa confidencial$/i,
  /^vaga confidencial$/i,
  /^anonim[oa]$/i,
  /^a definir$/i,
  /^sem identifica[çc][ãa]o$/i,
  /\bacademia\b/i,
  /^sunojobs$/i,
  /^oval\s*-\s*vagas/i,
  /^conex[aã]o talento$/i,
  /^vagas instituto/i,
  /^seja pasa!?$/i,
  /^fa[cç]a parte do time/i,
  /^talentos barcelos/i,
  /^programa de est[áa]gio e aprendiz \d+$/i,
  /\bassessoria$/i,
];

function isTitleBlacklisted(title: string): boolean {
  if (!title) return false;
  for (const re of TITLE_BLACKLIST_REGEXES) {
    if (re.test(title)) return true;
  }
  return false;
}

function isCompanyNameBlacklisted(name: string | null | undefined): boolean {
  const n = (name ?? "").trim();
  if (!n) return false;
  for (const re of COMPANY_NAME_BLACKLIST_REGEXES) {
    if (re.test(n)) return true;
  }
  return false;
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
 * Verifica se já existe uma vaga ativa com título normalizado parecido
 * + cidade igual. Usado pra evitar duplicatas entre:
 * (a) Brazil Jobs e Apify Gupy (mesma vaga em InfoJobs e Gupy)
 * (b) Internamente dentro do Brazil Jobs (mesma vaga em InfoJobs + LinkedIn)
 *
 * Heurística: title contém substring + cidade igual + is_active.
 * Tolera falsos negativos (perde algumas dedups), evita falsos positivos
 * (não suprime vagas reais). title_norm cobre só os primeiros 40 chars pra
 * pegar variações tipo "Estagiário Marketing" vs "Estagiário de Marketing".
 */
async function isDuplicate(
  supabase: SupabaseClient,
  title: string,
  city: string | null | undefined,
): Promise<boolean> {
  const titleNorm = normalizeForDedup(title);
  const cityNorm = normalizeForDedup(city);
  if (!titleNorm || titleNorm.length < 8) return false; // título curto demais — não dedup

  // Pega primeiros 30 chars como "core" do título — suporta variações no fim
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

async function upsertCompany(
  supabase: SupabaseClient,
  name: string,
  source: string,
): Promise<string | null> {
  // Brazil Jobs não fornece logo/website/about por empresa. Usa só o nome.
  const slug = `brz:${normalizeForDedup(name).replace(/\s+/g, "-").slice(0, 60)}`;

  const { data, error } = await supabase
    .from("companies")
    .upsert(
      { slug, name, source },
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
  job: BrazilJob,
  companyId: string,
): Promise<"inserted" | "error"> {
  const jobType = inferJobType(job.title, job.employmentType);

  const workModel = job.workModality && WORK_MODE_MAP[job.workModality]
    ? WORK_MODE_MAP[job.workModality]
    : "presencial";

  const salaryMin = parseSalary(job.salaryMin);
  const salaryMax = parseSalary(job.salaryMax);

  // Description: prefere full, fallback pro snippet
  const rawDesc = job.description || job.descriptionSnippet || "";
  const description = stripHtml(rawDesc).slice(0, 8000);

  // Benefits: string única — split por separador comum
  const benefits = (job.benefits ?? "")
    .split(/[,;\n•]+/)
    .map((s) => s.trim())
    .filter((s) => s.length > 2 && s.length < 200)
    .slice(0, 20);

  const tags = (job.tags ?? []).filter((t) => t && t.length > 0).slice(0, 10);

  // Location fallback: city/state diretos, senão "location" geral, senão Brasil
  const locationCity = job.city || job.location || (workModel === "remoto" ? "Remoto" : "Brasil");
  const locationState = job.state || "BR";

  const dbSource = sourceForDb(job.source);

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
    area: inferArea(job),
    is_active: true,
    published_at: job.datePosted || new Date().toISOString(),
    source: dbSource,
    external_id: String(job.id),
    external_url: job.url ?? null,
    last_seen_at: new Date().toISOString(),
    raw_payload: job,
  };

  if (salaryMin != null) payload.salary_min = salaryMin * 100; // converte BRL → centavos
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

async function markStaleJobsInactive(
  supabase: SupabaseClient,
  cutoffHours: number,
): Promise<number> {
  const cutoff = new Date(Date.now() - cutoffHours * 60 * 60 * 1000).toISOString();
  const { error, count } = await supabase
    .from("jobs")
    .update({ is_active: false }, { count: "exact" })
    .like("source", "brz_%")
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

  // Hard cap em 200 — protege contra `maxListings: 0` (ilimitado no actor!) que
  // poderia trazer 10k+ vagas = $200+. Em produção mantemos 50 por dia ($1/dia).
  const requestedMax = (body.maxListings as number | undefined) ?? 50;
  const maxListings = Math.min(Math.max(1, requestedMax), HARD_CAP_LISTINGS);

  const keyword = (body.keyword as string | undefined) ?? "estagio";
  const sources = (body.sources as string | undefined) ?? DEFAULT_SOURCES;
  const includeDescription = (body.includeDescription as boolean | undefined) ?? true;

  // Build input pro actor
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
  let skippedDuplicate = 0;
  let skippedGupy = 0;       // defesa contra Gupy vindo no output (não deveria mas...)
  let skippedNoId = 0;
  const companyCache = new Map<string, string>();
  const perSource: Record<string, number> = {};

  for (const job of items) {
    // Validações básicas
    if (!job.id || !job.title || !job.company) {
      skippedNoId++;
      continue;
    }

    // Defesa: se vier do Gupy mesmo configuração excluindo, pula (já temos no sync-jobs-apify)
    if (sourceForDb(job.source) === "brz_gupy") {
      skippedGupy++;
      continue;
    }

    // Filtros de qualidade
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

    // Dedup runtime (defense-in-depth contra duplicatas entre fontes)
    if (await isDuplicate(supabase, job.title, job.city)) {
      skippedDuplicate++;
      continue;
    }

    // Upsert company (cache em memória pra evitar N writes na mesma empresa)
    const companyKey = normalizeForDedup(job.company);
    let companyId = companyCache.get(companyKey);
    if (!companyId) {
      const id = await upsertCompany(supabase, job.company, sourceForDb(job.source));
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

  const stale = await markStaleJobsInactive(supabase, 48);

  const durationMs = Date.now() - startedAt;
  return jsonResponse({
    ok: true,
    fetched: items.length,
    inserted,
    skippedNotEntryLevel,
    skippedTitleBlacklist,
    skippedCompanyBlacklist,
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
