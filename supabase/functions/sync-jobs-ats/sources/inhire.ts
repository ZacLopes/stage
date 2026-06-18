// Adapter InHire — ATS brasileiro com API pública (api.inhire.app).
//
// Diferente de Greenhouse/Lever, o InHire separa LISTA de DETALHE:
//   • Lista:    GET /job-posts/public/pages          (header X-Tenant: {tenant})
//               → { tenantName, about, logo, jobsPage:[{displayName, jobId,
//                   status, workplaceType, location}] }
//   • Detalhe:  GET /job-posts/public/pages/{jobId}   (mesmo header)
//               → { displayName, description(HTML), contractType:string[],
//                   workplaceType, location, locationComplement, publishedAt, ... }
//
// Fluxo: lista → filtra nos campos baratos (título entry-level + local BR, sem
// talent pool, sem cargo operacional blacklistado) → busca detalhe SÓ dos
// sobreviventes → upsert. Mantém o nº de chamadas HTTP baixo (só ~poucos
// detalhes por tenant), cabendo no budget de 120s do orquestrador.
//
// `company_slug` em external_job_sources = o tenant (subdomínio). A vaga pública
// vive em https://{tenant}.inhire.app/vagas/{jobId}.

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
  isTitleBlacklisted,
  parseLocation,
} from "../../_shared/jobs.ts";
import type { SourceRow, SyncStats } from "./types.ts";

export const SOURCE_NAME = "inhire";

const API_BASE = "https://api.inhire.app";

// Item da lista (campos baratos — bastam pra filtrar antes de gastar detalhe).
interface InhireListItem {
  displayName: string;
  jobId: string;
  status: string;
  workplaceType?: string;
  location?: string;
}

interface InhireListResponse {
  tenantName?: string;
  logo?: string | null;
  jobsPage?: InhireListItem[];
}

// Detalhe da vaga.
interface InhireDetail {
  displayName: string;
  description?: string; // HTML
  contractType?: string[];
  workplaceType?: string;
  location?: string;
  locationComplement?: string;
  publishedAt?: string;
  lastPublishedAt?: string;
  status?: string;
}

/**
 * Mapeia o `workplaceType` do InHire (enum limpo) pro CHECK de `jobs.work_model`.
 * Fallback pro inferWorkModel(location) quando vier algo inesperado.
 */
export function mapWorkplaceType(
  workplaceType: string | null | undefined,
  location?: string | null,
): string {
  switch ((workplaceType ?? "").toLowerCase()) {
    case "on-site":
    case "onsite":
      return "presencial";
    case "remote":
      return "remoto";
    case "hybrid":
      return "hibrido";
    default:
      return inferWorkModel(location);
  }
}

/**
 * isBrazil do _shared cobre "São Paulo, SP, BR" (termina em ", br"), mas vagas
 * remotas do InHire vêm com location == "BR" puro, que o padrão geral deixa
 * passar. Aceita ambos. Todos os tenants do InHire são BR, mas filtramos por
 * segurança (um tenant pode ter vaga fora do país).
 */
export function isBrazilLocation(location: string | null | undefined): boolean {
  const loc = (location ?? "").trim();
  if (!loc) return false;
  if (isBrazil(loc)) return true;
  return /(^|,\s*)br$/i.test(loc);
}

async function fetchList(tenant: string): Promise<InhireListResponse> {
  const resp = await fetchWithTimeout(`${API_BASE}/job-posts/public/pages`, {
    headers: {
      "Accept": "application/json",
      "X-Tenant": tenant,
      "User-Agent": "stage-app/1.0",
    },
  });
  if (!resp.ok) throw new Error(`InHire list ${tenant} returned ${resp.status}`);
  return (await resp.json()) as InhireListResponse;
}

async function fetchDetail(tenant: string, jobId: string): Promise<InhireDetail | null> {
  try {
    const resp = await fetchWithTimeout(
      `${API_BASE}/job-posts/public/pages/${jobId}`,
      {
        headers: {
          "Accept": "application/json",
          "X-Tenant": tenant,
          "User-Agent": "stage-app/1.0",
        },
      },
    );
    if (!resp.ok) return null;
    return (await resp.json()) as InhireDetail;
  } catch {
    return null;
  }
}

/**
 * Monta o row de `jobs` a partir do detalhe do InHire. Pura (sem DB/rede) — é a
 * lógica de domínio do conector; compartilhada por `sync`, pelos testes e pelo
 * dry-run pra não haver drift entre o que validamos e o que é gravado.
 */
export function buildJobRow(
  tenant: string,
  item: InhireListItem,
  detail: InhireDetail,
  companyId: string,
): Record<string, unknown> {
  const title = detail.displayName || item.displayName;
  const description = htmlToText(detail.description).slice(0, 8000);
  const locName = detail.location ?? item.location ?? "";
  const { city, state } = parseLocation(locName);
  const contractType = (detail.contractType ?? []).join(" ");
  return {
    company_id: companyId,
    title,
    description: description || title,
    // description vem como HTML cru do InHire (entidades escapadas) — decodifica
    // antes de salvar pro flutter_html não renderizar literal.
    description_html: detail.description
      ? decodeEntities(detail.description).slice(0, 16000)
      : null,
    requirements: extractSection(detail.description, REQ_KEYWORDS),
    benefits: extractSection(detail.description, BENEFIT_KEYWORDS),
    location_city: city,
    location_state: state,
    work_model: mapWorkplaceType(detail.workplaceType, locName),
    job_type: inferJobType(title, contractType),
    area: inferArea(title, description),
    is_active: true,
    published_at: detail.publishedAt || detail.lastPublishedAt || new Date().toISOString(),
    source: SOURCE_NAME,
    external_id: item.jobId,
    external_url: `https://${tenant}.inhire.app/vagas/${item.jobId}`,
    last_seen_at: new Date().toISOString(),
    raw_payload: detail,
  };
}

/** Filtro barato sobre a LISTA — decide se vale buscar o detalhe. */
function passesListFilter(item: InhireListItem): boolean {
  if (item.status && item.status !== "published") return false;
  const title = item.displayName ?? "";
  if (!isEntryLevel(title)) return false;
  if (!isBrazilLocation(item.location)) return false;
  if (isTalentPoolTitle(title)) return false;
  if (isTitleBlacklisted(title)) return false;
  return true;
}

export async function sync(
  supabase: SupabaseClient,
  src: SourceRow,
): Promise<SyncStats> {
  const tenant = src.company_slug;

  let list: InhireListResponse;
  try {
    list = await fetchList(tenant);
  } catch (e) {
    await supabase.from("external_job_sources")
      .update({ last_sync_error: (e as Error).message, last_synced_at: new Date().toISOString() })
      .eq("id", src.id);
    return { inserted: 0, skipped: 0, errors: 1 };
  }

  const items = list.jobsPage ?? [];
  const stats: SyncStats = { inserted: 0, skipped: 0, errors: 0 };
  let companyId: string | null = null;

  for (const item of items) {
    if (!passesListFilter(item)) { stats.skipped++; continue; }

    const detail = await fetchDetail(tenant, item.jobId);
    if (!detail) { stats.errors++; continue; }

    const description = htmlToText(detail.description).slice(0, 8000);
    if (isTalentPoolDescription(description)) { stats.skipped++; continue; }

    if (!companyId) {
      companyId = await getOrCreateCompany(
        supabase,
        `${SOURCE_NAME}:${tenant.toLowerCase()}`,
        list.tenantName || src.display_name,
        SOURCE_NAME,
        { logo_url: list.logo ?? null },
      );
      if (!companyId) { stats.errors++; break; }
    }

    const { error } = await supabase
      .from("jobs")
      .upsert(buildJobRow(tenant, item, detail, companyId), {
        onConflict: "source,external_id",
      });

    if (error) {
      console.error(`InHire job upsert failed for ${item.jobId}:`, error.message);
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
