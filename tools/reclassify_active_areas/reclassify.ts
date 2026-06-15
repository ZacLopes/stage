// reclassify_active_areas — FASE 2 fixes (#4)
//
// Recompõe `jobs.area` das vagas ATIVAS com o inferArea CORRIGIDO (2 rulesets:
// título completo + descrição FORTE, sem boilerplate). Conserta já as vagas
// que o sync ainda não re-upsertou (o upsert do sync sobrescreve `area`, então
// vagas vivas na fonte auto-corrigem no próximo crawl — isto cobre o intervalo
// e as que não reaparecerão tão cedo).
//
// Importa o MESMO inferArea das edge functions (zero drift por construção):
//   ../../supabase/functions/_shared/jobs.ts
//
// SEGURANÇA (igual convert_internal_account.sh): SERVICE_ROLE só via ambiente.
//
// Uso (terminal do fundador):
//   export SERVICE_ROLE=<service-role-key>
//   deno run --allow-env --allow-net tools/reclassify_active_areas/reclassify.ts            # DRY-RUN (não escreve)
//   deno run --allow-env --allow-net --allow-write tools/reclassify_active_areas/reclassify.ts --apply
//   deno run --allow-env --allow-net tools/reclassify_active_areas/reclassify.ts --revert backup_<ts>.json
//   unset SERVICE_ROLE
//
// Sequência recomendada: dry-run (revisa a lista de/para) → --apply (faz
// backup JSON local + UPDATE só nos diffs). UPDATE é DADO (não schema) via
// service role — não viola R2. O backup é arquivo LOCAL (não cria tabela:
// R2 proíbe DDL fora de migration; desvio consciente vs. o "_jobs_area_backup"
// do plano — registrado no relatório).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { inferArea } from "../../supabase/functions/_shared/jobs.ts";

const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ??
  "https://gaxfmniffjvwrwyunorl.supabase.co";

if (!SERVICE_ROLE) {
  console.error("ERRO: export SERVICE_ROLE=<service-role-key> antes de rodar.");
  Deno.exit(1);
}

const args = new Set(Deno.args);
const apply = args.has("--apply");
const revertIdx = Deno.args.indexOf("--revert");
const revertFile = revertIdx >= 0 ? Deno.args[revertIdx + 1] : null;

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { persistSession: false },
});

type JobRow = {
  id: string;
  title: string;
  description: string | null;
  requirements: string[] | null;
  area: string;
  source: string | null;
};

// SÓ fontes cujo pipeline usa a DESCRIÇÃO como hint do inferArea — assim a
// recomputação é FIEL ao pipeline e o diff = exclusivamente o fix do #4.
//   gupy (sync-jobs-apify): hint = descrição[:500]
//   brz_infojobs (sync-jobs-brazil): hint = descrição[:500] + tags
// greenhouse (depto), polifinance (area_hint da IA/descrição) usam OUTRO hint
// → ficam de fora (recomputar com descrição divergiria do pipeline; o próximo
// sync re-upserta a área correta de qualquer forma).
const DESC_HINT_SOURCES = new Set(["gupy", "brz_infojobs"]);

function areaHints(job: JobRow): string {
  const desc = (job.description ?? "").slice(0, 500);
  if (job.source === "brz_infojobs") {
    const tags = (job.requirements ?? []).join(" ");
    return `${desc} ${tags}`;
  }
  return desc; // gupy e demais de descrição
}

// ── Modo revert ────────────────────────────────────────────────────────────
if (revertFile) {
  const backup = JSON.parse(await Deno.readTextFile(revertFile)) as Array<
    { id: string; old_area: string }
  >;
  console.log(`Revertendo ${backup.length} vagas de ${revertFile}…`);
  let n = 0;
  for (const b of backup) {
    const { error } = await supabase
      .from("jobs")
      .update({ area: b.old_area })
      .eq("id", b.id);
    if (error) console.error(`  falha ${b.id}: ${error.message}`);
    else n++;
  }
  console.log(`Revertidas: ${n}/${backup.length}.`);
  Deno.exit(0);
}

// ── Carrega ativas ───────────────────────────────────────────────────────
const { data, error } = await supabase
  .from("jobs")
  .select("id, title, description, requirements, area, source")
  .eq("is_active", true);

if (error) {
  console.error(`ERRO ao ler jobs: ${error.message}`);
  Deno.exit(1);
}
const jobs = (data ?? []) as JobRow[];

// ── Calcula diffs ──────────────────────────────────────────────────────────
type Diff = {
  id: string;
  title: string;
  old_area: string;
  new_area: string;
  source: string | null;
};
const diffs: Diff[] = [];
let skippedOtherSource = 0;
for (const job of jobs) {
  // Só recomputa fontes de descrição-hint (fidelidade ao pipeline).
  if (!DESC_HINT_SOURCES.has(job.source ?? "")) {
    skippedOtherSource++;
    continue;
  }
  const newArea = inferArea(job.title, areaHints(job));
  if (newArea !== job.area) {
    diffs.push({
      id: job.id,
      title: job.title,
      old_area: job.area,
      new_area: newArea,
      source: job.source,
    });
  }
}

// ── Relatório ──────────────────────────────────────────────────────────────
console.log(`Vagas ativas: ${jobs.length}`);
console.log(
  `Fora de escopo (fonte não-descrição: greenhouse/polifinance/…): ${skippedOtherSource}`,
);
console.log(`Vão mudar de área (gupy/brz_infojobs): ${diffs.length}\n`);

const byTransition = new Map<string, number>();
const bySource = new Map<string, number>();
for (const d of diffs) {
  const k = `${d.old_area} → ${d.new_area}`;
  byTransition.set(k, (byTransition.get(k) ?? 0) + 1);
  const s = d.source ?? "?";
  bySource.set(s, (bySource.get(s) ?? 0) + 1);
}
console.log("Por transição (de → para):");
for (const [k, v] of [...byTransition.entries()].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${v.toString().padStart(3)}  ${k}`);
}
console.log("\nPor fonte:");
for (const [k, v] of [...bySource.entries()].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${v.toString().padStart(3)}  ${k}`);
}
console.log("\nLista completa (id · fonte · de → para · título):");
for (const d of diffs) {
  console.log(
    `  ${d.id} · ${d.source ?? "?"} · ${d.old_area} → ${d.new_area} · ${d.title.trim()}`,
  );
}

if (!apply) {
  console.log("\nDRY-RUN: nada foi escrito. Reveja a lista e rode com --apply.");
  Deno.exit(0);
}

// ── Apply: backup local + UPDATE dos diffs ───────────────────────────────
const ts = new Date().toISOString().replace(/[:.]/g, "-");
const backupPath =
  new URL(`./backup_${ts}.json`, import.meta.url).pathname;
await Deno.writeTextFile(
  backupPath,
  JSON.stringify(
    diffs.map((d) => ({ id: d.id, old_area: d.old_area, new_area: d.new_area })),
    null,
    2,
  ),
);
console.log(`\nBackup salvo: ${backupPath}`);

let ok = 0;
for (const d of diffs) {
  const { error: upErr } = await supabase
    .from("jobs")
    .update({ area: d.new_area })
    .eq("id", d.id);
  if (upErr) console.error(`  falha ${d.id}: ${upErr.message}`);
  else ok++;
}
console.log(`Atualizadas: ${ok}/${diffs.length}.`);
console.log("Reverter, se preciso: --revert " + backupPath);
