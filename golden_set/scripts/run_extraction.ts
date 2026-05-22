// run_extraction.ts
//
// Roda extract-profile contra cada PDF em ../cvs/ e salva o JSON resultante
// em ../outputs/cv_NNN_output.json. Usa service-role pra forçar a chamada
// sem JWT de usuário (e pra mandar force: true ignorando cache).
//
// Uso:
//   cd career_gamification/golden_set
//   deno run --allow-env --allow-net --allow-read --allow-write scripts/run_extraction.ts
//
// Variáveis de ambiente (vêm de ../.env):
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//
// Custo aprox: ~$0.005 por CV (30 CVs ≈ $0.15).

import { encode as encodeBase64 } from 'https://deno.land/std@0.224.0/encoding/base64.ts'

const ROOT = new URL('../', import.meta.url)
const CVS_DIR = new URL('./cvs/', ROOT)
const OUTPUTS_DIR = new URL('./outputs/', ROOT)

interface RunSummary {
  cv_id: string
  status: 'success' | 'partial' | 'failed' | 'http_error'
  http_status: number
  confidence_global: number | null
  low_confidence_fields: string[]
  experiences_count: number
  education_count: number
  skills_count: number
  duration_ms: number
  error?: string
}

async function loadEnv(): Promise<{ url: string; serviceKey: string; userId: string }> {
  // Tenta .env do projeto (../.env relativo a golden_set/scripts/)
  const envPath = new URL('../.env', ROOT)
  let envText = ''
  try {
    envText = await Deno.readTextFile(envPath)
  } catch {
    // ok — pode vir do environment
  }

  function parseEnvLine(name: string): string | undefined {
    const m = envText.match(new RegExp(`^${name}\\s*=\\s*(.+)$`, 'm'))
    if (m) return m[1].trim().replace(/^["']|["']$/g, '')
    return Deno.env.get(name)
  }

  const url = parseEnvLine('SUPABASE_URL')
  const serviceKey = parseEnvLine('SUPABASE_SERVICE_ROLE_KEY')
  const userId = parseEnvLine('GOLDEN_SET_USER_ID') ?? '00000000-0000-0000-0000-000000000001'

  if (!url || !serviceKey) {
    console.error('ERROR: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY devem estar em .env ou no environment')
    Deno.exit(1)
  }

  return { url, serviceKey, userId }
}

async function listPdfs(): Promise<string[]> {
  const out: string[] = []
  try {
    for await (const entry of Deno.readDir(CVS_DIR)) {
      if (entry.isFile && entry.name.toLowerCase().endsWith('.pdf')) {
        out.push(entry.name)
      }
    }
  } catch (_e) {
    console.error(`ERROR: pasta ${CVS_DIR} não encontrada ou vazia`)
    Deno.exit(1)
  }
  return out.sort()
}

async function runOne(
  url: string,
  serviceKey: string,
  userId: string,
  pdfFilename: string,
): Promise<RunSummary> {
  const start = Date.now()
  const cvId = pdfFilename.replace(/\.pdf$/i, '')
  const pdfPath = new URL(pdfFilename, CVS_DIR)

  let pdfBytes: Uint8Array
  try {
    pdfBytes = await Deno.readFile(pdfPath)
  } catch (e) {
    return {
      cv_id: cvId,
      status: 'failed',
      http_status: 0,
      confidence_global: null,
      low_confidence_fields: [],
      experiences_count: 0,
      education_count: 0,
      skills_count: 0,
      duration_ms: 0,
      error: `read_file_failed: ${(e as Error).message}`,
    }
  }

  const pdfBase64 = encodeBase64(pdfBytes)

  let resp: Response
  try {
    resp = await fetch(`${url}/functions/v1/extract-profile`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
        'X-Service-Role-Key': serviceKey,
      },
      body: JSON.stringify({
        pdf_base64: pdfBase64,
        user_id: userId,
        force: true,
      }),
    })
  } catch (e) {
    return {
      cv_id: cvId,
      status: 'failed',
      http_status: 0,
      confidence_global: null,
      low_confidence_fields: [],
      experiences_count: 0,
      education_count: 0,
      skills_count: 0,
      duration_ms: Date.now() - start,
      error: `network: ${(e as Error).message}`,
    }
  }

  const text = await resp.text()
  let body: any
  try { body = JSON.parse(text) } catch { body = { raw: text } }

  if (!resp.ok) {
    await Deno.writeTextFile(
      new URL(`${cvId}_output.json`, OUTPUTS_DIR),
      JSON.stringify({ error: body, http_status: resp.status }, null, 2),
    )
    return {
      cv_id: cvId,
      status: 'http_error',
      http_status: resp.status,
      confidence_global: null,
      low_confidence_fields: [],
      experiences_count: 0,
      education_count: 0,
      skills_count: 0,
      duration_ms: Date.now() - start,
      error: body?.error ?? body?.detail ?? text.slice(0, 200),
    }
  }

  const profileData = body?.profile_data ?? {}
  const meta = body?.extraction_meta ?? {}

  await Deno.writeTextFile(
    new URL(`${cvId}_output.json`, OUTPUTS_DIR),
    JSON.stringify(body, null, 2),
  )

  return {
    cv_id: cvId,
    status: meta.status ?? 'success',
    http_status: resp.status,
    confidence_global: meta.confidence_global ?? null,
    low_confidence_fields: meta.low_confidence_fields ?? [],
    experiences_count: (profileData.experiences ?? []).length,
    education_count: (profileData.education ?? []).length,
    skills_count: (profileData.skills ?? []).length,
    duration_ms: Date.now() - start,
  }
}

async function main() {
  const { url, serviceKey, userId } = await loadEnv()
  const pdfs = await listPdfs()
  if (pdfs.length === 0) {
    console.log('Nenhum PDF em cvs/. Adicione PDFs antes de rodar.')
    return
  }
  console.log(`Encontrei ${pdfs.length} PDF(s) em cvs/.`)
  console.log(`Endpoint: ${url}/functions/v1/extract-profile`)
  console.log(`User ID alvo: ${userId}`)
  console.log('---')

  const summaries: RunSummary[] = []
  for (const pdf of pdfs) {
    console.log(`→ ${pdf}`)
    const s = await runOne(url, serviceKey, userId, pdf)
    summaries.push(s)
    const tag = s.status === 'success' ? 'OK' : s.status.toUpperCase()
    const conf = s.confidence_global != null ? s.confidence_global.toFixed(2) : 'n/a'
    console.log(`  ${tag} • confidence=${conf} • ${s.experiences_count} exp • ${s.education_count} edu • ${s.skills_count} skills • ${s.duration_ms}ms`)
    if (s.error) console.log(`  error: ${s.error}`)
  }

  const successCount = summaries.filter(s => s.status === 'success').length
  const partialCount = summaries.filter(s => s.status === 'partial').length
  const failCount = summaries.length - successCount - partialCount
  const confidences = summaries
    .map(s => s.confidence_global)
    .filter((c): c is number => c != null)
  const avgConfidence = confidences.length > 0
    ? confidences.reduce((a, b) => a + b, 0) / confidences.length
    : 0

  console.log('---')
  console.log(`Resumo: ${successCount} success, ${partialCount} partial, ${failCount} failed`)
  console.log(`Confidence global médio: ${avgConfidence.toFixed(2)}`)
  console.log(`Resultados em outputs/`)
}

main().catch(e => {
  console.error('Fatal:', e)
  Deno.exit(1)
})
