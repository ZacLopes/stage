-- Migration: desativa vagas de baixa qualidade já salvas no banco
--
-- Não DELETA — só marca `is_active = false`. Mantém histórico (caso usuário
-- já tenha swipado/curtido) e permite reativar manualmente se algum filtro
-- pegar falso positivo.
--
-- Critério: mesmas blacklists do sync-jobs-apify (título operacional +
-- empresas de varejo de massa).

BEGIN;

-- 1. Vagas com título operacional (atendente, balconista, etc).
UPDATE public.jobs
SET is_active = false
WHERE is_active = true
  AND (
    title ~* '\matendente\M'
    OR title ~* '\mbalconist[ao]\M'
    OR title ~* '\moperador(a)? de caix[ao]\M'
    OR title ~* '\moperador(a)? de loja\M'
    OR title ~* '\mcaixa de loja\M'
    OR title ~* '\maux(iliar)? de cozinha\M'
    OR title ~* '\maux(iliar)? de loja\M'
    OR title ~* '\maux(iliar)? de limpeza\M'
    OR title ~* '\maux(iliar)? de produ[cç][aã]o\M'
    OR title ~* '\maux(iliar)? log[íi]stico\M'
    OR title ~* '\maux(iliar)? de servi[cç]os gerais\M'
    OR title ~* '\mservi[cç]os gerais\M'
    OR title ~* '\mrepositor(a)?\M'
    OR title ~* '\mempacotador(a)?\M'
    OR title ~* '\mestoquista\M'
    OR title ~* '\moperador(a)? de telemarketing\M'
    OR title ~* '\mteleoperador(a)?\M'
    OR title ~* '\mvendedor(a)? de loja\M'
    OR title ~* '\mpromotor(a)? de vendas?\M'
    OR title ~* '\mdemonstrador(a)?\M'
    OR title ~* '\mvigilante\M'
    OR title ~* '\mporteiro(a)?\M'
    OR title ~* '\mmotoboy\M'
    OR title ~* '\mmotorista\M'
    OR title ~* '\mentregador(a)?\M'
    OR title ~* '\moperador(a)? de produ[cç][aã]o\M'
    OR title ~* '\moperador(a)? de m[áa]quinas?\M'
    OR title ~* '\msoldador(a)?\M'
    OR title ~* '\mcosturei[rt][ao]\M'
    OR title ~* '\mcamareir[ao]\M'
    OR title ~* '\mgar[cç]on(ete)?\M'
    OR title ~* '\mcopeiro(a)?\M'
    OR title ~* '\mpadeiro(a)?\M'
    OR title ~* '\maçougueiro(a)?\M'
    OR title ~* '\mconfeiteiro(a)?\M'
    OR title ~* '\msushiman\M'
    OR title ~* '\mpizzaiolo\M'
    OR title ~* '\m(jovem )?aprendiz(agem)?\M'
  );

-- 2. Todas as vagas de companies com slug em varejo de massa.
UPDATE public.jobs j
SET is_active = false
WHERE j.is_active = true
  AND EXISTS (
    SELECT 1 FROM public.companies c
    WHERE c.id = j.company_id
      AND lower(coalesce(c.slug, '')) ~ ('^gupy:(' || array_to_string(ARRAY[
        'mcdonalds','mcd','burgerking','bk','subway','kfc',
        'carrefour','atacadao','paodeacucar','extra',
        'casasbahia','viavarejo',
        'americanas','lojasamericanas',
        'drogasil','drogariaspacheco','drogariasp','raia',
        'marisa','centauro-loja','habibs','habib','cacau-show'
      ], '|') || ')$')
  );

-- 3. Reativar vagas de tipo "estagio" que foram parar como is_active=false
-- mas têm título "Aprendiz" — esses ainda são alvo do filtro acima, mas
-- aprendizes legítimos de empresa boa (ex: "Aprendiz de Engenharia @ Inter")
-- ficam de fora. Sem reativação manual — confiamos no filtro pra excluir os
-- de varejo, deixar os corporativos passar é responsabilidade do sync futuro.

COMMIT;
