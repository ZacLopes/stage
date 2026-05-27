-- Adiciona description_html (HTML cru) ao lado do description (texto plano)
-- pra que o app renderize formatação (negrito, listas, headings) via
-- flutter_html. As 4 sync functions (apify, brazil, greenhouse, lever)
-- passam a gravar ambos: HTML cru no novo campo + plain text no antigo
-- (que continua sendo usado pra match score, JobCard preview e analytics).
--
-- Mudança não-destrutiva — colunas TEXT NULL, vagas existentes ficam com
-- NULL e o app cai no fallback de texto plano até serem re-sincronizadas.

ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS description_html TEXT;
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS description_html TEXT;

COMMENT ON COLUMN public.jobs.description_html IS 'HTML cru do description preservado pra renderização rica no app (flutter_html). O campo description continua sendo texto plano pra match score e analytics.';
COMMENT ON COLUMN public.companies.description_html IS 'HTML cru do description da empresa pra renderização rica no app.';
