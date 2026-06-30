class UserJobPreferences {
  final String? id;
  final String userId;
  final List<String> areas;
  final List<String> locations;
  final List<String> workModels;
  final List<String> jobTypes;

  /// Cargo/posição específica desejada (ex.: "Desenvolvedor Front-end"). Não é
  /// dimensão de peso — entra como BÔNUS aditivo pequeno no match quando bate
  /// com o título da vaga. null/vazio = sem bônus. Vem do profile-prefs
  /// (`profile_job_preferences.desired_position`), não do legacy user_preferences.
  final String? desiredPosition;

  /// Match score mínimo (0-100). Vagas com score abaixo disso são ocultadas
  /// do feed. Avaliado client-side combinando match_analyses cacheado + score
  /// determinístico fallback. null = sem filtro.
  final int? minMatchScore;

  UserJobPreferences({
    this.id,
    required this.userId,
    this.areas = const [],
    this.locations = const [],
    this.workModels = const [],
    this.jobTypes = const [],
    this.desiredPosition,
    this.minMatchScore,
  });

  factory UserJobPreferences.fromJson(Map<String, dynamic> json) {
    return UserJobPreferences(
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      areas: _parseStringList(json['areas']),
      locations: _parseStringList(json['locations']),
      workModels: _parseStringList(json['work_models']),
      jobTypes: _parseStringList(json['job_types']),
      minMatchScore: json['min_match_score'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'areas': areas.isEmpty ? null : areas,
      'locations': locations.isEmpty ? null : locations,
      'work_models': workModels.isEmpty ? null : workModels,
      'job_types': jobTypes.isEmpty ? null : jobTypes,
      'min_match_score': minMatchScore,
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
    String? desiredPosition,
    int? minMatchScore,
    bool clearMinMatchScore = false,
  }) {
    return UserJobPreferences(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      areas: areas ?? this.areas,
      locations: locations ?? this.locations,
      workModels: workModels ?? this.workModels,
      jobTypes: jobTypes ?? this.jobTypes,
      desiredPosition: desiredPosition ?? this.desiredPosition,
      minMatchScore:
          clearMinMatchScore ? null : (minMatchScore ?? this.minMatchScore),
    );
  }

  bool get isEmpty =>
      areas.isEmpty &&
      locations.isEmpty &&
      workModels.isEmpty &&
      jobTypes.isEmpty &&
      minMatchScore == null;

  /// Quantas dimensões de filtro estão ativas. Cada dimensão conta 1 ponto
  /// (independente de quantos valores selecionados nela). Usado no badge
  /// "X filtros" do AppBar.
  int get activeFilterCount {
    int n = 0;
    if (areas.isNotEmpty) n++;
    if (locations.isNotEmpty) n++;
    if (workModels.isNotEmpty) n++;
    if (jobTypes.isNotEmpty) n++;
    if (minMatchScore != null) n++;
    return n;
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.cast<String>();
    return [];
  }
}
