-- Classificação dos aliases de skill: o que é sinônimo de VERDADE.
--
-- Revisão UX 28/07, achado P2-19 — e a decisão do fundador em 01/08 de limpar
-- a taxonomia antes de consertar o sintoma.
--
-- ## O problema
--
-- `skill_aliases` foi construída para ACHAR gente: ela junta tudo que soa
-- parecido, de propósito, e é isso que faz a busca de candidatos do admin
-- funcionar (o gatilho `set_canonical_skill_id` carimba
-- `profile_skills.canonical_skill_id` na escrita). Para RECALL ela está certa.
--
-- O consumidor novo faz outra pergunta, mais exigente: "posso PARAR de
-- oferecer isto, porque a pessoa já tem?". Isso é IDENTIDADE, e a tabela mente
-- nesse uso — "excel avançado" e "excel básico" viram ambos "Excel".
--
-- Errar aqui é INVISÍVEL: o candidato perde uma linha do currículo e nunca
-- fica sabendo. Por isso a permissão de esconder é opt-in, nunca herdada.
--
-- ## As classes
--
--   exact      mesma habilidade, mesmo escopo, mesmo nível → PODE esconder
--   level      carrega nível explícito que se perde no mapa → não esconde
--   compound   contém 2+ habilidades distintas             → não esconde
--   scope      mais amplo ou mais estreito que a canônica   → não esconde
--   wrong      mapeamento contraditório                     → não esconde
--   unclassified  DEFAULT de qualquer linha nova            → não esconde
--
-- ## Método
--
-- 401 linhas classificadas por 7 revisores com rubrica escrita, e TODAS as
-- marcadas `exact` reexaminadas por 3 céticos independentes — só essa classe
-- autoriza o silêncio. 5 foram derrubadas de `exact` na revisão, todas para o
-- lado de esconder demais.
--
-- ## O que esta migration NÃO faz
--
-- Não muda nenhum mapeamento e não apaga nenhuma linha. A busca do admin
-- continua idêntica — de propósito: "limpar" os aliases de scope faria a busca
-- perder alcance, e ninguém ligaria uma coisa na outra.
--
-- ⚠️ ACHADO PARA O FUNDADOR: a canônica "Informática básica" deveria se chamar
-- "Informática". O nome com nível embutido é o que torna 6 aliases estranhos —
-- "informática avançada" carimbado como "básica" é o pior deles. Renomear a
-- canônica é UMA linha e conserta a família inteira; fica de fora daqui porque
-- muda o rótulo que o admin vê na busca.

begin;

alter table public.skill_aliases
  add column if not exists match_kind text not null default 'unclassified';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'skill_aliases_match_kind_check'
  ) then
    alter table public.skill_aliases
      add constraint skill_aliases_match_kind_check
      check (match_kind in ('exact','level','compound','scope','wrong','unclassified'));
  end if;
end $$;

comment on column public.skill_aliases.match_kind is
  'exact = seguro afirmar identidade (pode esconder da folha de extras). '
  'Todo o resto serve para RECALL (busca) e nunca autoriza esconder. '
  'Default unclassified: permissão de silêncio é opt-in.';

-- exact: 269 linhas
update public.skill_aliases set match_kind = 'exact'
where alias_normalized in (
  select a from (values
    ('adaptabilidade'),
    ('adaptação'),
    ('administração'),
    ('adobe illustrator'),
    ('adobe photoshop'),
    ('adobe premiere'),
    ('after effects'),
    ('angular'),
    ('análise de dados'),
    ('apis rest'),
    ('aprendizado rápido'),
    ('aprendizagem rápida'),
    ('atendimento ao cliente'),
    ('atenção aos detalhes'),
    ('autocad'),
    ('automação'),
    ('aws'),
    ('azure'),
    ('banco de dados'),
    ('boa comunicação'),
    ('boa comunicação com a equipe'),
    ('boa comunicação interpessoal'),
    ('boa comunicação verbal'),
    ('boa comunicação verbal e escrita'),
    ('bom relacionamento interpessoal'),
    ('bootstrap'),
    ('c'),
    ('c#'),
    ('c++'),
    ('canva'),
    ('capacidade de adaptação'),
    ('capacidade de aprender rapidamente'),
    ('capacidade de aprendizado rápido'),
    ('capacidade de resolver problemas'),
    ('capacidade de trabalhar em equipe'),
    ('capacidade de trabalho em equipe'),
    ('capcut'),
    ('ci/cd'),
    ('competências de comunicação'),
    ('comprometido'),
    ('comprometimento'),
    ('comunicativa'),
    ('comunicativo'),
    ('comunicação'),
    ('comunicação assertiva'),
    ('comunicação clara'),
    ('comunicação clara e cordial'),
    ('comunicação clara e objetiva'),
    ('comunicação clara e profissional'),
    ('comunicação eficaz'),
    ('comunicação eficaz escrita e verbal'),
    ('comunicação eficiente'),
    ('comunicação interpessoal'),
    ('comunicação oral e escrita'),
    ('comunicação verbal e escrita'),
    ('conhecimento básico em informática'),
    ('conhecimento do pacote office'),
    ('conhecimento em pacote office'),
    ('conhecimento em python'),
    ('conhecimento prático em operação de caixa'),
    ('conhecimentos básicos em informática'),
    ('contabilidade'),
    ('contas a pagar'),
    ('controle de estoque'),
    ('controle financeiro'),
    ('criativa'),
    ('criatividade'),
    ('criativo'),
    ('criação de conteúdo'),
    ('crm'),
    ('css'),
    ('css3'),
    ('dedicação'),
    ('departamento pessoal'),
    ('desenvolvimento web'),
    ('design'),
    ('digitação'),
    ('digitação rápida'),
    ('dinamismo'),
    ('dinâmica'),
    ('dinâmico'),
    ('disciplina'),
    ('django'),
    ('docker'),
    ('edição de vídeo'),
    ('empatia'),
    ('erp'),
    ('escuta ativa'),
    ('etl'),
    ('excel'),
    ('excelente comunicação oral e escrita'),
    ('exel'),
    ('express.js'),
    ('facilidade de adaptação'),
    ('facilidade de aprendizado'),
    ('facilidade de aprendizagem'),
    ('facilidade em aprender'),
    ('facilidade em lidar com pessoas'),
    ('facilidade em trabalhar em equipe'),
    ('facilidade para aprender'),
    ('facilidade para trabalhar em equipe'),
    ('facilidade para trabalho em equipe'),
    ('figma'),
    ('firebase'),
    ('flask'),
    ('flutter'),
    ('foco em resultados'),
    ('fácil adaptação'),
    ('fácil aprendizado'),
    ('gerenciamento de tempo'),
    ('gestão de pessoas'),
    ('gestão de projetos'),
    ('gestão de redes sociais'),
    ('gestão de tempo'),
    ('gestão do tempo'),
    ('gestão documental'),
    ('git'),
    ('google workspace'),
    ('habilidade de comunicação'),
    ('habilidade em powerpoint'),
    ('html'),
    ('html5'),
    ('illustrator'),
    ('informática básica'),
    ('inglês'),
    ('insomnia'),
    ('inteligência artificial'),
    ('inteligência emocional'),
    ('intellij idea'),
    ('java'),
    ('java script'),
    ('javascript'),
    ('jest'),
    ('jira'),
    ('js'),
    ('kanban'),
    ('laravel'),
    ('liderança'),
    ('linux'),
    ('lógica de programação'),
    ('mac os'),
    ('machine learning'),
    ('manutenção de hardware'),
    ('marketing digital'),
    ('matemática financeira'),
    ('maven'),
    ('metodologias ágeis'),
    ('microsoft excel'),
    ('microsoft office'),
    ('microsoft outlook'),
    ('microsoft powerpoint'),
    ('microsoft teams'),
    ('microsoft word'),
    ('miro'),
    ('modelagem financeira'),
    ('mongodb'),
    ('ms excel'),
    ('mysql'),
    ('n8n'),
    ('negociação'),
    ('next.js'),
    ('node js'),
    ('node.js'),
    ('nodejs'),
    ('notion'),
    ('noções de informática'),
    ('obs studio'),
    ('omie'),
    ('operação de caixa'),
    ('oracle'),
    ('oratória'),
    ('organizada'),
    ('organizado'),
    ('organização'),
    ('organização exemplar'),
    ('outlook'),
    ('paciência'),
    ('pacote adobe'),
    ('pacote microsoft office'),
    ('pacote office'),
    ('pacote office completo'),
    ('pensamento criativo'),
    ('pensamento crítico'),
    ('photoshop'),
    ('php'),
    ('planejamento'),
    ('planilhas'),
    ('pontual'),
    ('pontualidade'),
    ('postgres'),
    ('postgresql'),
    ('postman'),
    ('power apps'),
    ('power automate'),
    ('power bi'),
    ('power point'),
    ('powerpoint'),
    ('premiere'),
    ('proativa'),
    ('proatividade'),
    ('proatividade e iniciativa'),
    ('proativo'),
    ('produção de conteúdo'),
    ('programação'),
    ('programação em python'),
    ('programação orientada a objetos (poo)'),
    ('python'),
    ('r'),
    ('raciocínio lógico'),
    ('react'),
    ('react native'),
    ('react.js'),
    ('recepção'),
    ('recrutamento e seleção'),
    ('redes de computadores'),
    ('relacionamento interpessoal'),
    ('resiliência'),
    ('resolução de problemas'),
    ('responsabilidade'),
    ('responsável'),
    ('rest api'),
    ('rest apis'),
    ('revit'),
    ('rotinas administrativas'),
    ('rápido aprendizado'),
    ('salesforce'),
    ('sap'),
    ('scrum'),
    ('segurança da informação'),
    ('selenium'),
    ('servicenow'),
    ('sistemas operacionais windows'),
    ('sketchup'),
    ('social media'),
    ('solidworks'),
    ('solução de problemas'),
    ('spring boot'),
    ('sql'),
    ('storytelling'),
    ('suporte tecnico'),
    ('suporte técnico'),
    ('suporte técnico presencial e remoto'),
    ('tableau'),
    ('tailwind css'),
    ('tailwindcss'),
    ('tasy'),
    ('tomada de decisões'),
    ('totvs'),
    ('trabalho bem em equipe'),
    ('trabalho em equipe'),
    ('trabalho em equipe e colaboração'),
    ('trello'),
    ('typescript'),
    ('valuation'),
    ('vba'),
    ('vendas'),
    ('vercel'),
    ('vite'),
    ('vs code'),
    ('vue.js'),
    ('windows'),
    ('windows 10'),
    ('windows 10/11'),
    ('windows 11'),
    ('word'),
    ('wordpress'),
    ('zabbix'),
    ('ética'),
    ('ótimo relacionamento interpessoal')
  ) as t(a)
);
-- level: 22 linhas
update public.skill_aliases set match_kind = 'level'
where alias_normalized in (
  select a from (values
    ('conhecimento básico em excel'),
    ('conhecimento intermediário em erp'),
    ('domínio do pacote office'),
    ('excel avançado'),
    ('excel básico'),
    ('excel intermediário'),
    ('informática básica e avançada'),
    ('informática intermediária'),
    ('inglês avançado'),
    ('inglês básico'),
    ('inglês intermediário'),
    ('javascript (básico)'),
    ('noções de lógica de programação'),
    ('noções de marketing digital'),
    ('noções de redes'),
    ('noções de segurança da informação'),
    ('pacote office (excel intermediário)'),
    ('pacote office avançado'),
    ('pacote office básico'),
    ('pacote office intermediário'),
    ('python (básico)'),
    ('word intermediário')
  ) as t(a)
);
-- compound: 49 linhas
update public.skill_aliases set match_kind = 'compound'
where alias_normalized in (
  select a from (values
    ('boa comunicação e atendimento ao cliente'),
    ('boa comunicação e atendimento ao público'),
    ('boa comunicação e relacionamento interpessoal'),
    ('boa comunicação e trabalho em equipe'),
    ('capacidade de investigação e resolução de problemas'),
    ('comprometimento com metas e resultados'),
    ('comprometimento com resultados'),
    ('comprometimento e responsabilidade'),
    ('comunicação clara e empática'),
    ('comunicação e oratória'),
    ('comunicação e trabalho em equipe'),
    ('comunicação eficaz e trabalho em equipe'),
    ('disciplina e responsabilidade'),
    ('facilidade de aprendizado e adaptação'),
    ('git e github'),
    ('git/github'),
    ('html & css'),
    ('html e css'),
    ('html/css'),
    ('microsoft office (word, excel e powerpoint)'),
    ('organização e atenção a detalhes'),
    ('organização e atenção aos detalhes'),
    ('organização e comprometimento'),
    ('organização e controle de estoque'),
    ('organização e controle de informações'),
    ('organização e controle de processos'),
    ('organização e cumprimento de prazos'),
    ('organização e disciplina'),
    ('organização e gestão de informações'),
    ('organização e gestão de tarefas'),
    ('organização e planejamento'),
    ('organização e pontualidade'),
    ('organização e proatividade'),
    ('organização e responsabilidade'),
    ('pacote office (excel e word)'),
    ('pacote office (excel, word e powerpoint)'),
    ('pacote office (excel, word, powerpoint)'),
    ('pacote office (word, excel e outlook)'),
    ('pacote office (word, excel e powerpoint)'),
    ('pacote office (word, excel, powerpoint)'),
    ('pacote office (word, excel, powerpoint, outlook)'),
    ('pontualidade e responsabilidade'),
    ('proatividade e aprendizado rápido'),
    ('proatividade e disposição para aprender'),
    ('proatividade e facilidade de aprendizado'),
    ('proatividade e responsabilidade'),
    ('responsabilidade e comprometimento'),
    ('responsabilidade e pontualidade'),
    ('vendas e negociação')
  ) as t(a)
);
-- scope: 60 linhas
update public.skill_aliases set match_kind = 'scope'
where alias_normalized in (
  select a from (values
    ('adobe creative cloud'),
    ('agilidade'),
    ('aprendizado contínuo'),
    ('assistente administrativo'),
    ('atendimento ao público'),
    ('atividades em grupo'),
    ('capacidade de aprendizado contínuo'),
    ('capacidade de aprendizagem'),
    ('competências organizacionais'),
    ('comunicação institucional'),
    ('conhecimento em informática'),
    ('conhecimentos em informática'),
    ('controle de planilhas'),
    ('controle de processos'),
    ('controle documental'),
    ('docker compose'),
    ('emissão de notas fiscais'),
    ('experiência com chatgpt'),
    ('facilidade com atendimento ao público'),
    ('facilidade com ferramentas digitais'),
    ('facilidade com sistemas e tecnologia'),
    ('facilidade com tecnologia'),
    ('facilidade de aprendizagem de novas funções'),
    ('faturamento'),
    ('flexibilidade'),
    ('flexível'),
    ('foco no cliente'),
    ('gestão administrativa'),
    ('gestão de estoque'),
    ('gestão de prazos'),
    ('github'),
    ('habilidades em informática'),
    ('identidade visual'),
    ('informática'),
    ('inventário'),
    ('marketing'),
    ('microsoft 365'),
    ('microsoft office (excel)'),
    ('microsoft sql server'),
    ('modelagem de banco de dados'),
    ('modelagem de dados'),
    ('montagem e manutenção de computadores'),
    ('organização administrativa'),
    ('organização de documentos'),
    ('organização de processos'),
    ('pandas'),
    ('persuasão'),
    ('pl/sql'),
    ('redes'),
    ('redes sociais'),
    ('relacionamento com clientes'),
    ('solid'),
    ('sql server'),
    ('suporte administrativo'),
    ('versatilidade'),
    ('versionamento de código'),
    ('videomaker'),
    ('vontade de aprender'),
    ('web design'),
    ('web designer')
  ) as t(a)
);
-- wrong: 1 linhas
update public.skill_aliases set match_kind = 'wrong'
where alias_normalized in (
  select a from (values
    ('informática avançada')
  ) as t(a)
);

-- Índice parcial: o consumidor de identidade só lê as `exact`.
create index if not exists skill_aliases_exact_idx
  on public.skill_aliases (alias_normalized)
  where match_kind = 'exact';

commit;
