import { assert, assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts'
import { findUnsupportedExperienceClaims } from './experience_claim.ts'

/// Trava os quatro buracos que a auditoria de 29/07 mediu no anti-invenção.
///
/// O achado P0-2 diz que o CV adaptado afirma experiência que a pessoa não tem,
/// sob o selo "Nenhuma informação foi inventada". A primeira correção (28/07)
/// fechou só a forma mais literal; estes casos são as outras três.
///
/// Direção dupla, de propósito: os `rejeita` pegam o validador ficando frouxo,
/// os `aceita` pegam ele ficando estrito demais — que é o erro pior, porque
/// deixa gente honesta sem currículo (foi o BLOQUEADOR C do golden set).

function claims(real: number, summary: string, outExp = 0) {
    return findUnsupportedExperienceClaims(real, summary, outExp)
}

// ── Buraco 1: cargo inventado no ARRAY (nenhum regex de prosa pega) ──────────
Deno.test('rejeita: perfil sem experiência recebe bloco de experiências preenchido', () => {
    // Foi assim que 3 currículos saíram em produção, com até 3 cargos.
    const found = claims(0, 'Estudante de Engenharia.', 3)
    assertEquals(found.length, 1)
    assertEquals(found[0].field, 'experiences')
})

Deno.test('aceita: perfil COM experiência recebe bloco preenchido', () => {
    assertEquals(claims(2, 'Analista com 2 anos de experiência em dados.', 2).length, 0)
})

// ── Buraco 2: o regex só pegava "experiência" colada numa preposição ─────────
const VARIANTES_QUE_PASSAVAM = [
    'Estudante com experiência prática em elaboração de relatórios',
    'Profissional com experiência acadêmica em cotações com fornecedores',
    'Atuei na elaboração de relatórios financeiros',
    'Já trabalhei com gestão de estoque e logística',
    'Responsável pela operação de compras da empresa',
    'Experiente em análise de dados e automação',
]

for (const frase of VARIANTES_QUE_PASSAVAM) {
    Deno.test(`rejeita: "${frase.slice(0, 42)}…"`, () => {
        const found = claims(0, frase)
        assert(found.length > 0, 'passou batido — é a mesma mentira do achado')
        assertEquals(found[0].field, 'summary')
    })
}

// ── Buraco 3: LIMITE CONHECIDO, não fechado nesta fatia ─────────────────────
// Tentei gatilhar por CONTAGEM (>= 2) e o golden set reprovou na hora: quem tem
// 1 experiência real PODE dizer "experiência em X". Julgar "5 anos" exige a
// DURAÇÃO, que o predicado não recebe. Este teste FIXA o comportamento atual
// para ninguém achar que está coberto.
Deno.test('LIMITE: com 1 experiência a prosa não é checada (falta duração)', () => {
    assertEquals(claims(1, 'Profissional com 5 anos de experiência em Suprimentos.').length, 0)
})

Deno.test('aceita: perfil com 1 experiência pode dizer "experiência em"', () => {
    assertEquals(claims(1, 'Analista com experiência em Suprimentos.').length, 0)
})

Deno.test('mas o cargo inventado é pego mesmo com prosa limpa', () => {
    assertEquals(claims(0, 'Estudante de Administração.', 2).length, 1)
})

// ── A direção oposta: frase de busca é legítima e TEM que passar ─────────────
const FRASES_HONESTAS = [
    'Estudante buscando experiência em Suprimentos',
    'Em busca da primeira experiência profissional',
    'Sem experiência prévia, com forte interesse em logística',
    'Procuro oportunidade de ganhar experiência em dados',
    'Student seeking experience in supply chain',
]

for (const frase of FRASES_HONESTAS) {
    Deno.test(`aceita: "${frase.slice(0, 42)}…"`, () => {
        assertEquals(claims(0, frase).length, 0, 'barrou frase honesta — deixaria a pessoa sem CV')
    })
}

// ── Bordas ──────────────────────────────────────────────────────────────────
Deno.test('summary vazio ou nulo não quebra nem acusa', () => {
    assertEquals(claims(0, '').length, 0)
    assertEquals(findUnsupportedExperienceClaims(0, null).length, 0)
    assertEquals(findUnsupportedExperienceClaims(0, undefined).length, 0)
})

Deno.test('acento e caixa não escapam da checagem', () => {
    assert(claims(0, 'EXPERIÊNCIA EM VENDAS').length > 0)
})
