-- Migration: baseline (tabelas legacy criadas antes do versionamento)
--
-- HISTÓRICO: as 9 tabelas abaixo foram criadas manualmente no UI do Supabase
-- antes do versionamento via migrations começar. Isso causa falha ao criar
-- Database Branches (branch nasce vazio; migrations posteriores que dependem
-- dessas tabelas falham).
--
-- Esta migration é IDEMPOTENTE — usa CREATE TABLE IF NOT EXISTS, DROP POLICY
-- IF EXISTS, DO blocks com EXCEPTION. Em prod, é no-op (tudo já existe).
-- Em branch novo, popula com schema idêntico a prod (snapshot 2026-05-21).
--
-- Tabelas legacy cobertas:
--   tracks, phases, questions, user_profiles, user_progress,
--   user_answers, saved_resumes, ai_generation_logs, security_audit_log

BEGIN;

-- ═══ 1. CREATE TABLE ═══

CREATE TABLE IF NOT EXISTS "public"."ai_generation_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "generation_type" "text" NOT NULL,
    "tokens_used" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "ai_generation_logs_generation_type_check" CHECK (("generation_type" = ANY (ARRAY['profile'::"text", 'resume'::"text", 'interview'::"text", 'bullets'::"text", 'resume_evaluation'::"text", 'resume_refine'::"text", 'match_analysis'::"text", 'resume_adaptation'::"text", 'skill_extraction'::"text", 'profile_extraction'::"text"])))
);

CREATE TABLE IF NOT EXISTS "public"."phases" (
    "id" "text" NOT NULL,
    "track_id" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "order_index" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

CREATE TABLE IF NOT EXISTS "public"."questions" (
    "id" "text" NOT NULL,
    "phase_id" "text" NOT NULL,
    "type" integer NOT NULL,
    "content" "text" NOT NULL,
    "options" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);

CREATE TABLE IF NOT EXISTS "public"."saved_resumes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "title" "text" NOT NULL,
    "file_path" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text" DEFAULT 'manual'::"text" NOT NULL,
    CONSTRAINT "saved_resumes_source_check" CHECK (("source" = ANY (ARRAY['manual'::"text", 'imported'::"text", 'adapted'::"text"])))
);

CREATE TABLE IF NOT EXISTS "public"."security_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "event_type" "text" NOT NULL,
    "ip_address" "text",
    "user_agent" "text",
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);

CREATE TABLE IF NOT EXISTS "public"."tracks" (
    "id" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "color" bigint NOT NULL,
    "icon_asset" "text" NOT NULL,
    "order_index" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

CREATE TABLE IF NOT EXISTS "public"."user_answers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "question_id" "text" NOT NULL,
    "answer" "text" NOT NULL,
    "answered_at" timestamp with time zone DEFAULT "now"()
);

CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text" NOT NULL,
    "course" "text",
    "semester" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "gamification_data" "jsonb" DEFAULT '{}'::"jsonb",
    "age" integer,
    "ai_consent" boolean DEFAULT false,
    "ai_consent_timestamp" timestamp with time zone,
    "phone" "text"
);

CREATE TABLE IF NOT EXISTS "public"."user_progress" (
    "user_id" "uuid" NOT NULL,
    "phase_id" "text" NOT NULL,
    "completed" boolean DEFAULT false,
    "completed_at" timestamp with time zone
);

-- ═══ 2. ALTER TABLE (constraints, FKs) ═══

DO $$
BEGIN
  ALTER TABLE "public"."ai_generation_logs" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."phases" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."questions" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."saved_resumes" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."security_audit_log" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."tracks" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."user_answers" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."user_profiles" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."user_progress" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."ai_generation_logs"
      ADD CONSTRAINT "ai_generation_logs_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."phases"
      ADD CONSTRAINT "phases_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."questions"
      ADD CONSTRAINT "questions_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."saved_resumes"
      ADD CONSTRAINT "saved_resumes_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."security_audit_log"
      ADD CONSTRAINT "security_audit_log_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."tracks"
      ADD CONSTRAINT "tracks_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_answers"
      ADD CONSTRAINT "user_answers_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_answers"
      ADD CONSTRAINT "user_answers_user_question_uniq" UNIQUE ("user_id", "question_id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_profiles"
      ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_progress"
      ADD CONSTRAINT "user_progress_pkey" PRIMARY KEY ("user_id", "phase_id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."ai_generation_logs"
      ADD CONSTRAINT "ai_generation_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."phases"
      ADD CONSTRAINT "phases_track_id_fkey" FOREIGN KEY ("track_id") REFERENCES "public"."tracks"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."questions"
      ADD CONSTRAINT "questions_phase_id_fkey" FOREIGN KEY ("phase_id") REFERENCES "public"."phases"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."saved_resumes"
      ADD CONSTRAINT "saved_resumes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."security_audit_log"
      ADD CONSTRAINT "security_audit_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE SET NULL;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_answers"
      ADD CONSTRAINT "user_answers_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "public"."questions"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_answers"
      ADD CONSTRAINT "user_answers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_profiles"
      ADD CONSTRAINT "user_profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_progress"
      ADD CONSTRAINT "user_progress_phase_id_fkey" FOREIGN KEY ("phase_id") REFERENCES "public"."phases"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_progress"
      ADD CONSTRAINT "user_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

-- ═══ 3. ENABLE ROW LEVEL SECURITY ═══

ALTER TABLE "public"."ai_generation_logs" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."phases" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."questions" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."saved_resumes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."security_audit_log" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tracks" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_answers" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_progress" ENABLE ROW LEVEL SECURITY;

-- ═══ 4. CREATE INDEX ═══

CREATE INDEX IF NOT EXISTS "idx_ai_logs_user_type_date" ON "public"."ai_generation_logs" USING "btree" ("user_id", "generation_type", "created_at");

CREATE INDEX IF NOT EXISTS "idx_answers_question" ON "public"."user_answers" USING "btree" ("question_id");

CREATE INDEX IF NOT EXISTS "idx_answers_user" ON "public"."user_answers" USING "btree" ("user_id");

CREATE INDEX IF NOT EXISTS "idx_audit_event_date" ON "public"."security_audit_log" USING "btree" ("event_type", "created_at");

CREATE INDEX IF NOT EXISTS "idx_audit_user_date" ON "public"."security_audit_log" USING "btree" ("user_id", "created_at");

CREATE INDEX IF NOT EXISTS "idx_phases_track" ON "public"."phases" USING "btree" ("track_id");

CREATE INDEX IF NOT EXISTS "idx_progress_user" ON "public"."user_progress" USING "btree" ("user_id");

CREATE INDEX IF NOT EXISTS "idx_questions_phase" ON "public"."questions" USING "btree" ("phase_id");

-- ═══ 5. CREATE POLICY (DROP IF EXISTS + CREATE) ═══

DROP POLICY IF EXISTS "Allow authenticated users to insert questions" ON "public"."questions";
CREATE POLICY "Allow authenticated users to insert questions" ON "public"."questions" FOR INSERT TO "authenticated" WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated users to update questions" ON "public"."questions";
CREATE POLICY "Allow authenticated users to update questions" ON "public"."questions" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Anyone can view phases" ON "public"."phases";
CREATE POLICY "Anyone can view phases" ON "public"."phases" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Anyone can view questions" ON "public"."questions";
CREATE POLICY "Anyone can view questions" ON "public"."questions" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Anyone can view tracks" ON "public"."tracks";
CREATE POLICY "Anyone can view tracks" ON "public"."tracks" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public can view phases" ON "public"."phases";
CREATE POLICY "Public can view phases" ON "public"."phases" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public can view questions" ON "public"."questions";
CREATE POLICY "Public can view questions" ON "public"."questions" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public can view tracks" ON "public"."tracks";
CREATE POLICY "Public can view tracks" ON "public"."tracks" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service can insert generation logs" ON "public"."ai_generation_logs";
CREATE POLICY "Service can insert generation logs" ON "public"."ai_generation_logs" FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Service role can view audit logs" ON "public"."security_audit_log";
CREATE POLICY "Service role can view audit logs" ON "public"."security_audit_log" FOR SELECT USING (false);

DROP POLICY IF EXISTS "Users can delete own answers" ON "public"."user_answers";
CREATE POLICY "Users can delete own answers" ON "public"."user_answers" FOR DELETE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can delete own profile" ON "public"."user_profiles";
CREATE POLICY "Users can delete own profile" ON "public"."user_profiles" FOR DELETE USING (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Users can delete own progress" ON "public"."user_progress";
CREATE POLICY "Users can delete own progress" ON "public"."user_progress" FOR DELETE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can delete their own resumes" ON "public"."saved_resumes";
CREATE POLICY "Users can delete their own resumes" ON "public"."saved_resumes" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

DROP POLICY IF EXISTS "Users can insert own answers" ON "public"."user_answers";
CREATE POLICY "Users can insert own answers" ON "public"."user_answers" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can insert own profile" ON "public"."user_profiles";
CREATE POLICY "Users can insert own profile" ON "public"."user_profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Users can insert own progress" ON "public"."user_progress";
CREATE POLICY "Users can insert own progress" ON "public"."user_progress" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can insert their own resumes" ON "public"."saved_resumes";
CREATE POLICY "Users can insert their own resumes" ON "public"."saved_resumes" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

DROP POLICY IF EXISTS "Users can update own answers" ON "public"."user_answers";
CREATE POLICY "Users can update own answers" ON "public"."user_answers" FOR UPDATE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can update own profile" ON "public"."user_profiles";
CREATE POLICY "Users can update own profile" ON "public"."user_profiles" FOR UPDATE USING (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Users can update own progress" ON "public"."user_progress";
CREATE POLICY "Users can update own progress" ON "public"."user_progress" FOR UPDATE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can view own answers" ON "public"."user_answers";
CREATE POLICY "Users can view own answers" ON "public"."user_answers" FOR SELECT USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can view own generation logs" ON "public"."ai_generation_logs";
CREATE POLICY "Users can view own generation logs" ON "public"."ai_generation_logs" FOR SELECT USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can view own profile" ON "public"."user_profiles";
CREATE POLICY "Users can view own profile" ON "public"."user_profiles" FOR SELECT USING (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Users can view own progress" ON "public"."user_progress";
CREATE POLICY "Users can view own progress" ON "public"."user_progress" FOR SELECT USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can view their own resumes" ON "public"."saved_resumes";
CREATE POLICY "Users can view their own resumes" ON "public"."saved_resumes" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

-- ═══ 6. TRIGGERS ═══

DO $$
BEGIN
  CREATE OR REPLACE TRIGGER "notify_new_signup" AFTER INSERT ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/notify-signup', 'POST', '{"Content-type":"application/json"}', '{}', '5000');
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  CREATE OR REPLACE TRIGGER "update_user_profiles_updated_at" BEFORE UPDATE ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

-- ═══ 7. GRANTS ═══

GRANT ALL ON TABLE "public"."ai_generation_logs" TO "anon";
GRANT ALL ON TABLE "public"."ai_generation_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_generation_logs" TO "service_role";

GRANT ALL ON TABLE "public"."phases" TO "anon";
GRANT ALL ON TABLE "public"."phases" TO "authenticated";
GRANT ALL ON TABLE "public"."phases" TO "service_role";

GRANT ALL ON TABLE "public"."questions" TO "anon";
GRANT ALL ON TABLE "public"."questions" TO "authenticated";
GRANT ALL ON TABLE "public"."questions" TO "service_role";

GRANT ALL ON TABLE "public"."saved_resumes" TO "anon";
GRANT ALL ON TABLE "public"."saved_resumes" TO "authenticated";
GRANT ALL ON TABLE "public"."saved_resumes" TO "service_role";

GRANT ALL ON TABLE "public"."security_audit_log" TO "anon";
GRANT ALL ON TABLE "public"."security_audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."security_audit_log" TO "service_role";

GRANT ALL ON TABLE "public"."tracks" TO "anon";
GRANT ALL ON TABLE "public"."tracks" TO "authenticated";
GRANT ALL ON TABLE "public"."tracks" TO "service_role";

GRANT ALL ON TABLE "public"."user_answers" TO "anon";
GRANT ALL ON TABLE "public"."user_answers" TO "authenticated";
GRANT ALL ON TABLE "public"."user_answers" TO "service_role";

GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";

GRANT ALL ON TABLE "public"."user_progress" TO "anon";
GRANT ALL ON TABLE "public"."user_progress" TO "authenticated";
GRANT ALL ON TABLE "public"."user_progress" TO "service_role";


COMMIT;
