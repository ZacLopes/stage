# Fase 3 — Gate 3.0F: idiomas (add / nível / remove) com contratos server-side

## Status

Implementado e validado localmente. Branch `refactor/ia-fase-2-fechamento`,
sobre `1572cd6` (3.0E). Flag `trilha_assist_v1` OFF/0. Sem push, deploy,
migration remota ou mudança de flag. **Inclui uma migration nova**
(`20260717160000_guided_language_remove_cas.sql`, manifest 121) — autorizada
pelo fundador ("3.0F completo, com migration"), não aplicada remotamente.

## Achado da auditoria

Idiomas tinham só DOIS contratos prontos na fundação 3.0A:
`merge_guided_profile_list('languages')` (add aditivo) e
`set_guided_language_level_cas` (CAS de nível). **Não havia** contrato de
remove nem de replace (`_replace_profile_simple_list` cobre só
skills/interesses). Os caminhos de escrita de idioma eram vários: guiado
(`TrilhaWriteback`), assistente (`assistUpsertLanguage`, `assistRemoveItem`),
bridge, editor manual (Perfil/resume).

## Escopo entregue (guiado/Assistente)

1. **Add** — `TrilhaWriteback._saveLanguages` → `merge_guided_profile_list(
   'languages')` (sem pré-leitura; insere só novos, nível null; 'none' pula).
2. **Nível** — `TrilhaWriteback._saveLanguageLevel` → `set_guided_language_
   level_cas` com `expected = nível observado` (CAS; manual recente vence;
   idioma inexistente = no-op).
3. **Remove** — `assistRemoveItem('language')` (delete por nome) → roteado por
   `assistReversibleRemove('language')` usando o novo `remove_guided_language_
   cas`: CAS contra o nível observado, devolve o nível removido; undo re-add
   (merge) + restaura o nível. `'language'` entrou no conjunto reversível do
   `trilha_chat_controller` → nunca cai no remover por nome inseguro.
   `resume_tab` injeta o writer de idioma (só com a flag ON).

## Migration nova

`20260717160000_guided_language_remove_cas.sql`: `remove_guided_language_cas(
p_user_id, p_name, p_expected_level)` — `SECURITY DEFINER SET search_path=''`,
sob o advisory lock por usuário, `_assert_profile_list_unique`, casa a chave
normalizada; `not_found` / `stale`(live_level) / `applied`(level removido).
REVOKE de PUBLIC/anon/service_role; GRANT só authenticated. Aditiva.

## Adapter Dart

`GuidedLanguageWriter` (domínio) + `GuidedLanguageWriterSupabase` (dados),
injetável, com recibos tipados fail-closed: `GuidedLanguageMergeReceipt`
(updated==0), `GuidedLanguageLevelReceipt` (applied/noop/stale/not_found +
live_level), `GuidedLanguageRemoveReceipt` (applied+level / stale+live_level /
not_found). Níveis validados contra `native|fluent|advanced|intermediate|basic`.

## Contrato antes → depois

| | Antes | Depois |
|---|---|---|
| add | get + `addLanguage` por novo | 1 merge aditivo sob lock |
| nível | get + `updateLanguage` incondicional | CAS vs nível observado (stale = manual vence) |
| remove | `deleteLanguage` por nome ambíguo | `remove_guided_language_cas` CAS de nível + undo honesto |

## Testes

- `flutter test`: **660** (20 novos 3.0F).
- Focados adapter/remove: **18**.
- Harness 1: **T6b** (ACL + CAS de nível + not_found) + T1–T15; harness 2 OK.
- Analyzer 627 (0 erros, baseline, sem reflow); manifest 121; env/deno/diff OK.

## Fora do escopo (legado, follow-up)

- **`assistUpsertLanguage`** (upsert do card): o `set_guided_language_level_cas`
  exige nível NÃO-null, então **limpar** o nível (set null) não é expressável —
  o card fica no caminho legado até existir um contrato de clear-level.
- **Bridge** (`_routeT4` idioma, dual-write da trilha gamificada) — secundário.
- **Editor manual** de idioma (Perfil/resume `updateLanguagesStructured`) —
  precisa de um replace atômico de {nome, nível} (análogo ao skills 3.0D);
  gate próprio.
- Interesses e áreas: 3.0G.

## Risco conhecido

Undo do remove é `Future<void>`: re-add (merge) sempre funciona, mas o
`setLevel` de restauração pode voltar `stale` se o usuário mexer no idioma
depois — honesto server-side (não sobrescreve edição mais nova), a folha de
undo pode não refletir. Co-deploy: as migrations 130000–160000 sobem juntas
(Gate 3.0J).
