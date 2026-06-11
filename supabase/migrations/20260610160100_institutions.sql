-- Fase 1 T1.6 — catálogo de instituições + vínculo em profile_education +
-- backfill best-effort. Resolve a fragmentação do texto livre (V8: 2.288
-- rows; USP 65, variantes UNIP/Cruzeiro do Sul/SENAI fragmentadas; FATEC
-- invisível no top-30 exatamente pela fragmentação — motivo da inclusão
-- com aliases agressivos, decisão do fundador #3).
-- Meta de aceite: ≥70% das rows education_level='college' casadas
-- (containment cru já dava 50,4% em plan mode).

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

-- Wrapper IMMUTABLE (unaccent é STABLE; dicionário não muda em prática —
-- truque padrão pra permitir uso em índices/backfills determinísticos).
CREATE OR REPLACE FUNCTION public._normalize_institution(t text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT lower(extensions.unaccent(trim(coalesce(t, ''))));
$$;

CREATE TABLE public.institutions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  normalized_name text NOT NULL UNIQUE,
  aliases text[] NOT NULL DEFAULT '{}',
  type text CHECK (type IS NULL OR type IN ('publica','privada','tecnica')),
  city text,
  state text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.institutions ENABLE ROW LEVEL SECURITY;
CREATE POLICY institutions_select_auth ON public.institutions FOR SELECT
  TO authenticated USING (true);
-- Sem escrita client: catálogo é mantido por migration/ops.

-- Seed (32 — lista aprovada 10/06 + UNESP, FATEC/Centro Paula Souza, UFABC,
-- ESPM, FEI). normalized_name SEM caracteres de regex (o backfill pass 2 usa
-- word-boundary match); variantes vão em aliases.
INSERT INTO public.institutions (name, normalized_name, aliases, type, state) VALUES
  ('USP — Universidade de São Paulo', 'usp', '{universidade de sao paulo}', 'publica', 'SP'),
  ('UNICAMP — Universidade Estadual de Campinas', 'unicamp', '{universidade estadual de campinas}', 'publica', 'SP'),
  ('UNESP — Universidade Estadual Paulista', 'unesp', '{universidade estadual paulista}', 'publica', 'SP'),
  ('UFMG — Universidade Federal de Minas Gerais', 'ufmg', '{universidade federal de minas gerais}', 'publica', 'MG'),
  ('UFRJ — Universidade Federal do Rio de Janeiro', 'ufrj', '{universidade federal do rio de janeiro}', 'publica', 'RJ'),
  ('UFABC — Universidade Federal do ABC', 'ufabc', '{universidade federal do abc}', 'publica', 'SP'),
  ('FATEC — Centro Paula Souza', 'fatec', '{centro paula souza,fatec sp,fatec sao paulo,fatec zona leste,fatec zl,fatec zona sul,fatec ipiranga,fatec osasco,fatec santo andre,fatec sao caetano,faculdade de tecnologia}', 'tecnica', 'SP'),
  ('Anhanguera', 'anhanguera', '{universidade anhanguera,anhanguera educacional}', 'privada', NULL),
  ('Estácio', 'estacio', '{estacio de sa,universidade estacio,universidade estacio de sa}', 'privada', NULL),
  ('Uninove — Universidade Nove de Julho', 'uninove', '{universidade nove de julho,nove de julho}', 'privada', 'SP'),
  ('UNIP — Universidade Paulista', 'unip', '{universidade paulista}', 'privada', 'SP'),
  ('Cruzeiro do Sul', 'cruzeiro do sul', '{universidade cruzeiro do sul,unicsul}', 'privada', 'SP'),
  ('Mackenzie — Universidade Presbiteriana Mackenzie', 'mackenzie', '{universidade presbiteriana mackenzie,upm}', 'privada', 'SP'),
  ('PUC-SP — Pontifícia Universidade Católica de São Paulo', 'puc-sp', '{puc sp,pucsp,pontificia universidade catolica de sao paulo}', 'privada', 'SP'),
  ('PUC-Campinas', 'puc-campinas', '{puc campinas,puccamp,pontificia universidade catolica de campinas}', 'privada', 'SP'),
  ('SENAI', 'senai', '{servico nacional de aprendizagem industrial,escola senai,faculdade senai}', 'tecnica', NULL),
  ('SENAC', 'senac', '{servico nacional de aprendizagem comercial,faculdade senac,centro universitario senac}', 'tecnica', NULL),
  ('Fundação Bradesco', 'fundacao bradesco', '{escola fundacao bradesco}', 'tecnica', NULL),
  ('Uniasselvi', 'uniasselvi', '{centro universitario leonardo da vinci}', 'privada', 'SC'),
  ('São Judas — Universidade São Judas Tadeu', 'sao judas', '{universidade sao judas tadeu,sao judas tadeu,usjt}', 'privada', 'SP'),
  ('Unicid — Universidade Cidade de São Paulo', 'unicid', '{universidade cidade de sao paulo}', 'privada', 'SP'),
  ('Insper', 'insper', '{instituto de ensino e pesquisa}', 'privada', 'SP'),
  ('Unicesumar', 'unicesumar', '{centro universitario de maringa,cesumar}', 'privada', 'PR'),
  ('FGV — Fundação Getulio Vargas', 'fgv', '{fundacao getulio vargas}', 'privada', NULL),
  ('Uninassau', 'uninassau', '{centro universitario mauricio de nassau,mauricio de nassau}', 'privada', NULL),
  ('FIAP', 'fiap', '{faculdade de informatica e administracao paulista}', 'privada', 'SP'),
  ('Anhembi Morumbi', 'anhembi morumbi', '{universidade anhembi morumbi,anhembi}', 'privada', 'SP'),
  ('Metodista — Universidade Metodista de São Paulo', 'metodista', '{universidade metodista de sao paulo,universidade metodista}', 'privada', 'SP'),
  ('FMU', 'fmu', '{faculdades metropolitanas unidas,centro universitario fmu}', 'privada', 'SP'),
  ('Link School of Business', 'link school', '{link school of business,link sb}', 'privada', 'SP'),
  ('ESPM', 'espm', '{escola superior de propaganda e marketing}', 'privada', 'SP'),
  ('FEI — Centro Universitário FEI', 'fei', '{centro universitario fei,faculdade de engenharia industrial}', 'privada', 'SP')
ON CONFLICT (normalized_name) DO NOTHING;

ALTER TABLE public.profile_education
  ADD COLUMN IF NOT EXISTS institution_id uuid REFERENCES public.institutions(id);

-- ── Backfill best-effort (idempotente — só rows com institution_id NULL) ──
-- Pass 1: igualdade normalizada exata com o nome canônico.
UPDATE public.profile_education pe
SET institution_id = i.id
FROM public.institutions i
WHERE pe.institution_id IS NULL
  AND public._normalize_institution(pe.institution) = i.normalized_name;

-- Pass 1b: igualdade normalizada exata com qualquer alias.
UPDATE public.profile_education pe
SET institution_id = i.id
FROM public.institutions i, unnest(i.aliases) AS a
WHERE pe.institution_id IS NULL
  AND public._normalize_institution(pe.institution)
      = public._normalize_institution(a);

-- Pass 2: containment com fronteira de palavra (nomes ≥4 chars — evita
-- usp/fei/fgv casarem dentro de outras palavras; esses ficam nas passes
-- exatas, que cobrem o caso comum "USP"). Ambiguidade múltipla: best-effort,
-- primeiro match arbitrário (texto cita 2 IES é raro e revisável depois).
UPDATE public.profile_education pe
SET institution_id = i.id
FROM public.institutions i
WHERE pe.institution_id IS NULL
  AND length(i.normalized_name) >= 4
  AND public._normalize_institution(pe.institution)
      ~ ('\m' || i.normalized_name || '\M');

-- Pass 2b: containment por alias (≥4 chars).
UPDATE public.profile_education pe
SET institution_id = i.id
FROM public.institutions i, unnest(i.aliases) AS a
WHERE pe.institution_id IS NULL
  AND length(a) >= 4
  AND public._normalize_institution(pe.institution)
      ~ ('\m' || public._normalize_institution(a) || '\M');
