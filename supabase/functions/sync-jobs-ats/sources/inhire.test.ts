// Testes dos helpers puros do adapter InHire. Sem rede.
//   deno test supabase/functions/sync-jobs-ats/sources/inhire.test.ts
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildJobRow, isBrazilLocation, mapWorkplaceType } from "./inhire.ts";
import { inferJobType } from "../../_shared/jobs.ts";

// ── mapWorkplaceType: enum do InHire → CHECK de jobs.work_model ──────────────
Deno.test("mapWorkplaceType: enum conhecido", () => {
  assertEquals(mapWorkplaceType("On-site"), "presencial");
  assertEquals(mapWorkplaceType("Remote"), "remoto");
  assertEquals(mapWorkplaceType("Hybrid"), "hibrido");
  // case-insensitive
  assertEquals(mapWorkplaceType("remote"), "remoto");
});

Deno.test("mapWorkplaceType: desconhecido cai no fallback por location", () => {
  assertEquals(mapWorkplaceType(null, "São Paulo - Home Office"), "remoto");
  assertEquals(mapWorkplaceType(undefined, "São Paulo, SP"), "presencial");
  assertEquals(mapWorkplaceType("", "Híbrido - SP"), "hibrido");
});

// ── isBrazilLocation: cobre o "Remote / BR" que o isBrazil puro deixa passar ──
Deno.test("isBrazilLocation: formatos do InHire", () => {
  assertEquals(isBrazilLocation("São Paulo, SP, BR"), true);
  assertEquals(isBrazilLocation("Maringá, PR, BR"), true);
  assertEquals(isBrazilLocation("BR"), true); // remota: location puro "BR"
  assertEquals(isBrazilLocation("Lisboa, PT"), false);
  assertEquals(isBrazilLocation(""), false);
  assertEquals(isBrazilLocation(null), false);
});

// ── contractType[] → job_type via inferJobType (employmentType = join) ───────
Deno.test("inferJobType: contractType do InHire", () => {
  assertEquals(inferJobType("Estágio em Produto", "Estagio"), "estagio");
  assertEquals(inferJobType("Aprendiz Administrativo", "Menor aprendiz"), "estagio");
  assertEquals(inferJobType("Analista Comercial Trainee", "CLT"), "trainee");
  assertEquals(inferJobType("Analista Comercial Júnior", "CLT"), "clt_junior");
  assertEquals(inferJobType("Consultor", "Temporario"), "temporario");
});

// ── buildJobRow: montagem do row (área, job_type, work_model, url, html) ─────
Deno.test("buildJobRow: detalhe do InHire → row de jobs", () => {
  const row = buildJobRow(
    "v360",
    { displayName: "Estágio em Marketing Digital", jobId: "abc-123", status: "published" },
    {
      displayName: "Estágio em Marketing Digital",
      description: "<p>Voc&ecirc; vai atuar com <strong>campanhas</strong> e mídia.</p>",
      contractType: ["Estagio"],
      workplaceType: "Remote",
      location: "BR",
      publishedAt: "2026-06-01T00:00:00.000Z",
    },
    "company-uuid",
  );
  assertEquals(row.source, "inhire");
  assertEquals(row.external_id, "abc-123");
  assertEquals(row.external_url, "https://v360.inhire.app/vagas/abc-123");
  assertEquals(row.job_type, "estagio"); // contractType ["Estagio"]
  assertEquals(row.work_model, "remoto"); // workplaceType "Remote"
  assertEquals(row.area, "Marketing"); // título "Marketing Digital"
  assertEquals(row.company_id, "company-uuid");
  // description vem como texto limpo; description_html decodifica entidades.
  assertEquals(row.description, "Você vai atuar com campanhas e mídia.");
  assertEquals(
    (row.description_html as string).includes("&ecirc;"),
    false,
  );
});
