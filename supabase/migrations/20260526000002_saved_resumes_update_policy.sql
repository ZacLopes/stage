-- Adiciona policy de UPDATE em `public.saved_resumes`.
--
-- Faltava: a tabela tinha SELECT/INSERT/DELETE mas nenhuma policy de UPDATE.
-- Quando o app atualiza `template_id` (caso de uso: troca de template no
-- detalhe da biblioteca), o UPDATE roda mas RLS filtra todas as rows, e
-- `.select().single()` cai com PGRST116 (0 rows).
--
-- Regra simétrica às outras: user só atualiza rows da própria conta.
-- `with_check` evita também que user mude `user_id` pra outro id.

CREATE POLICY "Users can update their own resumes"
  ON public.saved_resumes
  FOR UPDATE
  TO authenticated
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);
