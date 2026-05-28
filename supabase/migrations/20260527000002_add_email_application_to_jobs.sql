-- Adiciona suporte a vagas em que a candidatura é por email (não URL).
--
-- Contexto: começamos a ingerir vagas via mailing (ex: Polifinance) onde
-- o candidato envia o CV pra um endereço como "rpgm@empresa.com.br" com
-- um assunto específico — não há URL de ATS pra apontar.
--
-- Schema:
--   application_method = 'url'   → comportamento legacy (external_url aponta
--                                  pra Greenhouse/Lever/Gupy/site da empresa)
--   application_method = 'email' → app abre mailto:application_email com
--                                  application_subject pré-preenchido
--
-- Vagas existentes (todas com application_method NULL → fallback 'url').

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS application_method TEXT
    DEFAULT 'url'
    CHECK (application_method IN ('url', 'email'));

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS application_email TEXT;

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS application_subject TEXT;

-- Quando method='email', application_email é obrigatório. Quando method='url',
-- application_email deve ser NULL pra não confundir o frontend.
ALTER TABLE public.jobs
  DROP CONSTRAINT IF EXISTS jobs_application_method_consistency;
ALTER TABLE public.jobs
  ADD CONSTRAINT jobs_application_method_consistency
  CHECK (
    (application_method = 'email' AND application_email IS NOT NULL AND application_email <> '')
    OR
    (application_method = 'url' AND application_email IS NULL)
  );

COMMENT ON COLUMN public.jobs.application_method IS
  'Como o candidato aplica: ''url'' (legacy, abre external_url no browser) ou ''email'' (abre mailto:application_email com application_subject).';

COMMENT ON COLUMN public.jobs.application_email IS
  'Email do recrutador pra envio de CV. Só preenchido quando application_method=''email''. Ex: rpgm@bbscp.com.br';

COMMENT ON COLUMN public.jobs.application_subject IS
  'Assunto recomendado pro email de candidatura. App substitui placeholders tipo [SEU NOME]. Ex: ''Vaga Investimentos Alternativos – [SEU NOME]''';
