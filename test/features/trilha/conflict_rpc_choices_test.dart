import 'package:career_gamification/features/trilha/application/conflict_rpc_choices.dart';
import 'package:career_gamification/features/trilha/application/cv_conflict.dart';
import 'package:flutter_test/flutter_test.dart';

ConflictRow _row(
  ConflictSection section,
  ConflictKind kind, {
  String field = '',
  String value = '',
  String currentText = '',
  String extra = '',
  String refId = '',
  Map<String, dynamic> cvItem = const {},
}) =>
    ConflictRow(
      id: 'r',
      section: section,
      kind: kind,
      label: 'l',
      cvText: 'cv',
      field: field,
      value: value,
      currentText: currentText,
      extra: extra,
      refId: refId,
      cvItem: cvItem,
    );

void main() {
  group('conflictRowToRpcChoice — Gate 3.0I (mapa por seção)', () {
    test('escalar (summary): personal com expected=observado, value efetivo', () {
      final r = _row(ConflictSection.summary, ConflictKind.conflict,
          field: 'summary', currentText: 'antigo', value: 'do CV');
      expect(conflictRowToRpcChoice(r, 'editado'), {
        'kind': 'personal',
        'field': 'summary',
        'expected': 'antigo',
        'value': 'editado',
      });
    });

    test('name/phone/city/linkedin/website também viram personal', () {
      for (final f in [
        ConflictSection.name,
        ConflictSection.phone,
        ConflictSection.city,
        ConflictSection.linkedin,
        ConflictSection.website,
      ]) {
        final r = _row(f, ConflictKind.conflict, field: f.name, currentText: 'y');
        final c = conflictRowToRpcChoice(r, 'v');
        expect(c?['kind'], 'personal');
        expect(c?['field'], f.name);
        expect(c?['expected'], 'y');
      }
    });

    test('add: skill/interest/coursework/award/project com source=original', () {
      for (final s in [
        ConflictSection.skill,
        ConflictSection.interest,
        ConflictSection.coursework,
        ConflictSection.award,
        ConflictSection.project,
      ]) {
        final r = _row(s, ConflictKind.addition, value: 'Original');
        expect(conflictRowToRpcChoice(r, 'Editado'), {
          'kind': 'add',
          'section': s.name,
          'value': 'Editado',
          'source': 'Original',
        });
      }
    });

    test('certification: add_cert com issuer (extra) e source', () {
      final r = _row(ConflictSection.certification, ConflictKind.addition,
          value: 'AWS SAA', extra: 'Amazon');
      expect(conflictRowToRpcChoice(r, 'AWS SAA'), {
        'kind': 'add_cert',
        'name': 'AWS SAA',
        'issuer': 'Amazon',
        'source': 'AWS SAA',
      });
    });

    test('certification sem issuer: sem chave issuer', () {
      final r = _row(ConflictSection.certification, ConflictKind.addition,
          value: 'Scrum');
      expect(conflictRowToRpcChoice(r, 'Scrum'), {
        'kind': 'add_cert',
        'name': 'Scrum',
        'source': 'Scrum',
      });
    });

    test('language ADIÇÃO: add_lang (nível vem do payload)', () {
      final r = _row(ConflictSection.language, ConflictKind.addition,
          value: 'Inglês', extra: 'advanced');
      expect(conflictRowToRpcChoice(r, 'Inglês'), {
        'kind': 'add_lang',
        'name': 'Inglês',
        'source': 'Inglês',
      });
    });

    test('language CONFLITO de nível → null (LACUNA documentada, fail-closed)', () {
      final r = _row(ConflictSection.language, ConflictKind.conflict,
          value: 'Inglês', currentText: 'Básico', extra: 'advanced');
      expect(conflictRowToRpcChoice(r, 'Inglês'), isNull);
    });

    test('experience conflito → item_field; adição → add_experience', () {
      final conf = _row(ConflictSection.experience, ConflictKind.conflict,
          field: 'title', currentText: 'Dev', refId: 'e1');
      expect(conflictRowToRpcChoice(conf, 'Senior Dev'), {
        'kind': 'item_field',
        'section': 'experience',
        'field': 'title',
        'expected': 'Dev',
        'value': 'Senior Dev',
        'ref_id': 'e1',
      });
      final add = _row(ConflictSection.experience, ConflictKind.addition,
          cvItem: {'company': 'Acme', 'title': 'Estágio'});
      expect(conflictRowToRpcChoice(add, 'x'), {
        'kind': 'add_experience',
        'company': 'Acme',
        'title': 'Estágio',
      });
    });

    test('education conflito → item_field; adição → add_education', () {
      final conf = _row(ConflictSection.education, ConflictKind.conflict,
          field: 'degree', currentText: 'Bacharel', refId: 'ed1');
      expect(conflictRowToRpcChoice(conf, 'Bacharelado'), {
        'kind': 'item_field',
        'section': 'education',
        'field': 'degree',
        'expected': 'Bacharel',
        'value': 'Bacharelado',
        'ref_id': 'ed1',
      });
      final add = _row(ConflictSection.education, ConflictKind.addition,
          cvItem: {'institution': 'USP', 'degree': 'Graduação'});
      expect(conflictRowToRpcChoice(add, 'x'), {
        'kind': 'add_education',
        'institution': 'USP',
        'degree': 'Graduação',
      });
    });
  });
}
