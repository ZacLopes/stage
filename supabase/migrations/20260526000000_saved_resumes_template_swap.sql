-- Migration: saved_resumes ganha resume_data (jsonb) e template_id (text)
--
-- Motivação: permitir que o user troque o template de um CV salvo na
-- biblioteca do Perfil. Pra fazer isso, precisamos do ResumeData
-- estruturado (não só do PDF binário). resume_data fica null em CVs
-- antigos (que continuam view-only) e em imported PDFs (sem estrutura).
--
-- template_id guarda qual template foi usado pra gerar o PDF atual no
-- file_path. Quando user troca, o app re-renderiza com template novo +
-- substitui o arquivo no Storage + atualiza essa coluna.

ALTER TABLE public.saved_resumes
  ADD COLUMN IF NOT EXISTS resume_data jsonb NULL,
  ADD COLUMN IF NOT EXISTS template_id text NULL;

COMMENT ON COLUMN public.saved_resumes.resume_data IS
  'ResumeData estruturado usado pra renderizar o PDF. Null em CVs antigos '
  'ou imported (sem estrutura). Quando presente, app habilita troca de '
  'template na tela de detalhe.';

COMMENT ON COLUMN public.saved_resumes.template_id IS
  'Template atualmente aplicado no PDF do file_path. Null em CVs antigos. '
  'Atualizado quando user troca template e re-renderiza.';
