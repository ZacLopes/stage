-- Adiciona 2 empresas BR descobertas na auditoria 2026-05-20:
--   • XP Inc (xpinc):  156 vagas totais, 129 BR, ~19 entry-level
--   • Getnet (getnet): 70 vagas totais, 47 BR, ~3 entry-level
--
-- Ambas validadas via curl direto na Greenhouse boards API.
-- Esperado: +20-25 vagas/dia ativas no feed (após filtros isBrazil + isEntryLevel).

INSERT INTO public.external_job_sources (ats, company_slug, display_name)
VALUES
  ('greenhouse', 'xpinc',  'XP Inc'),
  ('greenhouse', 'getnet', 'Getnet')
ON CONFLICT (ats, company_slug) DO NOTHING;
