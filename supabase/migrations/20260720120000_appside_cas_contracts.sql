-- Gate 3.0H (app-side) — contratos CAS para os writers do assistente que ainda
-- gravavam direto (sem atomicidade server-side). Dois wrappers granted a
-- authenticated, sob o MESMO advisory lock por usuário. Manual recente vence:
-- se o valor vivo divergir do observado (p_expected), retorna 'stale' e NÃO grava.
--
-- Co-deploy (3.0J): estas RPCs precisam existir em prod ANTES do app que as
-- chama. Dependem das migrations 20260714120000/130000 (lock helper + o interno
-- _cas_write_personal_field + _profile_scalar_column).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Escalares de perfil (name/city/phone compostos + summary/headline/linkedin/
--    website/email): expõe a authenticated o helper interno já testado
--    _cas_write_personal_field (que faz o split composto + CAS + guarda de email).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cas_write_personal_field_v1(
  p_user_id uuid, p_field text, p_expected text, p_value text,
  p_expected_country_code text DEFAULT NULL, p_new_country_code text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000';
  END IF;
  -- Delega ao interno (auth revalidada lá; ambos DEFINER do mesmo owner).
  RETURN public._cas_write_personal_field(
    p_user_id, p_field, p_expected, p_value, p_expected_country_code, p_new_country_code);
END $$;
REVOKE ALL ON FUNCTION public.cas_write_personal_field_v1(uuid,text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cas_write_personal_field_v1(uuid,text,text,text,text,text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Campo de item multi-campo (experiência/formação/certificação) por ref_id,
--    com CAS contra o valor observado. Cobre exatamente o que o writer legado
--    fazia: experience(title,company), education(degree,institution[+limpa
--    institution_id],semester[int/limpa]), certification(name,issuer).
--    NÃO seta updated_at (nem toda tabela tem; os gatilhos disparam no UPDATE).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cas_write_item_field_v1(
  p_user_id uuid, p_kind text, p_ref_id uuid, p_field text,
  p_expected text, p_value text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_owner uuid; v_live text; v_val text := btrim(COALESCE(p_value,'')); v_sem int;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000';
  END IF;
  IF p_ref_id IS NULL THEN RAISE EXCEPTION 'ref_id_required' USING ERRCODE='22004'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(p_user_id));

  IF p_kind = 'experience' THEN
    SELECT user_id, CASE p_field WHEN 'title' THEN title WHEN 'company' THEN company END
      INTO v_owner, v_live FROM public.profile_experiences WHERE id = p_ref_id;
    IF v_owner IS NULL OR v_owner <> p_user_id THEN RAISE EXCEPTION 'item_not_found' USING ERRCODE='P0002'; END IF;
    IF p_field NOT IN ('title','company') THEN RAISE EXCEPTION 'invalid_field' USING ERRCODE='22023'; END IF;
    IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(p_expected),'') THEN RETURN 'stale'; END IF;
    IF p_field = 'title' THEN
      UPDATE public.profile_experiences SET title = v_val WHERE id = p_ref_id;
    ELSE
      UPDATE public.profile_experiences SET company = v_val WHERE id = p_ref_id;
    END IF;
    RETURN 'applied';

  ELSIF p_kind = 'education' THEN
    SELECT user_id, CASE p_field
             WHEN 'degree' THEN COALESCE(degree,'')
             WHEN 'institution' THEN institution
             WHEN 'semester' THEN COALESCE(current_semester::text,'') END
      INTO v_owner, v_live FROM public.profile_education WHERE id = p_ref_id;
    IF v_owner IS NULL OR v_owner <> p_user_id THEN RAISE EXCEPTION 'item_not_found' USING ERRCODE='P0002'; END IF;
    IF p_field NOT IN ('degree','institution','semester') THEN RAISE EXCEPTION 'invalid_field' USING ERRCODE='22023'; END IF;
    IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(p_expected),'') THEN RETURN 'stale'; END IF;
    IF p_field = 'degree' THEN
      UPDATE public.profile_education SET degree = NULLIF(v_val,'') WHERE id = p_ref_id;
    ELSIF p_field = 'institution' THEN
      -- trocar o NOME invalida o vínculo canônico (institution_id) — senão o
      -- candidato fica sob a IES errada na busca.
      UPDATE public.profile_education SET institution = v_val, institution_id = NULL WHERE id = p_ref_id;
    ELSE  -- semester: int ou limpa
      v_sem := CASE WHEN v_val = '' THEN NULL
                    ELSE NULLIF(regexp_replace(v_val, '[^0-9]', '', 'g'), '')::int END;
      UPDATE public.profile_education SET current_semester = v_sem WHERE id = p_ref_id;
    END IF;
    RETURN 'applied';

  ELSIF p_kind = 'bullet' THEN
    -- bullet é filho de experiência (sem user_id direto); posse via o pai.
    SELECT e.user_id, b.text INTO v_owner, v_live
      FROM public.profile_bullets b
      JOIN public.profile_experiences e ON e.id = b.experience_id
     WHERE b.id = p_ref_id;
    IF v_owner IS NULL OR v_owner <> p_user_id THEN RAISE EXCEPTION 'item_not_found' USING ERRCODE='P0002'; END IF;
    IF p_field <> 'text' THEN RAISE EXCEPTION 'invalid_field' USING ERRCODE='22023'; END IF;
    IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(p_expected),'') THEN RETURN 'stale'; END IF;
    IF v_val = '' THEN RETURN 'applied'; END IF;  -- legado ignora texto vazio; espelha (no-op)
    UPDATE public.profile_bullets SET text = v_val WHERE id = p_ref_id;
    RETURN 'applied';

  ELSIF p_kind = 'certification' THEN
    SELECT user_id, CASE p_field WHEN 'name' THEN name WHEN 'issuer' THEN COALESCE(issuer,'') END
      INTO v_owner, v_live FROM public.profile_certifications WHERE id = p_ref_id;
    IF v_owner IS NULL OR v_owner <> p_user_id THEN RAISE EXCEPTION 'item_not_found' USING ERRCODE='P0002'; END IF;
    IF p_field NOT IN ('name','issuer') THEN RAISE EXCEPTION 'invalid_field' USING ERRCODE='22023'; END IF;
    IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(p_expected),'') THEN RETURN 'stale'; END IF;
    IF p_field = 'name' THEN
      UPDATE public.profile_certifications SET name = v_val WHERE id = p_ref_id;
    ELSE
      UPDATE public.profile_certifications SET issuer = NULLIF(v_val,'') WHERE id = p_ref_id;
    END IF;
    RETURN 'applied';
  END IF;
  RAISE EXCEPTION 'invalid_kind' USING ERRCODE='22023';
END $$;
REVOKE ALL ON FUNCTION public.cas_write_item_field_v1(uuid,text,uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cas_write_item_field_v1(uuid,text,uuid,text,text,text) TO authenticated;
