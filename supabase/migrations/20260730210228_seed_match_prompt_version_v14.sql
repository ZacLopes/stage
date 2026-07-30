-- Seed: vira a versão de prompt do match que o CLIENTE aceita — v13 → v14.
--
-- Ato SEPARADO do código de propósito (padrão de
-- `20260622120000_seed_resume_trail_enabled.sql`): a Edge Function já foi
-- deployada gravando `prompt_version = 'v14'`, e este arquivo apenas autoriza o
-- cliente a LER essas linhas. Separar deixa o rollback ser um passo próprio.
--
-- POR QUE ESTA ORDEM (function primeiro, chave depois):
--   • Com a function em v14 e a chave em v13, o cliente vê menos cache, chama
--     ao vivo, e o servidor devolve v14 CORRETO. Degrada em custo, não em
--     conteúdo.
--   • Invertido, o cliente pediria uma versão que o servidor não sabe produzir
--     e receberia o cache antigo — as razões CONTRADITÓRIAS — sob rótulo novo.
--     Ou seja: exibiria o defeito anunciando o conserto.
--
-- O QUE MUDA PARA O USUÁRIO: vaga remota deixa de perder os 15 pontos de
-- Localização (achado P1-5). Medido em produção antes do conserto: 2.041
-- razões `Localização matched=false` e 872 de `Modelo`, atingindo 518 pessoas,
-- presentes em TODAS as 7 versões de prompt desde 13/05 — comportamento de
-- origem, não regressão.
--
-- CACHE: `match_analyses` tem UNIQUE (user_id, job_id), então versões NÃO
-- coexistem — recomputar sobrescreve a linha antiga. Não há "aquecer antes de
-- virar": o recompute É a virada, para os pares que ele toca. Só 970 linhas
-- (57 usuários) estavam simultaneamente na versão ativa e dentro do TTL de 30
-- dias; o resto já era cache morto. Custo do recompute ≈ US$ 0,26.
--
-- ROLLBACK DE EMERGÊNCIA: `UPDATE public.app_config SET
-- match_prompt_version = 'v13' WHERE id = 1;` — volta o COMPORTAMENTO, não o
-- dado: as linhas recomputadas já são v14 e o cliente veria cache vazio até
-- recomputar de novo. Registrar depois numa migration própria.

BEGIN;

UPDATE public.app_config
SET match_prompt_version = 'v14',
    updated_at = NOW()
WHERE id = 1
  AND match_prompt_version IS DISTINCT FROM 'v14';

COMMIT;
