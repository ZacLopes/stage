// Testes do inferArea (FASE 2 fixes #4) — dois rulesets: TÍTULO completo,
// DESCRIÇÃO forte (sem boilerplate). Roda com:
//   deno test supabase/functions/_shared/jobs.test.ts
//
// Casos vêm da medição em prod: 17/36 das vagas "Tecnologia" ativas não
// tinham token tech no título (classificadas pela descrição ruidosa).
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  cleanCompanyName,
  inferArea,
  markExpiredJobsInactive,
  markStaleJobsInactive,
  silenceShouldDeactivate,
  STALE_MAX_AGE_DAYS,
} from "./jobs.ts";

// ── Pelo TÍTULO: os suspeitos saem de Tecnologia ───────────────────────────
Deno.test("título: esterilização → Saúde (não Tecnologia)", () => {
  assertEquals(
    inferArea("ESTAGIÁRIO - CENTRAL DE MATERIAL DE ESTERILIZAÇÃO", null),
    "Saúde",
  );
});

Deno.test("título: inclusão → Recursos Humanos", () => {
  assertEquals(inferArea("ESTAGIARIO (A) INCLUSAO", null), "Recursos Humanos");
});

Deno.test("título: criação → Produto", () => {
  assertEquals(inferArea("Estágio de Criação", null), "Produto");
});

// Genéricos puros: sem sinal no título e sem descrição → Geral honesto
// (antes caíam em Tecnologia pela descrição).
Deno.test("título genérico sem hint → Geral", () => {
  assertEquals(inferArea("ESTAGIARIO", null), "Geral");
  assertEquals(inferArea("Programa de Estágio Nemak", null), "Geral");
  assertEquals(inferArea("Trainee de Pesquisa", null), "Geral");
  assertEquals(inferArea("ESTAGIO SUPERIOR - MEIO AMBIENTE", null), "Geral");
  assertEquals(
    inferArea("Trainee Receituário Agronômico (Curitiba-PR)", null),
    "Geral",
  );
});

// ── DESCRIÇÃO forte: tech REAL classifica; boilerplate NÃO ─────────────────
Deno.test("descrição: dev de software → Tecnologia", () => {
  assertEquals(
    inferArea(
      "Estagiário",
      "Atuação com desenvolvimento de software e back-end em time ágil.",
    ),
    "Tecnologia",
  );
});

Deno.test("descrição boilerplate (sistemas/dados/suporte/tecnologia) → Geral", () => {
  // O bug do #4: esses tokens fracos jogavam a vaga em Tecnologia.
  assertEquals(
    inferArea(
      "Estagiário",
      "Trabalhará com sistemas internos, análise de dados e suporte ao time, " +
        "em um ambiente de tecnologia e inovação.",
    ),
    "Geral",
  );
});

Deno.test("descrição: psicologia (título com typo derrota a 1ª passada) → Saúde", () => {
  // "Pscicologia" no título não casa psic; a descrição correta salva.
  assertEquals(
    inferArea(
      "ESTAGIÁRIO - PSCICOLOGIA DO TRABALHO",
      "Vaga na área de psicologia organizacional e saúde do trabalhador.",
    ),
    "Saúde",
  );
});

// ── Controles: classificações boas NÃO podem regredir ──────────────────────
Deno.test("controle: tech legítimo no título permanece Tecnologia", () => {
  assertEquals(inferArea("Desenvolvedor Back-end Júnior", null), "Tecnologia");
  assertEquals(inferArea("Estágio em Engenharia de Software", null), "Tecnologia");
  assertEquals(inferArea("Analista de Dados (Data Analyst)", null), "Tecnologia");
});

Deno.test("controle: outras áreas pelo título", () => {
  assertEquals(inferArea("Estágio em Enfermagem", null), "Saúde");
  assertEquals(inferArea("Estágio Financeiro", null), "Finanças");
  assertEquals(inferArea("Estágio em Administração", null), "Administrativo");
  assertEquals(inferArea("Analista de Marketing Digital", null), "Marketing");
  assertEquals(inferArea("Estágio em Vendas", null), "Vendas");
});

// Regressões pegas no dry-run do backfill (15/06) — termos de saúde que o
// regex antigo não casava ("nutricion" ≠ "nutrição") caíam em
// Marketing/Finanças/Geral; segurança do trabalho e educação física idem.
Deno.test("regressão: saúde por título (nutri/educação física/segurança do trabalho)", () => {
  assertEquals(inferArea("Estágio Em Nutrição", null), "Saúde");
  assertEquals(inferArea("Estagiário de Nutrição", null), "Saúde");
  assertEquals(inferArea("Estagiário em Educação Física - João XXIII", null), "Saúde");
  assertEquals(inferArea("Estagiário de Segurança do Trabalho", null), "Saúde");
});

Deno.test("regressão: 'Eficiência Operacional' → Operações (não Vendas)", () => {
  assertEquals(
    inferArea("ESTAGIARIO NIVEL SUPERIOR - Eficiência Operacional", null),
    "Operações",
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// cleanCompanyName — gêmeo de Job.cleanCompanyName (Dart)
//
// ⚠️ ESTA TABELA É O CONTRATO. Ela existe IDÊNTICA em
// test/features/jobs/job_text_normalization_test.dart. Mudou aqui, muda lá —
// duas implementações de uma regra só divergem quando a tabela não é a mesma.
// ─────────────────────────────────────────────────────────────────────────────

const CASOS_NOME_EMPRESA: Array<[string, string]> = [
  // limpa o prefixo de tipo de vaga
  ["Estágio M. Dias Branco", "M. Dias Branco"],
  ["ESTÁGIO KEMPETRO", "KEMPETRO"],
  ["Programa de Estágio - Santa Casa BH", "Santa Casa BH"],
  ["Programa de Estágio Anbima 2026", "Anbima"],
  ["Programa de Trainee SLC Agrícola", "SLC Agrícola"],
  ["Programa de Trainees - BLB Auditores e Consultores", "BLB Auditores e Consultores"],
  ["Banco de Talentos — Acme", "Acme"],
  // o que o prefixo deixava para trás (medido em prod, 30/07)
  ["Estágio | Pif Paf Alimentos", "Pif Paf Alimentos"],
  ["Programa de Estágio 2026 - Grupo Solví", "Grupo Solví"],
  ["Programa de Estágio da PUCPR", "PUCPR"],
  ["Programa de Estágio do CEPEL", "CEPEL"],
  // NÃO mexe: marca legítima, nome comum, conectivo sem prefixo
  ["Programa UTalent", "Programa UTalent"],
  ["Nubank", "Nubank"],
  ["Vagas.com", "Vagas.com"],
  ["Estagiário Digital Ltda", "Estagiário Digital Ltda"],
  ["Banco do Brasil", "Banco do Brasil"],
  ["2026 Ventures", "2026 Ventures"],
  ["de Souza Consultoria", "de Souza Consultoria"],
  // guard: sobrou pouco demais → devolve o cru
  ["Estágio", "Estágio"],
  ["Programa de Estágio", "Programa de Estágio"],
  // bordas
  ["", ""],
  ["   ", ""],
  ["  Acme  ", "Acme"],
];

for (const [entrada, esperado] of CASOS_NOME_EMPRESA) {
  Deno.test(`cleanCompanyName: "${entrada}" → "${esperado}"`, () => {
    assertEquals(cleanCompanyName(entrada), esperado);
  });
}

Deno.test("cleanCompanyName é idempotente (limpar o já limpo não muda)", () => {
  for (const [entrada] of CASOS_NOME_EMPRESA) {
    const umaVez = cleanCompanyName(entrada);
    assertEquals(cleanCompanyName(umaVez), umaVez, `não idempotente em "${entrada}"`);
  }
});


// ═══════════════════════════════════════════════════════════════════════════
// Desligamento: silêncio do robô × prazo do empregador
//
// O bug (medido em prod, 21/08/2026): `last_seen_at` era tratado como "a vaga
// está aberta", mas significa "a vaga apareceu na amostra que puxamos". Gupy e
// InfoJobs são varridos com teto e ordenados pelas mais novas, então vaga VIVA
// sai da amostra — e morria em 48h. De 200 vagas da Gupy que desligamos em 30
// dias, 123 (61,5%) continuavam publicadas.
// ═══════════════════════════════════════════════════════════════════════════

const AGORA = Date.parse("2026-08-21T12:00:00Z");
const DIA = 86_400_000;
const iso = (ms: number) => new Date(ms).toISOString();

Deno.test("silêncio mata quando NÃO há prazo (Greenhouse/InHire/InfoJobs)", () => {
  assertEquals(
    silenceShouldDeactivate({ deadline: null, published_at: iso(AGORA - DIA) }, AGORA),
    true,
  );
});

Deno.test("prazo futuro SEGURA a vaga viva — o conserto", () => {
  assertEquals(
    silenceShouldDeactivate(
      { deadline: iso(AGORA + 30 * DIA), published_at: iso(AGORA - 5 * DIA) },
      AGORA,
    ),
    false,
  );
});

Deno.test("prazo vencido mata, mesmo com a vaga recém-publicada", () => {
  assertEquals(
    silenceShouldDeactivate(
      { deadline: iso(AGORA - DIA), published_at: iso(AGORA - 2 * DIA) },
      AGORA,
    ),
    true,
  );
});

Deno.test("teto de idade vence o prazo: a de 2030 não fica viva pra sempre", () => {
  // Caso REAL: existe linha da Gupy com deadline em 2030-12-31.
  assertEquals(
    silenceShouldDeactivate(
      {
        deadline: "2030-12-31T00:00:00Z",
        published_at: iso(AGORA - (STALE_MAX_AGE_DAYS + 1) * DIA),
      },
      AGORA,
    ),
    true,
  );
});

Deno.test("prazo futuro sem data de publicação NÃO protege", () => {
  // No PostgREST `published_at.lt.X` é falso quando a coluna é NULL; sem a
  // cláusula `is.null` no `.or()`, esta linha ficaria imortal.
  assertEquals(
    silenceShouldDeactivate({ deadline: iso(AGORA + 30 * DIA), published_at: null }, AGORA),
    true,
  );
});

Deno.test("na borda do teto de idade a vaga ainda é protegida", () => {
  assertEquals(
    silenceShouldDeactivate(
      {
        deadline: iso(AGORA + 30 * DIA),
        published_at: iso(AGORA - (STALE_MAX_AGE_DAYS - 1) * DIA),
      },
      AGORA,
    ),
    false,
  );
});

// ── A query de verdade, não só a regra ─────────────────────────────────────
// Cliente falso que grava os filtros: a regra pura e o filtro do PostgREST
// podem divergir em silêncio, e é a query que roda em produção.

function clienteFalso() {
  const chamadas: Record<string, string[]> = {};
  const rec = (nome: string, ...args: unknown[]) => {
    (chamadas[nome] ??= []).push(args.map(String).join("|"));
    return api;
  };
  const api: Record<string, unknown> = {
    from: (...a: unknown[]) => rec("from", ...a),
    update: (...a: unknown[]) => rec("update", ...a),
    eq: (...a: unknown[]) => rec("eq", ...a),
    lt: (...a: unknown[]) => rec("lt", ...a),
    lte: (...a: unknown[]) => rec("lte", ...a),
    not: (...a: unknown[]) => rec("not", ...a),
    or: (...a: unknown[]) => rec("or", ...a),
    like: (...a: unknown[]) => rec("like", ...a),
    then: (resolve: (v: unknown) => void) => resolve({ error: null, count: 7 }),
  };
  return { api, chamadas };
}

Deno.test("markStale: o filtro carrega as 4 cláusulas de escape", async () => {
  const { api, chamadas } = clienteFalso();
  // deno-lint-ignore no-explicit-any
  const n = await markStaleJobsInactive(api as any, "gupy", 48);
  assertEquals(n, 7);
  const or = chamadas["or"][0];
  assertEquals(or.includes("deadline.is.null"), true);
  assertEquals(or.includes("deadline.lte."), true);
  assertEquals(or.includes("published_at.is.null"), true);
  assertEquals(or.includes("published_at.lt."), true);
  // e continua sendo por silêncio + fonte
  assertEquals(chamadas["lt"].some((c) => c.startsWith("last_seen_at")), true);
  assertEquals(chamadas["eq"].some((c) => c === "source|gupy"), true);
});

Deno.test("markStale: fonte com curinga usa like, não eq", async () => {
  const { api, chamadas } = clienteFalso();
  // deno-lint-ignore no-explicit-any
  await markStaleJobsInactive(api as any, "brz_%", 48);
  assertEquals(chamadas["like"][0], "source|brz_%");
  assertEquals(chamadas["eq"].some((c) => c.startsWith("source")), false);
});

Deno.test("markExpired: desliga por prazo SEM olhar last_seen_at", async () => {
  const { api, chamadas } = clienteFalso();
  // deno-lint-ignore no-explicit-any
  const n = await markExpiredJobsInactive(api as any, "polifinance");
  assertEquals(n, 7);
  assertEquals(chamadas["lte"][0].startsWith("deadline"), true);
  assertEquals(chamadas["not"][0], "deadline|is|null");
  // o ponto do teste: silêncio não entra na conta
  assertEquals(chamadas["lt"] ?? [], []);
});
