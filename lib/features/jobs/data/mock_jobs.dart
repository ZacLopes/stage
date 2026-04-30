import '../models/job.dart';

final List<Job> mockJobs = [
  Job(
    id: '1',
    title: 'Estágio em Marketing Digital',
    companyName: 'Nubank',
    companyLogoUrl: 'https://logo.clearbit.com/nubank.com.br',
    location: 'São Paulo, SP',
    salaryRange: 'R\$ 2.200',
    workModel: 'Híbrido',
    jobType: 'Estágio',
    matchScore: 92,
    description: 'Buscamos estagiário(a) para atuar na equipe de Growth Marketing, apoiando campanhas de aquisição e retenção. Você terá a oportunidade de trabalhar lado a lado com especialistas em marketing focado em dados e alta performance, impactando milhões de clientes.',
    requirements: [
      'Cursando Marketing, Publicidade, Administração ou áreas correlatas',
      'A partir do 4º semestre',
      'Conhecimento em Google Analytics e Meta Ads',
      'Perfil analítico e criativo'
    ],
    benefits: [
      'VT',
      'VR (R\$ 35/dia)',
      'Gympass',
      'Seguro de vida',
      'Auxílio home office'
    ],
    aboutCompany: 'O Nubank nasceu para devolver às pessoas o controle sobre sua vida financeira. Somos uma das maiores plataformas digitais de serviços financeiros do mundo.',
    postedDaysAgo: 'Publicada há 2 dias',
  ),
  Job(
    id: '2',
    title: 'Programa Trainee 2026',
    companyName: 'Ambev',
    companyLogoUrl: 'https://logo.clearbit.com/ambev.com.br',
    location: 'São Paulo, SP',
    salaryRange: 'R\$ 8.500',
    workModel: 'Presencial',
    jobType: 'Trainee',
    matchScore: 78,
    description: 'O Programa Trainee Ambev é uma oportunidade para recém-formados que querem liderar a transformação de uma das maiores empresas do Brasil. Se você é apaixonado por grandes desafios e busca desenvolvimento acelerado, este é o seu lugar.',
    requirements: [
      'Formação entre dez/2024 e dez/2026 em qualquer curso',
      'Disponibilidade para mudança de estado',
      'Inglês intermediário'
    ],
    benefits: [
      'PLR',
      'Plano de saúde',
      'Previdência privada',
      'Carro corporativo após efetivação',
      'Auxílio farmácia'
    ],
    aboutCompany: 'Nós sonhamos em unir as pessoas por um mundo melhor. Para a Ambev, o consumidor é nosso patrão e servimos a ele todos os dias.',
    postedDaysAgo: 'Publicada há 5 dias',
    deadline: 'Inscrições até 15 de abril',
  ),
  Job(
    id: '3',
    title: 'Estágio em Engenharia de Dados',
    companyName: 'iFood',
    companyLogoUrl: 'https://logo.clearbit.com/ifood.com.br',
    location: 'Remoto',
    salaryRange: 'R\$ 2.800',
    workModel: 'Remoto',
    jobType: 'Estágio',
    matchScore: 85,
    description: 'Faça parte do time de Data Engineering do iFood e ajude a processar milhões de eventos por dia. O estagiário atuará com as tecnologias mais recentes do mercado ajudando a construir pipelines robustos.',
    requirements: [
      'Cursando Ciência da Computação, Engenharia ou áreas correlatas',
      'Noções de Python e SQL básicos',
      'Interesse em big data e cloud',
      'Disponibilidade para estagiar 6 horas/dia'
    ],
    benefits: [
      'VR/VA (R\$ 40/dia)',
      'Gympass',
      'Auxílio home office mensal',
      'Day off no mês de aniversário',
      'Aulas de idiomas'
    ],
    aboutCompany: 'O iFood é uma empresa brasileira de tecnologia, sendo a maior foodtech da América Latina, atuando fortemente em delivery.',
    postedDaysAgo: 'Publicada hoje',
  ),
  Job(
    id: '4',
    title: 'Estágio em Finanças Corporativas',
    companyName: 'Itaú Unibanco',
    companyLogoUrl: 'https://logo.clearbit.com/itau.com.br',
    location: 'São Paulo, SP',
    salaryRange: 'R\$ 2.400',
    workModel: 'Híbrido',
    jobType: 'Estágio',
    matchScore: 71,
    description: 'Atue no time de FP&A do maior banco da América Latina, apoiando análises financeiras e projeções. O estágio proporciona uma visão estratégica de negócios e contato com alta liderança.',
    requirements: [
      'Cursando Administração, Economia, Engenharia ou Contabilidade',
      'Excel avançado e conhecimento básico em VBA/PowerBI é um diferencial',
      'A partir do 5º semestre'
    ],
    benefits: [
      'VT',
      'VR + VA',
      'Plano de Saúde e Odontológico',
      'Totalpass',
      'Bolsa auxílio para idiomas'
    ],
    aboutCompany: 'Nós somos o Itaú Unibanco. Feito de futuro. O maior banco privado do Brasil e da América Latina focando na melhor experiência do cliente.',
    postedDaysAgo: 'Publicada há 3 dias',
  ),
  Job(
    id: '5',
    title: 'Estágio em UX/UI Design',
    companyName: 'Mercado Livre',
    companyLogoUrl: 'https://logo.clearbit.com/mercadolivre.com.br',
    location: 'São Paulo, SP',
    salaryRange: 'R\$ 2.600',
    workModel: 'Híbrido',
    jobType: 'Estágio',
    matchScore: 88,
    description: 'Venha criar experiências para mais de 100 milhões de usuários na América Latina. O estagiário atuará no time de Design de Produto, colaborando com Product Managers e Engenheiros em squads ágeis.',
    requirements: [
      'Cursando Design, Comunicação Visual ou áreas correlatas',
      'Portfolio online no Behance, Dribbble ou Figma (obrigatório apresentar link)',
      'Conhecimento básico em Design System',
      'Facilidade de comunicação e trabalho em equipe'
    ],
    benefits: [
      'VT e Van intermunicipal fretada',
      'VR (R\$ 42/dia)',
      'Gympass',
      'Desconto em compras no MELI e frete grátis ME',
      'Aulas de idiomas online'
    ],
    aboutCompany: 'O Mercado Livre é o maior site de comércio da América Latina e estamos transformando o digital commerce na região.',
    postedDaysAgo: 'Publicada há 1 semana',
  )
];
