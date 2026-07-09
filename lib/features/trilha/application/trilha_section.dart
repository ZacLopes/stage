// Mapeamento passo-da-trilha → seção do stepper da aba Currículo (PLANO-FASE-6).
//
// A trilha conversacional NÃO carrega seção no `ConversationStep`; o stepper das
// 5 seções (Formação → Experiência → Skills → Idiomas → Interesses) é derivado
// aqui, de forma pura e testável:
//
//  - `trilhaSectionForStepId`: prefixo do `step.id` → seção (passos fora das 5,
//    como área/cidade/LinkedIn/cert/projeto, caem em `outros`).
//  - `sectionStatuses`: status (`pending`/`current`/`done`) de cada uma das 5
//    seções, derivado do histórico + passo atual. "Done" reusa
//    [TrilhaProgress.segmentToMark] (passos terminais), então é IMUNE à injeção
//    dinâmica de passos (loop de skills, níveis de idioma não "des-concluem").
//
// Fica em application/ (não domain/) porque depende de [ConversationExchange] e
// [TrilhaProgress], ambos desta camada.

import '../../../services/profile_snapshot_service.dart' show ProfileSnapshot;
import '../domain/conversation_step.dart';
import 'conversation_controller.dart';
import 'trilha_progress.dart';

/// Seções possíveis. As 5 primeiras aparecem no stepper; `outros` agrupa os
/// passos da trilha que não pertencem a nenhuma delas (preferências, cidade,
/// disponibilidade, LinkedIn, certificações, projetos…).
enum TrilhaSection { formacao, experiencia, skills, idiomas, interesses, outros }

/// Estado de uma seção no stepper.
enum SectionStatus { pending, current, done }

/// Ordem fixa exibida no stepper (espelha o mockup).
const List<TrilhaSection> kStepperSections = <TrilhaSection>[
  TrilhaSection.formacao,
  TrilhaSection.experiencia,
  TrilhaSection.skills,
  TrilhaSection.idiomas,
  TrilhaSection.interesses,
];

/// Seções (das 5 do stepper) que o perfil JÁ tem preenchidas. Base da abertura
/// adaptativa da trilha: se retornar não-vazio, o chat reconhece o que existe e
/// pula o gate de import (em vez de oferecer "começar do zero" a quem já tem dados).
Set<TrilhaSection> preFilledSectionsFromSnapshot(ProfileSnapshot s) {
  final out = <TrilhaSection>{};
  if (s.education.isNotEmpty) out.add(TrilhaSection.formacao);
  if (s.experiences.isNotEmpty) out.add(TrilhaSection.experiencia);
  if (s.skills.isNotEmpty) out.add(TrilhaSection.skills);
  if (s.languages.isNotEmpty) out.add(TrilhaSection.idiomas);
  if (s.interests.isNotEmpty) out.add(TrilhaSection.interesses);
  return out;
}

/// Rótulo curto da seção (pt-BR).
String trilhaSectionLabel(TrilhaSection s) {
  switch (s) {
    case TrilhaSection.formacao:
      return 'Formação';
    case TrilhaSection.experiencia:
      return 'Experiência';
    case TrilhaSection.skills:
      return 'Skills';
    case TrilhaSection.idiomas:
      return 'Idiomas';
    case TrilhaSection.interesses:
      return 'Interesses';
    case TrilhaSection.outros:
      return 'Outros';
  }
}

/// Seção de um passo a partir do seu `id` (prefixos do plano de conversa).
TrilhaSection trilhaSectionForStepId(String id) {
  if (id.startsWith('gap.edu')) return TrilhaSection.formacao;
  if (id.startsWith('exp.')) return TrilhaSection.experiencia;
  if (id.startsWith('gap.skills')) return TrilhaSection.skills;
  if (id.startsWith('gap.languages') || id.startsWith('lang.level')) {
    return TrilhaSection.idiomas;
  }
  if (id.startsWith('gap.interests') || id.startsWith('interests.')) {
    return TrilhaSection.interesses;
  }
  return TrilhaSection.outros;
}

/// Converte um "segmento" do [TrilhaProgress] numa das 5 seções (ou null).
TrilhaSection? _sectionForSegment(String? segment) {
  switch (segment) {
    case 'education':
      return TrilhaSection.formacao;
    case 'experience':
      return TrilhaSection.experiencia;
    case 'skills':
      return TrilhaSection.skills;
    case 'languages':
      return TrilhaSection.idiomas;
    case 'interests':
      return TrilhaSection.interesses;
  }
  return null;
}

/// Status de cada uma das 5 seções do stepper.
///
/// Regras:
///  - **done**: a seção já tem dado — ou pré-existente no perfil (`preFilled`),
///    ou um passo terminal foi respondido no histórico ([segmentToMark]).
///  - **current**: a seção do passo atual (quando é uma das 5). Tem precedência
///    sobre `done` (a seção ativa fica destacada mesmo que o passo terminal já
///    tenha sido respondido — ex.: durante o loop "adicionar mais skills").
///    Se o passo atual cai em `outros`, usa `stickyCurrent` (mantém a última
///    seção ativa destacada — evita o stepper "apagar" em cidade/área/LinkedIn).
///  - **pending**: o resto.
Map<TrilhaSection, SectionStatus> sectionStatuses({
  required List<ConversationExchange> history,
  required ConversationStep? current,
  Set<TrilhaSection> preFilled = const <TrilhaSection>{},
  TrilhaSection? stickyCurrent,
}) {
  final done = <TrilhaSection>{...preFilled};
  for (final ex in history) {
    final seg = TrilhaProgress.segmentToMark(ex.step.id, ex.answer.value);
    final sec = _sectionForSegment(seg);
    if (sec != null) done.add(sec);
    // Idiomas: o picker (gap.languages) NÃO marca a memória de "abordado" (Fase
    // 7 +10 Tarefa 3 — pra a trilha voltar a perguntar o nível que faltou), mas
    // no STEPPER ele conta como concluído: o usuário já engajou com a seção.
    if (ex.step.id.startsWith('gap.languages') ||
        ex.step.id.startsWith('lang.level')) {
      done.add(TrilhaSection.idiomas);
    }
  }

  TrilhaSection? cur;
  if (current != null) {
    final s = trilhaSectionForStepId(current.id);
    if (s != TrilhaSection.outros) cur = s;
  }
  cur ??= stickyCurrent;

  final out = <TrilhaSection, SectionStatus>{};
  for (final sec in kStepperSections) {
    if (sec == cur) {
      out[sec] = SectionStatus.current;
    } else if (done.contains(sec)) {
      out[sec] = SectionStatus.done;
    } else {
      out[sec] = SectionStatus.pending;
    }
  }
  return out;
}

/// A seção (das 5) do passo atual, ou null se for `outros`/nula. Útil pro shell
/// da aba manter o "sticky" da última seção ativa.
TrilhaSection? activeFiveSection(ConversationStep? current) {
  if (current == null) return null;
  final s = trilhaSectionForStepId(current.id);
  return s == TrilhaSection.outros ? null : s;
}
