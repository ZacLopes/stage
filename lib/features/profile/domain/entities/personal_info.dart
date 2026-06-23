// PersonalInfo — espelho 1:1 da tabela `profile_personal`.
//
// completeness_score é calculado pelo backend (extract-profile) — cliente
// apenas exibe. profile_source default 'manual' quando criado pelo Flutter;
// 'imported' quando vem do extract-profile.

import 'package:flutter/foundation.dart';

enum Gender { male, female, other, preferNotToSay }
enum AgeRange { under18, age18_24, age25_34, age35_44, age45_54, age55_64, age65Plus }
enum ProfileSource { imported, manual, mixed }

@immutable
class PersonalInfo {
  final String userId;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phoneCountryCode;
  final String? phoneNumber;
  final String? headline;
  final String? summary;
  final Gender? gender;
  final AgeRange? ageRange;
  final DateTime? dateOfBirth;
  final String? locationCountry;
  final String? locationState;
  final String? locationCity;
  final String? locationPostalCode;
  final String? locationStreetAddress;
  final String? linkedinUrl;
  final String? website;
  final String? availability;
  final String? attributionSource;
  final ProfileSource? profileSource;
  final int completenessScore;
  final DateTime? profileCompletedAt;
  final DateTime? lastExtractedAt;

  const PersonalInfo({
    required this.userId,
    this.firstName,
    this.lastName,
    this.email,
    this.phoneCountryCode,
    this.phoneNumber,
    this.headline,
    this.summary,
    this.gender,
    this.ageRange,
    this.dateOfBirth,
    this.locationCountry,
    this.locationState,
    this.locationCity,
    this.locationPostalCode,
    this.locationStreetAddress,
    this.linkedinUrl,
    this.website,
    this.availability,
    this.attributionSource,
    this.profileSource,
    this.completenessScore = 0,
    this.profileCompletedAt,
    this.lastExtractedAt,
  });

  String get fullName {
    final f = firstName?.trim() ?? '';
    final l = lastName?.trim() ?? '';
    if (f.isEmpty && l.isEmpty) return '';
    if (f.isEmpty) return l;
    if (l.isEmpty) return f;
    return '$f $l';
  }

  String get formattedLocation {
    final parts = [locationCity, locationState, locationCountry]
        .where((p) => p != null && p.trim().isNotEmpty)
        .toList();
    return parts.join(', ');
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone_country_code': phoneCountryCode,
      'phone_number': phoneNumber,
      'headline': headline,
      'summary': summary,
      'gender': _genderToDb(gender),
      'age_range': _ageRangeToDb(ageRange),
      'date_of_birth': _dateOnlyToDb(dateOfBirth),
      'location_country': locationCountry,
      'location_state': locationState,
      'location_city': locationCity,
      'location_postal_code': locationPostalCode,
      'location_street_address': locationStreetAddress,
      'linkedin_url': linkedinUrl,
      'website': website,
      'availability': availability,
      'attribution_source': attributionSource,
      'profile_source': _profileSourceToDb(profileSource),
      'completeness_score': completenessScore,
      'profile_completed_at': profileCompletedAt?.toIso8601String(),
      'last_extracted_at': lastExtractedAt?.toIso8601String(),
    };
  }

  factory PersonalInfo.fromMap(Map<String, dynamic> map) {
    return PersonalInfo(
      userId: map['user_id'] as String,
      firstName: map['first_name'] as String?,
      lastName: map['last_name'] as String?,
      email: map['email'] as String?,
      phoneCountryCode: map['phone_country_code'] as String?,
      phoneNumber: map['phone_number'] as String?,
      headline: map['headline'] as String?,
      summary: map['summary'] as String?,
      gender: _genderFromDb(map['gender'] as String?),
      ageRange: _ageRangeFromDb(map['age_range'] as String?),
      dateOfBirth: _dateOnlyFromDb(map['date_of_birth']),
      locationCountry: map['location_country'] as String?,
      locationState: map['location_state'] as String?,
      locationCity: map['location_city'] as String?,
      locationPostalCode: map['location_postal_code'] as String?,
      locationStreetAddress: map['location_street_address'] as String?,
      linkedinUrl: map['linkedin_url'] as String?,
      website: map['website'] as String?,
      availability: map['availability'] as String?,
      attributionSource: map['attribution_source'] as String?,
      profileSource: _profileSourceFromDb(map['profile_source'] as String?),
      completenessScore: (map['completeness_score'] as num?)?.toInt() ?? 0,
      profileCompletedAt: map['profile_completed_at'] != null
          ? DateTime.parse(map['profile_completed_at'] as String)
          : null,
      lastExtractedAt: map['last_extracted_at'] != null
          ? DateTime.parse(map['last_extracted_at'] as String)
          : null,
    );
  }

  PersonalInfo copyWith({
    String? userId,
    String? firstName,
    String? lastName,
    String? email,
    String? phoneCountryCode,
    String? phoneNumber,
    String? headline,
    String? summary,
    Gender? gender,
    AgeRange? ageRange,
    DateTime? dateOfBirth,
    String? locationCountry,
    String? locationState,
    String? locationCity,
    String? locationPostalCode,
    String? locationStreetAddress,
    String? linkedinUrl,
    String? website,
    String? availability,
    String? attributionSource,
    ProfileSource? profileSource,
    int? completenessScore,
    DateTime? profileCompletedAt,
    DateTime? lastExtractedAt,
  }) {
    return PersonalInfo(
      userId: userId ?? this.userId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phoneCountryCode: phoneCountryCode ?? this.phoneCountryCode,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      headline: headline ?? this.headline,
      summary: summary ?? this.summary,
      gender: gender ?? this.gender,
      ageRange: ageRange ?? this.ageRange,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      locationCountry: locationCountry ?? this.locationCountry,
      locationState: locationState ?? this.locationState,
      locationCity: locationCity ?? this.locationCity,
      locationPostalCode: locationPostalCode ?? this.locationPostalCode,
      locationStreetAddress: locationStreetAddress ?? this.locationStreetAddress,
      linkedinUrl: linkedinUrl ?? this.linkedinUrl,
      website: website ?? this.website,
      availability: availability ?? this.availability,
      attributionSource: attributionSource ?? this.attributionSource,
      profileSource: profileSource ?? this.profileSource,
      completenessScore: completenessScore ?? this.completenessScore,
      profileCompletedAt: profileCompletedAt ?? this.profileCompletedAt,
      lastExtractedAt: lastExtractedAt ?? this.lastExtractedAt,
    );
  }
}

// Helpers de enum (Postgres usa snake_case nos CHECK constraints).
String? _genderToDb(Gender? g) {
  switch (g) {
    case Gender.male: return 'male';
    case Gender.female: return 'female';
    case Gender.other: return 'other';
    case Gender.preferNotToSay: return 'prefer_not_to_say';
    case null: return null;
  }
}

Gender? _genderFromDb(String? s) {
  switch (s) {
    case 'male': return Gender.male;
    case 'female': return Gender.female;
    case 'other': return Gender.other;
    case 'prefer_not_to_say': return Gender.preferNotToSay;
    default: return null;
  }
}

String? _ageRangeToDb(AgeRange? a) {
  switch (a) {
    case AgeRange.under18: return 'under_18';
    case AgeRange.age18_24: return '18_24';
    case AgeRange.age25_34: return '25_34';
    case AgeRange.age35_44: return '35_44';
    case AgeRange.age45_54: return '45_54';
    case AgeRange.age55_64: return '55_64';
    case AgeRange.age65Plus: return '65_plus';
    case null: return null;
  }
}

AgeRange? _ageRangeFromDb(String? s) {
  switch (s) {
    case 'under_18': return AgeRange.under18;
    case '18_24': return AgeRange.age18_24;
    case '25_34': return AgeRange.age25_34;
    case '35_44': return AgeRange.age35_44;
    case '45_54': return AgeRange.age45_54;
    case '55_64': return AgeRange.age55_64;
    case '65_plus': return AgeRange.age65Plus;
    default: return null;
  }
}

String? _profileSourceToDb(ProfileSource? s) {
  switch (s) {
    case ProfileSource.imported: return 'imported';
    case ProfileSource.manual: return 'manual';
    case ProfileSource.mixed: return 'mixed';
    case null: return null;
  }
}

ProfileSource? _profileSourceFromDb(String? s) {
  switch (s) {
    case 'imported': return ProfileSource.imported;
    case 'manual': return ProfileSource.manual;
    case 'mixed': return ProfileSource.mixed;
    default: return null;
  }
}

// Postgres DATE: YYYY-MM-DD. Não inclui timezone — usamos a parte UTC
// pra evitar drift por fuso (uma data de nascimento é um dia civil, não
// um instante).
String? _dateOnlyToDb(DateTime? d) {
  if (d == null) return null;
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime? _dateOnlyFromDb(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString();
  return DateTime.tryParse(s);
}

/// Deriva [AgeRange] a partir da data de nascimento. Usa idade em anos
/// completos no momento da chamada. Retorna null se [dob] for null ou no futuro.
AgeRange? ageRangeFromDate(DateTime? dob, {DateTime? now}) {
  if (dob == null) return null;
  final ref = now ?? DateTime.now();
  if (dob.isAfter(ref)) return null;
  var age = ref.year - dob.year;
  final hadBirthdayThisYear = (ref.month > dob.month) ||
      (ref.month == dob.month && ref.day >= dob.day);
  if (!hadBirthdayThisYear) age -= 1;
  if (age < 18) return AgeRange.under18;
  if (age <= 24) return AgeRange.age18_24;
  if (age <= 34) return AgeRange.age25_34;
  if (age <= 44) return AgeRange.age35_44;
  if (age <= 54) return AgeRange.age45_54;
  if (age <= 64) return AgeRange.age55_64;
  return AgeRange.age65Plus;
}
