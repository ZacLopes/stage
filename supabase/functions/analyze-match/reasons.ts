// Razões do match — parte determinística, separada do `index.ts` para poder
// ser TESTADA. O `index.ts` termina num `Deno.serve(...)` de módulo: importá-lo
// num teste subiria um servidor e travaria a suíte.
//
// R6: extração mecânica, sem mudança de comportamento. O `index.ts` passa a
// importar daqui.

export interface MatchReason {
  label: string
  matched: boolean
  weight: number
  detail?: string
}

/**
 * Normaliza work_mode do schema relacional (EN: `remote`/`hybrid`/`in_person`)
 * pro vocabulário que `jobs.work_model` usa (PT: `remoto`/`hibrido`/`presencial`).
 * Sem isso, a IA tentava casar "in_person" com "presencial" textualmente e
 * marcava matched=false mesmo o user tendo presencial nas prefs.
 *
 * Valores legacy (PT) passam intactos — `user_preferences.work_models`
 * sempre foi PT.
 */
export function normalizeWorkMode(s: string): string {
  switch (s) {
    case 'remote': return 'remoto'
    case 'hybrid': return 'hibrido'
    case 'in_person': return 'presencial'
    default: return s // já PT ou desconhecido — passa intacto
  }
}

/**
 * Correção determinística das razões de vaga REMOTA (revisão UX 28/07/2026).
 *
 * Dois defeitos observados ao vivo no detalhe da vaga, ambos vindos do modelo:
 *
 *  1. `{"label":"Modelo","matched":false,"detail":"Você prefere remoto, mas a
 *     vaga é remoto."}` — a frase se contradiz sozinha e conta um ACERTO como
 *     falha. É a mesma classe de erro que `normalizeWorkMode` já trata na
 *     ENTRADA (in_person × presencial); aqui tratamos a SAÍDA.
 *  2. "Localização — <cidade> não está entre suas cidades preferidas" numa vaga
 *     remota, contradizendo a regra que os filtros anunciam ("Remoto sempre
 *     passa"). Cidade não limita quem trabalha remoto.
 *
 * Mesma doutrina do score: a IA propõe, o código determinístico valida. Só
 * mexe no que é provavelmente errado — nunca inventa acerto onde não há:
 *  - Modelo só vira matched quando a vaga É remota E o candidato aceita remoto;
 *  - Localização só é REMOVIDA quando já vinha matched=false (contribuição 0),
 *    então a correção nunca infla nem reduz o score derivado por esta via.
 */
export function reconcileRemoteReasons(
  reasons: MatchReason[],
  // deno-lint-ignore no-explicit-any
  job: any,
  // deno-lint-ignore no-explicit-any
  prefs: any,
): MatchReason[] {
  const jobModel = normalizeWorkMode(String(job?.work_model ?? '').trim().toLowerCase())
  if (jobModel !== 'remoto') return reasons

  const accepted: string[] = Array.isArray(prefs?.work_models) ? prefs.work_models : []
  const acceptsRemote = accepted
    .map((w: unknown) => normalizeWorkMode(String(w ?? '').trim().toLowerCase()))
    .includes('remoto')

  const out: MatchReason[] = []
  for (const r of reasons) {
    const label = r.label.trim().toLowerCase()

    if (label === 'modelo' && acceptsRemote && !r.matched) {
      out.push({
        ...r,
        matched: true,
        // `weight` da dimensão vem da IA (15 no prompt). Se veio 0 — caso em
        // que ela considerou a dimensão inexistente — mantemos 0 e o score não
        // muda; corrigimos só a leitura contraditória.
        detail: 'Remoto, que é como você prefere trabalhar.',
      })
      continue
    }

    // Vaga remota: a dimensão localização não se aplica. Some a linha em vez de
    // exibir uma penalidade falsa com ⊖.
    if (label === 'localização' && !r.matched) continue

    out.push(r)
  }

  // Log distinto: sem isto a correção apareceria só como "score divergence" e
  // seria confundida com regressão do modelo. Mede quanto o gpt erra aqui.
  if (out.length !== reasons.length || out.some((r, i) => r !== reasons[i])) {
    console.log(
      `[analyze-match] remote reasons reconciled job=${job?.id ?? '?'} ` +
        `acceptsRemote=${acceptsRemote} before=${reasons.length} after=${out.length}`,
    )
  }
  return out
}
