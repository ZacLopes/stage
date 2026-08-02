-- "Informática básica" passa a se chamar "Informática".
--
-- Achado durante a classificação dos aliases (01/08). É a ÚNICA canônica do
-- catálogo com nível embutido no nome — as outras 164 nomeiam a habilidade, não
-- o grau em que a pessoa a tem.
--
-- ## Por que o nome é o defeito
--
-- Nível é atributo de QUEM tem a habilidade, não da habilidade. Com "básica" no
-- nome, 14 aliases apontam para uma afirmação que nem sempre é verdadeira:
--
--   informática avançada       -> "Informática básica"   ← afirma o oposto
--   informática intermediária  -> "Informática básica"   ← nível se perde
--   informática                -> "Informática básica"   ← quem não declarou
--                                                          nível vira "básica"
--   habilidades em informática -> "Informática básica"
--   conhecimento em informática-> "Informática básica"
--
-- Nenhum desses mapeamentos está errado como AGRUPAMENTO — é o rótulo que
-- mente. Com a canônica chamada "Informática", os cinco viram verdade.
--
-- ## O que muda na prática
--
-- 93 perfis estão carimbados com esta canônica. Nenhum deles muda de linha:
-- o `canonical_skill_id` é o mesmo, só o RÓTULO exibido muda. Afeta:
--   - a faceta de skills da busca de candidatos do admin (rótulo);
--   - as sugestões do typeahead do editor de skills (rótulo);
--   - ⚠️ **o prompt do `analyze-match`**, que lê
--     `profile_skills → skills_catalog(canonical_name)` (index.ts:271) e ESTÁ
--     NO AR. Para os 93 perfis com esta canônica, o texto enviado ao modelo
--     muda de "Informática básica" para "Informática" — o que muda a análise e
--     invalida o cache dessas pessoas, recomputado sob demanda.
--     Eu tinha escrito aqui que era "só rótulo". Era falso: a auditoria das
--     migrations pegou, e eu confirmei no código.
--   - o gatilho `set_canonical_skill_id` NÃO é afetado: casa por
--     `alias_normalized`, não pelo nome da canônica.
--
-- ## O que esta migration NÃO faz
--
-- Não cria "Informática avançada" nem move ninguém de canônica. Se um dia o
-- catálogo ganhar níveis como canônicas separadas, a classificação de aliases
-- (`match_kind`) precisa ser refeita para essa família — hoje 3 delas são
-- `level` e 5 são `scope` justamente por causa do nome antigo.
--
-- Idempotente: só renomeia se o nome antigo ainda existir, e só se o novo ainda
-- não existir (evita colidir com uma canônica "Informática" criada à mão).

begin;

update public.skills_catalog
set canonical_name = 'Informática'
where canonical_name = 'Informática básica'
  and not exists (
    select 1 from public.skills_catalog where canonical_name = 'Informática'
  );

-- O alias literal do nome antigo continua valendo: quem escreveu
-- "informática básica" no perfil tem que continuar casando.
--
-- ⚠️ `do update`, não `do nothing`. A linha JÁ EXISTE (era o nome da canônica,
-- então virou alias dela) e estava classificada como `exact` — a classe que
-- autoriza esconder. Com `do nothing` o INSERT não executava, a classificação
-- ficava intacta, e o resultado era: quem escreveu só "informática" passaria a
-- "possuir" "informática básica", e uma vaga pedindo isso sumiria da folha
-- dela. Achado na auditoria das migrations (01/08).
--
-- O erro é meu e é do tipo que o teste não pega: `owned_skills.test.ts` fica
-- verde porque o fixture dele só tem Excel e Comunicação.
--
-- Pela minha própria rubrica, "informática básica" carrega nível explícito
-- contra uma canônica que (após o rename) não carrega — logo é `level`. A
-- migration estava inconsistente consigo mesma: rebaixava "noções de
-- informática" e deixava esta como sinônimo pleno.
insert into public.skill_aliases (alias_normalized, canonical_skill_id, match_kind)
select 'informática básica', sc.id, 'level'
from public.skills_catalog sc
where sc.canonical_name = 'Informática'
on conflict (alias_normalized) do update set match_kind = 'level';

-- Com o rótulo consertado, "informática" sem nível deixa de ser `scope`
-- (não estreita mais nada) e vira sinônimo de verdade.
update public.skill_aliases set match_kind = 'exact'
where alias_normalized in (
  'informática',
  'conhecimento em informática',
  'conhecimentos em informática',
  'habilidades em informática'
);

-- E "informática avançada" deixa de ser contraditória: vira nível, como as
-- outras variações de grau.
update public.skill_aliases set match_kind = 'level'
where alias_normalized in (
  'informática avançada',
  'informática básica e avançada',
  'informática intermediária',
  'conhecimento básico em informática',
  'conhecimentos básicos em informática',
  'noções de informática'
);

commit;
