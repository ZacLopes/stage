import { assert, assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts'

/// Guarda contra a classe de drift que aconteceu de verdade (29/07): o SERVIDOR
/// deixou de oferecer uma capacidade que o CLIENTE já implementava, e o prompt
/// passou a mandar o modelo NEGAR essa capacidade.
///
/// Histórico: `41ab981` (17/07) removeu `import_cv` junto com o pipeline de
/// escrita inseguro. Os Gates 3.0I (19/07) e `35e4175` (27/07) reconstruíram o
/// import pelo chat com RPCs atômicos e fiaram `assistImportCv` na composição
/// de produção (`resume_tab.dart`) — mas o servidor ficou para trás. Resultado:
/// `trilha_chat_controller.dart` tinha `case 'import_cv'` inalcançável e o
/// assistente responderia "indisponível" com o fluxo seguro pronto ao lado.
///
/// É um teste de FONTE, não de runtime: `index.ts` termina em `serve(...)` e
/// importá-lo subiria um servidor. O que precisa ser travado aqui é o contrato
/// entre os dois lados, que vive no texto do catálogo e do prompt.
const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url))
const controller = await Deno.readTextFile(
    new URL(
        '../../../lib/features/trilha/presentation/trilha_chat_controller.dart',
        import.meta.url,
    ),
)

function toolNames(source: string): string[] {
    return [...source.matchAll(/name: '([a-z_]+)',/g)].map((m) => m[1])
}

Deno.test('oferece import_cv — o cliente tem o fluxo seguro fiado', () => {
    assert(
        toolNames(src).includes('import_cv'),
        'import_cv sumiu do catálogo; o cliente tem case + _handleImportCv (Gate 3.0I)',
    )
})

Deno.test('o prompt NÃO manda negar a importação', () => {
    assert(
        !/importa\w*\s+pelo\s+Assistente\s+est[áa]\s+temporariamente\s+indispon/i.test(src),
        'o prompt manda o modelo dizer que importar CV está indisponível, mas o fluxo existe',
    )
})

Deno.test('toda tool oferecida é tratada pelo cliente', () => {
    // O servidor propõe; o cliente executa. Uma tool sem `case` no controller é
    // um turno que morre em silêncio na mão do usuário.
    const semCase = toolNames(src).filter(
        (t) => !controller.includes(`case '${t}':`),
    )
    assertEquals(semCase, [], `tools sem tratamento no cliente: ${semCase.join(', ')}`)
})

Deno.test('não reabre os editores replace-all sem CAS', () => {
    // edit_areas/edit_interests continuam FORA de propósito: seus callbacks
    // replace-all não são injetados na composição de produção (ao contrário de
    // skills/idiomas, que ganharam writers CAS nos gates 3.0B/3.0C/3.0F).
    const nomes = toolNames(src)
    assert(!nomes.includes('edit_areas'), 'edit_areas voltou sem writer CAS')
    assert(!nomes.includes('edit_interests'), 'edit_interests voltou sem writer CAS')
})
