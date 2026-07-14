// Testes do scoring puro do auto-rank (Fase 7 Onda 1 — Tarefa 2, R3).
//   deno test supabase/functions/admin-candidate-lists/scoring.test.ts
//
// Foco: a dimensão de Localização (15 pts) passou a ler também
// primary_location_city (JP), destravando os 176 candidatos com cidade só ali.
import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import { type CandidateProfile, scoreCandidate } from './scoring.ts';

function makeCandidate(overrides: Partial<CandidateProfile> = {}): CandidateProfile {
  return {
    userId: 'u1',
    name: 'Fulano',
    email: '',
    phone: '',
    city: '',
    primaryLocationCity: '',
    state: '',
    headline: '',
    summary: '',
    completenessScore: 0,
    skills: [],
    desiredTitles: [],
    education: [],
    workModes: [],
    jobTypes: [],
    otherLocations: [],
    likes: 0,
    applies: 0,
    consentStatus: 'not_asked',
    createdAt: '2026-01-01',
    ...overrides,
  };
}

// Vaga presencial em São Paulo — força a dimensão de Localização a depender da
// cidade declarada do candidato (remota passaria por default).
const spJob = {
  title: '',
  area: '',
  description: '',
  requirements: [] as string[],
  location_city: 'São Paulo',
  location_state: 'SP',
  work_model: 'presencial',
  job_type: '',
};

// deno-lint-ignore no-explicit-any
function locationPoints(request: any, candidate: CandidateProfile): number {
  const { breakdown } = scoreCandidate(request, candidate);
  return breakdown.find((b) => b.label === 'Localizacao')?.points ?? -1;
}

Deno.test('cidade só em primary_location_city (JP) agora ganha os 15 de Localização', () => {
  assertEquals(locationPoints(spJob, makeCandidate({ primaryLocationCity: 'São Paulo' })), 15);
});

Deno.test('sem cidade nenhuma → 0 (era o gap dos 176 candidatos JP-only)', () => {
  assertEquals(locationPoints(spJob, makeCandidate()), 0);
});

Deno.test('cidade em profile_personal.location_city continua pontuando 15 (não regride)', () => {
  assertEquals(locationPoints(spJob, makeCandidate({ city: 'São Paulo' })), 15);
});

Deno.test('cidade JP divergente não casa vaga de outra cidade', () => {
  assertEquals(locationPoints(spJob, makeCandidate({ primaryLocationCity: 'Curitiba' })), 0);
});

Deno.test('vaga remota passa Localização mesmo sem cidade declarada', () => {
  assertEquals(locationPoints({ ...spJob, work_model: 'remoto' }, makeCandidate()), 15);
});
