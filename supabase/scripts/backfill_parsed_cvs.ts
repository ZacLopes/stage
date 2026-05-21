// Script standalone para backfill de `imported_resume.parsed` nos
// user_profiles legados que têm `raw_text` mas nunca tiveram o parsing
// estruturado da F2 rodado. Roda manualmente do Mac do operador (não
// é Edge Function).
//
// Uso:
//   # Dry-run em 10 users (default: vê o que vai mudar, NÃO grava nada):
//   deno run --allow-env --allow-net supabase/scripts/backfill_parsed_cvs.ts
//
//   # Apply em 10 users (grava de verdade):
//   deno run --allow-env --allow-net supabase/scripts/backfill_parsed_cvs.ts --apply
//
//   # Apply em batch maior:
//   deno run --allow-env --allow-net supabase/scripts/backfill_parsed_cvs.ts --apply --limit=56
//
//   # Forçar reprocessamento de users que já têm parsed:
//   deno run --allow-env --allow-net supabase/scripts/backfill_parsed_cvs.ts --apply --force --limit=5
//
// Variáveis de ambiente necessárias (definir antes de rodar):
//   SUPABASE_URL                  ex: https://gaxfmniffjvwrwyunorl.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY     pega no dashboard Supabase → Settings → API
//
// Garantias:
// - Idempotente: skip se `parsed` já existe (a menos que --force).
// - Aditivo: só insere/atualiza imported_resume.parsed, não toca em raw_text
//   nem em qualquer outro campo de gamification_data.
// - Rate-limited: 1 req/segundo (não derruba a Edge Function nem estoura
//   quota OpenAI).
// - Sem dependência de novo código: chama a Edge Function parse-cv direto
//   via fetch (single source of truth pra lógica de parsing).
//
// Reverter: SQL único pra remover parsed dos usuários backfilled —
//   UPDATE user_profiles
//   SET gamification_data = jsonb_set(
//     gamification_data,
//     '{imported_resume}',
//     (gamification_data->'imported_resume') - 'parsed' - 'parsed_at'
//       - 'parser_version' - 'parser_model' - 'parsed_backfilled_at'
//   )
//   WHERE gamification_data->'imported_resume'->>'parsed_backfilled_at' IS NOT NULL;

interface BackfillResult {
  userId: string
  email: string | null
  status: 'success' | 'skipped_already_parsed' | 'skipped_no_raw_text' | 'error'
  fieldsFilled?: number
  rawTextLen?: number
  errorMessage?: string
  warnings?: string[]
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('ERRO: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios.')
  Deno.exit(1)
}

const args = Deno.args
const dryRun = !args.includes('--apply')
const force = args.includes('--force')
const limitArg = args.find((a) => a.startsWith('--limit='))
const limit = limitArg ? parseInt(limitArg.split('=')[1], 10) : 10
const onlyArg = args.find((a) => a.startsWith('--only='))
const onlyUserId = onlyArg ? onlyArg.split('=')[1] : null

console.log('━'.repeat(60))
console.log(`backfill_parsed_cvs — modo: ${dryRun ? 'DRY-RUN (sem escrita)' : 'APPLY (gravando!)'}`)
console.log(`limit=${limit} force=${force} only=${onlyUserId ?? '(não)'}`)
console.log('━'.repeat(60))

async function sb(path: string, init?: RequestInit): Promise<Response> {
  return await fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  })
}

// 1. Lista candidatos: user_profiles com raw_text >= 200 mas sem parsed.
//    (se --force, ignora a parte do "sem parsed").
const candidateFilter = force
  ? 'gamification_data->imported_resume->>raw_text=not.is.null'
  : 'and=(gamification_data->imported_resume->>raw_text.not.is.null,gamification_data->imported_resume->parsed.is.null)'

console.log('\n→ Buscando candidatos no banco...')
const listResp = await sb(
  `/rest/v1/user_profiles?select=id,email,gamification_data` +
  (onlyUserId ? `&id=eq.${onlyUserId}` : `&${candidateFilter}`) +
  `&limit=${limit}`,
)
if (!listResp.ok) {
  console.error(`ERRO ao listar: ${listResp.status} ${await listResp.text()}`)
  Deno.exit(1)
}
const candidates: Array<{
  id: string
  email: string | null
  gamification_data: any
}> = await listResp.json()

console.log(`  ${candidates.length} candidato(s) encontrado(s).\n`)
if (candidates.length === 0) {
  console.log('Nada a fazer.')
  Deno.exit(0)
}

// 2. Filtra os que realmente têm raw_text utilizável.
const ready = candidates.filter((u) => {
  const rawText = u.gamification_data?.imported_resume?.raw_text
  return typeof rawText === 'string' && rawText.length >= 200
})
console.log(`  ${ready.length} têm raw_text >= 200 chars (filtrados ${candidates.length - ready.length}).\n`)

// 3. Processa um a um, com 1 segundo de delay entre chamadas.
const results: BackfillResult[] = []
let i = 0
for (const u of ready) {
  i++
  const rawTextLen = u.gamification_data.imported_resume.raw_text.length
  const hasExistingParsed = u.gamification_data?.imported_resume?.parsed != null

  const tag = `[${i}/${ready.length}]`
  console.log(`${tag} ${u.email ?? '(sem email)'} — id=${u.id.slice(0, 8)} rawLen=${rawTextLen} hasParsed=${hasExistingParsed}`)

  if (hasExistingParsed && !force) {
    results.push({
      userId: u.id,
      email: u.email,
      status: 'skipped_already_parsed',
    })
    console.log(`     ↳ SKIP (já tem parsed; use --force pra reprocessar)`)
    continue
  }

  if (dryRun) {
    console.log(`     ↳ DRY-RUN — chamaria parse-cv via service-role`)
    results.push({
      userId: u.id,
      email: u.email,
      status: 'success',
      rawTextLen,
    })
    continue
  }

  // Chama a Edge Function parse-cv via service-role + user_id no body.
  try {
    const resp = await sb(`/functions/v1/parse-cv`, {
      method: 'POST',
      body: JSON.stringify({ user_id: u.id, force }),
    })
    const data = await resp.json().catch(() => ({}))

    if (!resp.ok) {
      console.log(`     ↳ ERRO HTTP ${resp.status}: ${JSON.stringify(data).slice(0, 200)}`)
      results.push({
        userId: u.id,
        email: u.email,
        status: 'error',
        errorMessage: `${resp.status}: ${JSON.stringify(data).slice(0, 200)}`,
      })
    } else {
      const fieldsFilled = data?.fields_filled ?? 0
      const warnings = data?.warnings ?? []
      console.log(`     ↳ OK fields_filled=${fieldsFilled}${warnings.length > 0 ? ` warnings=${warnings.length}` : ''}`)
      results.push({
        userId: u.id,
        email: u.email,
        status: 'success',
        fieldsFilled,
        rawTextLen,
        warnings: warnings.length > 0 ? warnings : undefined,
      })
    }
  } catch (e) {
    console.log(`     ↳ EXCEPTION: ${(e as Error).message}`)
    results.push({
      userId: u.id,
      email: u.email,
      status: 'error',
      errorMessage: (e as Error).message,
    })
  }

  // Rate limit: 1 req/segundo. Protege OpenAI quota + Edge Function.
  await new Promise((r) => setTimeout(r, 1000))
}

// 4. Relatório final.
console.log('\n' + '━'.repeat(60))
console.log('RELATÓRIO FINAL')
console.log('━'.repeat(60))
const success = results.filter((r) => r.status === 'success').length
const skipped = results.filter((r) => r.status === 'skipped_already_parsed').length
const errors = results.filter((r) => r.status === 'error').length
console.log(`  Sucessos: ${success}`)
console.log(`  Pulados (já tinham parsed): ${skipped}`)
console.log(`  Erros: ${errors}`)

const successResults = results.filter((r) => r.status === 'success' && r.fieldsFilled != null)
if (successResults.length > 0) {
  const avgFields = successResults.reduce((s, r) => s + (r.fieldsFilled ?? 0), 0) / successResults.length
  console.log(`  Média de fields_filled: ${avgFields.toFixed(1)} / 11`)
}

if (errors > 0) {
  console.log('\nErros:')
  for (const r of results.filter((r) => r.status === 'error')) {
    console.log(`  - ${r.email ?? r.userId.slice(0, 8)}: ${r.errorMessage}`)
  }
}

const withWarnings = results.filter((r) => r.warnings && r.warnings.length > 0)
if (withWarnings.length > 0) {
  console.log(`\nWarnings de validação em ${withWarnings.length} users:`)
  for (const r of withWarnings.slice(0, 5)) {
    console.log(`  - ${r.email ?? r.userId.slice(0, 8)}: ${r.warnings!.slice(0, 2).join(' | ')}`)
  }
  if (withWarnings.length > 5) {
    console.log(`  ... (${withWarnings.length - 5} mais)`)
  }
}

if (dryRun) {
  console.log('\n⚠️  DRY-RUN — nada foi gravado. Re-rode com --apply pra persistir.')
} else {
  console.log('\n✅ Backfill aplicado. Verifique no Supabase Dashboard:')
  console.log('   SELECT id, email, gamification_data->\'imported_resume\'->>\'parsed_at\' AS parsed_at')
  console.log('   FROM user_profiles')
  console.log('   WHERE gamification_data->\'imported_resume\'->>\'parsed_backfilled_at\' IS NOT NULL')
  console.log('   ORDER BY parsed_at DESC LIMIT 10;')
}
