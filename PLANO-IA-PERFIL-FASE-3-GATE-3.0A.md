# Fase 3 — Gate 3.0A: fundação segura de escrita guiada

## Status

Implementado, integrado à fundação de Fonte importada e validado localmente.
Não foi commitado nem implantado. Os novos RPCs ainda não foram ligados aos
callers Flutter; a UI da Fase 2 já consulta a feature flag, que nasce OFF/0%
num banco novo. Esta rodada não consulta nem altera o estado remoto.

Este gate prepara contratos server-side para skills, interesses, idiomas e
áreas desejadas. Ele não muda telas, navegação nem o comportamento visível do
usuário.

## Contratos preparados

- replace atômico de skills e interesses, preservando IDs e metadados dos itens
  que continuam na lista;
- replace atômico de áreas, com precedência explícita de fontes;
- merge guiado aditivo e idempotente, sem apagar informação manual;
- compare-and-set do nível de idioma: uma edição manual mais recente vence;
- um lock único por usuário para writers autenticados e para o import;
- validação fail-closed de payload, permissões e duplicatas semânticas.

## Integração concluída

As migrations estacionadas foram incorporadas seletivamente, sem trazer UI,
Dart ou Edge Functions da outra branch:

1. `20260714120000_saved_resumes_import_metadata.sql`;
2. `20260714130000_save_profile_fill_empty.sql`;
3. `20260717120000_seed_trilha_assist_v1.sql`;
4. `20260717130000_profile_guided_write_foundation.sql`.

A cadeia foi reconciliada para ter uma única infraestrutura de lock e um único
`save_profile_from_json` canônico. A migration guiada reutiliza o writer seguro
de 14/07 em vez de renomeá-lo e embrulhá-lo novamente. As duas migrations de
14/07 agora são explicitamente transacionais. Também ficaram privados, já na
fronteira entre elas, o helper de lock e a promoção direta aposentada.

## Decisão de compatibilidade

Os índices normalizados globais ficaram fora deste gate. Writers antigos ainda
usam regras diferentes de conflito; criar esses índices agora poderia quebrar
um fluxo antigo mesmo com a flag desligada. Por enquanto, cada RPC nova verifica
a sua própria seção sob lock e, se encontrar ambiguidade, falha sem escolher,
mesclar ou apagar dados.

Os índices só entram no cutover em que todos os writers estiverem unificados.

## Evidências locais

- PostgreSQL 17 efêmero: T1–T10 verdes no harness guiado isolado;
- harness completo de Fonte importada verde, seguido no mesmo banco pelas duas
  migrations de 17/07 e pelos contratos combinados C1–C4; cadeia concorrente
  reforçada repetida 3 vezes, sem flake;
- concorrência writer manual × RPC: verde, sem deadlock;
- concorrência import × writer manual: verde, sem deadlock;
- concorrência fill-empty × merge guiado nas duas ordens: verde, sem mistura,
  perda ou deadlock;
- concorrência do `save_profile_from_json` real (service-role) × merge guiado:
  verde, preservando os dois lados e sem deadlock;
- vínculo canônico de skill e trigger de completude simulados no harness
  combinado; replace/reorder não perdem ID, categoria nem vínculo;
- RLS, ACL, rollback, idempotência, CAS e oito caminhos fail-closed cobertos;
- `flutter test`: 577 testes verdes;
- request contract da Edge Function: 5 testes verdes;
- 31 entrypoints de Edge Functions passam no check oficial do repositório;
- manifest: 118 migrations; segurança de ambiente: OK.

## Condições que continuam obrigatórias antes de deploy

1. Manter no manifest a ordem 14/07 → 17/07.
2. Aplicar e validar a cadeia num ambiente de release antes de produção.
3. Não ligar `trilha_assist_v1` neste ponto.
4. Fazer o cutover dos callers Flutter somente em um checkpoint separado, com
   testes de recibo/CAS e rollback.

## Próximo gate correto

Substituir, de forma incremental, os writers antigos de listas pelos contratos
atômicos e adicionar recibos/CAS às operações e aos cards de lista ainda não
cobertos, para impedir que um card antigo reintroduza algo removido manualmente.
Os recibos da importação e o CAS de idioma já existem. Somente esse cutover,
seguido da suíte completa e de teste em device, autoriza avaliar rollout da
flag.
