class CultureFitKeys {
  CultureFitKeys._();

  static const String workStyle = 'work_style';
  static const String learningStyle = 'learning_style';
  static const String collaborationStyle = 'collaboration_style';
  static const String paceStyle = 'pace_style';

  static const List<String> all = <String>[
    workStyle,
    learningStyle,
    collaborationStyle,
    paceStyle,
  ];
}

class CultureFitProfile {
  final String userId;
  final String? workStyle;
  final String? learningStyle;
  final String? collaborationStyle;
  final String? paceStyle;
  final DateTime? updatedAt;

  const CultureFitProfile({
    required this.userId,
    this.workStyle,
    this.learningStyle,
    this.collaborationStyle,
    this.paceStyle,
    this.updatedAt,
  });

  factory CultureFitProfile.empty(String userId) {
    return CultureFitProfile(userId: userId);
  }

  factory CultureFitProfile.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return CultureFitProfile(
      userId: (json['user_id'] ?? '').toString(),
      workStyle: _nullableString(json[CultureFitKeys.workStyle]),
      learningStyle: _nullableString(json[CultureFitKeys.learningStyle]),
      collaborationStyle: _nullableString(
        json[CultureFitKeys.collaborationStyle],
      ),
      paceStyle: _nullableString(json[CultureFitKeys.paceStyle]),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  CultureFitProfile copyWith({
    String? userId,
    String? workStyle,
    String? learningStyle,
    String? collaborationStyle,
    String? paceStyle,
    DateTime? updatedAt,
  }) {
    return CultureFitProfile(
      userId: userId ?? this.userId,
      workStyle: workStyle ?? this.workStyle,
      learningStyle: learningStyle ?? this.learningStyle,
      collaborationStyle: collaborationStyle ?? this.collaborationStyle,
      paceStyle: paceStyle ?? this.paceStyle,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  CultureFitProfile withAnswer(String key, String value) {
    switch (key) {
      case CultureFitKeys.workStyle:
        return copyWith(workStyle: value);
      case CultureFitKeys.learningStyle:
        return copyWith(learningStyle: value);
      case CultureFitKeys.collaborationStyle:
        return copyWith(collaborationStyle: value);
      case CultureFitKeys.paceStyle:
        return copyWith(paceStyle: value);
      default:
        return this;
    }
  }

  String? answerFor(String key) {
    switch (key) {
      case CultureFitKeys.workStyle:
        return workStyle;
      case CultureFitKeys.learningStyle:
        return learningStyle;
      case CultureFitKeys.collaborationStyle:
        return collaborationStyle;
      case CultureFitKeys.paceStyle:
        return paceStyle;
      default:
        return null;
    }
  }

  bool get isComplete {
    return CultureFitKeys.all.every((key) => answerFor(key) != null);
  }

  int get answeredCount {
    return CultureFitKeys.all.where((key) => answerFor(key) != null).length;
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      CultureFitKeys.workStyle: workStyle,
      CultureFitKeys.learningStyle: learningStyle,
      CultureFitKeys.collaborationStyle: collaborationStyle,
      CultureFitKeys.paceStyle: paceStyle,
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  static String? _nullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
