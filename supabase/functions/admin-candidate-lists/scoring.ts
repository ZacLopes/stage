// Lógica pura de scoring do auto-rank de shortlist (extraída de index.ts na
// Fase 7 Onda 1 para virar unidade testável — index.ts chama serve() no
// top-level e não pode ser importado por `deno test` sem subir servidor).
// Mesmo padrão do repo: _shared/jobs.ts (inferArea) + jobs.test.ts.
//
// Pesos do auto-rank: Cargo/área 25 · Skills 25 · Localização 15 · Modelo 10 ·
// Tipo 10 · Prontidão 15. Modelo e Tipo pontuam por DEFAULT se o candidato não
// declarou (inflação conhecida — fora do escopo desta onda, ver I.2.3).

import { normalizeText, tokenize } from '../_shared/admin.ts';

export interface CandidateProfile {
  userId: string;
  name: string;
  email: string;
  phone: string;
  city: string;
  // Cidade só em profile_job_preferences.primary_location_city (176 candidatos
  // legacy). Entra no COALESCE de localização (score + CSV) — Fase 7 Onda 1.
  primaryLocationCity: string;
  state: string;
  headline: string;
  summary: string;
  completenessScore: number;
  skills: string[];
  desiredTitles: string[];
  education: string[];
  workModes: string[];
  jobTypes: string[];
  otherLocations: string[];
  likes: number;
  applies: number;
  consentStatus: string;
  createdAt: string;
}

export function text(value: unknown): string {
  return String(value ?? '').trim();
}

function hasTokenOverlap(a: string[], b: string[]): boolean {
  const set = new Set(a);
  return b.some((token) => set.has(token));
}

function normalizeWorkMode(value: string): string {
  switch (value) {
    case 'remote':
      return 'remoto';
    case 'hybrid':
      return 'hibrido';
    case 'in_person':
      return 'presencial';
    default:
      return value;
  }
}

function normalizeJobType(value: string): string {
  switch (value) {
    case 'internship':
      return 'estagio';
    case 'full_time':
      return 'clt_junior';
    case 'contract':
      return 'temporario';
    case 'part_time':
      return 'temporario';
    default:
      return value;
  }
}

// deno-lint-ignore no-explicit-any
export function scoreCandidate(request: any, candidate: CandidateProfile) {
  const breakdown: Array<{ label: string; points: number; detail: string }> = [];
  let score = 0;

  const reqTitleTokens = tokenize(`${request.title ?? ''} ${request.area ?? ''}`);
  const candidateTitleTokens = tokenize([
    ...candidate.desiredTitles,
    candidate.headline,
    candidate.summary,
  ].join(' '));
  const titleMatched = hasTokenOverlap(reqTitleTokens, candidateTitleTokens);
  if (titleMatched) score += 25;
  breakdown.push({
    label: 'Cargo/area',
    points: titleMatched ? 25 : 0,
    detail: titleMatched
      ? 'Cargo desejado ou resumo profissional conversa com a vaga.'
      : 'Nao ha sinal claro de cargo/area desejada para essa vaga.',
  });

  const reqSkillTokens = tokenize([
    request.description,
    ...(Array.isArray(request.requirements) ? request.requirements : []),
  ].join(' '));
  const candidateSkillTokens = tokenize([
    ...candidate.skills,
    candidate.summary,
    candidate.headline,
    ...candidate.education,
  ].join(' '));
  const reqSet = new Set(reqSkillTokens);
  const overlap = Array.from(new Set(candidateSkillTokens)).filter((token) => reqSet.has(token));
  const skillRatio = reqSet.size > 0 ? Math.min(1, overlap.length / Math.min(reqSet.size, 8)) : 0;
  const skillPoints = Math.round(skillRatio * 25);
  score += skillPoints;
  breakdown.push({
    label: 'Skills',
    points: skillPoints,
    detail: overlap.length > 0
      ? `Sobreposicao detectada: ${overlap.slice(0, 5).join(', ')}.`
      : 'Nao houve sobreposicao relevante de skills/requisitos.',
  });

  const requestCity = normalizeText(request.location_city);
  const requestState = normalizeText(request.location_state);
  // COALESCE das cidades do candidato: residência (PP) + primary_location_city
  // (JP) + cidades de interesse. Sem primaryLocationCity, os 176 candidatos com
  // cidade só em JP perdiam os 15 pts de Localização (Fase 7 Onda 1).
  const candidateLocations = [
    candidate.city,
    candidate.state,
    candidate.primaryLocationCity,
    ...candidate.otherLocations,
  ].map(normalizeText).filter(Boolean);
  const locationMatched = normalizeText(request.work_model) === 'remoto' ||
    !requestCity && !requestState ||
    (requestCity && candidateLocations.includes(requestCity)) ||
    (requestState && candidateLocations.includes(requestState));
  if (locationMatched) score += 15;
  breakdown.push({
    label: 'Localizacao',
    points: locationMatched ? 15 : 0,
    detail: locationMatched
      ? 'Localizacao ou remoto parece compativel.'
      : 'Localizacao declarada nao bate com a vaga.',
  });

  const requestWorkModel = normalizeWorkMode(text(request.work_model));
  const candidateWorkModes = candidate.workModes.map(normalizeWorkMode);
  const workMatched = !requestWorkModel || candidateWorkModes.length === 0 ||
    candidateWorkModes.includes(requestWorkModel);
  if (workMatched) score += 10;
  breakdown.push({
    label: 'Modelo',
    points: workMatched ? 10 : 0,
    detail: workMatched
      ? 'Modelo de trabalho compativel.'
      : 'Modelo de trabalho nao declarado como preferido.',
  });

  const requestJobType = normalizeJobType(text(request.job_type));
  const candidateJobTypes = candidate.jobTypes.map(normalizeJobType);
  const typeMatched = !requestJobType || candidateJobTypes.length === 0 ||
    candidateJobTypes.includes(requestJobType);
  if (typeMatched) score += 10;
  breakdown.push({
    label: 'Tipo',
    points: typeMatched ? 10 : 0,
    detail: typeMatched
      ? 'Tipo/nivel de vaga compativel.'
      : 'Tipo de vaga nao bate com a preferencia.',
  });

  let readiness = 0;
  if (candidate.completenessScore >= 60) readiness += 8;
  if (candidate.skills.length >= 3) readiness += 3;
  if (candidate.education.length > 0) readiness += 2;
  if (candidate.likes > 0 || candidate.applies > 0) readiness += 2;
  score += readiness;
  breakdown.push({
    label: 'Prontidao',
    points: readiness,
    detail: 'Pontua perfil completo, skills, formacao e atividade no app.',
  });

  return { score: Math.max(0, Math.min(100, score)), breakdown };
}
