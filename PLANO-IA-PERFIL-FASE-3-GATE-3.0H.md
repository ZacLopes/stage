# Fase 3 — Gate 3.0H: escalares, bullets, itens compostos e Edge writers

## Status

Em andamento, por **fatias** (o gate é amplo). Fatias entregues: os dois Edge
writers (`generate-bullets`, `generate-profile-summary`). Branch
`refactor/ia-fase-2-fechamento`. Dart+Edge; **sem migration nova** (as RPCs já
existem na fundação de 14/07). Flag OFF/0.

## Achado da auditoria

As RPCs seguras já existem, prontas na migration de 14/07 (uma das 5
não-aplicadas): `append_experience_bullets(p_user_id, p_experience_id,
p_bullets)` (append sob advisory lock, dedup por texto, auth) e
`set_profile_summary_cas(...)` (CAS de summary+headline), além de uma família de
CAS de campos escalares. Os dois Edge writers (`generate-bullets`,
`generate-profile-summary`) usam o **JWT do usuário** (`ANON_KEY` +
Authorization), então `auth.uid()` == usuário e eles PODEM chamar essas RPCs.

## Fatia 1 entregue — generate-bullets

`supabase/functions/generate-bullets/index.ts`: a escrita forward-compat em
`profile_bullets` deixou de ser um `INSERT` direto e passou a chamar
`append_experience_bullets`. Ganhos: advisory lock por usuário, dedup por texto,
`order_index` correto server-side, e `not_authorized`/`experience_not_found`
tratados no RPC. O `try/catch` fire-and-forget original foi preservado (falha
aqui não derruba a resposta com `bullet_versions`).

## Testes

- `deno check` (check_functions_types): OK (31 entrypoints).
- `append_experience_bullets` validado no harness (promote test: dedup de
  `orig`/`nova`); harness 2 verde.
- `flutter test`: **672** (inalterado — Edge não afeta o app).
- `git diff --check` limpo; env OK; manifest 121.

## Fatia 2 entregue — generate-profile-summary

`supabase/functions/generate-profile-summary/index.ts`: a gravação do
resumo+headline deixou de ser `.update()` direto e passou a chamar
`set_profile_summary_cas`. Os "esperados" são os valores que a IA leu no passo 1
(`personalR.summary/headline`); se o vivo mudou desde então, o RPC volta
`'stale'` e **mantém a edição manual** (logamos e devolvemos a sugestão gerada;
o app recarrega e vê o estado real). `deno check` OK;
`set_profile_summary_cas` validado no harness (promote test: stale/applied).

## Fatias restantes do 3.0H (não iniciadas)

- **Escalares app-side** (`assistWriteFieldValue`) → família de CAS de campo.
- **Bullets/itens compostos app-side** (`_saveExperience`, `assistWriteItemField`)
  → `append_experience_bullets` / RPCs de item composto sob o mesmo lock.
- Cada fatia com seu relatório; nada inicia sem novo "ok".

## Risco conhecido — CO-DEPLOY (importante)

`append_experience_bullets` só existe na migration local `20260714130000` (NÃO
aplicada remotamente). Portanto o `generate-bullets` **não pode ser deployado
sozinho**: a migration precisa ir junto (Gate 3.0J). Se for deployado antes, o
RPC não existe em prod → o `try/catch` engole → os bullets forward-compat
deixam de ser gravados **em silêncio** (a resposta principal com
`bullet_versions` continua funcionando). É a mesma dependência de co-deploy dos
gates anteriores, agora do lado Edge — registrada para o 3.0J.

## Flag e operações remotas

Flag `trilha_assist_v1` OFF/0. Sem push, deploy, `supabase functions deploy`,
migration remota ou mudança de flag. Nenhum código Edge foi publicado.
