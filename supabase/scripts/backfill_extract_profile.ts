// backfill_extract_profile.ts
//
// Risco 1 (Semana 1 profile-first): roda extract-profile com force=true pra
// todos os usuários que já têm CV importado mas ainda estão em parser_source
// legacy ('pdf', 'vision', 'text'). Popula:
//   - imported_resume.parsed atualizado pro schema legacy derivado do novo
//   - As 18 tabelas relacionais (profile_personal, profile_experiences,
//     profile_bullets, profile_education, ...) via save-profile interno
//
// Por que rodar:
//   - extract-profile só popula relacional quando o usuário re-uploadar o CV
//   - Sem backfill, usuários históricos (~240) ficariam com 18 tabelas vazias
//   - Tela de revisão da Semana 2 e queries diretas exigem dados relacionais
//
// Baseado em backfill_parsed_cvs_pdf.ts (mesmo padrão: Storage download +
// edge function invoke). Custo: ~$0.005 por user (GPT-4o).
//
// Uso:
//   # Dry-run em 5 users:
//   deno run --allow-env --allow-net supabase/scripts/backfill_extract_profile.ts
//
//   # Apply em 5 users:
//   deno run --allow-env --allow-net supabase/scripts/backfill_extract_profile.ts --apply
//
//   # Apply em 240 users (full backfill):
//   deno run --allow-env --allow-net supabase/scripts/backfill_extract_profile.ts --apply --limit=300
//
//   # User específico:
//   deno run --allow-env --allow-net supabase/scripts/backfill_extract_profile.ts --apply --only=<user_id>
//
// Filtros:
//   - User precisa ter saved_resumes (source='imported' ou 'manual') pra ter PDF
//   - User precisa ter raw_text >= 200 chars
//   - Default: pula quem já está em parser_source='extract-profile-v1.0'
//   - --force: re-processa mesmo quem já está
//   - --no-relational-only: pula quem JÁ tem registro em profile_personal
//     (útil pra evitar re-processar usuários que já foram populados)

// Lê .env do projeto (../../.env relativo a supabase/scripts/) pra SUPABASE_URL.
// SERVICE_ROLE_KEY NÃO deve ficar no .env por segurança — passar via env var
// inline na chamada do comando.
function loadEnvKey(name: string): string {
  const fromEnv = Deno.env.get(name)
  if (fromEnv) return fromEnv
  try {
    const envPath = new URL('../../.env', import.meta.url)
    const text = Deno.readTextFileSync(envPath)
    const m = text.match(new RegExp(`^${name}\\s*=\\s*(.+)$`, 'm'))
    if (m) return m[1].trim().replace(/^["']|["']$/g, '')
  } catch (_e) { /* arquivo não existe ou sem permissão — ok */ }
  return ''
}

const SUPABASE_URL = loadEnvKey('SUPABASE_URL')
const SERVICE_ROLE_KEY = loadEnvKey('SUPABASE_SERVICE_ROLE_KEY')

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('ERRO: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios.')
  console.error()
  console.error('SUPABASE_URL: lido do .env do projeto automaticamente.')
  console.error('SUPABASE_SERVICE_ROLE_KEY: você precisa passar inline.')
  console.error()
  console.error('Pegue a service_role key em:')
  console.error('  https://supabase.com/dashboard/project/gaxfmniffjvwrwyunorl/settings/api')
  console.error('Clique em "Reveal" no campo "service_role" e copie.')
  console.error()
  console.error('Depois rode:')
  console.error('  SUPABASE_SERVICE_ROLE_KEY="cole_aqui" deno run --allow-env --allow-net --allow-read \\')
  console.error('    supabase/scripts/backfill_extract_profile.ts')
  Deno.exit(1)
}

const args = Deno.args
const dryRun = !args.includes('--apply')
const force = args.includes('--force')
const noRelationalOnly = args.includes('--no-relational-only')
const limitArg = args.find((a) => a.startsWith('--limit='))
const limit = limitArg ? parseInt(limitArg.split('=')[1], 10) : 5
const onlyArg = args.find((a) => a.startsWith('--only='))
const onlyUserId = onlyArg ? onlyArg.split('=')[1] : null

const STORAGE_BUCKET = 'resumes'
const CURRENT_EXTRACTOR_VERSION = 'extract-profile-v1.0'
const RATE_LIMIT_MS = 1500

console.log('━'.repeat(60))
console.log(`backfill_extract_profile — modo: ${dryRun ? 'DRY-RUN' : 'APPLY (gravando!)'}`)
console.log(`limit=${limit} force=${force} no-relational-only=${noRelationalOnly} only=${onlyUserId ?? '(não)'}`)
console.log(`target version: ${CURRENT_EXTRACTOR_VERSION}`)
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

console.log('\n→ Listando candidatos...')

// 1. Lista users elegíveis (tem raw_text + não está na versão atual)
const userProfilesUrl = onlyUserId
  ? `/rest/v1/user_profiles?select=id,email,gamification_data&id=eq.${onlyUserId}`
  : `/rest/v1/user_profiles?select=id,email,gamification_data` +
    `&gamification_data->imported_resume->>raw_text=not.is.null` +
    (force
      ? ''
      : `&or=(gamification_data->imported_resume->>parser_source.is.null,gamification_data->imported_resume->>parser_source.neq.${CURRENT_EXTRACTOR_VERSION})`) +
    `&limit=${limit * 3}` // pega extra pra compensar quem não tem saved_resumes

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

type Candidate = {
  id: string
  email: string | null
  file_path: string
  parsed: any
  raw_text: string
  parser_source: string | null
  has_relational: boolean
  n_exp_before: number
  n_edu_before: number
}
const candidates: Candidate[] = []

for (const p of allProfiles) {
  const imported = p.gamification_data?.imported_resume
  if (!imported || typeof imported.raw_text !== 'string' || imported.raw_text.length < 200) {
    continue
  }

  // 2. Busca PDF mais recente no Storage
  const resumeResp = await sb(
    `/rest/v1/saved_resumes?select=file_path,created_at&user_id=eq.${p.id}` +
    `&source=in.(imported,manual)&order=created_at.desc&limit=1`,
  )
  if (!resumeResp.ok) continue
  const resumes: Array<{ file_path: string; created_at: string }> = await resumeResp.json()
  if (resumes.length === 0) continue

  // 3. Check se já tem relacional (profile_personal) populado
  const personalResp = await sb(`/rest/v1/profile_personal?select=user_id&user_id=eq.${p.id}`)
  const hasRelational = personalResp.ok
    ? ((await personalResp.json()) as unknown[]).length > 0
    : false

  if (noRelationalOnly && hasRelational) continue

  const parsed = imported.parsed ?? {}
  const nExp = Array.isArray(parsed.experiences) ? parsed.experiences.length : 0
  const nEdu = Array.isArray(parsed.education) ? parsed.education.length : 0

  candidates.push({
    id: p.id,
    email: p.email,
    file_path: resumes[0].file_path,
    parsed,
    raw_text: imported.raw_text,
    parser_source: imported.parser_source ?? null,
    has_relational: hasRelational,
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

// Estatística pré-execução
const breakdown = new Map<string, number>()
for (const c of candidates) {
  const k = c.parser_source ?? '(none)'
  breakdown.set(k, (breakdown.get(k) ?? 0) + 1)
}
console.log('Breakdown por parser_source:')
for (const [k, v] of breakdown.entries()) {
  console.log(`  ${k}: ${v}`)
}
const withRelational = candidates.filter(c => c.has_relational).length
console.log(`  com profile_personal populado: ${withRelational}/${candidates.length}`)
console.log()

// 4. Processa um a um
let i = 0
type Result = {
  email: string | null
  user_id: string
  status: 'success' | 'error' | 'partial'
  n_exp_before: number
  n_exp_after: number
  n_edu_before: number
  n_edu_after: number
  save_status?: string
  confidence?: number
  error?: string
}
const results: Result[] = []

for (const c of candidates) {
  i++
  const tag = `[${i}/${candidates.length}]`
  console.log(`${tag} ${c.email ?? '(sem email)'} — id=${c.id.slice(0, 8)} pdf=${c.file_path.slice(-30)}`)
  console.log(
    `     ↳ antes: parser=${c.parser_source ?? '(none)'} relational=${c.has_relational ? 'sim' : 'não'} ` +
    `exp=${c.n_exp_before} edu=${c.n_edu_before}`,
  )

  if (dryRun) {
    console.log(`     ↳ DRY-RUN — baixaria PDF, chamaria extract-profile`)
    results.push({
      email: c.email,
      user_id: c.id,
      status: 'success',
      n_exp_before: c.n_exp_before,
      n_exp_after: -1,
      n_edu_before: c.n_edu_before,
      n_edu_after: -1,
    })
    continue
  }

  // 4a. Baixa PDF do Storage
  const downloadUrl = `${SUPABASE_URL}/storage/v1/object/${STORAGE_BUCKET}/${c.file_path}`
  const pdfResp = await fetch(downloadUrl, {
    headers: { 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` },
  })
  if (!pdfResp.ok) {
    console.log(`     ↳ ERRO ao baixar PDF: ${pdfResp.status} ${(await pdfResp.text()).slice(0, 100)}`)
    results.push({
      email: c.email,
      user_id: c.id,
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
      user_id: c.id,
      status: 'error',
      n_exp_before: c.n_exp_before,
      n_exp_after: c.n_exp_before,
      n_edu_before: c.n_edu_before,
      n_edu_after: c.n_edu_before,
      error: 'pdf_empty',
    })
    continue
  }

  let binary = ''
  for (let j = 0; j < pdfBytes.length; j++) binary += String.fromCharCode(pdfBytes[j])
  const pdfBase64 = btoa(binary)

  console.log(`     ↳ PDF=${(pdfBytes.length / 1024).toFixed(0)}KB → chamando extract-profile...`)

  // 4b. Chama extract-profile via service-role
  const extractResp = await sb(`/functions/v1/extract-profile`, {
    method: 'POST',
    body: JSON.stringify({
      user_id: c.id,
      pdf_base64: pdfBase64,
      raw_text_fallback: c.raw_text,
      force: true,
    }),
  })
  const extractData = await extractResp.json().catch(() => ({}))

  if (!extractResp.ok) {
    console.log(`     ↳ ERRO extract-profile: ${extractResp.status} ${JSON.stringify(extractData).slice(0, 200)}`)
    results.push({
      email: c.email,
      user_id: c.id,
      status: 'error',
      n_exp_before: c.n_exp_before,
      n_exp_after: c.n_exp_before,
      n_edu_before: c.n_edu_before,
      n_edu_after: c.n_edu_before,
      error: `extract-profile:${extractResp.status}:${extractData?.error ?? 'unknown'}`,
    })
    continue
  }

  const newParsed = extractData?.parsed ?? {}
  const newProfileData = extractData?.profile_data ?? {}
  const meta = extractData?.extraction_meta ?? {}
  const newExp = Array.isArray(newProfileData.experiences) ? newProfileData.experiences.length : 0
  const newEdu = Array.isArray(newProfileData.education) ? newProfileData.education.length : 0
  const saveStatus = meta.save_profile_status ?? '?'
  const confidence = meta.confidence_global ?? 0

  const arrow = (d: number) => d > 0 ? `+${d}` : `${d}`
  console.log(
    `     ↳ OK confidence=${confidence.toFixed(2)} save=${saveStatus} ` +
    `exp=${c.n_exp_before}→${newExp}(${arrow(newExp - c.n_exp_before)}) ` +
    `edu=${c.n_edu_before}→${newEdu}(${arrow(newEdu - c.n_edu_before)})`,
  )

  // Se save-profile falhou em produção, marca como partial (JSONB ok, relacional não)
  const status: 'success' | 'partial' = saveStatus === 'success' ? 'success' : 'partial'

  results.push({
    email: c.email,
    user_id: c.id,
    status,
    n_exp_before: c.n_exp_before,
    n_exp_after: newExp,
    n_edu_before: c.n_edu_before,
    n_edu_after: newEdu,
    save_status: saveStatus,
    confidence,
  })

  // Rate limit pra não estourar OpenAI quota
  await new Promise((r) => setTimeout(r, RATE_LIMIT_MS))

  // Marca para o linter que essa variável foi usada
  void newParsed
}

// 5. Relatório final
console.log('\n' + '━'.repeat(60))
console.log('RELATÓRIO FINAL')
console.log('━'.repeat(60))
const succ = results.filter((r) => r.status === 'success').length
const partial = results.filter((r) => r.status === 'partial').length
const errs = results.filter((r) => r.status === 'error').length
console.log(`  Success (JSONB + relacional): ${succ}`)
console.log(`  Partial (JSONB ok, relacional falhou): ${partial}`)
console.log(`  Erros: ${errs}`)

if (!dryRun) {
  const realSucc = results.filter((r) => r.status === 'success' && r.n_exp_after >= 0)
  if (realSucc.length > 0) {
    const expGained = realSucc.reduce((s, r) => s + (r.n_exp_after - r.n_exp_before), 0)
    const eduGained = realSucc.reduce((s, r) => s + (r.n_edu_after - r.n_edu_before), 0)
    const usersImproved = realSucc.filter((r) =>
      r.n_exp_after > r.n_exp_before || r.n_edu_after > r.n_edu_before
    ).length
    const avgConfidence = realSucc.reduce((s, r) => s + (r.confidence ?? 0), 0) / realSucc.length
    console.log(`  Total experiences ganhas: +${expGained}`)
    console.log(`  Total education ganhas: +${eduGained}`)
    console.log(`  Users com melhoria: ${usersImproved}/${realSucc.length}`)
    console.log(`  Confidence_global médio: ${avgConfidence.toFixed(2)}`)
    console.log(`  Custo estimado: $${(realSucc.length * 0.005).toFixed(2)}`)
  }
}

if (partial > 0) {
  console.log('\nPartial (verificar profile_extraction_logs):')
  for (const r of results.filter((r) => r.status === 'partial')) {
    console.log(`  - ${r.email}: save_status=${r.save_status}`)
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
  console.log('\n✅ Backfill profile-first aplicado.')
}
