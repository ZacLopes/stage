// Edge Function: sync-jobs-ats
//
// Itera sobre `external_job_sources` (ats = greenhouse | lever), busca os
// boards públicos de cada empresa, filtra vagas BR de estágio/júnior/trainee
// e upserta em `companies` + `jobs`.
//
// Acesso:
// - Header `x-cron-secret: <CRON_SECRET>` OU
// - Header `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`
//
// Não tem custo externo — só rede.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

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
  // Aceita 2 caminhos:
  // (1) pg_cron com `x-cron-secret: <CRON_SECRET>`.
  // (2) Trigger manual via Dashboard/curl com JWT Bearer válido. O gateway
  //     do Supabase JÁ valida a JWT antes da função receber, então qualquer
  //     `Bearer <...>` aqui significa "veio de alguém com chave do projeto".
  const cronHeader = req.headers.get("x-cron-secret");
  if (CRON_SECRET && cronHeader === CRON_SECRET) return true;
  const auth = req.headers.get("authorization");
  if (auth && /^Bearer\s+\S+/.test(auth)) return true;
  return false;
}

// ── Filtros ──────────────────────────────────────────────────────────────────

const BR_PATTERN = /brazil|brasil|são paulo|s[aã]o paulo|rio de janeiro|recife|porto alegre|belo horizonte|salvador|brasília|, br$|, br /i;

const ENTRY_LEVEL_PATTERN = /est[áa]gi|estagi[áa]ri|^intern$| intern | internship|trainee|j[úu]nior| jr | jr\.|jr,|aprendiz|associate|entry[ -]?level|rec[ée]m[ -]?formad|primeiro emprego|1[ºo] emprego|analyst i$|analyst i,|analyst i |analyst ii$|analyst ii,|analyst ii |jovem aprendiz|dcs /i;

function isBrazil(location: string | null | undefined): boolean {
  return !!location && BR_PATTERN.test(location);
}

function isEntryLevel(text: string | null | undefined): boolean {
  return !!text && ENTRY_LEVEL_PATTERN.test(text);
}

function inferJobType(title: string): string {
  const t = title.toLowerCase();
  if (/intern|estági|estagiári|aprendiz/.test(t)) return "estagio";
  if (/trainee/.test(t)) return "trainee";
  return "clt_junior"; // "Junior", "Analyst I/II", "Associate", "Entry-level"
}

function inferArea(title: string, dept: string | null): string {
  const text = `${title} ${dept ?? ""}`.toLowerCase();
  const rules: Array<[string, RegExp]> = [
    ["Tecnologia", /(software|developer|engenheir|engineer|data|machine learning|ml|backend|frontend|full[- ]?stack|cloud|devops|sre|qa|test|sec|tech|tecnologia|programa|sistema)/],
    ["Marketing", /(marketing|growth|crm|brand|comunicação|publicidade|social media)/],
    ["Vendas", /(sales|venda|comercial|account|business development|bdr|sdr)/],
    ["Finanças", /(finance|financ|account|controller|treasur|fp&a|invest)/],
    ["Recursos Humanos", /(human|people|hr|rh|talent|recruit|gente)/],
    ["Operações", /(operations|opera[cç]ões|logist|supply|cs|customer success|atendimento|suporte)/],
    ["Produto", /(product|produto|design|ux|ui)/],
    ["Engenharia", /(\bengineer\b|engenheir|engenharia)/],
    ["Jurídico", /(legal|jurídic|advogad|compliance)/],
    ["Administrativo", /(admin|administrativ)/],
  ];
  for (const [area, re] of rules) if (re.test(text)) return area;
  return "Geral";
}

function inferWorkModel(location: string | null | undefined): string {
  if (!location) return "presencial";
  const l = location.toLowerCase();
  if (/remot|home[ -]?office/.test(l)) return "remoto";
  if (/h[íi]brid|hybrid/.test(l)) return "hibrido";
  return "presencial";
}

function parseLocation(location: string): { city: string; state: string } {
  // "São Paulo, São Paulo, Brasil" → city = São Paulo, state = SP
  const parts = location.split(",").map((s) => s.trim()).filter(Boolean);
  const city = parts[0] || "Brasil";
  const stateRaw = parts[1] || "BR";

  // Mapa simples de estados (se vier por extenso)
  const STATE_MAP: Record<string, string> = {
    "são paulo": "SP", "sao paulo": "SP", "rio de janeiro": "RJ",
    "minas gerais": "MG", "rio grande do sul": "RS", "paraná": "PR", "parana": "PR",
    "santa catarina": "SC", "bahia": "BA", "pernambuco": "PE",
    "ceará": "CE", "ceara": "CE", "distrito federal": "DF",
    "espírito santo": "ES", "espirito santo": "ES", "goiás": "GO", "goias": "GO",
    "amazonas": "AM", "pará": "PA", "para": "PA", "maranhão": "MA",
    "paraíba": "PB", "alagoas": "AL", "rio grande do norte": "RN", "tocantins": "TO",
  };
  const state = STATE_MAP[stateRaw.toLowerCase()] || (stateRaw.length === 2 ? stateRaw.toUpperCase() : "BR");

  return { city, state };
}

// ── Greenhouse ───────────────────────────────────────────────────────────────

interface GreenhouseJob {
  id: number;
  internal_job_id: number;
  title: string;
  location: { name: string };
  absolute_url: string;
  updated_at: string;
  departments: Array<{ id: number; name: string }>;
  offices: Array<{ id: number; name: string }>;
  content?: string; // se ?content=true
}

async function fetchGreenhouseJobs(slug: string): Promise<GreenhouseJob[]> {
  const url = `https://boards-api.greenhouse.io/v1/boards/${slug}/jobs?content=true`;
  const resp = await fetch(url, {
    headers: { "Accept": "application/json", "User-Agent": "stage-app/1.0" },
  });
  if (!resp.ok) throw new Error(`Greenhouse ${slug} returned ${resp.status}`);
  const data = await resp.json();
  return (data.jobs ?? []) as GreenhouseJob[];
}

// ── Lever ────────────────────────────────────────────────────────────────────

interface LeverJob {
  id: string;
  text: string;
  categories: {
    team?: string;
    department?: string;
    location?: string;
    commitment?: string;
    level?: string;
  };
  descriptionPlain?: string;
  description?: string;
  hostedUrl: string;
  applyUrl?: string;
  createdAt: number;
}

async function fetchLeverJobs(slug: string): Promise<LeverJob[]> {
  const url = `https://api.lever.co/v0/postings/${slug}?mode=json`;
  const resp = await fetch(url, {
    headers: { "Accept": "application/json", "User-Agent": "stage-app/1.0" },
  });
  if (!resp.ok) throw new Error(`Lever ${slug} returned ${resp.status}`);
  return (await resp.json()) as LeverJob[];
}

// ── Persistência ────────────────────────────────────────────────────────────

async function getOrCreateCompany(
  supabase: SupabaseClient,
  ats: string,
  slug: string,
  displayName: string,
): Promise<string | null> {
  const fullSlug = `${ats}:${slug.toLowerCase()}`;
  const { data, error } = await supabase
    .from("companies")
    .upsert(
      { slug: fullSlug, name: displayName, source: ats },
      { onConflict: "slug" },
    )
    .select("id")
    .single();

  if (error) {
    console.error(`Company upsert failed for ${fullSlug}:`, error.message);
    return null;
  }
  return data.id as string;
}

// Palavras-chave que tipicamente prefixam seções no HTML de vagas (PT/EN)
// Importante: PT pluraliza `el` → `eis` (Desejável → Desejáveis), então
// usamos prefixos que casam ambos (`desej[áa]ve` cobre vel/veis).
const REQ_KEYWORDS = [
  /requisitos/i, /qualifica/i, /requirements/i, /qualifications/i,
  /pr[ée][- ]requisitos/i, /desej[áa]ve/i, /obrigat[óo]rios/i,
  /must have/i, /nice to have/i, /who you are/i, /what we are looking/i,
  /what you'?ll need/i, /habilidades/i, /skills/i,
  /o que esperamos/i, /esperamos de voc[êe]/i, /o que buscamos/i,
  /o que precisa ter/i, /o que voc[êe] precisa/i, /quem somos buscando/i,
];
const BENEFIT_KEYWORDS = [
  /benef[íi]cios/i, /benefits/i, /perks/i, /oferecemos/i, /we offer/i,
  /vantagens/i, /what we offer/i, /o que oferecemos/i, /additional information/i,
];

/**
 * Decodifica entidades HTML comuns. Alguns ATSs (Greenhouse) entregam content
 * já com `&lt;`, `&gt;` etc, então precisamos decodificar antes de aplicar regex.
 */
function decodeEntities(s: string): string {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&ndash;/g, "–")
    .replace(/&mdash;/g, "—")
    .replace(/&hellip;/g, "…")
    .replace(/&amp;/g, "&"); // por último pra não dupla-decodificar
}

/**
 * Tenta extrair items de uma seção (Requisitos / Benefícios) do HTML.
 * Estratégia: encontra todos os headers (h1-h6 ou <p><strong>), strippa tags
 * inline pra pegar só o texto, casa contra os keywords. Conteúdo da seção é
 * tudo até o próximo header. Suporta tags aninhadas (<h2><strong>X</strong></h2>).
 */
function extractSection(html: string | null | undefined, keywords: RegExp[]): string[] {
  if (!html) return [];
  const decoded = decodeEntities(html);

  // Coleta headers candidatos. Importante: NÃO incluir bare <strong> porque
  // muitas vagas têm <strong> dentro de <li> (ex: "<li>... entre <strong>Dez 2023</strong>...</li>")
  // e isso truncaria a seção antes dela ter qualquer <li> completo.
  const headerRe =
    /<(h[1-6])[^>]*>([\s\S]*?)<\/\1>|<p[^>]*>\s*<strong[^>]*>([\s\S]*?)<\/strong>\s*<\/p>/gi;

  type Header = { startIdx: number; endIdx: number; text: string };
  const headers: Header[] = [];
  let m: RegExpExecArray | null;
  while ((m = headerRe.exec(decoded)) !== null) {
    const inner = m[2] ?? m[3] ?? "";
    const text = inner.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
    if (text.length > 0 && text.length < 200) {
      headers.push({ startIdx: m.index, endIdx: headerRe.lastIndex, text });
    }
  }

  // Acumula items de TODOS os headers que casam — alguns sites separam em
  // sub-seções (ex: Inter usa "Obrigatórios:" + "Desejáveis:" ambos pra requisitos).
  const allItems: string[] = [];
  const seenIdx = new Set<number>();

  for (let i = 0; i < headers.length; i++) {
    if (seenIdx.has(i)) continue;
    const matches = keywords.some((kw) => kw.test(headers[i].text));
    if (!matches) continue;
    seenIdx.add(i);

    const start = headers[i].endIdx;
    const end = i + 1 < headers.length ? headers[i + 1].startIdx : decoded.length;
    const sectionHtml = decoded.slice(start, end);

    const liMatches = sectionHtml.match(/<li[^>]*>([\s\S]*?)<\/li>/gi);
    if (!liMatches || liMatches.length === 0) continue;

    const items = liMatches
      .map((li) => htmlToText(li).trim())
      .filter((s) => s.length > 3 && s.length < 500);
    allItems.push(...items);

    if (allItems.length >= 15) break;
  }

  return allItems.slice(0, 15);
}

function htmlToText(html: string | null | undefined): string {
  if (!html) return "";
  return decodeEntities(html)
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<\/li>/gi, "\n")
    .replace(/<li[^>]*>/gi, "• ")
    .replace(/<[^>]*>/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

async function syncGreenhouseSource(
  supabase: SupabaseClient,
  src: { id: string; company_slug: string; display_name: string },
): Promise<{ inserted: number; skipped: number; errors: number }> {
  let jobs: GreenhouseJob[];
  try {
    jobs = await fetchGreenhouseJobs(src.company_slug);
  } catch (e) {
    await supabase.from("external_job_sources")
      .update({ last_sync_error: (e as Error).message, last_synced_at: new Date().toISOString() })
      .eq("id", src.id);
    return { inserted: 0, skipped: 0, errors: 1 };
  }

  const stats = { inserted: 0, skipped: 0, errors: 0 };
  let companyId: string | null = null;

  for (const job of jobs) {
    const locName = job.location?.name ?? "";
    if (!isBrazil(locName)) { stats.skipped++; continue; }
    if (!isEntryLevel(job.title)) { stats.skipped++; continue; }

    if (!companyId) {
      companyId = await getOrCreateCompany(supabase, "greenhouse", src.company_slug, src.display_name);
      if (!companyId) { stats.errors++; break; }
    }

    const { city, state } = parseLocation(locName);
    const description = htmlToText(job.content).slice(0, 8000);
    const dept = job.departments?.[0]?.name ?? null;
    // Tenta extrair seções estruturadas do HTML (Greenhouse costuma ter
    // <strong>Requisitos</strong> seguido de <ul><li>...).
    const requirements = extractSection(job.content, REQ_KEYWORDS);
    const benefits = extractSection(job.content, BENEFIT_KEYWORDS);

    const { error } = await supabase
      .from("jobs")
      .upsert({
        company_id: companyId,
        title: job.title,
        description: description || job.title,
        requirements,
        benefits,
        location_city: city,
        location_state: state,
        work_model: inferWorkModel(locName),
        job_type: inferJobType(job.title),
        area: inferArea(job.title, dept),
        is_active: true,
        published_at: job.updated_at,
        source: "greenhouse",
        external_id: String(job.id),
        external_url: job.absolute_url,
        last_seen_at: new Date().toISOString(),
        raw_payload: job,
      }, { onConflict: "source,external_id" });

    if (error) {
      console.error(`Greenhouse job upsert failed for ${job.id}:`, error.message);
      stats.errors++;
    } else {
      stats.inserted++;
    }
  }

  await supabase.from("external_job_sources")
    .update({ last_synced_at: new Date().toISOString(), last_sync_error: null })
    .eq("id", src.id);

  return stats;
}

async function syncLeverSource(
  supabase: SupabaseClient,
  src: { id: string; company_slug: string; display_name: string },
): Promise<{ inserted: number; skipped: number; errors: number }> {
  let jobs: LeverJob[];
  try {
    jobs = await fetchLeverJobs(src.company_slug);
  } catch (e) {
    await supabase.from("external_job_sources")
      .update({ last_sync_error: (e as Error).message, last_synced_at: new Date().toISOString() })
      .eq("id", src.id);
    return { inserted: 0, skipped: 0, errors: 1 };
  }

  const stats = { inserted: 0, skipped: 0, errors: 0 };
  let companyId: string | null = null;

  for (const job of jobs) {
    const loc = job.categories?.location ?? "";
    if (!isBrazil(loc)) { stats.skipped++; continue; }

    const tags = `${job.text} ${job.categories?.commitment ?? ""} ${job.categories?.level ?? ""}`;
    if (!isEntryLevel(tags)) { stats.skipped++; continue; }

    if (!companyId) {
      companyId = await getOrCreateCompany(supabase, "lever", src.company_slug, src.display_name);
      if (!companyId) { stats.errors++; break; }
    }

    const { city, state } = parseLocation(loc);
    const description = (job.descriptionPlain || htmlToText(job.description)).slice(0, 8000);
    // Tenta extrair seções do HTML completo do Lever
    const requirements = extractSection(job.description, REQ_KEYWORDS);
    const benefits = extractSection(job.description, BENEFIT_KEYWORDS);

    const { error } = await supabase
      .from("jobs")
      .upsert({
        company_id: companyId,
        title: job.text,
        description: description || job.text,
        requirements,
        benefits,
        location_city: city,
        location_state: state,
        work_model: inferWorkModel(loc),
        job_type: inferJobType(job.text),
        area: inferArea(job.text, job.categories?.team ?? job.categories?.department ?? null),
        is_active: true,
        published_at: new Date(job.createdAt).toISOString(),
        source: "lever",
        external_id: job.id,
        external_url: job.hostedUrl,
        last_seen_at: new Date().toISOString(),
        raw_payload: job,
      }, { onConflict: "source,external_id" });

    if (error) {
      console.error(`Lever job upsert failed for ${job.id}:`, error.message);
      stats.errors++;
    } else {
      stats.inserted++;
    }
  }

  await supabase.from("external_job_sources")
    .update({ last_synced_at: new Date().toISOString(), last_sync_error: null })
    .eq("id", src.id);

  return stats;
}

async function markStaleJobsInactive(
  supabase: SupabaseClient,
  source: string,
  cutoffHours: number,
): Promise<number> {
  const cutoff = new Date(Date.now() - cutoffHours * 60 * 60 * 1000).toISOString();
  const { error, count } = await supabase
    .from("jobs")
    .update({ is_active: false }, { count: "exact" })
    .eq("source", source)
    .eq("is_active", true)
    .lt("last_seen_at", cutoff);
  if (error) {
    console.error(`markStaleJobsInactive(${source}) failed:`, error.message);
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

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: sources, error: srcErr } = await supabase
    .from("external_job_sources")
    .select("id, ats, company_slug, display_name")
    .eq("is_active", true);

  if (srcErr) return jsonResponse({ error: "list_sources_failed", message: srcErr.message }, 500);

  const startedAt = Date.now();
  const summary: Record<string, { inserted: number; skipped: number; errors: number }> = {};
  let totalInserted = 0;
  let totalErrors = 0;

  for (const src of sources ?? []) {
    const key = `${src.ats}:${src.company_slug}`;
    let stats: { inserted: number; skipped: number; errors: number };
    try {
      if (src.ats === "greenhouse") {
        stats = await syncGreenhouseSource(supabase, src);
      } else if (src.ats === "lever") {
        stats = await syncLeverSource(supabase, src);
      } else {
        stats = { inserted: 0, skipped: 0, errors: 1 };
      }
    } catch (e) {
      console.error(`Unexpected error syncing ${key}:`, (e as Error).message);
      stats = { inserted: 0, skipped: 0, errors: 1 };
    }
    summary[key] = stats;
    totalInserted += stats.inserted;
    totalErrors += stats.errors;
  }

  const staleGh = await markStaleJobsInactive(supabase, "greenhouse", 48);
  const staleLv = await markStaleJobsInactive(supabase, "lever", 48);

  return jsonResponse({
    ok: true,
    sources: sources?.length ?? 0,
    totalInserted,
    totalErrors,
    markedStale: { greenhouse: staleGh, lever: staleLv },
    durationMs: Date.now() - startedAt,
    detail: summary,
  });
});
