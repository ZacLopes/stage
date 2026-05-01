export 'interview_report.dart';
class UserProfile {
  final String? id; // Changed to String for Supabase UUID
  final String name;
  final String email;
  final String course;
  final String semester;
  final int? age;
  final int xp;
  final int level;
  final bool aiConsent;
  final DateTime? aiConsentTimestamp;
  final Map<String, dynamic> gamificationData;

  String get university => gamificationData['university'] as String? ?? '';

  UserProfile({
    this.id,
    required this.name,
    required this.email,
    required this.course,
    required this.semester,
    this.age,
    this.xp = 0,
    this.level = 1,
    this.aiConsent = false,
    this.aiConsentTimestamp,
    this.gamificationData = const {},
  });


  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'course': course,
      'semester': semester,
      'age': age, // Added age to map
      'xp': xp,
      'level': level,
      'ai_consent': aiConsent,
      'ai_consent_timestamp': aiConsentTimestamp?.toIso8601String(),
      'gamification_data': gamificationData,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id']?.toString(),
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      course: map['course'] ?? '',
      semester: map['semester'] ?? '',
      age: map['age'], // Added age mapping
      xp: map['xp'] ?? 0,
      level: map['level'] ?? 1,
      aiConsent: map['ai_consent'] ?? false,
      aiConsentTimestamp: map['ai_consent_timestamp'] != null ? DateTime.parse(map['ai_consent_timestamp']) : null,
      gamificationData: map['gamification_data'] ?? {},
    );
  }

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? course,
    String? semester,
    int? age,
    int? xp,
    int? level,
    bool? aiConsent,
    DateTime? aiConsentTimestamp,
    Map<String, dynamic>? gamificationData,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      course: course ?? this.course,
      semester: semester ?? this.semester,
      age: age ?? this.age,
      xp: xp ?? this.xp,
      level: level ?? this.level,
      aiConsent: aiConsent ?? this.aiConsent,
      aiConsentTimestamp: aiConsentTimestamp ?? this.aiConsentTimestamp,
      gamificationData: gamificationData ?? this.gamificationData,
    );
  }
}


class Track {
  final String id;
  final String title;
  final String description;
  final int color; // Hex color as int
  final String iconAsset;
  final int orderIndex;

  Track({
    required this.id,
    required this.title,
    required this.description,
    required this.color,
    required this.iconAsset,
    required this.orderIndex,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'color': color,
      'icon_asset': iconAsset,  // snake_case for Supabase
      'order_index': orderIndex, // snake_case for Supabase
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      color: map['color'],
      iconAsset: map['icon_asset'] ?? map['iconAsset'] ?? '',
      orderIndex: map['order_index'] ?? map['orderIndex'] ?? 0,
    );
  }
}


class Phase {
  final String id;
  final String trackId;
  final int orderIndex;
  final String title;
  final String description;
  final int xpReward;

  Phase({
    required this.id,
    required this.trackId,
    required this.orderIndex,
    required this.title,
    required this.description,
    required this.xpReward,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'track_id': trackId, // snake_case
      'order_index': orderIndex, // snake_case
      'title': title,
      'description': description,
      'xp_reward': xpReward, // snake_case
    };
  }

  factory Phase.fromMap(Map<String, dynamic> map) {
    return Phase(
      id: map['id'],
      trackId: map['track_id'] ?? map['trackId'],
      orderIndex: map['order_index'] ?? map['orderIndex'] ?? 0,
      title: map['title'],
      description: map['description'],
      xpReward: map['xp_reward'] ?? map['xpReward'] ?? 0,
    );
  }
}

enum QuestionType { 
  multipleChoice, 
  singleChoice, 
  scale, 
  text,
  // New complex types for Module 1
  characterSelect,
  interactiveStory,
  balanceSlider,
  dragAndDrop,
  vibeSelect,
  quickTimeEvent,
  chat,
  visionCards,
  squadSelect,
  // Module 2 types
  levelUpLadder,
  idCardBuilder,
  dualWheelDate,
  stepSlider,
  iconSelect,
  rewardCardSelect,
  badgeMultiSelect,
  miniTextBox,
  yesNoWithDetail,
  dynamicList,
  linkInput,
  platformSelect,
  phoneInput,
  licenseSelect,
  cityStateInput,
  binaryChoice,
  retroIdCard,
  bridgeText,
  activitiesGrid,
  experienceTypeSelect, // M3.1 Q1
  experienceForm,       // M3.1 Q2
  learningVault,        // M3.2 Q2
  email,                // M5.1 Q3
  // Phase 3 merged forms (indices 36, 37, 38 — must stay at end)
  academicForm,         // M2_1_1_Q1: institution+dates+semester+period
  toolsCatalog,         // M4_1_1_Q1: 8 categories with inline level
  contactForm,          // M5_1_1_Q1: LinkedIn+portfolio+email+phone
  // Phase 4 M3 redesign (indices 39, 40, 41 — must stay at end)
  experienceInventory,  // M3_1_1_Q1: multi-select 9 experience categories
  experienceQuantity,   // M3_1_1_QCount: count per category chips 1-5+
  experienceDetailForm, // M3_D1_*: org+role+dates+city for each experience
}

class Question {
  final String id;
  final String phaseId;
  final QuestionType type;
  final String content;
  final List<String> options; // JSON stringified list for simplicity in SQLite

  Question({
    required this.id,
    required this.phaseId,
    required this.type,
    required this.content,
    required this.options,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phase_id': phaseId, // snake_case
      'type': type.index,
      'content': content,
      'options': options.join('|'), // Simple delimiter for now
    };
  }

  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      id: map['id'],
      phaseId: map['phase_id'] ?? map['phaseId'],
      type: QuestionType.values[map['type']],
      content: map['content'],
      options: (map['options'] as String).split('|'),
    );
  }
}

class Badge {
  final String id;
  final String name;
  final String description;
  final String iconAsset;
  final String conditionType; // e.g., 'track_complete', 'xp_milestone'
  final int conditionValue;

  Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.iconAsset,
    required this.conditionType,
    required this.conditionValue,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'iconAsset': iconAsset,
      'conditionType': conditionType,
      'conditionValue': conditionValue,
    };
  }

  factory Badge.fromMap(Map<String, dynamic> map) {
    return Badge(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      iconAsset: map['iconAsset'],
      conditionType: map['conditionType'],
      conditionValue: map['conditionValue'],
    );
  }
}

class ProfileContent {
  final String aboutMe;
  final String experiences;
  final String skills;
  final String interests;

  ProfileContent({
    required this.aboutMe,
    required this.experiences,
    required this.skills,
    required this.interests,
  });

  factory ProfileContent.fromJson(Map<String, dynamic> json) {
    String parseField(dynamic value) {
      if (value is String) {
        return value;
      } else if (value is List) {
        return value.map((e) => '• $e').join('\n');
      }
      return '';
    }

    return ProfileContent(
      aboutMe: parseField(json['sobre_mim']),
      experiences: parseField(json['experiencias']),
      skills: parseField(json['habilidades']),
      interests: parseField(json['interesses']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sobre_mim': aboutMe,
      'experiencias': experiences,
      'habilidades': skills,
      'interesses': interests,
    };
  }
}

class ResumeExperience {
  final String role;
  final String company;
  final String period;
  final String description;

  ResumeExperience({
    required this.role,
    required this.company,
    required this.period,
    required this.description,
  });

  factory ResumeExperience.fromJson(Map<String, dynamic> json) {
    return ResumeExperience(
      role: json['cargo'] ?? '',
      company: json['empresa'] ?? '',
      period: json['periodo'] ?? '',
      description: _parseList(json['descricao']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cargo': role,
      'empresa': company,
      'periodo': period,
      'descricao': description,
    };
  }

  static String _parseList(dynamic value) {
    if (value is String) return value;
    if (value is List) return value.map((e) => '• $e').join('\n');
    return '';
  }
}

class ResumeEducation {
  final String institution;
  final String course;
  final String period;
  final String details;

  ResumeEducation({
    required this.institution,
    required this.course,
    required this.period,
    required this.details,
  });

  factory ResumeEducation.fromJson(Map<String, dynamic> json) {
    return ResumeEducation(
      institution: json['instituicao'] ?? '',
      course: json['curso'] ?? '',
      period: json['periodo'] ?? '',
      details: _parseList(json['detalhes'] ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'instituicao': institution,
      'curso': course,
      'periodo': period,
      'detalhes': details,
    };
  }

  static String _parseList(dynamic value) {
    if (value is String) return value;
    if (value is List) return value.map((e) => '• $e').join('\n');
    return '';
  }
}

class ResumeProject {
  final String title;
  final String role;
  final String period;
  final String description;

  ResumeProject({
    required this.title,
    required this.role,
    required this.period,
    required this.description,
  });

  factory ResumeProject.fromJson(Map<String, dynamic> json) {
    return ResumeProject(
      title: json['titulo'] ?? '',
      role: json['papel'] ?? '',
      period: json['periodo'] ?? '',
      description: json['descricao'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'titulo': title,
      'papel': role,
      'periodo': period,
      'descricao': description,
    };
  }
}

class ResumeLeadership {
  final String role;
  final String organization;
  final String period;
  final String location;
  final String description;

  ResumeLeadership({
    required this.role,
    required this.organization,
    required this.period,
    required this.location,
    required this.description,
  });

  factory ResumeLeadership.fromJson(Map<String, dynamic> json) {
    return ResumeLeadership(
      role: json['cargo'] ?? '',
      organization: json['organizacao'] ?? '',
      period: json['periodo'] ?? '',
      location: json['local'] ?? '',
      description: json['descricao'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cargo': role,
      'organizacao': organization,
      'periodo': period,
      'local': location,
      'descricao': description,
    };
  }
}

class ResumeCourse {
  final String title;
  final String institution;
  final String period;

  ResumeCourse({
    required this.title,
    required this.institution,
    required this.period,
  });

  factory ResumeCourse.fromJson(Map<String, dynamic> json) {
    return ResumeCourse(
      title: json['titulo'] ?? '',
      institution: json['instituicao'] ?? '',
      period: json['periodo'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'titulo': title,
      'instituicao': institution,
      'periodo': period,
    };
  }
}

class ResumeLanguage {
  final String language;
  final String level;

  ResumeLanguage({
    required this.language,
    required this.level,
  });

  factory ResumeLanguage.fromJson(Map<String, dynamic> json) {
    return ResumeLanguage(
      language: json['idioma'] ?? '',
      level: json['nivel'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idioma': language,
      'nivel': level,
    };
  }
}

class ResumeAward {
  final String title;
  final String institution;
  final String date;
  final String description;

  ResumeAward({
    required this.title,
    required this.institution,
    required this.date,
    required this.description,
  });

  factory ResumeAward.fromJson(Map<String, dynamic> json) {
    return ResumeAward(
      title: json['titulo'] ?? '',
      institution: json['instituicao'] ?? '',
      date: json['data'] ?? '',
      description: json['descricao'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'titulo': title,
      'instituicao': institution,
      'data': date,
      'descricao': description,
    };
  }
}

class ResumeContent {
  final String summary;
  final String skills;
  final List<ResumeExperience> experiences;
  final List<ResumeEducation> education;
  final String achievements; // Kept for backward compatibility, might represent generic text
  final String interests;
  final List<ResumeProject> academicProjects;
  final List<ResumeLeadership> leadership;
  final List<ResumeCourse> courses;
  final List<ResumeLanguage> languages;
  final List<ResumeAward> awards;

  ResumeContent({
    required this.summary,
    required this.skills,
    required this.experiences,
    required this.education,
    required this.achievements,
    required this.interests,
    this.academicProjects = const [],
    this.leadership = const [],
    this.courses = const [],
    this.languages = const [],
    this.awards = const [],
  });

  factory ResumeContent.fromJson(Map<String, dynamic> json) {
    String parseField(dynamic value) {
      if (value is String) {
        return value;
      } else if (value is List) {
        return value.map((e) => '• $e').join('\n');
      }
      return '';
    }

    List<ResumeExperience> parseExperiences(dynamic list) {
       if (list is! List) return [];
       return list.map((e) {
         if (e is Map<String, dynamic>) return ResumeExperience.fromJson(e);
         if (e is String) return ResumeExperience(role: 'Experiência Profissional', company: '', period: '', description: e);
         return ResumeExperience(role: '', company: '', period: '', description: '');
       }).toList();
    }

    List<ResumeEducation> parseEducation(dynamic list) {
       if (list is! List) return [];
       return list.map((e) {
         if (e is Map<String, dynamic>) return ResumeEducation.fromJson(e);
         // If string, try to infer or just put in details
         if (e is String) return ResumeEducation(institution: '', course: '', period: '', details: e);
         return ResumeEducation(institution: '', course: '', period: '', details: '');
       }).toList();
    }
    
    List<ResumeProject> parseProjects(dynamic list) {
       if (list is! List) return [];
       return list.map((e) {
         if (e is Map<String, dynamic>) return ResumeProject.fromJson(e);
         if (e is String) return ResumeProject(title: 'Projeto Acadêmico', role: '', period: '', description: e);
         return ResumeProject(title: '', role: '', period: '', description: '');
       }).toList();
    }

    List<ResumeLeadership> parseLeadership(dynamic list) {
       if (list is! List) return [];
       return list.map((e) {
         if (e is Map<String, dynamic>) return ResumeLeadership.fromJson(e);
         if (e is String) return ResumeLeadership(role: 'Liderança', organization: '', period: '', location: '', description: e);
         return ResumeLeadership(role: '', organization: '', period: '', location: '', description: '');
       }).toList();
    }

    List<ResumeCourse> parseCourses(dynamic list) {
       if (list is! List) return [];
       return list.map((e) {
         if (e is Map<String, dynamic>) return ResumeCourse.fromJson(e);
         if (e is String) return ResumeCourse(title: e, institution: '', period: '');
         return ResumeCourse(title: '', institution: '', period: '');
       }).toList();
    }

    List<ResumeLanguage> parseLanguages(dynamic list) {
       if (list is! List) return [];
       return list.map((e) {
         if (e is Map<String, dynamic>) return ResumeLanguage.fromJson(e);
         if (e is String) return ResumeLanguage(language: e, level: '');
         return ResumeLanguage(language: '', level: '');
       }).toList();
    }

    List<ResumeAward> parseAwards(dynamic list) {
       if (list is! List) return [];
       return list.map((e) {
         if (e is Map<String, dynamic>) return ResumeAward.fromJson(e);
         if (e is String) return ResumeAward(title: e, institution: '', date: '', description: '');
         return ResumeAward(title: '', institution: '', date: '', description: '');
       }).toList();
    }

    return ResumeContent(
      summary: parseField(json['resumo_profissional']),
      skills: parseField(json['habilidades']),
      experiences: parseExperiences(json['experiencias']),
      education: parseEducation(json['formacao']),
      achievements: parseField(json['conquistas']),
      interests: parseField(json['interesses']),
      academicProjects: parseProjects(json['projetos'] ?? json['projetos_academicos']),
      leadership: parseLeadership(json['lideranca']),
      courses: parseCourses(json['cursos']),
      languages: parseLanguages(json['idiomas']),
      awards: parseAwards(json['premios']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'resumo_profissional': summary,
      'habilidades': skills,
      'experiencias': experiences.map((e) => e.toJson()).toList(),
      'formacao': education.map((e) => e.toJson()).toList(),
      'conquistas': achievements,
      'interesses': interests,
      'projetos': academicProjects.map((e) => e.toJson()).toList(),
      'lideranca': leadership.map((e) => e.toJson()).toList(),
      'cursos': courses.map((e) => e.toJson()).toList(),
      'idiomas': languages.map((e) => e.toJson()).toList(),
      'premios': awards.map((e) => e.toJson()).toList(),
    };
  }
}

class ResumeAnalysisResult {
  final int score;
  final List<String> strengths;
  final List<String> weaknesses;
  final ProfileContent? parsedData;

  ResumeAnalysisResult({
    required this.score,
    required this.strengths,
    required this.weaknesses,
    this.parsedData,
  });

  factory ResumeAnalysisResult.fromJson(Map<String, dynamic> json) {
    return ResumeAnalysisResult(
      score: json['score'] ?? 0,
      strengths: List<String>.from(json['positives'] ?? json['strengths'] ?? []),
      weaknesses: List<String>.from(json['improvements'] ?? json['weaknesses'] ?? []),
      parsedData: json['parsed_data'] != null ? ProfileContent.fromJson(json['parsed_data']) : null,
    );
  }

  Map<String, dynamic> toJson() => toMap();

  Map<String, dynamic> toMap() {
    return {
      'score': score,
      'strengths': strengths,
      'weaknesses': weaknesses,
      'parsed_data': parsedData?.toJson(),
    };
  }
}

class SavedResume {
  final String id;
  final String title;
  final String filePath;
  final DateTime createdAt;

  SavedResume({
    required this.id,
    required this.title,
    required this.filePath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'file_path': filePath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SavedResume.fromMap(Map<String, dynamic> map) {
    return SavedResume(
      id: map['id'],
      title: map['title'],
      filePath: map['file_path'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

class TargetJob {
  final String id;
  final String userId;
  final String? title;
  final String? descriptionText;
  final String? sourceUrl;
  final bool isSkipped;
  final DateTime createdAt;

  const TargetJob({
    required this.id,
    required this.userId,
    this.title,
    this.descriptionText,
    this.sourceUrl,
    required this.isSkipped,
    required this.createdAt,
  });

  factory TargetJob.fromJson(Map<String, dynamic> json) {
    return TargetJob(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String?,
      descriptionText: json['description_text'] as String?,
      sourceUrl: json['source_url'] as String?,
      isSkipped: json['is_skipped'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class Campaign {
  final String id;
  final String userId;
  final String? targetJobId;
  final String name;
  final String status;
  final String templateId;
  final DateTime createdAt;
  final DateTime lastEditedAt;

  const Campaign({
    required this.id,
    required this.userId,
    this.targetJobId,
    required this.name,
    required this.status,
    required this.templateId,
    required this.createdAt,
    required this.lastEditedAt,
  });

  factory Campaign.fromJson(Map<String, dynamic> json) {
    return Campaign(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      targetJobId: json['target_job_id'] as String?,
      name: json['name'] as String,
      status: json['status'] as String,
      templateId: json['template_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastEditedAt: DateTime.parse(json['last_edited_at'] as String),
    );
  }
}
