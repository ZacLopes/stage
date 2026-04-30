-- 1. Create tables
CREATE TABLE public.companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  logo_url TEXT,
  description TEXT,
  website TEXT,
  industry TEXT,
  size TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES public.companies(id) NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  requirements TEXT[],
  benefits TEXT[],
  location_city TEXT,
  location_state TEXT,
  salary_min INTEGER,
  salary_max INTEGER,
  work_model TEXT NOT NULL CHECK (work_model IN ('presencial', 'hibrido', 'remoto')),
  job_type TEXT NOT NULL CHECK (job_type IN ('estagio', 'trainee', 'clt_junior', 'temporario')),
  area TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  published_at TIMESTAMPTZ DEFAULT now(),
  deadline TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.swipe_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  job_id UUID REFERENCES public.jobs(id) NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('liked', 'rejected')),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, job_id)
);

CREATE TABLE public.user_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  areas TEXT[],
  locations TEXT[],
  work_models TEXT[],
  job_types TEXT[],
  min_salary INTEGER,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Setup RLS Policies
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.swipe_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

-- Companies: readable by authenticated users
CREATE POLICY "Companies are viewable by authenticated users."
ON public.companies FOR SELECT
TO authenticated
USING (true);

-- Jobs: readable by authenticated users
CREATE POLICY "Jobs are viewable by authenticated users."
ON public.jobs FOR SELECT
TO authenticated
USING (true);

-- Swipe Actions: Users can manage their own swips
CREATE POLICY "Users can insert their own swipe actions."
ON public.swipe_actions FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own swipe actions."
ON public.swipe_actions FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own swipe actions."
ON public.swipe_actions FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own swipe actions."
ON public.swipe_actions FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- User Preferences: Users can manage their own preferences
CREATE POLICY "Users can insert their own preferences."
ON public.user_preferences FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own preferences."
ON public.user_preferences FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own preferences."
ON public.user_preferences FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

-- 3. Seed Data
-- We capture the generated IDs of the companies to reference them in the jobs table
DO $$
DECLARE
  company_1_id UUID := gen_random_uuid();
  company_2_id UUID := gen_random_uuid();
  company_3_id UUID := gen_random_uuid();
  company_4_id UUID := gen_random_uuid();
  company_5_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO public.companies (id, name, logo_url, description) VALUES
  (company_1_id, 'Nubank', 'https://logo.clearbit.com/nubank.com.br', 'O Nubank nasceu para devolver às pessoas o controle sobre sua vida financeira. Somos uma das maiores plataformas digitais de serviços financeiros do mundo.'),
  (company_2_id, 'Ambev', 'https://logo.clearbit.com/ambev.com.br', 'Nós sonhamos em unir as pessoas por um mundo melhor. Para a Ambev, o consumidor é nosso patrão e servimos a ele todos os dias.'),
  (company_3_id, 'iFood', 'https://logo.clearbit.com/ifood.com.br', 'O iFood é uma empresa brasileira de tecnologia, sendo a maior foodtech da América Latina, atuando fortemente em delivery.'),
  (company_4_id, 'Itaú Unibanco', 'https://logo.clearbit.com/itau.com.br', 'Nós somos o Itaú Unibanco. Feito de futuro. O maior banco privado do Brasil e da América Latina focando na melhor experiência do cliente.'),
  (company_5_id, 'Mercado Livre', 'https://logo.clearbit.com/mercadolivre.com.br', 'O Mercado Livre é o maior site de comércio da América Latina e estamos transformando o digital commerce na região.');

  INSERT INTO public.jobs (company_id, title, description, requirements, benefits, location_city, location_state, salary_min, salary_max, work_model, job_type, area, published_at, deadline) VALUES
  (
    company_1_id, 
    'Estágio em Marketing Digital', 
    'Buscamos estagiário(a) para atuar na equipe de Growth Marketing, apoiando campanhas de aquisição e retenção. Você terá a oportunidade de trabalhar lado a lado com especialistas em marketing focado em dados e alta performance, impactando milhões de clientes.',
    ARRAY['Cursando Marketing, Publicidade, Administração ou áreas correlatas', 'A partir do 4º semestre', 'Conhecimento em Google Analytics e Meta Ads', 'Perfil analítico e criativo'],
    ARRAY['VT', 'VR (R$ 35/dia)', 'Gympass', 'Seguro de vida', 'Auxílio home office'],
    'São Paulo', 'SP', 220000, 220000, 'hibrido', 'estagio', 'Marketing', now() - interval '2 days', null
  ),
  (
    company_2_id, 
    'Programa Trainee 2026', 
    'O Programa Trainee Ambev é uma oportunidade para recém-formados que querem liderar a transformação de uma das maiores empresas do Brasil. Se você é apaixonado por grandes desafios e busca desenvolvimento acelerado, este é o seu lugar.',
    ARRAY['Formação entre dez/2024 e dez/2026 em qualquer curso', 'Disponibilidade para mudança de estado', 'Inglês intermediário'],
    ARRAY['PLR', 'Plano de saúde', 'Previdência privada', 'Carro corporativo após efetivação', 'Auxílio farmácia'],
    'São Paulo', 'SP', 850000, 850000, 'presencial', 'trainee', 'Geral', now() - interval '5 days', now() + interval '14 days'
  ),
  (
    company_3_id, 
    'Estágio em Engenharia de Dados', 
    'Faça parte do time de Data Engineering do iFood e ajude a processar milhões de eventos por dia. O estagiário atuará com as tecnologias mais recentes do mercado ajudando a construir pipelines robustos.',
    ARRAY['Cursando Ciência da Computação, Engenharia ou áreas correlatas', 'Noções de Python e SQL básicos', 'Interesse em big data e cloud', 'Disponibilidade para estagiar 6 horas/dia'],
    ARRAY['VR/VA (R$ 40/dia)', 'Gympass', 'Auxílio home office mensal', 'Day off no mês de aniversário', 'Aulas de idiomas'],
    'Nacional', 'BR', 280000, 280000, 'remoto', 'estagio', 'Tecnologia', now(), null
  ),
  (
    company_4_id, 
    'Estágio em Finanças Corporativas', 
    'Atue no time de FP&A do maior banco da América Latina, apoiando análises financeiras e projeções. O estágio proporciona uma visão estratégica de negócios e contato com alta liderança.',
    ARRAY['Cursando Administração, Economia, Engenharia ou Contabilidade', 'Excel avançado e conhecimento básico em VBA/PowerBI é um diferencial', 'A partir do 5º semestre'],
    ARRAY['VT', 'VR + VA', 'Plano de Saúde e Odontológico', 'Totalpass', 'Bolsa auxílio para idiomas'],
    'São Paulo', 'SP', 240000, 240000, 'hibrido', 'estagio', 'Finanças', now() - interval '3 days', null
  ),
  (
    company_5_id, 
    'Estágio em UX/UI Design', 
    'Venha criar experiências para mais de 100 milhões de usuários na América Latina. O estagiário atuará no time de Design de Produto, colaborando com Product Managers e Engenheiros em squads ágeis.',
    ARRAY['Cursando Design, Comunicação Visual ou áreas correlatas', 'Portfolio online no Behance, Dribbble ou Figma (obrigatório apresentar link)', 'Conhecimento básico em Design System', 'Facilidade de comunicação e trabalho em equipe'],
    ARRAY['VT e Van intermunicipal fretada', 'VR (R$ 42/dia)', 'Gympass', 'Desconto em compras no MELI e frete grátis ME', 'Aulas de idiomas online'],
    'São Paulo', 'SP', 260000, 260000, 'hibrido', 'estagio', 'Design', now() - interval '7 days', null
  );
END $$;
