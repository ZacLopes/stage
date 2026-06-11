-- Fase 1 — BRIDGES (plano-mãe A2/A3): convertem escrita das builds antigas
-- (2.0.x/2.1.x, que seguem togglando swipe_actions.applied e criando
-- campaigns) para o modelo novo, em tempo real. Nascem aqui e morrem JUNTAS
-- na revogação futura (critério diferido: builds antigas <5% dos eventos
-- semanais por 2 semanas E zero escritas via pontes na janela).
--
-- bridge_activity = observabilidade exigida pelo critério de revogação.

CREATE TABLE public.bridge_activity (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  bridge text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.bridge_activity ENABLE ROW LEVEL SECURITY;
-- Sem policies: deny-all a clients (só service_role/triggers escrevem/leem).
CREATE INDEX bridge_activity_bridge_idx ON public.bridge_activity (bridge, occurred_at);

-- ── BRIDGE 1 — remover quando build antiga < limiar ─────────────────────
-- swipe_actions.applied → applications. No caminho normal roda na sessão
-- JWT do usuário (actor 'user'); no caminho service-role/Studio o actor é
-- 'system' (a matriz permite system→withdrawn exatamente pra isso).
CREATE FUNCTION public._bridge_swipe_applied() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.applied = true AND COALESCE(OLD.applied, false) = false THEN
    INSERT INTO applications (user_id, job_id, type, status, application_method, created_at)
    SELECT NEW.user_id, NEW.job_id, 'external_confirmed', 'submitted',
           COALESCE(j.application_method, 'url'), COALESCE(NEW.applied_at, now())
    FROM jobs j WHERE j.id = NEW.job_id
    ON CONFLICT (user_id, job_id) WHERE job_id IS NOT NULL DO NOTHING;
    INSERT INTO bridge_activity (bridge) VALUES ('swipe_applied');
  ELSIF NEW.applied = false AND COALESCE(OLD.applied, false) = true THEN
    -- Só desfaz se a application ainda está intocada (submitted) — não
    -- clobbera estado movido por admin/ops.
    UPDATE applications SET status = 'withdrawn'
    WHERE user_id = NEW.user_id AND job_id = NEW.job_id
      AND type = 'external_confirmed' AND status = 'submitted';
    INSERT INTO bridge_activity (bridge) VALUES ('swipe_applied_undo');
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_bridge_swipe_applied
  AFTER INSERT OR UPDATE OF applied ON public.swipe_actions
  FOR EACH ROW EXECUTE FUNCTION public._bridge_swipe_applied();

-- ── BRIDGE 2 — remover quando build antiga < limiar ─────────────────────
-- campaigns (criada em todo onboarding das builds antigas — 387/7d em
-- 10/06) → profile_personal.onboarding_completed_at. INSERT mínimo é
-- seguro (NOT NULLs têm default — verificado em plan mode); uma falha aqui
-- abortaria o INSERT de campaigns = onboarding quebrado, por isso o assert
-- dedicado no script de testes.
CREATE FUNCTION public._bridge_campaign_onboarding() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO profile_personal (user_id, onboarding_completed_at)
  VALUES (NEW.user_id, NEW.created_at)
  ON CONFLICT (user_id) DO UPDATE
    SET onboarding_completed_at =
        COALESCE(profile_personal.onboarding_completed_at,
                 EXCLUDED.onboarding_completed_at);
  INSERT INTO bridge_activity (bridge) VALUES ('campaign_onboarding');
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_bridge_campaign_onboarding AFTER INSERT ON public.campaigns
  FOR EACH ROW EXECUTE FUNCTION public._bridge_campaign_onboarding();
