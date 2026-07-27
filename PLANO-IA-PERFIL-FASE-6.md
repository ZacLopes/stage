# Fase 6 (IA/Perfil) — Currículos por vaga: identidade, idempotência, fonte correta

**Criado em:** 24/07/2026 · **Base:** `main`/`0999359` (PR #23); working tree com
F4.1–F4.5 e F5.1–F5.4 sem commit · **Frente:** roadmap IA/Perfil do
`HANDOFF-CLAUDE-CODE-IA-PERFIL.md` (§7 fase 6, §12 "Currículo por vaga").
Numeração própria da frente (1–8), não a do `PLANO-MAE.md`.

## 0. Decisões de produto (fundador, 24/07)

1. **Diagnóstico antes de organizar.** Executado nesta sessão, sem código —
   resultado na §2. Nenhuma fatia de instrumentação é necessária.
2. **A tela de Candidaturas NÃO entra.** O Stage é agregador: a candidatura
   acontece fora do app, e o botão "já me candidatei" é autodeclarado. O Stage
   **nunca** observa qual arquivo foi anexado. Qualquer campo "documento usado"
   seria falso sucesso (regra 5 do handoff). O critério §12 "candidatura informa
   qual documento foi usado" fica **explicitamente descartado como fato**.
3. **Re-baixar o mesmo CV adaptado da mesma vaga ⇒ noop honesto** — mesmo
   contrato do Currículo geral (F4.1/F4.3), sem linha nem blob novos.

**Correção de premissa registrada:** a justificativa B2B ("candidato se
candidatou com CV sob medida") é inválida pelo item 2. O valor real da Fase 6 é
**o usuário achar e anexar o arquivo certo** no momento em que o app o solta no
navegador — inclusive no caminho de e-mail, cujo corpo já diz "segue meu
currículo em anexo" sem anexar nada (`lib/features/jobs/utils/apply_email.dart:39`).

## 1. Estado verificado (auditoria 24/07: 5 exploradores read-only + queries em prod)

### 1.1 Três universos sem ligação

| Artefato | Onde | Sabe a vaga? | Volume em prod |
|---|---|---|---|
| A **adaptação** (trabalho da IA) | `adapted_resumes` | **sim** (`job_id` FK, UNIQUE(user,job)) | 34 linhas / 28 users / 34 vagas |
| O **documento** (PDF) | `saved_resumes` `source='adapted'` | **não** — só o texto do `title` | 5 linhas / 5 users |
| A **candidatura** | `applications` | sim (`job_id`) | 621 linhas, **0** com `adapted_resume_id` |

- `applications.adapted_resume_id` existe desde `20260610150000_applications.sql:24`
  (FK → `adapted_resumes`), **sem nenhum writer** em client, Edge, RPC ou trigger.
  Causa provada: a Edge **não devolve o `id`** do upsert
  (`v2.ts:2133-2142`, `index.ts:2922-2930`), então o client nunca conhece o valor.
  Por decisão 2 esta coluna **permanece sem writer** — não é dívida a pagar.
- `saved_resumes` não tem `job_id` em nenhuma das 9 migrations que a alteram.
  O vínculo é o título `'CV adaptado - <vaga> - <empresa>'`, truncado em 60 chars
  (`adapted_resume_preview_screen.dart:402-408,442-447`).

### 1.2 Sem idempotência no documento adaptado

`supabase_repository.dart:911-925` é `insert` puro — sem `select` prévio, sem
`onConflict`, sem fingerprint, e sem passar por `ProfileViewModel.resolveUniqueTitle`
(que existe e não é chamado). **N downloads ⇒ N linhas + N blobs.**
Contraste direto: o Currículo geral ganhou `computeResumeFingerprint` +
pré-check + RPC com recibo `noop` na F4.3.

### 1.3 A aba "Original" está errada — e a F4.5 piora

`adapted_resume_preview_screen.dart:301` resolve a fonte por
`inFilter('source', ['imported','manual'])` + `order(created_at desc).limit(1)`.
É recência, não escolha; não olha `is_current_source` (coluna existe desde
`20260714120000:22` e já é exposta em `SavedResume.isCurrentSource`).

Medido em prod hoje: **114 de 1.156 usuários (9,9%)** têm mais de um candidato;
o máximo é 10.

A migration `20260722120000_backfill_trail_source.sql` (F4.5, working tree,
**não aplicada**) reclassifica `manual` + `title LIKE 'Currículo Stage%'` →
`trail`, que **não está no filtro**. Impacto medido quando ela rodar:

- **91 linhas** mudam de `source`;
- **78 usuários (6,7%)** passam a ver outro documento como "Original";
- **50 usuários ficam sem nenhum** candidato — a aba fica vazia.

`source='general'` (documento canônico de saída da F4) também nunca é candidato.

### 1.4 Código morto no caminho

- `PendingAdaptedCvTracker` — escrito em 1 lugar, limpo em 4, **lido por nenhum**
  (o banner do Home foi removido; `home_screen.dart:419-423`).
- `JobsViewModel.requestOpenAdaptSheet` (`jobs_viewmodel.dart:256`) — **0 callers**;
  todo o handoff `pendingAdaptSheetJobId` → `_openPendingAdaptSheet` é inalcançável.
- Único ponto de entrada de adaptação é o botão IA do deck
  (`jobs_swipe_screen.dart:1520`). Da aba Candidaturas não se adapta.

### 1.5 Round-trip do serializer ainda é lossy

`EducationItem.coursework` e `repRole` são hard-codados como `''` no parse
(`adapted_resume.dart:428-429`) e nunca serializados; `honors` é derivado de
`activities`. São justamente campos que a Fase 3 F1c expôs no editor. A F4.2
cobriu awards/academicProjects/leadership/certificações — não estes.

### 1.6 R5 é vacuoso e aponta para o motor errado

`golden_set/` tem README + 3 scripts; `cvs/`, `ground_truth/`, `outputs/` **vazios**.
Os scripts chamam `/functions/v1/extract-profile` — **não** `adapt-resume-to-job`.
Com corpus vazio ambos saem **exit 0**: "golden_set limpo" é indistinguível de
"não havia nada pra rodar". Somado, `adapt-resume-to-job` está excluído por nome
de `scripts/check_functions_types.sh:25`, e `v2.ts` (2155 linhas) nem seria
coberto porque o script só globa `*/index.ts`.

**Consequência para esta fase:** qualquer fatia que toque a Edge do adapt não
tem rede. Ver F6.2 e a condição de parada §5.

### 1.7 Flags — o CLAUDE.md e a memória estão desatualizados

`applications_tracker_v1` e `feed_list_v1` estão **ON/100%** em prod
(não OFF). Na prática ninguém usa o tracker ainda: 0 candidaturas `type='manual'`
e 0 `external_url` — o client 2.5.0 não foi liberado. `trilha_assist_v1` = OFF/0.

## 2. Diagnóstico da taxa de falha (decisão 0.1) — CONCLUÍDO, sem código

O evento `adapt_failed` **sempre carregou o motivo** na propriedade `error_code`
(`analytics_service.dart:1182-1183`). Últimos 180 dias:

| `error_code` | falhas | pessoas |
|---|---|---|
| `profile_incomplete` | 27 (63%) | 17 |
| `adaptation_rejected` | 16 (37%) | 10 |

Cruzamento das 17 pessoas com o banco **na data de cada falha**:

- **13** genuinamente sem material (nem experiência, nem projeto, nem import);
- **3** preencheram o perfil **depois** — o app estava certo na hora;
- **1** já era elegível na hora (único suspeito; não é padrão).

**16/17 acertos — o pré-check `canAdaptCv` não tem bug.** A adaptação falha
porque o perfil está oco.

Teto da feature hoje: **1.496 de 2.136 usuários (70%)** passariam no critério
(`profile_snapshot_service.dart:93-107` replicado em SQL). Entre quem tentou,
~76% não passava — o botão de IA está sendo achado por quem ainda não tem o que
adaptar.

**Conclusões operacionais:**

1. A causa dominante **não é da Fase 6**; é resolvida enchendo o perfil — o que
   as Fases 3/4/5 já fazem, paradas atrás de `trilha_assist_v1` OFF.
2. `adaptation_rejected` é qualidade do motor de IA. Mexer nisso aciona R5, que
   não mede nada (§1.6). **Fora do escopo desta fase.**
3. Nenhuma fatia de instrumentação é necessária.

## 3. Sub-fatias (cada uma exige autorização própria e relatório medido)

### F6.0 — "Original" aponta para a fonte correta (§12, item 2)

Sem SQL, sem Edge, sem flag (é correção de regressão). **Precisa estar pronta
antes da migration 125 ir a prod de qualquer forma.**

- Extrair a resolução da fonte para uma **função pura testável**
  (`resolveOriginalSource(List<SavedResume>)`), fora do widget.
- Política: preferir `is_current_source`; senão o `imported` mais recente; senão
  o documento de saída mais recente entre `trail`/`manual`/`general`; desempate
  por `created_at DESC, id DESC` (igual ao contrato do banco).
- Substituir o `inFilter('source', ['imported','manual'])` por uma consulta que
  traga os candidatos e delegue a escolha à função pura.
- Manter a degradação atual: falha no download do PDF ⇒ cai no `ResumeData`
  fallback, sem falso sucesso.
- Testes: candidato único; `imported` + `manual` (importado vence);
  `trail` presente (não some); só `general`; nenhum candidato (estado vazio
  honesto, não spinner infinito); `is_current_source` vence recência.

### F6.1 — Contrato de dados do documento por vaga (§12, itens 1 e 3)

Migration `2026…_job_resume_versions.sql` (**nº 127** do manifest).

- `saved_resumes` ganha `job_id uuid REFERENCES public.jobs(id)` e
  `adaptation_id uuid REFERENCES public.adapted_resumes(id) ON DELETE SET NULL`.
  CHECK: obrigatórios quando `source='adapted'`, NULL em todo o resto.
- Relaxar `saved_resumes_general_version_check` (F4.1) para permitir
  `version` + `profile_fingerprint` também em `source='adapted'` — hoje a
  constraint força NULL em tudo que não é `general`. Renomear para
  `saved_resumes_versioned_check`. **A migration 124 ainda é local**, então isto
  é edição de contrato não aplicado, não alteração de schema remoto.
- Índice único parcial `(user_id, job_id, version) WHERE source='adapted'`
  (o do geral é `(user_id, version) WHERE source='general'` — escopos distintos).
- `job_id`, `adaptation_id`, `version`, `profile_fingerprint` **fora** dos grants
  por coluna do `authenticated` ⇒ escrita só via RPC (mesmo mecanismo que já
  impede INSERT direto de `general`).
- RPC `save_job_resume_version_v1(p_job_id, p_title, p_file_path, p_resume_data,
  p_template_id, p_fingerprint, p_adaptation_id)` — molde exato da F4.1:
  `SECURITY DEFINER`, `search_path=''`, REVOKE PUBLIC + grant `authenticated`,
  usuário = `auth.uid()`. Ordem: advisory lock (`profile_write_lock_key`) →
  validação fail-closed (payload ≤256 KiB, path `^{uid}/job/[0-9a-f-]{36}\.pdf$`,
  fingerprint `^[0-9a-f]{64}$`, vaga existe, adaptação — se informada — pertence
  ao par user+job) → `SELECT … FOR UPDATE` da última versão **daquela vaga** →
  fingerprint **e** template iguais ⇒ recibo `noop`; senão INSERT `version=max+1`
  ⇒ recibo `applied`. Recibo JSONB estrito.
- Estender `zzz_general_resume_immutable` para cobrir linhas `adapted` versionadas
  (hoje o `WHEN` exige `OLD.source='general'`).
- Compatibilidade a provar no harness: fence `zzz_fence_stmt` (statement-level,
  não rejeita), `zzz_mark_latest_legacy_source` (cai no ELSE ⇒
  `is_latest_legacy_source=false`), `saved_resumes_current_only_imported_check`.
- Seed da flag nova `job_resume_versions_v1` (OFF/0) na mesma migration.
- Harness SQL novo (`supabase/tests/perfil_central_fase6_job_versions_test.sql`),
  padrão `BEGIN…ROLLBACK` + `TESTS_OK`: applied, noop, versão monotônica **por
  vaga** (duas vagas do mesmo user não compartilham contador), ACL (user B não
  escreve em A; anon não), path fora do namespace falha, `job_id` inexistente
  falha, `adaptation_id` de outra vaga falha, concorrência (2 saves simultâneos
  na mesma vaga não duplicam versão), linhas legadas `adapted` sem `job_id`
  continuam válidas.
- **Co-deploy:** migration em prod ANTES do app que chama a RPC (padrão 3.0J).

### F6.2 — A Edge devolve o `id` da adaptação (§12, item 1)

- `adapt-resume-to-job` v1 e v2: o upsert passa a usar `.select('id').single()`
  e o `id` entra na resposta (chave nova, aditiva). Client antigo ignora.
- `AdaptedResume` ganha `adaptationId` (nullable — cache de builds antigas e
  respostas sem a chave continuam válidos).
- **Não muda prompt** ⇒ sem bump de `PROMPT_VERSION`/`PROMPT_VERSION_V2`.
- Verificação: `check_functions_types.sh` (que exclui adapt — registrar o vazio
  honestamente no relatório), `check_functions_drift.sh` (que **não** exclui),
  testes Dart do parser, e uma chamada real medida contra prod com conta de
  teste antes de qualquer deploy.
- **Condição de parada:** se a mudança exigir tocar prompt, validador ou
  qualquer caminho coberto por R5, parar e pedir decisão (§1.6).

### F6.3 — Auto-save do adaptado vira versão idempotente (§12, item 3)

- Adapter tipado fail-closed `JobResumeVersionWriter`, espelhando
  `GeneralResumeVersionWriter` (reusa `computeResumeFingerprint` e o
  `_canonicalJson`); recibo parseado estrito (`applied`/`noop`; desconhecido ou
  malformado ⇒ falha fechada).
- `_approveAndDownload` (`adapted_resume_preview_screen.dart:410`) deixa de
  chamar `profileVM.saveResume` (insert direto) e passa pelo writer:
  pré-check barato da última versão daquela vaga → upload em
  `{uid}/job/{uuid}.pdf` → RPC → share. Noop pós-upload ⇒ remove blob
  best-effort (blob órfão é o modo de falha aceito, §8.4 do handoff; nunca linha
  sem blob).
- Falha do save **não** quebra o share, mas nunca vira falso sucesso: mantém o
  snackbar honesto que já existe (`:497-511`) e o evento `cv_library_save_failed`.
- Evento novo `job_resume_version_saved` com `status` — constante em
  `analytics_events.dart` + emissor no mesmo PR (R7).
- Atrás da flag **`job_resume_versions_v1`**: OFF ⇒ caminho atual intacto
  (insert direto), writer nem é instanciado. Flag nova porque o fluxo adaptado
  **não** está atrás de `trilha_assist_v1` — é caminho vivo hoje.
- Testes: fingerprint estável; applied; noop sem linha nem blob novos; recibo
  malformado falha fechado; upload ok + RPC falha ⇒ blob removido e outcome
  honesto; flag OFF preserva o insert direto.

### F6.4 — O documento sabe a vaga (§12, item 1, superfície)

- Card da biblioteca e `ResumeDetailScreen` leem `job_id`/`adaptation_id` em vez
  de parsear o título; mostram vaga + empresa a partir de `jobs`, com fallback
  para o título quando `job_id` for NULL (todas as 5 linhas legadas em prod).
- Detalhe do documento `adapted`: continua view-only + troca de template
  (`_isStructuredAdapted`, inalterado).
- **Nada na aba Candidaturas** (decisão 0.2).
- Atrás da mesma flag `job_resume_versions_v1`.
- Testes: view pura com `job_id` presente; fallback legado sem `job_id`; vaga
  apagada (FK `ON DELETE` — definir política na fatia, provavelmente `SET NULL`
  no `job_id` para não perder o documento).

## 4. Fora de escopo da Fase 6

- **Candidaturas** (decisão 0.2): nenhuma superfície, nenhum writer de
  `applications.adapted_resume_id`.
- **Qualidade do motor de adaptação** (`adaptation_rejected`, 37% das falhas) —
  aciona R5, que não mede nada.
- **Popular o `golden_set/`** e/ou reapontá-lo para o adapt — trabalho legítimo,
  fase própria.
- Perfil oco (causa dominante da falha) — é o resto da frente, atrás de
  `trilha_assist_v1`.
- Cache legado `imported_resume`; `match_v2_enabled`; F4.6; F5.5.
- Código morto (`PendingAdaptedCvTracker`, `requestOpenAdaptSheet`) — registrado
  em §1.4, remoção fica para a Fase 8 (retirada do legado).
- `coursework`/`repRole`/`honors` no serializer (§1.5) — registrado; só entra se
  alguma fatia provar que o round-trip do adaptado depende deles.
- Release, build, deploy, migration remota, mudança de flag: **do fundador**.

## 5. Validação por fatia

Baseline **medido em 24/07** (não declarado): `flutter test` **768 verdes**
(exit 0) · `flutter analyze` **627 issues, 0 errors** · `check_migrations_manifest`
**OK (126)** · `check_env_safety` **OK** · `git diff --check` limpo.

Ao fim de cada fatia: `flutter test` completo + focados novos; `flutter analyze`
(0 erros, sem lint novo); `git diff --check`. Se tocar SQL:
`bash scripts/run_fase3_sql_test.sh` e
`bash scripts/run_profile_guided_write_foundation_test.sh` (ambos exigem
`export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"`) +
`check_migrations_manifest.sh` (127 após F6.1). Se tocar Edge:
`bash scripts/check_functions_types.sh` (registrando que adapt é excluído) e
`check_functions_drift.sh`. Sem `dart format` em arquivo legado.

## 6. Condições de parada

Parar e pedir decisão se: relaxar o CHECK da F4.1 conflitar com algum invariante
de `general`; o recibo não expressar `noop`/`applied` sem ambiguidade;
concorrência duplicar versão no harness; F6.2 exigir tocar prompt/validador ou
qualquer caminho coberto por R5; a política de `ON DELETE` da vaga implicar
perder documentos do usuário; ou surgir necessidade de tocar Candidaturas,
flag, deploy ou migration remota.
