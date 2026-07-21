# Fase 3 — Gate 3.0B: cutover seguro do editor de habilidades

## Status

Implementado e validado localmente. Não foi commitado, implantado nem aplicado
em banco remoto. A feature flag `trilha_assist_v1` continua OFF; este gate não
autoriza rollout.

O escopo deste checkpoint é deliberadamente pequeno: somente o editor visual de
habilidades aberto pelo Assistente passou a usar o novo contrato. A edição
manual em Perfil e os demais writers do Assistente continuam no caminho legado.

## O que mudou

- o card abre uma operação server-side com um `operation_id` estável e recebe o
  snapshot completo que será usado como baseline;
- aplicar usa compare-and-set sobre a linha completa — conteúdo, identidade,
  ordem e metadados — de modo que uma edição concorrente nunca é sobrescrita;
- recibos persistidos distinguem `applied`, `noop`, `stale` e `undone`, com
  replay idempotente e fail-closed para respostas inválidas;
- um resultado sem confirmação congela a mesma operação e o mesmo delta; o
  usuário pode tentar novamente, sem disparar uma segunda alteração diferente;
- desfazer só restaura o snapshot quando o estado vivo ainda corresponde ao
  resultado daquela operação; se houve edição posterior, retorna `stale`;
- `resulting` registra o resultado histórico da operação e `live` informa o
  estado atual, evitando atribuir ao card alterações posteriores;
- a UI não anuncia adições ou remoções em `noop`, encerra corretamente em
  `stale` e recarrega o perfil após todo resultado válido;
- a leitura de skills passou a ordenar explicitamente por
  `order_index ASC, id ASC`, igual ao contrato SQL, evitando falso `stale` em
  dados legados com empate de ordem;
- o writer novo só é construído quando a flag efetiva estiver ligada. Com a
  flag OFF, o fluxo anterior permanece intacto.

## Segurança e integridade

A migration `20260717140000_assist_skills_cas.sql` cria uma tabela privada de
operações e três RPCs autenticadas: abrir, aplicar e desfazer. Todas usam o lock
canônico por usuário, conferem posse, mantêm recibos idempotentes e não concedem
acesso a `anon` ou `service_role`.

Os testes cobrem concorrência manual × RPC, CAS × edição manual, duas aberturas
simultâneas do mesmo `operation_id`, writer de serviço × writer manual, replay,
timeout, `noop`, `stale`, undo e preservação integral de metadados. Uma remoção
posterior de catálogo canônico pode fazer o undo falhar e dar rollback; esse é
um comportamento seguro, pois não produz restauração parcial nem perda de dado.

## Evidências locais

- `flutter test`: 599 testes verdes;
- harness SQL isolado: T1–T15 e quatro matrizes de concorrência verdes;
- harness SQL combinado: `ALL_SQL_TESTS_OK` e
  `ALL_COMBINED_SQL_TESTS_OK`, sem deadlock;
- `flutter analyze --no-fatal-warnings`: 0 erros, 45 warnings e 582 infos,
  exatamente o baseline de 627 lints preexistentes;
- análise focada dos arquivos alterados: nenhum problema;
- `dart format`: 11 arquivos conferidos, todos formatados;
- sintaxe dos dois scripts de harness: válida;
- manifest: 119 migrations; segurança de ambiente: OK;
- `git diff --check`: limpo.

## O que este gate não resolve

- writers de adicionar/remover item e writeback guiado fora deste card;
- skills provenientes de extração/importação por caminhos legados;
- editores de idiomas, interesses, áreas e outros campos do perfil;
- edição manual de Perfil, que permanece com o comportamento atual;
- teste em device contra RPCs realmente implantadas;
- aplicação remota de migrations, commit, push, deploy ou ativação da flag.

## Próximo gate correto

O Gate 3.0C deve inventariar e cortar, um grupo por vez, os pontos restantes que
podem escrever skills e depois aplicar o mesmo padrão às outras listas. Cada
cutover precisa de recibo idempotente, proteção contra edição concorrente,
replay/undo honesto e teste com a flag ON e OFF.

Somente quando todos os writers de uma seção compartilharem o mesmo contrato,
e depois de aplicar as migrations num ambiente de release e fazer smoke test em
device, será seguro avaliar um rollout gradual. Até lá, a flag deve permanecer
OFF.
