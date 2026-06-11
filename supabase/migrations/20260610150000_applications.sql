-- Fase 1 T1.1/T1.2 (plano-mãe C/D1, PLANO-FASE-1.md) — a espinha de dados.
-- applications + application_events com máquina de estados validada por
-- trigger (matriz explícita por actor) e guarda de imutabilidade de colunas.
--
-- Decisões de design (aprovadas 2026-06-10):
--  - enums como text + CHECK (padrão do banco);
--  - unicidade parcial (user_id, job_id): re-candidatura = REABERTURA da row
--    (rejected/withdrawn → submitted), nunca segunda row;
--  - job_id ON DELETE RESTRICT: vaga com candidatura não se deleta, se
--    desativa — scripts de limpeza que deletem jobs passarão a FALHAR, e
--    isso é o comportamento desejado (applications = trilha de auditoria);
--  - histórico em LINHAS (application_events) desde o nascimento;
--  - sem DELETE client-side: withdrawn é o caminho.

CREATE TABLE public.applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  job_id uuid REFERENCES public.jobs(id) ON DELETE RESTRICT,
  type text NOT NULL CHECK (type IN ('stage','external_confirmed','manual')),
  status text NOT NULL DEFAULT 'submitted' CHECK (status IN
    ('submitted','in_review','shortlisted','interview','offer','hired',
     'rejected','withdrawn','expired')),
  application_method text,
  adapted_resume_id uuid REFERENCES public.adapted_resumes(id) ON DELETE SET NULL,
  sla_deadline timestamptz,
  rejection_category text CHECK (rejection_category IS NULL OR rejection_category IN
    ('perfil_distante','requisito_especifico','vaga_preenchida','outro_candidato','outro')),
  notes text,
  external_company text,
  external_title text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT applications_job_or_manual CHECK (job_id IS NOT NULL OR type = 'manual'),
  CONSTRAINT applications_manual_fields CHECK
    (type <> 'manual' OR (external_company IS NOT NULL AND external_title IS NOT NULL))
);

-- Re-candidatura à mesma vaga reabre a row existente — nunca duplica.
CREATE UNIQUE INDEX applications_user_job_uniq
  ON public.applications (user_id, job_id) WHERE job_id IS NOT NULL;
CREATE INDEX applications_user_status_idx ON public.applications (user_id, status);
CREATE INDEX applications_job_idx ON public.applications (job_id);
CREATE INDEX applications_sla_idx ON public.applications (sla_deadline)
  WHERE sla_deadline IS NOT NULL;

CREATE TRIGGER trg_applications_updated_at BEFORE UPDATE ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.application_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
  from_status text,                                -- null = evento de criação
  to_status text NOT NULL,
  actor text NOT NULL CHECK (actor IN ('user','admin','system')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX application_events_app_idx
  ON public.application_events (application_id, created_at);

-- ── Actor da operação corrente: GUC (edges admin, Fase 4) > JWT > system ──
CREATE FUNCTION public._application_actor() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('app.actor', true), ''),
                  CASE WHEN auth.uid() IS NOT NULL THEN 'user' ELSE 'system' END);
$$;

-- ── Matriz de transições (PLANO-FASE-1 T1.1) ────────────────────────────
-- user em manual/external: pode mover entre estados de pipeline INCLUSIVE
-- retrocesso (offer→in_review) — por design, o usuário corrige o próprio
-- tracker; reabertura rejected/withdrawn→submitted.
-- user em stage: só → withdrawn.
-- system: → expired|withdrawn (withdrawn cobre a Bridge 1 no caminho
-- service-role/Studio; no caminho normal o JWT do user da build antiga faz
-- o actor ser 'user').
CREATE FUNCTION public._application_transition_allowed(
  p_actor text, p_type text, p_from text, p_to text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_from = p_to THEN true                                   -- no-op idempotente
    WHEN p_actor = 'system' THEN
         p_to IN ('expired','withdrawn') AND p_from NOT IN ('hired','expired')
    WHEN p_actor = 'admin' THEN
         (p_from NOT IN ('hired','expired')
          AND p_to IN ('in_review','shortlisted','interview','offer','hired',
                       'rejected','withdrawn'))
         OR (p_type = 'stage' AND p_from IN ('rejected','withdrawn')
             AND p_to = 'submitted')
    WHEN p_actor = 'user' AND p_type = 'stage' THEN
         p_from NOT IN ('hired','expired','rejected','withdrawn')
         AND p_to = 'withdrawn'
    WHEN p_actor = 'user' THEN                                     -- manual / external_confirmed
         (p_from IN ('rejected','withdrawn') AND p_to = 'submitted')      -- reabertura
         OR (p_from NOT IN ('hired','expired','rejected','withdrawn')
             AND p_to IN ('in_review','shortlisted','interview','offer','hired',
                          'rejected','withdrawn'))
    ELSE false END;
$$;

-- ── Validação de UPDATE: imutabilidade por actor + máquina de estados ────
-- Roda em TODO update (não só OF status): a RLS de UPDATE own não restringe
-- colunas — sem esta guarda, um user via PostgREST fliparia type stage→manual
-- e se moveria livre até hired (lupa #2 da revisão do arquiteto).
CREATE FUNCTION public._applications_validate_update() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_actor text := public._application_actor();
BEGIN
  IF v_actor = 'user' THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.job_id IS DISTINCT FROM OLD.job_id
       OR NEW.type   IS DISTINCT FROM OLD.type THEN
      RAISE EXCEPTION 'user_id/job_id/type são imutáveis para actor user'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.rejection_category IS DISTINCT FROM OLD.rejection_category
       OR NEW.sla_deadline IS DISTINCT FROM OLD.sla_deadline THEN
      RAISE EXCEPTION 'rejection_category/sla_deadline só podem ser alterados por admin/system'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF OLD.status IS DISTINCT FROM NEW.status
     AND NOT public._application_transition_allowed(v_actor, NEW.type,
                                                    OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'transição % → % não permitida para actor % em type %',
      OLD.status, NEW.status, v_actor, NEW.type
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_applications_validate BEFORE UPDATE ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public._applications_validate_update();

-- ── Histórico em linhas, desde o nascimento ──────────────────────────────
-- SECURITY DEFINER: atravessa a RLS de application_events (client não tem
-- policy de INSERT — só o trigger escreve).
CREATE FUNCTION public._applications_log_event() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO application_events (application_id, from_status, to_status, actor)
    VALUES (NEW.id, NULL, NEW.status, public._application_actor());
  ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO application_events (application_id, from_status, to_status, actor)
    VALUES (NEW.id, OLD.status, NEW.status, public._application_actor());
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_applications_event_insert AFTER INSERT ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public._applications_log_event();
CREATE TRIGGER trg_applications_event_update AFTER UPDATE OF status ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public._applications_log_event();

-- ── RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE public.applications ENABLE ROW LEVEL SECURITY;
CREATE POLICY applications_select_own ON public.applications FOR SELECT
  USING (auth.uid() = user_id);
-- type='stage' fica fora do INSERT client até a Fase 4 (criação 1-toque).
CREATE POLICY applications_insert_own ON public.applications FOR INSERT
  WITH CHECK (auth.uid() = user_id AND type IN ('external_confirmed','manual'));
CREATE POLICY applications_update_own ON public.applications FOR UPDATE
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
-- Sem policy de DELETE: histórico não se apaga.

ALTER TABLE public.application_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY application_events_select_own ON public.application_events FOR SELECT
  USING (EXISTS (SELECT 1 FROM applications a
                 WHERE a.id = application_id AND a.user_id = auth.uid()));
-- Sem policy de INSERT/UPDATE/DELETE client: só o trigger SECURITY DEFINER escreve.

COMMENT ON TABLE public.applications IS
  'Candidaturas com máquina de estados (Fase 1). type=stage|external_confirmed|manual. Transições validadas por trigger contra matriz por actor.';
COMMENT ON COLUMN public.swipe_actions.applied IS
  'DEPRECATED desde Fase 1 (2026-06-10): fonte de verdade é applications. Builds antigas ainda escrevem; a bridge trg_bridge_swipe_applied converte. Remover na revogação futura.';
