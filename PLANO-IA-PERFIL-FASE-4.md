# Fase 4 (IA/Perfil) — Casa do Currículo geral: persistir, versionar, staleness

**Criado em:** 21/07/2026 · **Base:** `main`/`b66c24c` (PR #23 mergeado) · **Frente:** roadmap
IA/Perfil do `HANDOFF-CLAUDE-CODE-IA-PERFIL.md` (§7 fase 4, §12 "Currículo geral").
Fonte original: texto do fundador, linhas 451–465 ("Dar uma casa ao currículo geral").

## 0. Decisões de produto (fundador, 21/07)

1. **Onde:** `saved_resumes` com `source='general'` (biblioteca única, tipo explícito).
   Trade-off aceito: build antigo lê `general` como `manual` (fallback do enum) e
   lista a versão como item comum deletável — deletar uma versão NÃO afeta o
   perfil (é snapshot de saída, regra de domínio 9 do handoff).
2. **Quando:** auto-save no export — "Exportar PDF" cria/atualiza o documento.
3. **Idempotência:** re-export com fingerprint+template idênticos à última
   versão ⇒ **noop honesto** (recibo `noop`, nenhuma versão duplicada).

Flag: tudo atrás de `trilha_assist_v1` (o card já vive sob ela; sem flag nova).
O rollback do assistente (flag OFF) fica intacto — nele o export segue efêmero.

## 1. Estado verificado (auditoria 21/07, 5 agentes + spot-checks)

- Currículo geral é 100% virtual: `loadGeneralResumeSnapshot` (estrito, 9 fontes)
  → `toResumeData` → `ResumeRenderer(forceFallback:true)` → PDF → `sharePdf`.
  Contratos "NÃO toca em saved_resumes" nos headers de `general_resume_export.dart`,
  `general_resume_card.dart`, `general_resume_preview.dart`.
- `saved_resumes`: CHECK `source ∈ {manual, imported, adapted}`; sem `version`,
  sem fingerprint, sem `updated_at`. Grants POR COLUNA (INSERT/UPDATE restritos);
  fence trigger de advisory lock em todo write; `is_current_source` amarrado a
  `imported+ready` (NÃO reutilizável). Toda a pilha 3.0 já APLICADA em prod
  (migration list conferido: local == remoto até `20260720120000`).
- Template do export geral é volátil (`ResumeViewModel.selectedTemplateId`, em
  memória, default `harvard_ats`, sem picker no fluxo geral).
- Staleness: nada em UI. `updated_at` das `profile_*` é inconfiável (sem trigger;
  app/RPCs CAS não setam) — NÃO usar. Moldes reutilizáveis: fingerprint junto do
  artefato (`analyze-match.profile_hash`) e `_snapshot_profile_content` +
  `_import_snapshot_stable` (Gate 3.0I, escopados ao import).
- `ProfileEvents` (5 emissores, Fase 3 F3): bom como GATILHO de refresh; ruim
  como fonte de verdade (sem payload; preferências disparam sem mudar o CV).
- Anti-pattern vivo: `_isEditable => title.startsWith('Currículo Stage')`
  (`resume_detail_screen.dart:114`). Writer do título: `autoSaveTrailResume`
  (`resume_viewmodel.dart`), chamado por `phase_completion_widget.dart:269`.
- Serializer `AdaptedResume.serializeResumeData` NÃO cobre `awards` nem
  `academicProjects`/`leadership` (e certificações perdem issuer) — exatamente o
  que o Currículo geral popula. Reusar sem estender = perda silenciosa.
- Preview legado (§7): (a) shell rollback da ResumeTab — só removível PÓS-rollout,
  FORA desta fase; (b) `ResumePreviewScreen` órfão (zero call sites) — F4.6.
- Rede de testes: 52 em `general_resume_test.dart` (matriz 9 grupos × 5 templates),
  +7 mapper, +2 snapshot export, +8 widgets.
- Arqueologia: nenhum trabalho prévio de persistência do geral em nenhuma branch.
  `refactor/perfil-central-fase-3` é fundação de IMPORT superseded — não usar.

## 2. Sub-fatias (cada uma exige autorização própria e relatório medido)

### F4.1 — Contrato de dados: migration + RPC `save_general_resume_version_v1`

Migration `2026…_general_resume_versions.sql` (nº 124 do manifest):

- CHECK de `source` ganha `'general'` (e `'trail'`, usado só na F4.5 — entra já
  para evitar segundo ALTER; nenhuma linha muda nesta fatia).
- Colunas novas: `version integer` e `profile_fingerprint text` (NULL para os
  sources atuais; obrigatórias quando `source='general'` via CHECK).
- Índice único parcial `(user_id, version) WHERE source='general'`.
- Colunas novas FORA dos grants por coluna do client ⇒ escrita SÓ via RPC.
- RPC `save_general_resume_version_v1(p_title, p_file_path, p_resume_data,
  p_template_id, p_fingerprint)` — SECURITY DEFINER `search_path=''`, REVOKE
  PUBLIC + grant `authenticated`, usuário = `auth.uid()`. Ordem: advisory lock
  (`profile_write_lock_key`) → validação fail-closed (payload, namespace do
  `file_path` = `{uid}/…`, fingerprint não-vazio) → `SELECT … FOR UPDATE` da
  última versão general → se `fingerprint`+`template_id` iguais ⇒ recibo
  `noop` (id/version/created_at existentes) → senão INSERT `version = max+1` ⇒
  recibo `applied`. Recibo JSONB com status estrito.
- Compatível com fence trigger e `zzz_mark_latest_legacy_source` (source novo cai
  no ELSE ⇒ `is_latest_legacy_source=false`; provar no harness).
- Harness SQL novo no padrão dos existentes (BEGIN…ROLLBACK, `TESTS_OK`):
  applied, noop, versão monotônica, ACL (user B não escreve em A; anon não),
  path fora do namespace falha, concorrência (2 saves simultâneos não duplicam
  versão), fingerprint vazio falha.
- **Co-deploy:** a migration precisa estar em prod ANTES do app que chama a RPC
  (mesma janela da próxima leva, tipo 3.0J). Nenhuma operação remota nesta fatia.

### F4.2 — Serializer completo de ResumeData (Dart)

- Estender `serializeResumeData`/`parseResumeData` (aditivo, retrocompatível):
  `awards`, `academicProjects`, `leadership`, issuer/data de certificações.
- Testes: round-trip completo; fixtures de payload LEGADO (sem os campos novos)
  parseiam sem perda do que já existia; CVs adaptados não regridem.

### F4.3 — Auto-save no export (client)

- Adapter tipado fail-closed (`GeneralResumeVersionWriter`) para a RPC; recibo
  parseado estrito (`applied`/`noop`; desconhecido/malformado = falha fechada).
- Fingerprint: sha256 (Dart) da serialização CANÔNICA do `resume_data` da versão
  (chaves ordenadas) — computado e comparado SEMPRE no client (mesma camada,
  lição do analyze-match). Muda template ⇒ nova versão (template participa do
  critério de noop via coluna própria, não do fingerprint).
- Fluxo no `runExport` (flag ON): render → pré-check barato da última versão
  (evita upload à toa) → upload PDF em `{uid}/general/{uuid}.pdf` → RPC → share.
  Noop pós-upload ⇒ remove blob best-effort (blob órfão é o modo de falha aceito,
  §8.4 do handoff; nunca linha sem blob).
- Falha do save NÃO quebra o share, mas NUNCA vira falso sucesso: outcome
  distinto + aviso ("PDF exportado; não consegui salvar a versão").
- Reescrever os headers/contratos "não persiste". Evento novo (ex.:
  `general_resume_version_saved` com `status`) = constante + emissor no mesmo
  PR (R7). Flag OFF ⇒ zero mudança de comportamento (nem instancia o writer).

### F4.4 — Card vira documento real + staleness

- Card mostra a última versão: template (label) + data ("Versão de 21/07 ·
  Harvard"); sem versão ⇒ copy atual.
- Indicador "perfil mudou depois desta versão": fingerprint atual (snapshot
  estrito → serialização canônica → sha256) vs o da última versão; recomputado
  lazy no load do card e em `ProfileEvents` (gatilho, não verdade). Divergiu ⇒
  badge "desatualizado" + CTA de re-exportar.
- Picker de template no fluxo geral (prévia/card); escolha vigente = template da
  última versão (fallback `harvard_ats`); deixa de depender do
  `selectedTemplateId` volátil da aba legada.

### F4.5 — Documento tipado na biblioteca (mata o prefixo-como-tipo)

- `_kSourceMeta`/legenda/sort tratam `general` (novos builds; antigos caem no
  fallback `manual` — aceito na decisão 1).
- Migration backfill (nº 125): `UPDATE saved_resumes SET source='trail' WHERE
  source='manual' AND title LIKE 'Currículo Stage%'` (o prefixo é usado UMA vez,
  na migration, para tipar; depois morre). Build antigo lê `trail`→`manual` +
  heurística de título no binário velho ⇒ comportamento idêntico ao de hoje.
- Client: `_isEditable => source == trail` (fim do `startsWith`);
  `autoSaveTrailResume` passa a gravar `source='trail'`.
- Detalhe de um doc `general`: view-only (visualizar/compartilhar/excluir);
  troca de template NÃO muta versão (template novo = exportar de novo).
- **Co-deploy:** backfill + app na mesma janela.

### F4.6 — Limpeza (DEFERIDA, só pós-rollout 100% de `trilha_assist_v1`)

- Remover shell rollback da ResumeTab + `ResumePreviewScreen` órfão. NÃO fazer
  agora (flag OFF exige rollback vivo). Registrada para não esquecer.

## 3. Fora de escopo da Fase 4

Fase 5 (Fonte importada na UI, Currículos outputs-only), Edge Functions,
mudança/ativação de flag, deploy/migration remota, refactor Provider/Navigator,
editor sobre o documento salvo (regra 9: snapshot de saída não realimenta
`profile_*`), remoção do rollback (F4.6 deferida).

## 4. Validação por fatia (baseline: 712 testes verdes, analyzer 627/0 erros)

`flutter test` completo + focados novos; `flutter analyze` (0 erros, sem lint
novo); harnesses SQL (`run_fase3_sql_test.sh`, `run_profile_guided_write_…` +
novo harness F4.1; `PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH`);
`check_migrations_manifest.sh` (124 após F4.1, 125 após F4.5);
`check_env_safety.sh`; `git diff --check`. Sem `dart format` em legado.
Matriz 9×5 e testes de export existentes continuam verdes (paridade prévia=PDF).

## 5. Condições de parada

Parar e pedir decisão se: um invariante de import de `saved_resumes` conflitar
com linhas `general`; o recibo não conseguir expressar noop/applied sem
ambiguidade; concorrência duplicar versão no harness; o backfill F4.5 casar
linhas que não são da trilha; ou qualquer necessidade de tocar Edge/flag/deploy.
