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
import {
  isScenarioC,
  reconcileRemoteReasons,
  reconcileSkillsReason,
  type MatchReason,
} from './reasons.ts'

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

Deno.test('linha real de prod: vaga remota deixa de perder ponto por cidade', () => {
  const out = reconcileRemoteReasons(REASONS_REAIS, VAGA_REMOTA, ACEITA_REMOTO)

  // MUDANÇA DELIBERADA (29/07). Antes a linha era REMOVIDA e o score ficava em
  // 75 — a penalidade só tinha ficado invisível, e a vaga remota continuava
  // tetando 15 pontos abaixo da mesma vaga na cidade da pessoa. Agora a
  // dimensão conta como acerto, que é o "Esperado" literal do achado P1-5.
  // 75 → 90. Se alguém "consertar" este número de volta, desfez a decisão.
  assertEquals(out.map((r) => r.label), ['Área', 'Tipo', 'Localização', 'Modelo', 'Skills'])
  const loc = out.find((r) => r.label === 'Localização')!
  assertEquals(loc.matched, true)
  assertEquals(loc.weight, 15)
  assertEquals(loc.detail, 'Vaga remota — de onde você mora não pesa aqui.')
  assertEquals(somaMatched(REASONS_REAIS), 75)
  assertEquals(somaMatched(out), 90)
})

Deno.test('Modelo com weight 0 da IA recebe o peso cheio, não herda o zero', () => {
  // A IA costuma mandar weight 0 quando considera a dimensão falha. Herdar isso
  // consertava o texto e deixava o ponto para trás — era metade do defeito.
  const rs: MatchReason[] = [
    { label: 'Modelo', matched: false, weight: 0, detail: 'Você prefere remoto, mas a vaga é remoto.' },
  ]
  const out = reconcileRemoteReasons(rs, VAGA_REMOTA, ACEITA_REMOTO)
  assertEquals(out[0].weight, 15)
  assertEquals(somaMatched(out), 30) // Modelo 15 + Localização 15 inserida
})

Deno.test('Localização ausente é inserida (duas vagas remotas pontuam igual)', () => {
  // 2.343 de 3.132 análises remotas trazem a linha; sem inserir, a mesma vaga
  // pontuaria diferente só porque o modelo emitiu a dimensão numa e não noutra.
  const semLocalizacao: MatchReason[] = [
    { label: 'Área', matched: true, weight: 30, detail: 'bate.' },
  ]
  const out = reconcileRemoteReasons(semLocalizacao, VAGA_REMOTA, ACEITA_REMOTO)
  assertEquals(out.map((r) => r.label), ['Área', 'Localização'])
  assertEquals(somaMatched(out), 45)
})

Deno.test('rótulo sem acento ou em caixa alta não escapa da reconciliação', () => {
  const rs: MatchReason[] = [
    { label: 'LOCALIZACAO ', matched: false, weight: 0, detail: 'Eusébio, CE não está entre suas cidades.' },
  ]
  const out = reconcileRemoteReasons(rs, VAGA_REMOTA, ACEITA_REMOTO)
  assertEquals(out.length, 1, 'não pode duplicar a dimensão')
  assertEquals(out[0].matched, true)
  assertEquals(somaMatched(out), 15)
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

Deno.test('vaga NÃO remota: Localização é preservada, só o Modelo reconcilia', () => {
  // A dispensa de Localização é EXCLUSIVA de vaga remota — em presencial e
  // híbrida a cidade pesa de verdade e não pode ser perdoada.
  const presencial = { id: 'job-2', work_model: 'presencial' }
  const rs: MatchReason[] = [
    { label: 'Localização', matched: false, weight: 0, detail: 'São Paulo não está entre suas cidades.' },
    { label: 'Modelo', matched: false, weight: 15, detail: 'Você prefere presencial, mas a vaga é presencial.' },
  ]
  const out = reconcileRemoteReasons(rs, presencial, ACEITA_REMOTO)
  assertEquals(out[0], rs[0], 'Localização não podia ser tocada em vaga presencial')
  assertEquals(out[1].matched, true)
  assertEquals(out.length, 2, 'não insere Localização fora de vaga remota')
})

Deno.test('vaga HÍBRIDA: a mesma contradição do achado, noutro modelo', () => {
  // Visto ao vivo em 30/07 verificando o flip: "Você prefere remoto ou híbrido,
  // mas a vaga é híbrida" — a pessoa prefere híbrido, a vaga É híbrida, e isso
  // contava como falha. Corrigir só o remoto teria deixado este vivo.
  const hibrida = { id: 'job-3', work_model: 'hibrido' }
  const rs: MatchReason[] = [
    { label: 'Modelo', matched: false, weight: 0, detail: 'Você prefere remoto ou híbrido, mas a vaga é híbrida.' },
  ]
  const out = reconcileRemoteReasons(rs, hibrida, ACEITA_REMOTO)
  assertEquals(out[0].matched, true)
  assertEquals(out[0].weight, 15)
  assertEquals(out[0].detail, 'Híbrido, que é como você prefere trabalhar.')
})

Deno.test('modelo que a pessoa NÃO aceita continua sendo falha', () => {
  const soRemoto = { work_models: ['remoto'] }
  const presencial = { id: 'job-4', work_model: 'presencial' }
  const rs: MatchReason[] = [
    { label: 'Modelo', matched: false, weight: 15, detail: 'Você prefere remoto, mas a vaga é presencial.' },
  ]
  assertEquals(reconcileRemoteReasons(rs, presencial, soRemoto), rs)
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

// ────────────────────────────────────────────────────────────────────────────
// Skills — achado A4 do relatório de UX de 03/08/2026
//
// Os fixtures NÃO são inventados: as frases abaixo são os `detail` reais da
// dimensão Skills em `match_analyses`, com a contagem medida em 04/08/2026, e
// os perfis são os dois usuários identificados na sessão do relatório.
// ────────────────────────────────────────────────────────────────────────────

/** Usuária do A3 — 6 linhas reais em `profile_skills` (user fd768ecc…). */
const SKILLS_A3 = ['Power BI', 'SQL', 'Python', 'Excel Avancado', 'Estatistica', 'Gestao de Processos']
/** Usuário do A4 — 5 linhas reais (user c287ea53…). */
const SKILLS_A4 = ['Excel', 'Power BI', 'C#', 'Marketing Digital', 'Databricks']

/**
 * Família (A): NEGA que a pessoa tenha declarado skills. É o defeito — falso
 * para quem tem skills. Contagem real em produção ao lado.
 */
const NEGA_EXISTENCIA: string[] = [
  'Você não declarou skills específicas para comparar.', // 11.086
  'Você não declarou skills para comparação.', //             1.710
  'Você não possui skills específicas para comparação.', //      667
  'Você não possui skills específicas para comparar.', //        360
  'Você não declarou skills específicas para comparação.', //    276
  'Você não possui skills específicas para comparar com a vaga.', //      148
  'Você não possui skills específicas para comparação com a vaga.', //    125
  // Achadas só na varredura da CAUDA — a regra antiga (por verbo) deixava passar.
  'Você não possui skills técnicas para comparar.', //            52
  'Não há skills específicas para comparar.', //                  64
  'Você não possui skills técnicas para comparação.', //          31
  'Você não possui skills declaradas para comparação.', //        29
  'Você não declarou habilidades específicas para comparação.', // 33
  'Você não tem skills específicas para comparar com a vaga.', //   9
  'Não há skills específicas no seu perfil para comparar.', //      2
  'Você não possui skills em inglês para comparação.', //           1
]

/**
 * Família (B): diz que as skills NÃO BATERAM. É VERDADE para quem tem skills e
 * NÃO pode ser reescrita — a de "Excel" é inclusive a melhor frase do conjunto,
 * porque nomeia a skill.
 */
const NAO_BATEU: string[] = [
  'Nenhuma skill declarada bate com os requisitos da vaga.', //          956
  'Você não possui skills que correspondem aos requisitos da vaga.', //  947
  'Nenhuma skill sua aparece nos requisitos da vaga.', //                717
  'Você não possui skills relacionadas aos requisitos da vaga.', //      599
  'Você não possui skills que batem com os requisitos da vaga.', //      529
  'Nenhuma das suas skills aparece nos requisitos da vaga.', //          519
  'Nenhuma skill do seu perfil aparece nos requisitos da vaga.', //      462
  'Você não possui as skills exigidas para a vaga.', //                  354
  'Você não possui skills que atendem aos requisitos da vaga.', //       315
  'Você não possui skills que correspondam aos requisitos da vaga.', //  250
  'Nenhuma skill sua aparece nos requisitos desta vaga.', //             248
  'Você não possui skills relacionadas à vaga.', //                      237
  'Você não possui skills que se aplicam a esta vaga.', //               191
  'Nenhuma das suas skills aparece nos requisitos desta vaga.', //       190
  'Você não possui as skills técnicas exigidas para a vaga.', //         141
  'Excel não aparece nos requisitos desta vaga.', //                     141
  'Nenhuma skill declarada aparece nos requisitos da vaga.', //          117
  // Estas a regra ANTIGA (por verbo) reescrevia por engano — são comparação.
  'Você não declarou skills que batem com os requisitos da vaga.', //     47
  'Você não possui skills específicas para a vaga.', //                   67
  'Você não possui skills específicas para esta vaga.', //                47
  'Nenhuma skill se aplica aos requisitos da vaga.', //                   93
  'Você não possui skills relacionadas a Engenharia Civil.', //           57
  'Nenhuma skill da vaga aparece no seu perfil.', //                      90
  'Atendimento ao cliente não aparece nos requisitos desta vaga.', //     90
  // Grupo em que quem não tem skills é a VAGA, não a pessoa — reescrever
  // culparia o candidato por um anúncio mal escrito. ~73 linhas somadas.
  'Não há requisitos de skills para comparar.', //                        45
  'Não há skills específicas na vaga para comparar.', //                  22
  'Não há skills na vaga para comparar.', //                               6
  'Não há skills relevantes na vaga para comparar.', //                    5
  'Não há skills específicas na vaga para comparação.', //                 2
  'Não há skills na vaga para comparação.', //                             2
  'Nenhuma skill foi exigida na vaga para comparação.', //                 1
  'Nenhuma skill da vaga foi especificada para comparação.', //            1
  'Não há skills requeridas na vaga para comparar.', //                    1
  // Grupo que só a guarda de "menção a skill" segura: o `detail` fala de
  // REQUISITO ou nomeia a skill sem usar a palavra "skill". Reais em produção.
  'Não há requisitos específicos para comparar.', //                      23
  'Não há requisitos técnicos para comparar.', //                          4
  'Pacote Office básico não é suficiente para comparação.', //             1
  'Pacote Office não é suficiente para comparar com os requisitos da vaga.', // 1
]

const comSkills = (detail: string, matched = false, weight = 0): MatchReason[] => [
  { label: 'Área', matched: true, weight: 30, detail: 'Tecnologia bate com seu interesse.' },
  { label: 'Tipo', matched: true, weight: 20, detail: 'Estágio é o tipo que você procura.' },
  { label: 'Skills', matched, weight, detail },
]

Deno.test('A4: TODAS as frases que negam existência (12 variantes reais) são corrigidas', () => {
  for (const frase of NEGA_EXISTENCIA) {
    const out = reconcileSkillsReason(comSkills(frase), SKILLS_A4)
    const skills = out.find((r) => r.label === 'Skills')!
    assertEquals(
      skills.detail !== frase,
      true,
      `frase não corrigida: "${frase}"`,
    )
    assertEquals(
      skills.detail,
      'Você declarou Excel, Power BI e C# e mais 2 — não encontrei essas skills nos requisitos desta vaga.',
    )
  }
})

Deno.test('A4: as 25 frases de "não bateu" são PRESERVADAS (são verdade)', () => {
  // Reescrever estas destruiria informação correta. A de "Excel não aparece nos
  // requisitos desta vaga" é a MELHOR frase do conjunto — nomeia a skill.
  for (const frase of NAO_BATEU) {
    const entrada = comSkills(frase)
    const out = reconcileSkillsReason(entrada, SKILLS_A4)
    assertEquals(out, entrada, `frase indevidamente reescrita: "${frase}"`)
    assertEquals(out === entrada, true, 'tem que devolver a MESMA referência')
  }
})

Deno.test('A4: o SCORE não muda — matched e weight são preservados', () => {
  // A correção é de TEXTO. Se algum dia ela mexer no score, este teste cai.
  const somaMatchedLocal = (rs: MatchReason[]) =>
    rs.filter((r) => r.matched).reduce((s, r) => s + Math.max(0, r.weight), 0)
  for (const frase of NEGA_EXISTENCIA) {
    const entrada = comSkills(frase, false, 0)
    const out = reconcileSkillsReason(entrada, SKILLS_A3)
    assertEquals(somaMatchedLocal(out), somaMatchedLocal(entrada))
    assertEquals(somaMatchedLocal(out), 50)
    const skills = out.find((r) => r.label === 'Skills')!
    assertEquals(skills.matched, false)
    assertEquals(skills.weight, 0)
  }
})

Deno.test('A4: quem NÃO declarou skills continua lendo a verdade', () => {
  // A frase só é mentira pra quem tem skills. Pra quem não tem, ela é correta e
  // não pode ser trocada por "Você declarou  — ...".
  const entrada = comSkills('Você não declarou skills específicas para comparar.')
  assertEquals(reconcileSkillsReason(entrada, []), entrada)
  assertEquals(reconcileSkillsReason(entrada, ['', '   ']), entrada, 'nome vazio não conta como skill')
})

Deno.test('A4: matched=true nunca é tocado (reescrever acerto só pioraria)', () => {
  const entrada = comSkills('Você não declarou skills específicas para comparar.', true, 10)
  assertEquals(reconcileSkillsReason(entrada, SKILLS_A4), entrada)
})

Deno.test('A4: dimensão AUSENTE é inserida com weight 0 (é como o eixo "sumiu" no A3)', () => {
  const semSkills: MatchReason[] = [
    { label: 'Área', matched: true, weight: 30, detail: 'bate.' },
    { label: 'Tipo', matched: true, weight: 20, detail: 'bate.' },
  ]
  const out = reconcileSkillsReason(semSkills, SKILLS_A3)
  assertEquals(out.map((r) => r.label), ['Área', 'Tipo', 'Skills'])
  const inserida = out[2]
  assertEquals(inserida.matched, false)
  assertEquals(inserida.weight, 0, 'inserir não pode dar nem tirar ponto')
  assertEquals(
    inserida.detail,
    'Você declarou Power BI, SQL e Python e mais 3 — não encontrei essas skills nos requisitos desta vaga.',
  )
})

Deno.test('A4: inserção para quem não tem skills vira convite, não acusação', () => {
  const semSkills: MatchReason[] = [{ label: 'Área', matched: true, weight: 30, detail: 'bate.' }]
  const out = reconcileSkillsReason(semSkills, [])
  assertEquals(out[1].detail, 'Adicione suas habilidades pra eu comparar com o que a vaga pede.')
  assertEquals(out[1].weight, 0)
})

Deno.test('A4: variações de rótulo não escapam (Skills/Ferramentas, Habilidades, caixa)', () => {
  // "Skills/Ferramentas" existe em produção (1 ocorrência) e escaparia de um
  // casamento por string exata — a mesma classe de furo que `canonical` fechou
  // para Localização.
  for (const label of ['Skills', 'SKILLS ', 'Skills/Ferramentas', 'Habilidades', 'habilidades']) {
    const entrada: MatchReason[] = [
      { label, matched: false, weight: 0, detail: 'Você não declarou skills específicas para comparar.' },
    ]
    const out = reconcileSkillsReason(entrada, SKILLS_A4)
    assertEquals(out.length, 1, `duplicou a dimensão para o rótulo "${label}"`)
    assertEquals(out[0].label, label, 'o rótulo original é preservado')
    assertEquals(out[0].detail?.startsWith('Você declarou'), true, `rótulo "${label}" escapou`)
  }
})

Deno.test('A4: singular quando é uma skill só', () => {
  const out = reconcileSkillsReason(
    comSkills('Você não declarou skills específicas para comparar.'),
    ['Excel'],
  )
  assertEquals(
    out.find((r) => r.label === 'Skills')!.detail,
    'Você declarou Excel — não encontrei essa skill nos requisitos desta vaga.',
  )
})

Deno.test('A4: nome de skill absurdamente longo não estoura o cartão', () => {
  const gigante = Array.from({ length: 3 }, (_, i) => `${'x'.repeat(90)}${i}`)
  const out = reconcileSkillsReason(
    comSkills('Você não declarou skills específicas para comparar.'),
    gigante,
  )
  const detail = out.find((r) => r.label === 'Skills')!.detail!
  assertEquals(detail.length <= 200, true, `detail com ${detail.length} chars`)
  assertEquals(detail, 'Suas skills declaradas não aparecem nos requisitos desta vaga.')
})

Deno.test('A4: sem mudança, devolve a MESMA referência (cache não re-deriva score)', () => {
  // O caminho de cache do index.ts recalcula o score sempre que o array troca.
  // Preservar a referência é o que garante "correção sem efeito colateral".
  const entrada = comSkills('Excel não aparece nos requisitos desta vaga.')
  assertEquals(reconcileSkillsReason(entrada, SKILLS_A4) === entrada, true)
  assertEquals(reconcileSkillsReason([], SKILLS_A4).length, 0, 'array vazio não ganha dimensão')
})

// ────────────────────────────────────────────────────────────────────────────
// Cenário C — a linha de score 50 que o caminho de cache zerava
// ────────────────────────────────────────────────────────────────────────────

const CENARIO_C: MatchReason[] = [
  {
    label: 'Sem perfil',
    matched: false,
    weight: 0,
    detail: 'Defina seus objetivos ou complete seu perfil para ter um match mais preciso.',
  },
]

Deno.test('Cenário C é reconhecido', () => {
  assertEquals(isScenarioC(CENARIO_C), true)
  assertEquals(isScenarioC(comSkills('x')), false)
  assertEquals(isScenarioC([{ label: 'Sem perfil', matched: true, weight: 0 }]), false)
})

Deno.test('Cenário C: NENHUM reconciliador encosta (senão o cache serve 0 no lugar de 50)', () => {
  // Medido em 04/08/2026: 872 linhas de Cenário C em `match_analyses` são de
  // usuários que HOJE têm work_models — passam pelo `aceitaEsteModelo` e caíam
  // no laço. Vaga remota era o pior caso: inseria Localização matched=true e o
  // cache devolvia 15.
  assertEquals(reconcileRemoteReasons(CENARIO_C, VAGA_REMOTA, ACEITA_REMOTO), CENARIO_C)
  assertEquals(
    reconcileRemoteReasons(CENARIO_C, VAGA_REMOTA, ACEITA_REMOTO) === CENARIO_C,
    true,
    'tem que ser a MESMA referência, senão o index.ts re-deriva o score',
  )
  assertEquals(reconcileSkillsReason(CENARIO_C, SKILLS_A3) === CENARIO_C, true)
})
