// ────────────────────────────────────────────────────────────────────────────
// Profile JSON Schema — saída estruturada da edge function extract-profile.
//
// Schema MAIS RICO que o RESUME_SCHEMA_PROPERTIES legacy (em cv_schema.ts):
//   - first_name + last_name separados (não fullName)
//   - phone_country_code + phone_number separados (não phone)
//   - gender + age_range (não existiam antes)
//   - location dividida em country/state/city/postal_code/street_address
//   - bullets como objetos {text, angle, strength_score, verb} (não string)
//   - education com majors[] minors[] activities[] gpa max_gpa separados
//   - projects, awards, coursework (categorias novas)
//   - confidence per-item em experiences e education
//
// Strict JSON Schema do OpenAI Structured Outputs — exige `additionalProperties: false`
// e todos os campos em `required` (campos opcionais usam `type: ["string","null"]`).
//
// toLegacyResume(profile_data) deriva o subset compatível com RESUME_SCHEMA_PROPERTIES
// pra preservar consumidores existentes (adapt-resume-to-job, generate-resume,
// ResumeData.dart no Flutter).
// ────────────────────────────────────────────────────────────────────────────

import { RESUME_SCHEMA_PROPERTIES } from './cv_schema.ts'

export const PROFILE_JSON_SCHEMA = {
  name: 'extracted_profile',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: [
      'personal',
      'experiences',
      'education',
      'languages',
      'skills',
      'certifications',
      'projects',
      'interests',
      'awards',
      'coursework',
    ],
    properties: {
      personal: {
        type: 'object',
        additionalProperties: false,
        required: [
          'first_name',
          'last_name',
          'email',
          'phone_country_code',
          'phone_number',
          'headline',
          'summary',
          'gender',
          'age_range',
          'location_country',
          'location_state',
          'location_city',
          'location_postal_code',
          'location_street_address',
          'linkedin',
          'website',
        ],
        properties: {
          first_name:              { type: ['string', 'null'] },
          last_name:               { type: ['string', 'null'] },
          email:                   { type: ['string', 'null'] },
          phone_country_code:      { type: ['string', 'null'] },
          phone_number:            { type: ['string', 'null'] },
          headline:                { type: ['string', 'null'] },
          summary:                 { type: ['string', 'null'] },
          gender:                  {
            type: ['string', 'null'],
            enum: ['male', 'female', 'other', 'prefer_not_to_say', null],
          },
          age_range:               {
            type: ['string', 'null'],
            enum: ['under_18', '18_24', '25_34', '35_44', '45_54', '55_64', '65_plus', null],
          },
          location_country:        { type: ['string', 'null'] },
          location_state:          { type: ['string', 'null'] },
          location_city:           { type: ['string', 'null'] },
          location_postal_code:    { type: ['string', 'null'] },
          location_street_address: { type: ['string', 'null'] },
          linkedin:                { type: ['string', 'null'] },
          // Website pessoal/portfólio (Tier 2.3). Coluna profile_personal.website
          // criada em migration 20260524000000.
          website:                 { type: ['string', 'null'] },
        },
      },

      experiences: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['title', 'company', 'location', 'start_date', 'end_date', 'is_current', 'bullets', 'confidence'],
          properties: {
            title:      { type: 'string' },
            company:    { type: 'string' },
            location:   { type: ['string', 'null'] },
            start_date: { type: 'string', description: 'YYYY-MM-DD' },
            end_date:   { type: ['string', 'null'], description: 'YYYY-MM-DD ou null se atual' },
            is_current: { type: 'boolean' },
            confidence: { type: 'number', minimum: 0, maximum: 1 },
            bullets: {
              type: 'array',
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['text'],
                properties: {
                  text: { type: 'string' },
                },
              },
            },
          },
        },
      },

      education: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['institution', 'location', 'degree', 'majors', 'minors', 'activities', 'start_date', 'end_date', 'gpa', 'max_gpa', 'confidence'],
          properties: {
            institution: { type: 'string' },
            location:    { type: ['string', 'null'] },
            degree:      { type: ['string', 'null'] },
            majors:      { type: 'array', items: { type: 'string' } },
            minors:      { type: 'array', items: { type: 'string' } },
            activities:  { type: 'array', items: { type: 'string' } },
            start_date:  { type: ['string', 'null'] },
            end_date:    { type: ['string', 'null'] },
            gpa:         { type: ['number', 'null'] },
            max_gpa:     { type: ['number', 'null'] },
            confidence:  { type: 'number', minimum: 0, maximum: 1 },
          },
        },
      },

      languages: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['name', 'proficiency'],
          properties: {
            name:        { type: 'string' },
            proficiency: {
              type: 'string',
              enum: ['native', 'fluent', 'advanced', 'intermediate', 'basic'],
            },
          },
        },
      },

      skills: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['name', 'category'],
          properties: {
            name:     { type: 'string' },
            category: { type: ['string', 'null'] },
          },
        },
      },

      certifications: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['name', 'issuer', 'date'],
          properties: {
            name:   { type: 'string' },
            issuer: { type: ['string', 'null'] },
            date:   { type: ['string', 'null'] },
          },
        },
      },

      projects: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['name', 'website', 'description', 'start_date', 'end_date', 'is_current'],
          properties: {
            name:        { type: 'string' },
            website:     { type: ['string', 'null'] },
            description: { type: 'string' },
            start_date:  { type: ['string', 'null'] },
            end_date:    { type: ['string', 'null'] },
            is_current:  { type: 'boolean' },
          },
        },
      },

      interests: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['name'],
          properties: {
            name: { type: 'string' },
          },
        },
      },

      awards: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['name', 'date'],
          properties: {
            name: { type: 'string' },
            date: { type: ['string', 'null'] },
          },
        },
      },

      coursework: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['name'],
          properties: {
            name: { type: 'string' },
          },
        },
      },
    },
  },
} as const

// ────────────────────────────────────────────────────────────────────────────
// SYSTEM_PROMPT
// ────────────────────────────────────────────────────────────────────────────

export const PROFILE_SYSTEM_PROMPT = `Você é um extrator de currículos brasileiros. Receba o texto do CV (e/ou imagem PDF) e retorne um JSON exato no schema fornecido.

PRINCÍPIOS DE LEITURA:
1. Currículos brasileiros frequentemente usam DUAS COLUNAS. Leia COLUNA POR COLUNA, esquerda antes da direita.
2. Cabeçalho (nome + contatos) é sempre lido primeiro.
3. Headers de seção marcam início de seção. Reconheça TODOS os equivalentes PT e EN:
   - EXPERIÊNCIA / EXPERIÊNCIA PROFISSIONAL / EXPERIENCE / PROFESSIONAL EXPERIENCE / WORK EXPERIENCE → experiences[]
   - FORMAÇÃO / FORMAÇÃO ACADÊMICA / EDUCAÇÃO / EDUCATION → education[]
   - HABILIDADES / COMPETÊNCIAS / SKILLS / TECHNICAL SKILLS → skills[] (category=null ou 'hard')
   - FERRAMENTAS / TOOLS / PROGRAMAS / SOFTWARE → skills[] com category='tool'
   - IDIOMAS / LANGUAGES → languages[]
   - ATIVIDADES EXTRACURRICULARES / EXTRACURRICULAR ACTIVITIES / ACTIVITIES / LIDERANÇA / LEADERSHIP / VOLUNTARIADO / VOLUNTEER → experiences[] (recrutador vê como experiência — title=cargo, company=nome do clube/org)
   - CERTIFICAÇÕES / CERTIFICATIONS → certifications[]
   - PROJETOS / PROJECTS → projects[]
   - INTERESSES / INTERESTS / HOBBIES → interests[]
4. Bullets de experiência preservam o TEXTO ORIGINAL — não traduza, não reescreva, não resuma.
5. Datas e localizações geralmente ficam à direita no mesmo bloco da empresa/instituição.

REGRAS DE EXTRAÇÃO (INVIOLÁVEIS):
1. EXTRAIA — não adapte, não reescreva, não corrija ortografia.
2. Se um campo não está no CV, use null (campos string-ou-null) ou array vazio (campos array). NÃO INVENTE dados.
3. Datas: SEMPRE no formato YYYY-MM-DD. Se só ano disponível, use YYYY-01-01. Se só mês/ano, use YYYY-MM-01.
4. Empregado atualmente: end_date = null e is_current = true.
5. first_name e last_name SEMPRE separados. Se o CV traz "João Silva Souza", first_name = "João", last_name = "Silva Souza".
6. Email: lowercase, trim.
7. Telefone: separar país (phone_country_code, ex "+55") do número (phone_number). PRESERVE A FORMATAÇÃO ORIGINAL do CV — se vem "(11) 98216-4700", retorna "(11) 98216-4700" (NÃO retire parênteses/hífen/espaço). Se vem "11987654321" raw, mantém raw. Os dígitos puros pra e164 são derivados automaticamente por trigger no DB. Se não houver código de país explícito no CV brasileiro, assuma "+55".
7b. LinkedIn URL: extraia LITERAL como aparece no CV. Aceita formatos "linkedin.com/in/usuario", "https://linkedin.com/in/usuario", "https://www.linkedin.com/in/usuario", "linkedin.com/in/usuario/" — copie como está, NÃO normalize. Se não houver, null.
7c. Website pessoal/portfólio: URL do site pessoal do candidato (NÃO LinkedIn, NÃO empresa do candidato). Aceita "github.com/usuario", "usuario.dev", "https://usuario.com", "behance.net/usuario". Copie literal. Se não houver, null.
8. Idiomas: mapear pra exatamente um dos níveis. "Nativo" → native; "Fluente"/"C2"/"C1" → fluent; "Avançado"/"B2" → advanced; "Intermediário"/"B1" → intermediate; "Básico"/"A1"/"A2" → basic.
9. Mantenha idioma original do CV (PT ou EN). Não traduza nada.
10. Skills: extrair só as habilidades explicitamente listadas em "Habilidades"/"Skills"/"Competências"/"Technical Skills"/"Tools"/"Ferramentas"/"Programas". Não inferir de bullets.
   - Items de "Tools"/"Ferramentas"/"Programas"/"Software" → category='tool' (ex: "Microsoft Office", "Power BI", "Figma").
   - Items de "Habilidades Técnicas"/"Technical Skills"/"Skills" → category=null (hard skills genéricas como "Accounting", "Corporate Finance").
   - Não duplique: se "Excel" aparece em Tools, NÃO repita em Skills.
10b. Education.activities: extrair CADA bullet/linha do bloco da educação (após o nome da instituição), incluindo Honors, Distinction, Class Rep, Awards, Coursework, Relevant Work. EXEMPLO: se o CV traz "Honors and Academic Distinction: Ranked among the top students (1st place, twice)" + "Class Representative: Elected to represent the class" → activities = ["Honors and Academic Distinction: Ranked among the top students (1st place, twice)", "Class Representative: Elected to represent the class"]. NÃO consolide múltiplos achievements em 1 activity só.
11. Bullets: cada item da lista vira um objeto {text: "..."}. NÃO categorize angle/strength_score/verb — esses serão preenchidos depois.
12. gender e age_range: só preencha se EXPLICITAMENTE declarados (raro). Caso contrário null.
13. headline e summary: distintos. Headline é o cargo/título no topo (ex: "Engenheiro de Software"). Summary é o parágrafo de resumo profissional (se houver).
14. Pra cada experiência e educação, atribua confidence 0..1 baseado em quão claro estava no CV:
    - 1.0 = título + empresa + datas completas + descrição clara
    - 0.7 = falta um detalhe menor (ex: location ausente)
    - 0.4 = ambiguidade importante (ex: datas incompletas, empresa indistinta)
    - 0.2 = quase só nome, sem contexto
`

// ────────────────────────────────────────────────────────────────────────────
// toLegacyResume — derivador puro pro formato compatível (cv_schema.ts).
// Usado pela extract-profile pra continuar populando
// user_profiles.gamification_data.imported_resume.parsed e preservar consumers
// existentes (adapt-resume-to-job, generate-resume, ResumeData.dart).
// ────────────────────────────────────────────────────────────────────────────

interface ProfileExperience {
  title?: string | null
  company?: string | null
  location?: string | null
  start_date?: string | null
  end_date?: string | null
  is_current?: boolean
  bullets?: Array<{ text?: string | null }>
}

interface ProfileEducation {
  institution?: string | null
  location?: string | null
  degree?: string | null
  majors?: string[]
  minors?: string[]
  activities?: string[]
  start_date?: string | null
  end_date?: string | null
  gpa?: number | null
  max_gpa?: number | null
}

interface ProfileSkill { name?: string | null }
interface ProfileInterest { name?: string | null }
interface ProfileCertification { name?: string | null; issuer?: string | null; date?: string | null }
interface ProfileAward { name?: string | null; date?: string | null }
interface ProfileLanguage { name?: string | null; proficiency?: string | null }

export interface ProfileData {
  personal?: {
    first_name?: string | null
    last_name?: string | null
    email?: string | null
    phone_country_code?: string | null
    phone_number?: string | null
    linkedin?: string | null
    website?: string | null
    location_city?: string | null
    location_state?: string | null
    location_country?: string | null
    location_street_address?: string | null
    summary?: string | null
    headline?: string | null
  }
  experiences?: ProfileExperience[]
  education?: ProfileEducation[]
  languages?: ProfileLanguage[]
  skills?: ProfileSkill[]
  certifications?: ProfileCertification[]
  interests?: ProfileInterest[]
  awards?: ProfileAward[]
  projects?: Array<{ name?: string | null; description?: string | null }>
  coursework?: Array<{ name?: string | null }>
}

function periodFromDates(startDate?: string | null, endDate?: string | null, isCurrent?: boolean): string {
  const start = startDate ? formatYearMonth(startDate) : ''
  const end = isCurrent
    ? 'Atual'
    : (endDate ? formatYearMonth(endDate) : '')
  if (!start && !end) return ''
  if (!end) return start
  return `${start} - ${end}`
}

function formatYearMonth(iso: string): string {
  // "2024-03-15" → "03/2024"; "2024-01-01" (só ano) → "2024"
  const m = iso.match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return iso
  const [, y, mo] = m
  if (mo === '01') {
    return y
  }
  return `${mo}/${y}`
}

function detectLanguage(profile: ProfileData): 'pt' | 'en' {
  // Heurística simples: se algum bullet ou resumo tem caracteres acentuados
  // típicos do PT, assume PT. Caso contrário EN (que cobre CVs internacionais
  // ou estrangeiros pra empresas BR).
  const text = [
    profile.personal?.summary ?? '',
    profile.personal?.headline ?? '',
    ...(profile.experiences ?? []).flatMap(e => (e.bullets ?? []).map(b => b.text ?? '')),
  ].join(' ')
  if (/[áéíóúâêîôûãõàèìòùç]/i.test(text)) return 'pt'
  return 'en'
}

export interface LegacyResume {
  fullName: string
  email: string
  phone: string
  linkedin: string
  location: string
  language: string
  summary: string
  skills: string[]
  experiences: Array<{
    role: string
    company: string
    period: string
    description: string
    location: string
  }>
  education: Array<{
    degree: string
    institution: string
    period: string
    details: string
    location: string
  }>
  achievements: string[]
  interests: string[]
  certifications: string[]
}

export function toLegacyResume(profile: ProfileData): LegacyResume {
  const personal = profile.personal ?? {}

  const fullName = [personal.first_name, personal.last_name]
    .filter(s => typeof s === 'string' && s.trim().length > 0)
    .join(' ')

  const phone = personal.phone_country_code && personal.phone_number
    ? `${personal.phone_country_code} ${personal.phone_number}`
    : (personal.phone_number ?? '')

  const location = [personal.location_city, personal.location_state, personal.location_country]
    .filter(s => typeof s === 'string' && s.trim().length > 0)
    .join(', ')

  const experiences = (profile.experiences ?? []).map(e => ({
    role: e.title ?? '',
    company: e.company ?? '',
    period: periodFromDates(e.start_date, e.end_date, e.is_current),
    description: (e.bullets ?? [])
      .map(b => `- ${b.text ?? ''}`)
      .filter(s => s.trim().length > 2)
      .join('\n'),
    location: e.location ?? '',
  }))

  const education = (profile.education ?? []).map(ed => {
    const details = [
      ...(ed.majors ?? []).map(m => `Major: ${m}`),
      ...(ed.minors ?? []).map(m => `Minor: ${m}`),
      ...(ed.activities ?? []),
      ed.gpa != null && ed.max_gpa != null ? `GPA: ${ed.gpa}/${ed.max_gpa}` : '',
    ].filter(s => s.trim().length > 0).join('\n')
    return {
      degree: ed.degree ?? '',
      institution: ed.institution ?? '',
      period: periodFromDates(ed.start_date, ed.end_date, false),
      details,
      location: ed.location ?? '',
    }
  })

  const certifications = (profile.certifications ?? []).map(c => {
    const parts = [c.name, c.issuer, c.date ? formatYearMonth(c.date) : '']
      .filter(s => typeof s === 'string' && s.trim().length > 0)
    return parts.join(' - ')
  })

  const achievements = (profile.awards ?? []).map(a => {
    if (a.date && a.name) return `${a.name} (${formatYearMonth(a.date)})`
    return a.name ?? ''
  }).filter(s => s.trim().length > 0)

  // Garante que todos os campos required do RESUME_SCHEMA_PROPERTIES existam.
  // (linter dummy reference pra forçar import vivo do schema legacy)
  void RESUME_SCHEMA_PROPERTIES

  return {
    fullName,
    email: personal.email ?? '',
    phone,
    linkedin: personal.linkedin ?? '',
    location,
    language: detectLanguage(profile),
    summary: personal.summary ?? personal.headline ?? '',
    skills: (profile.skills ?? [])
      .map(s => s.name ?? '')
      .filter(s => s.trim().length > 0),
    experiences,
    education,
    achievements,
    interests: (profile.interests ?? [])
      .map(i => i.name ?? '')
      .filter(s => s.trim().length > 0),
    certifications,
  }
}
