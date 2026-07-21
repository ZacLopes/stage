# Fase 3 — Gate 3.0J: co-deploy da pilha (release + rollout)

## O que é

Publicar a pilha inteira da Fase 3 (gates 3.0A–3.0I), hoje **só local**, sem
quebrar produção. É o único gate que faz **operação remota** (migrations, deploy
de Edge, release, flag). Nada aqui foi executado — este é o roteiro para o
fundador aprovar e disparar.

## Estado no fechamento do 3.0I (19/07)

- Branch `refactor/ia-fase-2-fechamento`, HEAD `497e729`. `main` intocado (`24007c2`).
- Flag `trilha_assist_v1` **OFF/0** (nada do assistente/import-revisão liga sem ela).
- Migrations da pilha **NÃO aplicadas** remotamente; Edge **NÃO deployado**; app **não** buildado com este código.
- Verde local: flutter test 699, analyzer 627, 2 harnesses SQL (exit 0), deno 31, manifest 122, env, diff limpos.

## Por que TEM que ser co-deploy (dependências duras)

1. **Cutover de cliente NÃO-gated pela flag (3.0D/3.0F/3.0G):** o editor MANUAL de
   skills/interesses/áreas/idiomas já chama RPCs atômicos
   (`replace_profile_skills_atomic_v1`, `replace_profile_interests_atomic_v1`,
   `replace_profile_desired_titles_atomic_v1`, `remove_guided_language_cas`, +
   `_replace_profile_simple_list` autoritativo). Isso roda **com a flag OFF**.
   → As migrations **têm que estar aplicadas ANTES do app** que as chama chegar ao
   usuário, senão **salvar perfil quebra pra todo mundo**.
2. **Edge chama RPCs que só existem nas migrations locais (3.0H/3.0I):**
   `extract-profile`→`complete_import_extraction`; `generate-bullets`→
   `append_experience_bullets`; `generate-profile-summary`→`set_profile_summary_cas`;
   o applier/undo do import→`apply_reviewed_with_snapshot`/`revert_reviewed_apply`.
   → As migrations **antes do Edge**, senão o RPC falta em prod (bullets/summary
   somem em silêncio no fire-and-forget; o import falha).
3. **Par 14/07 é indivisível:** `20260714120000` deixa `save_profile_from_json`
   fail-closed (`profile_import_temporarily_unavailable`); `20260714130000` o
   restaura como fill-empty. Um `db push` aplica as pendentes **em ordem**, então
   isso se resolve sozinho — desde que as duas subam **no mesmo push**.

## Ordem obrigatória

```
(0) verificar estado remoto  →  (1) MIGRATIONS  →  (2) EDGE  →  (3) APP
                                                     (flag OFF o tempo todo)
                                          →  (4) go/no-go device  →  (5) rollout da flag
```

Migrations antes de Edge; Edge antes (ou junto) do app; flag OFF até o rollout.
Aplicar migrations com o app ANTIGO em prod é seguro: as funções compartilhadas
mantêm assinatura/comportamento (fill-empty), e o Edge antigo não chama as RPCs novas.

## Passo a passo (comandos)

### (0) Pré-voo — VERIFICAR (não declarar)
```bash
git checkout refactor/ia-fase-2-fechamento && git pull   # HEAD == 497e729
supabase migration list          # ver EXATAMENTE quais estão pendentes no remoto
bash scripts/check_migrations_manifest.sh     # manifest limpo (122)
bash scripts/check_functions_drift.sh         # o que difere do deployado
bash scripts/check_functions_types.sh         # deno check (31)
bash scripts/check_env_safety.sh
```
As pendentes desta pilha devem incluir (confirmar na saída do `migration list`):
`20260714120000`, `20260714130000`, `20260717120000`, `20260717130000`,
`20260717140000`, `20260717150000`, `20260717160000`, `20260719120000`.

### (1) Migrations (R2 — só CLI, nunca dashboard)
```bash
supabase db push                 # aplica TODAS as pendentes, em ordem
supabase migration list          # confirmar que subiram; manifest list limpo
```
Aceite: `import_apply_receipts` tem `pre_snapshot/after_snapshot/reverted_at`;
`apply_reviewed_with_snapshot`/`revert_reviewed_apply`/`complete_import_extraction`
existem e estão GRANTeadas (authenticated/service_role conforme cada uma).

### (2) Edge (deploy só de commitado; após migrations)
```bash
# code COMMITADO (HEAD limpo). Deployar do working tree cria drift.
supabase functions deploy extract-profile
supabase functions deploy generate-bullets
supabase functions deploy generate-profile-summary
# trilha-assistant: só se check_functions_drift acusar diferença do deployado.
bash scripts/check_functions_drift.sh         # repo == deployado (sem drift)
```
Nota: nenhum desses é webhook, então `verify_jwt` do `config.toml` não é o ponto
aqui (isso vale para `ingest-jobs-email`/`notify-signup`, que NÃO tocamos).

### (3) App Flutter (com flag ainda OFF)
- Bump de versão (próxima release — conferir `pubspec.yaml`), build, submeter.
- O app já traz todo o cliente 3.0A–3.0I; com a flag OFF, a barra e o import
  seguem no comportamento de hoje. O cutover manual NÃO-gated (skills/interesses/
  áreas/idiomas) passa a usar os RPCs atômicos — por isso o passo (1) veio antes.

### (4) Go/no-go — device com a flag LIGADA só pra conta interna
Antes de qualquer rollout amplo, ligar a flag **só** pra conta interna
(`internal-fase0-test@stage.app`) e forçar o caminho REAL:
- editar skills/idiomas/interesses manualmente → salva (recibo/CAS ok);
- importar um CV real → cartão de revisão aparece com "CV diz X × você tem Y";
- aceitar algumas linhas → agregado honesto ("trouxe N; M você já tinha; K não deu");
- **Desfazer** → perfil volta ao estado pré-import; refazer → aplica de novo;
- editar algo e tentar Desfazer → "não deu" (stale), edição preservada.
Smoke tem que forçar o caminho real (perfil protegido/não-vazio) — perfil vazio
cai no caminho inicial e não prova a revisão.

### (5) Rollout da flag `trilha_assist_v1` (R4: 10→50→100)
```sql
-- via app_feature_flags (estrutural), NÃO dashboard de schema:
UPDATE public.app_feature_flags SET enabled = true, rollout_percent = 10 WHERE key = 'trilha_assist_v1';
-- observar 24–48h (PostHog + logs Edge) → 50 → 100.
```
Lembrar de remover o override de dev em `feature_flags_service.dart` se ainda existir.

## Rollback

- **Instantâneo (sem rebuild):** `UPDATE app_feature_flags SET enabled=false WHERE key='trilha_assist_v1'` — desliga TODO o fluxo do assistente/import-revisão. O cutover manual NÃO-gated (3.0D/G) continua (é o caminho novo de salvar), mas é atômico/testado.
- **Edge:** `git revert` do commit + `supabase functions deploy` da versão anterior (só de código commitado).
- **Migrations:** são fix-forward (não dá rollback limpo de DDL com dados). A reversão do IMPORT é in-app (`revert_reviewed_apply`), não da migration. Se uma migration causar problema, corrigir com nova migration.
- **Sinal de saúde:** monitorar `save_profile_failed` (Edge), p90 de `analyze-match`, e erros `candidate_persist_failed`/`revert_verification_failed` nos logs.

## Checklist final (marcar ao publicar)

- [ ] (0) `migration list` conferido; drift/manifest/deno/env limpos.
- [ ] (1) `db push` aplicou as 8 pendentes; aceites de schema conferidos.
- [ ] (2) 3 (ou 4) Edge deployadas; `check_functions_drift` sem drift.
- [ ] (3) App buildado/submetido (flag OFF).
- [ ] (4) Device-test da conta interna: manual + import + Desfazer + stale.
- [ ] (5) Flag 10% → observar → 50% → 100%; override de dev removido.
- [ ] `scripts/posthog_annotate_deploy.sh` na LIBERAÇÃO da build aos usuários.

## Contexto herdado (memória)

Gates anteriores também esperam este co-deploy: 3.0H (Edge bullets/summary),
3.0D (migration 150000 autoritativa), 3.0F (160000 idioma). Tudo na mesma pilha
local — sobe junto. Detalhe por gate: memória `gates_3_0c_3_0d_skills_cutover`.
