// bootstrap_ground_truth.ts
//
// Chama extract-profile pra cada PDF em cvs/ que ainda não tem ground_truth
// correspondente, salva o profile_data em ground_truth/cv_NNN.json como
// TEMPLATE INICIAL. Humano revisa e corrige.
//
// ATENÇÃO: NÃO usar pra CVs marcados como adversariais. Adversariais
// precisam de ground truth 100% manual (sem ver output da IA) pra evitar
// viés de auto-validação.
//
// Uso:
//   cd career_gamification/golden_set
//   deno run --allow-env --allow-net --allow-read --allow-write scripts/bootstrap_ground_truth.ts
//
// Cada arquivo gerado tem o campo "_bootstrap": true marcando que precisa
// de revisão humana antes de ser usado em compare.ts.

import { encode as encodeBase64 } from 'https://deno.land/std@0.224.0/encoding/base64.ts'

const ROOT = new URL('../', import.meta.url)
const CVS_DIR = new URL('./cvs/', ROOT)
const GROUND_TRUTH_DIR = new URL('./ground_truth/', ROOT)

async function loadEnv(): Promise<{ url: string; serviceKey: string; userId: string }> {
  const envPath = new URL('../.env', ROOT)
  let envText = ''
  try { envText = await Deno.readTextFile(envPath) } catch { /* ok */ }

  function get(name: string): string | undefined {
    const m = envText.match(new RegExp(`^${name}\\s*=\\s*(.+)$`, 'm'))
    if (m) return m[1].trim().replace(/^["']|["']$/g, '')
    return Deno.env.get(name)
  }

  const url = get('SUPABASE_URL')
  const serviceKey = get('SUPABASE_SERVICE_ROLE_KEY')
  const userId = get('GOLDEN_SET_USER_ID') ?? '00000000-0000-0000-0000-000000000001'
  if (!url || !serviceKey) {
    console.error('ERROR: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY required')
    Deno.exit(1)
  }
  return { url, serviceKey, userId }
}

async function exists(path: URL): Promise<boolean> {
  try { await Deno.stat(path); return true } catch { return false }
}

async function main() {
  const { url, serviceKey, userId } = await loadEnv()

  const pdfs: string[] = []
  for await (const e of Deno.readDir(CVS_DIR)) {
    if (e.isFile && e.name.toLowerCase().endsWith('.pdf')) pdfs.push(e.name)
  }
  pdfs.sort()

  for (const pdf of pdfs) {
    const cvId = pdf.replace(/\.pdf$/i, '')
    const gtPath = new URL(`${cvId}.json`, GROUND_TRUTH_DIR)

    if (await exists(gtPath)) {
      console.log(`SKIP ${cvId} — ground_truth já existe`)
      continue
    }

    const bytes = await Deno.readFile(new URL(pdf, CVS_DIR))
    const resp = await fetch(`${url}/functions/v1/extract-profile`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
        'X-Service-Role-Key': serviceKey,
      },
      body: JSON.stringify({
        pdf_base64: encodeBase64(bytes),
        user_id: userId,
        force: true,
      }),
    })

    if (!resp.ok) {
      console.log(`FAIL ${cvId} — HTTP ${resp.status}`)
      continue
    }

    const body = await resp.json()
    const template = {
      _bootstrap: true,
      _generated_at: new Date().toISOString(),
      _note: 'Template inicial via extract-profile. REVISAR e remover _bootstrap antes de usar em compare.ts. NÃO usar pra CVs adversariais.',
      _adversarial: false,
      ...body.profile_data,
    }

    await Deno.writeTextFile(gtPath, JSON.stringify(template, null, 2))
    console.log(`WROTE ${cvId} (review manualmente antes de remover _bootstrap)`)
  }
}

main().catch(e => {
  console.error('Fatal:', e)
  Deno.exit(1)
})
