import 'package:career_gamification/features/profile/domain/entities/entities.dart';
import 'package:career_gamification/features/resume/data/profile_pdf_data_loader.dart';
import 'package:career_gamification/features/resume/pdf_service.dart';
import 'package:career_gamification/features/resume/widgets/general_resume_preview.dart';
import 'package:career_gamification/services/profile_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _templates = <String>[
  'harvard_ats',
  'jakes_resume',
  'forte_foundation',
  'one_page_compact',
  'cobalt_modern',
];

Education _education({
  String degree = 'Bacharelado',
  String major = 'Administração',
  String? status,
  DateTime? start,
  DateTime? end,
}) => Education(
  id: 'education',
  userId: 'user',
  institution: 'Link School of Business',
  degree: degree,
  educationStatus: status,
  startDate: start,
  endDate: end,
  majors: [EducationMajor(id: 'major', educationId: 'education', name: major)],
);

void main() {
  group('contrato canônico de Educação', () {
    test('deduplica grau/curso equivalentes sem sufixo artificial Major', () {
      final education = _education(
        degree: 'Administração',
        major: 'administração',
      );
      final item = ProfileSnapshot(
        education: [education],
      ).toResumeData().education.single;

      expect(item.degree, 'Administração');
      expect(item.details, isEmpty);
      expect('${item.degree} ${item.details}', isNot(contains('Major')));
    });

    test('combina grau genérico e curso em português natural', () {
      final item = ProfileSnapshot(
        education: [_education()],
      ).toResumeData().education.single;

      expect(item.degree, 'Bacharelado em Administração');
      expect(item.details, isEmpty);
    });

    test('marca previsão de conclusão e nunca inventa Atual', () {
      final expected = _education(
        status: 'studying',
        start: DateTime(2095, 2),
        end: DateTime(2099, 12),
      );
      final withoutEnd = _education(
        status: 'studying',
        start: DateTime(2095, 2),
      );

      expect(
        expected.formattedPeriodAt(DateTime(2096, 7)),
        'Fev 2095 - Dez 2099 (previsto)',
      );
      expect(
        withoutEnd.formattedPeriodAt(DateTime(2096, 7)),
        'Fev 2095 - Em andamento',
      );
      expect(withoutEnd.formattedPeriod, isNot(contains('Atual')));
    });

    test('Snapshot e ProfilePdfData usam exatamente a mesma projeção', () {
      final education = _education(status: 'studying', end: DateTime(2099, 12));
      final snapshotItem = ProfileSnapshot(
        education: [education],
      ).toResumeData().education.single;
      final pdfItem = ProfilePdfData(
        personal: const PersonalInfo(userId: 'user'),
        experiences: const [],
        education: [education],
        skills: const [],
        languages: const [],
        certifications: const [],
        projects: const [],
        interests: const [],
        awards: const [],
      ).toResumeData().education.single;

      expect(pdfItem.degree, snapshotItem.degree);
      expect(pdfItem.details, snapshotItem.details);
      expect(pdfItem.period, snapshotItem.period);
      expect(pdfItem.gpa, snapshotItem.gpa);
      expect(pdfItem.activities, snapshotItem.activities);
    });

    test('não repete Administração em nenhum template de PDF', () {
      final resume = ProfileSnapshot(
        education: [
          _education(degree: 'Administração', major: 'Administração'),
        ],
      ).toResumeData();

      for (final template in _templates) {
        final html = PdfService.buildResumeHtmlForTest(null, resume, template);
        expect(html, isNot(contains('Administração Major')));
        expect(
          RegExp('Administração').allMatches(html),
          hasLength(1),
          reason: template,
        );
      }
    });

    test('prévia mostra a mesma qualificação e período do PDF', () {
      final education = _education(status: 'studying', end: DateTime(2099, 12));
      final row = educationPreviewRow(education);
      final mapped = ProfileSnapshot(
        education: [education],
      ).toResumeData().education.single;

      expect(row.title, mapped.degree);
      expect(row.subtitle, contains(mapped.institution));
      expect(row.subtitle, contains(mapped.period));
    });
  });

  group('capitalização conservadora', () {
    test('capitaliza minúsculos e preserva marca e sigla existentes', () {
      final resume = const ProfileSnapshot(
        projects: [
          Project(
            id: 'project-1',
            userId: 'user',
            name: 'aplicativo de busca de estágios',
          ),
          Project(id: 'project-2', userId: 'user', name: 'iFood TCC'),
        ],
        awards: [Award(id: 'award', userId: 'user', name: 'hackathon na link')],
      ).toResumeData();

      expect(
        resume.academicProjects.first.title,
        'Aplicativo de busca de estágios',
      );
      expect(resume.academicProjects.last.title, 'iFood TCC');
      expect(resume.awards.single.title, 'Hackathon na link');
      expect(
        projectPreviewRow(
          const Project(id: 'p', userId: 'user', name: 'aplicativo social'),
        ).title,
        'Aplicativo social',
      );
      expect(
        awardPreviewTitle(
          const Award(id: 'a', userId: 'user', name: 'prêmio universitário'),
        ),
        'Prêmio universitário',
      );
    });
  });
}
