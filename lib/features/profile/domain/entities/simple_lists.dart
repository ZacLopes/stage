// Entities de listas simples: Language, Skill, Certification, Project,
// Interest, Award, Coursework. Todas seguem padrão CRUD direto sem nested.

import 'package:flutter/foundation.dart';

enum LanguageProficiency { native, fluent, advanced, intermediate, basic }

@immutable
class Language {
  final String id;
  final String userId;
  final String name;
  final LanguageProficiency? proficiency;
  final int orderIndex;

  const Language({
    required this.id,
    required this.userId,
    required this.name,
    this.proficiency,
    this.orderIndex = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'proficiency': _profToDb(proficiency),
        'order_index': orderIndex,
      };

  factory Language.fromMap(Map<String, dynamic> m) => Language(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        name: m['name'] as String? ?? '',
        proficiency: _profFromDb(m['proficiency'] as String?),
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );

  Language copyWith({String? id, String? userId, String? name, LanguageProficiency? proficiency, int? orderIndex}) =>
      Language(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        proficiency: proficiency ?? this.proficiency,
        orderIndex: orderIndex ?? this.orderIndex,
      );

  String get proficiencyLabel {
    switch (proficiency) {
      case LanguageProficiency.native: return 'Nativo';
      case LanguageProficiency.fluent: return 'Fluente';
      case LanguageProficiency.advanced: return 'Avançado';
      case LanguageProficiency.intermediate: return 'Intermediário';
      case LanguageProficiency.basic: return 'Básico';
      case null: return '';
    }
  }
}

String? _profToDb(LanguageProficiency? p) {
  switch (p) {
    case LanguageProficiency.native: return 'native';
    case LanguageProficiency.fluent: return 'fluent';
    case LanguageProficiency.advanced: return 'advanced';
    case LanguageProficiency.intermediate: return 'intermediate';
    case LanguageProficiency.basic: return 'basic';
    case null: return null;
  }
}

LanguageProficiency? _profFromDb(String? s) {
  switch (s) {
    case 'native': return LanguageProficiency.native;
    case 'fluent': return LanguageProficiency.fluent;
    case 'advanced': return LanguageProficiency.advanced;
    case 'intermediate': return LanguageProficiency.intermediate;
    case 'basic': return LanguageProficiency.basic;
    default: return null;
  }
}

@immutable
class Skill {
  final String id;
  final String userId;
  final String name;
  final String? category;
  final int orderIndex;

  const Skill({required this.id, required this.userId, required this.name, this.category, this.orderIndex = 0});

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'category': category,
        'order_index': orderIndex,
      };

  factory Skill.fromMap(Map<String, dynamic> m) => Skill(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        name: m['name'] as String? ?? '',
        category: m['category'] as String?,
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );

  Skill copyWith({String? id, String? userId, String? name, String? category, int? orderIndex}) =>
      Skill(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        category: category ?? this.category,
        orderIndex: orderIndex ?? this.orderIndex,
      );
}

@immutable
class Certification {
  final String id;
  final String userId;
  final String name;
  final String? issuer;
  final DateTime? date;
  final int orderIndex;

  const Certification({
    required this.id,
    required this.userId,
    required this.name,
    this.issuer,
    this.date,
    this.orderIndex = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'issuer': issuer,
        'date': date != null ? _dateToDb(date!) : null,
        'order_index': orderIndex,
      };

  factory Certification.fromMap(Map<String, dynamic> m) => Certification(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        name: m['name'] as String? ?? '',
        issuer: m['issuer'] as String?,
        date: m['date'] != null ? DateTime.parse(m['date'] as String) : null,
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );

  Certification copyWith({String? id, String? userId, String? name, String? issuer, DateTime? date, int? orderIndex}) =>
      Certification(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        issuer: issuer ?? this.issuer,
        date: date ?? this.date,
        orderIndex: orderIndex ?? this.orderIndex,
      );
}

@immutable
class Project {
  final String id;
  final String userId;
  final String name;
  /// Função/papel do usuário no projeto (ex: "Fundador", "Líder técnico").
  final String? role;
  /// Contexto onde rolou (ex: "Empresa Júnior", "Hackathon", "Pessoal").
  final String? context;
  final String? website;
  /// Descrição legada em texto livre. Novos projetos usam [bullets].
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isCurrent;
  final int orderIndex;
  /// Bullets de impacto/responsabilidade. Carregado via nested select de
  /// profile_project_bullets.
  final List<ProjectBullet> bullets;

  const Project({
    required this.id,
    required this.userId,
    required this.name,
    this.role,
    this.context,
    this.website,
    this.description,
    this.startDate,
    this.endDate,
    this.isCurrent = false,
    this.orderIndex = 0,
    this.bullets = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'role': role,
        'context': context,
        'website': website,
        'description': description,
        'start_date': startDate != null ? _dateToDb(startDate!) : null,
        'end_date': endDate != null ? _dateToDb(endDate!) : null,
        'is_current': isCurrent,
        'order_index': orderIndex,
      };

  factory Project.fromMap(Map<String, dynamic> m) {
    final bulletsRaw = m['profile_project_bullets'] as List?;
    final bullets = bulletsRaw == null
        ? const <ProjectBullet>[]
        : bulletsRaw
            .map((b) => ProjectBullet.fromMap(b as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return Project(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      name: m['name'] as String? ?? '',
      role: m['role'] as String?,
      context: m['context'] as String?,
      website: m['website'] as String?,
      description: m['description'] as String?,
      startDate: m['start_date'] != null ? DateTime.parse(m['start_date'] as String) : null,
      endDate: m['end_date'] != null ? DateTime.parse(m['end_date'] as String) : null,
      isCurrent: m['is_current'] as bool? ?? false,
      orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      bullets: bullets,
    );
  }

  Project copyWith({
    String? id, String? userId, String? name, String? role, String? context,
    String? website, String? description,
    DateTime? startDate, DateTime? endDate, bool? isCurrent, int? orderIndex,
    List<ProjectBullet>? bullets,
  }) =>
      Project(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        role: role ?? this.role,
        context: context ?? this.context,
        website: website ?? this.website,
        description: description ?? this.description,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        isCurrent: isCurrent ?? this.isCurrent,
        orderIndex: orderIndex ?? this.orderIndex,
        bullets: bullets ?? this.bullets,
      );
}

@immutable
class ProjectBullet {
  final String id;
  final String projectId;
  final String text;
  final int orderIndex;

  const ProjectBullet({
    required this.id,
    required this.projectId,
    required this.text,
    this.orderIndex = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'project_id': projectId,
        'text': text,
        'order_index': orderIndex,
      };

  factory ProjectBullet.fromMap(Map<String, dynamic> m) => ProjectBullet(
        id: m['id'] as String,
        projectId: m['project_id'] as String,
        text: m['text'] as String? ?? '',
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );

  ProjectBullet copyWith({String? id, String? projectId, String? text, int? orderIndex}) =>
      ProjectBullet(
        id: id ?? this.id,
        projectId: projectId ?? this.projectId,
        text: text ?? this.text,
        orderIndex: orderIndex ?? this.orderIndex,
      );
}

@immutable
class Interest {
  final String id;
  final String userId;
  final String name;
  final int orderIndex;
  const Interest({required this.id, required this.userId, required this.name, this.orderIndex = 0});
  Map<String, dynamic> toMap() => {'id': id, 'user_id': userId, 'name': name, 'order_index': orderIndex};
  factory Interest.fromMap(Map<String, dynamic> m) => Interest(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        name: m['name'] as String? ?? '',
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );
  Interest copyWith({String? id, String? userId, String? name, int? orderIndex}) =>
      Interest(id: id ?? this.id, userId: userId ?? this.userId, name: name ?? this.name, orderIndex: orderIndex ?? this.orderIndex);
}

@immutable
class Award {
  final String id;
  final String userId;
  final String name;
  final DateTime? date;
  final int orderIndex;
  const Award({required this.id, required this.userId, required this.name, this.date, this.orderIndex = 0});
  Map<String, dynamic> toMap() => {
        'id': id, 'user_id': userId, 'name': name,
        'date': date != null ? _dateToDb(date!) : null, 'order_index': orderIndex,
      };
  factory Award.fromMap(Map<String, dynamic> m) => Award(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        name: m['name'] as String? ?? '',
        date: m['date'] != null ? DateTime.parse(m['date'] as String) : null,
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );
  Award copyWith({String? id, String? userId, String? name, DateTime? date, int? orderIndex}) =>
      Award(id: id ?? this.id, userId: userId ?? this.userId, name: name ?? this.name, date: date ?? this.date, orderIndex: orderIndex ?? this.orderIndex);
}

@immutable
class Coursework {
  final String id;
  final String userId;
  final String name;
  final int orderIndex;
  const Coursework({required this.id, required this.userId, required this.name, this.orderIndex = 0});
  Map<String, dynamic> toMap() => {'id': id, 'user_id': userId, 'name': name, 'order_index': orderIndex};
  factory Coursework.fromMap(Map<String, dynamic> m) => Coursework(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        name: m['name'] as String? ?? '',
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );
  Coursework copyWith({String? id, String? userId, String? name, int? orderIndex}) =>
      Coursework(id: id ?? this.id, userId: userId ?? this.userId, name: name ?? this.name, orderIndex: orderIndex ?? this.orderIndex);
}

String _dateToDb(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
