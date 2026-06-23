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

  TrilhaWriteback(this._repo, this.userId);

  /// Grava uma resposta. Passos sem mapeamento (ex.: 'intro') são no-op.
  Future<void> save(StepAnswer answer) async {
    if (answer.stepId.startsWith('exp.')) {
      await _handleExperience(answer);
      return;
    }
    switch (answer.stepId) {
      case 'gap.area':
        await _saveAreas(_ids(answer));
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
      case 'gap.skills':
        await _saveSkills(_ids(answer));
        break;
      case 'gap.languages':
        await _saveLanguages(_ids(answer));
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

  // ── Idiomas → profile_languages (insere os novos; 'none' = pular) ────────
  Future<void> _saveLanguages(List<String> names) async {
    final clean =
        names.where((n) => n.trim().isNotEmpty && n != 'none').toList();
    if (clean.isEmpty) return;
    final existing = await _repo.getLanguages(userId);
    final have = existing.map((l) => l.name.toLowerCase().trim()).toSet();
    for (final name in clean) {
      if (have.contains(name.toLowerCase().trim())) continue;
      await _repo.addLanguage(Language(id: '', userId: userId, name: name.trim()));
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
