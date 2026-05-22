-- Migration: profile_* RLS policies
--
-- 4 policies (SELECT/INSERT/UPDATE/DELETE) por tabela, expandidas
-- EXPLICITAMENTE (sem placeholder/loop). Política padrão: auth.uid() =
-- user_id pras tabelas com FK direta de user, e EXISTS via parent pras
-- tabelas filhas (bullets, education_majors/minors/activities).
--
-- DELIBERADAMENTE EXCLUÍDA: profile_extraction_logs. RLS habilitada na
-- migration anterior (000009) sem policies = só service_role acessa.
--
-- Naming: users_<op>_<table>. Compactos e descritivos.

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- profile_personal (1:1)
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_personal ON public.profile_personal
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_personal ON public.profile_personal
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_personal ON public.profile_personal
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_personal ON public.profile_personal
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_experiences
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_experiences ON public.profile_experiences
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_experiences ON public.profile_experiences
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_experiences ON public.profile_experiences
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_experiences ON public.profile_experiences
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- profile_bullets — acesso via parent (profile_experiences)
CREATE POLICY users_select_profile_bullets ON public.profile_bullets
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_experiences pe
            WHERE pe.id = profile_bullets.experience_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_insert_profile_bullets ON public.profile_bullets
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_experiences pe
            WHERE pe.id = profile_bullets.experience_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_update_profile_bullets ON public.profile_bullets
  FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_experiences pe
            WHERE pe.id = profile_bullets.experience_id AND pe.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_experiences pe
            WHERE pe.id = profile_bullets.experience_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_delete_profile_bullets ON public.profile_bullets
  FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_experiences pe
            WHERE pe.id = profile_bullets.experience_id AND pe.user_id = auth.uid())
  );

-- ────────────────────────────────────────────────────────────────────
-- profile_education
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_education ON public.profile_education
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_education ON public.profile_education
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_education ON public.profile_education
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_education ON public.profile_education
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- profile_education_majors — acesso via parent
CREATE POLICY users_select_profile_education_majors ON public.profile_education_majors
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_majors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_insert_profile_education_majors ON public.profile_education_majors
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_majors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_update_profile_education_majors ON public.profile_education_majors
  FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_majors.education_id AND pe.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_majors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_delete_profile_education_majors ON public.profile_education_majors
  FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_majors.education_id AND pe.user_id = auth.uid())
  );

-- profile_education_minors — acesso via parent
CREATE POLICY users_select_profile_education_minors ON public.profile_education_minors
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_minors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_insert_profile_education_minors ON public.profile_education_minors
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_minors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_update_profile_education_minors ON public.profile_education_minors
  FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_minors.education_id AND pe.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_minors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_delete_profile_education_minors ON public.profile_education_minors
  FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_minors.education_id AND pe.user_id = auth.uid())
  );

-- profile_education_activities — acesso via parent
CREATE POLICY users_select_profile_education_activities ON public.profile_education_activities
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_activities.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_insert_profile_education_activities ON public.profile_education_activities
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_activities.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_update_profile_education_activities ON public.profile_education_activities
  FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_activities.education_id AND pe.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_activities.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_delete_profile_education_activities ON public.profile_education_activities
  FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_activities.education_id AND pe.user_id = auth.uid())
  );

-- ────────────────────────────────────────────────────────────────────
-- profile_languages
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_languages ON public.profile_languages
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_languages ON public.profile_languages
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_languages ON public.profile_languages
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_languages ON public.profile_languages
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_skills
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_skills ON public.profile_skills
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_skills ON public.profile_skills
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_skills ON public.profile_skills
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_skills ON public.profile_skills
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_certifications
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_certifications ON public.profile_certifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_certifications ON public.profile_certifications
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_certifications ON public.profile_certifications
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_certifications ON public.profile_certifications
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_projects
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_projects ON public.profile_projects
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_projects ON public.profile_projects
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_projects ON public.profile_projects
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_projects ON public.profile_projects
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_interests
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_interests ON public.profile_interests
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_interests ON public.profile_interests
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_interests ON public.profile_interests
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_interests ON public.profile_interests
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_awards
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_awards ON public.profile_awards
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_awards ON public.profile_awards
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_awards ON public.profile_awards
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_awards ON public.profile_awards
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_coursework
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_coursework ON public.profile_coursework
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_coursework ON public.profile_coursework
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_coursework ON public.profile_coursework
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_coursework ON public.profile_coursework
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_job_preferences (1:1)
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_job_preferences ON public.profile_job_preferences
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_job_preferences ON public.profile_job_preferences
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_job_preferences ON public.profile_job_preferences
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_job_preferences ON public.profile_job_preferences
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_desired_titles
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_desired_titles ON public.profile_desired_titles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_desired_titles ON public.profile_desired_titles
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_desired_titles ON public.profile_desired_titles
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_desired_titles ON public.profile_desired_titles
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_application_countries
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_application_countries ON public.profile_application_countries
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_application_countries ON public.profile_application_countries
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_application_countries ON public.profile_application_countries
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_application_countries ON public.profile_application_countries
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_other_locations
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_other_locations ON public.profile_other_locations
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_other_locations ON public.profile_other_locations
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_other_locations ON public.profile_other_locations
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_other_locations ON public.profile_other_locations
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

COMMIT;
