# Fase 3 — Gate 3.0D: cutover do replace MANUAL de skills (Perfil)

## Status

Planejado a partir da auditoria read-only de 17/07/2026. Branch
`refactor/ia-fase-2-fechamento`, HEAD `41ab981` (commit de consolidação
Fase 2 + 3.0A/B/C). Este gate NÃO autoriza commit adicional sem pedido, push,
deploy, migration remota, `db push` nem alteração de flag.

Escopo pequeno: a **edição manual de skills em Perfil** deixa de usar o writer
cliente `get → múltiplos insert/update → delete` e passa a usar o contrato
atômico `replace_profile_skills_atomic_v1`, já entregue na fundação do
Gate 3.0A (`20260717130000_profile_guided_write_foundation.sql`). **Nenhuma
migration nova** — o RPC já existe. É Dart-only.

## Achado da auditoria (o fato vence)

- `ProfileEditorViewModel.replaceSkills` (`profile_editor_view_model.dart:355`)
  normaliza, faz update otimista da UI e chama `_repo.replaceSkills`.
- `ProfileRepositorySupabase.replaceSkills`
  (`profile_repository_supabase.dart:546`) faz `getSkills` + N insert/update +
  delete — multi-request, sem transação/lock (janela de falha parcial).
- Após o Gate 3.0C, **só o editor manual** ainda usa `replaceSkills`
  (`ProfileEditorViewModel` → repo; `profile_section_list.dart:223` → VM).
  Trilha e bridge já saíram desse método.
- `replace_profile_skills_atomic_v1(p_user_id, p_names)` já existe, é
  `SECURITY DEFINER`, `GRANT` só para `authenticated`, roda sob o advisory lock
  por usuário, preserva IDs/metadados (category/canonical_skill_id) dos itens
  retidos, faz replace atômico, limita a 12 e retorna `{status, count}`.
- `profile_skills` tem `UNIQUE(user_id, LOWER(name))`; duplicatas semânticas
  legadas só existem em variantes de acento/whitespace (raras), que
  `_assert_profile_list_unique` recusa (`duplicate_profile_skills_require_review`).
- `ProfileRepositorySupabase` aceita `SupabaseClient` injetável; o padrão de
  teste do repo usa `MockClient` (http) para interceptar a chamada REST.

## Objetivo

Ligar o replace **manual** de skills ao contrato atômico:

```text
replace_profile_skills_atomic_v1(p_user_id: user, p_names: [...])
```

Eliminando a janela `get → replace` multi-request e garantindo replace
atômico com preservação de IDs/metadados e política "usuário manual é
autoritativo" (a lista enviada É o estado final desejado).

## Caller incluído

- `ProfileRepositorySupabase.replaceSkills` — único caller do replace manual
  após o 3.0C. `ProfileEditorViewModel`, `profile_section_list` e a interface
  `ProfileRepository.replaceSkills` permanecem inalterados.

## Implementação esperada

- **Domínio (novo)** `lib/features/profile/domain/manual_skills_replace.dart`:
  `ManualSkillsReplaceReceipt.fromRpc(Object?)` — aceita apenas
  `status ∈ {applied, noop}` e `count` inteiro `0 ≤ count ≤` (nº de nomes
  enviados, deduplicados); qualquer divergência lança
  `ManualSkillsReplaceContractException` (fail-closed).
- **Cutover** `ProfileRepositorySupabase.replaceSkills`: normaliza (mantém o
  pré-check de 12 como ArgumentError, defensivo e paridade com o VM), chama
  `_client.rpc('replace_profile_skills_atomic_v1', {p_user_id, p_names})`,
  valida o recibo e retorna `void`. Remove o `getSkills` + insert/update/delete.
- Erros do RPC (`too_many_items`, `not_authorized`,
  `duplicate_..._require_review`) propagam como `PostgrestException` e são
  tratados pelo `try/catch` já existente do `ProfileEditorViewModel` (mostra
  erro, recarrega a lista viva) — sem falso sucesso.
- Sem tocar UI, navegação, VM, interface, Edge, migrations, flags, ou os
  writers guiados/CAS de skills (3.0B/3.0C).

## Contrato antes → depois

| | Antes | Depois |
|---|---|---|
| replace manual | `getSkills` + N insert/update + delete (multi-request) | 1 RPC atômico sob lock |
| Falha parcial | possível (janela entre writes) | impossível (transação única) |
| IDs/metadados | preservados por match manual (foldSkillName) | preservados pelo RPC (chave normalizada) |
| Duplicata legada (acento/ws) | colapsada silenciosamente no replace | recusada fail-closed (require_review) |
| Recibo | nenhum | `ManualSkillsReplaceReceipt` tipado |

## Retry, concorrência, stale e erro

- **Concorrência:** o RPC pega o advisory `profile_write:<user>` antes de tuple
  locks; um replace manual concorrente serializa sem deadlock (harness 3.0A).
- **Retry:** replace é idempotente — reenviar a mesma lista final retorna
  `noop`. O VM recarrega a lista viva após sucesso ou erro.
- **Erro:** recibo malformado falha fechado; erro do RPC propaga; nada é
  reinterpretado como sucesso.

## Testes obrigatórios

1. `replaceSkills` chama `rpc/replace_profile_skills_atomic_v1` com
   `p_user_id`/`p_names` normalizados (MockClient assere o request).
2. recibo `applied` aceito; `noop` aceito (idempotente).
3. resposta malformada/status desconhecido/count incoerente falha fechado.
4. `> 12` não vira sucesso (ArgumentError no pré-check; RPC também recusaria).
5. erro do RPC (`too_many_items`/`duplicate_require_review`/`not_authorized`)
   propaga, sem falso sucesso.
6. já NÃO faz `getSkills` + insert/update/delete (nenhuma chamada REST a
   `profile_skills` fora do rpc no caminho de replace).
7. suíte existente e regressão (flag OFF) continuam verdes; harnesses SQL do
   3.0A (que já exercitam `replace_profile_skills_atomic_v1`) verdes.

## Critério de pronto

- `replaceSkills` do repo usa só o RPC (sem get/insert/update/delete manuais);
- IDs/metadados preservados (garantido pelo contrato SQL, coberto no harness);
- recibo contraditório falha fechado; erro do RPC propaga honesto;
- testes focados + suíte completa + analyzer no baseline + harnesses SQL verdes;
- flag `trilha_assist_v1` OFF/0; nenhuma operação remota;
- relatório lista o comportamento de duplicata legada como mudança conhecida.

## Fora do Gate 3.0D

remoções/undo de skills (3.0E); idiomas/interesses/áreas (3.0F/G); escalares,
bullets, Edge writers (3.0H); import/conflito (3.0I); fluxo de de-duplicação de
skills legadas (não previsto — ver riscos); UI/navegação; migration nova; deploy.

## Condições de parada

Parar e pedir decisão se: a auditoria mostrar outro caller manual não
inventariado; o RPC não expressar o replace sem ampliar escopo; o recibo tiver
contrato contraditório; o comportamento de duplicata legada exigir um fluxo de
de-dup (expansão de escopo). Ao terminar, parar para revisão independente. Não
iniciar o Gate 3.0E.

## Correção do cutover — rename manual autoritativo (migration nova)

A revisão adversarial pegou uma regressão CONFIRMADA: o
`_replace_profile_simple_list` original conservava a grafia canônica de um item
retido e **descartava em silêncio** uma correção cosmética do usuário
(case/acento/whitespace) — violando "manual autoritativo" e "sem falso
sucesso". O fundador autorizou o conserto de verdade.

Migration `20260717150000_manual_skills_replace_authoritative.sql`
(`CREATE OR REPLACE` do helper, mesma assinatura, posição 120 do manifest):

- quando a grafia enviada difere do item retido → UPDATE inclui `name` (a
  grafia manual vence; o trigger de taxonomia recomputa canonical a partir do
  novo nome — idêntico ao caminho manual antigo);
- reorder puro (nome idêntico) → UPDATE só `order_index` (não dispara o
  trigger, canonical/metadados preservados);
- afeta `replace_profile_skills_atomic_v1` e
  `replace_profile_interests_atomic_v1` (ambos replace MANUAL); não toca o
  merge guiado nem a importação. Helper segue privado (REVOKE reafirmado).

Cobertura: harness T1 (reorder preserva metadados) + **T1b** (rename cosmético
vence, preservando ID/category/ordem) + C2 ajustado (re-save exato = noop).
Não há mudança no Dart: o repo já envia a grafia desejada.

**Este gate deixou de ser Dart-only** — inclui a migration acima (arquivo, não
aplicada remotamente).

## Risco conhecido remanescente (a destacar no relatório)

O editor manual antigo **colapsava** silenciosamente uma duplicata legada de
acento/whitespace ao salvar; o RPC **recusa** o save inteiro com
`duplicate_..._require_review` enquanto a duplicata existir no estado vivo. É o
comportamento fail-closed intencional do 3.0A ("nunca escolher/fundir/apagar
duplicata em silêncio"), mas cria um beco: o usuário não consegue salvar
skills até a duplicata ser resolvida. Um fluxo de de-dup dedicado fica fora
deste gate; o relatório deve registrar isso como decisão pendente.
