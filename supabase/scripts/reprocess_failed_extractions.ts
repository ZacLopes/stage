// reprocess_failed_extractions.ts
//
// Semana 3 — Bloco A: reprocessa partial failures do backfill profile-first.
//
// Estratégia em 3 categorias (descoberto via sanity check em 2026-05-23):
//
//   1. status='partial' (29 users)  → raw_json_output salvo → tenta
//      save_profile_from_json RPC direto. Custo OpenAI = 0.
//
//   2. status='failed' + sem perfil estruturado (10 users)  → órfãos genuínos:
//      8 sem profile_personal + 2 com personal mas exp+edu=0.
//      Resgate via re-call de extract-profile com o raw_text salvo em
//      user_profiles.gamification_data.imported_resume.raw_text.
//      Custo: ~$0.02/user (~$0.20 total).
//
//   3. status='failed' + perfil completo (133 users)  → log_only.
//      Apenas marca o log como 'log_only' sem reprocessar.
//      O user já teve sucesso depois com outra tentativa — log é só ruído.
//
// Auditoria: setamos `recovery_attempted_at = now()` em qualquer log que
// passamos pelo script — evita re-rodar sobre os mesmos logs.
//
// Critério de aceitação (definido pelo founder em 2026-05-23):
//   ≥75% dos 39 recuperáveis (29 partial + 10 órfãos) → status='recovered'
//   100% dos 143 'failed' devem ser sanity-checked e reclassificados
//
// Uso:
//   # Dry-run completo (default — não escreve nada):
//   deno run --allow-env --allow-net --allow-read \
//     supabase/scripts/reprocess_failed_extractions.ts
//
//   # Apply real:
//   SUPABASE_SERVICE_ROLE_KEY="..." deno run --allow-env --allow-net --allow-read \
//     supabase/scripts/reprocess_failed_extractions.ts --apply
//
//   # Só uma categoria (debug):
//   deno run ... --apply --only=partial
//   deno run ... --apply --only=orphan
//   deno run ... --apply --only=log_only
//
//   # User específico:
//   deno run ... --apply --user=<uuid>

function loadEnvKey(name: string): string {
  const fromEnv = Deno.env.get(name)
  if (fromEnv) return fromEnv
  try {
    const envPath = new URL('../../.env', import.meta.url)
    const text = Deno.readTextFileSync(envPath)
    const m = text.match(new RegExp(`^${name}\\s*=\\s*(.+)$`, 'm'))
    if (m) return m[1].trim().replace(/^["']|["']$/g, '')
  } catch (_e) { /* ignore */ }
  return ''
}

const SUPABASE_URL = loadEnvKey('SUPABASE_URL')
const SERVICE_ROLE_KEY = loadEnvKey('SUPABASE_SERVICE_ROLE_KEY')

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('ERRO: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios.')
  console.error('Pegue service_role em https://supabase.com/dashboard/project/gaxfmniffjvwrwyunorl/settings/api')
  console.error('Rode: SUPABASE_SERVICE_ROLE_KEY="..." deno run --allow-env --allow-net --allow-read \\')
  console.error('  supabase/scripts/reprocess_failed_extractions.ts')
  Deno.exit(1)
}

const args = Deno.args
const dryRun = !args.includes('--apply')
const onlyArg = args.find((a) => a.startsWith('--only='))
const only = onlyArg ? onlyArg.split('=')[1] : null // partial | orphan | log_only
const userArg = args.find((a) => a.startsWith('--user='))
const onlyUser = userArg ? userArg.split('=')[1] : null
// --retry-unrecoverable: re-tenta logs já marcados 'unrecoverable'. Útil
// quando bug do script anterior gerou unrecoverable falso (ex: orphan path
// sem PDF binary antes do patch de 2026-05-23).
const retryUnrecoverable = args.includes('--retry-unrecoverable')

const RATE_LIMIT_MS = 1500
const STORAGE_BUCKET = 'resumes'

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

console.log('━'.repeat(60))
console.log(`reprocess_failed_extractions — modo: ${dryRun ? 'DRY-RUN' : 'APPLY'}`)
console.log(`filtros: only=${only ?? '(todos)'} user=${onlyUser ?? '(todos)'}`)
console.log('━'.repeat(60))

// ─────────────────────────────────────────────────────────────────────────
// 1. Classifica todos os logs failed/partial recentes em 3 buckets
// ─────────────────────────────────────────────────────────────────────────

console.log('\n→ Classificando logs failed/partial (últimos 60 dias)...')

// Pega TODOS os logs não-success últimos 60 dias que ainda não foram processados
// (ou todos unrecoverable se --retry-unrecoverable).
const statusFilter = retryUnrecoverable
  ? `status=in.(failed,partial,unrecoverable)`
  : `status=in.(failed,partial)`
// Quando re-tentando unrecoverable, ignora o filter de recovery_attempted_at
// (já foi setado pela tentativa anterior).
const attemptedFilter = retryUnrecoverable ? '' : '&recovery_attempted_at=is.null'
const logsResp = await sb(
  `/rest/v1/profile_extraction_logs?select=id,user_id,status,raw_json_output,error_message,created_at` +
  `&${statusFilter}` +
  attemptedFilter +
  `&created_at=gte.${new Date(Date.now() - 60 * 86400_000).toISOString()}` +
  `&order=created_at.desc` +
  `&limit=1000`,
)
if (!logsResp.ok) {
  console.error(`ERRO ao listar logs: ${logsResp.status} ${await logsResp.text()}`)
  Deno.exit(1)
}

type Log = {
  id: string
  user_id: string
  status: 'failed' | 'partial' | 'unrecoverable'
  raw_json_output: any
  error_message: string | null
  created_at: string
}

let logs: Log[] = await logsResp.json()
if (onlyUser) logs = logs.filter((l) => l.user_id === onlyUser)

console.log(`  ${logs.length} logs candidatos.`)

// Dedup por user (pega só o log mais recente por user — se reprocessar, atualiza esse)
const latestByUser = new Map<string, Log>()
for (const l of logs) {
  if (!latestByUser.has(l.user_id)) latestByUser.set(l.user_id, l)
}
const uniqueLogs = Array.from(latestByUser.values())
console.log(`  ${uniqueLogs.length} users únicos.`)

// Estado do perfil estruturado por user (single query)
const userIds = uniqueLogs.map((l) => l.user_id)
const orFilter = `user_id=in.(${userIds.join(',')})`
const [personalR, expR, eduR, importedR] = await Promise.all([
  sb(`/rest/v1/profile_personal?select=user_id&${orFilter}`),
  sb(`/rest/v1/profile_experiences?select=user_id&${orFilter}`),
  sb(`/rest/v1/profile_education?select=user_id&${orFilter}`),
  sb(`/rest/v1/user_profiles?select=id,gamification_data&id=in.(${userIds.join(',')})`),
])

const hasPersonal = new Set((await personalR.json()).map((r: any) => r.user_id))
const expByUser = new Map<string, number>()
for (const r of (await expR.json())) {
  expByUser.set(r.user_id, (expByUser.get(r.user_id) ?? 0) + 1)
}
const eduByUser = new Map<string, number>()
for (const r of (await eduR.json())) {
  eduByUser.set(r.user_id, (eduByUser.get(r.user_id) ?? 0) + 1)
}
const rawTextByUser = new Map<string, string>()
for (const r of (await importedR.json())) {
  const rt = r.gamification_data?.imported_resume?.raw_text
  if (typeof rt === 'string' && rt.length > 100) rawTextByUser.set(r.id, rt)
}

// Classifica
type Category = 'partial' | 'orphan' | 'log_only'
type Candidate = {
  log: Log
  category: Category
  has_personal: boolean
  exp_count: number
  edu_count: number
  has_raw_text: boolean
}

const candidates: Candidate[] = []
for (const log of uniqueLogs) {
  const has_personal = hasPersonal.has(log.user_id)
  const exp_count = expByUser.get(log.user_id) ?? 0
  const edu_count = eduByUser.get(log.user_id) ?? 0
  const has_raw_text = rawTextByUser.has(log.user_id)

  // Categorização robusta a re-tentativas (--retry-unrecoverable):
  //   - tem raw_json_output salvo → tentar RPC direto (partial)
  //   - sem raw_json_output E perfil ausente/esqueleto → orphan (re-extract)
  //   - sem raw_json_output mas perfil completo → log_only
  let category: Category
  if (log.raw_json_output) {
    category = 'partial'
  } else if (!has_personal || (exp_count === 0 && edu_count === 0)) {
    category = 'orphan'
  } else {
    category = 'log_only'
  }

  candidates.push({ log, category, has_personal, exp_count, edu_count, has_raw_text })
}

const byCategory = {
  partial: candidates.filter((c) => c.category === 'partial'),
  orphan: candidates.filter((c) => c.category === 'orphan'),
  log_only: candidates.filter((c) => c.category === 'log_only'),
}

console.log('\nClassificação:')
console.log(`  partial   (RPC direto, custo 0):       ${byCategory.partial.length}`)
console.log(`  orphan    (re-call extract, ~$0.02/u): ${byCategory.orphan.length}`)
console.log(`  log_only  (só marca o log):            ${byCategory.log_only.length}`)
console.log(`  ─────────────────────────────────────`)
console.log(`  total candidatos:                       ${candidates.length}`)
const recoverable = byCategory.partial.length + byCategory.orphan.length
console.log(`  recuperáveis (partial+orphan):          ${recoverable}`)
console.log()

// Filtra por --only se passado
let workSet = candidates
if (only) {
  workSet = candidates.filter((c) => c.category === only)
  console.log(`Filtro --only=${only} aplicado: ${workSet.length} candidatos restantes.\n`)
}

// ─────────────────────────────────────────────────────────────────────────
// 2. Processa cada candidato
// ─────────────────────────────────────────────────────────────────────────

type RecoveryResult = {
  log_id: string
  user_id: string
  category: Category
  new_status: 'recovered' | 'unrecoverable' | 'log_only'
  detail?: string
}
const results: RecoveryResult[] = []

let i = 0
for (const c of workSet) {
  i++
  const tag = `[${i}/${workSet.length}]`
  const uid8 = c.log.user_id.slice(0, 8)
  console.log(`${tag} ${c.category.padEnd(8)} user=${uid8} log=${c.log.id.slice(0, 8)} ` +
    `(personal=${c.has_personal ? 'sim' : 'não'}, exp=${c.exp_count}, edu=${c.edu_count}, ` +
    `raw_text=${c.has_raw_text ? 'sim' : 'não'})`)

  if (dryRun) {
    console.log(`     ↳ DRY-RUN`)
    results.push({
      log_id: c.log.id,
      user_id: c.log.user_id,
      category: c.category,
      new_status: c.category === 'log_only' ? 'log_only' : 'recovered',
      detail: 'dry-run',
    })
    continue
  }

  if (c.category === 'log_only') {
    // Apenas marca log
    const upd = await sb(`/rest/v1/profile_extraction_logs?id=eq.${c.log.id}`, {
      method: 'PATCH',
      body: JSON.stringify({
        status: 'log_only',
        recovery_attempted_at: new Date().toISOString(),
      }),
    })
    if (!upd.ok) {
      console.log(`     ↳ ERRO update log: ${upd.status} ${(await upd.text()).slice(0, 100)}`)
      results.push({ log_id: c.log.id, user_id: c.log.user_id, category: c.category,
        new_status: 'unrecoverable', detail: `update_log:${upd.status}` })
      continue
    }
    console.log(`     ↳ marcado log_only`)
    results.push({ log_id: c.log.id, user_id: c.log.user_id, category: c.category,
      new_status: 'log_only' })
    continue
  }

  if (c.category === 'partial') {
    // RPC direto: save_profile_from_json com o raw_json_output salvo
    const rpcResp = await sb(`/rest/v1/rpc/save_profile_from_json`, {
      method: 'POST',
      body: JSON.stringify({
        p_user_id: c.log.user_id,
        p_data: c.log.raw_json_output,
      }),
    })
    if (!rpcResp.ok) {
      const errTxt = (await rpcResp.text()).slice(0, 200)
      console.log(`     ↳ ERRO save_profile_from_json: ${rpcResp.status} ${errTxt}`)
      await sb(`/rest/v1/profile_extraction_logs?id=eq.${c.log.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          status: 'unrecoverable',
          recovery_attempted_at: new Date().toISOString(),
          error_message: `recovery_rpc:${rpcResp.status}:${errTxt.slice(0, 200)}`,
        }),
      })
      results.push({ log_id: c.log.id, user_id: c.log.user_id, category: c.category,
        new_status: 'unrecoverable', detail: errTxt })
      continue
    }
    await sb(`/rest/v1/profile_extraction_logs?id=eq.${c.log.id}`, {
      method: 'PATCH',
      body: JSON.stringify({
        status: 'recovered',
        recovery_attempted_at: new Date().toISOString(),
      }),
    })
    console.log(`     ↳ recovered via RPC`)
    results.push({ log_id: c.log.id, user_id: c.log.user_id, category: c.category,
      new_status: 'recovered' })
    continue
  }

  // orphan: re-call extract-profile com PDF binário do Storage + raw_text
  // como fallback. extract-profile EXIGE pdf_base64; raw_text_fallback é só
  // um hint pro validador anti-invenção.
  if (c.category === 'orphan') {
    if (!c.has_raw_text) {
      console.log(`     ↳ SEM raw_text salvo → unrecoverable`)
      await sb(`/rest/v1/profile_extraction_logs?id=eq.${c.log.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          status: 'unrecoverable',
          recovery_attempted_at: new Date().toISOString(),
          error_message: 'no_raw_text_to_reprocess',
        }),
      })
      results.push({ log_id: c.log.id, user_id: c.log.user_id, category: c.category,
        new_status: 'unrecoverable', detail: 'no_raw_text' })
      continue
    }

    // Busca PDF mais recente do user no Storage (mesmo padrão do
    // backfill_extract_profile.ts).
    const resumeResp = await sb(
      `/rest/v1/saved_resumes?select=file_path,created_at&user_id=eq.${c.log.user_id}` +
      `&source=in.(imported,manual)&order=created_at.desc&limit=1`,
    )
    if (!resumeResp.ok) {
      console.log(`     ↳ ERRO listando saved_resumes: ${resumeResp.status}`)
      await sb(`/rest/v1/profile_extraction_logs?id=eq.${c.log.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          status: 'unrecoverable',
          recovery_attempted_at: new Date().toISOString(),
          error_message: `saved_resumes_query:${resumeResp.status}`,
        }),
      })
      results.push({ log_id: c.log.id, user_id: c.log.user_id, category: c.category,
        new_status: 'unrecoverable', detail: 'saved_resumes_query_failed' })
      continue
    }
    const resumes: Array<{ file_path: string }> = await resumeResp.json()
    if (resumes.length === 0) {
      console.log(`     ↳ SEM PDF salvo (saved_resumes vazio) → unrecoverable`)
      await sb(`/rest/v1/profile_extraction_logs?id=eq.${c.log.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          status: 'unrecoverable',
          recovery_attempted_at: new Date().toISOString(),
          error_message: 'no_saved_resume',
        }),
      })
      results.push({ log_id: c.log.id, user_id: c.log.user_id, category: c.category,
        new_status: 'unrecoverable', detail: 'no_saved_resume' })
      continue
    }

    // Baixa PDF e converte pra base64.
    const downloadUrl = `${SUPABASE_URL}/storage/v1/object/${STORAGE_BUCKET}/${resumes[0].file_path}`
    const pdfResp = await fetch(downloadUrl, {
      headers: { 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` },
    })
    if (!pdfResp.ok) {
      console.log(`     ↳ ERRO baixando PDF: ${pdfResp.status}`)
      await sb(`/rest/v1/profile_extraction_logs?id=eq.${c.log.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          status: 'unrecoverable',
          recovery_attempted_at: new Date().toISOString(),
          error_message: `pdf_download:${pdfResp.status}`,
        }),
      })
      results.push({ log_id: c.log.id, user_id: c.log.user_id, category: c.category,
        new_status: 'unrecoverable', detail: `pdf_download_${pdfResp.status}` })
      continue
    }
    const pdfBytes = new Uint8Array(await pdfResp.arrayBuffer())
    let binary = ''
    for (let j = 0; j < pdfBytes.length; j++) binary += String.fromCharCode(pdfBytes[j])
    const pdfBase64 = btoa(binary)

    const rawText = rawTextByUser.get(c.log.user_id)!
    const extResp = await sb(`/functions/v1/extract-profile`, {
      method: 'POST',
      body: JSON.stringify({
        user_id: c.log.user_id,
        pdf_base64: pdfBase64,
        raw_text_fallback: rawText,
        force: true,
      }),
    })
    if (!extResp.ok) {
      const errTxt = (await extResp.text()).slice(0, 200)
      console.log(`     ↳ ERRO extract-profile: ${extResp.status} ${errTxt}`)
      await sb(`/rest/v1/profile_extraction_logs?id=eq.${c.log.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          status: 'unrecoverable',
          recovery_attempted_at: new Date().toISOString(),
          error_message: `recovery_extract:${extResp.status}:${errTxt.slice(0, 200)}`,
        }),
      })
      results.push({ log_id: c.log.id, user_id: c.log.user_id, category: c.category,
        new_status: 'unrecoverable', detail: errTxt })
      continue
    }
    // extract-profile cria log novo 'success'. Marca o log antigo como recovered.
    await sb(`/rest/v1/profile_extraction_logs?id=eq.${c.log.id}`, {
      method: 'PATCH',
      body: JSON.stringify({
        status: 'recovered',
        recovery_attempted_at: new Date().toISOString(),
      }),
    })
    console.log(`     ↳ recovered via re-extract`)
    results.push({ log_id: c.log.id, user_id: c.log.user_id, category: c.category,
      new_status: 'recovered' })

    // Rate limit pra não estourar OpenAI quota (orphan paths chamam OpenAI)
    await new Promise((r) => setTimeout(r, RATE_LIMIT_MS))
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 3. Relatório final + verificação do critério ≥75%
// ─────────────────────────────────────────────────────────────────────────

console.log('\n' + '━'.repeat(60))
console.log('RELATÓRIO FINAL')
console.log('━'.repeat(60))

const recovered = results.filter((r) => r.new_status === 'recovered').length
const logOnly = results.filter((r) => r.new_status === 'log_only').length
const unrecoverable = results.filter((r) => r.new_status === 'unrecoverable').length

console.log(`  recovered:      ${recovered}`)
console.log(`  log_only:       ${logOnly}`)
console.log(`  unrecoverable:  ${unrecoverable}`)
console.log()

if (!only) {
  const targetRecoverable = byCategory.partial.length + byCategory.orphan.length
  const actuallyRecovered = results.filter(
    (r) => (r.category === 'partial' || r.category === 'orphan') && r.new_status === 'recovered',
  ).length
  const pct = targetRecoverable > 0 ? (actuallyRecovered / targetRecoverable) * 100 : 0
  console.log(`Critério ≥75% de recuperáveis:`)
  console.log(`  ${actuallyRecovered}/${targetRecoverable} = ${pct.toFixed(1)}% ${pct >= 75 ? '✅' : '❌'}`)
}

if (unrecoverable > 0) {
  console.log('\nNão-recuperáveis (investigar padrão):')
  for (const r of results.filter((r) => r.new_status === 'unrecoverable')) {
    console.log(`  - user=${r.user_id.slice(0, 8)} category=${r.category} detail=${r.detail}`)
  }
}

if (dryRun) {
  console.log('\n⚠️  DRY-RUN — nada gravado. Re-rode com --apply.')
} else {
  console.log('\n✅ Reprocessamento aplicado.')
}
