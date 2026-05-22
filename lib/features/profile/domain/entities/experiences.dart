// Experience + Bullet — espelho de profile_experiences + profile_bullets.
//
// Bullets têm `angle` (leadership/technical/impact) e `strength_score` setados
// quando vêm da geração Harvard (generate-bullets). Em edição manual via
// modal, ficam null e a UI mostra só o texto.

import 'package:flutter/foundation.dart';

enum BulletAngle { leadership, technical, impact }

@immutable
class Bullet {
  final String id;
  final String experienceId;
  final String text;
  final BulletAngle? angle;
  final int? strengthScore;
  final String? verb;
  final int orderIndex;

  const Bullet({
    required this.id,
    required this.experienceId,
    required this.text,
    this.angle,
    this.strengthScore,
    this.verb,
    this.orderIndex = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'experience_id': experienceId,
        'text': text,
        'angle': _angleToDb(angle),
        'strength_score': strengthScore,
        'verb': verb,
        'order_index': orderIndex,
      };

  factory Bullet.fromMap(Map<String, dynamic> map) => Bullet(
        id: map['id'] as String,
        experienceId: map['experience_id'] as String,
        text: map['text'] as String? ?? '',
        angle: _angleFromDb(map['angle'] as String?),
        strengthScore: (map['strength_score'] as num?)?.toInt(),
        verb: map['verb'] as String?,
        orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      );

  Bullet copyWith({
    String? id,
    String? experienceId,
    String? text,
    BulletAngle? angle,
    int? strengthScore,
    String? verb,
    int? orderIndex,
  }) =>
      Bullet(
        id: id ?? this.id,
        experienceId: experienceId ?? this.experienceId,
        text: text ?? this.text,
        angle: angle ?? this.angle,
        strengthScore: strengthScore ?? this.strengthScore,
        verb: verb ?? this.verb,
        orderIndex: orderIndex ?? this.orderIndex,
      );
}

@immutable
class Experience {
  final String id;
  final String userId;
  final String title;
  final String company;
  final String? location;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isCurrent;
  final int orderIndex;
  final double? confidence;
  final bool needsReview;
  final List<Bullet> bullets;

  const Experience({
    required this.id,
    required this.userId,
    required this.title,
    required this.company,
    this.location,
    required this.startDate,
    this.endDate,
    this.isCurrent = false,
    this.orderIndex = 0,
    this.confidence,
    this.needsReview = false,
    this.bullets = const [],
  });

  /// Exibição: "Jan 2024 - Atual" ou "Jan 2024 - Dez 2024"
  String get formattedPeriod {
    final start = _formatMonthYear(startDate);
    if (isCurrent) return '$start - Atual';
    if (endDate == null) return start;
    return '$start - ${_formatMonthYear(endDate!)}';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'company': company,
        'location': location,
        'start_date': _dateToDb(startDate),
        'end_date': endDate != null ? _dateToDb(endDate!) : null,
        'is_current': isCurrent,
        'order_index': orderIndex,
        'confidence': confidence,
        'needs_review': needsReview,
      };

  factory Experience.fromMap(Map<String, dynamic> map) {
    final bulletsRaw = map['profile_bullets'] as List?;
    return Experience(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String? ?? '',
      company: map['company'] as String? ?? '',
      location: map['location'] as String?,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: map['end_date'] != null
          ? DateTime.parse(map['end_date'] as String)
          : null,
      isCurrent: map['is_current'] as bool? ?? false,
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      confidence: (map['confidence'] as num?)?.toDouble(),
      needsReview: map['needs_review'] as bool? ?? false,
      bullets: bulletsRaw == null
          ? const []
          : bulletsRaw
              .map((b) => Bullet.fromMap(b as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)),
    );
  }

  Experience copyWith({
    String? id,
    String? userId,
    String? title,
    String? company,
    String? location,
    DateTime? startDate,
    DateTime? endDate,
    bool? isCurrent,
    int? orderIndex,
    double? confidence,
    bool? needsReview,
    List<Bullet>? bullets,
  }) =>
      Experience(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        company: company ?? this.company,
        location: location ?? this.location,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        isCurrent: isCurrent ?? this.isCurrent,
        orderIndex: orderIndex ?? this.orderIndex,
        confidence: confidence ?? this.confidence,
        needsReview: needsReview ?? this.needsReview,
        bullets: bullets ?? this.bullets,
      );
}

String _dateToDb(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _formatMonthYear(DateTime d) {
  const months = [
    '', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
  ];
  return '${months[d.month]} ${d.year}';
}

String? _angleToDb(BulletAngle? a) {
  switch (a) {
    case BulletAngle.leadership: return 'leadership';
    case BulletAngle.technical: return 'technical';
    case BulletAngle.impact: return 'impact';
    case null: return null;
  }
}

BulletAngle? _angleFromDb(String? s) {
  switch (s) {
    case 'leadership': return BulletAngle.leadership;
    case 'technical': return BulletAngle.technical;
    case 'impact': return BulletAngle.impact;
    default: return null;
  }
}
