// ────────────────────────────────────────────────────────────────────────────
// Schema JSON do "resume" — compartilhado entre adapt-resume-to-job (que
// retorna `{changes, resume}`) e parse-cv (que retorna apenas `{resume}`).
//
// Mantém estrutura ÚNICA do CV pra que parse-cv emita JSON consumível direto
// por buildInputResume() em adapt-resume-to-job, e ResumeData no Flutter.
// Mudar formato aqui = mudar em todos os consumidores. NÃO MUDAR sem
// atualizar adapt-resume-to-job, parse-cv-vision (F3), e adapted_resume.dart.
// ────────────────────────────────────────────────────────────────────────────

/**
 * Properties do objeto `resume`. Pode ser embutido como sub-schema em
 * outras funções (ex: adapt-resume-to-job adiciona o array `changes` ao
 * lado).
 */
export const RESUME_SCHEMA_PROPERTIES = {
  fullName: { type: 'string' },
  email: { type: 'string' },
  phone: { type: 'string' },
  linkedin: { type: 'string' },
  location: { type: 'string' },
  language: { type: 'string' },
  summary: { type: 'string' },
  skills: { type: 'array', items: { type: 'string' } },
  experiences: {
    type: 'array',
    items: {
      type: 'object',
      additionalProperties: false,
      required: ['role', 'company', 'period', 'description', 'location'],
      properties: {
        role: { type: 'string' },
        company: { type: 'string' },
        period: { type: 'string' },
        description: { type: 'string' },
        location: { type: 'string' },
      },
    },
  },
  education: {
    type: 'array',
    items: {
      type: 'object',
      additionalProperties: false,
      required: ['degree', 'institution', 'period', 'details', 'location'],
      properties: {
        degree: { type: 'string' },
        institution: { type: 'string' },
        period: { type: 'string' },
        details: { type: 'string' },
        location: { type: 'string' },
      },
    },
  },
  achievements: { type: 'array', items: { type: 'string' } },
  interests: { type: 'array', items: { type: 'string' } },
  /// Certificações / cursos extracurriculares. Cada item é uma string
  /// auto-contida (ex: "Modelagem Financeira - Wall Street Prep - 2025").
  /// Renderizado no template como seção dedicada "Certificações" dentro
  /// das habilidades. Mantido separado de `achievements` porque conquistas
  /// são valoradas pelo recrutador de forma diferente (premiações,
  /// projetos pessoais).
  certifications: { type: 'array', items: { type: 'string' } },
} as const

export const RESUME_REQUIRED_FIELDS = [
  'fullName',
  'email',
  'phone',
  'linkedin',
  'location',
  'language',
  'summary',
  'skills',
  'experiences',
  'education',
  'achievements',
  'interests',
  'certifications',
] as const

/**
 * Schema completo para o endpoint parse-cv (input: raw_text, output:
 * apenas o objeto `resume` estruturado). Strict JSON schema para
 * response_format do OpenAI.
 */
export const PARSE_CV_JSON_SCHEMA = {
  name: 'parsed_cv',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['resume'],
    properties: {
      resume: {
        type: 'object',
        additionalProperties: false,
        required: [...RESUME_REQUIRED_FIELDS],
        properties: RESUME_SCHEMA_PROPERTIES,
      },
    },
  },
} as const
