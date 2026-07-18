import 'package:career_gamification/features/resume/resume_tab.dart';
import 'package:career_gamification/features/trilha/data/assist_skills_writer_supabase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gate OFF não constrói nem injeta o writer CAS', () {
    var constructions = 0;

    final writer = resolveResumeTabAssistSkillsWriter(
      assistEnabled: false,
      factory: () {
        constructions++;
        return AssistSkillsWriterSupabase(
          rpcCall: (function, params) async => throw StateError('unexpected'),
        );
      },
    );

    expect(writer, isNull);
    expect(constructions, 0);
  });

  test('gate ON constrói uma vez e injeta o writer CAS escolhido', () {
    var constructions = 0;
    final expected = AssistSkillsWriterSupabase(
      rpcCall: (function, params) async => throw StateError('not called'),
    );

    final writer = resolveResumeTabAssistSkillsWriter(
      assistEnabled: true,
      factory: () {
        constructions++;
        return expected;
      },
    );

    expect(writer, same(expected));
    expect(constructions, 1);
  });
}
