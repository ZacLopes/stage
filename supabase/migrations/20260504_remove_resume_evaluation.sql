-- Migration: Remove a feature de "IA analisa CV pronto" do app.
-- Apaga logs de geração relacionados às edge functions evaluate-resume e
-- refine-resume (ambas removidas em 2026-05-04). As tabelas e colunas
-- continuam existindo — só limpamos os tipos de evento que não existem
-- mais.

DELETE FROM ai_generation_logs
  WHERE generation_type IN ('resume_evaluation', 'resume_refine');
