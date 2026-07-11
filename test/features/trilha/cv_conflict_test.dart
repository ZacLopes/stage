// Testa o cérebro do widget de conflito de import de CV (puro): dado o CV
// parseado (profile_data) e o perfil atual, produz ADIÇÃO / CONFLITO e omite
// o que é IGUAL.
import 'package:career_gamification/features/profile/domain/entities/entities.dart';
import 'package:career_gamification/features/trilha/application/cv_conflict.dart';
import 'package:career_gamification/services/profile_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';

ConflictRow _by(List<ConflictRow> rows, ConflictSection s) =>
    rows.firstWhere((r) => r.section == s);

bool _has(List<ConflictRow> rows, ConflictSection s) =>
    rows.any((r) => r.section == s);

void main() {
  group('CvConflictDiff — pessoais (escalares)', () {
    test('campo vazio no perfil → ADIÇÃO', () {
      final rows = CvConflictDiff.compute({
        'personal': {'location_city': 'Recife', 'location_state': 'PE'}
      }, const ProfileSnapshot());
      final city = _by(rows, ConflictSection.city);
      expect(city.kind, ConflictKind.addition);
      expect(city.cvText, 'Recife, PE');
      expect(city.field, 'city');
      expect(city.value, 'Recife, PE');
    });

    test('valor diferente → CONFLITO com X e Y', () {
      final rows = CvConflictDiff.compute({
        'personal': {'location_city': 'Recife', 'location_state': 'PE'}
      }, const ProfileSnapshot(
          personal: PersonalInfo(
              userId: 'u', locationCity: 'São Paulo', locationState: 'SP')));
      final city = _by(rows, ConflictSection.city);
      expect(city.kind, ConflictKind.conflict);
      expect(city.cvText, 'Recife, PE');
      expect(city.currentText, 'São Paulo, SP');
    });

    test('valor igual (acento/caixa) → OMITIDO', () {
      final rows = CvConflictDiff.compute({
        'personal': {'summary': 'Analista de Dados'}
      }, const ProfileSnapshot(
          personal:
              PersonalInfo(userId: 'u', summary: 'analista de dados')));
      expect(_has(rows, ConflictSection.summary), isFalse);
    });

    test('nome monta first+last e casa vazio→adição', () {
      final rows = CvConflictDiff.compute({
        'personal': {'first_name': 'João', 'last_name': 'Silva'}
      }, const ProfileSnapshot());
      final n = _by(rows, ConflictSection.name);
      expect(n.value, 'João Silva');
      expect(n.kind, ConflictKind.addition);
    });

    test('CV sem valor → nada proposto', () {
      final rows = CvConflictDiff.compute(
          {'personal': {'linkedin': ''}}, const ProfileSnapshot());
      expect(rows, isEmpty);
    });

    test('cidade: CV sem UF, perfil com UF, mesma cidade → OMITIDO (não apaga)',
        () {
      final rows = CvConflictDiff.compute({
        'personal': {'location_city': 'São Paulo'} // sem location_state
      }, const ProfileSnapshot(
          personal: PersonalInfo(
              userId: 'u', locationCity: 'São Paulo', locationState: 'SP')));
      expect(_has(rows, ConflictSection.city), isFalse);
    });

    test('cidade: CV traz UF que faltava → ADIÇÃO (enriquece)', () {
      final rows = CvConflictDiff.compute({
        'personal': {'location_city': 'São Paulo', 'location_state': 'SP'}
      }, const ProfileSnapshot(
          personal: PersonalInfo(userId: 'u', locationCity: 'São Paulo')));
      final c = _by(rows, ConflictSection.city);
      expect(c.kind, ConflictKind.addition);
      expect(c.value, 'São Paulo, SP');
    });

    test('nome: CV sem sobrenome (prefixo do atual) → OMITIDO (não derruba)', () {
      final rows = CvConflictDiff.compute({
        'personal': {'first_name': 'João'} // sem last_name
      }, const ProfileSnapshot(
          personal:
              PersonalInfo(userId: 'u', firstName: 'João', lastName: 'Silva')));
      expect(_has(rows, ConflictSection.name), isFalse);
    });
  });

  group('CvConflictDiff — listas planas', () {
    test('skill nova → adição; skill que já tem → omitida', () {
      final rows = CvConflictDiff.compute({
        'skills': [
          {'name': 'Python'},
          {'name': 'SQL'}
        ]
      }, const ProfileSnapshot(
          skills: [Skill(id: 's1', userId: 'u', name: 'python')]));
      final skills =
          rows.where((r) => r.section == ConflictSection.skill).toList();
      expect(skills.length, 1); // só SQL (Python já existe, case-insensitive)
      expect(skills.single.value, 'SQL');
      expect(skills.single.kind, ConflictKind.addition);
    });

    test('skills duplicadas no CV → dedup', () {
      final rows = CvConflictDiff.compute({
        'skills': [
          {'name': 'Excel'},
          {'name': 'excel'}
        ]
      }, const ProfileSnapshot());
      expect(rows.where((r) => r.section == ConflictSection.skill).length, 1);
    });

    test('certificação casa por nome+emissor', () {
      final rows = CvConflictDiff.compute({
        'certifications': [
          {'name': 'AWS', 'issuer': 'Amazon'},
          {'name': 'Scrum', 'issuer': 'Scrum.org'}
        ]
      }, const ProfileSnapshot(certifications: [
        Certification(id: 'c1', userId: 'u', name: 'AWS', issuer: 'Amazon')
      ]));
      final certs = rows
          .where((r) => r.section == ConflictSection.certification)
          .toList();
      expect(certs.length, 1); // AWS/Amazon já existe → só Scrum
      expect(certs.single.value, 'Scrum');
      expect(certs.single.extra, 'Scrum.org');
    });
  });

  group('CvConflictDiff — idiomas', () {
    test('idioma novo → adição com nível', () {
      final rows = CvConflictDiff.compute({
        'languages': [
          {'name': 'Inglês', 'proficiency': 'advanced'}
        ]
      }, const ProfileSnapshot());
      final l = _by(rows, ConflictSection.language);
      expect(l.kind, ConflictKind.addition);
      expect(l.value, 'Inglês');
      expect(l.extra, 'advanced');
    });

    test('mesmo idioma, nível diferente → conflito', () {
      final rows = CvConflictDiff.compute({
        'languages': [
          {'name': 'Inglês', 'proficiency': 'fluent'}
        ]
      }, const ProfileSnapshot(languages: [
        Language(
            id: 'l1',
            userId: 'u',
            name: 'Inglês',
            proficiency: LanguageProficiency.intermediate)
      ]));
      final l = _by(rows, ConflictSection.language);
      expect(l.kind, ConflictKind.conflict);
      expect(l.extra, 'fluent');
      expect(l.currentText, isNotEmpty);
    });

    test('mesmo idioma, mesmo nível → omitido', () {
      final rows = CvConflictDiff.compute({
        'languages': [
          {'name': 'Inglês', 'proficiency': 'advanced'}
        ]
      }, const ProfileSnapshot(languages: [
        Language(
            id: 'l1',
            userId: 'u',
            name: 'Inglês',
            proficiency: LanguageProficiency.advanced)
      ]));
      expect(_has(rows, ConflictSection.language), isFalse);
    });
  });

  group('CvConflictDiff — experiências', () {
    test('empresa nova → adição (carrega o item cru)', () {
      final rows = CvConflictDiff.compute({
        'experiences': [
          {'title': 'Estágio', 'company': 'Ambev', 'start_date': '2023-01'}
        ]
      }, const ProfileSnapshot());
      final e = _by(rows, ConflictSection.experience);
      expect(e.kind, ConflictKind.addition);
      expect(e.label, 'Estágio · Ambev');
      expect(e.cvItem['company'], 'Ambev');
    });

    test('mesma empresa, cargo diferente → conflito editável (title/refId)', () {
      final rows = CvConflictDiff.compute({
        'experiences': [
          {'title': 'Analista', 'company': 'Ambev'}
        ]
      }, ProfileSnapshot(experiences: [
        Experience(
            id: 'e1',
            userId: 'u',
            title: 'Estagiário',
            company: 'Ambev',
            startDate: DateTime(2023))
      ]));
      final e = _by(rows, ConflictSection.experience);
      expect(e.kind, ConflictKind.conflict);
      expect(e.field, 'title');
      expect(e.value, 'Analista');
      expect(e.currentText, 'Estagiário');
      expect(e.refId, 'e1');
    });

    test('mesma empresa, mesmo cargo → omitido', () {
      final rows = CvConflictDiff.compute({
        'experiences': [
          {'title': 'Estagiário', 'company': 'Ambev'}
        ]
      }, ProfileSnapshot(experiences: [
        Experience(
            id: 'e1',
            userId: 'u',
            title: 'estagiário',
            company: 'ambev',
            startDate: DateTime(2023))
      ]));
      expect(_has(rows, ConflictSection.experience), isFalse);
    });

    test('2 cargos na MESMA empresa → cargo novo vira ADIÇÃO, não conflito', () {
      final rows = CvConflictDiff.compute({
        'experiences': [
          {'title': 'Analista', 'company': 'Ambev', 'start_date': '2021'}
        ]
      }, ProfileSnapshot(experiences: [
        Experience(
            id: 'e1',
            userId: 'u',
            title: 'Estágio',
            company: 'Ambev',
            startDate: DateTime(2019)),
        Experience(
            id: 'e2',
            userId: 'u',
            title: 'Trainee',
            company: 'Ambev',
            startDate: DateTime(2020)),
      ]));
      final e = _by(rows, ConflictSection.experience);
      // 2 experiências na Ambev ⇒ ambíguo ⇒ NÃO mexe em nenhuma (adição).
      expect(e.kind, ConflictKind.addition);
    });

    test('experiência sem start_date → NÃO oferecida (não inventa "hoje")', () {
      final rows = CvConflictDiff.compute({
        'experiences': [
          {'title': 'Freelancer', 'company': 'Autônomo'} // sem start_date
        ]
      }, ProfileSnapshot(experiences: [
        Experience(
            id: 'e1',
            userId: 'u',
            title: 'Outro',
            company: 'OutraEmpresa',
            startDate: DateTime(2023))
      ]));
      expect(_has(rows, ConflictSection.experience), isFalse);
    });
  });

  group('CvConflictDiff — formação', () {
    test('instituição nova → adição', () {
      final rows = CvConflictDiff.compute({
        'education': [
          {'institution': 'USP', 'degree': 'Engenharia'}
        ]
      }, const ProfileSnapshot());
      final e = _by(rows, ConflictSection.education);
      expect(e.kind, ConflictKind.addition);
      expect(e.cvItem['institution'], 'USP');
    });

    test('mesma instituição, curso diferente → conflito', () {
      final rows = CvConflictDiff.compute({
        'education': [
          {'institution': 'USP', 'degree': 'Ciência da Computação'}
        ]
      }, const ProfileSnapshot(education: [
        Education(
            id: 'ed1', userId: 'u', institution: 'USP', degree: 'Engenharia')
      ]));
      final e = _by(rows, ConflictSection.education);
      expect(e.kind, ConflictKind.conflict);
      expect(e.field, 'degree');
      expect(e.refId, 'ed1');
    });
  });

  test('CV vazio → nenhuma linha', () {
    expect(CvConflictDiff.compute(const {}, const ProfileSnapshot()), isEmpty);
  });
}
