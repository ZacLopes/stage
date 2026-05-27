// Adapter Lever — board público em api.lever.co.
//
// Endpoint: GET https://api.lever.co/v0/postings/{slug}?mode=json
// Sem autenticação. Retorna array direto de postings.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  BENEFIT_KEYWORDS,
  REQ_KEYWORDS,
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

export const SOURCE_NAME = "lever";

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

async function fetchJobs(slug: string): Promise<LeverJob[]> {
  const url = `https://api.lever.co/v0/postings/${slug}?mode=json`;
  const resp = await fetchWithTimeout(url, {
    headers: { "Accept": "application/json", "User-Agent": "stage-app/1.0" },
  });
  if (!resp.ok) throw new Error(`Lever ${slug} returned ${resp.status}`);
  return (await resp.json()) as LeverJob[];
}

export async function sync(
  supabase: SupabaseClient,
  src: SourceRow,
): Promise<SyncStats> {
  let jobs: LeverJob[];
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
    const loc = job.categories?.location ?? "";
    if (!isBrazil(loc)) { stats.skipped++; continue; }

    if (!isEntryLevel(job.text, job.categories?.commitment, job.categories?.level)) {
      stats.skipped++;
      continue;
    }
    if (isTalentPoolTitle(job.text)) { stats.skipped++; continue; }

    if (!companyId) {
      companyId = await getOrCreateCompany(
        supabase,
        `${SOURCE_NAME}:${src.company_slug.toLowerCase()}`,
        src.display_name,
        SOURCE_NAME,
      );
      if (!companyId) { stats.errors++; break; }
    }

    const { city, state } = parseLocation(loc);
    const description = (job.descriptionPlain || htmlToText(job.description)).slice(0, 8000);
    if (isTalentPoolDescription(description)) { stats.skipped++; continue; }
    const requirements = extractSection(job.description, REQ_KEYWORDS);
    const benefits = extractSection(job.description, BENEFIT_KEYWORDS);

    const { error } = await supabase
      .from("jobs")
      .upsert({
        company_id: companyId,
        title: job.text,
        description: description || job.text,
        // job.description é o HTML cru do Lever (descriptionPlain é o já-stripped).
        description_html: job.description ? job.description.slice(0, 16000) : null,
        requirements,
        benefits,
        location_city: city,
        location_state: state,
        work_model: inferWorkModel(loc),
        job_type: inferJobType(job.text),
        area: inferArea(job.text, job.categories?.team ?? job.categories?.department ?? null),
        is_active: true,
        published_at: new Date(job.createdAt).toISOString(),
        source: SOURCE_NAME,
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
