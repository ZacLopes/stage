// compare.ts
//
// Compara outputs/ (geradas por run_extraction.ts) contra ground_truth/
// (criadas manualmente). Produz relatório agregado:
//   - % de campos corretos por seção
//   - Confidence_global médio
//   - Top 5 erros sistemáticos
//   - Pass/fail por CV adversarial (fail é bloqueante)
//
// Uso:
//   cd career_gamification/golden_set
//   deno run --allow-read scripts/compare.ts
//
// Lê adversarial flag de cvs/README.md ou de ground_truth/cv_NNN.json
// (campo "_adversarial": true).

const ROOT = new URL('../', import.meta.url)
const OUTPUTS_DIR = new URL('./outputs/', ROOT)
const GROUND_TRUTH_DIR = new URL('./ground_truth/', ROOT)

interface FieldMatch {
  section: string
  field: string
  expected: any
  actual: any
  matched: boolean
}

interface CvComparison {
  cv_id: string
  adversarial: boolean
  matches: FieldMatch[]
  total: number
  correct: number
  pct: number
  confidence_global: number | null
  status: 'pass' | 'fail'
}

function normalize(v: any): any {
  if (typeof v === 'string') return v.trim().toLowerCase()
  return v
}

function fieldsEqual(a: any, b: any): boolean {
  if (a == null && b == null) return true
  if (a == null || b == null) return false
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false
    return a.every((x, i) => fieldsEqual(x, b[i]))
  }
  if (typeof a === 'object' && typeof b === 'object') {
    const ka = Object.keys(a).filter(k => !k.startsWith('_'))
    const kb = Object.keys(b).filter(k => !k.startsWith('_'))
    if (ka.length !== kb.length) return false
    return ka.every(k => fieldsEqual(a[k], b[k]))
  }
  return normalize(a) === normalize(b)
}

function compareSection(
  cvId: string,
  section: string,
  expected: any,
  actual: any,
  matches: FieldMatch[],
) {
  if (typeof expected !== 'object' || expected === null) {
    matches.push({ section, field: section, expected, actual, matched: fieldsEqual(expected, actual) })
    return
  }

  if (Array.isArray(expected)) {
    // Compara por count + matching por título/nome principal (campo "title" ou "name")
    matches.push({
      section,
      field: `${section}.length`,
      expected: expected.length,
      actual: Array.isArray(actual) ? actual.length : 0,
      matched: Array.isArray(actual) && actual.length === expected.length,
    })
    for (let i = 0; i < expected.length; i++) {
      const e = expected[i]
      const a = Array.isArray(actual) ? actual[i] : undefined
      if (typeof e === 'object' && e !== null) {
        for (const key of Object.keys(e)) {
          if (key.startsWith('_')) continue
          matches.push({
            section,
            field: `${section}[${i}].${key}`,
            expected: e[key],
            actual: a?.[key],
            matched: fieldsEqual(e[key], a?.[key]),
          })
        }
      }
    }
    return
  }

  for (const key of Object.keys(expected)) {
    if (key.startsWith('_')) continue
    matches.push({
      section,
      field: `${section}.${key}`,
      expected: expected[key],
      actual: actual?.[key],
      matched: fieldsEqual(expected[key], actual?.[key]),
    })
  }
}

async function loadJson(path: URL): Promise<any> {
  try {
    return JSON.parse(await Deno.readTextFile(path))
  } catch {
    return null
  }
}

async function listGroundTruth(): Promise<string[]> {
  const out: string[] = []
  try {
    for await (const entry of Deno.readDir(GROUND_TRUTH_DIR)) {
      if (entry.isFile && entry.name.endsWith('.json')) {
        out.push(entry.name.replace(/\.json$/, ''))
      }
    }
  } catch {
    // empty
  }
  return out.sort()
}

async function compareOne(cvId: string): Promise<CvComparison | null> {
  const expected = await loadJson(new URL(`${cvId}.json`, GROUND_TRUTH_DIR))
  const outputResp = await loadJson(new URL(`${cvId}_output.json`, OUTPUTS_DIR))
  if (!expected) return null

  const actual = outputResp?.profile_data ?? {}
  const adversarial = expected._adversarial === true
  const matches: FieldMatch[] = []

  for (const section of ['personal', 'experiences', 'education', 'languages', 'skills', 'certifications', 'projects', 'interests', 'awards', 'coursework']) {
    if (section in expected) {
      compareSection(cvId, section, expected[section], actual?.[section], matches)
    }
  }

  const total = matches.length
  const correct = matches.filter(m => m.matched).length
  const pct = total > 0 ? (correct / total) * 100 : 0

  return {
    cv_id: cvId,
    adversarial,
    matches,
    total,
    correct,
    pct,
    confidence_global: outputResp?.extraction_meta?.confidence_global ?? null,
    status: adversarial ? (pct >= 95 ? 'pass' : 'fail') : (pct >= 70 ? 'pass' : 'fail'),
  }
}

async function main() {
  const ids = await listGroundTruth()
  if (ids.length === 0) {
    console.log('Nenhum ground_truth/*.json encontrado. Crie pelo menos 1 antes de rodar compare.')
    return
  }

  const comps: CvComparison[] = []
  for (const id of ids) {
    const c = await compareOne(id)
    if (c) comps.push(c)
  }

  console.log('=== Per-CV ===')
  for (const c of comps) {
    const adv = c.adversarial ? '★' : ' '
    const tag = c.status === 'pass' ? 'PASS' : 'FAIL'
    const conf = c.confidence_global != null ? c.confidence_global.toFixed(2) : 'n/a'
    console.log(`${adv} ${tag} ${c.cv_id} • ${c.correct}/${c.total} (${c.pct.toFixed(1)}%) • conf=${conf}`)
  }

  console.log('\n=== Per-section ===')
  const bySection = new Map<string, { correct: number; total: number }>()
  for (const c of comps) {
    for (const m of c.matches) {
      const agg = bySection.get(m.section) ?? { correct: 0, total: 0 }
      agg.total++
      if (m.matched) agg.correct++
      bySection.set(m.section, agg)
    }
  }
  for (const [section, agg] of bySection.entries()) {
    const pct = agg.total > 0 ? (agg.correct / agg.total) * 100 : 0
    console.log(`  ${section.padEnd(15)} ${agg.correct}/${agg.total} (${pct.toFixed(1)}%)`)
  }

  console.log('\n=== Top 5 padrões de erro ===')
  const errorCounts = new Map<string, number>()
  for (const c of comps) {
    for (const m of c.matches) {
      if (!m.matched) {
        errorCounts.set(m.field, (errorCounts.get(m.field) ?? 0) + 1)
      }
    }
  }
  const top = Array.from(errorCounts.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
  for (const [field, count] of top) {
    console.log(`  ${field} → ${count} CV(s)`)
  }

  console.log('\n=== Resumo ===')
  const adversarials = comps.filter(c => c.adversarial)
  const adversarialFails = adversarials.filter(c => c.status === 'fail')
  const allPassCount = comps.filter(c => c.status === 'pass').length

  console.log(`Total: ${comps.length} CVs avaliados`)
  console.log(`Adversariais: ${adversarials.length} (${adversarialFails.length} FAIL)`)
  console.log(`Pass geral: ${allPassCount}/${comps.length}`)
  const confidences = comps.map(c => c.confidence_global).filter((c): c is number => c != null)
  if (confidences.length > 0) {
    console.log(`Confidence médio: ${(confidences.reduce((a, b) => a + b, 0) / confidences.length).toFixed(2)}`)
  }

  if (adversarialFails.length > 0) {
    console.log('\n⚠️  CVs ADVERSARIAIS FALHANDO — BLOQUEANTE pra deploy:')
    for (const c of adversarialFails) {
      console.log(`  - ${c.cv_id} (${c.pct.toFixed(1)}%)`)
    }
    Deno.exit(1)
  }
}

main().catch(e => {
  console.error('Fatal:', e)
  Deno.exit(1)
})
