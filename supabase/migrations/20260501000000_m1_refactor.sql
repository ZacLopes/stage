-- Fase 2: Refatoração do M1 "Quem eu sou" → "Direção"
-- Consolida em 1 fase com 3 etapas; cria raw_responses universal;
-- migra e notifica usuários existentes.

-- ═══════════════════════════════════════════
-- STEP 1: Renomear track_1
-- ═══════════════════════════════════════════
UPDATE tracks
SET title       = 'Direção',
    description = 'Sua direção profissional.'
WHERE id = 'track_1';

-- ═══════════════════════════════════════════
-- STEP 2: Limpar respostas do M1 (reset limpo)
-- ═══════════════════════════════════════════
DELETE FROM user_answers
WHERE question_id IN (
  'M1_1_1_Q1', 'M1_1_1_Q2', 'M1_1_1_Q3', 'M1_1_1_Q4',  -- DISC (removidos)
  'M1_3_1_Q2',  -- área (não pre-seleciona; usuário re-responde)
  'M1_3_1_Q3'   -- visionCards antigo (não traduz para texto livre)
);

-- ═══════════════════════════════════════════
-- STEP 3: Resetar progresso do M1
-- ═══════════════════════════════════════════
DELETE FROM user_progress
WHERE phase_id IN ('t1_p1', 't1_p3');

-- ═══════════════════════════════════════════
-- STEP 4: Remover fase e perguntas DISC (t1_p1)
-- ═══════════════════════════════════════════
DELETE FROM questions WHERE phase_id = 't1_p1';
DELETE FROM phases    WHERE id = 't1_p1';

-- ═══════════════════════════════════════════
-- STEP 5: Renomear e reposicionar t1_p3
-- ═══════════════════════════════════════════
UPDATE phases
SET title       = 'Direção',
    description = 'Área, tipo de vaga e norte profissional.',
    order_index = 1
WHERE id = 't1_p3';

-- ═══════════════════════════════════════════
-- STEP 6: Atualizar Etapa 1.1 — Área de foco
-- (M1_3_1_Q2 permanece, mesmas opções, só confirma tipo)
-- ═══════════════════════════════════════════
-- Sem mudanças: conteúdo e opções estão corretos

-- ═══════════════════════════════════════════
-- STEP 7: Inserir Etapa 1.2 — Tipo de oportunidade
-- ID M1_3_1_Q25 ordena entre M1_3_1_Q2 e M1_3_1_Q3 (order by id ASC)
-- ═══════════════════════════════════════════
INSERT INTO questions (id, phase_id, type, content, options)
VALUES (
  'M1_3_1_Q25',
  't1_p3',
  0,  -- multipleChoice
  'Que tipo de oportunidade você está buscando agora?',
  '["Estágio","Trainee","Primeiro emprego (CLT)","Estágio internacional ou intercâmbio com trabalho","Freelance / projetos pontuais","Ainda explorando"]'
)
ON CONFLICT (id) DO NOTHING;

-- ═══════════════════════════════════════════
-- STEP 8: Atualizar Etapa 1.3 — Norte profissional
-- visionCards → text; novo conteúdo; placeholder no options[0]
-- ═══════════════════════════════════════════
UPDATE questions
SET type    = 3,  -- text
    content = 'Pensando nos próximos 2-3 anos, o que você quer construir profissionalmente?',
    options = '["Ex: quero entrar em uma empresa de tecnologia que valorize desenvolvimento técnico e crescer em produtos digitais..."]'
WHERE id = 'M1_3_1_Q3';

-- ═══════════════════════════════════════════
-- STEP 9: Criar tabela raw_responses (universal M1–M5)
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS raw_responses (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID        NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  phase_id      TEXT        NOT NULL,  -- 'm1.1', 'm1.2', 'm1.3', 'm2.1', etc.
  question      TEXT        NOT NULL,
  answer        TEXT        NOT NULL,
  answer_type   TEXT        NOT NULL
                CHECK (answer_type IN ('single_choice', 'multi_choice', 'free_text')),
  question_order INT        NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE raw_responses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own raw_responses"
  ON raw_responses FOR ALL
  USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_raw_responses_user_phase
  ON raw_responses(user_id, phase_id);

-- ═══════════════════════════════════════════
-- STEP 10: Sinalizar usuários existentes para o banner
-- Usa o campo gamification_data (jsonb) já existente em user_profiles
-- ═══════════════════════════════════════════
UPDATE user_profiles
SET gamification_data = COALESCE(gamification_data, '{}'::jsonb)
                        || '{"show_m1_reset_notice": true}'::jsonb
WHERE created_at < NOW();
