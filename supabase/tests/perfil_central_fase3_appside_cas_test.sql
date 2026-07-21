-- Gate 3.0H (app-side) — CAS de escalar (cas_write_personal_field_v1) e de
-- campo de item (cas_write_item_field_v1). Roda depois do combined (schema mock
-- + migrations). Chamado como superuser com request.jwt.claims setando auth.uid.

-- H-SCALAR — applied quando o observado bate; stale quando diverge; compostos.
DO $h$
DECLARE u uuid := '000000ca-0000-0000-0000-0000000000c1'; r text;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"'||u||'"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, summary, first_name, last_name, location_city, location_state)
    VALUES (u, 'resumo antigo', 'Ana', 'Silva', 'São Paulo', 'SP');

  -- summary: applied (expected == vivo)
  r := public.cas_write_personal_field_v1(u, 'summary', 'resumo antigo', 'resumo novo', NULL, NULL);
  IF r <> 'applied' OR (SELECT summary FROM public.profile_personal WHERE user_id=u) <> 'resumo novo' THEN
    RAISE EXCEPTION 'H-SCALAR: summary applied falhou (%)', r; END IF;

  -- summary: stale (expected != vivo) → não grava, manual vence
  r := public.cas_write_personal_field_v1(u, 'summary', 'valor ERRADO', 'nao deveria', NULL, NULL);
  IF r <> 'stale' OR (SELECT summary FROM public.profile_personal WHERE user_id=u) <> 'resumo novo' THEN
    RAISE EXCEPTION 'H-SCALAR: summary stale falhou (%)', r; END IF;

  -- name COMPOSTO: expected = "Ana Silva" (reconstruído) → split em first/last
  r := public.cas_write_personal_field_v1(u, 'name', 'Ana Silva', 'Bruno Costa', NULL, NULL);
  IF r <> 'applied'
     OR (SELECT first_name FROM public.profile_personal WHERE user_id=u) <> 'Bruno'
     OR (SELECT last_name FROM public.profile_personal WHERE user_id=u) <> 'Costa' THEN
    RAISE EXCEPTION 'H-SCALAR: name composto falhou (%)', r; END IF;

  -- city COMPOSTO: expected = "São Paulo, SP" (display) → "Rio|RJ" split
  r := public.cas_write_personal_field_v1(u, 'city', 'São Paulo, SP', 'Rio|RJ', NULL, NULL);
  IF r <> 'applied'
     OR (SELECT location_city FROM public.profile_personal WHERE user_id=u) <> 'Rio'
     OR (SELECT location_state FROM public.profile_personal WHERE user_id=u) <> 'RJ' THEN
    RAISE EXCEPTION 'H-SCALAR: city composto falhou (%)', r; END IF;

  RAISE NOTICE 'H-SCALAR OK: personal CAS applied/stale + name/city compostos';
END $h$;

-- H-ITEM — applied/stale por ref_id; institution limpa institution_id; semester int.
DO $h$
DECLARE u uuid := '000000ca-0000-0000-0000-0000000000c2';
  eid uuid; edid uuid; cid uuid; r text;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"'||u||'"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'X');  -- protegido
  INSERT INTO public.profile_experiences(user_id, title, company, start_date, end_date)
    VALUES (u, 'Dev', 'Acme', DATE '2020-01-01', DATE '2021-01-01') RETURNING id INTO eid;
  INSERT INTO public.profile_education(user_id, institution, institution_id, current_semester)
    VALUES (u, 'USP', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 6) RETURNING id INTO edid;
  INSERT INTO public.profile_certifications(user_id, name, issuer)
    VALUES (u, 'AWS', 'Amazon') RETURNING id INTO cid;

  -- experience.title applied
  r := public.cas_write_item_field_v1(u, 'experience', eid, 'title', 'Dev', 'Senior Dev');
  IF r <> 'applied' OR (SELECT title FROM public.profile_experiences WHERE id=eid) <> 'Senior Dev' THEN
    RAISE EXCEPTION 'H-ITEM: experience.title applied falhou (%)', r; END IF;

  -- experience.title stale (expected 'Dev', mas vivo agora 'Senior Dev')
  r := public.cas_write_item_field_v1(u, 'experience', eid, 'title', 'Dev', 'Zzz');
  IF r <> 'stale' OR (SELECT title FROM public.profile_experiences WHERE id=eid) <> 'Senior Dev' THEN
    RAISE EXCEPTION 'H-ITEM: experience.title stale falhou (%)', r; END IF;

  -- education.semester applied (expected '6' → int 8)
  r := public.cas_write_item_field_v1(u, 'education', edid, 'semester', '6', '8');
  IF r <> 'applied' OR (SELECT current_semester FROM public.profile_education WHERE id=edid) <> 8 THEN
    RAISE EXCEPTION 'H-ITEM: education.semester falhou (%)', r; END IF;

  -- education.institution applied → limpa institution_id
  r := public.cas_write_item_field_v1(u, 'education', edid, 'institution', 'USP', 'Unicamp');
  IF r <> 'applied'
     OR (SELECT institution FROM public.profile_education WHERE id=edid) <> 'Unicamp'
     OR (SELECT institution_id FROM public.profile_education WHERE id=edid) IS NOT NULL THEN
    RAISE EXCEPTION 'H-ITEM: education.institution (limpa id) falhou (%)', r; END IF;

  -- certification.name applied
  r := public.cas_write_item_field_v1(u, 'certification', cid, 'name', 'AWS', 'AWS SAA');
  IF r <> 'applied' OR (SELECT name FROM public.profile_certifications WHERE id=cid) <> 'AWS SAA' THEN
    RAISE EXCEPTION 'H-ITEM: certification.name falhou (%)', r; END IF;

  -- bullet.text applied + stale (posse via a experiência pai)
  DECLARE bid uuid;
  BEGIN
    INSERT INTO public.profile_bullets(experience_id, text, order_index)
      VALUES (eid, 'bullet velho', 0) RETURNING id INTO bid;
    r := public.cas_write_item_field_v1(u, 'bullet', bid, 'text', 'bullet velho', 'bullet novo');
    IF r <> 'applied' OR (SELECT text FROM public.profile_bullets WHERE id=bid) <> 'bullet novo' THEN
      RAISE EXCEPTION 'H-ITEM: bullet.text applied falhou (%)', r; END IF;
    r := public.cas_write_item_field_v1(u, 'bullet', bid, 'text', 'bullet velho', 'x');
    IF r <> 'stale' OR (SELECT text FROM public.profile_bullets WHERE id=bid) <> 'bullet novo' THEN
      RAISE EXCEPTION 'H-ITEM: bullet.text stale falhou (%)', r; END IF;
  END;

  -- posse: item de OUTRO usuário → item_not_found (RAISE), não grava
  BEGIN
    PERFORM public.cas_write_item_field_v1(u, 'experience',
      '000000ca-0000-0000-0000-0000000000ff', 'title', 'x', 'y');
    RAISE EXCEPTION 'H-ITEM: deveria ter falhado em item inexistente';
  EXCEPTION WHEN sqlstate 'P0002' THEN NULL; END;

  RAISE NOTICE 'H-ITEM OK: item-field CAS applied/stale; institution limpa id; semester int; posse';
END $h$;

SELECT 'APPSIDE_CAS_SQL_TESTS_OK' AS result;
