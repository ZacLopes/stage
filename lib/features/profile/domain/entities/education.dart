// Education + majors/minors/activities — espelho de profile_education
// + filhas (cascade delete via FK ON DELETE CASCADE no banco).

import 'package:flutter/foundation.dart';

@immutable
class EducationMajor {
  final String id;
  final String educationId;
  final String name;
  final int orderIndex;
  const EducationMajor({required this.id, required this.educationId, required this.name, this.orderIndex = 0});
  Map<String, dynamic> toMap() => {'id': id, 'education_id': educationId, 'name': name, 'order_index': orderIndex};
  factory EducationMajor.fromMap(Map<String, dynamic> m) => EducationMajor(
        id: m['id'] as String,
        educationId: m['education_id'] as String,
        name: m['name'] as String? ?? '',
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class EducationMinor {
  final String id;
  final String educationId;
  final String name;
  final int orderIndex;
  const EducationMinor({required this.id, required this.educationId, required this.name, this.orderIndex = 0});
  Map<String, dynamic> toMap() => {'id': id, 'education_id': educationId, 'name': name, 'order_index': orderIndex};
  factory EducationMinor.fromMap(Map<String, dynamic> m) => EducationMinor(
        id: m['id'] as String,
        educationId: m['education_id'] as String,
        name: m['name'] as String? ?? '',
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class EducationActivity {
  final String id;
  final String educationId;
  final String text;
  final int orderIndex;
  const EducationActivity({required this.id, required this.educationId, required this.text, this.orderIndex = 0});
  Map<String, dynamic> toMap() => {'id': id, 'education_id': educationId, 'text': text, 'order_index': orderIndex};
  factory EducationActivity.fromMap(Map<String, dynamic> m) => EducationActivity(
        id: m['id'] as String,
        educationId: m['education_id'] as String,
        text: m['text'] as String? ?? '',
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class Education {
  final String id;
  final String userId;
  final String institution;
  final String? location;
  final String? degree;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? gpa;
  final double? maxGpa;
  final int orderIndex;
  final double? confidence;
  final List<EducationMajor> majors;
  final List<EducationMinor> minors;
  final List<EducationActivity> activities;

  const Education({
    required this.id,
    required this.userId,
    required this.institution,
    this.location,
    this.degree,
    this.startDate,
    this.endDate,
    this.gpa,
    this.maxGpa,
    this.orderIndex = 0,
    this.confidence,
    this.majors = const [],
    this.minors = const [],
    this.activities = const [],
  });

  String get formattedPeriod {
    if (startDate == null && endDate == null) return '';
    final start = startDate != null ? _formatMonthYear(startDate!) : '';
    final end = endDate != null ? _formatMonthYear(endDate!) : 'Atual';
    if (start.isEmpty) return end;
    return '$start - $end';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'institution': institution,
        'location': location,
        'degree': degree,
        'start_date': startDate != null ? _dateToDb(startDate!) : null,
        'end_date': endDate != null ? _dateToDb(endDate!) : null,
        'gpa': gpa,
        'max_gpa': maxGpa,
        'order_index': orderIndex,
        'confidence': confidence,
      };

  factory Education.fromMap(Map<String, dynamic> map) {
    final majorsRaw = map['profile_education_majors'] as List?;
    final minorsRaw = map['profile_education_minors'] as List?;
    final actsRaw = map['profile_education_activities'] as List?;
    return Education(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      institution: map['institution'] as String? ?? '',
      location: map['location'] as String?,
      degree: map['degree'] as String?,
      startDate: map['start_date'] != null ? DateTime.parse(map['start_date'] as String) : null,
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date'] as String) : null,
      gpa: (map['gpa'] as num?)?.toDouble(),
      maxGpa: (map['max_gpa'] as num?)?.toDouble(),
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      confidence: (map['confidence'] as num?)?.toDouble(),
      majors: majorsRaw == null ? const [] : majorsRaw.map((m) => EducationMajor.fromMap(m as Map<String, dynamic>)).toList(),
      minors: minorsRaw == null ? const [] : minorsRaw.map((m) => EducationMinor.fromMap(m as Map<String, dynamic>)).toList(),
      activities: actsRaw == null ? const [] : actsRaw.map((m) => EducationActivity.fromMap(m as Map<String, dynamic>)).toList(),
    );
  }

  Education copyWith({
    String? id,
    String? userId,
    String? institution,
    String? location,
    String? degree,
    DateTime? startDate,
    DateTime? endDate,
    double? gpa,
    double? maxGpa,
    int? orderIndex,
    double? confidence,
    List<EducationMajor>? majors,
    List<EducationMinor>? minors,
    List<EducationActivity>? activities,
  }) =>
      Education(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        institution: institution ?? this.institution,
        location: location ?? this.location,
        degree: degree ?? this.degree,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        gpa: gpa ?? this.gpa,
        maxGpa: maxGpa ?? this.maxGpa,
        orderIndex: orderIndex ?? this.orderIndex,
        confidence: confidence ?? this.confidence,
        majors: majors ?? this.majors,
        minors: minors ?? this.minors,
        activities: activities ?? this.activities,
      );
}

String _dateToDb(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _formatMonthYear(DateTime d) {
  const months = ['', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
  return '${months[d.month]} ${d.year}';
}
