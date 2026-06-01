import 'package:career_gamification/features/profile/domain/entities/education.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Education', () {
    test(
      'serializes college education fields used by onboarding and reports',
      () {
        final education = Education(
          id: 'education-1',
          userId: 'user-1',
          institution: 'Link School',
          educationLevel: 'college',
          educationStatus: 'studying',
          degree: 'Graduação',
          currentSemester: 6,
          majors: const [
            EducationMajor(
              id: 'major-1',
              educationId: 'education-1',
              name: 'Administração',
            ),
          ],
        );

        final map = education.toMap();

        expect(map['institution'], 'Link School');
        expect(map['education_level'], 'college');
        expect(map['education_status'], 'studying');
        expect(map['degree'], 'Graduação');
        expect(map['current_semester'], 6);
        expect(map['current_school_year'], isNull);
      },
    );

    test('deserializes relational education rows with majors and semester', () {
      final education = Education.fromMap({
        'id': 'education-1',
        'user_id': 'user-1',
        'institution': 'Insper',
        'education_level': 'college',
        'education_status': 'paused',
        'degree': 'Graduação',
        'current_semester': 4,
        'current_school_year': null,
        'order_index': 0,
        'profile_education_majors': [
          {
            'id': 'major-1',
            'education_id': 'education-1',
            'name': 'Economia',
            'order_index': 0,
          },
        ],
        'profile_education_minors': [],
        'profile_education_activities': [],
      });

      expect(education.institution, 'Insper');
      expect(education.educationLevel, 'college');
      expect(education.educationStatus, 'paused');
      expect(education.currentSemester, 4);
      expect(education.currentSchoolYear, isNull);
      expect(education.majors.single.name, 'Economia');
    });

    test('serializes school education without leaking college semester', () {
      final education = Education(
        id: 'education-2',
        userId: 'user-1',
        institution: 'Colégio Bandeirantes',
        educationLevel: 'school',
        educationStatus: 'studying',
        degree: 'Ensino médio',
        currentSchoolYear: 2,
      );

      final map = education.toMap();

      expect(map['institution'], 'Colégio Bandeirantes');
      expect(map['education_level'], 'school');
      expect(map['education_status'], 'studying');
      expect(map['degree'], 'Ensino médio');
      expect(map['current_school_year'], 2);
      expect(map['current_semester'], isNull);
    });
  });
}
