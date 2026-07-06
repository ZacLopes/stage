import { assert, assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import type { CandidateProfile } from './scoring.ts';
import {
  EXPORT_HEADERS,
  exportRowCells,
  isInternalAccount,
  isSyntheticEmail,
  motivoFromBreakdown,
} from './export_csv.ts';

function profile(overrides: Partial<CandidateProfile> = {}): CandidateProfile {
  return {
    userId: 'u1',
    name: 'Maria Souza',
    email: 'maria@gmail.com',
    phone: '+5511999998888',
    city: 'São Paulo',
    primaryLocationCity: '',
    state: 'SP',
    headline: '',
    summary: 'Estudante de ADM focada em finanças.',
    completenessScore: 70,
    skills: ['Excel', 'Power BI'],
    desiredTitles: ['Finanças'],
    education: [],
    workModes: ['hibrido'],
    jobTypes: ['estagio'],
    otherLocations: [],
    likes: 0,
    applies: 0,
    consentStatus: 'not_asked',
    createdAt: '2026-01-01',
    institution: 'FGV',
    course: 'Administração',
    semester: 5,
    graduationYear: 2027,
    educationLevel: 'college',
    languages: 'Inglês (Avançado)',
    linkedin: 'https://linkedin.com/in/maria',
    availability: 'immediate',
    desiredPosition: 'Estágio em FP&A',
    cvPath: 'u1/123.pdf',
    isSyntheticEmail: false,
    isInternal: false,
    ...overrides,
  };
}

Deno.test('sintético e interno são detectados', () => {
  assert(isSyntheticEmail('phone_5511999998888@stage.app'));
  assert(!isSyntheticEmail('maria@gmail.com'));
  assert(isInternalAccount('internal-fase0-test@stage.app'));
  assert(isInternalAccount('phone_5500900000001@stage.app'));
  assert(!isInternalAccount('maria@gmail.com'));
});

Deno.test('motivo usa só dimensões com pontos > 0', () => {
  const m = motivoFromBreakdown([
    { label: 'Cargo/área', points: 25, detail: 'x' },
    { label: 'Skills', points: 0, detail: 'y' },
    { label: 'Localização', points: 15, detail: 'z' },
  ]);
  assertEquals(m, 'Cargo/área: 25; Localização: 15');
});

Deno.test('anti-injeção: campo começando com = ganha aspa simples', () => {
  const cells = exportRowCells(
    profile({ name: '=SOMA(A1:A9)', skills: ['@cmd', 'Excel'] }),
    { score: 88, scoreBreakdown: [{ label: 'Skills', points: 25 }] },
    'https://cv',
  );
  const nome = cells[EXPORT_HEADERS.indexOf('nome')];
  const skills = cells[EXPORT_HEADERS.indexOf('skills')];
  assertEquals(nome, "'=SOMA(A1:A9)");
  assert(skills.startsWith("'@cmd"), `skills sanitizado: ${skills}`);
});

Deno.test('telefone sai como fórmula ="..." e NÃO é sanitizado', () => {
  const cells = exportRowCells(profile(), { score: 90 }, '');
  const tel = cells[EXPORT_HEADERS.indexOf('telefone')];
  assertEquals(tel, '="+5511999998888"');
});

Deno.test('e-mail sintético vira vazio na coluna de contato', () => {
  const cells = exportRowCells(
    profile({ email: 'phone_5511999998888@stage.app' }),
    { score: 50 },
    '',
  );
  assertEquals(cells[EXPORT_HEADERS.indexOf('email')], '');
});

Deno.test('colunas ricas mapeiam PT + score/curriculo', () => {
  const cells = exportRowCells(
    profile(),
    { score: 82, scoreBreakdown: [{ label: 'Área', points: 30 }] },
    'https://cv/signed',
  );
  const at = (h: string) => cells[EXPORT_HEADERS.indexOf(h)];
  assertEquals(at('curso'), 'Administração');
  assertEquals(at('instituicao'), 'FGV');
  assertEquals(at('semestre'), '5');
  assertEquals(at('previsao_formatura'), '2027');
  assertEquals(at('nivel'), 'Graduação');
  assertEquals(at('modalidade'), 'Híbrido');
  assertEquals(at('tipo_vaga'), 'Estágio');
  assertEquals(at('disponibilidade'), 'Imediata');
  assertEquals(at('idiomas'), 'Inglês (Avançado)');
  assertEquals(at('score'), '82');
  assertEquals(at('motivo'), 'Área: 30');
  assertEquals(at('curriculo_link'), 'https://cv/signed');
  assertEquals(cells.length, EXPORT_HEADERS.length);
});

Deno.test('cidade cai pro primaryLocationCity quando location_city vazio', () => {
  const cells = exportRowCells(
    profile({ city: '', primaryLocationCity: 'Curitiba' }),
    { score: 40 },
    '',
  );
  assertEquals(cells[EXPORT_HEADERS.indexOf('cidade')], 'Curitiba');
});
