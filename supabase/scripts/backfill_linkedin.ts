// backfill_linkedin.ts
//
// Tier 2.5 do plano "1000x melhor". Popula `profile_personal.linkedin_url`
// (e `website`) pros users com `profile_source='imported'` que tinham
// dados no JSONB legacy `gamification_data.imported_resume.parsed.personal`
// mas perderam quando a RPC `save_profile_from_json` tentou inserir numa
// coluna que não existia (bug histórico — coluna criada em 2026-05-24).
//
// Custo: ZERO (sem chamadas OpenAI). Só copy direto JSONB → coluna.
//
// Quem é afetado:
//   - Users com profile_personal.profile_source = 'imported'
//   - E profile_personal.linkedin_url IS NULL
//   - E gamification_data->'imported_resume'->'parsed'->'personal'->>'linkedin' IS NOT NULL
//
// Estimativa pré-execução: ~150 users (dos 257 com 'imported').
//
// Uso:
//   # Dry-run:
//   deno run --allow-env --allow-net --allow-read \
//     supabase/scripts/backfill_linkedin.ts
//
//   # Apply (preenche linkedin_url null):
//   SUPABASE_SERVICE_ROLE_KEY="..." deno run --allow-env --allow-net --allow-read \
//     supabase/scripts/backfill_linkedin.ts --apply
//
//   # Re-corrige linkedin_url damaged pelo regex v1 buggy (pré-2026-05-24):
//   SUPABASE_SERVICE_ROLE_KEY="..." deno run --allow-env --allow-net --allow-read \
//     supabase/scripts/backfill_linkedin.ts --apply --force

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
  console.error('Rode: SUPABASE_SERVICE_ROLE_KEY="..." deno run --allow-env --allow-net --allow-read \\')
  console.error('  supabase/scripts/backfill_linkedin.ts')
  Deno.exit(1)
}

const args = Deno.args
const dryRun = !args.includes('--apply')
const onlyUser = args.find((a) => a.startsWith('--user='))?.split('=')[1]
// --force: re-processa users que JÁ TÊM linkedin_url populado. Útil pra
// corrigir users cujo linkedin_url ficou damaged pelo regex v1 buggy
// (versão antes de 2026-05-24 que removia "Ci" inteiro em vez de só "C").
const force = args.includes('--force')

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

// Sanitiza artifacts "C" do Syncfusion (extração legacy do PDF insere "C"
// ANTES de cada 'i' ou 'm' em palavras com font subsetting quebrado).
// Padrão real do Syncfusion: "linkedin.com" → "lCinkedCin.coCm".
//
// Versão 1 (buggy) removia "Ci" inteiro → resultado "lnkedn".
// Versão 2 (esta) remove só o 'C' antes de 'i'/'m' → "linkedin".
// Espelho do _sanitizeSyncfusionArtifacts() em pdf_text_extractor.dart.
function sanitizeSyncfusionCi(text: string): string {
  if (!text || !text.includes('C')) return text
  const legit = new Set([
    'cidade', 'cidades', 'cinema', 'cinemas', 'ciência', 'ciências',
    'circuito', 'circuitos', 'círculo', 'círculos', 'cifra', 'cifras',
    'city', 'cities', 'circle', 'circles', 'cipher', 'circuit', 'circuits',
    'citizen', 'cite', 'cited',
  ])
  const tokens = text.split(/(\s+)/)
  const out: string[] = []
  for (const t of tokens) {
    if (t.length === 0 || /^\s+$/.test(t)) { out.push(t); continue }
    const clean = t.replace(/[^A-Za-zÀ-ÿ]/g, '').toLowerCase()
    if (legit.has(clean)) { out.push(t); continue }
    let cur = t
    for (let i = 0; i < 8; i++) {
      // Remove 'C' inserido antes de 'i'/'m' (preserva o char alvo).
      const next = cur.replace(/(?<![A-Z])C(?=[im])/g, '')
      if (next === cur) break
      cur = next
    }
    out.push(cur)
  }
  return out.join('')
}

console.log('━'.repeat(60))
console.log(`backfill_linkedin — modo: ${dryRun ? 'DRY-RUN' : 'APPLY'}`)
console.log(`filtro: user=${onlyUser ?? '(todos)'}`)
console.log('━'.repeat(60))

// 1. Lista candidatos: tem LinkedIn em QUALQUER path do JSONB legacy.
// Suporta 2 schemas históricos:
//   - parse-cv (legacy):  parsed.linkedin
//   - extract-profile:    parsed.personal.linkedin
const userFilter = onlyUser ? `&id=eq.${onlyUser}` : ''
const usersResp = await sb(
  `/rest/v1/user_profiles?select=id,email,gamification_data` +
  `&or=(gamification_data->imported_resume->parsed->personal->>linkedin.not.is.null,gamification_data->imported_resume->parsed->>linkedin.not.is.null)` +
  userFilter +
  `&limit=500`,
)
if (!usersResp.ok) {
  console.error(`ERRO listando users: ${usersResp.status} ${await usersResp.text()}`)
  Deno.exit(1)
}
const users: Array<{ id: string; email: string | null; gamification_data: any }> = await usersResp.json()
console.log(`  ${users.length} users com LinkedIn no JSONB legacy (qualquer schema).\n`)

// 2. Pra cada, checa se profile_personal.linkedin_url está null (precisa backfill)
type Candidate = {
  userId: string
  email: string | null
  linkedinFromJsonb: string
  websiteFromJsonb: string | null
  schemaPath: 'flat' | 'personal'  // qual path do JSONB tinha o dado
  needsBackfill: boolean
  currentLinkedinUrl: string | null
}
const candidates: Candidate[] = []
for (const u of users) {
  // Tenta path NOVO (extract-profile): parsed.personal.linkedin
  const personalObj = u.gamification_data?.imported_resume?.parsed?.personal ?? {}
  const linkedinFromPersonal = String(personalObj.linkedin ?? '').trim()
  // Tenta path LEGACY (parse-cv): parsed.linkedin direto
  const flatParsed = u.gamification_data?.imported_resume?.parsed ?? {}
  const linkedinFromFlat = String(flatParsed.linkedin ?? '').trim()

  const rawLinkedin = linkedinFromPersonal || linkedinFromFlat
  if (!rawLinkedin) continue
  const schemaPath: 'flat' | 'personal' = linkedinFromPersonal ? 'personal' : 'flat'

  // Aplica sanitização (caso o LinkedIn tenha sido extraído via raw_text
  // bugado pelo Syncfusion: "lCinkedCin.coCm" → "linkedin.com").
  const linkedinFromJsonb = sanitizeSyncfusionCi(rawLinkedin)

  const rawWebsite = personalObj.website != null
    ? String(personalObj.website).trim()
    : (flatParsed.website != null ? String(flatParsed.website).trim() : '')
  const websiteFromJsonb = rawWebsite
    ? sanitizeSyncfusionCi(rawWebsite) || null
    : null

  // Lê profile_personal.linkedin_url atual
  const ppResp = await sb(
    `/rest/v1/profile_personal?select=linkedin_url&user_id=eq.${u.id}`,
  )
  if (!ppResp.ok) continue
  const ppRows = await ppResp.json() as Array<{ linkedin_url: string | null }>
  const currentLinkedinUrl = ppRows[0]?.linkedin_url ?? null

  // Detecta "damaged" pelo regex v1 antigo: linkedin_url no DB que NÃO
  // bate com o sanitize v2 aplicado no rawLinkedin do JSONB. Sinal de
  // que a primeira backfill rodada usou o regex buggy ("Ci" inteiro
  // removido) e o valor atual está com `i`s perdidos.
  const damagedByOldRegex = !!currentLinkedinUrl &&
    currentLinkedinUrl !== linkedinFromJsonb

  // needsBackfill:
  //   - sem linkedin_url no DB → sempre backfill
  //   - com linkedin_url + --force → re-backfill (corrige damaged)
  //   - com linkedin_url batendo o sanitize v2 → skip (já correto)
  const needsBackfill = !currentLinkedinUrl ||
    (force && damagedByOldRegex)

  candidates.push({
    userId: u.id,
    email: u.email,
    linkedinFromJsonb,
    websiteFromJsonb,
    schemaPath,
    needsBackfill,
    currentLinkedinUrl,
  })
}

const toBackfill = candidates.filter((c) => c.needsBackfill)
const damagedCount = candidates.filter((c) =>
  c.currentLinkedinUrl && c.currentLinkedinUrl !== c.linkedinFromJsonb
).length
const alreadyOk = candidates.length - toBackfill.length

console.log(`Classificação:`)
console.log(`  ${alreadyOk.toString().padStart(4)} já têm linkedin_url populado`)
if (damagedCount > 0) {
  console.log(`     └─ ${damagedCount} parecem damaged pelo regex v1 (use --force pra re-corrigir)`)
}
console.log(`  ${toBackfill.length.toString().padStart(4)} ${force ? 'precisam (re-)backfill' : 'precisam backfill'}`)
console.log()

if (toBackfill.length === 0) {
  console.log('Nada a fazer. ✅')
  Deno.exit(0)
}

// 3. Processa
let succ = 0
let fail = 0
for (let i = 0; i < toBackfill.length; i++) {
  const c = toBackfill[i]
  const tag = `[${i + 1}/${toBackfill.length}]`
  const isFix = !!c.currentLinkedinUrl
  console.log(`${tag} user=${c.userId.slice(0, 8)} email=${c.email ?? '(no email)'} path=${c.schemaPath}${isFix ? ' [FIX]' : ''}`)
  if (isFix) {
    console.log(`     antes:    ${(c.currentLinkedinUrl ?? '').slice(0, 60)}`)
    console.log(`     depois:   ${c.linkedinFromJsonb.slice(0, 60)}${c.linkedinFromJsonb.length > 60 ? '...' : ''}`)
  } else {
    console.log(`     linkedin: ${c.linkedinFromJsonb.slice(0, 60)}${c.linkedinFromJsonb.length > 60 ? '...' : ''}`)
  }
  if (c.websiteFromJsonb) {
    console.log(`     website:  ${c.websiteFromJsonb}`)
  }

  if (dryRun) {
    console.log('     ↳ DRY-RUN')
    continue
  }

  const patchBody: Record<string, string | null> = {
    linkedin_url: c.linkedinFromJsonb,
  }
  if (c.websiteFromJsonb) patchBody.website = c.websiteFromJsonb

  const upd = await sb(`/rest/v1/profile_personal?user_id=eq.${c.userId}`, {
    method: 'PATCH',
    body: JSON.stringify(patchBody),
  })
  if (!upd.ok) {
    fail++
    console.log(`     ↳ ERRO ${upd.status} ${(await upd.text()).slice(0, 100)}`)
    continue
  }
  succ++
  console.log('     ↳ ok')
}

console.log('\n' + '━'.repeat(60))
console.log(`RELATÓRIO`)
console.log('━'.repeat(60))
if (dryRun) {
  console.log(`  Dry-run: ${toBackfill.length} users seriam atualizados.`)
} else {
  console.log(`  Sucesso: ${succ}`)
  console.log(`  Falha:   ${fail}`)
}
console.log()
console.log(dryRun ? '⚠️  DRY-RUN — re-rode com --apply.' : '✅ Backfill aplicado.')
