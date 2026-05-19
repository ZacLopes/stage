// Contrato compartilhado entre o orquestrador `sync-jobs-ats/index.ts` e cada
// adapter em `sources/{ats}.ts`. Cada novo ATS implementa essa interface e o
// orquestrador registra o adapter em SOURCE_ADAPTERS.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface SourceRow {
  id: string;
  company_slug: string;
  display_name: string;
}

export interface SyncStats {
  inserted: number;
  skipped: number;
  errors: number;
}

export type SourceAdapter = (
  supabase: SupabaseClient,
  src: SourceRow,
) => Promise<SyncStats>;
