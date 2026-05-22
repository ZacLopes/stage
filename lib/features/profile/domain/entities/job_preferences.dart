// JobPreferences (1:1) + filhas (DesiredTitle, ApplicationCountry, OtherLocation).
// Arrays no Postgres (TEXT[]) viram List<String> em Dart com mapeamento direto.

import 'package:flutter/foundation.dart';

enum WorkMode { remote, hybrid, inPerson }
enum JobType { fullTime, internship, contract, partTime }
enum ExperienceLevel { entry, mid, senior }
enum WorkAuth { citizen, authorized, sponsorshipNeeded }
enum DesiredTitleSource { userAdded, fromResume }

@immutable
class JobPreferences {
  final String userId;
  final String? primaryLocationCountry;
  final String? primaryLocationState;
  final String? primaryLocationCity;
  final String? primaryLocationPostalCode;
  final double? primaryLocationLat;
  final double? primaryLocationLng;
  final int primaryLocationRadiusKm;
  final List<ExperienceLevel> experienceLevel;
  final List<WorkMode> workMode;
  final List<JobType> jobTypes;

  const JobPreferences({
    required this.userId,
    this.primaryLocationCountry,
    this.primaryLocationState,
    this.primaryLocationCity,
    this.primaryLocationPostalCode,
    this.primaryLocationLat,
    this.primaryLocationLng,
    this.primaryLocationRadiusKm = 50,
    this.experienceLevel = const [],
    this.workMode = const [],
    this.jobTypes = const [],
  });

  Map<String, dynamic> toMap() => {
        'user_id': userId,
        'primary_location_country': primaryLocationCountry,
        'primary_location_state': primaryLocationState,
        'primary_location_city': primaryLocationCity,
        'primary_location_postal_code': primaryLocationPostalCode,
        'primary_location_lat': primaryLocationLat,
        'primary_location_lng': primaryLocationLng,
        'primary_location_radius_km': primaryLocationRadiusKm,
        'experience_level': experienceLevel.map(_expLevelToDb).toList(),
        'work_mode': workMode.map(_workModeToDb).toList(),
        'job_types': jobTypes.map(_jobTypeToDb).toList(),
      };

  factory JobPreferences.fromMap(Map<String, dynamic> m) => JobPreferences(
        userId: m['user_id'] as String,
        primaryLocationCountry: m['primary_location_country'] as String?,
        primaryLocationState: m['primary_location_state'] as String?,
        primaryLocationCity: m['primary_location_city'] as String?,
        primaryLocationPostalCode: m['primary_location_postal_code'] as String?,
        primaryLocationLat: (m['primary_location_lat'] as num?)?.toDouble(),
        primaryLocationLng: (m['primary_location_lng'] as num?)?.toDouble(),
        primaryLocationRadiusKm: (m['primary_location_radius_km'] as num?)?.toInt() ?? 50,
        experienceLevel: ((m['experience_level'] as List?) ?? [])
            .map((e) => _expLevelFromDb(e as String))
            .whereType<ExperienceLevel>()
            .toList(),
        workMode: ((m['work_mode'] as List?) ?? [])
            .map((e) => _workModeFromDb(e as String))
            .whereType<WorkMode>()
            .toList(),
        jobTypes: ((m['job_types'] as List?) ?? [])
            .map((e) => _jobTypeFromDb(e as String))
            .whereType<JobType>()
            .toList(),
      );

  JobPreferences copyWith({
    String? userId,
    String? primaryLocationCountry,
    String? primaryLocationState,
    String? primaryLocationCity,
    String? primaryLocationPostalCode,
    double? primaryLocationLat,
    double? primaryLocationLng,
    int? primaryLocationRadiusKm,
    List<ExperienceLevel>? experienceLevel,
    List<WorkMode>? workMode,
    List<JobType>? jobTypes,
  }) =>
      JobPreferences(
        userId: userId ?? this.userId,
        primaryLocationCountry: primaryLocationCountry ?? this.primaryLocationCountry,
        primaryLocationState: primaryLocationState ?? this.primaryLocationState,
        primaryLocationCity: primaryLocationCity ?? this.primaryLocationCity,
        primaryLocationPostalCode: primaryLocationPostalCode ?? this.primaryLocationPostalCode,
        primaryLocationLat: primaryLocationLat ?? this.primaryLocationLat,
        primaryLocationLng: primaryLocationLng ?? this.primaryLocationLng,
        primaryLocationRadiusKm: primaryLocationRadiusKm ?? this.primaryLocationRadiusKm,
        experienceLevel: experienceLevel ?? this.experienceLevel,
        workMode: workMode ?? this.workMode,
        jobTypes: jobTypes ?? this.jobTypes,
      );
}

@immutable
class DesiredTitle {
  final String id;
  final String userId;
  final String title;
  final DesiredTitleSource? source;
  final int orderIndex;

  const DesiredTitle({
    required this.id,
    required this.userId,
    required this.title,
    this.source,
    this.orderIndex = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'source': _sourceToDb(source),
        'order_index': orderIndex,
      };

  factory DesiredTitle.fromMap(Map<String, dynamic> m) => DesiredTitle(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        title: m['title'] as String? ?? '',
        source: _sourceFromDb(m['source'] as String?),
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );

  DesiredTitle copyWith({String? id, String? userId, String? title, DesiredTitleSource? source, int? orderIndex}) =>
      DesiredTitle(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        source: source ?? this.source,
        orderIndex: orderIndex ?? this.orderIndex,
      );
}

@immutable
class ApplicationCountry {
  final String id;
  final String userId;
  final String countryCode;
  final WorkAuth? workAuth;

  const ApplicationCountry({
    required this.id,
    required this.userId,
    required this.countryCode,
    this.workAuth,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'country_code': countryCode,
        'work_auth': _workAuthToDb(workAuth),
      };

  factory ApplicationCountry.fromMap(Map<String, dynamic> m) => ApplicationCountry(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        countryCode: m['country_code'] as String? ?? '',
        workAuth: _workAuthFromDb(m['work_auth'] as String?),
      );

  ApplicationCountry copyWith({String? id, String? userId, String? countryCode, WorkAuth? workAuth}) =>
      ApplicationCountry(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        countryCode: countryCode ?? this.countryCode,
        workAuth: workAuth ?? this.workAuth,
      );
}

@immutable
class OtherLocation {
  final String id;
  final String userId;
  final String? city;
  final String? state;
  final String? country;
  final int radiusKm;

  const OtherLocation({
    required this.id,
    required this.userId,
    this.city,
    this.state,
    this.country,
    this.radiusKm = 50,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'city': city,
        'state': state,
        'country': country,
        'radius_km': radiusKm,
      };

  factory OtherLocation.fromMap(Map<String, dynamic> m) => OtherLocation(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        city: m['city'] as String?,
        state: m['state'] as String?,
        country: m['country'] as String?,
        radiusKm: (m['radius_km'] as num?)?.toInt() ?? 50,
      );

  OtherLocation copyWith({String? id, String? userId, String? city, String? state, String? country, int? radiusKm}) =>
      OtherLocation(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        city: city ?? this.city,
        state: state ?? this.state,
        country: country ?? this.country,
        radiusKm: radiusKm ?? this.radiusKm,
      );
}

// Enum helpers DB <-> Dart
String _expLevelToDb(ExperienceLevel l) {
  switch (l) {
    case ExperienceLevel.entry: return 'entry';
    case ExperienceLevel.mid: return 'mid';
    case ExperienceLevel.senior: return 'senior';
  }
}
ExperienceLevel? _expLevelFromDb(String s) {
  switch (s) {
    case 'entry': return ExperienceLevel.entry;
    case 'mid': return ExperienceLevel.mid;
    case 'senior': return ExperienceLevel.senior;
    default: return null;
  }
}

String _workModeToDb(WorkMode m) {
  switch (m) {
    case WorkMode.remote: return 'remote';
    case WorkMode.hybrid: return 'hybrid';
    case WorkMode.inPerson: return 'in_person';
  }
}
WorkMode? _workModeFromDb(String s) {
  switch (s) {
    case 'remote': return WorkMode.remote;
    case 'hybrid': return WorkMode.hybrid;
    case 'in_person': return WorkMode.inPerson;
    default: return null;
  }
}

String _jobTypeToDb(JobType t) {
  switch (t) {
    case JobType.fullTime: return 'full_time';
    case JobType.internship: return 'internship';
    case JobType.contract: return 'contract';
    case JobType.partTime: return 'part_time';
  }
}
JobType? _jobTypeFromDb(String s) {
  switch (s) {
    case 'full_time': return JobType.fullTime;
    case 'internship': return JobType.internship;
    case 'contract': return JobType.contract;
    case 'part_time': return JobType.partTime;
    default: return null;
  }
}

String? _workAuthToDb(WorkAuth? a) {
  switch (a) {
    case WorkAuth.citizen: return 'citizen';
    case WorkAuth.authorized: return 'authorized';
    case WorkAuth.sponsorshipNeeded: return 'sponsorship_needed';
    case null: return null;
  }
}
WorkAuth? _workAuthFromDb(String? s) {
  switch (s) {
    case 'citizen': return WorkAuth.citizen;
    case 'authorized': return WorkAuth.authorized;
    case 'sponsorship_needed': return WorkAuth.sponsorshipNeeded;
    default: return null;
  }
}

String? _sourceToDb(DesiredTitleSource? s) {
  switch (s) {
    case DesiredTitleSource.userAdded: return 'user_added';
    case DesiredTitleSource.fromResume: return 'from_resume';
    case null: return null;
  }
}
DesiredTitleSource? _sourceFromDb(String? s) {
  switch (s) {
    case 'user_added': return DesiredTitleSource.userAdded;
    case 'from_resume': return DesiredTitleSource.fromResume;
    default: return null;
  }
}
