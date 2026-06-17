# skills_taxonomy — vocabulário canônico de skills (auditoria P5)

Resolve a fragmentação de `profile_skills` (texto livre: 2.591 strings distintas,
83,7% únicas) num **vocabulário canônico** + **mapa de aliases** + classificação
**hard/soft/tool/language**. Espelha o padrão do catálogo `institutions`
(catálogo + FK `canonical_skill_id` + typeahead; texto cru `name` continua a verdade).

## Artefatos

- `dump_skills.sql` — query que lista as strings distintas + contagem (input do
  clustering). Roda como service role (MCP `execute_sql` ou Studio). **Dado vai
  pra arquivo local, gitignored — não commitar `skills_dump*.json`.**
- `taxonomy.json` — **seed revisável** (fonte da verdade): lista canônica + categoria
  + aliases normalizados. Editar à mão pra ajustar. A migration de seed é gerada a
  partir dele.

## Como regenerar / estender

1. `dump_skills.sql` em prod → ver as strings sem alias (`canonical_skill_id` null).
2. Estender `taxonomy.json` com as novas (clustering LLM sobre os não-mapeados).
3. Gerar/atualizar a migration de seed (`supabase/migrations/*_skills_taxonomy_seed*.sql`)
   a partir do `taxonomy.json` e aplicar via `supabase db push` (R2 + manifest).

## Convenções

- `aliases` são as formas **normalizadas** (`lower(btrim(name))`) que mapeiam pra
  canônica. O trigger em `profile_skills` faz lookup exato por essa forma.
- Categorias: `hard` (conhecimento técnico), `tool` (software/produto), `soft`
  (comportamental), `language` (idioma). O match agrupa `hard`∪`tool` = técnico;
  `soft` NÃO conta pro fit técnico.
- String não-mapeável (typo raro, frase, lixo de serialização) → fica sem alias
  (`canonical_skill_id` null). Typeahead + re-clustering cobrem a cauda no tempo.
