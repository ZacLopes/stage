// Script standalone para backfill de `imported_resume.parsed` via
// `parse-cv-pdf` (GPT-4o com PDF nativo). Substitui o text-only backfill
// pros CVs antigos que têm `saved_resumes` com source='imported' — PDF
// processado direto pela IA tem fidelidade muito maior que Syncfusion +
// GPT-4o-mini text-only.
//
// Uso:
//   # Dry-run em 5 users (lista candidatos, NÃO grava):
//   deno run --allow-env --allow-net supabase/scripts/backfill_parsed_cvs_pdf.ts
//
//   # Apply em 5 users (re-processa com PDF):
//   deno run --allow-env --allow-net supabase/scripts/backfill_parsed_cvs_pdf.ts --apply
//
//   # Limite custom + filtro por qualidade:
//   deno run --allow-env --allow-net supabase/scripts/backfill_parsed_cvs_pdf.ts --apply --limit=50 --zero-exp-only
//
//   # Processar 1 user específico:
//   deno run --allow-env --allow-net supabase/scripts/backfill_parsed_cvs_pdf.ts --apply --only=<user_id>
//
// Variáveis de ambiente:
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//
// Filtros:
//   - User precisa ter saved_resumes.source='imported' (pra ter PDF)
//   - Default: pula quem já tem parser_source='pdf'
//   - --force: re-processa mesmo quem já tem
//   - --zero-exp-only: só pega users com experiences=0 no parsed atual
//     (target alto impacto — esses provavelmente vão de 0 → 3+)
//
// Custo: ~$0.0045 por CV (GPT-4o, ~250 input + 800 output tokens).
//   100 users = $0.45.

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('ERRO: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios.')
  Deno.exit(1)
}

const args = Deno.args
const dryRun = !args.includes('--apply')
const force = args.includes('--force')
const zeroExpOnly = args.includes('--zero-exp-only')
const limitArg = args.find((a) => a.startsWith('--limit='))
const limit = limitArg ? parseInt(limitArg.split('=')[1], 10) : 5
const onlyArg = args.find((a) => a.startsWith('--only='))
const onlyUserId = onlyArg ? onlyArg.split('=')[1] : null

const STORAGE_BUCKET = 'resumes'
const PROJECT_REF = SUPABASE_URL.match(/https:\/\/([^.]+)\./)?.[1] ?? ''

console.log('━'.repeat(60))
console.log(`backfill_parsed_cvs_pdf — modo: ${dryRun ? 'DRY-RUN' : 'APPLY (gravando!)'}`)
console.log(`limit=${limit} force=${force} zero-exp-only=${zeroExpOnly} only=${onlyUserId ?? '(não)'}`)
console.log('━'.repeat(60))

async function sb(path: string, init?: RequestInit): Promise<Response> {
  return await fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'X-Service-Role-Key': SERVICE_ROLE_KEY,
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  })
}

// Lista candidatos via SQL (RPC genérica não tá disponível, mas o REST aceita
// filtros via PostgREST). Como precisamos de JOIN, usamos uma RPC seria ideal —
// no lugar, fazemos duas queries.
console.log('\n→ Listando candidatos...')

const userProfilesUrl = onlyUserId
  ? `/rest/v1/user_profiles?select=id,email,gamification_data&id=eq.${onlyUserId}`
  : `/rest/v1/user_profiles?select=id,email,gamification_data` +
    `&gamification_data->imported_resume->>raw_text=not.is.null` +
    (force ? '' : `&or=(gamification_data->imported_resume->>parser_source.is.null,gamification_data->imported_resume->>parser_source.neq.pdf)`) +
    `&limit=${limit * 3}` // pega mais que limit pra compensar quem não tem saved_resume

const profilesResp = await sb(userProfilesUrl)
if (!profilesResp.ok) {
  console.error(`ERRO ao listar profiles: ${profilesResp.status} ${await profilesResp.text()}`)
  Deno.exit(1)
}
const allProfiles: Array<{
  id: string
  email: string | null
  gamification_data: any
}> = await profilesResp.json()

// Pra cada um, busca o saved_resume importado mais recente
type Candidate = {
  id: string
  email: string | null
  file_path: string
  parsed: any
  raw_text: string
  parser_source: string | null
  n_exp_before: number
  n_edu_before: number
}
const candidates: Candidate[] = []

for (const p of allProfiles) {
  const imported = p.gamification_data?.imported_resume
  if (!imported || typeof imported.raw_text !== 'string' || imported.raw_text.length < 200) continue

  const resumeResp = await sb(
    `/rest/v1/saved_resumes?select=file_path,created_at&user_id=eq.${p.id}` +
    `&source=in.(imported,manual)&order=created_at.desc&limit=1`,
  )
  if (!resumeResp.ok) continue
  const resumes: Array<{ file_path: string; created_at: string }> = await resumeResp.json()
  if (resumes.length === 0) continue

  const parsed = imported.parsed ?? {}
  const nExp = Array.isArray(parsed.experiences) ? parsed.experiences.length : 0
  const nEdu = Array.isArray(parsed.education) ? parsed.education.length : 0

  if (zeroExpOnly && nExp > 0) continue

  candidates.push({
    id: p.id,
    email: p.email,
    file_path: resumes[0].file_path,
    parsed,
    raw_text: imported.raw_text,
    parser_source: imported.parser_source ?? null,
    n_exp_before: nExp,
    n_edu_before: nEdu,
  })

  if (candidates.length >= limit) break
}

console.log(`  ${candidates.length} candidato(s) com PDF disponível.\n`)
if (candidates.length === 0) {
  console.log('Nada a fazer.')
  Deno.exit(0)
}

// Processa um a um.
let i = 0
const results: Array<{
  email: string | null
  status: 'success' | 'error' | 'skipped'
  n_exp_before: number
  n_exp_after: number
  n_edu_before: number
  n_edu_after: number
  error?: string
}> = []

for (const c of candidates) {
  i++
  const tag = `[${i}/${candidates.length}]`
  console.log(`${tag} ${c.email ?? '(sem email)'} — id=${c.id.slice(0, 8)} pdf=${c.file_path.slice(-30)}`)
  console.log(`     ↳ antes: experiences=${c.n_exp_before} education=${c.n_edu_before} parser=${c.parser_source ?? '(text-only)'}`)

  if (dryRun) {
    console.log(`     ↳ DRY-RUN — baixaria PDF, chamaria parse-cv-pdf`)
    results.push({
      email: c.email,
      status: 'success',
      n_exp_before: c.n_exp_before,
      n_exp_after: -1,
      n_edu_before: c.n_edu_before,
      n_edu_after: -1,
    })
    continue
  }

  // 1. Baixa o PDF via Storage API.
  const downloadUrl = `${SUPABASE_URL}/storage/v1/object/${STORAGE_BUCKET}/${c.file_path}`
  const pdfResp = await fetch(downloadUrl, {
    headers: { 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` },
  })
  if (!pdfResp.ok) {
    console.log(`     ↳ ERRO ao baixar PDF: ${pdfResp.status} ${(await pdfResp.text()).slice(0, 100)}`)
    results.push({
      email: c.email,
      status: 'error',
      n_exp_before: c.n_exp_before,
      n_exp_after: c.n_exp_before,
      n_edu_before: c.n_edu_before,
      n_edu_after: c.n_edu_before,
      error: `storage_download:${pdfResp.status}`,
    })
    continue
  }
  const pdfBytes = new Uint8Array(await pdfResp.arrayBuffer())
  if (pdfBytes.length === 0) {
    console.log(`     ↳ ERRO: PDF vazio`)
    results.push({
      email: c.email,
      status: 'error',
      n_exp_before: c.n_exp_before,
      n_exp_after: c.n_exp_before,
      n_edu_before: c.n_edu_before,
      n_edu_after: c.n_edu_before,
      error: 'pdf_empty',
    })
    continue
  }

  // Base64 encode (Deno tem btoa pra ASCII, mas precisa converter binary).
  let binary = ''
  for (let j = 0; j < pdfBytes.length; j++) binary += String.fromCharCode(pdfBytes[j])
  const pdfBase64 = btoa(binary)

  console.log(`     ↳ PDF=${(pdfBytes.length / 1024).toFixed(0)}KB → chamando parse-cv-pdf...`)

  // 2. Chama parse-cv-pdf.
  const parseResp = await sb(`/functions/v1/parse-cv-pdf`, {
    method: 'POST',
    body: JSON.stringify({
      user_id: c.id,
      pdf_base64: pdfBase64,
      raw_text_fallback: c.raw_text,
      force: true, // força sobrescrever
    }),
  })
  const parseData = await parseResp.json().catch(() => ({}))

  if (!parseResp.ok) {
    console.log(`     ↳ ERRO parse-cv-pdf: ${parseResp.status} ${JSON.stringify(parseData).slice(0, 200)}`)
    results.push({
      email: c.email,
      status: 'error',
      n_exp_before: c.n_exp_before,
      n_exp_after: c.n_exp_before,
      n_edu_before: c.n_edu_before,
      n_edu_after: c.n_edu_before,
      error: `parse-cv-pdf:${parseResp.status}:${parseData?.error ?? 'unknown'}`,
    })
    continue
  }

  const newParsed = parseData?.parsed ?? {}
  const newExp = Array.isArray(newParsed.experiences) ? newParsed.experiences.length : 0
  const newEdu = Array.isArray(newParsed.education) ? newParsed.education.length : 0
  const fieldsFilled = parseData?.fields_filled ?? 0
  const warnings: string[] = parseData?.warnings ?? []

  const expDelta = newExp - c.n_exp_before
  const eduDelta = newEdu - c.n_edu_before
  const arrow = (d: number) => d > 0 ? `+${d}` : `${d}`

  console.log(
    `     ↳ OK fields=${fieldsFilled} ` +
    `experiences=${c.n_exp_before}→${newExp}(${arrow(expDelta)}) ` +
    `education=${c.n_edu_before}→${newEdu}(${arrow(eduDelta)})` +
    (warnings.length > 0 ? ` warnings=${warnings.length}` : ''),
  )

  results.push({
    email: c.email,
    status: 'success',
    n_exp_before: c.n_exp_before,
    n_exp_after: newExp,
    n_edu_before: c.n_edu_before,
    n_edu_after: newEdu,
  })

  // Rate limit: 1.5s entre chamadas (PDF é mais caro/lento que text).
  await new Promise((r) => setTimeout(r, 1500))
}

// Relatório.
console.log('\n' + '━'.repeat(60))
console.log('RELATÓRIO FINAL')
console.log('━'.repeat(60))
const succ = results.filter((r) => r.status === 'success').length
const errs = results.filter((r) => r.status === 'error').length
console.log(`  Sucessos: ${succ}`)
console.log(`  Erros: ${errs}`)

if (!dryRun) {
  const realSucc = results.filter((r) => r.status === 'success' && r.n_exp_after >= 0)
  if (realSucc.length > 0) {
    const expGained = realSucc.reduce((s, r) => s + (r.n_exp_after - r.n_exp_before), 0)
    const eduGained = realSucc.reduce((s, r) => s + (r.n_edu_after - r.n_edu_before), 0)
    const usersImproved = realSucc.filter((r) =>
      r.n_exp_after > r.n_exp_before || r.n_edu_after > r.n_edu_before
    ).length
    console.log(`  Total experiences ganhas: +${expGained}`)
    console.log(`  Total education ganhas: +${eduGained}`)
    console.log(`  Users com melhoria: ${usersImproved}/${realSucc.length}`)
  }
}

if (errs > 0) {
  console.log('\nErros:')
  for (const r of results.filter((r) => r.status === 'error')) {
    console.log(`  - ${r.email}: ${r.error}`)
  }
}

if (dryRun) {
  console.log('\n⚠️  DRY-RUN — nada foi gravado. Re-rode com --apply.')
} else {
  console.log('\n✅ Backfill PDF aplicado.')
}

void PROJECT_REF
