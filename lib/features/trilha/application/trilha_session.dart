// Montagem da sessão da trilha (PLANO-FASE-6 T6.3, Increment 2c + fix memória).
//
// Junta as peças: carrega o perfil real + os trechos já abordados (memória) →
// calcula as lacunas → monta o plano adaptativo (sem re-perguntar o que já foi
// abordado) → cria o ConversationController com o write-back plugado (grava em
// profile_* e marca cada trecho como abordado).

import '../../../services/ai_service.dart';
import '../../../services/analytics_events.dart';
import 'dart:typed_data';

import '../../../services/analytics_service.dart';
import '../../../services/cv_import_service.dart';
import '../../../services/profile_snapshot_service.dart';
import '../../profile/application/profile_gaps.dart';
import '../../profile/data/repositories/profile_repository_supabase.dart';
import '../../profile/domain/entities/job_preferences.dart'
    show
        JobPreferences,
        WorkMode,
        workModeFromId,
        workModeLabel,
        DesiredTitle,
        DesiredTitleSource;
import 'area_canonical.dart' show withInferredAreas;
import '../../profile/domain/entities/personal_info.dart' show PersonalInfo;
import '../../profile/domain/entities/education.dart' show Education;
import '../../profile/domain/entities/experiences.dart' show Experience, Bullet;
import '../../profile/domain/entities/simple_lists.dart'
    show Language, Certification, Award, Project, languageProficiencyFromId;
import '../../profile/domain/repositories/profile_repository.dart';
import 'cv_conflict.dart';
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

/// Grande (render estruturado) — lacunas do perfil pro card de show_gaps/
/// show_profile_summary: % de completude + o que falta ({key,tier,label}),
/// ordenado por tier (tier1 primeiro). Pula `summary` (é GERADO, não pedido).
/// NÃO é failure-safe DE PROPÓSITO: em erro RELANÇA, pro controller cair no
/// texto (senão um erro viraria um card "0% + tá completo", contraditório).
Future<
    ({
      int completionPercent,
      List<({String key, String tier, String label, String section})> missing
    })> loadAssistGaps(
  String userId, {
  ProfileRepository? repository,
  ProfileSnapshotService? snapshotService,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final snapSvc = snapshotService ?? ProfileSnapshotService();
  final snapshot = await snapSvc.loadSnapshot(userId);
  final prefs = await repo.getJobPreferences(userId);
  final desired = await repo.getDesiredTitles(userId);
  final gaps =
      profileGapsFromData(snapshot: snapshot, prefs: prefs, desiredTitles: desired);
  const tierOrder = {'tier1': 0, 'tier2': 1, 'tier3': 2};
  final missing = [
    for (final l in gaps.missing)
      if (l.key != LacunaKey.summary)
        (
          key: l.key.name,
          tier: l.tier.name,
          label: l.label,
          // section pra o card virar botão "preencher"; '' ⇒ não conduzível.
          section: _sectionForLacuna(l.key) ?? '',
        )
  ]..sort((a, b) =>
      (tierOrder[a.tier] ?? 9).compareTo(tierOrder[b.tier] ?? 9));
  return (completionPercent: gaps.completionPercent, missing: missing);
}

/// Widget de conflito de import — carrega o CV parseado (dry-run: sem gravar) e
/// diffa contra o perfil atual. Devolve as linhas do card. Failure-safe: erro
/// ou CV sem dados úteis ⇒ lista vazia.
Future<List<ConflictRow>> loadCvConflicts(
  String userId,
  Uint8List pdfBytes, {
  String? rawTextFallback,
  ProfileRepository? repository,
  ProfileSnapshotService? snapshotService,
}) async {
  try {
    final cv = await CvImportService.extractProfile(pdfBytes,
        save: false, rawTextFallback: rawTextFallback);
    if (cv == null) return const [];
    final snapSvc = snapshotService ?? ProfileSnapshotService();
    final snapshot = await snapSvc.loadSnapshot(userId);
    return CvConflictDiff.compute(cv, snapshot);
  } catch (_) {
    return const [];
  }
}

DateTime? _parseCvDate(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d{4})(?:-(\d{1,2}))?').firstMatch(t);
  if (m == null) return null;
  final year = int.tryParse(m.group(1)!);
  if (year == null) return null;
  final month = int.tryParse(m.group(2) ?? '1') ?? 1;
  return DateTime(year, month.clamp(1, 12));
}

String? _nn(dynamic v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? null : s;
}

/// Aplica UMA linha de conflito ESCOLHIDA e devolve o undo (reverte só ela).
/// [value] = valor efetivo (pode ter sido editado pelo usuário). null ⇒ não
/// aplicou (nada a fazer). Centraliza o apply de todas as seções reusando os
/// write-backs do assistente + os adders do repo.
Future<Future<void> Function()?> assistApplyConflictRow(
  String userId,
  ConflictRow row,
  String value, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  switch (row.section) {
    // Escalares → write-back; undo restaura o valor anterior ('' se era adição).
    case ConflictSection.name:
    case ConflictSection.phone:
    case ConflictSection.city:
    case ConflictSection.summary:
    case ConflictSection.linkedin:
    case ConflictSection.website:
      final before = row.currentText;
      await assistWriteFieldValue(userId, row.field, value, repository: repo);
      return () =>
          assistWriteFieldValue(userId, row.field, before, repository: repo);
    case ConflictSection.skill:
      await assistAddItem(userId, 'skill', value, repository: repo);
      return () => assistRemoveItem(userId, 'skill', value, repository: repo);
    case ConflictSection.interest:
      await assistAddItem(userId, 'interest', value, repository: repo);
      return () => assistRemoveItem(userId, 'interest', value, repository: repo);
    case ConflictSection.language:
      // Captura o nível anterior (pro undo do conflito de nível).
      final existing = (await repo.getLanguages(userId))
          .where((l) => l.name.toLowerCase() == value.toLowerCase())
          .toList();
      final oldLevel = existing.isEmpty ? null : existing.first.proficiency;
      await assistUpsertLanguage(userId, value,
          row.extra.isEmpty ? null : row.extra,
          repository: repo);
      if (existing.isEmpty) {
        return () => assistRemoveItem(userId, 'language', value, repository: repo);
      }
      return () => repo.updateLanguage(existing.first.copyWith(proficiency: oldLevel));
    case ConflictSection.certification:
      final c = await repo.addCertification(Certification(
          id: '', userId: userId, name: value, issuer: _nn(row.extra)));
      return () => repo.deleteCertification(c.id);
    case ConflictSection.award:
      final a = await repo.addAward(Award(id: '', userId: userId, name: value));
      return () => repo.deleteAward(a.id);
    case ConflictSection.project:
      final p = await repo.addProject(Project(id: '', userId: userId, name: value));
      return () => repo.deleteProject(p.id);
    case ConflictSection.coursework:
      final cur = (await repo.getCoursework(userId)).map((c) => c.name).toList();
      await repo.replaceCoursework(userId, [...cur, value]);
      return () => repo.replaceCoursework(userId, cur);
    case ConflictSection.experience:
      if (row.kind == ConflictKind.conflict) {
        final before = row.currentText;
        await assistWriteItemField(
            userId, 'experience', row.refId, row.field, value,
            repository: repo);
        return () => assistWriteItemField(
            userId, 'experience', row.refId, row.field, before,
            repository: repo);
      }
      final it = row.cvItem;
      final start = _parseCvDate((it['start_date'] ?? '').toString());
      // Sem data parseável → NÃO inventa "hoje" (poluiria a ordenação/PDF).
      if (start == null) return null;
      final created = await repo.addExperience(Experience(
        id: '',
        userId: userId,
        title: (it['title'] ?? '').toString().trim(),
        company: (it['company'] ?? '').toString().trim(),
        location: _nn(it['location']),
        startDate: start,
        endDate: _parseCvDate((it['end_date'] ?? '').toString()),
        isCurrent: it['is_current'] == true,
      ));
      // Bullets best-effort: uma falha aqui NÃO pode deixar a experiência órfã
      // sem undo (o undo já é a deleção da experiência, com cascade nos bullets).
      try {
        for (final b
            in (it['bullets'] is List ? it['bullets'] as List : const [])) {
          final text = b is Map ? (b['text'] ?? '').toString().trim() : '';
          if (text.isNotEmpty) {
            await repo.addBullet(
                Bullet(id: '', experienceId: created.id, text: text));
          }
        }
      } catch (_) {/* bullets são best-effort */}
      return () => repo.deleteExperience(created.id);
    case ConflictSection.education:
      if (row.kind == ConflictKind.conflict) {
        final before = row.currentText;
        await assistWriteItemField(
            userId, 'education', row.refId, row.field, value,
            repository: repo);
        return () => assistWriteItemField(
            userId, 'education', row.refId, row.field, before,
            repository: repo);
      }
      final it = row.cvItem;
      final created = await repo.addEducation(Education(
        id: '',
        userId: userId,
        institution: (it['institution'] ?? '').toString().trim(),
        degree: _nn(it['degree']),
        location: _nn(it['location']),
      ));
      return () => repo.deleteEducation(created.id);
  }
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
      // Seções multi-campo — só os rótulos, pro assistente SABER que existem
      // (ver/remover/referenciar). O app resolve o item real pelo rótulo.
      'education': [for (final Education e in snapshot.education) eduLabel(e)],
      'certifications': [
        for (final Certification c in snapshot.certifications) c.name
      ],
      'awards': [for (final Award a in snapshot.awards) a.name],
      'projects': [for (final Project p in snapshot.projects) p.name],
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

/// Editor visual de ÁREAS — só as áreas VISÍVEIS do usuário (user_added), sem as
/// canônicas ocultas (inferred). Failure-safe.
Future<List<String>> loadAssistAreas(
  String userId, {
  ProfileRepository? repository,
}) async {
  try {
    final repo = repository ?? ProfileRepositorySupabase();
    return [
      for (final t in await repo.getDesiredTitles(userId))
        if ((t.source ?? DesiredTitleSource.userAdded) !=
            DesiredTitleSource.inferred)
          t.title
    ];
  } catch (_) {
    return const [];
  }
}

/// Editor visual de ÁREAS — grava a lista FINAL (replace-all), REGERANDO a
/// canônica oculta (inferred) de cada área não-canônica pra o candidato seguir
/// matchável no feed/busca (mesma lógica do write-back da coleta).
Future<void> assistReplaceAreas(
  String userId,
  List<String> areas, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  // Constrói as áreas VISÍVEIS (user_added, dedup por título) e delega o resto
  // — canônica oculta + normalização de caixa — pro ponto único withInferredAreas
  // (mesma derivação da coleta e do editor do perfil).
  final userAreas = <DesiredTitle>[];
  final seen = <String>{};
  for (final area in areas) {
    final t = area.trim();
    if (t.isEmpty) continue;
    if (!seen.add(t.toLowerCase())) continue;
    userAreas.add(DesiredTitle(
      id: '',
      userId: userId,
      title: t,
      source: DesiredTitleSource.userAdded,
      orderIndex: userAreas.length,
    ));
  }
  await repo.replaceDesiredTitles(userId, withInferredAreas(userId, userAreas));
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
    case 'name':
      final p = await repo.getPersonal(userId);
      final full =
          '${p?.firstName ?? ''} ${p?.lastName ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
      return {'raw': full, 'text': full.isEmpty ? '—' : full, 'label': 'Nome'};
    case 'linkedin':
      final p = await repo.getPersonal(userId);
      final v = p?.linkedinUrl?.trim() ?? '';
      return {'raw': v, 'text': v.isEmpty ? '—' : v, 'label': 'LinkedIn'};
    case 'website':
      final p = await repo.getPersonal(userId);
      final v = p?.website?.trim() ?? '';
      return {'raw': v, 'text': v.isEmpty ? '—' : v, 'label': 'Site/portfólio'};
    case 'phone':
      final p = await repo.getPersonal(userId);
      final v = p?.phoneNumber?.trim() ?? '';
      return {'raw': v, 'text': v.isEmpty ? '—' : v, 'label': 'Telefone'};
    case 'city':
      final p = await repo.getPersonal(userId);
      final city = p?.locationCity?.trim() ?? '';
      final st = p?.locationState?.trim() ?? '';
      final show = city.isEmpty ? '' : (st.isEmpty ? city : '$city, $st');
      return {'raw': show, 'text': show.isEmpty ? '—' : show, 'label': 'Cidade'};
    case 'work_mode':
      final prefs = await repo.getJobPreferences(userId);
      final modes = prefs?.workMode ?? const <WorkMode>[];
      final ids = modes.map((mo) => mo.name).join(',');
      final labels = modes.map(workModeLabel).join(', ');
      return {'raw': ids, 'text': labels.isEmpty ? '—' : labels, 'label': 'Modalidade'};
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
    case 'name':
      final p = await repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
      final parts =
          value.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      // Sobrenome = ÚLTIMA palavra; nome = o resto. Isso torna o par
      // read("nome sobrenome")→write→read um round-trip idempotente (o Desfazer
      // vira no-op de verdade) e casa melhor com nomes compostos pt-BR
      // ("Ana Paula Ferreira" → nome "Ana Paula", sobrenome "Ferreira").
      final first = parts.length <= 1
          ? (parts.isEmpty ? '' : parts.first)
          : parts.sublist(0, parts.length - 1).join(' ');
      final last = parts.length <= 1 ? '' : parts.last;
      await repo.upsertPersonal(p.copyWith(firstName: first, lastName: last));
      return;
    case 'linkedin':
      final p = await repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
      await repo.upsertPersonal(p.copyWith(linkedinUrl: value.trim()));
      return;
    case 'website':
      final p = await repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
      await repo.upsertPersonal(p.copyWith(website: value.trim()));
      return;
    case 'phone':
      final p = await repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
      await repo.upsertPersonal(p.copyWith(phoneNumber: value.trim()));
      return;
    case 'city':
      final p = await repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
      // "Cidade|UF" (typeahead) ou "Cidade, UF" ou só "Cidade".
      final raw = value.trim();
      var city = raw;
      String? st;
      if (raw.contains('|')) {
        final parts = raw.split('|');
        city = parts[0].trim();
        if (parts.length >= 2 && parts[1].trim().isNotEmpty) st = parts[1].trim();
      } else if (raw.contains(',')) {
        final parts = raw.split(',');
        city = parts[0].trim();
        if (parts.length >= 2 && parts[1].trim().isNotEmpty) st = parts[1].trim();
      }
      // UF do value é autoritativa: sem UF no texto ⇒ estado limpo (troca de
      // cidade não herda a UF antiga, e o undo pra uma cidade sem UF restaura
      // null certinho). O reader reemite "Cidade, UF" sempre que há estado.
      // O CEP também é LIMPO: era de outra cidade (ex.: trocar Londrina→Recife
      // deixava o CEP de Londrina), gerando par CEP/cidade impossível.
      await repo.upsertPersonal(
        p.copyWith(
          locationCity: city,
          locationState: st,
          clearLocationState: true,
          clearLocationPostalCode: true,
          locationCountry: p.locationCountry ?? 'BR',
        ),
        // Força o NULL no banco (o upsert parcial descarta nulls): o CEP SEMPRE
        // some (era de outra cidade); a UF some quando o value não traz UF.
        nullColumns: {'location_postal_code', if (st == null) 'location_state'},
      );
      return;
    case 'work_mode':
      final prefs =
          await repo.getJobPreferences(userId) ?? JobPreferences(userId: userId);
      // value = ids separados por vírgula (remote,hybrid,in_person). Replace.
      final modes = value
          .split(',')
          .map((s) => workModeFromId(s))
          .whereType<WorkMode>()
          .toSet()
          .toList();
      // Guarda: value NÃO-vazio que não casa nenhum id NÃO apaga a modalidade
      // (o card mostraria um label plausível e zeraria o campo). Só o undo
      // pra vazio (value == '') pode gravar lista vazia.
      if (modes.isEmpty && value.trim().isNotEmpty) return;
      await repo.upsertJobPreferences(prefs.copyWith(workMode: modes));
      return;
  }
}

/// True se [value] (ids separados por vírgula) casa ≥1 modalidade válida.
/// Usado no propose de work_mode pra não mostrar um card que zeraria o campo.
bool assistWorkModeValueValid(String value) => value
    .split(',')
    .map((s) => workModeFromId(s))
    .whereType<WorkMode>()
    .isNotEmpty;

/// Médios — LÊ um campo de item multi-campo (experiência/formação/cert),
/// resolvendo QUAL item pela query. Retorna {id, raw, text, label}; null ⇒ item
/// ou campo não encontrado. O `id` é estável (pro write/undo por id).
Future<Map<String, String>?> assistReadItemField(
  String userId,
  String kind,
  String query,
  String field, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  Map<String, String> m(String id, String raw, String label) =>
      {'id': id, 'raw': raw, 'text': raw.trim().isEmpty ? '—' : raw, 'label': label};
  switch (kind) {
    case 'experience':
      final list = await repo.getExperiences(userId);
      final e = _pickByName(list, (x) => _expLabelOf(x.title, x.company), query) ??
          _pickByName(list, (x) => x.company, query) ??
          _pickByName(list, (x) => x.title, query);
      if (e == null) return null;
      switch (field) {
        case 'title':
          return m(e.id, e.title, 'Cargo · ${e.company}');
        case 'company':
          return m(e.id, e.company, 'Empresa · ${e.title}');
      }
      return null;
    case 'education':
      final list = await repo.getEducation(userId);
      final ed = _pickByName(list, eduLabel, query) ??
          _pickByName(list, (x) => x.institution, query);
      if (ed == null) return null;
      final tag = eduLabel(ed);
      switch (field) {
        case 'degree':
          return m(ed.id, ed.degree ?? '', 'Curso · $tag');
        case 'institution':
          return m(ed.id, ed.institution, 'Instituição');
        case 'semester':
          return m(ed.id, ed.currentSemester?.toString() ?? '', 'Semestre · $tag');
      }
      return null;
    case 'certification':
      final list = await repo.getCertifications(userId);
      final c = _pickByName(list, (x) => x.name, query);
      if (c == null) return null;
      switch (field) {
        case 'name':
          return m(c.id, c.name, 'Certificação');
        case 'issuer':
          return m(c.id, c.issuer ?? '', 'Emissor · ${c.name}');
      }
      return null;
  }
  return null;
}

/// Médios — GRAVA um campo de um item multi-campo (por id estável, via updateX).
Future<void> assistWriteItemField(
  String userId,
  String kind,
  String id,
  String field,
  String value, {
  ProfileRepository? repository,
}) async {
  final repo = repository ?? ProfileRepositorySupabase();
  final v = value.trim();
  switch (kind) {
    case 'experience':
      final e = _firstById(await repo.getExperiences(userId), (x) => x.id, id);
      if (e == null) return;
      if (field == 'title') await repo.updateExperience(e.copyWith(title: v));
      if (field == 'company') await repo.updateExperience(e.copyWith(company: v));
      return;
    case 'education':
      final ed = _firstById(await repo.getEducation(userId), (x) => x.id, id);
      if (ed == null) return;
      if (field == 'degree') await repo.updateEducation(ed.copyWith(degree: v));
      if (field == 'institution') {
        // Trocar o NOME da instituição invalida o vínculo canônico antigo
        // (institution_id) — senão o candidato fica classificado sob a IES
        // errada na busca das empresas.
        await repo.updateEducation(
            ed.copyWith(institution: v, clearInstitutionId: true));
      }
      if (field == 'semester') {
        if (v.isEmpty) {
          // undo pra vazio → LIMPA o semestre (senão o valor novo ficaria).
          await repo.updateEducation(ed.copyWith(clearCurrentSemester: true));
        } else {
          final n = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), ''));
          if (n != null) {
            await repo.updateEducation(ed.copyWith(currentSemester: n));
          }
        }
      }
      return;
    case 'certification':
      final c = _firstById(await repo.getCertifications(userId), (x) => x.id, id);
      if (c == null) return;
      if (field == 'name') await repo.updateCertification(c.copyWith(name: v));
      if (field == 'issuer') await repo.updateCertification(c.copyWith(issuer: v));
      return;
  }
}

T? _firstById<T>(List<T> items, String Function(T) idOf, String id) {
  for (final it in items) {
    if (idOf(it) == id) return it;
  }
  return null;
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
      final flat = '${e.title} ${e.company}'.toLowerCase();
      // Casa também o rótulo "Cargo · Empresa" (o que a desambiguação mostra),
      // pra a pessoa poder re-digitar a opção oferecida.
      final lbl = _expLabelOf(e.title, e.company).toLowerCase();
      if (flat.contains(q) || lbl.contains(q)) {
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
    case 'certification':
      names = (await repo.getCertifications(userId)).map((c) => c.name).toList();
      break;
    case 'award':
      names = (await repo.getAwards(userId)).map((a) => a.name).toList();
      break;
    case 'project':
      names = (await repo.getProjects(userId)).map((p) => p.name).toList();
      break;
    case 'education':
      names = (await repo.getEducation(userId)).map(eduLabel).toList();
      break;
    default:
      return const [];
  }
  // Ignora nomes vazios (senão q.contains('') casa qualquer query = fantasma).
  names = names.where((n) => n.trim().isNotEmpty).toList();
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
    case 'certification':
      final c = _pickByName(await repo.getCertifications(userId), (x) => x.name, value);
      if (c == null) return null;
      await repo.deleteCertification(c.id);
      return () async => (repository ?? ProfileRepositorySupabase())
          .addCertification(c.copyWith(id: ''));
    case 'award':
      final a = _pickByName(await repo.getAwards(userId), (x) => x.name, value);
      if (a == null) return null;
      await repo.deleteAward(a.id);
      return () async => (repository ?? ProfileRepositorySupabase())
          .addAward(a.copyWith(id: ''));
    case 'project':
      final p = _pickByName(await repo.getProjects(userId), (x) => x.name, value);
      if (p == null) return null;
      await repo.deleteProject(p.id);
      return () async => (repository ?? ProfileRepositorySupabase())
          .addProject(p.copyWith(id: ''));
    case 'education':
      final list = await repo.getEducation(userId);
      // Casa pelo rótulo composto (curso · instituição) e, se não, por
      // instituição — mas SEMPRE exato-primeiro (via _pickByName).
      final ed = _pickByName(list, eduLabel, value) ??
          _pickByName(list, (x) => x.institution, value);
      if (ed == null) return null;
      await repo.deleteEducation(ed.id);
      // Undo re-insere o registro (nível superior; sub-itens raros).
      return () async => (repository ?? ProfileRepositorySupabase())
          .addEducation(ed.copyWith(id: ''));
  }
  return null;
}

/// Rótulo distinguível de uma formação ("Curso · Instituição").
String eduLabel(Education e) {
  final d = (e.degree ?? '').trim();
  final inst = e.institution.trim();
  if (d.isEmpty) return inst;
  if (inst.isEmpty) return d;
  return '$d · $inst';
}

/// Escolhe QUAL item casar com o que o resolver/usuário disse: nome EXATO
/// (case-insensitive) primeiro; senão o 1º cujo nome CONTÉM o value. NÃO usa o
/// sentido value.contains(name) — senão um item curto ("Java") engoliria uma
/// query longa ("Java SE 8") e o app removeria o item ERRADO.
T? _pickByName<T>(List<T> items, String Function(T) nameOf, String value) {
  final b = value.trim().toLowerCase();
  if (b.isEmpty) return null;
  for (final it in items) {
    if (nameOf(it).trim().toLowerCase() == b) return it;
  }
  for (final it in items) {
    final a = nameOf(it).trim().toLowerCase();
    if (a.isNotEmpty && a.contains(b)) return it;
  }
  return null;
}
