// Write-back da trilha (PLANO-FASE-6 T6.3, Increment 2b).
//
// Grava as respostas da conversa nas tabelas profile_*, roteando por
// StepAnswer.stepId. Faz MERGE/dedup com o que já existe — nunca sobrescreve
// cegamente (espelha a filosofia do TrailToProfileBridge, mas limpo e
// desacoplado do legacy, R6). É plugado no gancho [ConversationController.onAnswer];
// o controller já trata erros de forma defensiva, então aqui focamos na gravação.

import '../../profile/domain/entities/entities.dart';
import '../../profile/domain/profile_title.dart';
import '../../profile/domain/repositories/profile_repository.dart';
import '../data/guided_language_writer_supabase.dart';
import '../data/guided_skills_writer_supabase.dart';
import '../domain/conversation_step.dart';
import '../domain/guided_language_write.dart';
import '../domain/guided_skills_write.dart';
import 'area_canonical.dart';
import 'linkedin_url.dart';
import 'trilha_draft.dart';

class TrilhaWriteback {
  final ProfileRepository _repo;
  final String userId;

  /// Writer aditivo/idempotente das skills da coleta guiada (Gate 3.0C).
  /// Substitui o antigo `get → replaceSkills` por `merge_guided_profile_list`.
  final GuidedSkillsWriter _guidedSkillsWriter;

  /// Writers de idioma da coleta guiada (Gate 3.0F): add (merge aditivo) e
  /// nível (CAS; manual recente vence).
  final GuidedLanguageWriter _guidedLanguageWriter;

  /// Persistência do RASCUNHO de item em construção (resumabilidade por passo).
  /// Nulo ⇒ sem rascunho (testes/uso sem retomada).
  final TrilhaDraftStore? _draftStore;

  /// Acumula os campos de cada experiência (coletados em passos separados) até
  /// ter o suficiente pra gravar. Chave = índice 'n' do passo 'exp.{n}.*'.
  final Map<int, _ExpBuffer> _expBuffers = {};
  final Map<int, _ProjBuffer> _projBuffers = {};
  final Map<int, _CertBuffer> _certBuffers = {};
  final Map<int, _AwardBuffer> _awardBuffers = {};
  _EduBuffer? _eduBuffer;

  TrilhaWriteback(
    this._repo,
    this.userId, {
    GuidedSkillsWriter? guidedSkillsWriter,
    GuidedLanguageWriter? guidedLanguageWriter,
    TrilhaDraftStore? draftStore,
  })  : _guidedSkillsWriter =
            guidedSkillsWriter ?? GuidedSkillsWriterSupabase(),
        _guidedLanguageWriter =
            guidedLanguageWriter ?? GuidedLanguageWriterSupabase(),
        _draftStore = draftStore;

  /// Reidrata os buffers a partir dos rascunhos salvos (chamado na abertura,
  /// ANTES de criar o controller) — pra o save terminal ver TODOS os campos.
  void seedFromDrafts(List<TrilhaItemDraft> drafts) {
    for (final d in drafts) {
      switch (d.kind) {
        case 'experience':
          _expBuffers[d.itemIndex] = _ExpBuffer.fromJson(d.fields);
          break;
        case 'project':
          _projBuffers[d.itemIndex] = _ProjBuffer.fromJson(d.fields);
          break;
        case 'education':
          _eduBuffer = _EduBuffer.fromJson(d.fields);
          break;
      }
    }
  }

  Future<void> _persistDraft(
      String kind, int n, String lastStepId, Map<String, dynamic> fields) async {
    await _draftStore?.save(
        userId,
        TrilhaItemDraft(
            kind: kind, itemIndex: n, lastStepId: lastStepId, fields: fields));
  }

  Future<void> _clearDraft(String kind) async =>
      _draftStore?.delete(userId, kind);

  /// Grava uma resposta. Passos sem mapeamento (ex.: 'intro') são no-op.
  Future<void> save(StepAnswer answer) async {
    if (answer.stepId.startsWith('exp.')) {
      await _handleExperience(answer);
      return;
    }
    if (answer.stepId.startsWith('cert.')) {
      await _handleCertification(answer);
      return;
    }
    if (answer.stepId.startsWith('award.')) {
      await _handleAward(answer);
      return;
    }
    if (answer.stepId.startsWith('project.')) {
      await _handleProject(answer);
      return;
    }
    // 'gap.edu.*' → educação (momento + faculdade/escola + curso + semestre/ano).
    if (answer.stepId.startsWith('gap.edu.')) {
      await _handleEducation(answer);
      return;
    }
    // 'gap.skills' (escolha) e 'gap.skills.more' (sugestão da IA) → mesmas skills.
    if (answer.stepId.startsWith('gap.skills')) {
      await _saveSkills(_ids(answer));
      return;
    }
    // 'lang.level.{Idioma}' → atualiza a proficiência do idioma.
    if (answer.stepId.startsWith('lang.level.')) {
      await _saveLanguageLevel(
          answer.stepId.substring('lang.level.'.length), _ids(answer));
      return;
    }
    switch (answer.stepId) {
      case 'gap.area':
        await _saveAreas(_ids(answer));
        break;
      case 'gap.desired_position':
        await _saveDesiredPosition(_text(answer));
        break;
      case 'linkedin.url':
        await _saveLinkedin(_text(answer));
        break;
      case 'gap.workmode':
        await _saveWorkMode(_ids(answer));
        break;
      case 'gap.jobtype':
        await _saveJobTypes(_ids(answer));
        break;
      case 'gap.city':
        await _saveCity(_text(answer));
        break;
      case 'gap.languages':
        await _saveLanguages(_ids(answer));
        break;
      case 'gap.availability':
        await _saveAvailability(_ids(answer));
        break;
      case 'gap.interests':
        await _saveInterests(_ids(answer));
        break;
      case 'gap.company_stage':
        await _saveCulturalFit(companyStage: _ids(answer));
        break;
      case 'gap.work_environment':
        await _saveCulturalFit(workEnvironment: _ids(answer));
        break;
      case 'gap.work_style':
        await _saveCulturalFit(workStyle: _ids(answer));
        break;
      default:
        break; // 'intro' e desconhecidos
    }
  }

  // ── Helpers de extração ──────────────────────────────────────────────────
  List<String> _ids(StepAnswer a) =>
      a.value is List ? (a.value as List).whereType<String>().toList() : const [];

  String _text(StepAnswer a) => a.value is String ? a.value as String : '';

  // ── Áreas → profile_desired_titles (merge dedup + canônica oculta) ───────
  // O usuário pode adicionar QUALQUER área (texto livre). Guardamos a área dele
  // (source='user_added', visível) e, se ela não for uma das 13 canônicas, uma
  // linha CANÔNICA oculta (source='inferred') pro candidato ficar matchável no
  // match/feed/busca — que só entendem as 13. Fase 7 · +10 (Tarefa 2).
  Future<void> _saveAreas(List<String> areas) async {
    final clean = areas.where((a) => a.trim().isNotEmpty).toList();
    if (clean.isEmpty) return;
    final existing = await _repo.getDesiredTitles(userId);

    // Dedup por título (case-insensitive). Precedência: uma área explícita do
    // usuário nunca fica oculta por um 'inferred' anterior (upgrade abaixo).
    final byKey = <String, DesiredTitle>{};
    void put(String rawTitle, DesiredTitleSource source) {
      final t = rawTitle.trim();
      if (t.isEmpty) return;
      final key = t.toLowerCase();
      final prev = byKey[key];
      if (prev == null) {
        byKey[key] = DesiredTitle(
          id: '',
          userId: userId,
          title: t,
          source: source,
          orderIndex: byKey.length,
        );
      } else if (prev.source == DesiredTitleSource.inferred &&
          source != DesiredTitleSource.inferred) {
        // Área que era só canônica-oculta e agora o usuário escolheu de fato.
        byKey[key] = prev.copyWith(source: source, title: t);
      }
    }

    for (final t in existing) {
      put(t.title, t.source ?? DesiredTitleSource.userAdded);
    }
    for (final area in clean) {
      put(area, DesiredTitleSource.userAdded);
      if (!isCanonicalArea(area)) {
        put(canonicalArea(area), DesiredTitleSource.inferred);
      }
    }

    // Só grava se algo mudou (título novo OU upgrade de source).
    final changed = byKey.length != existing.length ||
        !existing.every((e) =>
            byKey[e.title.toLowerCase().trim()]?.source ==
            (e.source ?? DesiredTitleSource.userAdded));
    if (!changed) return;
    await _repo.replaceDesiredTitles(userId, byKey.values.toList());
  }

  // ── Modalidade → profile_job_preferences.work_mode (merge) ───────────────
  Future<void> _saveWorkMode(List<String> ids) async {
    final modes = ids.map(_workModeFromId).whereType<WorkMode>().toList();
    if (modes.isEmpty) return;
    final existing =
        await _repo.getJobPreferences(userId) ?? JobPreferences(userId: userId);
    final merged = {...existing.workMode, ...modes}.toList();
    if (merged.length == existing.workMode.length) return;
    await _repo.upsertJobPreferences(existing.copyWith(workMode: merged));
  }

  // ── Tipo de vaga → profile_job_preferences.job_types (merge) ─────────────
  Future<void> _saveJobTypes(List<String> ids) async {
    final types = ids.map(_jobTypeFromId).whereType<JobType>().toList();
    if (types.isEmpty) return;
    final existing =
        await _repo.getJobPreferences(userId) ?? JobPreferences(userId: userId);
    final merged = {...existing.jobTypes, ...types}.toList();
    if (merged.length == existing.jobTypes.length) return;
    await _repo.upsertJobPreferences(existing.copyWith(jobTypes: merged));
  }

  // ── Cargo desejado → profile_job_preferences.desired_position ────────────
  // Pulou (vazio) → não grava (o segmento já marca como abordado, não re-pergunta).
  Future<void> _saveDesiredPosition(String raw) async {
    final pos = raw.trim();
    if (pos.isEmpty) return;
    final existing =
        await _repo.getJobPreferences(userId) ?? JobPreferences(userId: userId);
    if (existing.desiredPosition == pos) return; // idempotente
    await _repo.upsertJobPreferences(existing.copyWith(desiredPosition: pos));
  }

  // ── Cidade → profile_personal.location_city/_state ───────────────────────
  Future<void> _saveCity(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    String city = text;
    String? state;
    // Typeahead canônico do IBGE: 'Cidade|UF'. Retrocompat: 'Cidade, UF'.
    if (text.contains('|')) {
      final p = text.split('|');
      city = p[0].trim();
      if (p.length >= 2 && p[1].trim().isNotEmpty) state = p[1].trim();
    } else {
      final parts = text.split(','); // "São Paulo, SP"
      if (parts.length >= 2 && parts[1].trim().isNotEmpty) {
        city = parts[0].trim();
        state = parts[1].trim();
      }
    }
    final existing =
        await _repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
    await _repo.upsertPersonal(existing.copyWith(
      locationCity: city,
      locationState: state ?? existing.locationState,
      locationCountry: existing.locationCountry ?? 'BR',
    ));
  }

  // ── LinkedIn → profile_personal.linkedin_url ─────────────────────────────
  Future<void> _saveLinkedin(String raw) async {
    final url = normalizeLinkedinUrl(raw); // garante https / monta vanity
    if (url == null) return; // vazio
    final existing =
        await _repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
    await _repo.upsertPersonal(existing.copyWith(linkedinUrl: url));
  }

  // ── Certificação → profile_certifications (ATÔMICO no último passo: date) ──
  // Acumula nome + emissor + data num buffer e grava de uma vez no passo
  // terminal (cert.{n}.date) — emissor/data são opcionais (podem vir vazios).
  Future<void> _handleCertification(StepAnswer a) async {
    final parts = a.stepId.split('.'); // cert.{n}.{field}
    if (parts.length < 3) return; // 'cert.gate'
    final n = int.tryParse(parts[1]);
    if (n == null) return;
    final buf = _certBuffers.putIfAbsent(n, () => _CertBuffer());
    switch (parts[2]) {
      case 'name':
        buf.name = _text(a);
        break;
      case 'issuer':
        buf.issuer = _text(a);
        break;
      case 'date':
        buf.date = _parseMonth(_text(a));
        await _saveCertification(n, buf); // último passo → grava a cert
        break;
      // 'more' → controle de fluxo, no-op
    }
  }

  Future<void> _saveCertification(int n, _CertBuffer buf) async {
    final name = buf.name?.trim() ?? '';
    if (name.isEmpty) {
      throw StateError('invalid_guided_certification');
    }
    final issuer = buf.issuer?.trim();
    final desired = Certification(
      id: '',
      userId: userId,
      name: name,
      issuer: (issuer != null && issuer.isNotEmpty) ? issuer : null,
      date: buf.date,
    );
    final existing = await _repo.getCertifications(userId);
    if (!existing.any((certification) =>
        _sameText(certification.name, desired.name) &&
        _sameText(certification.issuer, desired.issuer) &&
        _sameMonth(certification.date, desired.date))) {
      await _repo.addCertification(desired);
    }
    _certBuffers.remove(n);
  }

  // ── Conquistas/prêmios → profile_awards (ATÔMICO no último passo: date) ────
  Future<void> _handleAward(StepAnswer a) async {
    final parts = a.stepId.split('.'); // award.{n}.{field}
    if (parts.length < 3) return; // 'award.gate'
    final n = int.tryParse(parts[1]);
    if (n == null) return;
    final buf = _awardBuffers.putIfAbsent(n, () => _AwardBuffer());
    switch (parts[2]) {
      case 'name':
        buf.name = _text(a);
        break;
      case 'date':
        buf.date = _parseMonth(_text(a));
        await _saveAward(n, buf); // último passo → grava a conquista
        break;
      // 'more' → controle de fluxo, no-op
    }
  }

  Future<void> _saveAward(int n, _AwardBuffer buf) async {
    final name = normalizeProfileTitle(buf.name ?? '');
    if (name.isEmpty) {
      throw StateError('invalid_guided_award');
    }
    final desired = Award(id: '', userId: userId, name: name, date: buf.date);
    final existing = await _repo.getAwards(userId);
    if (!existing.any((award) =>
        _sameText(award.name, desired.name) &&
        _sameMonth(award.date, desired.date))) {
      await _repo.addAward(desired);
    }
    _awardBuffers.remove(n);
  }

  // ── Disponibilidade → profile_personal.availability ──────────────────────
  Future<void> _saveAvailability(List<String> ids) async {
    final id = ids.isNotEmpty ? ids.first.trim() : '';
    if (id.isEmpty) return;
    final existing =
        await _repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
    await _repo.upsertPersonal(existing.copyWith(availability: id));
  }

  // ── Fit cultural → profile_job_preferences (id da opção escolhida) ───────────
  // Um saver flexível: cada passo manda só o seu campo (escolha única → 1º id);
  // copyWith deixa os outros intactos. Vazio ⇒ no-op.
  Future<void> _saveCulturalFit({
    List<String>? companyStage,
    List<String>? workEnvironment,
    List<String>? workStyle,
  }) async {
    String? pick(List<String>? ids) {
      final id = (ids != null && ids.isNotEmpty) ? ids.first.trim() : '';
      return id.isEmpty ? null : id;
    }

    final cs = pick(companyStage);
    final we = pick(workEnvironment);
    final ws = pick(workStyle);
    if (cs == null && we == null && ws == null) return;
    final existing =
        await _repo.getJobPreferences(userId) ?? JobPreferences(userId: userId);
    await _repo.upsertJobPreferences(existing.copyWith(
      companyStage: cs,
      workEnvironment: we,
      workStyle: ws,
    ));
  }

  // ── Habilidades → profile_skills (merge ADITIVO server-side, Gate 3.0C) ──
  // Sem pré-leitura: manda a seleção guiada ao contrato aditivo/idempotente
  // `merge_guided_profile_list(section='skills')`, que dedup e insere só o que
  // falta sob o advisory lock por usuário. Elimina o TOCTOU do antigo
  // `get → replaceSkills` e nunca apaga skill editada manualmente. Uma falha
  // (recibo malformado, payload inválido ou estouro do limite de 12) propaga e
  // o ConversationController mantém o passo aberto para retry (fail-closed).
  Future<void> _saveSkills(List<String> names) async {
    final clean = names.where((n) => n.trim().isNotEmpty).toList();
    if (clean.isEmpty) return;
    await _guidedSkillsWriter.mergeSkills(userId: userId, names: clean);
  }

  // ── Interesses → profile_interests (merge dedup) ─────────────────────────
  Future<void> _saveInterests(List<String> names) async {
    final clean =
        names.where((n) => n.trim().isNotEmpty && n != 'none').toList();
    if (clean.isEmpty) return;
    final existing = await _repo.getInterests(userId);
    final have = existing.map((i) => i.name.toLowerCase().trim()).toSet();
    final toAdd =
        clean.where((n) => !have.contains(n.toLowerCase().trim())).toList();
    if (toAdd.isEmpty) return;
    await _repo.replaceInterests(userId, [
      ...existing.map((i) => i.name),
      ...toAdd.map((n) => n.trim()),
    ]);
  }

  // ── Idiomas → profile_languages (merge ADITIVO server-side, Gate 3.0F) ───
  // Sem pré-leitura: manda os idiomas escolhidos ao merge aditivo (insere só os
  // novos, com nível null; o passo lang.level.X preenche depois). 'none' pula.
  Future<void> _saveLanguages(List<String> names) async {
    final clean =
        names.where((n) => n.trim().isNotEmpty && n != 'none').toList();
    if (clean.isEmpty) return;
    await _guidedLanguageWriter.mergeLanguages(userId: userId, names: clean);
  }

  // ── Nível de idioma → CAS server-side (Gate 3.0F; manual recente vence) ──
  // Lê o nível observado do idioma e faz CAS: se mudou entre a leitura e a
  // escrita (edição manual concorrente), volta stale e não sobrescreve.
  Future<void> _saveLanguageLevel(String name, List<String> ids) async {
    final id = ids.isNotEmpty ? ids.first : '';
    if (!kLanguageLevels.contains(id)) return; // nível inválido → no-op
    final langs = await _repo.getLanguages(userId);
    Language? match;
    for (final l in langs) {
      if (l.name.toLowerCase() == name.toLowerCase()) {
        match = l;
        break;
      }
    }
    if (match == null) return; // o passo de add roda antes; sem idioma, no-op
    await _guidedLanguageWriter.setLevel(
      userId: userId,
      name: match.name,
      expectedLevel: match.proficiency?.name, // CAS contra o nível observado
      newLevel: id,
    );
  }

  WorkMode? _workModeFromId(String id) {
    switch (id) {
      case 'remote':
        return WorkMode.remote;
      case 'hybrid':
        return WorkMode.hybrid;
      case 'inPerson':
        return WorkMode.inPerson;
    }
    return null;
  }

  JobType? _jobTypeFromId(String id) {
    switch (id) {
      case 'internship':
        return JobType.internship;
      case 'trainee':
        return JobType.trainee;
      case 'juniorFullTime':
        return JobType.juniorFullTime;
      case 'temporary':
        return JobType.temporary;
    }
    return null;
  }

  // ── Experiência → profile_experiences + 1 bullet (acumula campos) ────────
  Future<void> _handleExperience(StepAnswer a) async {
    final parts = a.stepId.split('.'); // exp.{n}.{kind}.{field}
    // 'exp.gate' / 'exp.more' (seletor de tipos) → controle de fluxo, no-op.
    if (parts.length < 4) return;
    final n = int.tryParse(parts[1]);
    if (n == null) return;
    final kind = parts[2];
    final field = parts[3];
    final buf = _expBuffers.putIfAbsent(n, () => _ExpBuffer());
    // Kind vem do id (tipo canônico). Pra 'outro', o campo 'label' (nome livre
    // do tipo) vira o kind — então NÃO sobrescreve aqui.
    if (kind != 'outro') buf.kind = kind;
    switch (field) {
      case 'label':
        // 'Outro': o nome que a pessoa deu é o próprio kind gravado.
        final t = _text(a);
        buf.kind = t.isEmpty ? 'outro' : t;
        break;
      case 'company':
        buf.company = _text(a);
        break;
      case 'role':
        buf.role = _text(a);
        break;
      case 'start':
        buf.start = _parseMonth(_text(a));
        break;
      case 'current':
        buf.isCurrent = _yes(a);
        break;
      case 'end':
        buf.end = _parseMonth(_text(a));
        break;
      case 'ofazia':
        buf.ofazia = _text(a);
        await _saveExperience(n, buf);
        break;
    }
    // Resumabilidade: rascunho nos passos intermediários, apaga no terminal.
    const intermediate = {'label', 'company', 'role', 'start', 'current', 'end'};
    if (intermediate.contains(field)) {
      await _persistDraft('experience', n, a.stepId, buf.toJson());
    } else if (field == 'ofazia') {
      await _clearDraft('experience');
    }
  }

  Future<void> _saveExperience(int n, _ExpBuffer buf) async {
    final company = buf.company?.trim() ?? '';
    final role = buf.role?.trim() ?? '';
    final raw = buf.ofazia?.trim() ?? '';
    if (company.isEmpty ||
        role.isEmpty ||
        buf.start == null ||
        buf.isCurrent == null ||
        (buf.isCurrent == false && buf.end == null) ||
        raw.isEmpty) {
      throw StateError('invalid_guided_experience');
    }
    final exp = Experience(
      id: '',
      userId: userId,
      title: role,
      company: company,
      kind: buf.kind, // tipo da experiência (trilha por tipo)
      startDate: buf.start!,
      endDate: buf.isCurrent == true ? null : buf.end,
      isCurrent: buf.isCurrent == true,
      needsReview: true, // veio da trilha; refino do bullet pela IA vem depois
      bullets: [Bullet(id: '', experienceId: '', text: raw)],
    );
    final existing = await _repo.getExperiences(userId);
    Experience? match;
    for (final candidate in existing) {
      if (_sameGuidedExperience(candidate, exp)) {
        match = candidate;
        break;
      }
    }
    if (match == null) {
      // Envia o bullet junto do pai. O repositório concreto reconcilia ambos
      // antes de confirmar sucesso; se a operação ficar ambígua, o retry
      // reencontra o pai e completa somente o que estiver faltando.
      await _repo.addExperience(exp);
    } else if (!match.bullets.any((bullet) => _sameText(bullet.text, raw))) {
      await _repo.addBullet(Bullet(
        id: '',
        experienceId: match.id,
        text: raw,
      ));
    }
    _expBuffers.remove(n);
  }

  // ── Projetos → profile_projects (ATÔMICO: grava tudo de uma vez no 'link') ──
  // O projeto é salvo SÓ no último passo (link), com nome+contexto+bullet+data+
  // link juntos. Por quê: se o usuário sair no meio (ex.: na data), NADA foi
  // gravado → a trilha re-pergunta o projeto na volta, em vez de "pular" uma
  // pergunta que ele não respondeu (a cauda opcional sumindo). Atômico = sem
  // estado meio-salvo que a memória por lacunas descartaria.
  Future<void> _handleProject(StepAnswer a) async {
    final parts = a.stepId.split('.'); // project.{n}.{field}
    if (parts.length < 3) return; // 'project.gate'
    final n = int.tryParse(parts[1]);
    if (n == null) return;
    final buf = _projBuffers.putIfAbsent(n, () => _ProjBuffer());
    switch (parts[2]) {
      case 'name':
        buf.name = _text(a);
        break;
      case 'what':
        buf.what = _text(a);
        break;
      case 'did':
        buf.did = _text(a);
        break;
      case 'when':
        buf.start = _parseMonth(_text(a));
        break;
      case 'current':
        buf.isCurrent = _yes(a);
        break;
      case 'end':
        buf.end = _parseMonth(_text(a));
        break;
      case 'link':
        buf.link = _text(a);
        await _saveProject(n, buf); // último passo → grava o projeto inteiro
        break;
      // 'more' → controle, no-op
    }
    const intermediate = {'name', 'what', 'did', 'when', 'current', 'end'};
    if (intermediate.contains(parts[2])) {
      await _persistDraft('project', n, a.stepId, buf.toJson());
    } else if (parts[2] == 'link') {
      await _clearDraft('project');
    }
  }

  Future<void> _saveProject(int n, _ProjBuffer buf) async {
    final name = normalizeProfileTitle(buf.name ?? '');
    if (name.isEmpty) {
      throw StateError('invalid_guided_project');
    }
    final what = buf.what?.trim();
    final link = buf.link?.trim();
    final did = buf.did?.trim();
    if (what == null ||
        what.isEmpty ||
        did == null ||
        did.isEmpty ||
        buf.isCurrent == null) {
      throw StateError('invalid_guided_project');
    }
    final project = Project(
      id: '',
      userId: userId,
      name: name,
      context: what,
      website: (link != null && link.isNotEmpty) ? link : null,
      startDate: buf.start,
      endDate: buf.isCurrent == true ? null : buf.end,
      isCurrent: buf.isCurrent == true,
      bullets: [ProjectBullet(id: '', projectId: '', text: did)],
    );
    final existing = await _repo.getProjects(userId);
    Project? match;
    for (final candidate in existing) {
      if (_sameGuidedProject(candidate, project)) {
        match = candidate;
        break;
      }
    }
    if (match == null) {
      await _repo.addProject(project);
    } else if (!match.bullets.any((bullet) => _sameText(bullet.text, did))) {
      await _repo.addProjectBullet(ProjectBullet(
        id: '',
        projectId: match.id,
        text: did,
      ));
    }
    _projBuffers.remove(n);
  }

  // ── Educação → profile_education (atômico no último passo: semestre/ano) ────
  // UPSERT: se já existe uma formação do mesmo nível (faculdade/escola) — ex.:
  // veio rasa do import sem semestre — atualiza em vez de duplicar.
  Future<void> _handleEducation(StepAnswer a) async {
    final parts = a.stepId.split('.'); // gap.edu.{field}
    if (parts.length < 3) return;
    final buf = _eduBuffer ??= _EduBuffer();
    switch (parts[2]) {
      case 'moment':
        buf.moment = _firstId(a);
        break;
      case 'institution':
        // Typeahead do catálogo: 'institution_id|Nome'. Texto livre: só o nome.
        final v = _text(a);
        final pipe = v.indexOf('|');
        if (pipe > 0 && _looksLikeUuid(v.substring(0, pipe))) {
          buf.institutionId = v.substring(0, pipe);
          buf.institution = v.substring(pipe + 1).trim();
        } else {
          buf.institution = v;
          buf.institutionId = null;
        }
        break;
      case 'school':
        buf.institution = _text(a); // escola: texto livre (sem catálogo)
        break;
      case 'course':
        buf.course = _text(a);
        break;
      case 'semester':
        buf.semester = int.tryParse(_firstId(a)); // faculdade salva na graduação
        break;
      case 'graduation':
        // 'unsure' → tryParse null → sem previsão (endDate fica nulo).
        buf.gradYear = int.tryParse(_firstId(a));
        await _saveEducation(buf); // último passo da faculdade
        break;
      case 'schoolyear':
        buf.schoolYear = int.tryParse(_firstId(a));
        await _saveEducation(buf); // último passo do ensino médio
        break;
    }
    final f = parts[2];
    if (f == 'graduation' || f == 'schoolyear') {
      await _clearDraft('education'); // salvou
    } else if (f == 'moment' && buf.moment == 'outro') {
      await _clearDraft('education'); // 'outro' não vira item — nada a retomar
    } else {
      // moment + institution/school/course/semester → intermediário (retoma).
      await _persistDraft('education', 0, a.stepId, buf.toJson());
    }
  }

  Future<void> _saveEducation(_EduBuffer buf) async {
    final inst = buf.institution?.trim() ?? '';
    final isSchool = buf.moment == 'in_school';
    final isCollege =
        buf.moment == 'in_college' || buf.moment == 'college_paused';
    final course = buf.course?.trim() ?? '';
    if (inst.isEmpty ||
        (!isSchool && !isCollege) ||
        (isSchool && buf.schoolYear == null) ||
        (isCollege && (course.isEmpty || buf.semester == null))) {
      throw StateError('invalid_guided_education');
    }
    final level = isSchool ? 'school' : 'college';
    final status = buf.moment == 'college_paused' ? 'paused' : 'studying';

    // Upsert: acha a formação existente do mesmo nível pra atualizar.
    final existing = await _repo.getEducation(userId);
    Education? match;
    for (final e in existing) {
      if ((e.educationLevel ?? '').toLowerCase() == level) {
        match = e;
        break;
      }
    }
    final edu = Education(
      id: match?.id ?? '',
      userId: userId,
      institution: inst,
      // id do typeahead > vínculo existente (se o nome não mudou) > null.
      institutionId: buf.institutionId ??
          (inst == match?.institution ? match?.institutionId : null),
      educationLevel: level,
      educationStatus: status,
      location: match?.location,
      degree: isSchool ? 'Ensino médio' : 'Graduação',
      currentSemester: isSchool ? null : buf.semester,
      currentSchoolYear: isSchool ? buf.schoolYear : null,
      startDate: match?.startDate,
      // Previsão de formatura (faculdade) → endDate. Dez do ano previsto; sem
      // previsão ('não sei'), preserva o que já houver.
      endDate: (!isSchool && buf.gradYear != null)
          ? DateTime(buf.gradYear!, 12, 1)
          : match?.endDate,
      gpa: match?.gpa,
      maxGpa: match?.maxGpa,
      orderIndex: match?.orderIndex ?? 0,
      confidence: match?.confidence,
      majors: (!isSchool && course.isNotEmpty)
          ? [EducationMajor(id: '', educationId: match?.id ?? '', name: course)]
          : (match?.majors ?? const []),
      minors: match?.minors ?? const [],
      activities: match?.activities ?? const [],
    );
    if (match != null && _sameGuidedEducation(match, edu)) {
      // Um write anterior pode ter sido confirmado no servidor e falhado na
      // resposta ao cliente. Reconhecer o estado vivo evita um segundo write.
    } else if (match == null) {
      await _repo.addEducation(edu);
    } else {
      await _repo.updateEducation(edu);
    }
    _eduBuffer = null;
  }

  String _firstId(StepAnswer a) =>
      a.value is List && (a.value as List).isNotEmpty
          ? (a.value as List).first as String
          : '';

  static final _uuidRe = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  bool _looksLikeUuid(String s) => _uuidRe.hasMatch(s);

  DateTime? _parseMonth(String yyyymm) {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(yyyymm.trim());
    if (m == null) return null;
    final month = int.parse(m.group(2)!);
    if (month < 1 || month > 12) return null;
    return DateTime(int.parse(m.group(1)!), month, 1);
  }

  bool _yes(StepAnswer a) =>
      a.value is List && (a.value as List).contains('yes');

  bool _sameGuidedExperience(Experience current, Experience desired) =>
      _sameText(current.company, desired.company) &&
      _sameText(current.title, desired.title) &&
      _sameText(current.kind, desired.kind) &&
      _sameMonth(current.startDate, desired.startDate) &&
      current.isCurrent == desired.isCurrent &&
      _sameMonth(current.endDate, desired.endDate);

  bool _sameGuidedProject(Project current, Project desired) =>
      _sameText(current.name, desired.name) &&
      _sameText(current.context, desired.context) &&
      _sameText(current.website, desired.website) &&
      _sameMonth(current.startDate, desired.startDate) &&
      current.isCurrent == desired.isCurrent &&
      _sameMonth(current.endDate, desired.endDate);

  bool _sameGuidedEducation(Education current, Education desired) {
    if (!_sameText(current.institution, desired.institution) ||
        current.institutionId != desired.institutionId ||
        current.educationLevel != desired.educationLevel ||
        current.educationStatus != desired.educationStatus ||
        !_sameText(current.degree, desired.degree) ||
        current.currentSemester != desired.currentSemester ||
        current.currentSchoolYear != desired.currentSchoolYear ||
        !_sameMonth(current.endDate, desired.endDate)) {
      return false;
    }
    final currentMajors = current.majors.map((major) => _textKey(major.name));
    final desiredMajors = desired.majors.map((major) => _textKey(major.name));
    return _sameOrderedValues(currentMajors, desiredMajors);
  }

  bool _sameOrderedValues(Iterable<String> left, Iterable<String> right) {
    final a = left.toList(growable: false);
    final b = right.toList(growable: false);
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

String _textKey(String? value) =>
    (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

bool _sameText(String? left, String? right) =>
    _textKey(left) == _textKey(right);

bool _sameMonth(DateTime? left, DateTime? right) {
  if (left == null || right == null) return left == right;
  return left.year == right.year && left.month == right.month;
}

String? _iso(DateTime? d) => d?.toIso8601String();
DateTime? _fromIso(Object? s) =>
    s is String && s.isNotEmpty ? DateTime.tryParse(s) : null;

/// Buffer temporário dos campos de uma experiência em construção.
class _ExpBuffer {
  String? kind;
  String? company;
  String? role;
  DateTime? start;
  DateTime? end;
  bool? isCurrent;
  String? ofazia;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'company': company,
        'role': role,
        'start': _iso(start),
        'end': _iso(end),
        'isCurrent': isCurrent,
        'ofazia': ofazia,
      };

  static _ExpBuffer fromJson(Map<String, dynamic> j) => _ExpBuffer()
    ..kind = j['kind'] as String?
    ..company = j['company'] as String?
    ..role = j['role'] as String?
    ..start = _fromIso(j['start'])
    ..end = _fromIso(j['end'])
    ..isCurrent = j['isCurrent'] as bool?
    ..ofazia = j['ofazia'] as String?;
}

/// Buffer dos campos de um projeto em construção (gravado de uma vez no fim).
class _ProjBuffer {
  String? name;
  String? what; // o que era (→ context)
  String? did; // o que VOCÊ fez (→ bullet)
  DateTime? start; // 'when' → data de início (opcional → startDate)
  bool? isCurrent; // ainda tá rolando? (→ isCurrent)
  DateTime? end; // quando terminou (opcional → endDate)
  String? link; // link (opcional → website)

  Map<String, dynamic> toJson() => {
        'name': name,
        'what': what,
        'did': did,
        'start': _iso(start),
        'isCurrent': isCurrent,
        'end': _iso(end),
        'link': link,
      };

  static _ProjBuffer fromJson(Map<String, dynamic> j) => _ProjBuffer()
    ..name = j['name'] as String?
    ..what = j['what'] as String?
    ..did = j['did'] as String?
    ..start = _fromIso(j['start'])
    ..isCurrent = j['isCurrent'] as bool?
    ..end = _fromIso(j['end'])
    ..link = j['link'] as String?;
}

/// Buffer de uma certificação (nome + emissor + data) — gravado de uma vez no
/// passo terminal (date). Sem draft (fluxo curto; se abandonar, o gate
/// re-pergunta porque nada foi salvo). Emissor/data são opcionais.
class _CertBuffer {
  String? name;
  String? issuer;
  DateTime? date;
}

/// Buffer de uma conquista/prêmio (nome + data) — gravado no passo terminal
/// (date). Sem draft (fluxo curto; gate re-pergunta se nada foi salvo).
class _AwardBuffer {
  String? name;
  DateTime? date;
}

/// Buffer da educação (momento + instituição + curso + semestre/ano + previsão
/// de formatura), gravado de uma vez no último passo do ramo (formatura p/
/// faculdade, ano p/ escola).
class _EduBuffer {
  String? moment; // in_college | college_paused | in_school | outro
  String? institution;
  String? institutionId; // FK do catálogo (typeahead) — null se texto livre
  String? course;
  int? semester;
  int? schoolYear;
  int? gradYear; // previsão de formatura (faculdade) → endDate

  Map<String, dynamic> toJson() => {
        'moment': moment,
        'institution': institution,
        'institutionId': institutionId,
        'course': course,
        'semester': semester,
        'schoolYear': schoolYear,
        'gradYear': gradYear,
      };

  static _EduBuffer fromJson(Map<String, dynamic> j) => _EduBuffer()
    ..moment = j['moment'] as String?
    ..institution = j['institution'] as String?
    ..institutionId = j['institutionId'] as String?
    ..course = j['course'] as String?
    ..semester = (j['semester'] as num?)?.toInt()
    ..schoolYear = (j['schoolYear'] as num?)?.toInt()
    ..gradYear = (j['gradYear'] as num?)?.toInt();
}
