// Regra de identidade da folha de skills extras — achado P2-19.
//
// A tabela `skill_aliases` foi construída para ACHAR gente (busca do admin):
// ela junta "excel básico" e "excel avançado" na mesma canônica de propósito.
// Este arquivo trava a distinção que o conserto depende: só a classe `exact`
// pode autorizar o app a esconder um item da folha.
//
// Errar para o lado de esconder é INVISÍVEL — a pessoa perde uma linha do
// currículo e nunca fica sabendo. Errar para o lado de oferecer é chato e
// visível. Os casos abaixo fixam essa assimetria.

import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts'

/**
 * Mesma chave de IDENTIDADE do index.ts. Preserva `+` e `#` de propósito — o
 * `flatten` da busca joga fora todo não-alfanumérico e faz C, C++ e C# virarem
 * a mesma string.
 */
function flatten(raw: string): string {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ'
  const to = 'aaaaaeeeeiiiiooooouuuucn'
  let s = raw.trim().toLowerCase()
  for (let i = 0; i < from.length; i++) s = s.replaceAll(from[i], to[i])
  return s.replace(/[^a-z0-9+#]/g, '')
}

/**
 * Reproduz a expansão do index.ts: parte do que a pessoa declarou e cresce
 * SÓ pelos aliases `exact`.
 */
function expandirComExact(
  declaradas: string[],
  aliasesExact: Array<{ alias: string; canonica: string }>,
): Set<string> {
  const owned = new Set(declaradas.map(flatten).filter(Boolean))
  const porCanonica = new Map<string, string[]>()
  for (const { alias, canonica } of aliasesExact) {
    const a = flatten(alias)
    const c = flatten(canonica)
    if (!a || !c) continue
    if (!porCanonica.has(c)) porCanonica.set(c, [])
    porCanonica.get(c)!.push(a)
  }
  for (const [canon, aliases] of porCanonica) {
    const tem = owned.has(canon) || aliases.some((a) => owned.has(a))
    if (!tem) continue
    owned.add(canon)
    for (const a of aliases) owned.add(a)
  }
  return owned
}

const EXACT = [
  { alias: 'exel', canonica: 'Excel' },
  { alias: 'ms excel', canonica: 'Excel' },
  { alias: 'microsoft excel', canonica: 'Excel' },
  { alias: 'boa comunicação', canonica: 'Comunicação' },
]

Deno.test('o caso do achado: declarou e a folha reoferecia', () => {
  const owned = expandirComExact(['Excel', 'Power BI', 'Python'], EXACT)
  assertEquals(owned.has(flatten('Excel')), true)
  assertEquals(owned.has(flatten('Power BI')), true)
  assertEquals(owned.has(flatten('Python')), true)
})

Deno.test('sinônimo exact casa nas duas direções', () => {
  // Escreveu "exel", a vaga pede "Excel".
  assertEquals(expandirComExact(['exel'], EXACT).has(flatten('Excel')), true)
  // Escreveu "Excel", a vaga pede "ms excel".
  assertEquals(expandirComExact(['Excel'], EXACT).has(flatten('ms excel')), true)
})

Deno.test('"boa comunicação" é a mesma reivindicação que "Comunicação"', () => {
  const owned = expandirComExact(['boa comunicação'], EXACT)
  assertEquals(owned.has(flatten('Comunicação')), true)
})

Deno.test('NÍVEL não entra: quem tem básico não é dono do avançado', () => {
  // `excel avançado` é classe `level`, então NÃO está em EXACT — e por isso
  // não pode ser alcançado por quem declarou só "Excel". Se um dia alguém
  // mover essa linha para `exact`, este teste cai.
  const owned = expandirComExact(['Excel'], EXACT)
  assertEquals(owned.has(flatten('Excel avançado')), false)
})

Deno.test('COMPOSTO não entra: a segunda habilidade continua sendo oferecida', () => {
  // Quem escreveu "boa comunicação e atendimento ao cliente" tem Comunicação
  // carimbada; "Atendimento ao cliente" nunca entrou no perfil dela — e é
  // exatamente o tipo de linha que a folha deveria oferecer.
  const owned = expandirComExact(['boa comunicação e atendimento ao cliente'], EXACT)
  assertEquals(owned.has(flatten('Atendimento ao cliente')), false)
})

Deno.test('ESCOPO não entra: "informática" não prova "informática básica"', () => {
  const owned = expandirComExact(['informática'], EXACT)
  assertEquals(owned.has(flatten('Informática básica')), false)
})

Deno.test('sem aliases (coluna ainda não aplicada) ainda resolve o achado', () => {
  // Failure-open: se a leitura da classificação falhar, a comparação literal
  // sozinha já tira o absurdo da frente da pessoa.
  const owned = expandirComExact(['Excel', 'Python'], [])
  assertEquals(owned.has(flatten('Excel')), true)
  assertEquals(owned.has(flatten('exel')), false)
})

Deno.test('perfil vazio não esconde nada', () => {
  assertEquals(expandirComExact([], EXACT).size, 0)
})

Deno.test('C, C++ e C# NÃO se confundem — são 3 habilidades do catálogo', () => {
  // Este é o defeito que a própria correção introduziu: a chave de BUSCA
  // (`flatten` do index.ts) descarta `+` e `#`, então as três viravam "c".
  // Quem declarou C# passaria a "possuir" C++ e perderia a chance de
  // reivindicá-lo — falso positivo silencioso, a classe que todo o trabalho
  // de classificação existe para evitar.
  const owned = expandirComExact(['C#'], [])
  assertEquals(owned.has(flatten('C#')), true)
  assertEquals(owned.has(flatten('C')), false)
  assertEquals(owned.has(flatten('C++')), false)

  const soC = expandirComExact(['C'], [])
  assertEquals(soC.has(flatten('C')), true)
  assertEquals(soC.has(flatten('C++')), false)
})

Deno.test('o ponto continua sendo ignorado: Node.js é nodejs', () => {
  // A chave preserva `+` e `#`, mas NÃO `.` — nenhum par do catálogo se
  // distingue só pelo ponto, e "Node.js"/"nodejs" são a mesma coisa.
  assertEquals(flatten('Node.js'), flatten('nodejs'))
  assertEquals(flatten('Vue.js'), flatten('vuejs'))
  assertEquals(flatten('Power BI'), flatten('powerbi'))
})

Deno.test('a família informática: nível NUNCA vira sinônimo pleno', () => {
  // O fixture deste arquivo só tinha Excel e Comunicação, e por isso ficou
  // VERDE enquanto a migration do rename deixava "informática básica"
  // classificada como `exact` — a classe que autoriza esconder. A auditoria
  // das migrations pegou o que o teste não pegava. Este caso existe para o
  // buraco não voltar.
  const EXACT_INFO = [
    { alias: 'informática', canonica: 'Informática' },
    { alias: 'conhecimento em informática', canonica: 'Informática' },
    { alias: 'habilidades em informática', canonica: 'Informática' },
  ]
  const owned = expandirComExact(['informática'], EXACT_INFO)

  // Sinônimos plenos entram.
  assertEquals(owned.has(flatten('Informática')), true)
  assertEquals(owned.has(flatten('conhecimento em informática')), true)

  // Nenhuma variação de NÍVEL entra — nem para baixo, nem para cima.
  for (const nivel of [
    'informática básica',
    'informática intermediária',
    'informática avançada',
    'noções de informática',
  ]) {
    assertEquals(owned.has(flatten(nivel)), false, nivel)
  }
})
