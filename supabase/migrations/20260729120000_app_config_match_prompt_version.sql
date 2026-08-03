-- Migration: declara app_config.match_prompt_version (regularização de R2)
--
-- A coluna EXISTE em produção desde ~05/2026 e nunca esteve em migration
-- nenhuma: `20260512000000_app_config.sql` cria a tabela sem ela, e um grep por
-- `match_prompt_version` em supabase/migrations/ não retorna nada. Ou seja, foi
-- criada pelo dashboard — exatamente o que a R2 proíbe.
--
-- Por que isso importa, e não é burocracia:
--   1. Um ambiente novo (`supabase db reset`, staging, máquina de outra pessoa)
--      NÃO teria a coluna. O cliente lê esse valor em `ai_service.dart` e, na
--      falha, cai no fallback 'v4' — versão sem nenhuma linha viva de cache.
--      Resultado: todo mundo no score determinístico, sem IA, e ninguém sabe
--      por quê.
--   2. Ela é o botão de rollback do match (o cliente filtra `match_analyses`
--      por igualdade exata contra este valor). Mexer nela sem declarar é
--      empilhar drift em cima do drift.
--
-- ESTA MIGRATION É NO-OP CONTRA PRODUÇÃO. A definição abaixo foi copiada da
-- realidade, não suposta — `information_schema.columns` em 29/07/2026 devolve
-- exatamente `text`, `NOT NULL`, default `'v10'::text`:
--
--   column_name          | data_type | is_nullable | column_default
--   match_prompt_version | text      | NO          | 'v10'::text
--
-- Conferir isso importa: se o tipo, a nullability ou o default divergissem, o
-- `IF NOT EXISTS` pularia em SILÊNCIO e o repo passaria a declarar uma coluna
-- que o banco não tem — drift novo, escondido pelo próprio conserto.
--
-- Nota sobre o default: `'v10'` é o default histórico e o valor VIVO hoje é
-- 'v13'. Default só vale para linha nova, e a tabela é singleton (id=1), então
-- não há o que corrigir aqui — mudar o default agora só criaria divergência com
-- produção sem benefício. O valor ativo é trocado por migration de seed própria
-- (padrão de `20260622120000_seed_resume_trail_enabled.sql`), separada, para o
-- flip de versão ser um ato distinto da declaração do schema.

BEGIN;

ALTER TABLE public.app_config
  ADD COLUMN IF NOT EXISTS match_prompt_version TEXT NOT NULL DEFAULT 'v10';

COMMENT ON COLUMN public.app_config.match_prompt_version IS
  'Versão de prompt do analyze-match que o CLIENTE aceita ao ler o cache de '
  'match_analyses (igualdade exata). Tem que ser bumpada JUNTO com '
  'PROMPT_VERSION da Edge Function, e DEPOIS dela: com a function à frente o '
  'cliente chama ao vivo e recebe resultado correto; invertido, ele pede uma '
  'versão que o servidor não sabe produzir e recebe o cache antigo sob rótulo '
  'novo. Rebaixar este valor é o rollback de emergência.';

COMMIT;
