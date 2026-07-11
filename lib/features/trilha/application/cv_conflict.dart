// Diff de conflito de import de CV (widget "o CV diz X × você tem Y").
//
// PURO e testável (R3): recebe o JSON parseado do CV (profile_data da edge
// extract-profile, snake_case) + o ProfileSnapshot atual, e devolve as LINHAS
// pro card de resolução — ADIÇÃO (só no CV → aceitar traz pro perfil) ou
// CONFLITO (existe nos dois com valor diferente → CV-diz-X vs você-tem-Y).
// Campos IGUAIS são omitidos. NÃO grava nada; o apply é feito à parte pelos
// writers do assistente conforme a escolha do usuário.

import '../../profile/domain/entities/entities.dart';
import '../../../services/profile_snapshot_service.dart';

/// Seção do perfil a que a linha pertence (grupo no card + rota de apply).
enum ConflictSection {
  name,
  phone,
  city,
  summary,
  linkedin,
  website,
  skill,
  interest,
  language,
  certification,
  award,
  project,
  coursework,
  experience,
  education,
}

/// ADIÇÃO (só no CV) ou CONFLITO (nos dois, diferente).
enum ConflictKind { addition, conflict }

/// Uma linha do card de conflito. Carrega o necessário pro apply seletivo.
class ConflictRow {
  final String id; // estável (pro toggle no card)
  final ConflictSection section;
  final ConflictKind kind;

  /// Rótulo curto ("Cidade", "Python", "Analista · Ambev").
  final String label;

  /// Valor do CV (exibição) e valor cru a aplicar.
  final String cvText;

  /// Valor atual (conflito); '' quando é adição.
  final String currentText;

  /// Campo alvo pro apply de escalar/campo-de-item (ex.: 'city', 'title').
  final String field;

  /// Valor cru a gravar (escalar/campo) ou nome do item (adição de lista).
  final String value;

  /// Nível/emissor/etc. secundário (idioma: proficiency id; cert: emissor).
  final String extra;

  /// Item existente a editar (conflito de campo de experiência/formação): id.
  final String refId;

  /// Item cru do CV (adição de experiência/formação inteira).
  final Map<String, dynamic> cvItem;

  const ConflictRow({
    required this.id,
    required this.section,
    required this.kind,
    required this.label,
    required this.cvText,
    this.currentText = '',
    this.field = '',
    this.value = '',
    this.extra = '',
    this.refId = '',
    this.cvItem = const {},
  });
}

String _stripAccents(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf.toString();
}

String _norm(String s) => _stripAccents(s.toLowerCase().trim());

String _s(dynamic v) => (v ?? '').toString().trim();

List<Map<String, dynamic>> _list(dynamic v) => v is List
    ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)]
    : const [];

/// Monta as linhas de conflito entre o CV parseado ([cv] = profile_data) e o
/// perfil atual ([current]). Ordem: pessoais → listas → experiências/formação.
class CvConflictDiff {
  static List<ConflictRow> compute(
    Map<String, dynamic> cv,
    ProfileSnapshot current,
  ) {
    final rows = <ConflictRow>[];
    var seq = 0;
    String nextId() => 'cf_${seq++}';

    // ── Pessoais (escalares) ────────────────────────────────────────────────
    final p = cv['personal'] is Map
        ? Map<String, dynamic>.from(cv['personal'] as Map)
        : const <String, dynamic>{};
    final cur = current.personal;

    void scalar(ConflictSection section, String field, String label,
        String cvVal, String curVal) {
      final c = cvVal.trim();
      if (c.isEmpty) return; // CV não trouxe nada → nada a propor
      final y = curVal.trim();
      if (y.isEmpty) {
        rows.add(ConflictRow(
            id: nextId(),
            section: section,
            kind: ConflictKind.addition,
            label: label,
            cvText: c,
            field: field,
            value: c));
      } else if (_norm(c) != _norm(y)) {
        rows.add(ConflictRow(
            id: nextId(),
            section: section,
            kind: ConflictKind.conflict,
            label: label,
            cvText: c,
            currentText: y,
            field: field,
            value: c));
      }
    }

    final cvName =
        '${_s(p['first_name'])} ${_s(p['last_name'])}'.replaceAll(RegExp(r'\s+'), ' ').trim();
    final curName = '${cur?.firstName ?? ''} ${cur?.lastName ?? ''}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    scalar(ConflictSection.name, 'name', 'Nome', cvName, curName);

    scalar(ConflictSection.phone, 'phone', 'Telefone', _s(p['phone_number']),
        cur?.phoneNumber ?? '');

    final cvCity = _joinCity(_s(p['location_city']), _s(p['location_state']));
    final curCity =
        _joinCity(cur?.locationCity ?? '', cur?.locationState ?? '');
    scalar(ConflictSection.city, 'city', 'Cidade', cvCity, curCity);

    scalar(ConflictSection.summary, 'summary', 'Resumo', _s(p['summary']),
        cur?.summary ?? '');
    scalar(ConflictSection.linkedin, 'linkedin', 'LinkedIn', _s(p['linkedin']),
        cur?.linkedinUrl ?? '');
    scalar(ConflictSection.website, 'website', 'Site', _s(p['website']),
        cur?.website ?? '');

    // ── Listas planas: adição por membership (nome normalizado) ─────────────
    void addMembership(
      ConflictSection section,
      List<Map<String, dynamic>> cvItems,
      Set<String> currentKeys,
      String Function(Map<String, dynamic>) nameOf,
      String labelPrefix,
    ) {
      final seen = <String>{};
      for (final it in cvItems) {
        final name = nameOf(it);
        if (name.isEmpty) continue;
        final k = _norm(name);
        if (currentKeys.contains(k) || !seen.add(k)) continue;
        rows.add(ConflictRow(
            id: nextId(),
            section: section,
            kind: ConflictKind.addition,
            label: '$labelPrefix$name',
            cvText: name,
            value: name));
      }
    }

    addMembership(
        ConflictSection.skill,
        _list(cv['skills']),
        {for (final s in current.skills) _norm(s.name)},
        (m) => _s(m['name']),
        '');
    addMembership(
        ConflictSection.interest,
        _list(cv['interests']),
        {for (final i in current.interests) _norm(i.name)},
        (m) => _s(m['name']),
        '');
    addMembership(
        ConflictSection.award,
        _list(cv['awards']),
        {for (final a in current.awards) _norm(a.name)},
        (m) => _s(m['name']),
        'Prêmio: ');
    addMembership(
        ConflictSection.coursework,
        _list(cv['coursework']),
        {for (final c in current.coursework) _norm(c.name)},
        (m) => _s(m['name']),
        'Disciplina: ');

    // Certificações: chave por nome+emissor; carrega emissor no extra.
    {
      final curKeys = {
        for (final c in current.certifications)
          _norm('${c.name}|${c.issuer ?? ''}')
      };
      final seen = <String>{};
      for (final it in _list(cv['certifications'])) {
        final name = _s(it['name']);
        if (name.isEmpty) continue;
        final issuer = _s(it['issuer']);
        final k = _norm('$name|$issuer');
        if (curKeys.contains(k) || !seen.add(k)) continue;
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.certification,
            kind: ConflictKind.addition,
            label: issuer.isEmpty ? 'Cert.: $name' : 'Cert.: $name · $issuer',
            cvText: name,
            value: name,
            extra: issuer));
      }
    }

    // Projetos: adição por nome.
    addMembership(
        ConflictSection.project,
        _list(cv['projects']),
        {for (final pr in current.projects) _norm(pr.name)},
        (m) => _s(m['name']),
        'Projeto: ');

    // ── Idiomas: adição OU conflito de nível ────────────────────────────────
    {
      final curByName = {for (final l in current.languages) _norm(l.name): l};
      final seen = <String>{};
      for (final it in _list(cv['languages'])) {
        final name = _s(it['name']);
        if (name.isEmpty) continue;
        final k = _norm(name);
        if (!seen.add(k)) continue;
        final prof = _s(it['proficiency']); // id canônico (ex.: 'advanced')
        final existing = curByName[k];
        if (existing == null) {
          rows.add(ConflictRow(
              id: nextId(),
              section: ConflictSection.language,
              kind: ConflictKind.addition,
              label: prof.isEmpty ? name : '$name · ${_profLabel(prof)}',
              cvText: name,
              value: name,
              extra: prof));
        } else if (prof.isNotEmpty && _norm(prof) != _norm(_profId(existing.proficiency))) {
          rows.add(ConflictRow(
              id: nextId(),
              section: ConflictSection.language,
              kind: ConflictKind.conflict,
              label: 'Idioma: $name',
              cvText: _profLabel(prof),
              currentText: existing.proficiencyLabel,
              value: name,
              extra: prof));
        }
      }
    }

    // ── Experiências: adição (nova) ou conflito de CARGO (mesma empresa) ─────
    _diffExperiences(cv, current, rows, nextId);

    // ── Formação: adição (nova) ou conflito de curso (mesma instituição) ─────
    _diffEducation(cv, current, rows, nextId);

    return rows;
  }

  static void _diffExperiences(Map<String, dynamic> cv, ProfileSnapshot current,
      List<ConflictRow> rows, String Function() nextId) {
    // Casa por EMPRESA normalizada (o caso comum de re-import é a mesma empresa
    // com cargo/datas refinados). Sem empresa correspondente → experiência nova.
    final curByCompany = <String, Experience>{};
    for (final e in current.experiences) {
      curByCompany.putIfAbsent(_norm(e.company), () => e);
    }
    for (final it in _list(cv['experiences'])) {
      final title = _s(it['title']);
      final company = _s(it['company']);
      if (title.isEmpty && company.isEmpty) continue;
      final match = company.isEmpty ? null : curByCompany[_norm(company)];
      final label = [title, company].where((s) => s.isNotEmpty).join(' · ');
      if (match == null) {
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.experience,
            kind: ConflictKind.addition,
            label: label,
            cvText: label,
            cvItem: it));
      } else if (title.isNotEmpty && _norm(title) != _norm(match.title)) {
        // Mesma empresa, CARGO diferente → conflito editável (assistWriteItemField).
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.experience,
            kind: ConflictKind.conflict,
            label: 'Cargo · ${match.company}',
            cvText: title,
            currentText: match.title,
            field: 'title',
            value: title,
            refId: match.id));
      }
    }
  }

  static void _diffEducation(Map<String, dynamic> cv, ProfileSnapshot current,
      List<ConflictRow> rows, String Function() nextId) {
    final curByInst = <String, Education>{};
    for (final e in current.education) {
      curByInst.putIfAbsent(_norm(e.institution), () => e);
    }
    for (final it in _list(cv['education'])) {
      final inst = _s(it['institution']);
      final degree = _s(it['degree']);
      if (inst.isEmpty && degree.isEmpty) continue;
      final match = inst.isEmpty ? null : curByInst[_norm(inst)];
      final label = [degree, inst].where((s) => s.isNotEmpty).join(' · ');
      if (match == null) {
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.education,
            kind: ConflictKind.addition,
            label: label,
            cvText: label,
            cvItem: it));
      } else if (degree.isNotEmpty && _norm(degree) != _norm(match.degree ?? '')) {
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.education,
            kind: ConflictKind.conflict,
            label: 'Curso · ${match.institution}',
            cvText: degree,
            currentText: match.degree ?? '—',
            field: 'degree',
            value: degree,
            refId: match.id));
      }
    }
  }
}

String _joinCity(String city, String state) {
  final c = city.trim();
  final s = state.trim();
  if (c.isEmpty) return '';
  return s.isEmpty ? c : '$c, $s';
}

String _profId(LanguageProficiency? p) {
  switch (p) {
    case LanguageProficiency.basic:
      return 'basic';
    case LanguageProficiency.intermediate:
      return 'intermediate';
    case LanguageProficiency.advanced:
      return 'advanced';
    case LanguageProficiency.fluent:
      return 'fluent';
    case LanguageProficiency.native:
      return 'native';
    case null:
      return '';
  }
}

String _profLabel(String id) {
  switch (_norm(id)) {
    case 'basic':
      return 'Básico';
    case 'intermediate':
      return 'Intermediário';
    case 'advanced':
      return 'Avançado';
    case 'fluent':
      return 'Fluente';
    case 'native':
      return 'Nativo';
    default:
      return id;
  }
}
