// Write-back da trilha (PLANO-FASE-6 T6.3, Increment 2b).
//
// Grava as respostas da conversa nas tabelas profile_*, roteando por
// StepAnswer.stepId. Faz MERGE/dedup com o que já existe — nunca sobrescreve
// cegamente (espelha a filosofia do TrailToProfileBridge, mas limpo e
// desacoplado do legacy, R6). É plugado no gancho [ConversationController.onAnswer];
// o controller já trata erros de forma defensiva, então aqui focamos na gravação.

import '../../profile/domain/entities/entities.dart';
import '../../profile/domain/repositories/profile_repository.dart';
import '../domain/conversation_step.dart';

class TrilhaWriteback {
  final ProfileRepository _repo;
  final String userId;

  /// Acumula os campos de cada experiência (coletados em passos separados) até
  /// ter o suficiente pra gravar. Chave = índice 'n' do passo 'exp.{n}.*'.
  final Map<int, _ExpBuffer> _expBuffers = {};
  final Map<int, _ProjBuffer> _projBuffers = {};
  _EduBuffer? _eduBuffer;

  TrilhaWriteback(this._repo, this.userId);

  /// Grava uma resposta. Passos sem mapeamento (ex.: 'intro') são no-op.
  Future<void> save(StepAnswer answer) async {
    if (answer.stepId.startsWith('exp.')) {
      await _handleExperience(answer);
      return;
    }
    if (answer.stepId.startsWith('cert.') && answer.stepId.endsWith('.name')) {
      await _saveCertification(_text(answer));
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
      default:
        break; // 'intro' e desconhecidos
    }
  }

  // ── Helpers de extração ──────────────────────────────────────────────────
  List<String> _ids(StepAnswer a) =>
      a.value is List ? (a.value as List).whereType<String>().toList() : const [];

  String _text(StepAnswer a) => a.value is String ? a.value as String : '';

  // ── Áreas → profile_desired_titles (merge dedup) ─────────────────────────
  Future<void> _saveAreas(List<String> areas) async {
    final clean = areas.where((a) => a.trim().isNotEmpty).toList();
    if (clean.isEmpty) return;
    final existing = await _repo.getDesiredTitles(userId);
    final have = existing.map((t) => t.title.toLowerCase().trim()).toSet();
    final toAdd =
        clean.where((a) => !have.contains(a.toLowerCase().trim())).toList();
    if (toAdd.isEmpty) return;
    final merged = <DesiredTitle>[
      ...existing,
      for (var i = 0; i < toAdd.length; i++)
        DesiredTitle(
          id: '',
          userId: userId,
          title: toAdd[i].trim(),
          source: DesiredTitleSource.userAdded,
          orderIndex: existing.length + i,
        ),
    ];
    await _repo.replaceDesiredTitles(userId, merged);
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

  // ── Cidade → profile_personal.location_city/_state ───────────────────────
  Future<void> _saveCity(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    String city = text;
    String? state;
    final parts = text.split(','); // "São Paulo, SP"
    if (parts.length >= 2 && parts[1].trim().isNotEmpty) {
      city = parts[0].trim();
      state = parts[1].trim();
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
    final url = raw.trim();
    if (url.isEmpty) return;
    final existing =
        await _repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
    await _repo.upsertPersonal(existing.copyWith(linkedinUrl: url));
  }

  // ── Certificação → profile_certifications ────────────────────────────────
  Future<void> _saveCertification(String raw) async {
    final name = raw.trim();
    if (name.isEmpty) return;
    await _repo.addCertification(
      Certification(id: '', userId: userId, name: name),
    );
  }

  // ── Disponibilidade → profile_personal.availability ──────────────────────
  Future<void> _saveAvailability(List<String> ids) async {
    final id = ids.isNotEmpty ? ids.first.trim() : '';
    if (id.isEmpty) return;
    final existing =
        await _repo.getPersonal(userId) ?? PersonalInfo(userId: userId);
    await _repo.upsertPersonal(existing.copyWith(availability: id));
  }

  // ── Habilidades → profile_skills (merge dedup) ───────────────────────────
  Future<void> _saveSkills(List<String> names) async {
    final clean = names.where((n) => n.trim().isNotEmpty).toList();
    if (clean.isEmpty) return;
    final existing = await _repo.getSkills(userId);
    final have = existing.map((s) => s.name.toLowerCase().trim()).toSet();
    final toAdd =
        clean.where((n) => !have.contains(n.toLowerCase().trim())).toList();
    if (toAdd.isEmpty) return;
    await _repo.replaceSkills(userId, [
      ...existing.map((s) => s.name),
      ...toAdd.map((n) => n.trim()),
    ]);
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

  // ── Idiomas → profile_languages (insere os novos; 'none' = pular) ────────
  Future<void> _saveLanguages(List<String> names) async {
    final clean =
        names.where((n) => n.trim().isNotEmpty && n != 'none').toList();
    if (clean.isEmpty) return;
    final existing = await _repo.getLanguages(userId);
    final have = existing.map((l) => l.name.toLowerCase().trim()).toSet();
    for (final name in clean) {
      if (have.contains(name.toLowerCase().trim())) continue;
      // Português = nativo (auto); o nível dos demais vem no passo seguinte.
      final prof = name.toLowerCase().trim() == 'português'
          ? LanguageProficiency.native
          : null;
      await _repo.addLanguage(
          Language(id: '', userId: userId, name: name.trim(), proficiency: prof));
    }
  }

  // ── Nível de idioma → profile_languages.proficiency (atualiza o existente) ──
  Future<void> _saveLanguageLevel(String name, List<String> ids) async {
    final id = ids.isNotEmpty ? ids.first : '';
    LanguageProficiency? prof;
    for (final p in LanguageProficiency.values) {
      if (p.name == id) {
        prof = p;
        break;
      }
    }
    if (prof == null) return;
    final langs = await _repo.getLanguages(userId);
    for (final l in langs) {
      if (l.name.toLowerCase() == name.toLowerCase()) {
        await _repo.updateLanguage(l.copyWith(proficiency: prof));
        return;
      }
    }
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
    final parts = a.stepId.split('.'); // exp.{n}.{field}
    if (parts.length < 3) return; // 'exp.gate' etc.
    final n = int.tryParse(parts[1]);
    if (n == null) return;
    final field = parts[2];
    final buf = _expBuffers.putIfAbsent(n, () => _ExpBuffer());
    switch (field) {
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
      // 'more' → controle de fluxo, no-op
    }
  }

  Future<void> _saveExperience(int n, _ExpBuffer buf) async {
    final company = buf.company?.trim() ?? '';
    final role = buf.role?.trim() ?? '';
    if (company.isEmpty || role.isEmpty || buf.start == null) {
      _expBuffers.remove(n);
      return;
    }
    final exp = Experience(
      id: '',
      userId: userId,
      title: role,
      company: company,
      startDate: buf.start!,
      endDate: buf.isCurrent == true ? null : buf.end,
      isCurrent: buf.isCurrent == true,
      needsReview: true, // veio da trilha; refino do bullet pela IA vem depois
    );
    final saved = await _repo.addExperience(exp);
    final raw = buf.ofazia?.trim() ?? '';
    if (raw.isNotEmpty) {
      await _repo.addBullet(Bullet(id: '', experienceId: saved.id, text: raw));
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
        buf.when = _parseMonth(_text(a));
        break;
      case 'link':
        buf.link = _text(a);
        await _saveProject(n, buf); // último passo → grava o projeto inteiro
        break;
      // 'more' → controle, no-op
    }
  }

  Future<void> _saveProject(int n, _ProjBuffer buf) async {
    final name = buf.name?.trim() ?? '';
    if (name.isEmpty) {
      _projBuffers.remove(n);
      return;
    }
    final what = buf.what?.trim();
    final link = buf.link?.trim();
    final saved = await _repo.addProject(Project(
      id: '',
      userId: userId,
      name: name,
      context: (what != null && what.isNotEmpty) ? what : null,
      website: (link != null && link.isNotEmpty) ? link : null,
      endDate: buf.when,
    ));
    final did = buf.did?.trim();
    if (did != null && did.isNotEmpty) {
      await _repo.addProjectBullet(
          ProjectBullet(id: '', projectId: saved.id, text: did));
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
      case 'school':
        buf.institution = _text(a);
        break;
      case 'course':
        buf.course = _text(a);
        break;
      case 'semester':
        buf.semester = int.tryParse(_firstId(a));
        await _saveEducation(buf); // último passo da faculdade
        break;
      case 'schoolyear':
        buf.schoolYear = int.tryParse(_firstId(a));
        await _saveEducation(buf); // último passo do ensino médio
        break;
    }
  }

  Future<void> _saveEducation(_EduBuffer buf) async {
    final inst = buf.institution?.trim() ?? '';
    if (inst.isEmpty) return;
    final isSchool = buf.moment == 'in_school';
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
    final course = buf.course?.trim();
    final edu = Education(
      id: match?.id ?? '',
      userId: userId,
      institution: inst,
      institutionId: inst == match?.institution ? match?.institutionId : null,
      educationLevel: level,
      educationStatus: status,
      location: match?.location,
      degree: isSchool ? 'Ensino médio' : 'Graduação',
      currentSemester: isSchool ? null : buf.semester,
      currentSchoolYear: isSchool ? buf.schoolYear : null,
      startDate: match?.startDate,
      endDate: match?.endDate,
      gpa: match?.gpa,
      maxGpa: match?.maxGpa,
      orderIndex: match?.orderIndex ?? 0,
      confidence: match?.confidence,
      majors: (!isSchool && course != null && course.isNotEmpty)
          ? [EducationMajor(id: '', educationId: match?.id ?? '', name: course)]
          : (match?.majors ?? const []),
      minors: match?.minors ?? const [],
      activities: match?.activities ?? const [],
    );
    if (match == null) {
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

  DateTime? _parseMonth(String yyyymm) {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(yyyymm.trim());
    if (m == null) return null;
    final month = int.parse(m.group(2)!);
    if (month < 1 || month > 12) return null;
    return DateTime(int.parse(m.group(1)!), month, 1);
  }

  bool _yes(StepAnswer a) =>
      a.value is List && (a.value as List).contains('yes');
}

/// Buffer temporário dos campos de uma experiência em construção.
class _ExpBuffer {
  String? company;
  String? role;
  DateTime? start;
  DateTime? end;
  bool? isCurrent;
  String? ofazia;
}

/// Buffer dos campos de um projeto em construção (gravado de uma vez no fim).
class _ProjBuffer {
  String? name;
  String? what; // o que era (→ context)
  String? did; // o que VOCÊ fez (→ bullet)
  DateTime? when; // quando (opcional → endDate)
  String? link; // link (opcional → website)
}

/// Buffer da educação (momento + instituição + curso + semestre/ano), gravado
/// de uma vez no último passo do ramo (semestre p/ faculdade, ano p/ escola).
class _EduBuffer {
  String? moment; // in_college | college_paused | in_school | outro
  String? institution;
  String? course;
  int? semester;
  int? schoolYear;
}
