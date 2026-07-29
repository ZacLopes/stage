// Rede para `reconcileRemoteReasons` (revisão UX 28/07/2026).
//
// O fixture do primeiro teste é uma linha REAL de `match_analyses` em produção,
// da conta de teste criada durante a revisão — vaga remota (Eusébio, CE) que o
// modelo penalizou por cidade, contradizendo o "Remoto sempre passa" que a
// própria folha de filtros anuncia.
//
// Rodar:
//   deno test --no-check --import-map=supabase/functions/import_map.json \
//     supabase/functions/analyze-match/reasons.test.ts

import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts'
import { reconcileRemoteReasons, type MatchReason } from './reasons.ts'

const VAGA_REMOTA = { id: 'job-1', work_model: 'remoto' }
const ACEITA_REMOTO = { work_models: ['remoto', 'hibrido', 'presencial'] }

/** Linha real de produção (user de teste, vaga remota da M. Dias Branco). */
const REASONS_REAIS: MatchReason[] = [
  { label: 'Área', matched: true, weight: 30, detail: 'Operações bate exatamente com seu interesse declarado.' },
  { label: 'Tipo', matched: true, weight: 20, detail: 'Estágio é o tipo que você procura.' },
  { label: 'Localização', matched: false, weight: 0, detail: 'Eusébio, CE não está entre suas cidades preferidas.' },
  { label: 'Modelo', matched: true, weight: 15, detail: 'Remoto bate com sua preferência.' },
  { label: 'Skills', matched: true, weight: 10, detail: 'Excel e Power BI estão entre suas skills e os requisitos da vaga.' },
]

const somaMatched = (rs: MatchReason[]) =>
  rs.filter((r) => r.matched).reduce((s, r) => s + Math.max(0, r.weight), 0)

Deno.test('linha real de prod: some a penalidade falsa de localização em vaga remota', () => {
  const out = reconcileRemoteReasons(REASONS_REAIS, VAGA_REMOTA, ACEITA_REMOTO)
  assertEquals(out.map((r) => r.label), ['Área', 'Tipo', 'Modelo', 'Skills'])
  // O score derivado NÃO muda: a linha removida já contribuía 0.
  assertEquals(somaMatched(out), somaMatched(REASONS_REAIS))
  assertEquals(somaMatched(out), 75)
})

Deno.test('corrige a frase que se contradiz ("prefere remoto, mas a vaga é remoto")', () => {
  const contraditorio: MatchReason[] = [
    { label: 'Modelo', matched: false, weight: 15, detail: 'Você prefere remoto, mas a vaga é remoto.' },
  ]
  const out = reconcileRemoteReasons(contraditorio, VAGA_REMOTA, ACEITA_REMOTO)
  assertEquals(out[0].matched, true)
  assertEquals(out[0].detail, 'Remoto, que é como você prefere trabalhar.')
})

Deno.test('NÃO inventa acerto: quem não aceita remoto mantém o Modelo como falha', () => {
  const soPresencial = { work_models: ['presencial'] }
  const rs: MatchReason[] = [
    { label: 'Modelo', matched: false, weight: 15, detail: 'Você prefere presencial, mas a vaga é remota.' },
  ]
  const out = reconcileRemoteReasons(rs, VAGA_REMOTA, soPresencial)
  assertEquals(out[0].matched, false)
  assertEquals(out[0].detail, 'Você prefere presencial, mas a vaga é remota.')
})

Deno.test('vaga NÃO remota passa intacta (a correção não vaza)', () => {
  const presencial = { id: 'job-2', work_model: 'presencial' }
  const rs: MatchReason[] = [
    { label: 'Localização', matched: false, weight: 0, detail: 'São Paulo não está entre suas cidades.' },
    { label: 'Modelo', matched: false, weight: 15, detail: 'Você prefere remoto, mas a vaga é presencial.' },
  ]
  assertEquals(reconcileRemoteReasons(rs, presencial, ACEITA_REMOTO), rs)
})

Deno.test('Localização que BATEU é preservada mesmo em vaga remota (não reduz score)', () => {
  const rs: MatchReason[] = [
    { label: 'Localização', matched: true, weight: 15, detail: 'A vaga é na sua cidade.' },
  ]
  const out = reconcileRemoteReasons(rs, VAGA_REMOTA, ACEITA_REMOTO)
  assertEquals(out.length, 1)
  assertEquals(somaMatched(out), 15)
})

Deno.test('work_mode em EN (schema relacional) é normalizado antes de comparar', () => {
  const rs: MatchReason[] = [
    { label: 'Modelo', matched: false, weight: 15, detail: 'Você prefere remoto, mas a vaga é remoto.' },
  ]
  const out = reconcileRemoteReasons(rs, VAGA_REMOTA, { work_models: ['remote'] })
  assertEquals(out[0].matched, true)
})
