-- Adiciona policy de UPDATE no bucket `resumes` do Storage.
--
-- Faltava: o bucket tinha INSERT/SELECT/DELETE, mas não UPDATE. Quando o app
-- faz `upsert: true` pra sobrescrever um PDF existente (caso de uso: troca
-- de template em CV salvo na biblioteca), o RLS rejeita com
-- StorageException 403 "new row violates row-level security policy".
--
-- Regra simétrica às outras 3: user só atualiza arquivos dentro da pasta
-- `<auth.uid()>/` (folder root da própria conta).
--
-- DROP IF EXISTS torna idempotente — a policy foi aplicada manual no remoto
-- antes do histórico de migrations ser corrigido, então sem essa guarda
-- `supabase db push --include-all` falharia com "already exists".

DROP POLICY IF EXISTS "Users can update their own resumes in storage" ON storage.objects;

CREATE POLICY "Users can update their own resumes in storage"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'resumes'
    AND (storage.foldername(name))[1] = (auth.uid())::text
  )
  WITH CHECK (
    bucket_id = 'resumes'
    AND (storage.foldername(name))[1] = (auth.uid())::text
  );
