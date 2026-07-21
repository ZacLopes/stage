# Fase 3 — Gate 3.0G: interesses (replace atômico) — áreas ficam para a continuação

## Status

Implementado e validado localmente. Branch `refactor/ia-fase-2-fechamento`,
sobre `388c318` (3.0F). Dart-only (**sem migration** — reusa
`replace_profile_interests_atomic_v1` da fundação 3.0A). Flag OFF/0.

## Decisão de escopo (o handoff prevê "gates separados se políticas diferentes")

A auditoria confirmou que **interesses** e **áreas** têm políticas distintas:
interesses são lista simples (replace atômico pronto); áreas carregam **source
+ inferência canônica** (linhas ocultas `inferred`, precedência de fonte).
Portanto este gate cobre **interesses**; **áreas** ficam para a continuação
(3.0G-áreas), com o contrato `replace_profile_desired_titles_atomic_v1` +
`withInferredAreas`.

## Achado da auditoria (interesses)

Todos os writes de interesse passam por um único método:
`ProfileRepositorySupabase.replaceInterests`, que fazia **DELETE-all +
INSERT-all** — destrutivo (perdia IDs), não transacional, sem normalização.
Callers: `TrilhaWriteback._saveInterests` (gap.interests), `assistAddItem
('interest')`, `assistRemoveItem('interest')` (remove via replace(keep)) e o
editor manual (`ProfileEditorViewModel.replaceInterests`).

## Escopo entregue

Cutover de ponto único: `ProfileRepositorySupabase.replaceInterests` →
`replace_profile_interests_atomic_v1` (`_replace_profile_simple_list`,
manual-autoritativo desde o 3.0D): transação única sob o advisory lock,
preserva IDs dos itens retidos, autoritativo sobre a grafia, limite 50, recibo
tipado fail-closed (reusa o recibo genérico {status,count}). Um único ponto
cobre editor manual + guided add + remove + add-por-tool.

## Contrato antes → depois

| | Antes | Depois |
|---|---|---|
| replace de interesses | DELETE-all + INSERT-all (perde IDs, não atômico) | RPC atômico sob lock, preserva IDs, grafia autoritativa |
| recibo | nenhum | fail-closed (status/count) |
| duplicata legada / limite 50 | — | recusada/erro do RPC, propaga |

## Testes

- `flutter test`: **667** (7 novos).
- Focados replace-interesses (MockClient): **7** (request shape, sem
  delete/insert, limpar-tudo, noop, malformado, count incoerente, erro do RPC).
- Harness 1 e 2 verdes (ACL/replace de interesses no T3 + fundação); analyzer
  627 (0 erros, baseline, sem reflow); manifest 121; env/diff OK.

## Fora do escopo (follow-up)

- **Áreas** (`_saveAreas`, `assistReplaceAreas`, bridge `_routeT1Areas`, editor
  manual `PreferencesViewModel.replaceDesiredTitles`) →
  `replace_profile_desired_titles_atomic_v1`, preservando precedência de source
  e a inferência canônica. **Gate 3.0G-áreas** (próximo).
- **Guided add de interesse** (`_saveInterests`, `assistAddItem`) ainda lê o
  estado e faz replace (a escrita agora é atômica, mas há uma janela de
  read→replace); um merge aditivo (`merge_guided_profile_list('interests')`)
  eliminaria a janela — refinamento posterior.

## Risco conhecido

O guided add de interesse mantém a janela read→replace (escrita atômica, mas o
replace com a lista lida pode sobrescrever um add concorrente — improvável e
contido pela flag OFF). Co-deploy: migrations 130000–160000 juntas (3.0J).
