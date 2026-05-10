-- ============================================================
-- FASE 3: Refatoração M2, M3, M4, M5
-- MVP: deleta todos os usuários para início limpo
-- ============================================================

-- 1. Limpar dados de usuários (MVP - recomeço limpo)
DELETE FROM user_answers;
DELETE FROM user_progress;
DELETE FROM raw_responses;
DELETE FROM campaigns;
DELETE FROM target_jobs;
DELETE FROM user_profiles;

-- 2. Renomear fases
UPDATE phases SET title='Cursos', description='Cursos e certificações externas.' WHERE id='t2_p2';
UPDATE phases SET title='Atividades', description='Atividades extracurriculares.' WHERE id='t3_p2';

-- 3. Deletar perguntas cortadas
DELETE FROM questions WHERE id IN (
  'M2_1_1_Q4',                               -- bridge text (cortado)
  'M2_2_1_Q1', 'M2_2_1_Q2', 'M2_2_1_Q3',   -- datas/logística (fundidos no academicForm)
  'M2_3_1_Q3',                               -- miniTextBox atividades (cortado)
  'M4_1_1_Q2',                               -- lista ferramentas específicas (cortado)
  'M4_2_1_Q3',                               -- contexto de uso idioma (cortado)
  'M5_1_1_Q2', 'M5_1_1_Q3', 'M5_1_1_Q4',   -- contatos (fundidos no contactForm)
  'M5_2_1_Q3'                                -- observação final (cortado)
);
DELETE FROM questions WHERE id LIKE 'M4_1_1_Q3%'; -- níveis por ferramenta (gerados dinamicamente)

-- 4. Mover cursos de M3 → M2 (t3_p2 → t2_p2)
UPDATE questions SET phase_id='t2_p2' WHERE id IN ('M3_2_1_Q1', 'M3_2_1_Q2');

-- 5. Mover atividades de M2 → M3 (t2_p3 → t3_p2)
UPDATE questions SET phase_id='t3_p2' WHERE id='M2_3_1_Q2';

-- 6. Mudar tipo das perguntas fundidas para novos enum indices
--    academicForm = 36, toolsCatalog = 37, contactForm = 38
UPDATE questions SET type=36, options='[]' WHERE id='M2_1_1_Q1';
UPDATE questions SET type=37, options='["Pacote Office / Administrativo","Design & Criatividade","Programação & Tech","Dados & Análise","Redes Sociais & Marketing","Gestão de Projetos","Vendas & Negociação","Outros"]' WHERE id='M4_1_1_Q1';
UPDATE questions SET type=38, options='[]' WHERE id='M5_1_1_Q1';
