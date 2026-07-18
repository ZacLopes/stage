# Fase 3 — Gate 3.0E: remoção/undo de skills com CAS + recibo durável

## Status

Planejado a partir da auditoria read-only de 17/07. Branch
`refactor/ia-fase-2-fechamento`, HEAD `6f2ed19`. Dart-only (reusa o contrato
3.0B; **nenhuma migration nova**). Flag `trilha_assist_v1` OFF/0. Sem push,
deploy, migration remota ou mudança de flag.

## Achado da auditoria (o fato vence)

- Remoção avulsa de skill hoje: `assistRemoveItem(userId, 'skill', value)`
  (`trilha_session.dart:999`) faz `getSkills` e `deleteSkill(id)` para **todo**
  registro cujo nome (lowercased) casa — **remove por nome ambíguo**, sem CAS,
  sem recibo, e o undo (re-add via merge) cria um id novo (não restaura).
- O fluxo do chat (`trilha_chat_controller.dart:2797`) tenta primeiro
  `assistReversibleRemover` (com checagem de estado observado + mensagem de
  stale) e **cai** no `assistItemRemover` (o remove por nome) quando o
  reversível devolve null. Para skills, `assistReversibleRemove` devolve null
  (skill não está no switch dele) → cai no caminho inseguro.
- O editor visual `edit_skills` (card) já usa o writer CAS 3.0B
  (`AssistSkillsWriter` open/apply/undo, recibo durável em
  `profile_assist_skill_operations`) — remoção **dentro do card** já é segura.
  O que falta é a remoção avulsa (comando "remova X").
- O writer 3.0B já é injetado no controller e no `resume_tab`.

## Objetivo

Rotear a **remoção avulsa de skill** pelo contrato CAS/recibo 3.0B, eliminando
o `deleteSkill` por nome ambíguo e dando CAS contra estado observado, recibo
durável, stale honesto e undo que restaura de verdade.

## Callers incluídos

1. `assistReversibleRemove` (`trilha_session.dart`): passa a tratar `'skill'`
   via `AssistSkillsWriter` (open baseline → apply lista reduzida → undo).
2. `resume_tab.dart`: injeta o writer 3.0B (o mesmo já usado pelo card) no
   callback `assistReversibleRemover`.
3. `trilha_chat_controller.dart`: adiciona `'skill'` ao conjunto de kinds
   "obrigatoriamente reversíveis", para a remoção de skill **nunca** cair no
   `assistItemRemover` inseguro (fail-closed em vez de delete por nome).

## Implementação esperada

- `assistReversibleRemove('skill', value, {skillsWriter})`:
  - sem writer → devolve null (fluxo legado; só alcançável com flag OFF, que
    nem usa este caminho);
  - `open(opId)` reserva o baseline autoritativo; `desired` = baseline menos o
    item cujo `foldSkillName` casa `value`;
  - se o item não está no baseline → null (nada a remover);
  - `apply(opId, expected=baseline, desired)`; só `applied` devolve o undo
    `() => writer.undo(opId, expectedRestored=baseline)`; `noop`/`stale`
    devolvem null (sem falso sucesso);
- Nada de `deleteSkill` por nome para skills. `assistRemoveItem` permanece
  apenas para interest/language (3.0F/G) e para o undo de add do conflito de
  import (3.0I).

## Contrato antes → depois

| | Antes | Depois |
|---|---|---|
| remoção de skill | `getSkills` + `deleteSkill(id)` por nome (todos que casam) | open→apply(lista reduzida) CAS 3.0B |
| CAS vs estado observado | nenhum | apply CAS a linha completa vs baseline |
| recibo | nenhum | durável (`profile_assist_skill_operations`) |
| stale | não detectado | apply devolve stale → não remove, sem falso sucesso |
| undo | re-add (id novo, perde metadados) | `writer.undo` restaura o estado exato |

## Testes obrigatórios

1. remoção reversível de skill: `applied` → devolve undo; skill sai da lista.
2. skill inexistente no baseline → null (nada removido).
3. apply `stale`/`noop` → null (sem falso sucesso).
4. undo restaura o baseline (spy confirma `writer.undo` com `expectedRestored`).
5. uma operação lógica = um `open`+`apply` (spy).
6. sem writer → null (não usa deleteSkill).
7. suíte completa + regressão flag OFF verdes; harnesses SQL do 3.0B (recibo
   CAS) verdes.

## Critério de pronto

- remoção de skill não usa mais `deleteSkill` por nome (via o fluxo do chat);
- CAS/recibo/stale/undo honestos, reusando 3.0B;
- 'skill' no conjunto reversível → nunca cai no remover inseguro;
- testes focados + suíte + analyzer baseline + harnesses verdes;
- flag OFF/0; sem operação remota.

## Fora do Gate 3.0E

remoção de idiomas/interesses (3.0F/G); undo do add no conflito de import
(3.0I); replace/rename manual (3.0C/3.0D, já feitos); UI/navegação; Edge;
migration nova.

## Condições de parada

Parar se: a remoção não puder ser expressa pelo contrato 3.0B sem novo RPC; o
stale não puder ser sinalizado honestamente ao fluxo do chat; surgir
necessidade de tocar idiomas/interesses/import/UI. Ao terminar, parar; não
iniciar o Gate 3.0F.

## Risco conhecido

O closure de undo do padrão reversível é `Future<void>` — se o usuário mudar as
skills depois da remoção, `writer.undo` devolve `stale` (não restaura) e o
closure completa sem restaurar. É o comportamento honesto server-side do 3.0B
(não sobrescreve edição mais nova); a folha de undo pode não refletir isso
visualmente. Registrar no relatório.
