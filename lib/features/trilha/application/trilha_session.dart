// Montagem da sessão da trilha (PLANO-FASE-6 T6.3, Increment 2c + fix memória).
//
// Junta as peças: carrega o perfil real + os trechos já abordados (memória) →
// calcula as lacunas → monta o plano adaptativo (sem re-perguntar o que já foi
// abordado) → cria o ConversationController com o write-back plugado (grava em
// profile_* e marca cada trecho como abordado).

import '../../../services/ai_service.dart';
import '../../../services/analytics_events.dart';
import '../../../services/analytics_service.dart';
import '../../../services/profile_snapshot_service.dart';
import '../../profile/application/profile_gaps.dart';
import '../../profile/data/repositories/profile_repository_supabase.dart';
import '../../profile/domain/entities/job_preferences.dart' show JobPreferences;
import '../../profile/domain/entities/personal_info.dart' show PersonalInfo;
import '../../profile/domain/entities/simple_lists.dart'
    show Language, languageProficiencyFromId;
import '../../profile/domain/repositories/profile_repository.dart';
import '../domain/conversation_step.dart'
    show PickSuggestion, StepAnswer, StepOption, ConversationStep;
import 'conversation_controller.dart';
import 'conversation_plan.dart';
import 'trilha_draft.dart';
import 'ibge_city_service.dart';
import 'institution_search_service.dart';
import 'skill_suggestions.dart';
import 'trilha_progress.dart';
import 'trilha_writeback.dart';

/// Cache do catálogo IBGE compartilhado entre aberturas da trilha na sessão.
final _ibge = IbgeCityService();

/// Uma sessão da trilha: o [controller] + o [saveAnswer] que grava em profile_*
/// e marca o trecho. O `saveAnswer` é exposto pra o chat v2 poder REGRAVAR um
/// campo na edição de card (idempotente) sem passar pelo fluxo do controller.
class TrilhaSession {
  final ConversationController controller;
  final Future<void> Function(StepAnswer answer) saveAnswer;
  const TrilhaSession({required this.controller, required this.saveAnswer});
}

/// Constrói o controller da trilha para [userId] (caminho antigo — pushado/dev).
/// Pula trechos já abordados (memória [TrilhaProgress]). Delega a
/// [buildTrilhaSession].
Future<ConversationController> buildTrilhaController(
  String userId, {
  ProfileRepository? repository,
  ProfileSnapshotService? snapshotService,
  TrilhaProgress? progress,
}) async {
  final s = await buildTrilhaSession(
    userId,
    repository: repository,
    snapshotService: snapshotService,
    progress: progress,
  );
  return s.controller;
}

/// Constrói a sessão (controller + saveAnswer). Recalcula lacunas a partir do
/// perfil FRESCO — é o que permite o re-planejamento após o import (basta
/// chamar de novo). Sem cache stale.
Future<TrilhaSession> buildTrilhaSession(
  String userId, {
  ProfileRepository? repository,
  ProfileSnapshotService? snapshotService,
  TrilhaProgress? progress,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final snapSvc = snapshotService ?? ProfileSnapshotService();
  // Híbrido: retomada entre devices via profile_guided_progress (failure-safe).
  final prog = progress ?? TrilhaProgress(repository: repo);

  final snapshot = await snapSvc.loadSnapshot(userId);
  final prefs = await repo.getJobPreferences(userId);
  final desired = await repo.getDesiredTitles(userId);
  final addressed = await prog.addressed(userId);
  // Rascunhos de item em construção (resumabilidade por passo, failure-safe).
  final draftStore = TrilhaDraftStore();
  final drafts = await draftStore.load(userId);

  final gaps = profileGapsFromData(
    snapshot: snapshot,
    prefs: prefs,
    desiredTitles: desired,
  );

  // Pro passo de skills: catálogo (typeahead) + sugestões pela área. Só busca o
  // catálogo se skills é mesmo uma lacuna a perguntar (evita round-trip à toa).
  final needsSkills =
      gaps.missing.any((l) => l.key == LacunaKey.skills) &&
          !addressed.contains('skills');
  final skillCatalog = needsSkills ? await _safeSkillCatalog(repo) : const <String>[];
  final skillSuggestions = needsSkills
      ? suggestedSkillsForAreas(desired.map((d) => d.title).toList())
      : const <String>[];

  final plan = buildConversationPlan(
    gaps,
    addressed: addressed,
    // Idiomas sem nível → na volta pergunta só o nível que faltou (não o picker).
    languagesNeedingLevel: snapshot.languages
        .where((l) => l.proficiency == null)
        .map((l) => l.name)
        .toList(),
    skillSuggestions: skillSuggestions,
    skillCatalog: skillCatalog,
    // Depois de marcar skills, a IA sugere mais algumas pelo perfil (opcional).
    skillSuggester:
        needsSkills ? () => AIService().suggestProfileSkills() : null,
    // Sugestões de skills pela ÁREA — lidas na hora do passo (capta a área
    // escolhida DENTRO da trilha, não só a do onboarding).
    skillSuggestionsLoader: needsSkills
        ? () async => suggestedSkillsForAreas(
              (await repo.getDesiredTitles(userId))
                  .map((d) => d.title)
                  .toList(),
            )
        : null,
    // Typeahead canônico: cidade (IBGE, com UF) e instituição (catálogo, fixa o
    // institution_id) — não polui os campos de filtro do admin. Lazy: só busca
    // quando o usuário chega no passo.
    citySearch: (q) async => (await _ibge.search(q))
        .map((c) => PickSuggestion(
              label: c.uf.isEmpty ? c.name : '${c.name} - ${c.uf}',
              value: c.uf.isEmpty ? c.name : '${c.name}|${c.uf}',
            ))
        .toList(),
    institutionSearch: (q) async => (await searchInstitutions(q))
        .map((i) => PickSuggestion(label: i.name, value: '${i.id}|${i.name}'))
        .toList(),
    drafts: drafts, // retoma o item parcial no passo onde parou
  );
  final writeback = TrilhaWriteback(repo, userId, draftStore: draftStore);
  // Reidrata os buffers do rascunho ANTES do controller — pra o save terminal
  // ver TODOS os campos (os de antes do abandono + os respondidos na retomada).
  writeback.seedFromDrafts(drafts);

  // Grava a resposta + marca o trecho. Reusado pelo fluxo (onAnswer) E pela
  // edição de card (re-save direto). Marca o trecho só quando há DADO salvo ou
  // gate "não" (ver segmentToMark) — "sim" sem escrever NÃO conta (a pergunta volta).
  Future<void> saveAnswer(StepAnswer answer) async {
    await writeback.save(answer);
    final segment =
        TrilhaProgress.segmentToMark(answer.stepId, answer.value);
    if (segment != null) {
      await prog.mark(userId, segment);
      // Telemetria (5c): conta os trechos efetivamente abordados.
      // ignore: unawaited_futures
      Analytics.shared
          .track(evTrilhaColetaStepAnswered, props: {'segment': segment});
    }
  }

  final controller = ConversationController(plan, onAnswer: saveAnswer);
  return TrilhaSession(controller: controller, saveAnswer: saveAnswer);
}

/// Lê os nomes canônicos do skills_catalog (fonte do typeahead). Failure-safe:
/// erro/sem rede ⇒ lista vazia (a busca fica sem catálogo, mas chips + texto
/// livre seguem funcionando).
Future<List<String>> _safeSkillCatalog(ProfileRepository repo) async {
  try {
    return await repo.getSkillCatalogNames();
  } catch (_) {
    return const [];
  }
}

// ── Assistente de IA na barra (PLANO-ASSISTENTE, Fase A) ─────────────────────

/// Nome de seção (que o assistente devolve) → LacunaKey.
const Map<String, LacunaKey> _kAssistSection = {
  'area': LacunaKey.area,
  'desired_position': LacunaKey.desiredPosition,
  'work_mode': LacunaKey.workMode,
  'job_type': LacunaKey.jobType,
  'city': LacunaKey.city,
  'education': LacunaKey.educationStatus,
  'skills': LacunaKey.skills,
  'languages': LacunaKey.languages,
  'experience': LacunaKey.experience,
  'linkedin': LacunaKey.linkedin,
  'certifications': LacunaKey.certifications,
  'awards': LacunaKey.awards,
  'projects': LacunaKey.projects,
  'interests': LacunaKey.interests,
  'availability': LacunaKey.availability,
  'company_stage': LacunaKey.companyStage,
  'work_environment': LacunaKey.workEnvironment,
  'work_style': LacunaKey.workStyle,
};

/// LacunaKey → nome de seção (reverso de [_kAssistSection]).
String? _sectionForLacuna(LacunaKey key) {
  for (final e in _kAssistSection.entries) {
    if (e.value == key) return e.key;
  }
  return null;
}

/// Fase C (proativo) — a MAIOR lacuna que resta e que o assistente sabe
/// conduzir (`{section, label}`), pra sugerir o próximo ganho ao concluir.
/// null ⇒ nada a sugerir. Failure-safe.
Future<Map<String, String>?> assistTopGap(
  String userId, {
  ProfileRepository? repository,
  ProfileSnapshotService? snapshotService,
}) async {
  try {
    final repo = repository ?? ProfileRepositorySupabase();
    final snapSvc = snapshotService ?? ProfileSnapshotService();
    final snapshot = await snapSvc.loadSnapshot(userId);
    final prefs = await repo.getJobPreferences(userId);
    final desired = await repo.getDesiredTitles(userId);
    final gaps = profileGapsFromData(
        snapshot: snapshot, prefs: prefs, desiredTitles: desired);
    for (final l in gaps.missing) {
      if (l.key == LacunaKey.summary) continue; // gerado, não perguntado
      final section = _sectionForLacuna(l.key);
      if (section != null) return {'section': section, 'label': l.label};
    }
  } catch (_) {/* best-effort */}
  return null;
}

/// Passos reais de uma seção pra o assistente INJETAR ("quero preencher X"),
/// com os searchers canônicos (cidade IBGE + instituição + skills pela IA).
/// Seção desconhecida ⇒ lista vazia (o controller cai em conversa).
List<ConversationStep> assistSectionStepsFor(String section) {
  final key = _kAssistSection[section];
  if (key == null) return const [];
  return sectionSteps(
    key,
    skillSuggestions:
        key == LacunaKey.skills ? suggestedSkillsForAreas(const []) : const [],
    skillSuggester:
        key == LacunaKey.skills ? () => AIService().suggestProfileSkills() : null,
    citySearch: (q) async => (await _ibge.search(q))
        .map((c) => PickSuggestion(
              label: c.uf.isEmpty ? c.name : '${c.name} - ${c.uf}',
              value: c.uf.isEmpty ? c.name : '${c.name}|${c.uf}',
            ))
        .toList(),
    institutionSearch: (q) async => (await searchInstitutions(q))
        .map((i) => PickSuggestion(label: i.name, value: '${i.id}|${i.name}'))
        .toList(),
  );
}

/// Grounding compacto (SEM PII sensível) pro assistente: o que falta + um
/// inventário resumido. Failure-safe (erro ⇒ mapa vazio; o assistente ainda
/// responde/conduz, só sem personalizar tanto).
Future<Map<String, dynamic>> buildAssistContext(
  String userId, {
  ProfileRepository? repository,
  ProfileSnapshotService? snapshotService,
}) async {
  try {
    final repo = repository ?? ProfileRepositorySupabase();
    final snapSvc = snapshotService ?? ProfileSnapshotService();
    final snapshot = await snapSvc.loadSnapshot(userId);
    final prefs = await repo.getJobPreferences(userId);
    final desired = await repo.getDesiredTitles(userId);
    final gaps = profileGapsFromData(
        snapshot: snapshot, prefs: prefs, desiredTitles: desired);
    return {
      'completion_percent': gaps.completionPercent,
      'missing': [for (final l in gaps.missing) l.label],
      'areas': desired.map((d) => d.title).toList(),
      'desired_position': prefs?.desiredPosition,
      'skills_count': snapshot.skills.length,
      // Nomes das skills atuais — pro assistente MOSTRAR o que a pessoa já tem
      // (ver/editar) em vez de recomeçar a coleta. Cap pra não estourar tokens.
      'skills': [for (final s in snapshot.skills.take(40)) s.name],
      'experiences_count': snapshot.experiences.length,
      // Experiências com bullets (id + texto) — pro improve_bullet escolher qual.
      'experiences': [
        for (final e in snapshot.experiences.take(6))
          {
            'company': e.company,
            'title': e.title,
            'bullets': [
              for (final b in e.bullets)
                {
                  'id': b.id,
                  'text': b.text.length > 160
                      ? '${b.text.substring(0, 160)}…'
                      : b.text,
                }
            ],
          }
      ],
      // Nome + nível dos idiomas — pro assistente responder "qual meu nível de
      // inglês?" e o edit_languages ter base. '' quando sem nível.
      'languages': [
        for (final l in snapshot.languages)
          {'name': l.name, 'level': l.proficiencyLabel}
      ],
      // Nomes dos interesses atuais — pro assistente escolher edit_interests
      // (ver/editar) vs start_section (coletar do zero).
      'interests': [for (final i in snapshot.interests.take(30)) i.name],
      'has_summary': (snapshot.personal?.summary?.trim().isNotEmpty ?? false),
      // Resumo atual (texto do próprio usuário) — pra rewrite_summary reescrever
      // sem inventar. Cortado pra não estourar tokens.
      'summary': (snapshot.personal?.summary?.trim() ?? ''),
    };
  } catch (_) {
    return const {};
  }
}

/// Editor visual de skills — nomes das skills atuais (pra mostrar em chips).
/// Failure-safe: vazio ⇒ o assistente cai na coleta.
Future<List<String>> loadAssistSkills(
  String userId, {
  ProfileSnapshotService? snapshotService,
}) async {
  try {
    final snap =
        await (snapshotService ?? ProfileSnapshotService()).loadSnapshot(userId);
    return [for (final s in snap.skills) s.name];
  } catch (_) {
    return const [];
  }
}

/// Editor visual de skills — sugestões de skills pela ÁREA desejada (pra propor
/// adições). Failure-safe: vazio ⇒ o editor mostra só o campo de digitar.
Future<List<String>> assistSkillSuggestionsFor(
  String userId, {
  ProfileRepository? repository,
}) async {
  try {
    final repo = repository ?? ProfileRepositorySupabase();
    final desired = await repo.getDesiredTitles(userId);
    return suggestedSkillsForAreas(desired.map((d) => d.title).toList());
  } catch (_) {
    return const [];
  }
}

/// Editor visual de IDIOMAS — pares (nome, nível-canônico) atuais. O nível é o
/// id do banco ('basic'..'native') ou null. Failure-safe: vazio ⇒ cai na coleta.
Future<List<(String, String?)>> loadAssistLanguages(
  String userId, {
  ProfileSnapshotService? snapshotService,
}) async {
  try {
    final snap =
        await (snapshotService ?? ProfileSnapshotService()).loadSnapshot(userId);
    return [for (final l in snap.languages) (l.name, l.proficiency?.name)];
  } catch (_) {
    return const [];
  }
}

/// Editor visual de IDIOMAS — upsert de um idioma pelo nome (case-insensitive):
/// existe ⇒ atualiza o nível; não existe ⇒ insere com o nível. `level` é o id
/// canônico ('basic'..'native') ou null.
Future<void> assistUpsertLanguage(
  String userId,
  String name,
  String? level, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final n = name.trim();
  if (n.isEmpty) return;
  final prof = languageProficiencyFromId(level);
  final langs = await repo.getLanguages(userId);
  for (final l in langs) {
    if (l.name.trim().toLowerCase() == n.toLowerCase()) {
      // NÃO usar copyWith: `proficiency ?? this.proficiency` não consegue LIMPAR
      // o nível (setar null) — o undo de "definir nível" precisa disso.
      await repo.updateLanguage(Language(
          id: l.id,
          userId: l.userId,
          name: l.name,
          proficiency: prof,
          orderIndex: l.orderIndex));
      return;
    }
  }
  await repo.addLanguage(Language(id: '', userId: userId, name: n, proficiency: prof));
}

/// Editor visual de INTERESSES — nomes atuais. Failure-safe.
Future<List<String>> loadAssistInterests(
  String userId, {
  ProfileSnapshotService? snapshotService,
}) async {
  try {
    final snap =
        await (snapshotService ?? ProfileSnapshotService()).loadSnapshot(userId);
    return [for (final i in snap.interests) i.name];
  } catch (_) {
    return const [];
  }
}

/// Editor visual de INTERESSES — grava a lista FINAL (replace-all, como o
/// write-back da coleta). O editor computa o conjunto final e chama isto 1x.
Future<void> assistReplaceInterests(
  String userId,
  List<String> names, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final clean = <String>[];
  final seen = <String>{};
  for (final raw in names) {
    final n = raw.trim();
    if (n.isEmpty) continue;
    final lc = n.toLowerCase();
    if (seen.add(lc)) clean.add(n);
  }
  await repo.replaceInterests(userId, clean);
}

/// Fase B — LEITOR: valor atual de um campo editável pelo assistente
/// (`{raw, text, label}`; null ⇒ não editável por aqui — vai via start_section).
/// Por ora só `desired_position` (texto livre); o resto muda via chips/typeahead.
Future<Map<String, String>?> assistReadFieldMap(
  String userId,
  String field, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  switch (field) {
    case 'desired_position':
      final prefs = await repo.getJobPreferences(userId);
      final pos = prefs?.desiredPosition?.trim() ?? '';
      return {
        'raw': pos,
        'text': pos.isEmpty ? '—' : pos,
        'label': 'Cargo desejado',
      };
    case 'summary':
      final personal = await repo.getPersonal(userId);
      final s = personal?.summary?.trim() ?? '';
      return {'raw': s, 'text': s.isEmpty ? '—' : s, 'label': 'Resumo'};
  }
  return null;
}

/// Fase B — GRAVADOR: aplica um valor a um campo (reusa o write-back; savers
/// idempotentes). value '' ⇒ limpa (pro undo de um set-a-partir-de-vazio, que o
/// saver sozinho ignoraria).
Future<void> assistWriteFieldValue(
  String userId,
  String field,
  String value, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  switch (field) {
    case 'desired_position':
      final v = value.trim();
      if (v.isEmpty) {
        final prefs =
            await repo.getJobPreferences(userId) ?? JobPreferences(userId: userId);
        await repo.upsertJobPreferences(prefs.copyWith(desiredPosition: ''));
      } else {
        await TrilhaWriteback(repo, userId)
            .save(StepAnswer.text('gap.desired_position', v));
      }
      return;
    case 'summary':
      final personal =
          await repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
      await repo.upsertPersonal(personal.copyWith(summary: value.trim()));
      return;
  }
}

/// Fase B — ADICIONA um item de lista (skill/idioma) reusando o write-back
/// (merge/dedup — idempotente).
Future<void> assistAddItem(
  String userId,
  String kind,
  String value, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final v = value.trim();
  if (v.isEmpty) return;
  final wb = TrilhaWriteback(repo, userId);
  switch (kind) {
    case 'skill':
      await wb.save(
          StepAnswer.choice('gap.skills', [StepOption(id: v, label: v)]));
      return;
    case 'language':
      await wb.save(
          StepAnswer.choice('gap.languages', [StepOption(id: v, label: v)]));
      return;
    case 'interest':
      // Interesses são replace-all: acrescenta ao conjunto atual (dedup).
      final names = [for (final i in await repo.getInterests(userId)) i.name];
      if (names.any((n) => n.trim().toLowerCase() == v.toLowerCase())) return;
      await repo.replaceInterests(userId, [...names, v]);
      return;
  }
}

/// Fase B — REMOVE um item de lista pelo nome (case-insensitive; remove todos
/// os que casam exato).
Future<void> assistRemoveItem(
  String userId,
  String kind,
  String value, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final lc = value.trim().toLowerCase();
  if (lc.isEmpty) return;
  switch (kind) {
    case 'skill':
      for (final s in await repo.getSkills(userId)) {
        if (s.name.trim().toLowerCase() == lc) await repo.deleteSkill(s.id);
      }
      return;
    case 'language':
      for (final l in await repo.getLanguages(userId)) {
        if (l.name.trim().toLowerCase() == lc) await repo.deleteLanguage(l.id);
      }
      return;
    case 'interest':
      // Replace-all sem o que casa exato.
      final keep = [
        for (final i in await repo.getInterests(userId))
          if (i.name.trim().toLowerCase() != lc) i.name
      ];
      await repo.replaceInterests(userId, keep);
      return;
  }
}

/// Fase B — RESOLVE "qual item" remover: nomes que casam com a query (exato
/// primeiro; senão contains). 0 ⇒ não achou; 1 ⇒ segue; 2+ ⇒ desambigua.
Future<List<String>> assistResolveItems(
  String userId,
  String kind,
  String query, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  // Experiência: casa por cargo OU empresa; devolve um rótulo distinguível.
  if (kind == 'experience') {
    final out = <String>[];
    for (final e in await repo.getExperiences(userId)) {
      if ('${e.title} ${e.company}'.toLowerCase().contains(q)) {
        out.add(_expLabelOf(e.title, e.company));
      }
    }
    return out;
  }
  List<String> names;
  switch (kind) {
    case 'skill':
      names = (await repo.getSkills(userId)).map((s) => s.name).toList();
      break;
    case 'language':
      names = (await repo.getLanguages(userId)).map((l) => l.name).toList();
      break;
    case 'interest':
      names = (await repo.getInterests(userId)).map((i) => i.name).toList();
      break;
    default:
      return const [];
  }
  final exact = names.where((n) => n.trim().toLowerCase() == q).toList();
  if (exact.isNotEmpty) return exact;
  return names
      .where((n) =>
          n.trim().toLowerCase().contains(q) ||
          q.contains(n.trim().toLowerCase()))
      .toList();
}

/// Fase B — LÊ um bullet por id ({raw, text, label=experiência}). null ⇒ id
/// inválido.
Future<Map<String, String>?> assistBulletReadMap(
  String userId,
  String bulletId, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  for (final e in await repo.getExperiences(userId)) {
    for (final b in e.bullets) {
      if (b.id == bulletId) {
        return {
          'raw': b.text,
          'text': b.text,
          'label': e.company.trim().isEmpty ? e.title : e.company,
        };
      }
    }
  }
  return null;
}

/// Fase B — REESCREVE um bullet por id (updateBullet, preservando ângulo/ordem).
Future<void> assistBulletWrite(
  String userId,
  String bulletId,
  String text, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final t = text.trim();
  if (t.isEmpty) return;
  for (final e in await repo.getExperiences(userId)) {
    for (final b in e.bullets) {
      if (b.id == bulletId) {
        await repo.updateBullet(b.copyWith(text: t));
        return;
      }
    }
  }
}

/// Rótulo distinguível de uma experiência ("Cargo · Empresa").
String _expLabelOf(String title, String company) {
  final t = title.trim();
  final co = company.trim();
  if (t.isEmpty) return co;
  if (co.isEmpty) return t;
  return '$t · $co';
}

/// Fase B — remoção REVERSÍVEL de item multi-campo. Captura o registro, deleta,
/// e devolve um restore (que re-insere com id novo — o item volta, íntegro).
/// null ⇒ kind não tratado aqui (skill/idioma seguem no remover simples).
Future<Future<void> Function()?> assistReversibleRemove(
  String userId,
  String kind,
  String value, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  switch (kind) {
    case 'experience':
      for (final e in await repo.getExperiences(userId)) {
        final label = _expLabelOf(e.title, e.company);
        if (label == value ||
            e.company.trim() == value.trim() ||
            e.title.trim() == value.trim()) {
          final captured = e; // com bullets
          await repo.deleteExperience(e.id);
          return () async {
            final r = repository ?? ProfileRepositorySupabase();
            final saved = await r.addExperience(captured.copyWith(id: ''));
            for (final b in captured.bullets) {
              await r.addBullet(b.copyWith(id: '', experienceId: saved.id));
            }
          };
        }
      }
      return null;
  }
  return null;
}
