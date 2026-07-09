-- Migration: profile_experiences.kind
--
-- Tipo da experiência coletado na trilha de coleta (seção Experiência por tipo):
-- emprego / estagio / monitoria / voluntariado / atletica / freela / familia /
-- outro (ou um rótulo livre, quando "Outro"). Aditiva e NULLABLE — o import por
-- extração e as linhas legadas ficam com kind = NULL (o app tolera ausência).
--
-- O client só envia `kind` no caminho da trilha (atrás da flag trilha_coleta_v1);
-- os INSERTs do save_profile RPC não setam a coluna (nullable, sem default).

BEGIN;

ALTER TABLE public.profile_experiences
  ADD COLUMN IF NOT EXISTS kind TEXT;

COMMENT ON COLUMN public.profile_experiences.kind IS
  'Tipo da experiência coletado na trilha (emprego/estagio/monitoria/voluntariado/atletica/freela/familia/outro ou rótulo livre). NULL p/ import/legado.';

COMMIT;
