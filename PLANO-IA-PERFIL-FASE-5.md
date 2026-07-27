# Fase 5 (IA/Perfil) — Fonte importada em Dados + Currículos só-saída

**Criado em:** 22/07/2026 · **Base:** `main`/`b66c24c` (F4.1–F4.5 no working tree) ·
**Frente:** roadmap IA/Perfil do `HANDOFF-CLAUDE-CODE-IA-PERFIL.md` (§7 fase 5, §12
"Fonte importada"). Numeração própria da frente (1–8).

## 0. Decisões de produto (fundador, 22/07)

1. **Recorte:** núcleo primeiro — seção "Fonte importada" em Perfil → Dados
   (ver + remover atômico que preserva o perfil) + tirar `imported` da lista de
   Currículos. **"Substituir" e "pipeline único" ficam pra fatias seguintes.**
2. **Flag:** tudo atrás de `trilha_assist_v1` (mesma do assistente/Currículo
   geral). Flag OFF → comportamento atual intacto (importado segue na lista de
   Currículos; sem card em Dados). Rollout unificado com o resto do IA/Perfil.

## 1. Estado verificado (auditoria 22/07, 3 exploradores read-only)

- **"O fato vence":** o lado-servidor do motor de import JÁ ESTÁ EM PROD (o
  levantamento da F4 confirmou por `migration list`: 20260714120000/130000,
  20260719120000 e a Edge `extract-profile` aplicadas). Fase 5 = **só cliente**.
- Motor 3.0I completo mas DORMENTE atrás de `trilha_assist_v1`: importar →
  extrair na candidata (sem tocar o perfil) → card de conflitos → aplicar →
  desfazer.
- **RPCs de remoção que preservam os fatos:** `remove_imported_source(uuid)` e
  `delete_saved_resume(uuid)` — garantia explícita "NUNCA toca profile_*"
  (migration 130000:2093,2127), grant `authenticated`, **sem caller Dart**. A
  biblioteca ainda deleta por DELETE direto legado (`supabase_repository.dart:973`).
- Metadados em `saved_resumes` (`original_filename`, `extraction_status`,
  `is_current_source`, `created_at`, `client_import_id`) preenchidos no banco,
  mas **nenhum Dart os lê**; `SavedResume` (models.dart) só carrega
  id/title/file_path/created_at/source/resume_data/template_id.
- **Aba Dados = `_InfoTab`** (index 0): ListView de 3 blocos (header, card
  "Informações pessoais", `ProfileSectionList`); observa `ProfileEditorViewModel`,
  **NÃO** o `ProfileViewModel` (que tem `savedResumes`). Card novo precisa de um
  watch de `ProfileViewModel` aqui.
- **`_libraryResumes` (helper criado na F4.5) é o ponto único** que a lista de
  Currículos usa (lista, legenda, sort, empty). Excluir `imported` ali some de
  tudo de uma vez.
- **Única dependência real do row importado:** a aba "Original" do CV adaptado
  (`adapted_resume_preview_screen`) lê `saved_resumes` **direto por source**
  (`inFilter('source',['imported','manual'])`), não pela lista da UI → esconder
  da lista **não quebra**; só **não pode DELETAR o row**. Match/adapt leem
  `profile_*` via `toPseudoText`, não o importado.
- **Nome original** só é gravado no fluxo NOVO (`begin_import_source`); imports
  LEGADOS (maioria em prod) não têm → fallback pro título ("Meu Currículo").
- **Gotcha de ordem:** se `imported` sair da lista SEM a casa em Dados, o detalhe
  view-only do importado fica **inalcançável**. A casa (F5.2) vem antes/junto do
  outputs-only (F5.3).

## 2. Sub-fatias (cada uma exige verificação medida)

### F5.1 — Modelo: `SavedResume` carrega os metadados de import
- Estender `SavedResume.fromMap`/campos: `originalFilename`, `extractionStatus`,
  `isCurrentSource`, `clientImportId` (aditivo; nullable; não quebra callers).
- Teste: parsing de row com/sem os campos novos (legado → nulls, sem perda).

### F5.2 — Seção "Fonte importada" em Perfil → Dados (flag ON)
- Card compacto no `_InfoTab` (após `ProfileSectionList`), gated por
  `isTrilhaAssistEnabledForUser`. Lê a fonte importada (prefere
  `is_current_source`; senão a `source=imported` mais recente) via um
  `Consumer<ProfileViewModel>` novo.
- Mostra: **nome** (`originalFilename ?? title`), **data** (`createdAt`,
  DD/MM/YYYY), **status** honesto (se `extraction_status='ready'` OU o perfil já
  tem dados extraídos → "dados extraídos"; senão neutro). Sem inventar status
  onde o legado não gravou.
- Ações:
  - **Ver:** abre `ResumeDetailScreen` (view-only) do row importado — a NOVA
    entrada, já que sai da lista de Currículos.
  - **Remover:** confirma ("remover o arquivo NÃO apaga seus dados do perfil") →
    `remove_imported_source` (RPC atômico, preserva `profile_*`, limpa o cache
    legado se era current) → recarrega. Substitui o DELETE direto pra este card.
- Flag OFF → card não aparece (nada muda).
- Testes: view pura (nome/data/status/ações), lógica de "qual fonte" pura,
  adapter do RPC de remoção fail-closed. Widget do `_InfoTab` só se viável.

### F5.3 — Currículos só-saída (flag ON)
- `_libraryResumes` passa a excluir `imported` **quando a flag está ON** (com a
  flag OFF mantém o comportamento legado — importado na lista). `general` já é
  excluído (F4.5).
- Reescrever a copy do empty-state (hoje cita "arquivos que você importar").
- Teste: `_libraryResumes` filtra imported sob flag ON e mantém sob OFF (extrair
  a lógica pra função pura testável se o custo for baixo).

### Fora do núcleo (fatias seguintes, nova autorização)
- **F5.4 — Substituir fonte:** re-importar pelo motor seguro de revisão (card de
  conflitos + desfazer). Mexe no fluxo dormente do assistente.
- **F5.5 — Pipeline único:** reconciliar o import LEGADO (`pickAndImport`, modo
  replace) com o fluxo de revisão; migrar o delete da biblioteca pra
  `delete_saved_resume`; ligar `abort_import_source` na compensação.

## 3. Fora de escopo da Fase 5 (núcleo)

Substituir/re-importar, unificar pipeline, mudar o import legado do onboarding,
ativar flag, deploy/migration remota (nenhuma migration nova é necessária no
núcleo — tudo já existe no schema), refactor Provider/Navigator, apagar o cache
legado `imported_resume`.

## 4. Validação por fatia (baseline: 746 testes, analyzer 627/0 erros)

`flutter test` completo + focados novos; `flutter analyze` (0 erros, sem lint
novo); `git diff --check`. (Sem harness SQL novo — o núcleo não cria migration;
se alguma fatia tocar SQL, rodar os harnesses com
`PATH=/opt/homebrew/opt/postgresql@17/bin`.) Sem `dart format` em legado.

## 5. Condições de parada

Parar e pedir decisão se: remover a fonte exigir tocar `profile_*` (não deve —
os RPCs garantem que não); a aba "Original" do CV adaptado quebrar ao esconder
`imported` (não deve — lê por source, não pela lista); o status de extração não
puder ser derivado honestamente pro legado; ou surgir necessidade de "substituir"/
pipeline único (fora do núcleo).
