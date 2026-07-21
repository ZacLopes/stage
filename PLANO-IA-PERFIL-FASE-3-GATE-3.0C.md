# Fase 3 — Gate 3.0C: cutover da escrita ADITIVA de skills da coleta guiada

## Status

Planejado a partir da auditoria read-only de 17/07/2026. A branch é
`refactor/ia-fase-2-fechamento`, HEAD `24007c2`, working tree preservado
integralmente. Este gate NÃO autoriza commit, push, deploy, migration remota,
`db push` nem alteração de flag. A flag `trilha_assist_v1` permanece OFF/0.

O escopo é deliberadamente pequeno: apenas os **dois writers aditivos de skills
da coleta guiada** passam a usar o contrato server-side aditivo/idempotente
`merge_guided_profile_list(section='skills')`, já entregue na fundação do
Gate 3.0A (`20260717130000_profile_guided_write_foundation.sql`). Nenhuma
migration nova é criada; a fundação já existe e não é tocada.

## Achado da auditoria (o fato vence)

A auditoria confirma o handoff sem contradição e sem exigir expansão:

- `TrilhaWriteback._saveSkills` (`trilha_writeback.dart:385`) faz
  `getSkills → replaceSkills([...existentes, ...novas])` — leitura seguida de
  escrita multi-request (janela TOCTOU).
- `TrailToProfileBridge._routeT4` (`trail_to_profile_bridge.dart:294`, ramo
  `m4_1`/`m4.1`) faz o mesmo `getSkills → replaceSkills`.
- `merge_guided_profile_list(p_user_id, 'skills', p_items)` já existe, é
  aditivo (só INSERE skills novas, nunca UPDATE/DELETE), idempotente por chave
  normalizada, roda sob o advisory lock canônico por usuário, é fail-closed em
  ACL/payload e retorna `{status, inserted, updated, changed}`. **Não tem caller
  Flutter nesta branch** (grep confirmou zero referências em `lib`/`test`).
- Os outros `replaceSkills` (editor manual em `ProfileEditorViewModel` /
  `profile_section_list.dart` e a implementação `ProfileRepositorySupabase`)
  são REPLACE manual — fora do escopo (pertencem ao Gate 3.0D).
- Superfícies que chegam indiretamente a `_saveSkills` e ficam cobertas pelo
  mesmo cutover, por construção: `gap.skills`, `gap.skills.more.*`, adição de
  skill por tool (`assistAddItem('skill', …)` → `save(StepAnswer.choice(
  'gap.skills', …))`) e o batch de coleta.

## Objetivo

Migrar **somente a escrita aditiva de skills da coleta guiada** para:

```text
merge_guided_profile_list(p_user_id: user, p_section: 'skills', p_items: [...])
```

Isto elimina o TOCTOU `get → replace` e garante que uma resposta da coleta
guiada **adiciona** fatos confirmados sem apagar skills editadas manualmente.

## Callers incluídos

1. `TrilhaWriteback._saveSkills` — cobre `gap.skills`, `gap.skills.more.*`,
   adição de skill por tool e batch de coleta (todos passam por este método).
2. `TrailToProfileBridge` — ramo de skills de `_routeT4` (`m4_1`/`m4.1`), que
   continua registrado no `GamificationViewModel` e não pode ficar como writer
   concorrente esquecido.

## Implementação

Espelha o padrão tipado/fail-closed do Gate 3.0B (`assist_skills_write.dart` +
`assist_skills_writer_supabase.dart`):

- **Domínio (novo)** `lib/features/trilha/domain/guided_skills_write.dart`:
  - `GuidedProfileMergeContractException` (fail-closed);
  - `GuidedSkillsMergeReceipt.fromRpc(Object?)` — aceita apenas
    `status ∈ {applied, noop}`; exige `inserted/updated/changed` inteiros ≥ 0;
    exige `updated == 0` (skills é aditivo puro, nunca UPDATE de linha);
    exige `changed == inserted + updated`; exige `applied ⇔ changed > 0`;
  - interface `GuidedSkillsWriter { Future<GuidedSkillsMergeReceipt>
    mergeSkills({required userId, required names}) }`.
- **Dados (novo)** `lib/features/trilha/data/guided_skills_writer_supabase.dart`:
  - `GuidedSkillsWriterSupabase implements GuidedSkillsWriter`, injetável via
    `rpcCall`/`client` (não acopla domínio ao singleton Supabase);
  - normaliza o payload (`normalizeSkillNames` — trim/colapso/dobra de acento,
    dedup preservando ordem/grafia), recusa payload vazio e payload > 50 itens
    (limite de array do contrato SQL) com `ArgumentError` antes do round-trip;
  - chama `merge_guided_profile_list` com `p_section='skills'` e devolve o
    recibo tipado. O limite server-side de 12 skills, quando estourado, volta
    como erro do RPC e propaga fail-closed (nunca vira sucesso).
- **Cutover** `TrilhaWriteback`: injeta `GuidedSkillsWriter` (default
  `GuidedSkillsWriterSupabase()`); `_saveSkills` passa a selecionar as skills
  não-vazias e chamar `mergeSkills` — **sem pré-leitura** (o RPC dedup/insere
  sob lock). Remove a chamada a `replaceSkills`.
- **Cutover** `TrailToProfileBridge`: injeta `GuidedSkillsWriter` e um resolver
  `currentUserId` (seam de teste, default `Supabase.instance…`); o ramo de
  skills chama `mergeSkills`. Mantém o `try/catch` defensivo pré-existente (a
  bridge nunca derruba a trilha legacy).
- **Costura testável** `trilha_session.dart`: `assistAddItem` recebe um
  `GuidedSkillsWriter?` opcional repassado ao `TrilhaWriteback` (o tool de
  adição de skill chega a `_saveSkills`).
- `GamificationViewModel` não muda (usa o default).

Sem renomear chaves internas/rotas, sem migration nova, sem tocar Edge, UI,
navegação, editor visual 3.0B, replace manual, remoções, idiomas, interesses,
áreas, coursework ou importação.

## Contrato antes → depois

| | Antes | Depois |
|---|---|---|
| `_saveSkills` | `getSkills` + `replaceSkills([...existentes,...novas])` (TOCTOU, multi-request) | `mergeSkills(names)` → 1 RPC aditivo sob lock |
| Bridge skills | `getSkills` + `replaceSkills` | `mergeSkills(names)` |
| Dedup | cliente (contra leitura possivelmente stale) | servidor, sob advisory lock, por chave normalizada |
| Skill manual editada concorrentemente | podia ser sobrescrita na janela | preservada (merge só adiciona) |
| Limite 12 | `ArgumentError` no cliente | RAISE `too_many_items` no RPC → propaga fail-closed |
| Recibo | nenhum | `GuidedSkillsMergeReceipt` tipado, fail-closed |

## Retry, concorrência, stale e erro

- **Retry:** merge é idempotente por chave normalizada; um retry após resposta
  ambígua termina como `applied`/`noop` sem duplicar. `ConversationController`
  já é fail-closed: falha de write-back não avança o passo, não entra no
  histórico e preserva a resposta para retry.
- **Concorrência:** o RPC pega o advisory `profile_write:<user>` antes de tuple
  locks; skill manual concorrente é preservada (só há INSERT do que falta).
- **Stale/erro:** não há pós-leitura reinterpretada como sucesso; recibo
  malformado/contraditório e erro do RPC falham fechado.

## Testes obrigatórios (mapa)

| # | Critério | Onde |
|---|---|---|
| 1 | recibo `applied` válido | `guided_skills_writer_test.dart` (spy) |
| 2 | retry idempotente `noop` sem duplicar | writer test + SQL T4 |
| 3 | resposta malformada/status desconhecido falha fechado | writer test |
| 4 | payload inválido ou >12 não vira sucesso | writer test (empty/>50 ArgumentError; RPC throw propaga) |
| 5 | grafia equivalente não duplica | writer test (normalização) + SQL T4 ("Gestao"↔"Gestão") |
| 6 | manual × guided nas duas ordens preserva ambos | SQL harnesses (fill×guided, guided×fill, manual×RPC) |
| 7 | metadata/canonical ID/order manual não perdidos | SQL T4 (category/canonical_skill_id) |
| 8 | duas chamadas concorrentes sem duplicata/deadlock | SQL harnesses (manual×RPC, service×guided) |
| 9 | `gap.skills` e `gap.skills.more.*` usam o novo adapter | `trilha_writeback_test.dart` (spy; `replaceSkills` nunca chamado) |
| 10 | `TrailToProfileBridge` usa o mesmo contrato | `trail_to_profile_bridge_test.dart` (novo) |
| 11 | regressão flag OFF + suíte existente verdes | `flutter test` completo |
| 12 | RLS/ACL: usuário B não escreve perfil de A | SQL T3 (28000 / grants) |

## Critério de pronto

- não existe chamada a `replaceSkills` nos dois callers aditivos incluídos;
- uma resposta guiada nunca remove skill existente;
- retry idempotente e recibo contraditório falha fechado;
- concorrência real no harness Postgres preserva dados/metadados;
- testes focados, dois harnesses SQL e suíte completa verdes;
- analyzer no baseline (0 erros); manifest 119 e env safety OK;
- flag OFF/0; nenhum commit/push/deploy/migration remota;
- relatório lista honestamente os writers de skills ainda legados.

## Fora do Gate 3.0C

replace manual de skills; remoção/undo; editor visual 3.0B; idiomas,
interesses, áreas, coursework; importação/Fonte importada; UI/navegação; Edge
Functions; índices normalizados globais; migration nova; ativação de flag,
deploy ou migration remota.

## Condições de parada

Parar e pedir decisão se: o caller for na verdade replace/removal; o RPC não
expressar a política sem ampliar escopo; recibo/limite tiver contrato
contraditório; teste de concorrência perder dado/metadado; for preciso alterar
migration já aplicada remotamente; surgir necessidade de tocar
idiomas/interesses/áreas/import/UI. Ao terminar, parar para revisão
independente — não iniciar o Gate 3.0D.
