// Bateria reguladora do pipeline ADAPT (R5).
//
// Por que existe: a R5 manda rodar `golden_set/` antes e depois de encostar no
// adapt. O golden_set que existia é do `extract-profile` (PDFs → perfil) e
// estava VAZIO — "golden_set limpo" era indistinguível de "não havia o que
// rodar". Esta bateria cobre o outro pipeline, o do adapt.
//
// O que ela protege: `validateAdaptationV2`, a barreira anti-invenção entre a
// resposta do modelo e o PDF que o recrutador lê. Cada caso é um par
// (input do candidato, resposta hipotética do modelo) + o veredito esperado.
//
// Duas direções, ambas necessárias:
//   • casos `rejeita`  → pegam o validador ficando FROUXO (invenção passa)
//   • casos `aceita`   → pegam o validador ficando ESTRITO (usuário legítimo
//                        fica sem currículo — foi o BLOQUEADOR C)
//
// O que ela NÃO cobre, e é honesto dizer: qualidade de escrita do modelo.
// Saber se os bullets ficaram melhores ou piores exige rodada real contra a
// OpenAI + julgamento humano. Isto aqui é determinístico, offline e de graça —
// roda em CI e em toda mudança no pipeline.
//
// Uso:
//   bash scripts/run_golden_set_adapt.sh
//
// Adicionar caso: crie um JSON em `cases/`. Ver README.md.

import {
  validateAdaptationV2,
  ValidationErrorV2,
} from '../../supabase/functions/adapt-resume-to-job/v2.ts'
import type {
  InputResumeV2,
  InputExperienceV2,
  InputEducationV2,
} from '../../supabase/functions/adapt-resume-to-job/v2.ts'
import { tokenize } from '../../supabase/functions/_shared/cv_text.ts'

// ── Tipos do caso ───────────────────────────────────────────────────────────

interface CaseFile {
  id: string
  adversarial?: boolean
  categoria: string
  porque: string
  adicionado_em?: string
  /** Partial de InputResumeV2 — o resto vem de `BASE_INPUT`. */
  input?: Record<string, unknown>
  /** Partial de `resume` — o resto é uma cópia FIEL do input. */
  candidate?: Record<string, unknown>
  /** extra_skills confirmadas pela pessoa na folha de extras. */
  extraSkills?: string[]
  espera: {
    resultado: 'aceita' | 'rejeita'
    campo?: string
    mensagem_contem?: string
  }
}

// ── Construção do input ─────────────────────────────────────────────────────

const BASE_INPUT: Omit<InputResumeV2, 'keywordPool'> = {
  userId: 'golden-set',
  fullName: 'Ana Ribeiro',
  email: 'ana.ribeiro@example.com',
  phone: '+5511987650143',
  linkedin: '',
  location: 'São Paulo, SP, BR',
  streetAddress: '',
  headline: '',
  language: 'pt',
  summary: '',
  skills: [],
  tools: [],
  experiences: [],
  education: [],
  languages: [],
  achievements: [],
  interests: [],
  certifications: [],
}

/** Pool de palavras conhecidas — espelha o `feed()` da produção. */
function buildKeywordPool(i: Omit<InputResumeV2, 'keywordPool'>): Set<string> {
  const pool = new Set<string>()
  const feed = (s?: string) => {
    for (const w of tokenize(s ?? '')) pool.add(w)
  }
  ;[...i.skills, ...i.tools, ...i.achievements, ...i.interests, ...i.certifications].forEach(feed)
  feed(i.summary)
  feed(i.headline)
  for (const e of i.experiences) {
    feed(e.role); feed(e.company)
    for (const b of e.bullets) feed(b.text)
  }
  for (const e of i.education) {
    feed(e.degree); feed(e.institution)
    ;[...e.majors, ...e.minors, ...e.activities].forEach(feed)
  }
  return pool
}

function buildInput(partial: Record<string, unknown> = {}): InputResumeV2 {
  const merged = { ...BASE_INPUT, ...partial } as Omit<InputResumeV2, 'keywordPool'>
  return { ...merged, keywordPool: buildKeywordPool(merged) }
}

/**
 * Resposta FIEL do modelo: devolve exatamente o que entrou.
 * Tem de passar em tudo — é a linha de base contra excesso de rigor.
 * Cada caso sobrescreve só o campo que quer exercitar.
 */
function faithfulCandidate(input: InputResumeV2): Record<string, unknown> {
  return {
    fullName: input.fullName,
    email: input.email,
    linkedin: input.linkedin,
    streetAddress: input.streetAddress,
    headline: input.headline,
    summary: input.summary,
    skills: [...input.skills],
    tools: [...input.tools],
    experiences: input.experiences.map((e: InputExperienceV2) => ({
      company: e.company,
      role: e.role,
      period: e.period,
      location: e.location,
      bullets: e.bullets.map((b) => ({
        text: b.text,
        _action: 'kept',
        _source_bullet_id: b.id,
      })),
    })),
    education: input.education.map((e: InputEducationV2) => ({
      institution: e.institution,
      degree: e.degree,
      period: e.period,
      location: e.location,
      majors: [...e.majors],
      minors: [...e.minors],
      activities: [...e.activities],
      gpa: e.gpa,
    })),
    languages: input.languages.map((l) => ({ name: l.name, proficiency: l.proficiency })),
  }
}

// ── Execução ────────────────────────────────────────────────────────────────

interface Result {
  id: string
  adversarial: boolean
  categoria: string
  ok: boolean
  detalhe: string
}

function runCase(c: CaseFile): Result {
  const input = buildInput(c.input)
  const candidate = { resume: { ...faithfulCandidate(input), ...(c.candidate ?? {}) } }

  let threw: ValidationErrorV2 | null = null
  try {
    validateAdaptationV2(input, candidate, undefined, c.extraSkills ?? [])
  } catch (e) {
    if (e instanceof ValidationErrorV2) threw = e
    else return { id: c.id, adversarial: !!c.adversarial, categoria: c.categoria, ok: false, detalhe: `erro inesperado: ${e}` }
  }

  const base = { id: c.id, adversarial: !!c.adversarial, categoria: c.categoria }

  if (c.espera.resultado === 'aceita') {
    return threw === null
      ? { ...base, ok: true, detalhe: 'passou, como esperado' }
      : { ...base, ok: false, detalhe: `esperava ACEITAR, mas rejeitou em "${threw.field}": ${threw.message}` }
  }

  // espera rejeitar
  if (threw === null) {
    return { ...base, ok: false, detalhe: 'esperava REJEITAR, mas passou (invenção escapou)' }
  }
  if (c.espera.campo && threw.field !== c.espera.campo) {
    return { ...base, ok: false, detalhe: `rejeitou pelo campo errado: esperava "${c.espera.campo}", veio "${threw.field}"` }
  }
  if (c.espera.mensagem_contem && !threw.message.includes(c.espera.mensagem_contem)) {
    return { ...base, ok: false, detalhe: `mensagem não bate: esperava conter "${c.espera.mensagem_contem}", veio "${threw.message}"` }
  }
  return { ...base, ok: true, detalhe: `rejeitou em "${threw.field}", como esperado` }
}

// ── Main ────────────────────────────────────────────────────────────────────

const casesDir = new URL('./cases/', import.meta.url)
const files: string[] = []
for await (const e of Deno.readDir(casesDir)) {
  if (e.isFile && e.name.endsWith('.json')) files.push(e.name)
}
files.sort()

if (files.length === 0) {
  console.error('✗ golden_set/adapt/cases/ está VAZIO — a bateria não mede nada.')
  Deno.exit(1)
}

const results: Result[] = []
for (const f of files) {
  const raw = await Deno.readTextFile(new URL(`./cases/${f}`, import.meta.url))
  results.push(runCase(JSON.parse(raw) as CaseFile))
}

console.log(`\nGOLDEN SET — pipeline adapt (validateAdaptationV2)\n${'─'.repeat(72)}`)
for (const r of results) {
  const mark = r.ok ? '✓' : '✗'
  const tag = r.adversarial ? '[ADV]' : '     '
  console.log(`${mark} ${tag} ${r.id.padEnd(42)} ${r.ok ? '' : '← ' + r.detalhe}`)
}

const failed = results.filter((r) => !r.ok)
const advFailed = failed.filter((r) => r.adversarial)
console.log('─'.repeat(72))
console.log(
  `${results.length} casos · ${results.length - failed.length} ok · ${failed.length} falhando` +
  ` (${results.filter((r) => r.adversarial).length} adversariais)`,
)

if (failed.length > 0) {
  console.error(`\n✗ GOLDEN_SET_ADAPT_FAILED`)
  if (advFailed.length > 0) {
    console.error(`  ${advFailed.length} caso(s) ADVERSARIAL falhando — bloqueante, não faça deploy.`)
  }
  Deno.exit(1)
}
console.log('\n✓ GOLDEN_SET_ADAPT_OK')
