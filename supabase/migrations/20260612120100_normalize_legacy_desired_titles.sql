-- FASE 2 (T2.1, decisão D-11 do PLANO-FASE-2): normaliza títulos legacy do
-- merge F1 em profile_desired_titles — SÓ mapeamentos não-ambíguos
-- ("processos" fica de fora, registrado no plano). Títulos como
-- "administração" não casam nenhuma vaga no client (sem match direto nem
-- sinônimo pra "Administrativo") → feed zerado silencioso pros donos.
-- Parity-safe: client e RPC leem a MESMA tabela; harness tools/feed_parity/
-- re-rodado após aplicar (checklist T2.1).
--
-- Fato vence o plano: contagem real em 12/06 = 49 rows (plano estimava ~25;
-- o B6 só listava a cabeça da cauda). Inclui variações de caixa
-- ("tecnologia & Programação", "marketing & branding" etc.) — por isso o
-- match é por forma normalizada (lower + unaccent + btrim).
--
-- Padrão ajustado vs o literal do plano (UPDATE anti-duplicata + DELETE):
-- com 2 rows legacy do MESMO user apontando pro mesmo alvo, o NOT EXISTS
-- num único UPDATE enxerga o snapshot do início do statement e criaria
-- duplicata. Equivalente snapshot-safe: (1) reescreve TODAS as legacy pro
-- alvo; (2) dedup mantendo a row de menor (order_index, id) por
-- (user, título normalizado), só entre títulos-alvo. Mesmo estado final.
-- Idempotente: re-rodar = 0 rows afetadas nos dois passos.

-- Passo 1 — reescreve legacy → título canônico (área que existe em jobs.area)
with mapping(legacy_norm, target) as (values
  ('administracao',             'Administrativo'),
  ('administracao & processos', 'Administrativo'),
  ('tecnologia & programacao',  'Tecnologia'),
  ('programacao',               'Tecnologia'),
  ('marketing',                 'Marketing'),
  ('marketing & branding',      'Marketing'),
  ('vendas',                    'Vendas'),
  ('financas & controladoria',  'Finanças')
)
update profile_desired_titles t
   set title = m.target
  from mapping m
 where lower(btrim(extensions.unaccent(t.title))) = m.legacy_norm
   and t.title is distinct from m.target;

-- Passo 2 — dedup por (user, título normalizado), só entre os alvos do D-11
-- (não encosta em duplicatas de outros títulos — fora do escopo da fase).
delete from profile_desired_titles t
 using profile_desired_titles k
 where t.user_id = k.user_id
   and t.id <> k.id
   and lower(btrim(extensions.unaccent(t.title))) = lower(btrim(extensions.unaccent(k.title)))
   and lower(btrim(extensions.unaccent(t.title))) in
       ('administrativo', 'tecnologia', 'marketing', 'vendas', 'financas')
   and (k.order_index < t.order_index
        or (k.order_index = t.order_index and k.id < t.id));

-- Verificação do aceite #9 (rodar pós-migration; esperado: 0):
--   select count(*) from profile_desired_titles t
--    join (values ('administracao','Administrativo'),('administracao & processos','Administrativo'),
--                 ('tecnologia & programacao','Tecnologia'),('programacao','Tecnologia'),
--                 ('marketing','Marketing'),('marketing & branding','Marketing'),
--                 ('vendas','Vendas'),('financas & controladoria','Finanças')) m(legacy_norm, target)
--      on lower(btrim(extensions.unaccent(t.title))) = m.legacy_norm
--     and t.title is distinct from m.target;
