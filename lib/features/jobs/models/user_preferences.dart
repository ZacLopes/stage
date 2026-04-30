class UserJobPreferences {
  final String? id;
  final String userId;
  final List<String> areas;
  final List<String> locations;
  final List<String> workModels;
  final List<String> jobTypes;
  final int? minSalary; // in centavos

  UserJobPreferences({
    this.id,
    required this.userId,
    this.areas = const [],
    this.locations = const [],
    this.workModels = const [],
    this.jobTypes = const [],
    this.minSalary,
  });

  factory UserJobPreferences.fromJson(Map<String, dynamic> json) {
    return UserJobPreferences(
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      areas: _parseStringList(json['areas']),
      locations: _parseStringList(json['locations']),
      workModels: _parseStringList(json['work_models']),
      jobTypes: _parseStringList(json['job_types']),
      minSalary: json['min_salary'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'areas': areas.isEmpty ? null : areas,
      'locations': locations.isEmpty ? null : locations,
      'work_models': workModels.isEmpty ? null : workModels,
      'job_types': jobTypes.isEmpty ? null : jobTypes,
      'min_salary': minSalary,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  UserJobPreferences copyWith({
    String? id,
    String? userId,
    List<String>? areas,
    List<String>? locations,
    List<String>? workModels,
    List<String>? jobTypes,
    int? minSalary,
    bool clearMinSalary = false,
  }) {
    return UserJobPreferences(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      areas: areas ?? this.areas,
      locations: locations ?? this.locations,
      workModels: workModels ?? this.workModels,
      jobTypes: jobTypes ?? this.jobTypes,
      minSalary: clearMinSalary ? null : (minSalary ?? this.minSalary),
    );
  }

  bool get isEmpty =>
      areas.isEmpty &&
      locations.isEmpty &&
      workModels.isEmpty &&
      jobTypes.isEmpty &&
      minSalary == null;

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.cast<String>();
    return [];
  }
}
