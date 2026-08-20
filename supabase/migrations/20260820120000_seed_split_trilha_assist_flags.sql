-- Separa `trilha_assist_v1` em partes que podem ser ligadas independentemente.
--
-- POR QUE (decisão do fundador, 20/08/2026):
-- Uma única leitura de flag governava CINCO comportamentos. O fundador quer
-- dois deles e explicitamente NÃO quer os outros três:
--
--   QUER    (1) o Assistente de verdade na barra da trilha  -> segue em `trilha_assist_v1`
--   QUER    (2) salvar o curriculo geral ao exportar        -> `resume_save_on_export_v1`  (NOVA)
--   NAO QUER(3) importados sumirem da aba Curriculos        -> `imported_source_home_v1`   (NOVA, fica OFF)
--   NAO QUER(4) o botao "Importar CV em PDF" sumir          -> deixou de ser flag (ver abaixo)
--   NAO QUER(5) o card "Fonte importada" em Dados           -> `imported_source_home_v1`   (NOVA, fica OFF)
--
-- O ponto (4) NAO virou flag: a porta de import passou a depender apenas do
-- kill-switch `cv_import_entry_disabled`, que ja existia. O fundador quer
-- import pelas DUAS portas (aba Curriculos e conversa da trilha), entao nao ha
-- estado em que a porta se aposente sozinha -- e flag que nunca vai virar e
-- ruido. A regressao esta travada por teste em
-- `test/features/profile/library_import_entry_test.dart`.
--
-- ANINHAMENTO: as duas flags novas sao filhas de `trilha_assist_v1` -- mas o
-- aninhamento vive no DART (`isGeneralResumeSaveEnabledForUser` e
-- `isImportedSourceHomeEnabledForUser`), nao aqui. Ligar uma filha com a mae
-- desligada NAO tem efeito. Isso e proposital: nao depender de disciplina
-- operacional de quem abre a tabela no painel.
--
-- MOTIVACAO MEDIDA para a (2), em producao em 20/08/2026:
--   select source, count(*) from saved_resumes group by source;
--     imported 756 | manual 555 | adapted 8 | general 0
-- ZERO. Desde sempre. O app gera o PDF do curriculo, abre o share sheet, e nao
-- guarda copia nenhuma -- a pessoa monta o curriculo no Stage e no dia seguinte
-- nao tem curriculo no Stage. A persistencia estava presa em `trilha_assist_v1`,
-- que nunca ligou.
--
-- MOTIVACAO MEDIDA para manter a (3) OFF, mesma data:
--   756 CVs importados, de 696 pessoas, 47 delas com mais de um arquivo.
-- Ligar a (3) sem a (5) -- ou vice-versa -- deixaria essas 696 pessoas sem
-- NENHUMA tela que alcance o proprio CV importado. Por isso as duas metades
-- moram na MESMA flag: meia mudanca aqui tem consequencia real.
--
-- Esta migration NAO LIGA NADA. As duas linhas nascem inertes (false, 0). Ela
-- so torna a decisao de 20/08 reversivel por banco, sem publicar build.
--
-- ON CONFLICT preserva decisao operacional preexistente (idempotente).

BEGIN;

INSERT INTO public.app_feature_flags (
  feature_key,
  enabled,
  rollout_pct,
  description
)
VALUES
  (
    'resume_save_on_export_v1',
    false,
    0,
    'ANINHADA em trilha_assist_v1 (aninhamento no Dart, nao no banco). '
    'Persiste o curriculo geral em saved_resumes source=general ao exportar. '
    'OFF = exporta e nao guarda copia (comportamento historico; producao tinha '
    'ZERO linhas general em 20/08/2026).'
  ),
  (
    'imported_source_home_v1',
    false,
    0,
    'ANINHADA em trilha_assist_v1 (aninhamento no Dart, nao no banco). '
    'Move o CV importado da aba Curriculos para o card Fonte importada em '
    'Perfil -> Dados. OFF POR DECISAO DO FUNDADOR em 20/08/2026: os importados '
    'ficam na aba Curriculos. Ligar afeta 696 pessoas com CV importado.'
  )
ON CONFLICT (feature_key) DO NOTHING;

COMMIT;
