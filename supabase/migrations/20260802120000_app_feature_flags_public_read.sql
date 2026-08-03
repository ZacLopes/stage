-- Leitura de `app_feature_flags` passa a valer para `public` (inclui `anon`).
--
-- ⚠️ ESTA MIGRATION É PRÉ-REQUISITO DA TROCA DA CHAVE DO APP. Não aplique a
-- build 2.5.0 sem ela; e se reverter uma, reverta a outra.
--
-- CONTEXTO — por que só agora, se a tabela existe desde 20260523000002:
--
-- Até 02/08/2026 o app embarcava no `.env` (que é ASSET do bundle, viaja dentro
-- do IPA) a chave SECRETA do Supabase — `sb_secret_…`, a que IGNORA RLS — dentro
-- de uma variável chamada `SUPABASE_ANON_KEY`. Com ela, o cliente lia as flags
-- como se fosse superusuário e a policy restrita a `authenticated` nunca
-- estorvou ninguém. A troca pela chave publicável (`sb_publishable_…`) corrige
-- o vazamento e, de quebra, passa a APLICAR a RLS que sempre esteve lá.
--
-- O QUE QUEBRARIA SEM ESTA MIGRATION (medido em 02/08/2026):
--
--   $ curl -s .../rest/v1/app_feature_flags?select=feature_key \
--       -H "apikey: sb_publishable_…"        →  HTTP 200, corpo `[]`
--
-- Zero linhas, sem erro. E `FeatureFlagsService.refresh()` tem CALL SITE ÚNICO,
-- em `lib/main.dart:151`, dentro do `_bootstrap()`, ANTES de qualquer login e
-- envolto em `try/catch(_){}`. Não roda de novo no login nem no foreground.
-- Resultado: quem instala o app do zero — exatamente o funil das campanhas
-- Meta — passaria a PRIMEIRA SESSÃO INTEIRA com os 16 call sites em v1:
-- feed legado no lugar da RPC `get_feed_page` (167ms → 20ms perdidos), sem o
-- card "Completar com a IA" no fim do onboarding, "Vagas Salvas" legado no
-- lugar da aba Candidaturas, typeahead de skills desligado.
-- Falha silenciosa, sem exceção e sem log em release: a classe que só aparece
-- em métrica de ativação três semanas depois.
--
-- POR QUE ISTO NÃO É REGRESSÃO DE SEGURANÇA:
--
--   - a tabela tem 11 linhas de CONFIGURAÇÃO (feature_key, enabled,
--     rollout_pct, description). Zero PII, zero dado de usuário;
--   - o `anon` JÁ LÊ essas 11 linhas hoje em produção, via o bypass de RLS da
--     chave secreta. Isto não abre nada novo — só troca o mecanismo de
--     "superpoder acidental" por "permissão declarada";
--   - continua sendo SÓ leitura. `anon` tem grant de INSERT/UPDATE/DELETE na
--     tabela (default do Supabase), mas sem policy para esses comandos a RLS
--     os nega — verificado em `pg_policy`: existe uma única policy, `SELECT`;
--   - `app_config` (version gate, min_supported_version) já é `TO public` pelo
--     mesmo motivo e pelo mesmo desenho — esta migration só alinha a irmã.
--
-- IDEMPOTENTE: DROP IF EXISTS + CREATE, reaplicável sem efeito colateral.
-- ROLLBACK: recriar a policy com `TO authenticated` — mas só faz sentido junto
-- com a volta da chave antiga, que é o que não se quer.

DROP POLICY IF EXISTS "app_feature_flags read all" ON public.app_feature_flags;

CREATE POLICY "app_feature_flags read all"
  ON public.app_feature_flags
  FOR SELECT
  TO public
  USING (true);

COMMENT ON TABLE public.app_feature_flags IS
  'Flags estruturais lidas pelo cliente no cold start (main.dart:151). Leitura '
  'liberada a `public` porque o app lê ANTES do login — ver '
  '20260802120000_app_feature_flags_public_read.sql. Só configuração, sem PII. '
  'Escrita segue sem policy: negada pela RLS para anon/authenticated.';
