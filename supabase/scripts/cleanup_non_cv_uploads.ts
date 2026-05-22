// Script standalone para remover raw_text + parsed de usuários cujo
// upload era claramente NÃO um currículo (extrato bancário, doc gov.br,
// holerite). Roda do Mac do operador, idêntico em padrão ao
// backfill_parsed_cvs.ts.
//
// Uso:
//   # Dry-run (default — só mostra o que vai mudar):
//   deno run --allow-env --allow-net supabase/scripts/cleanup_non_cv_uploads.ts
//
//   # Apply (executa o UPDATE de verdade):
//   deno run --allow-env --allow-net supabase/scripts/cleanup_non_cv_uploads.ts --apply
//
// Variáveis de ambiente (mesmas do backfill_parsed_cvs.ts):
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//
// Contexto: 2 usuários foram detectados pós-hoc com conteúdo não-CV:
//   - b0bfa5d7-... (ananunew63u@gmail.com) — extrato Nubank 14k chars
//     com dados financeiros + dados de terceiros (Pix).
//   - 6298d344-... (joao.lautert@icloud.com) — doc gov.br com CPF,
//     nome da mãe, endereço.
//
// Ação: remove raw_text, parsed e todos os campos de metadata do
// parsing. Adiciona `removed_at` + `removed_reason` pra auditoria.
// Mantém o user_profile intacto (não apaga conta).
//
// Irreversível por design — esses dados nunca deveriam ter sido
// armazenados (escopo do consentimento de upload era currículo, não
// extrato/documento).

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('ERRO: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios.')
  Deno.exit(1)
}

const args = Deno.args
const dryRun = !args.includes('--apply')

// IDs hardcoded — confirmados manualmente via inspeção do raw_text.
// Adicione novos IDs aqui SOMENTE depois de inspecionar o conteúdo
// e confirmar que é não-CV (não confiar só na heurística automática
// — falsos positivos existem).
const TARGETS = [
  {
    id: 'b0bfa5d7-1187-49fc-b254-d0a5006e0eb6',
    email: 'ananunew63u@gmail.com',
    reason: 'extrato bancário Nubank',
  },
  {
    id: '6298d344-d81a-44be-9fd5-51fbf6a15eac',
    email: 'joao.lautert@icloud.com',
    reason: 'documento gov.br',
  },
]

console.log('━'.repeat(60))
console.log(`cleanup_non_cv_uploads — modo: ${dryRun ? 'DRY-RUN' : 'APPLY (executando!)'}`)
console.log(`alvos: ${TARGETS.length}`)
console.log('━'.repeat(60))

async function sb(path: string, init?: RequestInit): Promise<Response> {
  return await fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
      ...(init?.headers ?? {}),
    },
  })
}

for (let i = 0; i < TARGETS.length; i++) {
  const target = TARGETS[i]
  console.log(`\n[${i + 1}/${TARGETS.length}] ${target.email} (${target.reason})`)

  // 1. Lê estado atual.
  const readResp = await sb(`/rest/v1/user_profiles?id=eq.${target.id}&select=id,email,gamification_data`)
  if (!readResp.ok) {
    console.log(`     ↳ ERRO ao ler: ${readResp.status} ${await readResp.text()}`)
    continue
  }
  const rows = await readResp.json()
  if (rows.length === 0) {
    console.log(`     ↳ não encontrado (já removido?)`)
    continue
  }
  const row = rows[0]
  const imported = row.gamification_data?.imported_resume ?? {}
  const rawTextLen = (imported.raw_text ?? '').length
  const hasParsed = imported.parsed != null
  const alreadyRemoved = imported.removed_at != null

  console.log(`     ↳ estado atual: rawLen=${rawTextLen} hasParsed=${hasParsed} alreadyRemoved=${alreadyRemoved}`)

  if (alreadyRemoved) {
    console.log(`     ↳ SKIP — já foi limpo em ${imported.removed_at}`)
    continue
  }

  if (rawTextLen === 0 && !hasParsed) {
    console.log(`     ↳ SKIP — nada pra limpar`)
    continue
  }

  if (dryRun) {
    console.log(`     ↳ DRY-RUN — apagaria raw_text (${rawTextLen} chars) + parsed + metadata`)
    continue
  }

  // 2. Monta novo imported_resume: tudo que não é raw_text/parsed/metadata,
  //    + audit fields.
  const cleaned: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(imported)) {
    if ([
      'raw_text',
      'parsed',
      'parsed_warnings',
      'parsed_at',
      'parser_version',
      'parser_model',
      'parser_source',
      'parsed_backfilled_at',
    ].includes(k)) {
      continue
    }
    cleaned[k] = v
  }
  cleaned.removed_at = new Date().toISOString()
  cleaned.removed_reason = `non_cv_content:${target.reason}`

  const updatedGd = {
    ...row.gamification_data,
    imported_resume: cleaned,
  }

  // 3. Update.
  const updateResp = await sb(`/rest/v1/user_profiles?id=eq.${target.id}`, {
    method: 'PATCH',
    body: JSON.stringify({ gamification_data: updatedGd }),
  })

  if (!updateResp.ok) {
    console.log(`     ↳ ERRO ao atualizar: ${updateResp.status} ${(await updateResp.text()).slice(0, 200)}`)
    continue
  }

  const updated = await updateResp.json()
  const newImported = updated[0]?.gamification_data?.imported_resume ?? {}
  const newRawLen = (newImported.raw_text ?? '').length
  const newHasParsed = newImported.parsed != null

  console.log(`     ↳ OK rawLen=${newRawLen} hasParsed=${newHasParsed} removed_at=${newImported.removed_at}`)
}

console.log('\n' + '━'.repeat(60))
if (dryRun) {
  console.log('DRY-RUN — nada foi escrito. Re-rode com --apply pra executar.')
} else {
  console.log('✅ Cleanup aplicado. Verifique:')
  console.log(`   SELECT id, email, gamification_data->'imported_resume'`)
  console.log(`   FROM user_profiles WHERE id IN (${TARGETS.map((t) => `'${t.id}'`).join(', ')});`)
}
