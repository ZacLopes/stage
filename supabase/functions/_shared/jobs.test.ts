// Testes do inferArea (FASE 2 fixes #4) — dois rulesets: TÍTULO completo,
// DESCRIÇÃO forte (sem boilerplate). Roda com:
//   deno test supabase/functions/_shared/jobs.test.ts
//
// Casos vêm da medição em prod: 17/36 das vagas "Tecnologia" ativas não
// tinham token tech no título (classificadas pela descrição ruidosa).
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { cleanCompanyName, inferArea } from "./jobs.ts";

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
