-- Fase 4 (IA/Perfil) — F4.5: tipa os CVs legados da trilha por SOURCE.
--
-- Até aqui os CVs auto-salvos pela trilha nasciam source='manual' + título
-- 'Currículo Stage[...]', e o app decidia o modo editável pelo PREFIXO do
-- título (anti-pattern). A partir do F4.5 o tipo é ESTRUTURAL: source='trail'.
-- Esta migration converte os legados UMA vez — o título é usado só aqui, pra
-- tipar; depois o app usa o source. O valor 'trail' já entrou no CHECK de
-- source na migration 124 (general_resume_versions), então nenhum ALTER é
-- necessário.
--
-- Retrocompat: build ANTIGO lê 'trail' como 'manual' (fallback do enum Dart) e
-- segue decidindo editável pelo prefixo do título — comportamento idêntico ao
-- de hoje. CO-DEPLOY: esta migration entra JUNTO do app que grava/lê 'trail'.
--
-- Escopo estrito: só source='manual' E título começando com 'Currículo Stage'.
-- NÃO toca imported/adapted/general nem manuais de outro título. Idempotente:
-- reaplicar não muda nada (as linhas já viraram 'trail', então o WHERE não as
-- pega mais).
--
-- Triggers de saved_resumes neste UPDATE: o fence (auth.uid() NULL na migration
-- → não pega advisory), o immutable-de-general (OLD.source='manual' ≠ 'general'
-- → WHEN falso) e o mark-legacy (só BEFORE INSERT) NÃO interferem.

UPDATE public.saved_resumes
   SET source = 'trail'
 WHERE source = 'manual'
   AND title LIKE 'Currículo Stage%';
