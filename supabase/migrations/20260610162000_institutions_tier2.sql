-- Fase 1 T1.6 — tier 2 (última expansão do backfill; depois desta, a cauda
-- é de ocorrências únicas — o typeahead do client 2.3.0 cobre dali em
-- diante). Pós-tier1: college 685/1035 = 66,2%. "puc" genérica fica de fora
-- (ambígua entre PUCs). ETEC entra como entidade própria (Centro Paula
-- Souza nível técnico — não é FATEC).

INSERT INTO public.institutions (name, normalized_name, aliases, type, state) VALUES
  ('ETEC — Centro Paula Souza', 'etec', '{escola tecnica estadual}', 'tecnica', 'SP'),
  ('UFRA — Universidade Federal Rural da Amazônia', 'ufbra', '{ufra}', 'publica', 'PA'),
  ('Unifran', 'unifran', '{universidade de franca}', 'privada', 'SP'),
  ('Fametro', 'fametro', '{faculdade metropolitana}', 'privada', NULL),
  ('UCSal — Universidade Católica do Salvador', 'ucsal', '{universidade catolica do salvador}', 'privada', 'BA'),
  ('UniÍtalo', 'uni italo', '{uniitalo,centro universitario italo brasileiro}', 'privada', 'SP'),
  ('ENIAC', 'eniac', '{faculdade eniac}', 'privada', 'SP'),
  ('Unijorge', 'unijorge', '{centro universitario jorge amado}', 'privada', 'BA'),
  ('Cásper Líbero', 'casper libero', '{faculdade casper libero,fundacao casper libero}', 'privada', 'SP'),
  ('Unisanta — Universidade Santa Cecília', 'unisanta', '{universidade santa cecilia}', 'privada', 'SP'),
  ('Instituto Mauá de Tecnologia', 'instituto maua de tecnologia', '{maua,imt}', 'privada', 'SP'),
  ('UFFS — Universidade Federal da Fronteira Sul', 'uffs', '{universidade federal da fronteira sul}', 'publica', NULL),
  ('UFRPE — Universidade Federal Rural de Pernambuco', 'ufrpe', '{universidade federal rural de pernambuco}', 'publica', 'PE'),
  ('IBMR', 'ibmr', '{centro universitario ibmr}', 'privada', 'RJ'),
  ('Pitágoras', 'pitagoras', '{faculdade pitagoras}', 'privada', NULL),
  ('Unime', 'unime', '{uniao metropolitana de educacao e cultura}', 'privada', 'BA'),
  ('Wyden', 'wyden', '{faculdade wyden,unifanor wyden}', 'privada', NULL),
  ('EBAC', 'ebac', '{escola britanica de artes criativas}', 'privada', 'SP'),
  ('UniBra', 'unibra', '{centro universitario brasileiro}', 'privada', 'PE'),
  ('Veiga de Almeida', 'veiga de almeida', '{universidade veiga de almeida,uva rj}', 'privada', 'RJ'),
  ('Uniube — Universidade de Uberaba', 'uniube', '{universidade de uberaba}', 'privada', 'MG'),
  ('UniBH', 'unibh', '{centro universitario de belo horizonte}', 'privada', 'MG'),
  ('Una', 'una', '{centro universitario una}', 'privada', 'MG'),
  ('Unama — Universidade da Amazônia', 'unama', '{universidade da amazonia}', 'privada', 'PA'),
  ('USF — Universidade São Francisco', 'usf', '{universidade sao francisco}', 'privada', 'SP'),
  ('UDF — Centro Universitário do Distrito Federal', 'udf', '{centro universitario do distrito federal}', 'privada', 'DF'),
  ('Unoeste — Universidade do Oeste Paulista', 'unoeste', '{universidade do oeste paulista}', 'privada', 'SP'),
  ('IFSP — Instituto Federal de São Paulo', 'ifsp', '{instituto federal de sao paulo,instituto federal sp}', 'publica', 'SP'),
  ('UniGrande — Centro Universitário da Grande Fortaleza', 'uni grande', '{unigrande}', 'privada', 'CE')
ON CONFLICT (normalized_name) DO NOTHING;

-- Re-backfill idempotente (mesmas 4 passes).
UPDATE public.profile_education pe SET institution_id = i.id
FROM public.institutions i
WHERE pe.institution_id IS NULL
  AND public._normalize_institution(pe.institution) = i.normalized_name;

UPDATE public.profile_education pe SET institution_id = i.id
FROM public.institutions i, unnest(i.aliases) AS a
WHERE pe.institution_id IS NULL
  AND public._normalize_institution(pe.institution)
      = public._normalize_institution(a);

UPDATE public.profile_education pe SET institution_id = i.id
FROM public.institutions i
WHERE pe.institution_id IS NULL
  AND length(i.normalized_name) >= 4
  AND public._normalize_institution(pe.institution)
      ~ ('\m' || i.normalized_name || '\M');

UPDATE public.profile_education pe SET institution_id = i.id
FROM public.institutions i, unnest(i.aliases) AS a
WHERE pe.institution_id IS NULL
  AND length(a) >= 4
  AND public._normalize_institution(pe.institution)
      ~ ('\m' || public._normalize_institution(a) || '\M');
