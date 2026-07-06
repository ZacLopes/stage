// CSV v2 do export de shortlist (Fase 7 Onda 2) — lógica PURA e testável
// (o index.ts chama serve() no top-level e não pode ser importado por deno test).
// O que é impuro (signed URL do CV, IO) fica no index.ts; aqui só o mapeamento
// perfil+item → células, com sanitização anti-fórmula nos campos do candidato.

import { sanitizeCsvValue } from '../_shared/admin.ts';
import type { CandidateProfile } from './scoring.ts';

export interface ScoreBreakdownEntry {
  label?: string;
  points?: number;
  detail?: string;
}

export interface ExportItem {
  score: number;
  scoreBreakdown?: ScoreBreakdownEntry[] | null;
}

export const EXPORT_HEADERS = [
  'nome',
  'email',
  'telefone',
  'cidade',
  'estado',
  'curso',
  'instituicao',
  'semestre',
  'previsao_formatura',
  'nivel',
  'modalidade',
  'tipo_vaga',
  'cargo_desejado',
  'idiomas',
  'skills',
  'linkedin',
  'disponibilidade',
  'resumo',
  'score',
  'motivo',
  'curriculo_link',
];

const WORK_MODE_PT: Record<string, string> = {
  remoto: 'Remoto',
  remote: 'Remoto',
  hibrido: 'Híbrido',
  hybrid: 'Híbrido',
  presencial: 'Presencial',
  in_person: 'Presencial',
};

const JOB_TYPE_PT: Record<string, string> = {
  estagio: 'Estágio',
  internship: 'Estágio',
  trainee: 'Trainee',
  clt_junior: 'CLT júnior',
  full_time: 'CLT júnior',
  temporario: 'Temporário',
  contract: 'Temporário',
  part_time: 'Meio período',
};

const AVAILABILITY_PT: Record<string, string> = {
  immediate: 'Imediata',
  within_month: 'Em até 1 mês',
  after_graduation: 'Após me formar',
  flexible: 'Flexível',
};

const EDUCATION_LEVEL_PT: Record<string, string> = {
  college: 'Graduação',
  school: 'Ensino médio',
  technical: 'Técnico',
  other: 'Outro',
};

// Proficiência de idioma → PT. Fallback = valor cru (degrada sem quebrar).
export const LANG_LEVEL_PT: Record<string, string> = {
  native: 'Nativo',
  fluent: 'Fluente',
  advanced: 'Avançado',
  intermediate: 'Intermediário',
  basic: 'Básico',
  beginner: 'Básico',
};

function mapList(values: string[] | undefined, table: Record<string, string>): string {
  return (values ?? []).map((v) => table[v] ?? v).filter(Boolean).join(', ');
}

const SYNTHETIC_EMAIL = /^phone_\d+@stage\.app$/i;

// Conta(s) de teste internas — nunca vão numa lista vendida (CLAUDE.md).
const INTERNAL_EMAILS = new Set<string>([
  'internal-fase0-test@stage.app',
  'phone_5500900000001@stage.app',
]);

export function isSyntheticEmail(email: string): boolean {
  return SYNTHETIC_EMAIL.test((email ?? '').trim());
}

export function isInternalAccount(email: string): boolean {
  return INTERNAL_EMAILS.has((email ?? '').trim().toLowerCase());
}

// "Por que esse candidato": dimensões do breakdown que pontuaram > 0.
export function motivoFromBreakdown(breakdown: ScoreBreakdownEntry[] | null | undefined): string {
  return (breakdown ?? [])
    .filter((b) => (b?.points ?? 0) > 0 && b?.label)
    .map((b) => `${b.label}: ${b.points}`)
    .join('; ');
}

// E-mail sintético (phone_*@stage.app) não é contato real → sai vazio no CSV.
function contactEmail(email: string): string {
  return isSyntheticEmail(email) ? '' : (email ?? '');
}

// Uma linha do CSV (pré-escape). Sanitiza os campos de texto controlados pelo
// candidato; telefone sai como fórmula ="..." intocada (preserva o + do E.164).
export function exportRowCells(
  profile: CandidateProfile,
  item: ExportItem,
  cvUrl: string,
): string[] {
  const s = sanitizeCsvValue;
  return [
    s(profile.name),
    s(contactEmail(profile.email)),
    profile.phone ? `="${profile.phone}"` : '',
    s(profile.city || profile.primaryLocationCity || ''),
    s(profile.state),
    s(profile.course ?? ''),
    s(profile.institution ?? ''),
    profile.semester != null ? String(profile.semester) : '',
    profile.graduationYear != null ? String(profile.graduationYear) : '',
    EDUCATION_LEVEL_PT[profile.educationLevel ?? ''] ?? '',
    mapList(profile.workModes, WORK_MODE_PT),
    mapList(profile.jobTypes, JOB_TYPE_PT),
    s(profile.desiredPosition ?? ''),
    s(profile.languages ?? ''),
    s(profile.skills.join(', ')),
    s(profile.linkedin ?? ''),
    AVAILABILITY_PT[profile.availability ?? ''] ?? '',
    s(profile.summary),
    String(item.score ?? ''),
    s(motivoFromBreakdown(item.scoreBreakdown)),
    cvUrl ?? '',
  ];
}
