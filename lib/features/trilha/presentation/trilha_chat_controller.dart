// Orquestrador do chat da trilha v2 (PLANO chat v2 — F2 + F3).
//
// Dono do FIO. Três fases:
//   - gate: abre perguntando "começar do zero / já tenho currículo".
//   - importing: leu o PDF → "Lendo…" → poll da extração → card-resumo.
//   - converse: a conversa guiada pelas lacunas (recomputadas após o import).
//
// A sessão das lacunas ([TrilhaSession]) é construída SÓ ao entrar em `converse`
// — depois do import, então reflete o que a extração preencheu (menos perguntas).
// Edição de card é in-place (re-save idempotente via [TrilhaSession.saveAnswer]).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/ai_service.dart';
import '../../../services/analytics_events.dart';
import '../../../services/analytics_service.dart';
import '../../../services/profile_snapshot_service.dart';
import '../application/assistant_context_store.dart';
import '../application/conversation_controller.dart';
import '../application/conflict_rpc_choices.dart';
import '../application/cv_conflict.dart';
import '../application/import_apply_outcome.dart';
import '../application/trilha_session.dart';
import '../../profile/domain/skill_name_normalizer.dart';
import '../domain/assist_skills_write.dart';
import '../domain/conversation_step.dart';

/// Camada que interpreta texto livre → ids de opção (default: [AIService]).
/// Injetável p/ teste. Assinatura = [AIService.interpretStepAnswer].
typedef StepInterpreter =
    Future<StepInterpretation?> Function({
      required String stepId,
      required String question,
      required String freeText,
      required List<Map<String, String>> options,
      bool multi,
    });

Duration _typingFor(String msg) =>
    Duration(milliseconds: (msg.length * 16).clamp(420, 1200).toInt());
Duration _pauseFor(String msg) =>
    Duration(milliseconds: (msg.length * 4).clamp(200, 460).toInt());

enum ChatPhase { gate, importing, converse }

/// Contagem do que a extração trouxe (pro card-resumo).
class ImportSummary {
  final int experiences;
  final int skills;
  final int languages;
  final int education;
  const ImportSummary({
    required this.experiences,
    required this.skills,
    required this.languages,
    required this.education,
  });
  int get total => experiences + skills + languages + education;
  bool get isEmpty => total == 0;
}

/// Itens do fio.
sealed class ChatItem {
  const ChatItem();
}

class AiMsgItem extends ChatItem {
  final String text;
  const AiMsgItem(this.text);
}

/// Mensagem do USUÁRIO digitada na barra (assistente) — pra a conversa mostrar
/// o que a pessoa falou (respostas de passo viram AnsweredItem, não isto).
class UserMsgItem extends ChatItem {
  final String text;
  const UserMsgItem(this.text);
}

class AnsweredItem extends ChatItem {
  final ConversationExchange exchange;
  const AnsweredItem(this.exchange);
}

/// Bolha do arquivo enviado (lado do usuário).
class FileBubbleItem extends ChatItem {
  final String name;
  const FileBubbleItem(this.name);
}

/// Card-resumo da extração + "Revisar e confirmar".
class ImportSummaryItem extends ChatItem {
  final ImportSummary summary;
  const ImportSummaryItem(this.summary);
}

/// Estado do card de mutação do assistente (Fase B).
enum AssistEditStatus { pending, applied, undone, cancelled }

/// Operação da mutação: trocar um campo (update), adicionar (add), remover
/// (remove — destrutivo) um item de lista, ou reescrever um bullet (bullet,
/// keyed por id).
enum AssistEditOp { update, add, remove, bullet }

/// Card de ALTERAÇÃO do assistente: propõe (pending, com Aplicar/Cancelar) →
/// aplica (applied, com Desfazer) → desfaz (undone). A view renderiza conforme
/// o [status] e [op]; o controller o transiciona (confirm/cancel/undoAssistEdit).
class AssistEditItem extends ChatItem {
  final String id;
  final AssistEditOp op;
  final String field; // campo (update) ou kind (add/remove: skill/language)
  final String fieldLabel; // "Cargo desejado" / "suas skills"
  final String beforeRaw; // valor cru anterior (update, pro undo)
  final String beforeText; // "—" ou o texto anterior (update)
  final String afterText; // exibição do novo valor / do item
  final String value; // valor cru a aplicar / item a add/remove
  final String
  refId; // id da linha (op=bullet: bullet_id; item-field: id do item)
  /// Editar um CAMPO de item multi-campo (experiência/formação/cert): o kind da
  /// seção. Vazio ⇒ é um campo global (update normal). Usa op=update + refId=id.
  final String itemKind;

  /// Undo CAPTURADO na aplicação (ex.: remover experiência guarda o restore que
  /// re-insere o registro). Quando presente, tem prioridade sobre o undo por op.
  Future<void> Function()? capturedUndo;
  AssistEditStatus status;
  bool applying = false;
  bool undoing = false;
  String resultMessage = '';
  AssistEditItem({
    required this.id,
    this.op = AssistEditOp.update,
    required this.field,
    required this.fieldLabel,
    this.beforeRaw = '',
    this.beforeText = '',
    required this.afterText,
    required this.value,
    this.refId = '',
    this.itemKind = '',
    this.status = AssistEditStatus.pending,
  });
}

/// Um item extraído de um textão colado (Fase C): kind canônico + valor + como
/// exibir. kinds: skill / language / desired_position.
class AssistExtractEntry {
  final String kind;
  final String value;
  final String label; // "Skill: Python" / "Cargo: Analista"
  const AssistExtractEntry({
    required this.kind,
    required this.value,
    required this.label,
  });
}

/// Card "Peguei isto 👇" (extração multi-campo): lista os itens, confirma tudo
/// de uma vez, e um Desfazer reverte o lote inteiro.
class AssistExtractItem extends ChatItem {
  final String id;
  final List<AssistExtractEntry> entries;
  AssistEditStatus status;
  bool applying = false;
  bool undoing = false;
  bool undoFailed = false;
  String resultMessage = '';

  /// Recibo por entrada. Um retry tenta somente [failedIndexes]; entradas já
  /// confirmadas não são gravadas de novo. O undo existe apenas quando esta
  /// ação realmente mudou o perfil (um item que já existia não é removido).
  final Set<int> appliedIndexes = <int>{};
  final Set<int> failedIndexes = <int>{};
  final Map<int, Future<void> Function()> undoByIndex = {};

  int get appliedCount => appliedIndexes.length;
  bool get madeChanges => undoByIndex.isNotEmpty;
  bool get isPartial =>
      status == AssistEditStatus.pending && appliedIndexes.isNotEmpty;
  AssistExtractItem({
    required this.id,
    required this.entries,
    this.status = AssistEditStatus.pending,
  });
}

/// Editor VISUAL de lista simples (Fase C): mostra os itens atuais em chips (✕
/// pra tirar) + campo/sugestões pra adicionar. "Salvar" aplica o líquido (adds +
/// removes) e deixa um Desfazer que reverte o lote. Nesta fase, o editor ativo
/// serve somente SKILLS; interesses ficam em Perfil → Dados. O estado de
/// edição vive no widget; aqui ficam o baseline (itens no
/// momento de abrir), as sugestões, e o resultado aplicado (pro undo).
class ListEditorItem extends ChatItem {
  final String id;
  final String operationId;
  final String kind; // 'skill' | 'interest'
  final String title; // "Suas habilidades" / "Seus interesses"
  final List<String> initial;
  final List<String> suggestions;
  AssistEditStatus status;
  bool applying = false;
  bool undoing = false;
  bool hasUnconfirmedChanges = false;
  bool undoAvailable = false;
  String resultMessage = '';
  List<String> pendingAdded = const [];
  List<String> pendingRemoved = const [];
  List<String> pendingDesired = const [];
  List<String>? observedAfter;
  List<String> addedApplied = const [];
  List<String> removedApplied = const [];
  ListEditorItem({
    required this.id,
    required this.operationId,
    required this.kind,
    required this.title,
    required this.initial,
    this.suggestions = const [],
    this.status = AssistEditStatus.pending,
  });
}

/// Um idioma no editor visual: nome + nível canônico ('basic'..'native' ou null).
class LangEntry {
  final String name;
  final String? level;
  const LangEntry(this.name, this.level);
}

/// Editor VISUAL de idiomas (Fase C): como o [ListEditorItem], mas cada item tem
/// NÍVEL. O líquido tem 3 ops (adicionado c/ nível, removido, nível alterado);
/// o baseline guarda os níveis antigos pro undo.
class LanguagesEditorItem extends ChatItem {
  final String id;
  final List<LangEntry> initial;
  final List<String> options; // idiomas canônicos que dá pra adicionar
  AssistEditStatus status;
  bool applying = false;
  bool undoing = false;
  bool hasUnconfirmedChanges = false;
  bool undoAvailable = false;
  String resultMessage = '';
  List<LangEntry> pendingAdded = const [];
  List<String> pendingRemoved = const [];
  List<LangEntry> pendingChanged = const [];
  List<LangEntry>? observedAfter;
  List<LangEntry> addedApplied = const [];
  List<String> removedApplied = const [];
  List<LangEntry> changedApplied = const [];
  LanguagesEditorItem({
    required this.id,
    required this.initial,
    this.options = const [],
    this.status = AssistEditStatus.pending,
  });
}

/// Uma vaga real pro card do assistente (consulta ao feed). `score` 0-100;
/// `hasScore` false ⇒ não deu pra calcular (sem CV) → o card mostra "—".
class AssistJobRow {
  final String id;
  final String title;
  final String company;
  final String area;
  final int score;
  final bool hasScore;
  const AssistJobRow({
    required this.id,
    required this.title,
    required this.company,
    this.area = '',
    this.score = 0,
    this.hasScore = false,
  });
}

/// Resultado da consulta de vagas: as melhores N + se o user tem CV (pra o card
/// avisar que sem CV o match não sai). `outOfProfileArea` != '' ⇒ as vagas vêm
/// do CATÁLOGO (área pedida fora do perfil) → o card orienta a edição em
/// Perfil → Objetivos.
class AssistJobsResult {
  final bool hasResume;
  final List<AssistJobRow> jobs;
  final String outOfProfileArea;
  const AssistJobsResult({
    required this.hasResume,
    required this.jobs,
    this.outOfProfileArea = '',
  });
}

/// Desfecho do export_pdf: nada pra exportar (perfil vazio), falha na geração,
/// ou sucesso. Pro assistente falar a verdade (não "Pronto!" em cima de um erro).
enum AssistExportOutcome { empty, failed, ok }

/// Desfecho do import_cv: usuário cancelou o seletor, falhou (arquivo inválido/
/// não-CV), ou importou. `message` carrega o motivo do erro (ex.: "parece um
/// extrato bancário") pra falar a verdade.
enum AssistImportOutcome { cancelled, failed, ok }

class AssistImportResult {
  final AssistImportOutcome outcome;
  final String? message;

  /// Linhas de conflito (import mid-trilha com perfil não-vazio) → card.
  final List<ConflictRow> conflicts;

  /// Ids da candidata reservada (Gate 3.0I) — necessários pra aplicar as
  /// escolhas revisadas via `apply_reviewed_conflicts_and_promote`. Vazios
  /// quando não há candidata (import sem conflitos / caminho legado).
  final String candidateId;
  final String attemptId;
  const AssistImportResult(
    this.outcome, {
    this.message,
    this.conflicts = const [],
    this.candidateId = '',
    this.attemptId = '',
  });
}

/// Escolha do usuário por linha no card de conflito de import.
class ConflictChoice {
  final ConflictRow row;
  bool accepted;
  String editedValue; // vazio ⇒ usa row.value
  ConflictChoice(this.row, {required this.accepted, this.editedValue = ''});
  String get effectiveValue =>
      editedValue.trim().isEmpty ? row.value : editedValue.trim();
}

/// Card "o CV diz X × você tem Y": lista as linhas (adição/conflito), cada uma
/// com aceitar/rejeitar/editar; "Aplicar seleção" grava as aceitas + Desfazer.
class ImportConflictItem extends ChatItem {
  final String id;
  final List<ConflictChoice> choices;

  /// Candidata reservada (Gate 3.0I): a aplicação chama
  /// `apply_reviewed_conflicts_and_promote(candidateId, attemptId, choices)` —
  /// 1 transação atômica que aplica + promove, com agregado honesto.
  final String candidateId;
  final String attemptId;
  AssistEditStatus status;
  bool applying = false; // guarda de reentrância (evita duplo-apply)
  int appliedCount = 0;

  /// Resultado honesto da última aplicação (agregado do RPC) — pro card mostrar
  /// "N aplicados, M mantidos (você já tinha editado), K rejeitados" em vez de
  /// um "aplicado" cego. null enquanto pendente.
  ImportApplyOutcome? outcome;
  ImportConflictItem({
    required this.id,
    required this.choices,
    required this.candidateId,
    required this.attemptId,
    this.status = AssistEditStatus.pending,
  });
}

/// Uma lacuna do perfil pro card estruturado (show_gaps/show_profile_summary).
/// `key` = LacunaKey.name (pro ícone); `tier` = 'tier1'|'tier2'|'tier3' (cor).
class GapRow {
  final String key;
  final String tier;
  final String label;

  /// Seção (start_section) que preenche esta lacuna; '' ⇒ não dá pra preencher
  /// por aqui (ex.: summary, que é gerado) → linha não vira botão.
  final String section;
  const GapRow({
    required this.key,
    required this.tier,
    required this.label,
    this.section = '',
  });
}

/// Snapshot das lacunas: % de completude + o que ainda falta.
class AssistGaps {
  final int completionPercent;
  final List<GapRow> missing;
  const AssistGaps({required this.completionPercent, required this.missing});
}

/// Card "Seu perfil" (Grande: render estruturado): barra de completude + lista
/// do que falta. Display-only. Serve show_gaps E show_profile_summary.
class GapsCardItem extends ChatItem {
  final int completionPercent;
  final List<GapRow> rows;
  const GapsCardItem({required this.completionPercent, required this.rows});
}

/// Card "Vagas pra você" (Grande: consulta ao feed real). Lista as vagas
/// (tocáveis → abrem o detalhe) + salvar por vaga. `hasResume` false ⇒ header
/// avisa do CV. `outOfProfileArea` = área pedida que não está no perfil (busca
/// no catálogo) → o header orienta a edição em Perfil → Objetivos.
class JobsCardItem extends ChatItem {
  final String id;
  final List<AssistJobRow> jobs;
  final bool hasResume;
  final String outOfProfileArea;
  final Set<String> savedIds = {};
  // Estado legado preservado para rollback da flag. No Assistente novo, áreas
  // não são gravadas por este card: a edição mora em Perfil → Objetivos.
  bool areaAdded;
  JobsCardItem({
    required this.id,
    required this.jobs,
    this.hasResume = true,
    this.outOfProfileArea = '',
    this.areaAdded = false,
  });
}

/// O que o toque num chip de partida faz.
enum StarterChipAction {
  /// Manda um texto pro assistente (reusa o roteamento de vagas, lacunas,
  /// resumo e capacidades).
  message,

  /// "Montar do zero" → entra na coleta guiada.
  startZero,
}

/// Um chip de partida (empty-state do assistente): id + rótulo curto + ação. O
/// ícone é escolhido no view por [id] (o controller não conhece IconData).
class StarterChip {
  final String id;
  final String label;

  /// Herói = a melhor próxima ação (pílula no gradiente da marca).
  final bool hero;
  final StarterChipAction action;

  /// Texto mandado ao assistente quando [action] == message.
  final String message;

  const StarterChip({
    required this.id,
    required this.label,
    this.hero = false,
    this.action = StarterChipAction.message,
    this.message = '',
  });
}

/// Vitrine de chips na abertura do chat (só com o assistente ligado): mostra ao
/// usuário — que chega sem saber nada — o que o copiloto faz, com pontos de
/// entrada tocáveis (uso único; some ao primeiro toque).
class StarterChipsItem extends ChatItem {
  final List<StarterChip> chips;
  StarterChipsItem(this.chips);
}

/// Card de AÇÃO com botão (exportar/importar): o usuário toca no botão e SÓ
/// então a ação nativa dispara (folha de compartilhar / seletor de arquivo).
class AssistActionCardItem extends ChatItem {
  final String id;
  final String kind; // 'export' | 'import'
  AssistEditStatus status; // pending (botão) → applied (feito) / cancelled
  bool running = false;
  String resultMessage;
  // Import OK → oferece atalho "Ver meus currículos" (o CV importado foi salvo
  // na biblioteca, que vive na aba Perfil — não na aba Currículo).
  bool showCvLibraryLink;
  AssistActionCardItem({
    required this.id,
    required this.kind,
    this.status = AssistEditStatus.pending,
    this.resultMessage = '',
    this.showCvLibraryLink = false,
  });
}

/// Valor atual de um campo (pro diff/undo do assistente).
class AssistFieldValue {
  final String raw; // valor cru (id/texto) — '' se vazio
  final String text; // exibição ("São Paulo" / "—")
  final String label; // rótulo do campo ("Cidade")
  const AssistFieldValue({
    required this.raw,
    required this.text,
    required this.label,
  });
}

/// Lê o valor atual de um campo (pro diff/undo). null ⇒ campo não editável aqui.
typedef AssistFieldReader = Future<AssistFieldValue?> Function(String field);

/// Aplica um valor cru a um campo (value '' limpa). Reusado por vários callbacks
/// de 2 args (adder/remover/upserter/bullet-legado) — NÃO mexer.
typedef AssistFieldWriter = Future<void> Function(String field, String value);

/// Gate 3.0H app-side — writer de escalar/bullet COM o observado ([expected])
/// pro CAS server-side (manual-recente-vence). `a`=campo/bulletId, `b`=valor.
typedef AssistCasWriter = Future<void> Function(
  String a,
  String b,
  String expected,
);

/// Grande: consulta o feed real de vagas (já filtrado pelo perfil do user).
/// Filtro opcional por área/texto (client-side). Retorna as melhores N + se tem CV.
typedef AssistJobsLoader =
    Future<AssistJobsResult> Function({String? area, String? query, int limit});

/// Turno do assistente (injetável p/ teste). Mesma forma de [AIService.assistantTurn].
typedef AssistantTurnFn =
    Future<AssistantTurn?> Function({
      required String message,
      Map<String, dynamic>? openStep,
      Map<String, dynamic> context,
      List<Map<String, dynamic>> history,
    });

class TrilhaChatController extends ChangeNotifier {
  TrilhaChatController({
    required this.userId,
    required this.sessionBuilder,
    this.snapshotService,
    this.preFilledLoader,
    this.onFinalize,
    this.onStarted,
    this.interpret,
    this.assistEnabled = false,
    this.assistantTurn,
    this.assistantContextStore,
    this.assistContextLoader,
    this.assistSectionSteps,
    this.assistReadField,
    this.assistWriteField,
    this.assistItemAdder,
    this.assistItemRemover,
    this.assistItemResolver,
    this.assistBulletReader,
    this.assistBulletWriter,
    this.assistReversibleRemover,
    this.assistProactiveLoader,
    this.assistSkillsLoader,
    this.assistSkillsWriter,
    this.assistSkillSuggester,
    this.assistInterestsLoader,
    this.assistInterestsReplacer,
    this.assistAreasLoader,
    this.assistAreasReplacer,
    this.assistLanguagesLoader,
    this.assistLanguageUpserter,
    this.assistItemFieldReader,
    this.assistItemFieldWriter,
    this.assistJobsLoader,
    this.assistOpenTab,
    this.assistOpenCvLibrary,
    this.assistExportPdf,
    this.assistImportCv,
    this.assistGapsLoader,
    this.assistConflictApplier,
    this.assistReviewedConflictApplier,
    this.assistReviewedConflictReverter,
    this.assistOpenJobDetail,
    this.assistSaveJob,
    this.assistUnsaveJob,
    this.onProfileEdited,
    this.onDocumentsChanged,
    this.pollInterval = const Duration(milliseconds: 1500),
    this.maxPolls = 40,
  });

  final String userId;

  /// Constrói a sessão das lacunas a partir do perfil FRESCO (injetável p/ teste).
  final Future<TrilhaSession> Function(String userId) sessionBuilder;

  /// Pra o poll da extração (injetável p/ teste).
  final ProfileSnapshotService? snapshotService;

  /// Rótulos (pt-BR, minúsculo) das seções que o perfil JÁ tem — pra abertura
  /// adaptativa. Chamado 1x no [start]. null/vazio ⇒ perfil vazio ⇒ mostra o
  /// gate de import (comportamento padrão). Ex.: `['formação', 'skills', 'idiomas']`.
  final Future<List<String>> Function()? preFilledLoader;

  final Future<String?> Function()? onFinalize;

  /// Chamado ao entrar em `converse` (telemetria com o nº de passos).
  final void Function(int totalSteps)? onStarted;

  /// Interpretador de texto livre → ids de opção. null ⇒ usa [AIService].
  final StepInterpreter? interpret;

  // ── Assistente de IA na barra (PLANO-ASSISTENTE, Fase A) ──────────────────
  /// Flag `trilha_assist_v1`. OFF ⇒ a barra mantém o comportamento de hoje
  /// (responder o passo aberto). ON ⇒ o texto passa pelo assistente.
  final bool assistEnabled;

  /// Turno do assistente (injetável p/ teste). null ⇒ [AIService.assistantTurn].
  final AssistantTurnFn? assistantTurn;

  /// Memória textual curta do Assistente. null ⇒ totalmente in-memory.
  /// Só é consultada/gravada quando [assistEnabled] está ligado.
  final AssistantContextStore? assistantContextStore;

  /// Monta o grounding (lacunas + inventário compacto, SEM PII) pro assistente.
  /// null ⇒ contexto vazio (o assistente ainda responde/conduz, só sem
  /// personalizar tanto).
  final Future<Map<String, dynamic>> Function()? assistContextLoader;

  /// Passos reais de uma seção pra "quero preencher X" — o app liga com os
  /// searchers (cidade/instituição/skills). Recebe o nome da seção (LacunaKey
  /// em snake). Vazio/null ⇒ sem handoff (cai em conversa).
  final List<ConversationStep> Function(String section)? assistSectionSteps;

  /// Fase B: lê o valor atual de um campo (pro diff/undo). null ⇒ sem mutação.
  final AssistFieldReader? assistReadField;

  /// Fase B: aplica um valor a um campo (reusa o write-back). null ⇒ sem mutação.
  /// Gate 3.0H: 3º arg = valor observado no propose (CAS server-side).
  final AssistCasWriter? assistWriteField;

  /// Fase B: adiciona um item de lista (kind, value) — ex.: skill/idioma (merge).
  final AssistFieldWriter? assistItemAdder;

  /// Fase B: remove um item de lista (kind, value) — destrutivo.
  final AssistFieldWriter? assistItemRemover;

  /// Fase B: resolve "qual item" pra remover — (kind, query) → nomes que casam
  /// (0 ⇒ não achou; 1 ⇒ segue; 2+ ⇒ desambigua).
  final Future<List<String>> Function(String kind, String query)?
  assistItemResolver;

  /// Fase B: lê um bullet por id (pro diff/undo). raw/text = o texto atual;
  /// label = a experiência ("Ambev"). null ⇒ id inválido.
  final AssistFieldReader? assistBulletReader;

  /// Fase B: reescreve um bullet (bulletId, novo texto). Undo regrava o antigo.
  /// Gate 3.0H: 3º arg = texto observado no propose (CAS server-side).
  final AssistCasWriter? assistBulletWriter;

  /// Fase B: remoção REVERSÍVEL de item multi-campo (experiência/projeto):
  /// captura o registro, deleta, e devolve um restore (pro undo re-inserir).
  /// null / retorno null ⇒ cai no remover simples (skill/idioma). (kind, value).
  final Future<Future<void> Function()?> Function(String kind, String value)?
  assistReversibleRemover;

  /// Fase C (proativo): a maior lacuna que resta — `{section, label}` — pra o
  /// assistente SUGERIR o próximo ganho ao concluir. null ⇒ sem sugestão.
  final Future<Map<String, String>?> Function()? assistProactiveLoader;

  /// Leitura legada de skills. O editor seguro não usa este snapshot como
  /// baseline: a fotografia autoritativa é reservada por [assistSkillsWriter].
  final Future<List<String>> Function()? assistSkillsLoader;

  /// Writer atômico/CAS exclusivo do editor visual de skills. O UUID do card
  /// é reaproveitado em retries; apply e undo retornam recibos do servidor.
  final AssistSkillsWriter? assistSkillsWriter;

  /// Editor visual de skills: sugestões pra adicionar (pela área), best-effort.
  final Future<List<String>> Function()? assistSkillSuggester;

  /// Editor visual de interesses: nomes atuais. null/vazio ⇒ cai na coleta.
  final Future<List<String>> Function()? assistInterestsLoader;

  /// Editor visual de interesses: grava a lista FINAL (replace-all).
  final Future<void> Function(List<String>)? assistInterestsReplacer;

  /// Editor visual de ÁREAS: áreas visíveis atuais (user_added).
  final Future<List<String>> Function()? assistAreasLoader;

  /// Editor visual de ÁREAS: grava a lista FINAL (replace-all + canônica oculta).
  final Future<void> Function(List<String>)? assistAreasReplacer;

  /// Editor visual de idiomas: pares (nome, nível-canônico) atuais.
  final Future<List<(String, String?)>> Function()? assistLanguagesLoader;

  /// Editor visual de idiomas: upsert de um idioma (nome, nível-canônico|null).
  final Future<void> Function(String name, String? level)?
  assistLanguageUpserter;

  /// Editar CAMPO de item multi-campo: lê o valor atual de um campo (resolve o
  /// item pela query). Retorna {id, raw, text, label}; null ⇒ não achou/campo
  /// inválido pro kind.
  final Future<Map<String, String>?> Function(
    String kind,
    String query,
    String field,
  )?
  assistItemFieldReader;

  /// Editar CAMPO de item multi-campo: grava o campo do item (por id, estável).
  /// Gate 3.0H: 5º arg = valor observado no propose (CAS server-side).
  final Future<void> Function(
    String kind,
    String id,
    String field,
    String value,
    String expected,
  )?
  assistItemFieldWriter;

  /// Grande: consulta o feed real de vagas (cliente lê o JobsViewModel). null ⇒
  /// o assistente não lista vagas (cai numa resposta de texto).
  final AssistJobsLoader? assistJobsLoader;

  /// Grande: troca de aba do app (tabKey pt-BR/en → índice). null ⇒ no-op.
  final Future<void> Function(String tabKey)? assistOpenTab;

  /// Grande: leva pra biblioteca de currículos (aba Perfil → sub-aba
  /// Currículos), onde o CV importado fica salvo. Distinto do assistOpenTab
  /// genérico pra não forçar a sub-aba em toda navegação pro Perfil.
  final Future<void> Function()? assistOpenCvLibrary;

  /// Grande: exporta o currículo em PDF (reusa o _export da aba). Devolve o
  /// desfecho real (vazio/falha/ok) pro assistente não mentir sucesso. null ⇒
  /// não exporta.
  final Future<AssistExportOutcome> Function()? assistExportPdf;

  /// Grande: importa um CV (abre o seletor de arquivo, salva, dispara extração
  /// async). Em background — a conversa NÃO reinicia; o preview atualiza sozinho
  /// quando a extração cai. null ⇒ não importa.
  final Future<AssistImportResult> Function()? assistImportCv;

  /// Grande: lacunas do perfil (% + o que falta) pro card estruturado de
  /// show_gaps/show_profile_summary. null ⇒ cai na resposta de texto.
  final Future<AssistGaps> Function()? assistGapsLoader;

  /// LEGADO (congelado, R6): aplicava UMA linha por vez (sem atomicidade nem
  /// agregado honesto). Não é mais usado pelo `applyConflicts` (Gate 3.0I) —
  /// substituído pelo applier em lote abaixo. Mantido injetável pra não quebrar
  /// callers; pode sair num gate futuro de limpeza.
  final Future<Future<void> Function()?> Function(
    ConflictRow row,
    String value,
  )?
  assistConflictApplier;

  /// Gate 3.0I — aplica o LOTE revisado numa transação atômica via
  /// `apply_reviewed_conflicts_and_promote(candidateId, attemptId, choices)` e
  /// devolve o agregado cru do RPC (`{applied,stale,rejected,failed,promoted}`).
  /// null ⇒ não aplica (card vira cancelado). É a fonte do resultado HONESTO —
  /// nunca "aplicado" cego numa falha parcial.
  final Future<Map<String, dynamic>?> Function(
    String candidateId,
    String attemptId,
    List<Map<String, dynamic>> choices,
  )?
  assistReviewedConflictApplier;

  /// Gate 3.0I — desfaz um import JÁ aplicado, restaurando o snapshot pré-apply
  /// via `revert_reviewed_apply(candidateId, attemptId)`. Devolve true só se
  /// reverteu de verdade. null ⇒ sem reversão disponível → o card NÃO oferece
  /// "Desfazer" (sem falso affordance).
  final Future<bool> Function(String candidateId, String attemptId)?
  assistReviewedConflictReverter;

  /// O card só mostra "Desfazer" quando há reversão real fiada.
  bool get canRevertConflicts => assistReviewedConflictReverter != null;

  /// Card de vagas: abre o DETALHE de uma vaga (por id). null ⇒ não abre.
  final Future<void> Function(String jobId)? assistOpenJobDetail;

  /// Card de vagas: SALVA uma vaga (vai pra Vagas Salvas). Devolve true SÓ se
  /// persistiu de verdade (a vaga sumiu / já swipada / rede caiu ⇒ false, pra o
  /// card não mentir "salva"). null ⇒ não salva.
  final Future<bool> Function(String jobId)? assistSaveJob;

  /// Card de vagas: DES-SALVA uma vaga (tira de Vagas Salvas). Devolve true se
  /// removeu de fato. null ⇒ não des-salva.
  final Future<bool> Function(String jobId)? assistUnsaveJob;

  /// Chamado após uma edição in-place de card respondido (✏️) gravar — pra o
  /// preview da aba Currículo recarregar. As edições do assistente já recarregam
  /// pelos próprios writers; isto cobre o lápis (que grava via saveAnswer).
  final VoidCallback? onProfileEdited;

  /// Avisa o host que a BIBLIOTECA DE DOCUMENTOS mudou (`saved_resumes`) — não
  /// os fatos do perfil.
  ///
  /// E1 do device-test (24/07), 3ª instância do Bloqueador A: no fluxo novo de
  /// import a linha nasce SERVER-SIDE (`begin_import_source`, via
  /// `import_review_coordinator.dart:95`), e o card "Fonte importada" em
  /// Perfil → Dados lê `ProfileViewModel.savedResumes` — que ninguém
  /// recarregava. O card seguia dizendo "Nenhum currículo importado" com a
  /// linha já no banco. O caminho de REMOÇÃO recarregava; o de import, não.
  ///
  /// Canal separado de [onProfileEdited] de propósito: são invalidações de
  /// coisas diferentes (documentos × fatos) e com frequências muito diferentes
  /// — a coleta guiada dispara `onProfileEdited` a cada passo, e recarregar a
  /// biblioteca junto seria fetch desnecessário.
  final VoidCallback? onDocumentsChanged;

  /// Cadência do poll da extração (injetável p/ teste encurtar). ~60s = 40×1.5s.
  final Duration pollInterval;
  final int maxPolls;

  TrilhaSession? _session;
  ConversationController? get _conv => _session?.controller;

  /// Ledger separado do [thread]: contém apenas turnos livres completos
  /// user↔assistant. Cards, ferramentas e respostas guiadas nunca entram aqui.
  final List<AssistantContextTurn> _assistantTurns = [];

  ChatPhase phase = ChatPhase.gate;
  final List<ChatItem> thread = [];
  bool typing = false;
  bool inputVisible = false;
  bool finished = false;
  bool finalizing = false;
  bool awaitingImportConfirm = false;
  String? generatedSummary;

  /// Trava de reentrância: enquanto uma submissão (toque/texto/edição) está em
  /// voo, ignora novas — senão dois envios paralelos duplicam card e re-revelam.
  bool _busy = false;

  int? editingIndex;
  ConversationStep? _editingStep;
  ConversationExchange? _editingExchange;

  /// Na VOLTA (abertura adaptativa), a saudação de retorno — msg1 reconhece o
  /// que já existe + msg2 convida a completar — já diz o "vamos lá". Então o
  /// passo de abertura ('intro') entra só com o CTA, sem repetir a bolha de
  /// saudação (que soa como "começando agora"). Vale só pra 1ª revelação.
  bool _suppressIntroGreeting = false;

  ConversationStep? get activeStep => _editingStep ?? _conv?.current;
  bool get isEditing => _editingStep != null;
  int get answeredCount => _conv?.answeredCount ?? 0;
  List<ConversationExchange> get history => _conv?.history ?? const [];
  ConversationStep? get currentStep => _conv?.current;
  StepAnswer? get retryAnswer => _conv?.retryAnswer;
  int get totalSteps => _conv?.totalSteps ?? 0;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Abertura: gate de import ────────────────────────────────────────────────

  Future<void> start() async {
    // Descobre o que o perfil já tem pra escolher a abertura. Enquanto decide,
    // fica em `converse`+typing (neutro) — o gate só renderiza em phase==gate,
    // então não pisca os botões durante a decisão.
    phase = ChatPhase.converse;
    typing = true;
    _notify();
    if (assistEnabled && await _restoreAssistantContext()) return;
    if (_disposed) return;
    List<String> filled = const [];
    try {
      filled = (await preFilledLoader?.call()) ?? const [];
    } catch (_) {
      filled = const []; // failure-safe: cai no gate padrão
    }
    if (_disposed) return;
    if (assistEnabled) {
      // Copiloto ligado: abre com saudação + chips de partida (descoberta de
      // capacidades) em vez do gate/coleta automática. Os chips SÃO as portas
      // (preencher o perfil / achar vaga / ver o que falta).
      await _startAssistChips(hasData: filled.isNotEmpty);
    } else if (filled.isEmpty) {
      await _startGate();
    } else {
      await _startAdaptive(filled);
    }
  }

  /// Abertura do copiloto (assistente ON): saudação que nomeia os 3 mundos
  /// (currículo · vagas · carreira) + chips tocáveis. Dissolve o gate — quem
  /// escolhe o caminho é o usuário, e de quebra descobre a amplitude do agente.
  Future<void> _startAssistChips({required bool hasData}) async {
    phase = ChatPhase.converse;
    inputVisible = true;
    // Se depois tocar "Montar do zero", o _enterConverse não repete a saudação.
    _suppressIntroGreeting = true;
    typing = true;
    _notify();
    const msg1 = 'Oi! 👋 Sou seu copiloto de carreira aqui no Stage ✦';
    await Future.delayed(_typingFor(msg1));
    if (_disposed) return;
    typing = false;
    thread.add(const AiMsgItem(msg1));
    _notify();
    await Future.delayed(_pauseFor(msg1));
    if (_disposed) return;
    typing = true;
    _notify();
    const msg2 =
        'Eu construo seu perfil, acho vagas com a sua cara e mostro o que você '
        'pode fortalecer. Toca numa 👇';
    await Future.delayed(_typingFor(msg2));
    if (_disposed) return;
    typing = false;
    thread.add(const AiMsgItem(msg2));
    final chips = hasData ? _starterChipsHasData : _starterChipsEmpty;
    thread.add(StarterChipsItem(chips));
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistStarterShown,
      props: {'has_data': hasData, 'count': chips.length},
    );
    _notify();
  }

  static const List<StarterChip> _starterChipsEmpty = [
    StarterChip(
      id: 'zero',
      label: 'Preencher meu perfil',
      hero: true,
      action: StarterChipAction.startZero,
    ),
    StarterChip(
      id: 'jobs',
      label: 'Tem vaga de marketing?',
      message: 'tem vaga de marketing?',
    ),
    StarterChip(
      id: 'gaps',
      label: 'O que falta no meu perfil?',
      message: 'o que falta no meu perfil?',
    ),
    StarterChip(
      id: 'capabilities',
      label: 'Tudo que eu faço',
      message: 'o que você consegue fazer?',
    ),
  ];

  static const List<StarterChip> _starterChipsHasData = [
    StarterChip(
      id: 'summary',
      label: 'Melhorar meu resumo',
      hero: true,
      message: 'melhora meu resumo',
    ),
    StarterChip(
      id: 'jobs',
      label: 'Quais vagas combinam comigo?',
      message: 'quais vagas combinam comigo?',
    ),
    StarterChip(
      id: 'gaps',
      label: 'O que falta no meu perfil?',
      message: 'o que falta no meu perfil?',
    ),
    StarterChip(
      id: 'exp',
      label: 'Adicionar experiência',
      message: 'quero adicionar uma experiência',
    ),
    StarterChip(
      id: 'capabilities',
      label: 'Tudo que eu faço',
      message: 'o que você consegue fazer?',
    ),
  ];

  /// A vitrine "No que eu te ajudo" (bottom sheet do ✦ da barra) foi aberta —
  /// o acesso PERMANENTE à descoberta (os chips de partida são uso único).
  void trackCapabilitiesOpened() {
    Analytics.shared.track(
      evTrilhaAssistStarterTapped,
      props: {'chip_id': 'capabilities_sheet'},
    );
  }

  /// Toque num chip de partida: some a vitrine + roda a ação (reusa o assistente
  /// via submitFreeText, ou entra na coleta pra "Montar do zero").
  Future<void> onStarterChip(StarterChip chip) async {
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistStarterTapped,
      props: {'chip_id': chip.id},
    );
    thread.removeWhere((it) => it is StarterChipsItem); // uso único
    _notify();
    if (chip.action == StarterChipAction.startZero) {
      await _enterConverse();
    } else {
      await submitFreeText(chip.message);
    }
  }

  /// Perfil vazio: abertura padrão + gate "começar do zero / já tenho currículo".
  Future<void> _startGate() async {
    phase = ChatPhase.gate;
    typing = true;
    _notify();
    const msg1 = 'Oi! Vou te ajudar a construir seu perfil profissional.';
    await Future.delayed(_typingFor(msg1));
    if (_disposed) return;
    typing = false;
    thread.add(const AiMsgItem(msg1));
    _notify();
    await Future.delayed(_pauseFor(msg1));
    if (_disposed) return;
    thread.add(
      const AiMsgItem(
        'Como prefere começar? Você pode subir um currículo que já tem ou preencher seu perfil passo a passo.',
      ),
    );
    _notify();
    // A view mostra o widget de escolha do gate enquanto phase == gate.
  }

  /// Perfil já tem dado: reconhece o que existe e vai DIRETO completar o que
  /// falta (pula o gate de import — não faz sentido oferecer "começar do zero").
  Future<void> _startAdaptive(List<String> filled) async {
    phase = ChatPhase.converse; // sem gate
    // A saudação de retorno abaixo (msg1 + msg2) já dá as boas-vindas e convida
    // — então o passo de abertura não repete a saudação genérica (só o CTA).
    _suppressIntroGreeting = true;
    typing = true;
    _notify();
    final msg1 = 'Oi! Vi que você já tem ${_humanJoin(filled)} no seu perfil.';
    await Future.delayed(_typingFor(msg1));
    if (_disposed) return;
    typing = false;
    thread.add(AiMsgItem(msg1));
    _notify();
    await Future.delayed(_pauseFor(msg1));
    if (_disposed) return;
    typing = true;
    _notify();
    const msg2 = 'Bora completar o que falta no seu perfil?';
    await Future.delayed(_typingFor(msg2));
    if (_disposed) return;
    typing = false;
    thread.add(const AiMsgItem(msg2));
    _notify();
    await Future.delayed(_pauseFor(msg2));
    if (_disposed) return;
    await _enterConverse(); // monta a sessão (só as lacunas) e revela o 1º passo
  }

  /// Junta rótulos numa lista natural pt-BR: [a] → "a"; [a,b] → "a e b";
  /// [a,b,c] → "a, b e c".
  static String _humanJoin(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} e ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')} e ${items.last}';
  }

  /// "Começar do zero" → vai direto pra conversa.
  Future<void> chooseZero() async {
    if (phase != ChatPhase.gate) return;
    await _enterConverse();
  }

  /// Chamado pela view após o PDF ser escolhido. Só vale a partir do GATE — não
  /// dá pra re-importar no meio da conversa (reconstruir a sessão perderia o
  /// progresso). [extractionExpected]=false quando o PDF foi salvo mas o texto
  /// veio inutilizável (a extração nem roda) → pula o poll e cai na conversa.
  Future<void> onCvUploaded(
    String fileName, {
    bool extractionExpected = true,
  }) async {
    if (phase != ChatPhase.gate) {
      return; // só do gate; barra re-import e reentrância
    }
    thread.add(FileBubbleItem(fileName));
    phase = ChatPhase.importing;
    typing = true;
    thread.add(const AiMsgItem('Lendo seu currículo…'));
    _notify();

    final summary = extractionExpected ? await _pollExtraction() : null;
    if (_disposed) return;
    typing = false;

    if (summary == null || summary.isEmpty) {
      // Failure-safe (lição T6.2): nunca marca completo calado — cai na conversa.
      thread.add(
        const AiMsgItem(
          'Não consegui ler tudo agora — vamos completando pela conversa.',
        ),
      );
      _notify();
      await _enterConverse();
      return;
    }
    thread.add(ImportSummaryItem(summary));
    awaitingImportConfirm = true;
    _notify();
    // Espera o "Revisar e confirmar" (confirmImport()).
  }

  /// Confirma o resumo da extração → recomputa as lacunas e segue.
  Future<void> confirmImport() async {
    if (!awaitingImportConfirm) return;
    awaitingImportConfirm = false;
    _notify();
    await _enterConverse();
  }

  /// Poll do snapshot até a extração (fire-and-forget) concluir. ~60s (40×1.5s).
  ///
  /// Pronto = `last_extracted_at` AVANÇOU (sinal explícito de extração concluída
  /// — `save_profile_from_json` sempre o seta) OU os counts cresceram. NÃO basta
  /// crescer: pra perfil pré-existente a RPC pula INSERT em tabela já populada
  /// (counts ficam iguais), então sem o timestamp daria falso timeout de 60s.
  Future<ImportSummary?> _pollExtraction() async {
    final svc = snapshotService ?? ProfileSnapshotService();
    DateTime? baseAt;
    int baseTotal = 0;
    try {
      final base = await svc.loadSnapshot(userId);
      baseAt = base.personal?.lastExtractedAt;
      baseTotal = _total(base);
    } catch (_) {
      /* baseline assume vazio */
    }
    for (var i = 0; i < maxPolls; i++) {
      await Future.delayed(pollInterval);
      if (_disposed) return null;
      try {
        final s = await svc.loadSnapshot(userId);
        final at = s.personal?.lastExtractedAt;
        final extracted = at != null && (baseAt == null || at.isAfter(baseAt));
        if (extracted || _total(s) > baseTotal) {
          return ImportSummary(
            experiences: s.experiences.length,
            skills: s.skills.length,
            languages: s.languages.length,
            education: s.education.length,
          );
        }
      } catch (_) {
        /* tenta de novo */
      }
    }
    return null; // timeout — extração não concluiu
  }

  int _total(ProfileSnapshot s) =>
      s.experiences.length +
      s.skills.length +
      s.languages.length +
      s.education.length;

  // ── Converse: monta a sessão + revela ───────────────────────────────────────

  Future<void> _enterConverse() async {
    // Idempotente + anti-duplo-toque: sem o guard _busy, dois toques rápidos em
    // "Montar do zero" (o removeWhere+notify só some o chip no próximo frame)
    // veriam ambos _session==null e montariam DUAS sessões (intro/passo
    // duplicados). Nenhum caller de _enterConverse segura _busy — safe.
    if (_session != null || _busy) return;
    _busy = true;
    try {
      phase = ChatPhase.converse;
      typing = true; // feedback enquanto monta a sessão (sem fio "pelado")
      _notify();
      final session = await sessionBuilder(userId);
      if (_disposed) return;
      _session = session;
      onStarted?.call(totalSteps);
      await _reveal();
    } finally {
      _busy = false;
    }
  }

  Future<void> _reveal() async {
    final step = _conv?.current;
    if (step == null) {
      _onDone();
      return;
    }
    // Na volta, a saudação do passo de abertura ('intro') repetiria o que a
    // msg1+msg2 já disseram → revela o passo direto (só o CTA "Bora começar"),
    // sem bolha nem "typing". Vale uma vez só (a flag zera aqui).
    final skipGreeting = _suppressIntroGreeting && step.id == 'intro';
    _suppressIntroGreeting = false;
    if (skipGreeting) {
      typing = false;
      inputVisible = true;
      _notify();
      return;
    }
    typing = true;
    inputVisible = false;
    _notify();
    await Future.delayed(
      _typingFor(step.aiMessages.isNotEmpty ? step.aiMessages.first : ''),
    );
    if (_disposed) return;
    typing = false;
    for (final m in step.aiMessages) {
      thread.add(AiMsgItem(m));
      _notify();
      await Future.delayed(_pauseFor(m));
      if (_disposed) return;
    }
    inputVisible = true;
    _notify();
  }

  /// Entrada pública (toque num widget inline). Protegida por [_busy].
  Future<void> submit(StepAnswer answer) async {
    if (_busy) return;
    _busy = true;
    try {
      await _doSubmit(answer);
    } finally {
      _busy = false;
    }
  }

  Future<void> _doSubmit(StepAnswer answer) async {
    if (_editingStep != null) {
      final changed = await _applyEdit(answer);
      // O lápis grava via saveAnswer (fora dos writers do assistente) → avisa o
      // host pra recarregar os consumidores do perfil somente após sucesso.
      if (changed) onProfileEdited?.call();
      return;
    }
    final conv = _conv;
    if (conv == null) return;
    final step = conv.current;
    if (step == null) return;
    inputVisible = false;
    _notify();

    final before = conv.answeredCount;
    final submitResult = await conv.submit(answer);
    if (_disposed) return;
    if (submitResult == ConversationSubmitResult.writeFailed) {
      thread.add(
        AiMsgItem('Não consegui salvar essa resposta agora 😕 Tenta de novo.'),
      );
      inputVisible = conv.current != null;
      _notify();
      return;
    }
    // Defesa: se a submissão não avançou (stepId stale / writeback em voo), NÃO
    // duplica o card nem re-revela — só restaura o input do passo corrente.
    if (conv.answeredCount <= before) {
      inputVisible = conv.current != null;
      _notify();
      return;
    }
    // Bloqueador A do device-test (24/07): a COLETA GUIADA grava em profile_*
    // via TrilhaWriteback, fora do ProfileEditorViewModel — e nada invalidava
    // quem a UI lê. O usuário via "✓ Adicionei ao seu perfil" e, em Perfil →
    // Dados, "Experiência profissional (0)" até o cold start.
    //
    // Aqui os dois guards acima já passaram: a escrita NÃO falhou (:1217) e a
    // conversa realmente avançou (:1227). Só então avisamos — falha nunca vira
    // invalidação, e invalidação nunca vira falso sucesso (regra 5 do handoff).
    //
    // Sem gate de flag (decisão 3 do fundador, 26/07): `trilha_coleta_v1` está
    // ON/100 em prod e a trilha roda sem `trilha_assist_v1`, então gatear
    // deixaria o defeito vivo para quem já usa hoje. Mesmo padrão do lápis
    // (:1204) e do host, que já chama `_scheduleProfileReload` sem condição.
    onProfileEdited?.call();
    thread.add(AnsweredItem(conv.history.last));
    _notify();

    // Recap dinâmico (a IA mostra o que anotou) tem prioridade sobre o ack fixo.
    final ack =
        step.recap?.call([for (final e in conv.history) e.answer]) ??
        step.acknowledgement;
    if (ack != null && ack.trim().isNotEmpty) {
      typing = true;
      _notify();
      await Future.delayed(_typingFor(ack));
      if (_disposed) return;
      typing = false;
      thread.add(AiMsgItem(ack));
      _notify();
      await Future.delayed(_pauseFor(ack));
      if (_disposed) return;
    }
    await _reveal();
  }

  /// Texto livre da barra de baixo. Com o assistente OFF (flag): comportamento
  /// de HOJE — passo de TEXTO responde direto; ESCOLHA passa pela interpretação
  /// por IA; sem passo aberto, ignora. Com o assistente ON: roteia por intenção
  /// (atalho local barato → IA), podendo responder, conduzir uma seção ou (Fase
  /// B) alterar. Failure-safe: erro/timeout cai no fluxo roteirizado.
  Future<void> submitFreeText(String text) async {
    if (_busy) return;
    final t = text.trim();
    if (t.isEmpty) return;
    // Engajou (digitou/enviou) → some a vitrine de chips de partida (uso único).
    // O toque num chip já remove; aqui cobre quem DIGITA em vez de tocar (senão
    // os chips ficavam pendurados no fio pra sempre).
    if (thread.any((it) => it is StarterChipsItem)) {
      thread.removeWhere((it) => it is StarterChipsItem);
    }
    final step = activeStep;

    // "não sei"/"sla"/"passa" num passo de TEXTO NUNCA é resposta — não grava
    // literal (poluiria cargo/empresa/curso). Opcional ⇒ pula; senão ⇒
    // repergunta com jeito. Vale com o assistente ON ou OFF, sem gastar IA.
    if (step != null &&
        step.input is GuidedTextInput &&
        _looksLikeNonAnswer(t)) {
      _busy = true;
      try {
        if (_stepIsOptional(step)) {
          _pushAi('Sem problema, vou pular essa 🙂');
          await _doSubmit(
            StepAnswer(stepId: step.id, value: '', displayText: 'Pular'),
          );
        } else {
          _pushAi(
            'Tranquilo não saber! Me dá qualquer coisa que vier à cabeça '
            '— dá pra ajustar depois.',
          );
        }
      } finally {
        _busy = false;
      }
      return;
    }

    // Assistente OFF → comportamento de hoje (responder o passo aberto).
    if (!assistEnabled) {
      if (step == null) {
        // Sem passo aberto e sem assistente não há o que responder — mas NÃO
        // engolir a mensagem em silêncio (o botão parecia morto: sumia o texto
        // e baixava o teclado). Mostra o que a pessoa disse e ensina a editar o
        // que já está preenchido.
        thread.add(UserMsgItem(t));
        _pushAi(
          'Pra mudar algo que você já preencheu, é só tocar na seção lá '
          'em cima 👆 (ou no ✏️ de uma resposta).',
        );
        return;
      }
      _busy = true;
      try {
        await _routeToStep(step, t);
      } finally {
        _busy = false;
      }
      return;
    }

    _busy = true;
    try {
      // Fase C (proativo): acabei de SUGERIR uma seção e a pessoa topou ("quero",
      // "bora") → entra direto nela, sem gastar uma chamada de IA.
      final suggested = _suggestedSection;
      _suggestedSection = null;
      if (suggested != null && _isAffirmative(t)) {
        thread.add(UserMsgItem(t));
        _notify();
        final ok = await _injectSection(suggested, 'Boa, bora! 👇');
        if (!ok) _pushAi('Beleza! O que você quer preencher?');
        return;
      }

      // Nível 0 — atalho local (sem IA): passo de TEXTO aberto + mensagem sem
      // cara de comando ⇒ resposta direta (custo/latência zero, = hoje). Um
      // textão colado (várias infos) NÃO é resposta do passo — vai pra IA.
      if (step != null &&
          step.input is GuidedTextInput &&
          !_looksLikeCommand(t) &&
          !_looksLikePaste(t)) {
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistMessageSent,
          props: {
            'char_count': t.length,
            'has_active_step': true,
            'route': 'fast_lane',
          },
        );
        await _doSubmit(StepAnswer.text(step.id, t));
        return;
      }
      // Nível 1 — a IA roteia.
      await _runAssistant(t, step);
    } finally {
      _busy = false;
    }
  }

  /// Comportamento roteirizado de hoje (assistente OFF ou fallback).
  Future<void> _routeToStep(ConversationStep step, String t) async {
    final input = step.input;
    if (input is GuidedTextInput) {
      await _doSubmit(StepAnswer.text(step.id, t));
      return;
    }
    if (input is ChoiceInput) {
      await _interpretChoice(step, input, t);
      return;
    }
    // Mês/ano e typeahead (cidade/instituição) precisam do widget.
    _pushAi('Pra essa aqui, toca numa das opções acima 🙂');
  }

  // ── Assistente: roteia a mensagem por intenção e executa a ferramenta ──────

  Future<void> _runAssistant(String message, ConversationStep? step) async {
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistMessageSent,
      props: {
        'char_count': message.length,
        'has_active_step': step != null,
        'route': 'assistant',
      },
    );
    // O histórico é fechado ANTES de inserir a mensagem atual. Assim ela vai
    // uma vez no campo `message`, nunca duplicada dentro de `history`.
    final history = _assistantHistory();
    // Mostra a fala do usuário no fio (respostas de passo já viram card).
    thread.add(UserMsgItem(message));
    final responseStartIndex = thread.length;
    inputVisible = false;
    typing = true;
    _notify();

    Map<String, dynamic> context = const {};
    try {
      context = await assistContextLoader?.call() ?? const {};
    } catch (_) {
      /* grounding é best-effort */
    }
    if (_disposed) return;

    final fn = assistantTurn ?? AIService().assistantTurn;
    AssistantTurn? turn;
    try {
      turn = await fn(
        message: message,
        openStep: step == null ? null : _serializeStep(step),
        context: context,
        history: history,
      );
    } catch (_) {
      turn = null;
    }
    if (_disposed) return;
    typing = false;

    if (turn == null) {
      // Failure-safe: sem re-chamar IA. Passo aberto ⇒ mantém o widget; senão
      // ⇒ nota gentil.
      // ignore: unawaited_futures
      Analytics.shared.track(evTrilhaAssistError, props: {'stage': 'classify'});
      if (step != null) {
        inputVisible = true;
        _pushAi(
          'Não peguei bem 🤔 Toca numa opção aí em cima, ou tenta de outro jeito.',
        );
      } else {
        _pushAi('Não consegui agora 🤔 Tenta de novo daqui a pouco.');
      }
      _notify();
      return;
    }

    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistIntentClassified,
      props: {
        'intent': turn.tool,
        'tool': turn.tool,
        'prompt_version': turn.promptVersion,
      },
    );
    await _executeTool(turn, step);

    // Persiste apenas se a resposta textual retornada pela edge foi realmente
    // exibida e a ferramenta terminou sem lançar. Falhas locais, cards sem fala
    // e estados pending/running/undo não viram memória.
    final expectedReply = turn.reply.trim();
    const memorySafeTools = {'answer_question', 'clarify', 'out_of_scope'};
    if (step == null &&
        memorySafeTools.contains(turn.tool) &&
        expectedReply.isNotEmpty) {
      final renderedReply = thread
          .skip(responseStartIndex)
          .whereType<AiMsgItem>()
          .map((item) => item.text.trim())
          .where((text) => text == expectedReply)
          .firstOrNull;
      if (renderedReply != null) {
        await _rememberAssistantTurn(message, renderedReply);
      }
    }
  }

  Future<void> _executeTool(AssistantTurn turn, ConversationStep? step) async {
    final reply = turn.reply.trim();
    switch (turn.tool) {
      case 'answer_current_step':
        await _applyAnswerCurrentStep(turn, step);
        return;
      case 'start_section':
        await _handleStartSection(turn, step);
        return;
      case 'update_field':
        await _proposeUpdateField(turn, step);
        return;
      case 'update_item':
        await _proposeUpdateItem(turn, step);
        return;
      case 'add_item':
        await _proposeAddItem(turn, step);
        return;
      case 'remove_item':
        await _proposeRemoveItem(turn, step);
        return;
      case 'rewrite_summary':
        await _proposeRewriteSummary(turn, step);
        return;
      case 'improve_bullet':
        await _proposeImproveBullet(turn, step);
        return;
      case 'extract_profile':
        await _proposeExtract(turn, step);
        return;
      case 'edit_skills':
        await _proposeListEditor('skill', turn);
        return;
      case 'edit_interests':
        await _proposeListEditor('interest', turn);
        return;
      case 'edit_areas':
        await _proposeListEditor('area', turn);
        return;
      case 'edit_languages':
        await _proposeLanguagesEditor(turn);
        return;
      case 'skip_step':
        if (step != null && _stepIsOptional(step)) {
          if (reply.isNotEmpty) _pushAi(reply);
          await _doSubmit(
            StepAnswer(stepId: step.id, value: '', displayText: 'Pular'),
          );
        } else {
          _pushAi(reply.isEmpty ? 'Essa aqui não dá pra pular 🙂' : reply);
          if (step != null) inputVisible = true;
          _notify();
        }
        return;
      case 'out_of_scope':
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistOutOfScope,
          props: {'category': turn.args['category']?.toString() ?? 'other'},
        );
        _replyAndKeepStep(reply, step);
        return;
      case 'clarify':
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistClarifyRequested,
          props: {'reason': 'ambiguous'},
        );
        _replyAndKeepStep(reply, step);
        return;
      case 'show_jobs':
        await _handleShowJobs(turn, step);
        return;
      case 'open_tab':
        await _handleOpenTab(turn, step);
        return;
      case 'export_pdf':
        await _handleExportPdf(turn, step);
        return;
      case 'import_cv':
        await _handleImportCv(turn, step);
        return;
      case 'show_gaps':
      case 'show_profile_summary':
        await _handleShowGaps(turn, step);
        return;
      case 'answer_question':
      case 'explain_step':
      default:
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistAnswerReturned,
          props: {'grounded_in': 'llm', 'used_llm': true},
        );
        _replyAndKeepStep(reply, step);
        return;
    }
  }

  /// Empurra a fala e, se há passo aberto, re-exibe o widget (a conversa segue).
  void _replyAndKeepStep(String reply, ConversationStep? step) {
    if (reply.isNotEmpty) _pushAi(reply);
    if (step != null) inputVisible = true;
    _notify();
  }

  // ── Grandes: ações de app (vagas reais, navegar, exportar) ────────────────

  /// `show_jobs`: consulta o feed REAL (cliente lê o JobsViewModel via loader) e
  /// mostra as melhores vagas num card. Escopo = "vagas pra mim" (já filtradas
  /// pelo perfil). Sem loader/erro/vazio → responde por texto, sem card.
  Future<void> _handleShowJobs(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final loader = assistJobsLoader;
    final reply = turn.reply.trim();
    if (loader == null) {
      _replyAndKeepStep(reply, step);
      return;
    }
    final area = turn.args['area']?.toString().trim();
    final query = turn.args['query']?.toString().trim();
    final hasFilter =
        (area != null && area.isNotEmpty) ||
        (query != null && query.isNotEmpty);
    final filterTerm = (area != null && area.isNotEmpty) ? area : query;
    final rawLimit = int.tryParse(turn.args['limit']?.toString() ?? '') ?? 5;
    final limit = rawLimit.clamp(1, 8);
    // Resolver o match pode levar alguns segundos (feed frio) — mantém a bolha
    // de "digitando" enquanto busca, senão a tela parece travada.
    typing = true;
    _notify();
    AssistJobsResult res;
    try {
      res = await loader(
        area: (area == null || area.isEmpty) ? null : area,
        query: (query == null || query.isEmpty) ? null : query,
        limit: limit,
      );
    } catch (_) {
      if (_disposed) return;
      typing = false;
      _replyAndKeepStep(
        'Não consegui puxar as vagas agora 🤔 Tenta de novo daqui a pouco.',
        step,
      );
      return;
    }
    if (_disposed) return;
    typing = false;
    if (res.jobs.isEmpty) {
      // Ignora a fala da IA (ela assumia que haveria vagas) e é honesto. Se ele
      // filtrou por termo/área, diz que foi ESSE filtro que não bateu (não que
      // o perfil está ruim — o feed já vem filtrado pelo perfil dele).
      _pushAi(
        hasFilter
            ? 'Não achei vagas de "$filterTerm" no seu feed agora 🤔 Ajuste seus objetivos em Perfil → Objetivos ou os filtros desta busca em Vagas.'
            : 'Não achei vagas que batam com seu perfil agora 🤔 Ajuste seus objetivos em Perfil → Objetivos ou os filtros desta busca em Vagas.',
      );
      if (step != null) inputVisible = true;
      _notify();
      return;
    }
    if (reply.isNotEmpty) _pushAi(reply);
    thread.add(
      JobsCardItem(
        id: 'jobs_${_editSeq++}',
        jobs: res.jobs,
        hasResume: res.hasResume,
        outOfProfileArea: res.outOfProfileArea,
      ),
    );
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistActionUsed,
      props: {'action': 'show_jobs', 'count': res.jobs.length},
    );
    if (step != null) inputVisible = true;
    _notify();
  }

  /// `open_tab`: troca a aba do app (o app cumpre via callback). Confirma por
  /// bolha (a troca tira o user da tela do chat).
  Future<void> _handleOpenTab(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final tab = turn.args['tab']?.toString().trim() ?? '';
    final reply = turn.reply.trim();
    if (tab.isEmpty || assistOpenTab == null) {
      _replyAndKeepStep(reply, step);
      return;
    }
    if (reply.isNotEmpty) _pushAi(reply);
    try {
      await assistOpenTab!.call(tab);
    } catch (_) {
      /* best-effort */
    }
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistActionUsed,
      props: {'action': 'open_tab', 'tab': tab},
    );
    if (step != null) inputVisible = true;
    _notify();
  }

  /// `export_pdf`: mostra um CARD com botão "Exportar PDF" — a folha de
  /// compartilhar só abre quando o usuário toca no botão ([runActionCard]).
  Future<void> _handleExportPdf(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final reply = turn.reply.trim();
    if (assistExportPdf == null) {
      _replyAndKeepStep(reply, step);
      return;
    }
    // NÃO empurra a reply da IA: ela às vezes vem como confirmação PÓS-ação
    // ("Pronto!"), que contradiz o card (que ainda vai gerar no toque). O card
    // fala por si; o resultado pós-toque tem texto próprio.
    _pushActionCard('export');
    if (step != null) inputVisible = true;
    _notify();
  }

  /// Gate 3.0I — com o fluxo de revisão SEGURO fiado ([assistImportCv] != null:
  /// escolhe o PDF → reserva candidata → extrai nela → diffa → aplica atômico +
  /// promove), abre o card de ação "importar CV" (espelha o export). Sem o
  /// callback fiado (flag OFF / caminho legado), mantém a orientação segura de
  /// hoje — nunca abre o pipeline inseguro antigo.
  Future<void> _handleImportCv(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    if (assistImportCv == null) {
      _replyAndKeepStep(
        'A importação de CV pelo Assistente está temporariamente '
        'indisponível. Você ainda pode revisar e completar seus dados em '
        'Perfil → Dados.',
        step,
      );
      return;
    }
    // Não empurra a reply da IA (pode vir como confirmação pós-ação); o card
    // fala por si, e o resultado pós-toque tem texto próprio.
    _pushActionCard('import');
    if (step != null) inputVisible = true;
    _notify();
  }

  /// F5.4 — entrada EXTERNA de import (card "Fonte importada" em Perfil →
  /// Dados). Empurra o MESMO cartão de ação de import que o assistente já usa,
  /// para o usuário seguir pelo fluxo provado (revisar conflitos + desfazer).
  /// Não duplica o motor nem cria um segundo caminho de escrita. Idempotente
  /// por construção: se já houver um cartão de import pendente, não empilha
  /// outro (evita dois cartões após uma troca de aba com rebuild).
  void pushCvImportCard() {
    final hasPending = _pendingActions.values.any(
      (a) => a.kind == 'import' && a.status == AssistEditStatus.pending,
    );
    if (hasPending) return;
    _pushActionCard('import');
    _notify();
  }

  void _pushActionCard(String kind) {
    final id = 'act_${_editSeq++}';
    final item = AssistActionCardItem(id: id, kind: kind);
    _pendingActions[id] = item;
    thread.add(item);
  }

  /// Toque no botão do card de ação (export/import) → dispara a ação nativa.
  Future<void> runActionCard(String id) async {
    final item = _pendingActions[id];
    if (item == null ||
        item.status != AssistEditStatus.pending ||
        item.running) {
      return;
    }
    item.running = true;
    _notify();
    if (item.kind == 'export') {
      AssistExportOutcome outcome;
      try {
        outcome = await assistExportPdf?.call() ?? AssistExportOutcome.failed;
      } catch (_) {
        outcome = AssistExportOutcome.failed;
      }
      if (_disposed) return;
      item.running = false;
      switch (outcome) {
        case AssistExportOutcome.ok:
          item.resultMessage = 'Pronto! É só salvar ou compartilhar 👍';
          item.status = AssistEditStatus.applied;
          // ignore: unawaited_futures
          Analytics.shared.track(
            evTrilhaAssistActionUsed,
            props: {'action': 'export_pdf'},
          );
        case AssistExportOutcome.empty:
          item.resultMessage =
              'Seu perfil ainda não tem dados suficientes para gerar um currículo — bora completar um pouco primeiro? 🙂';
          item.status = AssistEditStatus.applied;
        case AssistExportOutcome.failed:
          // Mantém o botão pra tentar de novo.
          item.resultMessage = 'Deu um erro ao gerar o PDF 😕 Tenta de novo.';
      }
      _notify();
      return;
    }
    // import
    AssistImportResult res;
    try {
      res =
          await assistImportCv?.call() ??
          const AssistImportResult(AssistImportOutcome.failed);
    } catch (_) {
      res = const AssistImportResult(AssistImportOutcome.failed);
    }
    if (_disposed) return;
    item.running = false;
    switch (res.outcome) {
      case AssistImportOutcome.ok:
        item.status = AssistEditStatus.applied;
        item.resultMessage = res.message ?? 'Importei seu CV! 📄';
        // O PDF foi salvo na biblioteca (aba Perfil) em qualquer import ok —
        // oferece o atalho pra ver lá.
        item.showCvLibraryLink = true;
        // E1: a linha de saved_resumes já existe (nasceu server-side). Sem
        // este aviso, o card "Fonte importada" em Perfil → Dados continua
        // dizendo "Nenhum currículo importado" — e o atalho acima levaria a
        // uma tela que contradiz o recibo que acabamos de mostrar.
        onDocumentsChanged?.call();
        // Fail-closed (Gate 3.0I): só monta o card de revisão quando há uma
        // candidata reservada — sem candidate_id/attempt_id não há como aplicar
        // as escolhas depois (o RPC exige os dois). Sem eles, o import ok já
        // preencheu o que dava pelo caminho normal; não oferecemos revisão.
        if (res.conflicts.isNotEmpty &&
            res.candidateId.isNotEmpty &&
            res.attemptId.isNotEmpty) {
          final cid = 'conflict_${_editSeq++}';
          final citem = ImportConflictItem(
            id: cid,
            candidateId: res.candidateId,
            attemptId: res.attemptId,
            choices: [
              for (final r in res.conflicts)
                ConflictChoice(r, accepted: r.kind == ConflictKind.addition),
            ],
          );
          _pendingConflicts[cid] = citem;
          thread.add(citem);
        }
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistActionUsed,
          props: {'action': 'import_cv', 'conflicts': res.conflicts.length},
        );
      case AssistImportOutcome.cancelled:
        // Cancelou o seletor → volta o botão (pode escolher outro arquivo).
        item.resultMessage =
            'Beleza! Toca de novo quando quiser escolher o PDF.';
      case AssistImportOutcome.failed:
        item.resultMessage =
            res.message ??
            'Não consegui ler esse arquivo 😕 Tenta um PDF do seu currículo.';
    }
    _notify();
  }

  void cancelActionCard(String id) {
    final item = _pendingActions[id];
    if (item == null ||
        item.status != AssistEditStatus.pending ||
        item.running) {
      return; // não cancela no meio da ação (evita corrida com o resultado)
    }
    item.status = AssistEditStatus.cancelled;
    _notify();
  }

  /// Toque numa vaga do card → abre o detalhe.
  Future<void> openJobFromCard(String jobId) async {
    try {
      await assistOpenJobDetail?.call(jobId);
    } catch (_) {
      /* best-effort */
    }
  }

  /// Toque no bookmark de uma vaga do card → TOGGLE: salva se não estava, ou
  /// des-salva se já estava. Só muda o selo se a operação PERSISTIU (senão
  /// avisa, sem mentir).
  Future<void> saveJobFromCard(String cardId, String jobId) async {
    final alreadySaved = thread.whereType<JobsCardItem>().any(
      (it) => it.id == cardId && it.savedIds.contains(jobId),
    );
    if (alreadySaved) {
      bool ok;
      try {
        ok = await assistUnsaveJob?.call(jobId) ?? false;
      } catch (_) {
        ok = false;
      }
      if (_disposed) return;
      if (ok) {
        for (final it in thread) {
          if (it is JobsCardItem && it.id == cardId) it.savedIds.remove(jobId);
        }
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistActionUsed,
          props: {'action': 'unsave_job', 'via': 'jobs_card'},
        );
      } else {
        _pushAi(
          'Não consegui tirar essa vaga das salvas agora 🤔 Tenta de novo.',
        );
      }
      _notify();
      return;
    }
    var ok = false;
    try {
      ok = await assistSaveJob?.call(jobId) ?? false;
    } catch (_) {
      ok = false;
    }
    if (_disposed) return;
    if (ok) {
      for (final it in thread) {
        if (it is JobsCardItem && it.id == cardId) it.savedIds.add(jobId);
      }
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistActionUsed,
        props: {'action': 'save_job', 'via': 'jobs_card'},
      );
    } else {
      _pushAi('Não consegui salvar essa vaga agora 🤔 Tenta de novo.');
    }
    _notify();
  }

  /// Compatibilidade com cards antigos que ainda exibam a ação de área.
  /// O writer atual substitui a lista em mais de uma requisição; por isso o
  /// Assistente não o chama até existir persistência transacional.
  Future<void> addAreaFromCard(String cardId, String area) async {
    if (area.trim().isEmpty) return;
    _pushAi(
      'Para incluir $area nas suas buscas, ajuste suas áreas em '
      'Perfil → Objetivos.',
    );
  }

  /// Toque numa lacuna do card "Seu perfil" → começa a preencher a seção.
  Future<void> fillGapFromCard(String section) async {
    if (section.isEmpty) return;
    final ok = await _injectSection(section, 'Boa, bora preencher! 👇');
    if (!ok) _pushAi('Toca na seção lá em cima 👆 pra preencher.');
  }

  /// `show_gaps` / `show_profile_summary`: card estruturado (barra de completude
  /// + o que falta). Sem loader/erro ⇒ cai na resposta de texto.
  Future<void> _handleShowGaps(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final reply = turn.reply.trim();
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistAnswerReturned,
      props: {'grounded_in': 'profile_gaps', 'used_llm': true},
    );
    final loader = assistGapsLoader;
    if (loader == null) {
      _replyAndKeepStep(reply, step);
      return;
    }
    AssistGaps g;
    try {
      g = await loader();
    } catch (_) {
      if (_disposed) return;
      _replyAndKeepStep(reply, step);
      return;
    }
    if (_disposed) return;
    if (reply.isNotEmpty) _pushAi(reply);
    thread.add(
      GapsCardItem(completionPercent: g.completionPercent, rows: g.missing),
    );
    if (step != null) inputVisible = true;
    _notify();
  }

  /// `answer_current_step`: aplica a resposta da IA ao passo aberto (texto ou
  /// ids de opção, validados contra as opções reais). Sem match ⇒ pede toque.
  Future<void> _applyAnswerCurrentStep(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    if (step == null) {
      _replyAndKeepStep(turn.reply.trim(), null);
      return;
    }
    final input = step.input;
    if (input is GuidedTextInput) {
      final text = (turn.args['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) {
        _replyAndKeepStep('Manda o texto que eu anoto 🙂', step);
        return;
      }
      await _doSubmit(StepAnswer.text(step.id, text));
      return;
    }
    if (input is ChoiceInput) {
      final rawIds = turn.args['option_ids'];
      final ids = rawIds is List
          ? rawIds.map((e) => e.toString()).toSet()
          : <String>{};
      final matched = input.options.where((o) => ids.contains(o.id)).toList();
      if (matched.isEmpty) {
        _replyAndKeepStep(
          'Não tenho certeza 🤔 Toca numa opção aí em cima.',
          step,
        );
        return;
      }
      final selected = input.multi ? matched : [matched.first];
      await _doSubmit(StepAnswer.choice(step.id, selected));
      return;
    }
    // Mês/ano e typeahead precisam do widget.
    _replyAndKeepStep('Pra essa aqui, toca na opção acima 🙂', step);
  }

  /// `start_section`: injeta os passos reais da seção no fio (o app fornece via
  /// [assistSectionSteps]) e revela o primeiro. O passo que estava aberto
  /// RETOMA depois (a fila cuida disso — ver ConversationController.injectNext).
  Future<void> _handleStartSection(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final section = turn.args['section']?.toString() ?? '';
    if (step != null) {
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistStepConflict,
        props: {'active_step_id': step.id, 'resolution': 'deferred'},
      );
    }
    final ok = await _injectSection(section, turn.reply.trim());
    if (!ok) _replyAndKeepStep(turn.reply.trim(), step); // cai em conversa
  }

  /// Injeta os passos reais de uma seção no fio e revela o 1º. Reusado pelo
  /// `start_section` E pela sugestão proativa (Fase C). false ⇒ não deu (sem
  /// handoff/seção desconhecida). Reabre a trilha se estava concluída.
  Future<bool> _injectSection(String section, String reply) async {
    final builder = assistSectionSteps;
    final steps = builder == null
        ? const <ConversationStep>[]
        : builder(section);
    if (steps.isEmpty) return false;
    // Copiloto ON abre com chips (sem sessão). Se o user com-dados pede uma
    // seção (card "O que falta" / chip "Adicionar experiência" / start_section)
    // e ainda não há sessão, monta AGORA — senão daria dead-end (a sessão só
    // nascia pelo gate/coleta-automática, que os chips substituíram). Monta sem
    // revelar (o injectNext + _reveal abaixo já mostram a seção pedida).
    if (_session == null) {
      phase = ChatPhase.converse;
      _session = await sessionBuilder(userId);
      if (_disposed) return false;
      onStarted?.call(totalSteps);
    }
    final conv = _conv;
    if (conv == null) return false;
    if (!conv.injectNext(steps)) return false;
    if (reply.isNotEmpty) _pushAi(reply);
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistSectionHandoff,
      props: {'lacuna_key': section, 'steps_enqueued': steps.length},
    );
    finished = false; // reabre se estava concluída (proativo pós-conclusão)
    await _reveal();
    return true;
  }

  // ── Mutações (Fase B): propõe → confirma → aplica → desfaz ──────────────────

  final Map<String, AssistEditItem> _pendingEdits = {};
  final Map<String, ImportConflictItem> _pendingConflicts = {};
  final Map<String, AssistActionCardItem> _pendingActions = {};
  int _editSeq = 0;

  /// Toque no "Ver na aba Vagas" do card de vagas → troca de aba.
  Future<void> openTabFromCard(String tabKey) async {
    try {
      await assistOpenTab?.call(tabKey);
    } catch (_) {
      /* best-effort */
    }
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistActionUsed,
      props: {'action': 'open_tab', 'tab': tabKey, 'via': 'jobs_card'},
    );
  }

  /// Atalho do card de import: leva o usuário pra biblioteca de currículos
  /// (aba Perfil), onde o CV importado ficou salvo.
  Future<void> openCvLibraryFromCard() async {
    try {
      // Vai pra aba Perfil E seleciona a sub-aba Currículos (senão cai em
      // "Informações" e o CV importado fica escondido numa sub-aba não-ativa).
      await assistOpenCvLibrary?.call();
    } catch (_) {
      /* best-effort */
    }
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistActionUsed,
      props: {'action': 'open_cv_library', 'via': 'import_card'},
    );
  }

  // ── Widget de conflito de import: toggle/editar por linha + aplicar/desfazer ─

  void toggleConflictRow(String cardId, String rowId, bool accepted) {
    final item = _pendingConflicts[cardId];
    if (item == null || item.status != AssistEditStatus.pending) return;
    for (final c in item.choices) {
      if (c.row.id == rowId) c.accepted = accepted;
    }
    _notify();
  }

  void editConflictRow(String cardId, String rowId, String value) {
    final item = _pendingConflicts[cardId];
    if (item == null || item.status != AssistEditStatus.pending) return;
    for (final c in item.choices) {
      if (c.row.id == rowId) {
        c.editedValue = value;
        c.accepted = true; // editar implica aceitar
      }
    }
    _notify();
  }

  /// Gate 3.0I — aplica o lote revisado numa ÚNICA transação atômica
  /// (`apply_reviewed_conflicts_and_promote`) e reflete o agregado HONESTO:
  /// nunca marca "aplicado" cego. Falha dura (rollback global) ⇒ o card CONTINUA
  /// pendente (o RPC é idempotente por candidata+attempt+hash, então o usuário
  /// pode tentar de novo com segurança).
  Future<void> applyConflicts(String cardId) async {
    final item = _pendingConflicts[cardId];
    final applier = assistReviewedConflictApplier;
    if (item == null || item.status != AssistEditStatus.pending) return;
    if (item.applying) return; // guarda de reentrância (duplo-toque)
    if (applier == null) {
      item.status = AssistEditStatus.cancelled;
      _notify();
      return;
    }
    item.applying = true;
    _notify();

    // Só as linhas ACEITAS, cada uma pelo mapa puro verificado 1:1 contra o RPC.
    // Uma linha que não mapeia (não deveria ocorrer — o mapa cobre todas as
    // seções) é descartada; o agregado do RPC reflete só o que de fato entrou.
    final choices = <Map<String, dynamic>>[];
    for (final c in item.choices.where((c) => c.accepted)) {
      final choice = conflictRowToRpcChoice(c.row, c.effectiveValue);
      if (choice != null) choices.add(choice);
    }

    Map<String, dynamic>? raw;
    try {
      raw = await applier(item.candidateId, item.attemptId, choices);
    } catch (_) {
      raw = null; // fromRpc(null) ⇒ falha dura, nunca sucesso otimista
    }
    if (_disposed) return;
    item.applying = false;
    final outcome = ImportApplyOutcome.fromRpc(raw);
    item.outcome = outcome;
    item.appliedCount = outcome.appliedCount;
    // Falha dura ⇒ NADA foi aplicado (rollback global): mantém pendente pra
    // retry. Caso contrário promoveu ⇒ applied (com mensagem honesta no card).
    item.status =
        outcome.isHardFailure ? AssistEditStatus.pending : AssistEditStatus.applied;
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditApplied,
      props: {
        'lacuna_key': 'import_conflict',
        'op': 'apply',
        'applied': outcome.appliedCount,
        'stale': outcome.staleCount,
        'rejected': outcome.rejectedCount,
        'promoted': outcome.promoted,
      },
    );
    _notify();
  }

  void cancelConflicts(String cardId) {
    final item = _pendingConflicts[cardId];
    if (item == null || item.status != AssistEditStatus.pending) return;
    item.status = AssistEditStatus.cancelled;
    _notify();
  }

  /// Gate 3.0I — desfaz um import aplicado restaurando o snapshot pré-apply via
  /// `revert_reviewed_apply` (o servidor não desfaz item-a-item; a reversão é o
  /// snapshot completo). Só marca `undone` se a reversão confirmou de verdade —
  /// senão o card segue `applied` (sem mentir que desfez). Sem reverter fiado, o
  /// card nem mostra "Desfazer" ([canRevertConflicts]).
  Future<void> undoConflicts(String cardId) async {
    final item = _pendingConflicts[cardId];
    final reverter = assistReviewedConflictReverter;
    if (item == null || item.status != AssistEditStatus.applied) return;
    if (reverter == null || item.applying) return;
    item.applying = true;
    _notify();
    bool reverted = false;
    try {
      reverted = await reverter(item.candidateId, item.attemptId);
    } catch (_) {
      reverted = false;
    }
    if (_disposed) return;
    item.applying = false;
    if (reverted) {
      item.status = AssistEditStatus.undone;
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditUndone,
        props: {'lacuna_key': 'import_conflict', 'op': 'apply'},
      );
    }
    _notify();
  }

  /// `update_field`: NÃO grava direto — lê o valor atual, mostra um card de
  /// confirmação (Aplicar/Cancelar) e só grava no [confirmEdit]. Campo não
  /// editável / sem leitor-gravador ⇒ cai em conversa.
  /// "Cidade|UF" / "Cidade, UF" / "Cidade" → "Cidade, UF" (ou só "Cidade").
  String _cityDisplay(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return raw;
    final sep = raw.contains('|') ? '|' : (raw.contains(',') ? ',' : '');
    if (sep.isEmpty) return raw;
    final parts = raw.split(sep);
    final city = parts[0].trim();
    final uf = parts.length >= 2 ? parts[1].trim() : '';
    return uf.isEmpty ? city : '$city, $uf';
  }

  Future<void> _proposeUpdateField(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final field = turn.args['field']?.toString() ?? '';
    final value = turn.args['value']?.toString().trim() ?? '';
    // Pra CIDADE, o card SEMPRE mostra "Cidade, UF" (não o value_label curto do
    // modelo, que às vezes vem sem o estado). Pros demais, usa o value_label.
    final valueLabel = field == 'city'
        ? _cityDisplay(value)
        : (turn.args['value_label']?.toString().trim() ??
              (value.isEmpty ? '' : value));
    final reader = assistReadField;
    if (field.isEmpty ||
        value.isEmpty ||
        reader == null ||
        assistWriteField == null) {
      _replyAndKeepStep(
        turn.reply.trim().isEmpty
            ? 'Não peguei o que você quer mudar 🤔'
            : turn.reply.trim(),
        step,
      );
      return;
    }
    AssistFieldValue? current;
    try {
      current = await reader(field);
    } catch (_) {
      current = null;
    }
    if (_disposed) return;
    if (current == null) {
      _replyAndKeepStep('Essa eu ainda não consigo mudar por aqui 🙂', step);
      return;
    }
    // Modalidade precisa casar ≥1 id válido — senão o card diria "mudei" e
    // zeraria o campo (a gravação é replace). Pede a modalidade certa.
    if (field == 'work_mode' && !assistWorkModeValueValid(value)) {
      _replyAndKeepStep(
        'Qual modalidade você quer: remoto, híbrido ou presencial? 🙂',
        step,
      );
      return;
    }
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    final id = 'edit_${_editSeq++}';
    final item = AssistEditItem(
      id: id,
      field: field,
      fieldLabel: current.label,
      beforeRaw: current.raw,
      beforeText: current.text,
      afterText: valueLabel,
      value: value,
    );
    _pendingEdits[id] = item;
    thread.add(item);
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditProposed,
      props: {'lacuna_key': field, 'op': 'update'},
    );
    if (step != null) inputVisible = true;
    _notify();
  }

  /// `update_item`: muda UM campo de um item multi-campo (experiência/formação/
  /// cert). Resolve QUAL item (desambigua 2+), lê o campo (id estável) e propõe
  /// o card update; confirmar/desfazer gravam por id via assistItemFieldWriter.
  Future<void> _proposeUpdateItem(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final kind = turn.args['kind']?.toString() ?? '';
    final query = turn.args['item']?.toString().trim() ?? '';
    final field = turn.args['field']?.toString() ?? '';
    final value = turn.args['value']?.toString().trim() ?? '';
    final reader = assistItemFieldReader;
    final resolver = assistItemResolver;
    if (kind.isEmpty ||
        query.isEmpty ||
        field.isEmpty ||
        value.isEmpty ||
        reader == null ||
        assistItemFieldWriter == null ||
        resolver == null) {
      _replyAndKeepStep(
        turn.reply.trim().isEmpty
            ? 'Não peguei o que mudar 🤔'
            : turn.reply.trim(),
        step,
      );
      return;
    }
    // Semestre precisa ser NÚMERO — senão o card diria "feito" sem gravar nada.
    if (kind == 'education' && field == 'semester') {
      final n = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n == null || n < 1 || n > 14) {
        _replyAndKeepStep('Me diz o número do semestre (ex.: 5) 🙂', step);
        return;
      }
    }
    // Resolve QUAL item (0 ⇒ não achou; 2+ ⇒ desambigua; 1 ⇒ segue).
    List<String> matches;
    try {
      matches = await resolver(kind, query);
    } catch (_) {
      matches = const [];
    }
    if (_disposed) return;
    if (matches.isEmpty) {
      _replyAndKeepStep('Não achei "$query" em ${_kindLabel(kind)} 🤔', step);
      return;
    }
    if (matches.length > 1) {
      _replyAndKeepStep('Qual você quer mudar: ${matches.join(", ")}?', step);
      if (step != null) inputVisible = true;
      _notify();
      return;
    }
    // Lê o campo atual (id estável pro write/undo).
    Map<String, String>? cur;
    try {
      cur = await reader(kind, matches.first, field);
    } catch (_) {
      cur = null;
    }
    if (_disposed) return;
    if (cur == null || (cur['id'] ?? '').isEmpty) {
      _replyAndKeepStep('Esse campo eu ainda não consigo mudar aí 🙂', step);
      return;
    }
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    final id = 'edit_${_editSeq++}';
    final item = AssistEditItem(
      id: id,
      field: field,
      itemKind: kind,
      refId: cur['id']!,
      fieldLabel: cur['label'] ?? field,
      beforeRaw: cur['raw'] ?? '',
      beforeText: cur['text'] ?? '—',
      afterText: value,
      value: value,
    );
    _pendingEdits[id] = item;
    thread.add(item);
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditProposed,
      props: {'lacuna_key': kind, 'op': 'update'},
    );
    if (step != null) inputVisible = true;
    _notify();
  }

  /// `add_item`: propõe ADICIONAR um item de lista (skill/idioma). Confirma
  /// antes de gravar (postura da Fase B).
  Future<void> _proposeAddItem(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final kind = turn.args['kind']?.toString() ?? '';
    final rawValue = turn.args['value']?.toString().trim() ?? '';
    if (kind == 'interest') {
      _replyAndKeepStep(
        'Por enquanto, ajuste seus interesses em Perfil → Dados. Assim eu '
        'não corro o risco de apagar uma lista parcialmente.',
        step,
      );
      return;
    }
    // add_item só sabe skill/idioma/interesse (lista simples). Qualquer outro
    // kind (experiência/cert/…) tem vários campos → conduz pela conversa, sem
    // card falso.
    const addable = {'skill', 'language', 'interest'};
    if (kind.isEmpty ||
        rawValue.isEmpty ||
        assistItemAdder == null ||
        !addable.contains(kind)) {
      _replyAndKeepStep(
        turn.reply.trim().isEmpty
            ? 'O que você quer adicionar? 🙂'
            : turn.reply.trim(),
        step,
      );
      return;
    }

    // "adiciona SQL, Power BI e Excel" → vários itens. Sem isso viraria UMA
    // skill-lixo com vírgulas. Card em LOTE (reusa o AssistExtractItem: aplica
    // todos + Desfazer do lote). Só skill/idioma (interesse é replace-all).
    final names = _splitAddList(rawValue);
    if (names.length > 1 && (kind == 'skill' || kind == 'language')) {
      final entries = [
        for (final n in names)
          AssistExtractEntry(
            kind: kind,
            value: n,
            label: _extractLabel(kind, n),
          ),
      ];
      if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
      final item = AssistExtractItem(
        id: 'edit_${_editSeq++}',
        entries: entries,
      );
      _pendingExtracts[item.id] = item;
      thread.add(item);
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditProposed,
        props: {'lacuna_key': kind, 'op': 'add'},
      );
      if (step != null) inputVisible = true;
      _notify();
      return;
    }

    final value = names.isNotEmpty ? names.first : rawValue;

    // Já tem esse item? NÃO propõe card — senão ele mente "Adicionei" (o
    // write-back dedupa, não grava) E o Desfazer apagaria o item que já
    // existia. Só avisa. (resolver = match exato/contains no que já tem.)
    final resolver = assistItemResolver;
    if (resolver != null) {
      try {
        final existing = await resolver(kind, value);
        if (existing.any(
          (m) => m.trim().toLowerCase() == value.toLowerCase(),
        )) {
          if (_disposed) return;
          _replyAndKeepStep('"$value" já tá em ${_kindLabel(kind)} 🙂', step);
          return;
        }
      } catch (_) {
        /* best-effort: sem check, segue pro card */
      }
    }
    if (_disposed) return;
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    _pushEdit(
      AssistEditItem(
        id: 'edit_${_editSeq++}',
        op: AssistEditOp.add,
        field: kind,
        fieldLabel: _kindLabel(kind),
        afterText: value,
        value: value,
      ),
      step,
      opName: 'add',
    );
  }

  /// Quebra "SQL, Power BI e Excel" em ["SQL","Power BI","Excel"]. Só divide se
  /// tem vírgula (pra não picar "React e Redux" quando é um item só). Dedup.
  List<String> _splitAddList(String raw) {
    final s = raw.trim();
    if (!s.contains(',')) return [s];
    final out = <String>[];
    final seen = <String>{};
    for (final chunk in s.split(',')) {
      for (final p in chunk.split(RegExp(r'\s+e\s+', caseSensitive: false))) {
        final t = p.trim();
        if (t.isNotEmpty && seen.add(t.toLowerCase())) out.add(t);
      }
    }
    return out.isEmpty ? [s] : out;
  }

  /// `remove_item`: resolve QUAL item (desambigua se preciso) e propõe REMOVER
  /// (destrutivo → confirma).
  Future<void> _proposeRemoveItem(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final kind = turn.args['kind']?.toString() ?? '';
    final query = turn.args['query']?.toString().trim() ?? '';
    if (kind == 'interest') {
      _replyAndKeepStep(
        'Por enquanto, remova interesses em Perfil → Dados. Assim eu não '
        'corro o risco de apagar uma lista parcialmente.',
        step,
      );
      return;
    }
    final resolver = assistItemResolver;
    if (kind.isEmpty ||
        query.isEmpty ||
        resolver == null ||
        (assistItemRemover == null && assistReversibleRemover == null)) {
      _replyAndKeepStep(
        turn.reply.trim().isEmpty
            ? 'O que você quer remover? 🙂'
            : turn.reply.trim(),
        step,
      );
      return;
    }
    List<String> matches;
    try {
      matches = await resolver(kind, query);
    } catch (_) {
      matches = const [];
    }
    if (_disposed) return;
    if (matches.isEmpty) {
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistClarifyRequested,
        props: {'reason': 'no_match'},
      );
      _replyAndKeepStep('Não achei "$query" em ${_kindLabel(kind)} 🤔', step);
      return;
    }
    if (matches.length > 1) {
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistClarifyRequested,
        props: {'reason': 'multi_target'},
      );
      _replyAndKeepStep('Qual você quer remover: ${matches.join(', ')}?', step);
      return;
    }
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    _pushEdit(
      AssistEditItem(
        id: 'edit_${_editSeq++}',
        op: AssistEditOp.remove,
        field: kind,
        fieldLabel: _kindLabel(kind),
        afterText: matches.first,
        value: matches.first,
      ),
      step,
      opName: 'remove',
    );
  }

  void _pushEdit(
    AssistEditItem item,
    ConversationStep? step, {
    required String opName,
  }) {
    _pendingEdits[item.id] = item;
    thread.add(item);
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditProposed,
      props: {'lacuna_key': item.field, 'op': opName},
    );
    if (step != null) inputVisible = true;
    _notify();
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'skill':
        return 'suas skills';
      case 'language':
        return 'seus idiomas';
      case 'interest':
        return 'seus interesses';
      case 'area':
        return 'suas áreas';
      case 'experience':
        return 'suas experiências';
      case 'project':
        return 'seus projetos';
      case 'certification':
        return 'suas certificações';
      case 'award':
        return 'seus prêmios';
      case 'education':
        return 'sua formação';
    }
    return kind;
  }

  /// `rewrite_summary`: a IA já mandou a nova versão (new_summary). Lê o resumo
  /// atual, mostra ANTES→DEPOIS e confirma antes de gravar (é um update do campo
  /// 'summary' cujo valor veio da IA, não do usuário).
  Future<void> _proposeRewriteSummary(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final newSummary = turn.args['new_summary']?.toString().trim() ?? '';
    final reader = assistReadField;
    if (newSummary.isEmpty || reader == null || assistWriteField == null) {
      _replyAndKeepStep(
        turn.reply.trim().isEmpty
            ? 'Não consegui reescrever agora 🤔'
            : turn.reply.trim(),
        step,
      );
      return;
    }
    AssistFieldValue? current;
    try {
      current = await reader('summary');
    } catch (_) {
      current = null;
    }
    if (_disposed) return;
    final before =
        current ?? const AssistFieldValue(raw: '', text: '—', label: 'Resumo');
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    _pushEdit(
      AssistEditItem(
        id: 'edit_${_editSeq++}',
        op: AssistEditOp.update,
        field: 'summary',
        fieldLabel: before.label,
        beforeRaw: before.raw,
        beforeText: before.text,
        afterText: newSummary,
        value: newSummary,
      ),
      step,
      opName: 'update',
    );
  }

  /// `improve_bullet`: a IA mandou bullet_id + a versão melhorada (new_bullet).
  /// Lê o bullet atual (pro antes→depois e undo) e confirma antes de gravar.
  Future<void> _proposeImproveBullet(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final bulletId = turn.args['bullet_id']?.toString().trim() ?? '';
    final newText = turn.args['new_bullet']?.toString().trim() ?? '';
    final reader = assistBulletReader;
    if (bulletId.isEmpty ||
        newText.isEmpty ||
        reader == null ||
        assistBulletWriter == null) {
      _replyAndKeepStep(
        turn.reply.trim().isEmpty
            ? 'Qual bullet você quer que eu melhore? 🙂'
            : turn.reply.trim(),
        step,
      );
      return;
    }
    AssistFieldValue? current;
    try {
      current = await reader(bulletId);
    } catch (_) {
      current = null;
    }
    if (_disposed) return;
    if (current == null) {
      _replyAndKeepStep(
        'Não achei esse bullet 🤔 De qual experiência é?',
        step,
      );
      return;
    }
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    _pushEdit(
      AssistEditItem(
        id: 'edit_${_editSeq++}',
        op: AssistEditOp.bullet,
        field: 'bullet',
        fieldLabel: current.label, // a experiência ("Ambev")
        beforeRaw: current.raw,
        beforeText: current.text,
        afterText: newText,
        value: newText,
        refId: bulletId,
      ),
      step,
      opName: 'bullet',
    );
  }

  /// Confirma uma alteração proposta (toque em "Aplicar"/"Remover"). Grava e
  /// vira card "✓ … [Desfazer]".
  Future<void> confirmAssistEdit(String id) async {
    final item = _pendingEdits[id];
    if (item == null ||
        item.status != AssistEditStatus.pending ||
        item.applying ||
        item.undoing) {
      return;
    }
    item.applying = true;
    item.resultMessage = '';
    _notify();
    final ok = await _applyEditOp(item, item.op);
    item.applying = false;
    if (_disposed) return;
    if (!ok) {
      if (item.resultMessage.isEmpty) {
        item.resultMessage = 'Não consegui salvar. Tente novamente.';
      }
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditFailed,
        props: {'lacuna_key': item.field, 'op': item.op.name},
      );
      _notify();
      return;
    }
    item.status = AssistEditStatus.applied;
    item.resultMessage = '';
    _pendingEdits.remove(id);
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditApplied,
      props: {'lacuna_key': item.field, 'op': item.op.name},
    );
    _notify();
  }

  /// Cancela uma alteração proposta (toque em "Cancelar") — não grava nada.
  void cancelAssistEdit(String id) {
    final item = _pendingEdits[id];
    if (item == null ||
        item.status != AssistEditStatus.pending ||
        item.applying ||
        item.undoing) {
      return;
    }
    _pendingEdits.remove(id);
    item.status = AssistEditStatus.cancelled;
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditCancelled,
      props: {'lacuna_key': item.field, 'op': item.op.name},
    );
    _notify();
  }

  /// Desfaz uma alteração já aplicada (toque em "Desfazer") — aplica a operação
  /// INVERSA (add↔remove; update regrava o valor anterior). Savers idempotentes.
  Future<void> undoAssistEdit(String id) async {
    AssistEditItem? item;
    for (final it in thread) {
      if (it is AssistEditItem && it.id == id) {
        item = it;
        break;
      }
    }
    if (item == null ||
        item.status != AssistEditStatus.applied ||
        item.applying ||
        item.undoing) {
      return;
    }
    item.undoing = true;
    item.resultMessage = '';
    _notify();
    // Undo CAPTURADO (ex.: re-inserir a experiência removida) tem prioridade.
    final captured = item.capturedUndo;
    var ok = false;
    if (captured != null) {
      var alreadyPresent = false;
      try {
        final matches = await assistItemResolver?.call(item.field, item.value);
        alreadyPresent =
            matches != null && _containsExactValue(matches, item.value);
      } catch (_) {
        item.resultMessage =
            'Não consegui conferir o estado atual. Tente novamente.';
        ok = false;
      }
      if (item.resultMessage.isEmpty) {
        if (alreadyPresent) {
          item.resultMessage =
              'Esse item mudou depois da remoção. Não sobrescrevi o item mais recente.';
        } else {
          try {
            await captured();
          } catch (_) {
            // Pode ser timeout depois do restore; a leitura viva decide abaixo.
          }
        }
        if (item.resultMessage.isEmpty) {
          try {
            final matches = await assistItemResolver?.call(
              item.field,
              item.value,
            );
            ok = matches != null && _containsExactValue(matches, item.value);
          } catch (_) {
            ok = false;
          }
        }
      }
    } else {
      final inverse = switch (item.op) {
        AssistEditOp.update => AssistEditOp.update, // regrava beforeRaw
        AssistEditOp.add => AssistEditOp.remove, // desfaz add = remove
        AssistEditOp.remove => AssistEditOp.add, // desfaz remove = add
        AssistEditOp.bullet => AssistEditOp.bullet, // regrava o bullet antigo
      };
      ok = await _applyEditOp(item, inverse, undo: true);
    }
    item.undoing = false;
    if (_disposed) return;
    if (!ok) {
      if (item.resultMessage.isEmpty) {
        item.resultMessage = 'Não consegui desfazer. Tente novamente.';
      }
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditUndoFailed,
        props: {'lacuna_key': item.field, 'op': item.op.name},
      );
      _notify();
      return;
    }
    item.status = AssistEditStatus.undone;
    item.resultMessage = '';
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditUndone,
      props: {'lacuna_key': item.field, 'op': item.op.name},
    );
    _notify();
  }

  /// Aplica uma operação de mutação reusando os writers injetados. false (com
  /// aviso) se falhou. Undo de update usa beforeRaw.
  Future<bool> _applyEditOp(
    AssistEditItem item,
    AssistEditOp op, {
    bool undo = false,
  }) async {
    final expectedValue = undo ? item.beforeRaw : item.value;
    try {
      switch (op) {
        case AssistEditOp.update:
          // Campo de item multi-campo (itemKind setado) → grava por id; senão,
          // campo global (cargo/resumo/nome…).
          if (item.itemKind.isNotEmpty) {
            final iw = assistItemFieldWriter;
            final reader = assistItemFieldReader;
            if (iw == null || reader == null) return false;
            final liveBefore = await reader(
              item.itemKind,
              item.refId,
              item.field,
            );
            final requiredCurrent = undo ? item.value : item.beforeRaw;
            if (liveBefore == null ||
                !_samePersistedText(liveBefore['raw'] ?? '', requiredCurrent)) {
              item.resultMessage = undo
                  ? 'Esse dado mudou depois da aplicação. Não sobrescrevi a edição mais recente.'
                  : 'Esse dado mudou desde que o card abriu. Abra a edição novamente.';
              return false;
            }
            try {
              // Gate 3.0H: 5º arg = observado (CAS server-side manual-vence).
              await iw(
                item.itemKind, item.refId, item.field, expectedValue, requiredCurrent);
            } catch (_) {
              // A leitura por id estável confirma um possível commit tardio.
            }
            final current = await reader(item.itemKind, item.refId, item.field);
            return current != null &&
                _samePersistedText(current['raw'] ?? '', expectedValue);
          }
          final w = assistWriteField;
          final reader = assistReadField;
          if (w == null || reader == null) return false;
          final liveBefore = await reader(item.field);
          final requiredCurrent = undo ? item.value : item.beforeRaw;
          if (liveBefore == null ||
              !_samePersistedText(liveBefore.raw, requiredCurrent)) {
            item.resultMessage = undo
                ? 'Esse dado mudou depois da aplicação. Não sobrescrevi a edição mais recente.'
                : 'Esse dado mudou desde que o card abriu. Abra a edição novamente.';
            return false;
          }
          try {
            // Gate 3.0H: 3º arg = observado (CAS server-side manual-vence).
            await w(item.field, expectedValue, requiredCurrent);
          } catch (_) {
            // Timeout pode chegar depois do commit; a leitura viva decide.
          }
          final current = await reader(item.field);
          return current != null &&
              _samePersistedText(current.raw, expectedValue);
        case AssistEditOp.add:
          final a = assistItemAdder;
          final resolver = assistItemResolver;
          if (a == null || resolver == null) return false;
          final before = await resolver(item.field, item.value);
          if (!undo && _containsExactValue(before, item.value)) return false;
          try {
            await a(item.field, item.value);
          } catch (_) {
            // A leitura viva abaixo distingue falha de commit confirmado.
          }
          return _containsExactValue(
            await resolver(item.field, item.value),
            item.value,
          );
        case AssistEditOp.remove:
          // Item multi-campo (experiência/projeto): remoção reversível (captura
          // o restore pro undo). Se não for tratado ali, cai no remover simples.
          final rev = assistReversibleRemover;
          if (rev != null) {
            final resolver = assistItemResolver;
            if (resolver == null ||
                !_containsExactValue(
                  await resolver(item.field, item.value),
                  item.value,
                )) {
              item.resultMessage =
                  'Esse item mudou desde que o card abriu. Abra a edição novamente.';
              return false;
            }
            final restore = await rev(item.field, item.value);
            if (restore != null) {
              item.capturedUndo = restore;
              return true; // o helper só devolve recibo após confirmar delete
            }
            if ({
              'skill', // Gate 3.0E: skill remove é CAS/recibo; nunca cai no
              'language', // Gate 3.0F: idioma remove é CAS; ambos fail-closed
              'experience', // (nunca caem no remover por nome inseguro).
              'education',
              'certification',
              'award',
              'project',
            }.contains(item.field)) {
              return false;
            }
          }
          final r = assistItemRemover;
          final resolver = assistItemResolver;
          if (r == null || resolver == null) return false;
          final before = await resolver(item.field, item.value);
          if (!undo && !_containsExactValue(before, item.value)) return false;
          try {
            await r(item.field, item.value);
          } catch (_) {
            // A leitura viva abaixo distingue falha de commit confirmado.
          }
          return !_containsExactValue(
            await resolver(item.field, item.value),
            item.value,
          );
        case AssistEditOp.bullet:
          final bw = assistBulletWriter;
          final reader = assistBulletReader;
          if (bw == null || reader == null) return false;
          final liveBefore = await reader(item.refId);
          final requiredCurrent = undo ? item.value : item.beforeRaw;
          if (liveBefore == null ||
              !_samePersistedText(liveBefore.raw, requiredCurrent)) {
            item.resultMessage = undo
                ? 'Esse bullet mudou depois da aplicação. Não sobrescrevi a edição mais recente.'
                : 'Esse bullet mudou desde que o card abriu. Abra a edição novamente.';
            return false;
          }
          try {
            // Gate 3.0H: 3º arg = texto observado (CAS server-side).
            await bw(item.refId, expectedValue, requiredCurrent);
          } catch (_) {
            // A leitura viva abaixo distingue falha de commit confirmado.
          }
          final current = await reader(item.refId);
          return current != null &&
              _samePersistedText(current.raw, expectedValue);
      }
    } catch (_) {
      if (_disposed) return false;
      _pushAi(
        undo
            ? 'Não consegui desfazer agora 🤔'
            : 'Ops, não consegui salvar agora 🤔',
      );
      _notify();
      return false;
    }
  }

  // ── Extração de textão (Fase C): batch confirmar → aplica cada → desfaz tudo ─

  final Map<String, AssistExtractItem> _pendingExtracts = {};

  /// `extract_profile`: a IA extraiu vários campos de um textão. Mostra um card
  /// "Peguei isto 👇" — nada grava até confirmar. Só kinds de apply/undo limpos
  /// (skill/idioma/cargo); complexos (experiência/educação) a IA sugere na fala.
  Future<void> _proposeExtract(
    AssistantTurn turn,
    ConversationStep? step,
  ) async {
    final raw = turn.args['items'];
    final entries = <AssistExtractEntry>[];
    if (raw is List) {
      for (final it in raw) {
        if (it is! Map) continue;
        final kind = it['kind']?.toString() ?? '';
        final value = it['value']?.toString().trim() ?? '';
        if (value.isEmpty) continue;
        if (kind == 'skill' ||
            kind == 'language' ||
            kind == 'desired_position') {
          entries.add(
            AssistExtractEntry(
              kind: kind,
              value: value,
              label: _extractLabel(kind, value),
            ),
          );
        }
      }
    }
    if (entries.isEmpty) {
      _replyAndKeepStep(
        turn.reply.trim().isEmpty
            ? 'Não consegui pegar nada 🤔'
            : turn.reply.trim(),
        step,
      );
      return;
    }
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    final item = AssistExtractItem(id: 'edit_${_editSeq++}', entries: entries);
    _pendingExtracts[item.id] = item;
    thread.add(item);
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditProposed,
      props: {'lacuna_key': 'extract', 'op': 'add'},
    );
    if (step != null) inputVisible = true;
    _notify();
  }

  String _extractLabel(String kind, String value) {
    switch (kind) {
      case 'skill':
        return 'Skill: $value';
      case 'language':
        return 'Idioma: $value';
      case 'desired_position':
        return 'Cargo: $value';
    }
    return value;
  }

  /// Aplica os itens extraídos com recibo por entrada. Falha parcial permanece
  /// pendente e um retry tenta somente o que ainda não foi confirmado.
  Future<void> confirmExtract(String id) async {
    final item = _pendingExtracts[id];
    if (item == null ||
        item.status != AssistEditStatus.pending ||
        item.applying ||
        item.undoing ||
        item.undoFailed) {
      return;
    }
    final adder = assistItemAdder;
    final remover = assistItemRemover;
    final resolver = assistItemResolver;
    final writer = assistWriteField;
    final reader = assistReadField;

    final needsListWriter = item.entries.any(
      (e) => e.kind == 'skill' || e.kind == 'language',
    );
    final needsScalarWriter = item.entries.any(
      (e) => e.kind == 'desired_position',
    );

    // Preflight antes da primeira escrita: sem leitura + escrita + undo não há
    // como distinguir no-op, falha ambígua ou desfazer com segurança.
    if ((needsListWriter &&
            (adder == null || remover == null || resolver == null)) ||
        (needsScalarWriter && (writer == null || reader == null))) {
      item.failedIndexes
        ..clear()
        ..addAll(
          Iterable<int>.generate(
            item.entries.length,
          ).where((i) => !item.appliedIndexes.contains(i)),
        );
      item.resultMessage =
          'Não consegui aplicar esses dados agora. Tente de novo.';
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditFailed,
        props: {'lacuna_key': 'extract', 'op': 'add'},
      );
      _notify();
      return;
    }

    item.applying = true;
    item.undoFailed = false;
    item.resultMessage = '';
    item.failedIndexes.clear();
    _notify();

    for (var index = 0; index < item.entries.length; index++) {
      if (item.appliedIndexes.contains(index)) continue;
      final e = item.entries[index];
      try {
        if (e.kind == 'skill' || e.kind == 'language') {
          final before = await resolver!(e.kind, e.value);
          if (_containsExactValue(before, e.value)) {
            item.appliedIndexes.add(index); // já existia: não cria undo
            continue;
          }
          try {
            await adder!(e.kind, e.value);
          } catch (_) {
            // Falha de rede pode chegar depois do commit. Confirma no estado
            // vivo antes de declarar falha e permitir um retry duplicador.
            final after = await resolver(e.kind, e.value);
            if (!_containsExactValue(after, e.value)) rethrow;
          }
          item.appliedIndexes.add(index);
          item.undoByIndex[index] = () async {
            try {
              await remover!(e.kind, e.value);
            } catch (_) {
              // O callback pode falhar depois do commit. A releitura abaixo é
              // a fonte de verdade para o recibo do desfazer.
            }
            final restored = await resolver(e.kind, e.value);
            if (_containsExactValue(restored, e.value)) {
              throw StateError('undo_not_confirmed');
            }
          };
        } else if (e.kind == 'desired_position') {
          final beforeValue = await reader!('desired_position');
          if (beforeValue == null) throw StateError('field_not_readable');
          final before = beforeValue.raw;
          if (_samePersistedText(before, e.value)) {
            item.appliedIndexes.add(index);
            continue;
          }
          try {
            // desired_position é job_preferences → segue legado; o observado
            // (before) vai no 3º arg mas é ignorado pelo writer (não é CAS).
            await writer!('desired_position', e.value, before);
          } catch (_) {
            final after = await reader('desired_position');
            if (after == null || !_samePersistedText(after.raw, e.value)) {
              rethrow;
            }
          }
          item.appliedIndexes.add(index);
          item.undoByIndex[index] = () async {
            final live = await reader('desired_position');
            if (live == null || !_samePersistedText(live.raw, e.value)) {
              throw StateError('undo_stale_value');
            }
            try {
              await writer!('desired_position', before, e.value);
            } catch (_) {
              // Confirma no valor vivo antes de decidir se o rollback falhou.
            }
            final restored = await reader('desired_position');
            if (restored == null || !_samePersistedText(restored.raw, before)) {
              throw StateError('undo_not_confirmed');
            }
          };
        }
      } catch (_) {
        item.failedIndexes.add(index);
      }
    }
    item.applying = false;
    if (_disposed) return;

    if (item.appliedIndexes.length == item.entries.length) {
      item.status = AssistEditStatus.applied;
      item.resultMessage = item.madeChanges
          ? ''
          : 'Esses dados já estavam no seu perfil.';
      _pendingExtracts.remove(id);
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditApplied,
        props: {'lacuna_key': 'extract', 'op': 'add'},
      );
    } else {
      if (item.appliedIndexes.isEmpty) {
        item.resultMessage = 'Não consegui salvar esses dados. Tente de novo.';
      } else if (!item.madeChanges) {
        item.resultMessage =
            'Alguns dados já estavam no seu perfil. '
            'Não consegui salvar o restante.';
      } else {
        item.resultMessage =
            '${item.appliedCount} de ${item.entries.length} foram confirmados. '
            'Tente novamente para concluir.';
      }
      // ignore: unawaited_futures
      Analytics.shared.track(
        item.appliedIndexes.isEmpty
            ? evTrilhaAssistEditFailed
            : evTrilhaAssistEditPartial,
        props: {
          'lacuna_key': 'extract',
          'op': 'add',
          'applied_count': item.appliedCount,
          'total_count': item.entries.length,
        },
      );
    }
    _notify();
  }

  static String _normalizeAssistValue(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static bool _sameAssistValue(String left, String right) =>
      _normalizeAssistValue(left) == _normalizeAssistValue(right);

  /// Confirma o texto realmente persistido sem apagar diferenças de caixa.
  /// `_sameAssistValue` continua servindo para busca/dedup case-insensitive;
  /// recibos de update precisam distinguir `ana` de `Ana`.
  static bool _samePersistedText(String left, String right) =>
      _normalizePersistedText(left) == _normalizePersistedText(right);

  static String _normalizePersistedText(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static bool _containsExactValue(List<String> values, String expected) =>
      values.any((value) => _sameAssistValue(value, expected));

  void cancelExtract(String id) {
    final item = _pendingExtracts.remove(id);
    if (item == null ||
        item.status != AssistEditStatus.pending ||
        item.applying ||
        item.undoing ||
        item.madeChanges) {
      if (item != null) _pendingExtracts[id] = item;
      return;
    }
    item.status = AssistEditStatus.cancelled;
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditCancelled,
      props: {'lacuna_key': 'extract', 'op': 'add'},
    );
    _notify();
  }

  Future<void> undoExtract(String id) async {
    AssistExtractItem? item;
    for (final it in thread) {
      if (it is AssistExtractItem && it.id == id) {
        item = it;
        break;
      }
    }
    if (item == null ||
        (item.status != AssistEditStatus.applied && !item.isPartial) ||
        !item.madeChanges ||
        item.undoing ||
        item.applying) {
      return;
    }
    item.undoing = true;
    item.undoFailed = false;
    item.resultMessage = '';
    _notify();
    final failedUndoIndexes = <int>{};
    for (final entry in item.undoByIndex.entries.toList().reversed) {
      try {
        await entry.value();
        item.undoByIndex.remove(entry.key);
        item.appliedIndexes.remove(entry.key);
        item.failedIndexes.add(entry.key);
      } catch (_) {
        failedUndoIndexes.add(entry.key);
      }
    }
    item.undoing = false;
    if (_disposed) return;
    if (failedUndoIndexes.isEmpty) {
      item.status = AssistEditStatus.undone;
      item.resultMessage = '';
      _pendingExtracts.remove(id);
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditUndone,
        props: {'lacuna_key': 'extract', 'op': 'add'},
      );
    } else {
      item.undoFailed = true;
      item.resultMessage = 'Não consegui desfazer tudo. Tente novamente.';
      // Mantém applied: a UI nunca afirma "Desfeito" com mutação pendente.
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditUndoFailed,
        props: {
          'lacuna_key': 'extract',
          'op': 'add',
          'failed_count': failedUndoIndexes.length,
        },
      );
    }
    _notify();
  }

  // ── Editor visual de lista simples: skills / interesses (Fase C) ───────────

  final Map<String, ListEditorItem> _pendingListEditors = {};

  /// `edit_skills`/`edit_interests`: abre o editor visual com os itens atuais.
  /// Sem itens ainda ⇒ editar não faz sentido → cai na COLETA (start_section).
  Future<void> _proposeListEditor(String kind, AssistantTurn turn) async {
    if (kind == 'interest' || kind == 'area') {
      _replyAndKeepStep(
        'Por enquanto, edite ${kind == 'area' ? 'suas áreas' : 'seus interesses'} '
        'em Perfil → ${kind == 'area' ? 'Objetivos' : 'Dados'}. Assim suas escolhas ficam protegidas mesmo se a '
        'conexão cair.',
        currentStep,
      );
      return;
    }
    final isSkill = kind == 'skill';
    final section = kind == 'skill'
        ? 'skills'
        : kind == 'interest'
        ? 'interests'
        : 'area';
    final noun = kind == 'skill'
        ? 'skills'
        : kind == 'interest'
        ? 'interesses'
        : 'áreas';
    final title = kind == 'skill'
        ? 'Suas habilidades'
        : kind == 'interest'
        ? 'Seus interesses'
        : 'Suas áreas de interesse';
    final writer = isSkill ? assistSkillsWriter : null;
    if (writer == null) {
      _replyAndKeepStep(
        'Não consegui abrir esse editor agora. Tente novamente.',
        currentStep,
      );
      return;
    }
    final operationId = newAssistSkillsOperationId();
    List<String> current;
    try {
      final receipt = await writer.open(
        userId: userId,
        operationId: operationId,
      );
      current = normalizeSkillNames(receipt.baseline);
    } catch (_) {
      _replyAndKeepStep(
        'Não consegui carregar suas skills. Tente novamente.',
        currentStep,
      );
      return;
    }
    if (_disposed) return;
    if (current.isEmpty) {
      final reply = turn.reply.trim();
      final ok = await _injectSection(
        section,
        reply.isEmpty ? 'Você ainda não tem $noun — bora adicionar? 👇' : reply,
      );
      if (!ok) _pushAi('Bora adicionar seus $noun? Me conta um.');
      return;
    }
    // Sugestões (só skills, pela área) — best-effort, tira as que já tem.
    var suggestions = const <String>[];
    final suggester = isSkill ? assistSkillSuggester : null;
    if (suggester != null) {
      try {
        final existing = current.map(foldSkillName).toSet();
        suggestions = normalizeSkillNames(
          await suggester(),
        ).where((s) => !existing.contains(foldSkillName(s))).take(8).toList();
      } catch (_) {
        /* best-effort */
      }
    }
    if (_disposed) return;
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    final item = ListEditorItem(
      id: 'edit_${_editSeq++}',
      operationId: operationId,
      kind: kind,
      title: title,
      initial: current,
      suggestions: suggestions,
    );
    _pendingListEditors[item.id] = item;
    thread.add(item);
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditProposed,
      props: {'lacuna_key': kind, 'op': 'edit'},
    );
    _notify();
  }

  /// "Salvar" no editor de skills: envia a lista final em uma única operação
  /// CAS. O servidor é a única fonte de verdade para sucesso, retry e undo.
  Future<void> applyListEditor(
    String id, {
    required List<String> added,
    required List<String> removed,
  }) async {
    final item = _pendingListEditors[id];
    if (item == null ||
        item.status != AssistEditStatus.pending ||
        item.applying ||
        item.undoing) {
      return;
    }
    if (!item.hasUnconfirmedChanges && added.isEmpty && removed.isEmpty) {
      cancelListEditor(id);
      return;
    }
    final writer = item.kind == 'skill' ? assistSkillsWriter : null;
    if (writer == null) {
      item.resultMessage = 'Não consegui preparar uma gravação segura.';
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditFailed,
        props: {'lacuna_key': item.kind, 'op': 'edit'},
      );
      _notify();
      return;
    }

    final removedKeys = removed.map(foldSkillName).toSet();
    final requestedDesired = normalizeSkillNames(<String>[
      ...item.initial.where(
        (value) => !removedKeys.contains(foldSkillName(value)),
      ),
      ...added,
    ]);
    if (item.hasUnconfirmedChanges &&
        !_sameOrderedSkillNames(requestedDesired, item.pendingDesired)) {
      item.resultMessage =
          'Esta tentativa já foi enviada. Tente novamente sem mudar o card.';
      _notify();
      return;
    }
    if (!item.hasUnconfirmedChanges) {
      item.pendingAdded = List.unmodifiable(normalizeSkillNames(added));
      item.pendingRemoved = List.unmodifiable(normalizeSkillNames(removed));
      item.pendingDesired = List.unmodifiable(requestedDesired);
    }
    final desired = item.pendingDesired;
    item.applying = true;
    item.resultMessage = '';
    _notify();
    AssistSkillsApplyReceipt receipt;
    try {
      receipt = await writer.apply(
        userId: userId,
        operationId: item.operationId,
        expected: item.initial,
        desired: desired,
      );
    } on ArgumentError {
      item.applying = false;
      if (_disposed) return;
      _clearPendingListEditorAttempt(item);
      item.resultMessage =
          'Não consegui validar essas skills. Revise o card e tente novamente.';
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditFailed,
        props: {'lacuna_key': item.kind, 'op': 'edit', 'reason': 'validation'},
      );
      _notify();
      return;
    } catch (_) {
      item.applying = false;
      if (_disposed) return;
      item.hasUnconfirmedChanges = true;
      item.observedAfter = null;
      item.resultMessage =
          'Não consegui confirmar as mudanças. Tente novamente.';
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditFailed,
        props: {'lacuna_key': item.kind, 'op': 'edit', 'reason': 'unconfirmed'},
      );
      _notify();
      return;
    }
    item.applying = false;
    if (_disposed) return;
    item.hasUnconfirmedChanges = false;
    _clearPendingListEditorAttempt(item);
    switch (receipt.outcome) {
      case AssistSkillsApplyOutcome.applied:
        final diff = _canonicalSkillDiff(item.initial, receipt.resulting);
        item.addedApplied = List.unmodifiable(diff.added);
        item.removedApplied = List.unmodifiable(diff.removed);
        item.observedAfter = receipt.live;
        item.undoAvailable = receipt.canUndo;
        item.status = AssistEditStatus.applied;
        item.resultMessage = receipt.replayed && !receipt.canUndo
            ? 'A alteração foi aplicada, mas suas skills mudaram depois. Atualizei o perfil sem oferecer um desfazer inseguro.'
            : '';
        _pendingListEditors.remove(id);
        onProfileEdited?.call();
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistEditApplied,
          props: {
            'lacuna_key': item.kind,
            'op': 'edit',
            'outcome': 'applied',
            'changed': true,
            'replayed': receipt.replayed,
            'undo_receipt': receipt.canUndo,
          },
        );
        break;
      case AssistSkillsApplyOutcome.noop:
        item.addedApplied = const [];
        item.removedApplied = const [];
        item.observedAfter = receipt.live;
        item.undoAvailable = false;
        item.status = AssistEditStatus.applied;
        item.resultMessage = 'Esse estado já estava salvo; nada foi regravado.';
        _pendingListEditors.remove(id);
        onProfileEdited?.call();
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistEditApplied,
          props: {
            'lacuna_key': item.kind,
            'op': 'edit',
            'outcome': 'noop',
            'changed': false,
            'replayed': receipt.replayed,
            'undo_receipt': false,
          },
        );
        break;
      case AssistSkillsApplyOutcome.stale:
        item.observedAfter = receipt.live;
        item.undoAvailable = false;
        item.status = AssistEditStatus.cancelled;
        item.resultMessage =
            'Seu perfil mudou desde que este card abriu. Não sobrescrevi a edição mais recente; abra o editor de novo.';
        _pendingListEditors.remove(id);
        onProfileEdited?.call();
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistEditFailed,
          props: {
            'lacuna_key': item.kind,
            'op': 'edit',
            'outcome': 'stale',
            'changed': false,
            'reason': 'stale',
          },
        );
        break;
      case AssistSkillsApplyOutcome.undone:
        item.status = AssistEditStatus.undone;
        item.observedAfter = receipt.live;
        item.addedApplied = const [];
        item.removedApplied = const [];
        item.undoAvailable = false;
        item.resultMessage = '';
        _pendingListEditors.remove(id);
        onProfileEdited?.call();
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistEditUndone,
          props: {
            'lacuna_key': item.kind,
            'op': 'edit',
            'outcome': 'undone',
            'changed': false,
            'replayed': true,
            'source': 'apply_replay',
          },
        );
        break;
    }
    _notify();
  }

  void cancelListEditor(String id) {
    final item = _pendingListEditors[id];
    if (item == null ||
        item.status != AssistEditStatus.pending ||
        item.applying ||
        item.undoing ||
        item.hasUnconfirmedChanges) {
      return;
    }
    _pendingListEditors.remove(id);
    item.status = AssistEditStatus.cancelled;
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditCancelled,
      props: {'lacuna_key': item.kind, 'op': 'edit'},
    );
    _notify();
  }

  Future<void> undoListEditor(String id) async {
    ListEditorItem? item;
    for (final it in thread) {
      if (it is ListEditorItem && it.id == id) {
        item = it;
        break;
      }
    }
    if (item == null ||
        (item.status != AssistEditStatus.applied &&
            !(item.status == AssistEditStatus.pending &&
                item.hasUnconfirmedChanges &&
                item.observedAfter != null)) ||
        (item.status == AssistEditStatus.applied && !item.undoAvailable) ||
        item.applying ||
        item.undoing) {
      return;
    }
    final writer = item.kind == 'skill' ? assistSkillsWriter : null;
    if (writer == null) {
      item.resultMessage = 'Não consegui preparar um desfazer seguro.';
      _notify();
      return;
    }

    item.undoing = true;
    item.resultMessage = '';
    _notify();
    AssistSkillsUndoReceipt receipt;
    try {
      receipt = await writer.undo(
        userId: userId,
        operationId: item.operationId,
        expectedRestored: item.initial,
      );
    } catch (_) {
      item.undoing = false;
      if (_disposed) return;
      item.resultMessage = 'Não consegui desfazer. Tente novamente.';
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditUndoFailed,
        props: {'lacuna_key': item.kind, 'op': 'edit'},
      );
      _notify();
      return;
    }
    item.undoing = false;
    if (_disposed) return;
    switch (receipt.outcome) {
      case AssistSkillsUndoOutcome.undone:
        item.status = AssistEditStatus.undone;
        item.hasUnconfirmedChanges = false;
        item.observedAfter = receipt.live;
        item.undoAvailable = false;
        item.resultMessage = '';
        _pendingListEditors.remove(id);
        onProfileEdited?.call();
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistEditUndone,
          props: {
            'lacuna_key': item.kind,
            'op': 'edit',
            'outcome': 'undone',
            'changed': !receipt.replayed,
            'replayed': receipt.replayed,
          },
        );
        break;
      case AssistSkillsUndoOutcome.stale:
        item.observedAfter = receipt.live;
        item.undoAvailable = false;
        item.resultMessage =
            'Suas skills mudaram depois da aplicação. Não sobrescrevi a edição mais recente.';
        onProfileEdited?.call();
        // ignore: unawaited_futures
        Analytics.shared.track(
          evTrilhaAssistEditUndoFailed,
          props: {
            'lacuna_key': item.kind,
            'op': 'edit',
            'outcome': 'stale',
            'changed': false,
            'reason': 'stale',
          },
        );
        break;
    }
    _notify();
  }

  static bool _sameOrderedSkillNames(
    Iterable<String> left,
    Iterable<String> right,
  ) {
    final a = left.map(foldSkillName).toList(growable: false);
    final b = right.map(foldSkillName).toList(growable: false);
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static ({List<String> added, List<String> removed}) _canonicalSkillDiff(
    Iterable<String> before,
    Iterable<String> resulting,
  ) {
    final normalizedBefore = normalizeSkillNames(before);
    final normalizedResulting = normalizeSkillNames(resulting);
    final beforeKeys = normalizedBefore.map(foldSkillName).toSet();
    final resultingKeys = normalizedResulting.map(foldSkillName).toSet();
    return (
      added: normalizedResulting
          .where((value) => !beforeKeys.contains(foldSkillName(value)))
          .toList(growable: false),
      removed: normalizedBefore
          .where((value) => !resultingKeys.contains(foldSkillName(value)))
          .toList(growable: false),
    );
  }

  static void _clearPendingListEditorAttempt(ListEditorItem item) {
    item.pendingAdded = const [];
    item.pendingRemoved = const [];
    item.pendingDesired = const [];
  }

  static bool _samePersistedCollection(
    Iterable<String> actual,
    Iterable<String> expected,
  ) {
    final left = actual
        .map(_normalizePersistedText)
        .where((value) => value.isNotEmpty)
        .toSet();
    final right = expected
        .map(_normalizePersistedText)
        .where((value) => value.isNotEmpty)
        .toSet();
    return left.length == right.length && left.containsAll(right);
  }

  // ── Editor visual de idiomas (Fase C) — cada item tem nível ────────────────

  final Map<String, LanguagesEditorItem> _pendingLangEditors = {};

  /// Os 7 idiomas que a trilha oferece (mesma lista canônica da coleta).
  static const List<String> _kCanonicalLanguages = [
    'Português',
    'Inglês',
    'Espanhol',
    'Francês',
    'Alemão',
    'Italiano',
    'Mandarim',
  ];

  /// `edit_languages`: abre o editor visual de idiomas (nome + nível). Sem
  /// idiomas ainda ⇒ cai na COLETA (start_section 'languages').
  Future<void> _proposeLanguagesEditor(AssistantTurn turn) async {
    final loader = assistLanguagesLoader;
    if (loader == null) {
      _replyAndKeepStep(
        'Não consegui abrir o editor de idiomas agora. Tente novamente.',
        currentStep,
      );
      return;
    }
    List<(String, String?)> current;
    try {
      current = await loader();
    } catch (_) {
      _replyAndKeepStep(
        'Não consegui carregar seus idiomas. Tente novamente.',
        currentStep,
      );
      return;
    }
    if (_disposed) return;
    if (current.isEmpty) {
      final reply = turn.reply.trim();
      final ok = await _injectSection(
        'languages',
        reply.isEmpty
            ? 'Você ainda não tem idiomas — bora adicionar? 👇'
            : reply,
      );
      if (!ok) _pushAi('Bora adicionar seus idiomas?');
      return;
    }
    final have = current.map((e) => e.$1.toLowerCase()).toSet();
    final options = _kCanonicalLanguages
        .where((l) => !have.contains(l.toLowerCase()))
        .toList();
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    final item = LanguagesEditorItem(
      id: 'edit_${_editSeq++}',
      initial: [for (final e in current) LangEntry(e.$1, e.$2)],
      options: options,
    );
    _pendingLangEditors[item.id] = item;
    thread.add(item);
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditProposed,
      props: {'lacuna_key': 'languages', 'op': 'edit'},
    );
    _notify();
  }

  /// "Salvar" no editor de idiomas: upsert dos adicionados/alterados, remove dos
  /// tirados; undo inverso do lote (níveis antigos capturados do baseline).
  Future<void> applyLanguagesEditor(
    String id, {
    required List<LangEntry> added,
    required List<String> removed,
    required List<LangEntry> changed,
  }) async {
    final item = _pendingLangEditors[id];
    if (item == null ||
        item.status != AssistEditStatus.pending ||
        item.applying ||
        item.undoing) {
      return;
    }
    if (added.isEmpty && removed.isEmpty && changed.isEmpty) {
      cancelLanguagesEditor(id);
      return;
    }
    final upsert = assistLanguageUpserter;
    final remover = assistItemRemover;
    final loader = assistLanguagesLoader;
    if (loader == null || upsert == null || remover == null) {
      item.resultMessage = 'Não consegui preparar uma gravação segura.';
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditFailed,
        props: {'lacuna_key': 'languages', 'op': 'edit'},
      );
      _notify();
      return;
    }

    final initial = <String, String?>{
      for (final entry in item.initial)
        _normalizeAssistValue(entry.name): _normalizeLanguageLevel(entry.level),
    };
    final expected = Map<String, String?>.from(initial);
    for (final name in removed) {
      expected.remove(_normalizeAssistValue(name));
    }
    for (final entry in [...added, ...changed]) {
      expected[_normalizeAssistValue(entry.name)] = _normalizeLanguageLevel(
        entry.level,
      );
    }
    item.applying = true;
    item.resultMessage = '';
    _notify();
    if (!item.hasUnconfirmedChanges) {
      List<(String, String?)> live;
      try {
        live = await loader();
      } catch (_) {
        item.applying = false;
        item.resultMessage =
            'Não consegui conferir seus idiomas. Tente novamente.';
        _notify();
        return;
      }
      if (!_sameLanguageState(live, initial)) {
        item.applying = false;
        item.resultMessage =
            'Seus idiomas mudaram desde que este card abriu. Abra o editor de novo.';
        _notify();
        return;
      }
      item.pendingAdded = List.unmodifiable(added);
      item.pendingRemoved = List.unmodifiable(removed);
      item.pendingChanged = List.unmodifiable(changed);
      item.observedAfter = null;
    } else {
      if (!_sameLangEntries(added, item.pendingAdded) ||
          !_samePersistedCollection(removed, item.pendingRemoved) ||
          !_sameLangEntries(changed, item.pendingChanged)) {
        item.applying = false;
        item.resultMessage =
            'Conclua ou desfaça as mudanças pendentes antes de editar a seleção.';
        _notify();
        return;
      }
      final observed = item.observedAfter;
      if (observed != null) {
        List<(String, String?)> live;
        try {
          live = await loader();
        } catch (_) {
          item.applying = false;
          item.resultMessage =
              'Não consegui conferir seus idiomas. Tente novamente.';
          _notify();
          return;
        }
        if (!_sameAffectedLanguageState(live, observed, [
          ...added.map((entry) => entry.name),
          ...removed,
          ...changed.map((entry) => entry.name),
        ])) {
          item.applying = false;
          item.resultMessage =
              'Esses idiomas mudaram desde a última tentativa. Não sobrescrevi a edição mais recente.';
          _notify();
          return;
        }
      } else {
        List<(String, String?)> live;
        try {
          live = await loader();
        } catch (_) {
          item.applying = false;
          item.resultMessage =
              'Ainda não consegui confirmar seus idiomas. Tente novamente.';
          _notify();
          return;
        }
        if (_sameLanguageState(live, expected)) {
          item.applying = false;
          item.hasUnconfirmedChanges = false;
          item.addedApplied = added;
          item.removedApplied = removed;
          item.changedApplied = changed;
          item.observedAfter = List<LangEntry>.unmodifiable(
            live.map((entry) => LangEntry(entry.$1, entry.$2)),
          );
          item.undoAvailable = false;
          item.status = AssistEditStatus.applied;
          item.resultMessage =
              'As alterações já estavam no perfil; confirmei o estado sem criar um novo desfazer.';
          _pendingLangEditors.remove(id);
          // ignore: unawaited_futures
          Analytics.shared.track(
            evTrilhaAssistEditApplied,
            props: {
              'lacuna_key': 'languages',
              'op': 'edit',
              'undo_receipt': false,
            },
          );
          _notify();
          return;
        }
        if (_sameLanguageState(live, initial)) {
          item.applying = false;
          item.hasUnconfirmedChanges = false;
          item.observedAfter = List<LangEntry>.unmodifiable(
            live.map((entry) => LangEntry(entry.$1, entry.$2)),
          );
          item.resultMessage =
              'O perfil voltou ao estado inicial. Revise e salve novamente se ainda quiser aplicar.';
          _notify();
          return;
        } else {
          item.applying = false;
          item.resultMessage =
              'Esses idiomas mudaram desde a tentativa anterior. Não sobrescrevi a edição mais recente.';
          _notify();
          return;
        }
      }
    }

    var callbackFailed = false;
    for (final name in removed) {
      try {
        await remover('language', name);
      } catch (_) {
        callbackFailed = true;
      }
    }
    for (final entry in [...added, ...changed]) {
      try {
        await upsert(entry.name, entry.level);
      } catch (_) {
        callbackFailed = true;
      }
    }

    List<(String, String?)>? liveAfter;
    var verified = false;
    try {
      liveAfter = await loader();
      verified = _sameLanguageState(liveAfter, expected);
    } catch (_) {
      verified = false;
    }
    item.applying = false;
    if (_disposed) return;
    if (!verified) {
      item.hasUnconfirmedChanges =
          liveAfter == null || !_sameLanguageState(liveAfter, initial);
      item.observedAfter = liveAfter == null
          ? null
          : List<LangEntry>.unmodifiable(
              liveAfter.map((entry) => LangEntry(entry.$1, entry.$2)),
            );
      item.resultMessage = callbackFailed
          ? 'Algumas mudanças não foram confirmadas. Tente novamente.'
          : 'Não consegui confirmar as mudanças. Tente novamente.';
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditPartial,
        props: {'lacuna_key': 'languages', 'op': 'edit'},
      );
      _notify();
      return;
    }
    item.addedApplied = added;
    item.removedApplied = removed;
    item.changedApplied = changed;
    item.observedAfter = List<LangEntry>.unmodifiable(
      liveAfter!.map((entry) => LangEntry(entry.$1, entry.$2)),
    );
    item.undoAvailable = true;
    item.hasUnconfirmedChanges = false;
    item.status = AssistEditStatus.applied;
    item.resultMessage = '';
    _pendingLangEditors.remove(id);
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditApplied,
      props: {'lacuna_key': 'languages', 'op': 'edit'},
    );
    _notify();
  }

  static String? _normalizeLanguageLevel(String? level) {
    final value = level?.trim().toLowerCase() ?? '';
    return value.isEmpty ? null : value;
  }

  static bool _sameLanguageState(
    List<(String, String?)> actual,
    Map<String, String?> expected,
  ) {
    final normalized = <String, String?>{
      for (final entry in actual)
        _normalizeAssistValue(entry.$1): _normalizeLanguageLevel(entry.$2),
    };
    if (normalized.length != expected.length) return false;
    for (final entry in expected.entries) {
      if (!normalized.containsKey(entry.key) ||
          normalized[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static bool _sameLangEntries(
    Iterable<LangEntry> actual,
    Iterable<LangEntry> expected,
  ) {
    final expectedMap = <String, String?>{
      for (final entry in expected)
        _normalizeAssistValue(entry.name): _normalizeLanguageLevel(entry.level),
    };
    final actualList = [for (final entry in actual) (entry.name, entry.level)];
    return _sameLanguageState(actualList, expectedMap);
  }

  static bool _sameAffectedLanguageState(
    Iterable<(String, String?)> actual,
    Iterable<LangEntry> expected,
    Iterable<String> affected,
  ) {
    final keys = affected.map(_normalizeAssistValue).toSet();
    final actualMap = <String, (String, String?)>{
      for (final entry in actual)
        if (keys.contains(_normalizeAssistValue(entry.$1)))
          _normalizeAssistValue(entry.$1): (
            _normalizePersistedText(entry.$1),
            _normalizeLanguageLevel(entry.$2),
          ),
    };
    final expectedMap = <String, (String, String?)>{
      for (final entry in expected)
        if (keys.contains(_normalizeAssistValue(entry.name)))
          _normalizeAssistValue(entry.name): (
            _normalizePersistedText(entry.name),
            _normalizeLanguageLevel(entry.level),
          ),
    };
    if (actualMap.length != expectedMap.length) return false;
    for (final entry in expectedMap.entries) {
      if (actualMap[entry.key] != entry.value) return false;
    }
    return true;
  }

  void cancelLanguagesEditor(String id) {
    final item = _pendingLangEditors[id];
    if (item == null ||
        item.status != AssistEditStatus.pending ||
        item.applying ||
        item.undoing ||
        item.hasUnconfirmedChanges) {
      return;
    }
    _pendingLangEditors.remove(id);
    item.status = AssistEditStatus.cancelled;
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditCancelled,
      props: {'lacuna_key': 'languages', 'op': 'edit'},
    );
    _notify();
  }

  Future<void> undoLanguagesEditor(String id) async {
    LanguagesEditorItem? item;
    for (final it in thread) {
      if (it is LanguagesEditorItem && it.id == id) {
        item = it;
        break;
      }
    }
    if (item == null ||
        (item.status != AssistEditStatus.applied &&
            !(item.status == AssistEditStatus.pending &&
                item.hasUnconfirmedChanges)) ||
        (item.status == AssistEditStatus.applied && !item.undoAvailable) ||
        item.applying ||
        item.undoing) {
      return;
    }
    final loader = assistLanguagesLoader;
    final upsert = assistLanguageUpserter;
    final remover = assistItemRemover;
    if (loader == null || upsert == null || remover == null) {
      item.resultMessage = 'Não consegui preparar um desfazer seguro.';
      _notify();
      return;
    }

    item.undoing = true;
    item.resultMessage = '';
    _notify();
    final partial = item.status == AssistEditStatus.pending;
    final added = partial ? item.pendingAdded : item.addedApplied;
    final removed = partial ? item.pendingRemoved : item.removedApplied;
    final changed = partial ? item.pendingChanged : item.changedApplied;
    var current = const <(String, String?)>[];
    var loadFailed = false;
    try {
      current = await loader();
    } catch (_) {
      loadFailed = true;
    }
    final observed = item.observedAfter;
    final affectedNames = [
      ...added.map((entry) => entry.name),
      ...removed,
      ...changed.map((entry) => entry.name),
    ];
    if (!loadFailed &&
        (observed == null ||
            !_sameAffectedLanguageState(current, observed, affectedNames))) {
      item.undoing = false;
      item.resultMessage =
          'Esses idiomas mudaram depois da aplicação. Não sobrescrevi a edição mais recente.';
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditUndoFailed,
        props: {'lacuna_key': 'languages', 'op': 'edit'},
      );
      _notify();
      return;
    }
    final initialEntries = <String, LangEntry>{
      for (final entry in item.initial)
        _normalizeAssistValue(entry.name): entry,
    };
    if (!loadFailed) {
      final currentKeys = current
          .map((entry) => _normalizeAssistValue(entry.$1))
          .toSet();
      for (final entry in added) {
        if (!currentKeys.contains(_normalizeAssistValue(entry.name))) continue;
        try {
          await remover('language', entry.name);
        } catch (_) {
          // A releitura abaixo decide o resultado real.
        }
      }
      final restoreKeys = {
        ...removed.map(_normalizeAssistValue),
        ...changed.map((entry) => _normalizeAssistValue(entry.name)),
      };
      for (final key in restoreKeys) {
        final entry = initialEntries[key];
        if (entry == null) continue;
        try {
          await upsert(entry.name, entry.level);
        } catch (_) {
          // A releitura abaixo decide o resultado real.
        }
      }
    }

    var verified = false;
    if (!loadFailed) {
      try {
        final restored = await loader();
        verified = _sameAffectedLanguageState(
          restored,
          item.initial,
          affectedNames,
        );
      } catch (_) {
        verified = false;
      }
    }
    item.undoing = false;
    if (_disposed) return;
    if (!verified) {
      item.resultMessage = 'Não consegui desfazer tudo. Tente novamente.';
      // ignore: unawaited_futures
      Analytics.shared.track(
        evTrilhaAssistEditUndoFailed,
        props: {'lacuna_key': 'languages', 'op': 'edit'},
      );
      _notify();
      return;
    }
    item.status = AssistEditStatus.undone;
    item.hasUnconfirmedChanges = false;
    item.observedAfter = null;
    item.undoAvailable = false;
    item.resultMessage = '';
    _pendingLangEditors.remove(id);
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaAssistEditUndone,
      props: {'lacuna_key': 'languages', 'op': 'edit'},
    );
    _notify();
  }

  /// Serializa o passo aberto pro grounding do assistente (sem PII sensível).
  Map<String, dynamic> _serializeStep(ConversationStep step) {
    final input = step.input;
    var kind = 'other';
    var multi = false;
    var optional = false;
    var options = const <Map<String, String>>[];
    if (input is ChoiceInput) {
      kind = 'choice';
      multi = input.multi;
      options = [
        for (final o in input.options) {'id': o.id, 'label': o.label},
      ];
    } else if (input is GuidedTextInput) {
      kind = 'text';
      optional = input.optional;
    } else if (input is MonthYearInput) {
      kind = 'month_year';
      optional = input.optional;
    } else if (input is SuggestPickInput || input is AsyncSuggestInput) {
      kind = 'suggest';
    } else if (input is AsyncPickInput) {
      kind = 'search';
    } else if (input is ExperienceTypeInput) {
      kind = 'experience_type';
    }
    return {
      'id': step.id,
      'question': step.aiMessages.join(' ').trim(),
      'inputKind': kind,
      'options': options,
      'multi': multi,
      'optional': optional,
    };
  }

  /// Até 6 falas de turnos livres concluídos. O fio visual não é fonte de
  /// contexto: ele também contém cards, saudações e respostas guiadas.
  List<Map<String, dynamic>> _assistantHistory() {
    final out = <Map<String, dynamic>>[];
    for (final turn in _assistantTurns) {
      out.add({'role': 'user', 'text': turn.userText});
      out.add({'role': 'assistant', 'text': turn.assistantText});
    }
    return out.length <= 6 ? out : out.sublist(out.length - 6);
  }

  Future<bool> _restoreAssistantContext() async {
    final store = assistantContextStore;
    if (store == null) return false;
    AssistantContextSnapshot snapshot;
    try {
      snapshot = await store.load(userId);
    } catch (_) {
      return false;
    }
    if (_disposed || snapshot.isEmpty) return false;

    final restored = <AssistantContextTurn>[];
    for (final turn in snapshot.turns) {
      final user = SharedPreferencesAssistantContextStore.sanitizeText(
        turn.userText,
      );
      final assistant = SharedPreferencesAssistantContextStore.sanitizeText(
        turn.assistantText,
      );
      if (user.isEmpty || assistant.isEmpty) continue;
      restored.add(
        AssistantContextTurn(userText: user, assistantText: assistant),
      );
    }
    if (restored.isEmpty) return false;

    _assistantTurns
      ..clear()
      ..addAll(
        restored.length <= SharedPreferencesAssistantContextStore.maxTurns
            ? restored
            : restored.sublist(
                restored.length -
                    SharedPreferencesAssistantContextStore.maxTurns,
              ),
      );
    thread
      ..clear()
      ..addAll([
        for (final turn in _assistantTurns) ...[
          UserMsgItem(turn.userText),
          AiMsgItem(turn.assistantText),
        ],
      ]);
    phase = ChatPhase.converse;
    typing = false;
    inputVisible = true;
    _suppressIntroGreeting = true;
    _notify();
    return true;
  }

  Future<void> _rememberAssistantTurn(
    String userText,
    String assistantText,
  ) async {
    final user = SharedPreferencesAssistantContextStore.sanitizeText(userText);
    final assistant = SharedPreferencesAssistantContextStore.sanitizeText(
      assistantText,
    );
    if (user.isEmpty || assistant.isEmpty) return;
    _assistantTurns.add(
      AssistantContextTurn(userText: user, assistantText: assistant),
    );
    if (_assistantTurns.length >
        SharedPreferencesAssistantContextStore.maxTurns) {
      _assistantTurns.removeRange(
        0,
        _assistantTurns.length -
            SharedPreferencesAssistantContextStore.maxTurns,
      );
    }
    final store = assistantContextStore;
    if (store == null || !assistEnabled) return;
    try {
      await store.save(userId, List.unmodifiable(_assistantTurns));
    } catch (_) {
      // A conversa concluída continua válida mesmo se o cache local falhar.
    }
  }

  bool _stepIsOptional(ConversationStep step) {
    final i = step.input;
    if (i is GuidedTextInput) return i.optional;
    if (i is MonthYearInput) return i.optional;
    return false;
  }

  /// Heurística LOCAL e conservadora: a mensagem tem cara de COMANDO (e não de
  /// resposta ao passo de texto aberto)? Só é usada pra decidir o ATALHO local
  /// (Nível 0); falso-positivo apenas manda pro assistente (que reinterpreta).
  static final RegExp _cmdVerbs = RegExp(
    r'^(adiciona|adicionar|add|tira|tirar|remove|remover|apaga|apagar|muda|mudar|troca|trocar|corrige|corrigir|edita|editar|reescreve|reescrever|melhora|melhorar|refor[çc]a|refor[çc]ar|pula|pular|mostra|mostrar|explica|explicar|ajuda|quero|como|o que|qual|quais|por que|porque|pq)\b',
    caseSensitive: false,
  );
  // As palavras de seção mais antigas casam por PREFIXO de propósito
  // ('certifica'→certificado). As novas de AÇÃO (vaga/exportar/importar/pdf) usam
  // um lookahead `(?![a-zà-ú])` (não \b, que o Dart trata como ASCII e dispararia
  // no 'ç' de "importação"/"exportação"): casa "importa"/"vagas"/"exporta" mas
  // NÃO "importante"/"vagando"/"importação".
  static final RegExp _sectionWords = RegExp(
    r'\b(skill|habilidade|experi[eê]ncia|resumo|bullet|cidade|cargo|[aá]rea|idioma|projeto|forma[cç][aã]o|linkedin|certifica|pr[eê]mio|disponibilidade|interesse|perfil|curr[ií]culo|vagas?(?![a-zà-ú])|exportar?(?![a-zà-ú])|importar?(?![a-zà-ú])|pdf(?![a-zà-ú]))',
    caseSensitive: false,
  );
  bool _looksLikeCommand(String t) {
    final s = t.trim();
    if (s.endsWith('?')) return true;
    if (_cmdVerbs.hasMatch(s)) return true;
    if (_sectionWords.hasMatch(s)) return true;
    return false;
  }

  /// "não sei"/"sla"/"passa" e afins — não-resposta a um passo de texto.
  static final RegExp _nonAnswerRe = RegExp(
    r'^(n[aã]o sei|nao sei|sei l[aá]|sla|sei n[aã]o|nem sei|n[aã]o fa[çc]o ideia|nao faco ideia|sem ideia|passa|pula|prefiro n[aã]o|deixa (pra|pro) depois|talvez)[\s!.?]*$',
    caseSensitive: false,
  );
  bool _looksLikeNonAnswer(String t) => _nonAnswerRe.hasMatch(t.trim());

  /// Um textão colado (várias infos de uma vez) não é resposta de um passo —
  /// deve ir pra IA extrair. Heurística: quebra de linha, ou longo com ≥2
  /// vírgulas (enumeração "curso X, falo Y, sei Z").
  bool _looksLikePaste(String t) {
    final s = t.trim();
    if (s.contains('\n')) return true;
    if (s.length > 140 && ','.allMatches(s).length >= 2) return true;
    return false;
  }

  // ── Fase C: sugestão proativa do próximo ganho ─────────────────────────────

  /// Seção sugerida no último nudge (pra o atalho "quero" cair direto nela).
  String? _suggestedSection;

  // A mensagem TODA precisa ser uma confirmação curta (ancorado no fim) —
  // opcionalmente + 1 palavrinha de reforço + pontuação. Senão "quero editar
  // minhas habilidades" (que começa com "quero") sequestraria o atalho da seção
  // sugerida em vez de ir pro assistente.
  static final RegExp _affirmative = RegExp(
    r'^(sim|claro|quero|bora|pode|podemos|vamos|vam[uo]s|partiu|com certeza|isso|manda|ok|beleza|blz|t[aá]|uhum|s)( sim| l[áa]| ent[ãa]o| a[íi])?[\s!.]*$',
    caseSensitive: false,
  );
  bool _isAffirmative(String t) {
    final s = t.trim();
    return s == '👍' || _affirmative.hasMatch(s);
  }

  /// Ao CONCLUIR, sugere reforçar a maior lacuna que resta. A pessoa aceita com
  /// "quero/bora" (atalho) ou pedindo a seção. No-op se a flag OFF / sem loader.
  Future<void> _maybeSuggestNextGap() async {
    if (!assistEnabled) return;
    final loader = assistProactiveLoader;
    if (loader == null) return;
    Map<String, String>? gap;
    try {
      gap = await loader();
    } catch (_) {
      gap = null;
    }
    if (_disposed || gap == null) return;
    final section = gap['section'] ?? '';
    final label = gap['label'] ?? '';
    if (section.isEmpty || label.isEmpty) return;
    _suggestedSection = section;
    _pushAi(
      'Se quiser deixar ainda mais forte, o que mais pesa agora é: '
      '$label. Quer preencher? (é só dizer "quero" 😉)',
    );
  }

  /// Interpreta [text] contra as opções do passo de escolha [input] e, se casar
  /// com confiança, despacha por [submit] (mesmo caminho do toque). Senão,
  /// mantém o widget e pede pra tocar. Failure-safe: erro/timeout ⇒ fallback.
  Future<void> _interpretChoice(
    ConversationStep step,
    ChoiceInput input,
    String text,
  ) async {
    inputVisible = false;
    typing = true;
    _notify();

    final fn = interpret ?? AIService().interpretStepAnswer;
    StepInterpretation? result;
    try {
      result = await fn(
        stepId: step.id,
        question: step.aiMessages.join(' ').trim(),
        freeText: text,
        options: [
          for (final o in input.options) {'id': o.id, 'label': o.label},
        ],
        multi: input.multi,
      );
    } catch (_) {
      result = null;
    }
    if (_disposed) return;
    typing = false;

    final r = result;
    final matched = r == null
        ? const <StepOption>[]
        : input.options.where((o) => r.matchedIds.contains(o.id)).toList();

    // Telemetria R7 — só métricas, NUNCA o texto digitado (PII/LGPD).
    // ignore: unawaited_futures
    Analytics.shared.track(
      evTrilhaColetaFreeTextInterpreted,
      props: {
        'step_id': step.id,
        'matched_count': matched.length,
        'char_count': text.length,
        'confidence': r?.confidence ?? 'none',
      },
    );

    final lowConf = r == null || r.confidence == 'low';
    if (matched.isEmpty || lowConf) {
      inputVisible = true; // mantém o widget pra tocar
      _pushAi(
        'Não tenho certeza do que você quis dizer 🤔 Toca numa opção aí em cima.',
      );
      return;
    }

    final selected = input.multi
        ? _cap(matched, input.maxSelections)
        : [matched.first];
    // _doSubmit direto: já estamos dentro da seção _busy (via submitFreeText).
    await _doSubmit(StepAnswer.choice(step.id, selected));
  }

  List<StepOption> _cap(List<StepOption> xs, int? max) =>
      (max != null && xs.length > max) ? xs.sublist(0, max) : xs;

  void _pushAi(String text) {
    thread.add(AiMsgItem(text));
    _notify();
  }

  // ── Edição de card (in-place) ───────────────────────────────────────────────

  /// O lápis só aparece onde regravar realmente substitui o valor vivo.
  /// Itens multi-passo usam buffers já finalizados; listas da coleta fazem
  /// merge. Nesses casos a correção deve acontecer pelo editor seguro do perfil.
  bool canEditAnswer(AnsweredItem item) {
    final step = item.exchange.step;
    if (!step.reversible) return false;
    final conv = _conv;
    if (conv == null || !_isLiveEditableExchange(conv, item.exchange)) {
      return false;
    }
    // Um gate com ramo dinâmico só pode ser refeito enquanto ainda é a última
    // resposta confirmada. Nesse ponto `goBack` consegue podar exatamente os
    // follow-ups que ele inseriu; depois que outro passo foi respondido, editar
    // o gate poderia deixar histórico e perfil divergentes.
    if (step.expand != null) {
      return conv.canRewindExchange(item.exchange);
    }
    final id = step.id;
    if (id.startsWith('exp.') ||
        id.startsWith('project.') ||
        id.startsWith('cert.') ||
        id.startsWith('award.') ||
        id.startsWith('gap.edu.')) {
      return false;
    }
    return !{
      'gap.area',
      'gap.workmode',
      'gap.jobtype',
      'gap.skills',
      'gap.languages',
      'gap.interests',
    }.contains(id);
  }

  void beginEdit(AnsweredItem item) {
    if (!canEditAnswer(item)) return;
    final idx = thread.indexOf(item);
    if (idx < 0) return;
    editingIndex = idx;
    _editingStep = item.exchange.step;
    _editingExchange = item.exchange;
    _notify();
  }

  void cancelEdit() {
    editingIndex = null;
    _editingStep = null;
    _editingExchange = null;
    _notify();
  }

  Future<bool> _applyEdit(StepAnswer answer) async {
    final idx = editingIndex;
    final step = _editingStep;
    final exchange = _editingExchange;
    if (idx == null || step == null || exchange == null) return false;
    final session = _session;
    if (session == null) return false;
    editingIndex = null;
    _editingStep = null;
    _editingExchange = null;
    _notify();

    final conv = _conv;
    if (answer.stepId != step.id ||
        conv == null ||
        !_isLiveEditableExchange(conv, exchange)) {
      inputVisible = !typing && conv?.current != null;
      _pushAi('Essa resposta já mudou. Abra a edição novamente.');
      return false;
    }

    // Passo com RAMIFICAÇÃO dinâmica (expand) — ex.: "ainda está nessa
    // experiência?" sim→não passa a pedir a data de saída. Se é o ÚLTIMO
    // respondido (nada depois foi inserido ainda → seguro, sem duplicar) e a
    // resposta MUDOU, re-avalia o ramo: poda os follow-ups antigos, rebobina o
    // gate (goBack) e re-submete pra revelar o ramo certo.
    if (step.expand != null) {
      if (!conv.canRewindExchange(exchange)) {
        inputVisible = !typing && conv.current != null;
        _pushAi('Essa resposta já mudou. Abra a edição novamente.');
        return false;
      }
      final changed = exchange.answer.displayText != answer.displayText;
      if (changed) {
        if (idx >= 0 && idx <= thread.length) {
          thread.removeRange(idx, thread.length);
        }
        conv.goBack();
        _notify();
        await _doSubmit(answer); // re-roda o expand + revela o follow-up
        return conv.history.isNotEmpty &&
            identical(conv.history.last.answer, answer);
      }
      inputVisible = !typing && conv.current != null;
      _notify();
      return false;
    }

    // Edição leve (campo simples / sem mudança de ramo): re-grava + troca o card.
    try {
      await session.saveAnswer(answer); // somente writers de substituição
    } catch (_) {
      if (_disposed) return false;
      editingIndex = idx;
      _editingStep = step;
      _editingExchange = exchange;
      _pushAi('Não consegui salvar essa correção. Tente novamente.');
      _notify();
      return false;
    }
    if (_disposed) return false;
    final replacement = conv.replaceAnswer(exchange, answer);
    if (replacement == null) {
      inputVisible = !typing && conv.current != null;
      _pushAi('Essa resposta já mudou. Abra a edição novamente.');
      return false;
    }
    thread[idx] = AnsweredItem(replacement);
    // Restaura o widget do passo CORRENTE ao sair da edição — senão, ao editar
    // por texto livre (que zerou inputVisible), o passo atual sumiria.
    inputVisible = !typing && _conv?.current != null;
    _notify();
    return true;
  }

  bool _isLiveEditableExchange(
    ConversationController conv,
    ConversationExchange exchange,
  ) {
    final history = conv.history;
    final index = history.indexWhere((item) => identical(item, exchange));
    if (index < 0) return false;
    // Se a mesma seção foi coletada de novo, somente a ocorrência mais recente
    // pode representar o valor vivo. Um card anterior com o mesmo ID é stale.
    return !history
        .skip(index + 1)
        .any((item) => item.step.id == exchange.step.id);
  }

  // ── Conclusão ───────────────────────────────────────────────────────────────

  void _onDone() {
    finished = true;
    inputVisible = false;
    typing = false;
    _notify();
    _runFinalize();
  }

  Future<void> _runFinalize() async {
    final fn = onFinalize;
    if (fn != null) {
      finalizing = true;
      _notify();
      String? summary;
      try {
        summary = await fn();
      } catch (_) {
        summary = null;
      }
      if (_disposed) return;
      finalizing = false;
      generatedSummary = summary;
      _notify();
    }
    // Fase C: depois do resumo (ou direto, se não há finalize), sugere o
    // próximo ganho — se ainda falta algo que o assistente sabe conduzir.
    await _maybeSuggestNextGap();
  }
}
