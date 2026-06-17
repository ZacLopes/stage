#!/usr/bin/env python3
"""Gera a migration de taxonomia de skills a partir de taxonomy.json.

Saída: supabase/migrations/20260617120000_skills_taxonomy.sql — DDL (skills_catalog,
skill_aliases, profile_skills.canonical_skill_id), seed (catálogo + aliases),
trigger de normalização no write e backfill das linhas existentes.

Uso: python3 tools/skills_taxonomy/generate_seed.py
Reusável: ao estender taxonomy.json, gerar uma NOVA migration de seed (mudar OUT/ts)
em vez de reaplicar esta (migrations são imutáveis após aplicadas).
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TAX = os.path.join(HERE, "taxonomy.json")
OUT = os.path.join(ROOT, "supabase", "migrations", "20260617120000_skills_taxonomy.sql")


def q(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main():
    data = json.load(open(TAX, encoding="utf-8"))
    can = data["canonical"]

    cat_rows = ",\n  ".join(f"({q(c['name'])}, {q(c['category'])})" for c in can)

    alias_rows = []
    for c in can:
        for a in c["aliases"]:
            alias_rows.append(f"({q(a)}, {q(c['name'])})")
    alias_block = ",\n  ".join(alias_rows)

    sql = f"""-- skills taxonomy (auditoria P5) — GERADO por tools/skills_taxonomy/generate_seed.py
-- a partir de taxonomy.json v{data.get('version')}. NÃO editar à mão: editar o JSON e regerar.
--
-- Catálogo canônico de skills + mapa de aliases (texto livre normalizado → canônica)
-- + profile_skills.canonical_skill_id (name CRU permanece a verdade, padrão institution_id)
-- + trigger que normaliza em TODO insert/update (pega qualquer versão de client) + backfill.
-- {len(can)} canônicas, {len(alias_rows)} aliases.

create table if not exists public.skills_catalog (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null unique,
  category text not null check (category in ('hard','soft','tool','language')),
  created_at timestamptz not null default now()
);

create table if not exists public.skill_aliases (
  alias_normalized text primary key,
  canonical_skill_id uuid not null references public.skills_catalog(id) on delete cascade
);

alter table public.profile_skills
  add column if not exists canonical_skill_id uuid references public.skills_catalog(id) on delete set null;

create index if not exists profile_skills_canonical_idx on public.profile_skills(canonical_skill_id);
create index if not exists skill_aliases_canon_idx on public.skill_aliases(canonical_skill_id);

-- Reference data pública (nomes de skill, não-PII): RLS on + leitura p/ todos os papéis.
alter table public.skills_catalog enable row level security;
alter table public.skill_aliases enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='skills_catalog' and policyname='skills_catalog_read') then
    create policy skills_catalog_read on public.skills_catalog for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='skill_aliases' and policyname='skill_aliases_read') then
    create policy skill_aliases_read on public.skill_aliases for select using (true);
  end if;
end $$;
grant select on public.skills_catalog to anon, authenticated, service_role;
grant select on public.skill_aliases to anon, authenticated, service_role;

-- ── Seed: catálogo ──────────────────────────────────────────────────────────
insert into public.skills_catalog (canonical_name, category) values
  {cat_rows}
on conflict (canonical_name) do nothing;

-- ── Seed: aliases (resolve canônica por nome) ─────────────────────────────────
insert into public.skill_aliases (alias_normalized, canonical_skill_id)
select v.alias, c.id
from (values
  {alias_block}
) as v(alias, canon)
join public.skills_catalog c on c.canonical_name = v.canon
on conflict (alias_normalized) do nothing;

-- ── Trigger: normaliza canonical_skill_id em TODO write de name ───────────────
create or replace function public.set_canonical_skill_id() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select a.canonical_skill_id into new.canonical_skill_id
  from public.skill_aliases a
  where a.alias_normalized = lower(btrim(new.name));
  return new;
end $$;

drop trigger if exists trg_profile_skills_canonical on public.profile_skills;
create trigger trg_profile_skills_canonical
  before insert or update of name on public.profile_skills
  for each row execute function public.set_canonical_skill_id();

-- ── Backfill das linhas existentes (não dispara o trigger: seta a coluna direto) ─
update public.profile_skills ps
set canonical_skill_id = a.canonical_skill_id
from public.skill_aliases a
where a.alias_normalized = lower(btrim(ps.name))
  and ps.canonical_skill_id is distinct from a.canonical_skill_id;
"""
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8").write(sql)
    print(f"escrito: {OUT}")
    print(f"{len(can)} canônicas, {len(alias_rows)} aliases")


if __name__ == "__main__":
    main()
