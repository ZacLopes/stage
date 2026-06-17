-- skills_taxonomy: input do clustering. Lista strings distintas normalizadas +
-- contagem + quantos usuários. Rodar como service role (MCP execute_sql ou
-- Studio); salvar saída em tools/skills_taxonomy/skills_dump.json (gitignored).
with base as (
  select lower(btrim(name)) as norm
  from profile_skills
  where coalesce(btrim(name),'') <> ''
)
select json_agg(json_build_object('norm', norm, 'c', c) order by c desc, norm) as dump
from (select norm, count(*) c from base group by norm) g;
