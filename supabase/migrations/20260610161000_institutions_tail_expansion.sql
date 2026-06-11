-- Fase 1 T1.6 — expansão do catálogo a partir do top de valores distintos
-- NÃO-casados (passada prevista no plano; medição pós-seed: college 530/1035
-- = 51,2%, meta ≥70%). A cauda revelou que o gap é AMPLITUDE do catálogo
-- (IES reais fora do seed de 32), não variantes — então além dos 2 aliases
-- que faltavam (unesa→Estácio, link→Link School), entram as IES recorrentes
-- da base real. Backfill re-executado ao final (passes idempotentes:
-- só rows com institution_id IS NULL).

-- Aliases que o top-100 revelou:
UPDATE public.institutions SET aliases = aliases || '{unesa}'
 WHERE normalized_name = 'estacio' AND NOT ('unesa' = ANY(aliases));
UPDATE public.institutions SET aliases = aliases || '{link}'
 WHERE normalized_name = 'link school' AND NOT ('link' = ANY(aliases));

-- IES recorrentes da cauda real (≥2 ocorrências em college não-casadas):
INSERT INTO public.institutions (name, normalized_name, aliases, type, state) VALUES
  ('Uninter', 'uninter', '{centro universitario internacional}', 'privada', 'PR'),
  ('Unopar', 'unopar', '{universidade norte do parana}', 'privada', 'PR'),
  ('UNASP', 'unasp', '{centro universitario adventista de sao paulo}', 'privada', 'SP'),
  ('UNISA — Universidade Santo Amaro', 'unisa', '{universidade santo amaro}', 'privada', 'SP'),
  ('FAM — Faculdade das Américas', 'fam', '{faculdade das americas,centro universitario das americas}', 'privada', 'SP'),
  ('Uniceplac', 'uniceplac', '{centro universitario do planalto central}', 'privada', 'DF'),
  ('UniFECAF', 'unifecaf', '{fecaf}', 'privada', 'SP'),
  ('Univesp', 'univesp', '{universidade virtual do estado de sao paulo}', 'publica', 'SP'),
  ('FECAP', 'fecap', '{fundacao escola de comercio alvares penteado}', 'privada', 'SP'),
  ('Universidade Positivo', 'universidade positivo', '{positivo}', 'privada', 'PR'),
  ('UCB — Universidade Católica de Brasília', 'ucb', '{universidade catolica de brasilia}', 'privada', 'DF'),
  ('UniCEUB', 'uniceub', '{centro universitario de brasilia,ceub}', 'privada', 'DF'),
  ('UNIFESP — Universidade Federal de São Paulo', 'unifesp', '{universidade federal de sao paulo}', 'publica', 'SP'),
  ('UFMS — Universidade Federal de Mato Grosso do Sul', 'ufms', '{universidade federal de mato grosso do sul}', 'publica', 'MS'),
  ('UFBA — Universidade Federal da Bahia', 'ufba', '{universidade federal da bahia}', 'publica', 'BA'),
  ('UFMA — Universidade Federal do Maranhão', 'ufma', '{universidade federal do maranhao}', 'publica', 'MA'),
  ('USCS — Universidade Municipal de São Caetano do Sul', 'uscs', '{universidade municipal de sao caetano}', 'publica', 'SP'),
  ('UMC — Universidade de Mogi das Cruzes', 'umc', '{universidade de mogi das cruzes}', 'privada', 'SP'),
  ('ESAMC', 'esamc', '{}', 'privada', 'SP'),
  ('UNIFACS', 'unifacs', '{universidade salvador}', 'privada', 'BA'),
  ('UNISUAM', 'unisuam', '{centro universitario augusto motta}', 'privada', 'RJ'),
  ('Unigran', 'unigran', '{centro universitario da grande dourados}', 'privada', 'MS'),
  ('Multivix', 'multivix', '{}', 'privada', 'ES'),
  ('Grau Técnico', 'grau tecnico', '{}', 'tecnica', NULL),
  ('Afya', 'afya', '{}', 'privada', NULL),
  ('UNIG — Universidade Iguaçu', 'unig', '{universidade iguacu}', 'privada', 'RJ'),
  ('UniFatecie', 'unifatecie', '{fatecie}', 'privada', 'PR'),
  ('Celso Lisboa', 'celso lisboa', '{centro universitario celso lisboa}', 'privada', 'RJ'),
  ('CEFET-MG', 'cefet-mg', '{cefet mg,centro federal de educacao tecnologica de minas gerais}', 'publica', 'MG'),
  ('UniGoiás', 'unigoias', '{centro universitario de goias}', 'privada', 'GO'),
  ('Bras Cubas', 'bras cubas', '{universidade bras cubas}', 'privada', 'SP'),
  ('UVV — Universidade Vila Velha', 'uvv', '{universidade vila velha}', 'privada', 'ES'),
  ('FSG — Centro Universitário da Serra Gaúcha', 'fsg', '{centro universitario da serra gaucha}', 'privada', 'RS'),
  ('UniPiaget', 'unipiaget', '{piaget}', 'privada', 'SP')
ON CONFLICT (normalized_name) DO NOTHING;

-- Re-backfill (idempotente — só institution_id IS NULL):
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
