// Adapter Greenhouse — board público em boards-api.greenhouse.io.
//
// Endpoint: GET https://boards-api.greenhouse.io/v1/boards/{slug}/jobs?content=true
// Sem autenticação. Retorna array `jobs[]` com todas as posições abertas.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  BENEFIT_KEYWORDS,
  REQ_KEYWORDS,
  decodeEntities,
  extractSection,
  fetchWithTimeout,
  getOrCreateCompany,
  htmlToText,
  inferArea,
  inferJobType,
  inferWorkModel,
  isBrazil,
  isEntryLevel,
  isTalentPoolDescription,
  isTalentPoolTitle,
  parseLocation,
} from "../../_shared/jobs.ts";
import type { SourceRow, SyncStats } from "./types.ts";

export const SOURCE_NAME = "greenhouse";

interface GreenhouseJob {
  id: number;
  internal_job_id: number;
  title: string;
  location: { name: string };
  absolute_url: string;
  updated_at: string;
  departments: Array<{ id: number; name: string }>;
  offices: Array<{ id: number; name: string }>;
  content?: string;
}

async function fetchJobs(slug: string): Promise<GreenhouseJob[]> {
  const url = `https://boards-api.greenhouse.io/v1/boards/${slug}/jobs?content=true`;
  const resp = await fetchWithTimeout(url, {
    headers: { "Accept": "application/json", "User-Agent": "stage-app/1.0" },
  });
  if (!resp.ok) throw new Error(`Greenhouse ${slug} returned ${resp.status}`);
  const data = await resp.json();
  return (data.jobs ?? []) as GreenhouseJob[];
}

export async function sync(
  supabase: SupabaseClient,
  src: SourceRow,
): Promise<SyncStats> {
  let jobs: GreenhouseJob[];
  try {
    jobs = await fetchJobs(src.company_slug);
  } catch (e) {
    await supabase.from("external_job_sources")
      .update({ last_sync_error: (e as Error).message, last_synced_at: new Date().toISOString() })
      .eq("id", src.id);
    return { inserted: 0, skipped: 0, errors: 1 };
  }

  const stats: SyncStats = { inserted: 0, skipped: 0, errors: 0 };
  let companyId: string | null = null;

  for (const job of jobs) {
    const locName = job.location?.name ?? "";
    if (!isBrazil(locName)) { stats.skipped++; continue; }
    if (!isEntryLevel(job.title)) { stats.skipped++; continue; }
    if (isTalentPoolTitle(job.title)) { stats.skipped++; continue; }

    if (!companyId) {
      companyId = await getOrCreateCompany(
        supabase,
        `${SOURCE_NAME}:${src.company_slug.toLowerCase()}`,
        src.display_name,
        SOURCE_NAME,
      );
      if (!companyId) { stats.errors++; break; }
    }

    const { city, state } = parseLocation(locName);
    const description = htmlToText(job.content).slice(0, 8000);
    if (isTalentPoolDescription(description)) { stats.skipped++; continue; }
    const dept = job.departments?.[0]?.name ?? null;
    const requirements = extractSection(job.content, REQ_KEYWORDS);
    const benefits = extractSection(job.content, BENEFIT_KEYWORDS);

    const { error } = await supabase
      .from("jobs")
      .upsert({
        company_id: companyId,
        title: job.title,
        description: description || job.title,
        // job.content vem HTML-escapado da API do Greenhouse
        // (`&lt;div&gt;`, `&quot;`, etc) — precisa decodificar antes de salvar,
        // senão o flutter_html renderiza como texto literal no app.
        description_html: job.content
          ? decodeEntities(job.content).slice(0, 16000)
          : null,
        requirements,
        benefits,
        location_city: city,
        location_state: state,
        work_model: inferWorkModel(locName),
        job_type: inferJobType(job.title),
        area: inferArea(job.title, dept),
        is_active: true,
        published_at: job.updated_at,
        source: SOURCE_NAME,
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
