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
 * Peso de Localização e de Modelo no Cenário A do prompt (`index.ts`, seção
 * ESTRATÉGIA: Área 30, Tipo 20, Localização 15, Modelo 15, Skills 10).
 */
const PESO_DIMENSAO = 15

/**
 * Rótulo comparável: sem acento, sem caixa, sem espaço nas bordas.
 *
 * O casamento era por string exata em minúsculas, então qualquer variação que o
 * modelo devolvesse ("Localizacao", "LOCALIZAÇÃO ") escapava da reconciliação
 * em silêncio — e o usuário via a penalidade falsa de novo.
 */
function canonical(label: string): string {
  return String(label ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toLowerCase()
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
 * Mesma doutrina do score: a IA propõe, o código determinístico valida.
 *
 * REVISÃO 29/07 — esconder não era corrigir. A primeira versão apenas REMOVIA a
 * linha de Localização, então a vaga remota continuava sem os 15 pontos dela e
 * tetava em 85 enquanto a mesma vaga na cidade da pessoa chegava a 100. A
 * penalidade tinha virado invisível em vez de deixar de existir — e o
 * "Esperado" do achado é literalmente que vaga remota NÃO perca ponto por
 * cidade. Pior: o cálculo determinístico do cliente já dava esses 15 pontos, e
 * os dois motores divergiam na mesma vaga.
 *
 * A regra agora é uma só, e vale para as duas dimensões: **se remoto serve para
 * você, onde você mora não conta contra**.
 *  - Modelo e Localização viram matched com peso cheio (15) quando a vaga é
 *    remota E o candidato aceita remoto.
 *  - Se o candidato NÃO aceita remoto, nada é mexido: a vaga é um desencontro
 *    real e o score deve dizer isso.
 *  - Localização ausente é INSERIDA nesse caso. Sem isso, duas vagas remotas
 *    pontuariam diferente só porque o modelo emitiu a linha numa e não na
 *    outra — medido: 2.343 de 3.132 análises remotas trazem a linha.
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

  // Sem aceitar remoto, a vaga é desencontro real: não mexe em nada.
  if (!acceptsRemote) return reasons

  let sawLocation = false
  const out: MatchReason[] = []
  for (const r of reasons) {
    const label = canonical(r.label)

    if (label === 'modelo' && !r.matched) {
      out.push({
        ...r,
        matched: true,
        // Peso FORÇADO, não herdado. A IA costuma mandar weight 0 quando
        // considera a dimensão falha — herdar isso consertaria o texto e
        // deixaria o ponto para trás, que é o defeito que estamos fechando.
        weight: PESO_DIMENSAO,
        detail: 'Remoto, que é como você prefere trabalhar.',
      })
      continue
    }

    if (label === 'localizacao') {
      sawLocation = true
      if (!r.matched) {
        out.push({
          ...r,
          matched: true,
          weight: PESO_DIMENSAO,
          detail: 'Vaga remota — de onde você mora não pesa aqui.',
        })
        continue
      }
    }

    out.push(r)
  }

  // Linha ausente é inserida, senão duas vagas remotas pontuam diferente só
  // porque o modelo emitiu a dimensão numa e não na outra.
  if (!sawLocation) {
    out.push({
      label: 'Localização',
      matched: true,
      weight: PESO_DIMENSAO,
      detail: 'Vaga remota — de onde você mora não pesa aqui.',
    })
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
