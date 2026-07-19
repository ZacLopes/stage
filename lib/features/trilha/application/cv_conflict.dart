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

  /// Idioma (conflito de nível): id do nível OBSERVADO (currente), p/ CAS do
  /// `lang_level` no RPC de revisão. '' fora de conflito de idioma.
  final String observedLevelId;

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
    this.observedLevelId = '',
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

    // NOME: só conflita se genuinamente diferente. Se um é PREFIXO do outro (CV
    // sem sobrenome, ou mais completo) NÃO propõe — evita sobrescrever/derrubar
    // o sobrenome que a pessoa digitou.
    final cvName =
        '${_s(p['first_name'])} ${_s(p['last_name'])}'.replaceAll(RegExp(r'\s+'), ' ').trim();
    final curName = '${cur?.firstName ?? ''} ${cur?.lastName ?? ''}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cvName.isNotEmpty) {
      final cn = _norm(cvName), yn = _norm(curName);
      if (curName.isEmpty) {
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.name,
            kind: ConflictKind.addition,
            label: 'Nome',
            cvText: cvName,
            field: 'name',
            value: cvName));
      } else if (cn != yn && !cn.startsWith(yn) && !yn.startsWith(cn)) {
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.name,
            kind: ConflictKind.conflict,
            label: 'Nome',
            cvText: cvName,
            currentText: curName,
            field: 'name',
            value: cvName));
      }
    }

    scalar(ConflictSection.phone, 'phone', 'Telefone', _s(p['phone_number']),
        cur?.phoneNumber ?? '');

    // CIDADE: compara só o NOME da cidade pro conflito. UF ausente no CV NÃO
    // vira conflito (aceitar apagaria a UF salva). CV com UF que o perfil não
    // tem → adição (enriquece), sem risco.
    final cvCityName = _s(p['location_city']);
    final cvUf = _s(p['location_state']);
    final curCityName = (cur?.locationCity ?? '').trim();
    final curUf = (cur?.locationState ?? '').trim();
    if (cvCityName.isNotEmpty) {
      final cvFull = _joinCity(cvCityName, cvUf);
      if (curCityName.isEmpty) {
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.city,
            kind: ConflictKind.addition,
            label: 'Cidade',
            cvText: cvFull,
            field: 'city',
            value: cvFull));
      } else if (_norm(cvCityName) != _norm(curCityName)) {
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.city,
            kind: ConflictKind.conflict,
            label: 'Cidade',
            cvText: cvFull,
            currentText: _joinCity(curCityName, curUf),
            field: 'city',
            value: cvFull));
      } else if (cvUf.isNotEmpty && curUf.isEmpty) {
        // Mesma cidade, o CV traz a UF que faltava → adiciona (não apaga nada).
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.city,
            kind: ConflictKind.addition,
            label: 'Cidade (UF)',
            cvText: cvFull,
            field: 'city',
            value: cvFull));
      }
    }

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
              extra: prof,
              observedLevelId: _profId(existing.proficiency)));
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
    // Chave composta (empresa|cargo) pra "idêntico"; lista por empresa pra
    // decidir conflito de cargo SÓ quando há EXATAMENTE 1 experiência na empresa
    // (senão 2 papéis diferentes na mesma empresa colapsariam num conflito falso
    // que sobrescreveria o cargo errado).
    final byCompany = <String, List<Experience>>{};
    final composite = <String>{};
    for (final e in current.experiences) {
      byCompany.putIfAbsent(_norm(e.company), () => []).add(e);
      composite.add(_norm('${e.company}|${e.title}'));
    }
    for (final it in _list(cv['experiences'])) {
      final title = _s(it['title']);
      final company = _s(it['company']);
      if (title.isEmpty && company.isEmpty) continue;
      if (composite.contains(_norm('$company|$title'))) continue; // idêntico
      final same = company.isEmpty ? const <Experience>[] : (byCompany[_norm(company)] ?? const []);
      if (same.length == 1 && title.isNotEmpty) {
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.experience,
            kind: ConflictKind.conflict,
            label: 'Cargo · ${same.first.company}',
            cvText: title,
            currentText: same.first.title,
            field: 'title',
            value: title,
            refId: same.first.id));
      } else if (_s(it['start_date']).isNotEmpty) {
        // Papel novo (0 ou 2+ na empresa). Só oferece com data (o apply precisa
        // de start_date; sem data seria "iniciada hoje").
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.experience,
            kind: ConflictKind.addition,
            label: [title, company].where((s) => s.isNotEmpty).join(' · '),
            cvText: [title, company].where((s) => s.isNotEmpty).join(' · '),
            cvItem: it));
      }
    }
  }

  static void _diffEducation(Map<String, dynamic> cv, ProfileSnapshot current,
      List<ConflictRow> rows, String Function() nextId) {
    final byInst = <String, List<Education>>{};
    final composite = <String>{};
    for (final e in current.education) {
      byInst.putIfAbsent(_norm(e.institution), () => []).add(e);
      composite.add(_norm('${e.institution}|${e.degree ?? ''}'));
    }
    for (final it in _list(cv['education'])) {
      final inst = _s(it['institution']);
      final degree = _s(it['degree']);
      if (inst.isEmpty && degree.isEmpty) continue;
      if (composite.contains(_norm('$inst|$degree'))) continue; // idêntico
      final same = inst.isEmpty ? const <Education>[] : (byInst[_norm(inst)] ?? const []);
      if (same.length == 1 && degree.isNotEmpty) {
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.education,
            kind: ConflictKind.conflict,
            label: 'Curso · ${same.first.institution}',
            cvText: degree,
            currentText: same.first.degree ?? '—',
            field: 'degree',
            value: degree,
            refId: same.first.id));
      } else {
        rows.add(ConflictRow(
            id: nextId(),
            section: ConflictSection.education,
            kind: ConflictKind.addition,
            label: [degree, inst].where((s) => s.isNotEmpty).join(' · '),
            cvText: [degree, inst].where((s) => s.isNotEmpty).join(' · '),
            cvItem: it));
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
