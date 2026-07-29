// Rede para a checagem 8 de `validateAdaptationV2` (revisão UX 28/07, P0):
// o summary não pode alegar experiência profissional quando o perfil tem 0
// experiences.
//
// Por que este arquivo existe: a R5 manda rodar `golden_set/` ao encostar no
// pipeline adapt, mas o corpus está VAZIO e nenhum script/CI o invoca — então
// "golden_set limpo" não distingue "passou" de "não havia o que rodar". Estes
// testes são a única rede real desta mudança.
//
// Rodar:  deno test supabase/functions/adapt-resume-to-job/summary_experience_claim.test.ts

import { assertThrows } from 'https://deno.land/std@0.208.0/assert/mod.ts'
import { validateAdaptationV2, ValidationErrorV2 } from './v2.ts'
import type { InputResumeV2 } from './v2.ts'

/// Input mínimo e VÁLIDO para as checagens 1–7, para que qualquer throw venha
/// da checagem 8. `experiences: []` é o cenário do achado.
function inputSemExperiencia(): InputResumeV2 {
  return {
    userId: 'u1',
    fullName: 'Ana Ribeiro',
    email: 'ana@example.com',
    phone: '',
    linkedin: '',
    location: 'Curitiba, PR, BR',
    streetAddress: '',
    headline: '',
    language: 'pt',
    summary: '',
    skills: ['Excel', 'Power BI'],
    tools: [],
    experiences: [],
    education: [],
    languages: [],
    achievements: [],
    interests: [],
    certifications: [],
    keywordPool: new Set<string>(),
  }
}

function saidaCom(summary: string) {
  return {
    resume: {
      fullName: 'Ana Ribeiro',
      email: 'ana@example.com',
      linkedin: '',
      streetAddress: '',
      headline: '',
      summary,
      skills: ['Excel', 'Power BI'],
      tools: [],
      experiences: [],
      education: [],
      languages: [],
    },
  }
}

function assertRejeita(summary: string) {
  assertThrows(
    () => validateAdaptationV2(inputSemExperiencia(), saidaCom(summary)),
    ValidationErrorV2,
    'summary alega experiência profissional inexistente',
  )
}

function assertAceita(summary: string) {
  // Não deve lançar.
  validateAdaptationV2(inputSemExperiencia(), saidaCom(summary))
}

Deno.test('rejeita o texto exato observado em produção', () => {
  assertRejeita(
    'Estudante de Engenharia de Produção com experiência em elaboração de '
    + 'relatórios e cotações com fornecedores. Possuo conhecimento em Power BI.',
  )
})

Deno.test('rejeita variações de alegação de experiência (PT)', () => {
  assertRejeita('Profissional com experiência com fornecedores.')
  assertRejeita('Estudante com 2 anos de experiência na área.')
  assertRejeita('Tenho atuação em logística e suprimentos.')
  assertRejeita('Estudante com vivência em processos industriais.')
})

Deno.test('rejeita alegação de experiência em inglês', () => {
  assertRejeita('Production Engineering student with experience in reporting.')
  assertRejeita('Student experienced in supplier management.')
  assertRejeita('Student with 3 years of experience in logistics.')
})

Deno.test('aceita frases de BUSCA — é o que um CV de estudante deve dizer', () => {
  assertAceita('Estudante buscando experiência em Suprimentos.')
  assertAceita('Busco minha primeira experiência em Engenharia de Produção.')
  assertAceita('Estudante sem experiência prévia, com forte base em Excel.')
  assertAceita('Procuro uma oportunidade de ganhar experiência em Logística.')
  assertAceita('Student seeking experience in supply chain.')
  assertAceita('Looking for a first experience in operations.')
})

Deno.test('aceita summary que fala de conhecimento/formação (a saída correta)', () => {
  assertAceita(
    'Estudante de Engenharia de Produção com conhecimento em Power BI e Excel, '
    + 'além de familiaridade com elaboração de relatórios.',
  )
  assertAceita('Estudante de Engenharia de Produção. Cursando o 7º semestre.')
  assertAceita('')
})

Deno.test('não interfere quando o perfil TEM experiência', () => {
  const comExp: InputResumeV2 = {
    ...inputSemExperiencia(),
    experiences: [
      {
        id: 'e1',
        company: 'Empresa X',
        role: 'Estagiário',
        location: '',
        startDate: '2025-01',
        endDate: '',
        current: true,
        bullets: [],
        // deno-lint-ignore no-explicit-any
      } as any,
    ],
  }
  const saida = saidaCom('Estagiário com experiência em relatórios.')
  // deno-lint-ignore no-explicit-any
  ;(saida.resume as any).experiences = [
    { company: 'Empresa X', role: 'Estagiário', bullets: [] },
  ]
  validateAdaptationV2(comExp, saida)
})
