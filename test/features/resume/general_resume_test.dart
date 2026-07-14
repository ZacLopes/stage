// Fase 2 (casa única do perfil) — testes de comportamento do currículo geral.
//
// Cobre o CONTRATO REAL dos templates (a correção final):
//   • snapshot.toResumeData → prêmios em ResumeData.awards (NÃO achievements);
//     projetos em academicProjects; os dois convivem.
//   • O RENDERER/TEMPLATE de verdade (via seam PdfService.buildResumeHtmlForTest):
//     prêmio único, projeto único e prêmio+projeto aparecem nos CINCO templates;
//     whitespace não gera seção vazia.
//   • Origem do ResumeRenderer (decideSource): forceFallback → canonical (flag
//     ON/OFF idênticos), demais caminhos preservados.
//   • Loader do currículo geral: fontes usadas estritas (falha → failed);
//     coursework best-effort (falha NÃO bloqueia); vazio legítimo → empty.
//   • Predicate único (projetos incluídos, trim), card responsivo, prévia
//     (inclui Projetos), gating flag ON/OFF (AssistantTabLayout).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/services/profile_snapshot_service.dart';
import 'package:career_gamification/features/profile/domain/repositories/profile_repository.dart';
import 'package:career_gamification/features/profile/domain/entities/entities.dart';
import 'package:career_gamification/features/resume/pdf_service.dart';
import 'package:career_gamification/features/resume/resume_viewmodel.dart'
    show ResumeData, ExperienceItem, EducationItem;
import 'package:career_gamification/data/models/models.dart'
    show ResumeAward, ResumeProject, ResumeCourse, ResumeLanguage;
import 'package:career_gamification/features/resume/services/resume_renderer.dart';
import 'package:career_gamification/features/resume/services/general_resume_export.dart';
import 'package:career_gamification/features/resume/widgets/general_resume_card.dart';
import 'package:career_gamification/features/resume/widgets/general_resume_preview.dart';
import 'package:career_gamification/features/resume/widgets/assistant_tab_layout.dart';
import 'package:career_gamification/features/resume/widgets/curriculo_toggle.dart';
import 'package:career_gamification/features/trilha/presentation/trilha_chat_controller.dart'
    show AssistExportOutcome;

const _kTemplates = <String>[
  'harvard_ats',
  'jakes_resume',
  'forte_foundation',
  'one_page_compact',
  'cobalt_modern',
];

ProfileSnapshot _oneSkill() => const ProfileSnapshot(
  skills: [Skill(id: 's', userId: 'u', name: 'Excel')],
);

/// Repositório fake p/ exercitar o loader real (sem Supabase).
/// `failing` = nomes de consultas que lançam. As demais retornam o que foi
/// configurado (ou vazio). Métodos não usados caem no noSuchMethod.
class _FakeRepo implements ProfileRepository {
  _FakeRepo({this.skills = const [], this.failing = const <String>{}});

  final List<Skill> skills;
  final Set<String> failing;

  Future<T> _v<T>(String name, T value) async {
    if (failing.contains(name)) throw StateError('$name failed');
    return value;
  }

  @override
  Future<PersonalInfo?> getPersonal(String u) =>
      _v<PersonalInfo?>('getPersonal', null);
  @override
  Future<List<Experience>> getExperiences(String u) =>
      _v('getExperiences', const <Experience>[]);
  @override
  Future<List<Education>> getEducation(String u) =>
      _v('getEducation', const <Education>[]);
  @override
  Future<List<Skill>> getSkills(String u) => _v('getSkills', skills);
  @override
  Future<List<Language>> getLanguages(String u) =>
      _v('getLanguages', const <Language>[]);
  @override
  Future<List<Certification>> getCertifications(String u) =>
      _v('getCertifications', const <Certification>[]);
  @override
  Future<List<Project>> getProjects(String u) =>
      _v('getProjects', const <Project>[]);
  @override
  Future<List<Interest>> getInterests(String u) =>
      _v('getInterests', const <Interest>[]);
  @override
  Future<List<Award>> getAwards(String u) => _v('getAwards', const <Award>[]);
  @override
  Future<List<Coursework>> getCoursework(String u) =>
      _v('getCoursework', const <Coursework>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('snapshotHasContent — contrato único (campos renderáveis)', () {
    test('snapshot vazio → false (resumeData legado NÃO conta)', () {
      expect(
        GeneralResumeExport.snapshotHasContent(const ProfileSnapshot()),
        isFalse,
      );
    });
    test('só summary → true', () {
      expect(
        GeneralResumeExport.snapshotHasContent(
          const ProfileSnapshot(
            personal: PersonalInfo(userId: 'u', summary: 'x'),
          ),
        ),
        isTrue,
      );
    });
    test('só headline (NÃO renderizado) → false', () {
      expect(
        GeneralResumeExport.snapshotHasContent(
          const ProfileSnapshot(
            personal: PersonalInfo(userId: 'u', headline: 'x'),
          ),
        ),
        isFalse,
      );
    });
    test('só certificação → true', () {
      expect(
        GeneralResumeExport.snapshotHasContent(
          const ProfileSnapshot(
            certifications: [Certification(id: 'c', userId: 'u', name: 'AWS')],
          ),
        ),
        isTrue,
      );
    });
    test('só prêmio → true', () {
      expect(
        GeneralResumeExport.snapshotHasContent(
          const ProfileSnapshot(
            awards: [Award(id: 'a', userId: 'u', name: 'Menção')],
          ),
        ),
        isTrue,
      );
    });
    test('só projeto → true (projetos ENTRAM no currículo geral)', () {
      expect(
        GeneralResumeExport.snapshotHasContent(
          const ProfileSnapshot(
            projects: [Project(id: 'p', userId: 'u', name: 'App')],
          ),
        ),
        isTrue,
      );
    });
    test('projeto só-espaço (sem texto renderável) NÃO habilita', () {
      expect(
        GeneralResumeExport.snapshotHasContent(
          const ProfileSnapshot(
            projects: [Project(id: 'p', userId: 'u', name: '  ')],
          ),
        ),
        isFalse,
      );
    });
    test('só skills → true', () {
      expect(GeneralResumeExport.snapshotHasContent(_oneSkill()), isTrue);
    });
    test('itens só-espaço (vazios após trim) NÃO habilitam', () {
      expect(
        GeneralResumeExport.snapshotHasContent(
          const ProfileSnapshot(
            skills: [Skill(id: 's', userId: 'u', name: '  ')],
            interests: [Interest(id: 'i', userId: 'u', name: '')],
            awards: [Award(id: 'a', userId: 'u', name: '   ')],
          ),
        ),
        isFalse,
      );
    });
  });

  // O ResumeData do currículo geral vem SÓ de snapshot.toResumeData (o export
  // renderiza este mesmo objeto via forceFallback). Contrato corrigido: prêmios
  // vão pra ResumeData.awards (seção própria), projetos pra academicProjects; as
  // duas seções são INDEPENDENTES — nenhuma suprime a outra.
  group('ResumeData do currículo geral (snapshot.toResumeData)', () {
    test('prêmios → ResumeData.awards, NÃO achievements', () {
      final rd = const ProfileSnapshot(
        awards: [Award(id: 'a', userId: 'u', name: '1º lugar hackathon')],
      ).toResumeData();
      expect(rd.awards.map((a) => a.title), contains('1º Lugar hackathon'));
      expect(rd.achievements, isEmpty);
    });

    test('projetos → academicProjects', () {
      final rd = const ProfileSnapshot(
        projects: [Project(id: 'p', userId: 'u', name: 'App')],
      ).toResumeData();
      expect(rd.academicProjects.map((p) => p.title), contains('App'));
    });

    test('projeto + prêmio → ambos presentes (nenhum some)', () {
      final rd = const ProfileSnapshot(
        awards: [Award(id: 'a', userId: 'u', name: 'Prêmio X')],
        projects: [Project(id: 'p', userId: 'u', name: 'Projeto Y')],
      ).toResumeData();
      expect(rd.awards, isNotEmpty);
      expect(rd.academicProjects, isNotEmpty);
    });

    test('projeto só-espaço é filtrado (não vira academicProject vazio)', () {
      final rd = const ProfileSnapshot(
        projects: [Project(id: 'p', userId: 'u', name: '   ')],
      ).toResumeData();
      expect(rd.academicProjects, isEmpty);
    });
  });

  // TEMPLATE REAL: renderiza o HTML de fato (seam PdfService.buildResumeHtmlForTest)
  // e verifica o CONTEÚDO produzido — não só o mapper.
  group('Templates reais — prêmio/projeto aparecem nos 5 templates', () {
    ProfileSnapshot awardSnap() => ProfileSnapshot(
      awards: [
        Award(
          id: 'a',
          userId: 'u',
          name: 'Bolsa Mérito FGV',
          date: DateTime(2023),
        ),
      ],
    );
    ProfileSnapshot projectSnap() => const ProfileSnapshot(
      projects: [
        Project(
          id: 'p',
          userId: 'u',
          name: 'App de Doações',
          description: 'Conectou 200 doadores a ONGs.',
        ),
      ],
    );
    ProfileSnapshot bothSnap() => ProfileSnapshot(
      awards: [
        Award(
          id: 'a',
          userId: 'u',
          name: 'Bolsa Mérito FGV',
          date: DateTime(2023),
        ),
      ],
      projects: const [Project(id: 'p', userId: 'u', name: 'App de Doações')],
    );

    for (final t in _kTemplates) {
      test('$t: prêmio único aparece + seção de prêmios', () {
        final html = PdfService.buildResumeHtmlForTest(
          null,
          awardSnap().toResumeData(),
          t,
        );
        expect(
          html,
          contains('Bolsa Mérito FGV'),
          reason: '$t deve renderizar o título do prêmio',
        );
        expect(
          html.toLowerCase(),
          contains('reconhecimentos'),
          reason: '$t deve ter a seção "Prêmios e Reconhecimentos"',
        );
      });

      test('$t: projeto único aparece', () {
        final html = PdfService.buildResumeHtmlForTest(
          null,
          projectSnap().toResumeData(),
          t,
        );
        expect(
          html,
          contains('App de Doações'),
          reason: '$t deve renderizar o título do projeto',
        );
      });

      test('$t: projeto + prêmio aparecem SIMULTANEAMENTE', () {
        final html = PdfService.buildResumeHtmlForTest(
          null,
          bothSnap().toResumeData(),
          t,
        );
        expect(
          html,
          contains('App de Doações'),
          reason: '$t: projeto some quando há prêmio',
        );
        expect(
          html,
          contains('Bolsa Mérito FGV'),
          reason: '$t: prêmio some quando há projeto',
        );
      });

      test('$t: prêmio só-whitespace NÃO gera seção vazia', () {
        final rd = ResumeData(
          awards: [
            ResumeAward(
              title: '  ',
              institution: '',
              date: '',
              description: '',
            ),
          ],
        );
        final html = PdfService.buildResumeHtmlForTest(null, rd, t);
        expect(
          html.toLowerCase(),
          isNot(contains('reconhecimentos')),
          reason: '$t: prêmio vazio não deve criar heading',
        );
      });
    }

    test('flag-independência do conteúdo: MESMO ResumeData → MESMO HTML', () {
      // O currículo geral renderiza sempre o ResumeData do snapshot canônico
      // (forceFallback); a flag templates_v2 não entra. Provamos que o conteúdo
      // é função só do ResumeData: render idêntico do mesmo objeto.
      final rd = bothSnap().toResumeData();
      for (final t in _kTemplates) {
        final a = PdfService.buildResumeHtmlForTest(null, rd, t);
        final b = PdfService.buildResumeHtmlForTest(null, rd, t);
        expect(a, b);
        expect(a, contains('App de Doações'));
        expect(a, contains('Bolsa Mérito FGV'));
      }
    });
  });

  // MATRIZ DE CONTRATO: cada um dos 9 grupos renderáveis do currículo geral
  // aparece em CADA um dos 5 templates (token textual único por grupo, tier
  // standard). Detecta um template que HABILITA o CV mas DESCARTA um grupo —
  // ex.: o summary-only no Forte que era gerado sem o resumo.
  group('Matriz de contrato — 9 grupos × 5 templates', () {
    // Um item por grupo, texto curto → tier standard (sem shrink adaptativo).
    final full = ResumeData(
      summary: 'ZXSUMMARY resumo profissional curto.',
      experiences: [
        ExperienceItem(
          role: 'ZXEXP',
          company: 'Empresa X',
          period: '2023',
          description: 'Fez algo.',
        ),
      ],
      education: [
        EducationItem(degree: 'Bacharel', institution: 'ZXEDU', period: '2024'),
      ],
      skills: const ['ZXSKILL'],
      languages: [ResumeLanguage(language: 'ZXLANG', level: 'Fluente')],
      courses: [ResumeCourse(title: 'ZXCERT', institution: '', period: '')],
      academicProjects: [
        ResumeProject(title: 'ZXPROJ', role: '', period: '', description: ''),
      ],
      awards: [
        ResumeAward(
          title: 'ZXAWARD',
          institution: '',
          date: '',
          description: '',
        ),
      ],
      interests: const ['ZXINTEREST'],
    );
    const groups = <String, String>{
      'summary': 'ZXSUMMARY',
      'experiences': 'ZXEXP',
      'education': 'ZXEDU',
      'skills': 'ZXSKILL',
      'languages': 'ZXLANG',
      'certifications/courses': 'ZXCERT',
      'projects': 'ZXPROJ',
      'awards': 'ZXAWARD',
      'interests': 'ZXINTEREST',
    };

    for (final t in _kTemplates) {
      test('$t renderiza os 9 grupos (nenhum descartado)', () {
        final html = PdfService.buildResumeHtmlForTest(null, full, t);
        groups.forEach((group, token) {
          expect(
            html,
            contains(token),
            reason: '$t habilitaria o CV mas DESCARTA o grupo "$group"',
          );
        });
      });
    }
  });

  // Edge cases de projeto (achados da revisão adversarial): coerência
  // predicate ↔ mapper ↔ prévia ↔ templates para projetos parciais.
  group('Projetos parciais — coerência predicate/mapper/prévia/PDF', () {
    test('projeto só-context (sem âncora primária) → NÃO conta', () {
      // context vira relevantWork, que só Harvard renderiza → sozinho geraria
      // um cabeçalho "Projetos" com entrada em branco nos outros 4. Não conta.
      const snap = ProfileSnapshot(
        projects: [
          Project(id: 'p', userId: 'u', name: '', context: 'Hackathon'),
        ],
      );
      expect(GeneralResumeExport.snapshotHasContent(snap), isFalse);
      expect(snap.toResumeData().academicProjects, isEmpty);
    });

    test('projeto só-context: NENHUM template mostra a seção/o texto', () {
      final rd = ResumeData(
        academicProjects: [
          ResumeProject(
            title: '',
            role: '',
            period: '',
            description: '',
            relevantWork: 'Hackathon',
          ),
        ],
      );
      for (final t in _kTemplates) {
        final html = PdfService.buildResumeHtmlForTest(null, rd, t);
        expect(
          html,
          isNot(contains('Hackathon')),
          reason: '$t: projeto só-relevantWork não deve renderizar',
        );
      }
    });

    test('projeto só-descrição (sem nome) → renderiza a descrição nos 5', () {
      final rd = const ProfileSnapshot(
        projects: [
          Project(
            id: 'p',
            userId: 'u',
            name: '',
            description: 'Conectou 200 doadores a ONGs.',
          ),
        ],
      ).toResumeData();
      expect(rd.academicProjects, isNotEmpty);
      for (final t in _kTemplates) {
        expect(
          PdfService.buildResumeHtmlForTest(null, rd, t),
          contains('Conectou 200 doadores a ONGs.'),
          reason: '$t deve renderizar a descrição do projeto sem nome',
        );
      }
    });

    test(
      'projectPreviewRow: título nunca vazio (cai pra bullet/descrição)',
      () {
        expect(
          projectPreviewRow(
            const Project(id: 'p', userId: 'u', name: 'App'),
          ).title,
          'App',
        );
        expect(
          projectPreviewRow(
            const Project(
              id: 'p',
              userId: 'u',
              name: '',
              description: 'Conectou 200 doadores',
            ),
          ).title,
          'Conectou 200 doadores',
        );
        expect(
          projectPreviewRow(
            const Project(
              id: 'p',
              userId: 'u',
              name: '',
              bullets: [
                ProjectBullet(id: 'b', projectId: 'p', text: 'Fez X e Y'),
              ],
            ),
          ).title,
          'Fez X e Y',
        );
      },
    );

    testWidgets('prévia: skill/idioma só-espaço NÃO vira chip/linha vazia', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GeneralResumePreviewBody(
              name: 'Ana',
              location: '',
              strengthPercent: 20,
              hubStatus: null,
              summary: 'x',
              skills: ['  ', 'Excel'],
              languages: [(name: '   ', level: 'Fluente')],
              experiences: [],
              education: [],
              interests: ['', 'Dados'],
            ),
          ),
        ),
      );
      // O item real aparece; o só-espaço não vira widget.
      expect(find.text('Excel'), findsOneWidget);
      expect(find.text('Dados'), findsOneWidget);
      expect(find.text('  '), findsNothing);
      // Idioma só-espaço → a seção Idiomas não renderiza (defesa).
      expect(find.text('IDIOMAS'), findsNothing);
    });
  });

  // Origem do ResumeRenderer (telemetria). decideSource é puro (sem Printing).
  group('ResumeRenderer.decideSource — origem correta', () {
    test(
      'forceFallback → canonicalProfileSnapshot (flag/perfil irrelevantes)',
      () {
        for (final flagOn in [true, false]) {
          for (final hasData in [true, false]) {
            expect(
              ResumeRenderer.decideSource(
                forceFallback: true,
                flagOn: flagOn,
                hasProfileData: hasData,
              ),
              ResumeRenderSource.canonicalProfileSnapshot,
            );
          }
        }
      },
    );

    test(
      'flag ON e OFF dão a MESMA origem quando forceFallback (invariância)',
      () {
        final on = ResumeRenderer.decideSource(
          forceFallback: true,
          flagOn: true,
          hasProfileData: true,
        );
        final off = ResumeRenderer.decideSource(
          forceFallback: true,
          flagOn: false,
          hasProfileData: false,
        );
        expect(on, off);
        expect(on, ResumeRenderSource.canonicalProfileSnapshot);
      },
    );

    test('sem forceFallback: flag OFF → v1FlagOff', () {
      expect(
        ResumeRenderer.decideSource(
          forceFallback: false,
          flagOn: false,
          hasProfileData: false,
        ),
        ResumeRenderSource.v1FlagOff,
      );
    });

    test('sem forceFallback: flag ON + perfil relacional → v2Relational', () {
      expect(
        ResumeRenderer.decideSource(
          forceFallback: false,
          flagOn: true,
          hasProfileData: true,
        ),
        ResumeRenderSource.v2Relational,
      );
    });

    test('sem forceFallback: flag ON + perfil vazio → v1LegacyFallback', () {
      expect(
        ResumeRenderer.decideSource(
          forceFallback: false,
          flagOn: true,
          hasProfileData: false,
        ),
        ResumeRenderSource.v1LegacyFallback,
      );
    });
  });

  group('loadGeneralResumeSnapshot — loader do currículo geral', () {
    test(
      'todas as consultas OK, sem dados → snapshot vazio (sucesso)',
      () async {
        final svc = ProfileSnapshotService(repository: _FakeRepo());
        final snap = await svc.loadGeneralResumeSnapshot('u');
        expect(GeneralResumeExport.snapshotHasContent(snap), isFalse);
      },
    );
    test('falha de UMA fonte USADA (getSkills) → propaga', () async {
      final svc = ProfileSnapshotService(
        repository: _FakeRepo(failing: {'getSkills'}),
      );
      expect(
        () => svc.loadGeneralResumeSnapshot('u'),
        throwsA(isA<StateError>()),
      );
    });
    test('falha TOTAL → propaga', () async {
      final svc = ProfileSnapshotService(
        repository: _FakeRepo(
          failing: {
            'getPersonal',
            'getExperiences',
            'getEducation',
            'getSkills',
            'getLanguages',
            'getCertifications',
            'getProjects',
            'getInterests',
            'getAwards',
          },
        ),
      );
      expect(
        () => svc.loadGeneralResumeSnapshot('u'),
        throwsA(isA<StateError>()),
      );
    });
    test(
      'falha SÓ em coursework (fonte de fora) → NÃO propaga, carrega',
      () async {
        final svc = ProfileSnapshotService(
          repository: _FakeRepo(
            skills: [Skill(id: 's', userId: 'u', name: 'Excel')],
            failing: {'getCoursework'},
          ),
        );
        final snap = await svc.loadGeneralResumeSnapshot('u');
        expect(GeneralResumeExport.snapshotHasContent(snap), isTrue);
        expect(snap.coursework, isEmpty);
      },
    );
    test('sucesso completo (com dados) → snapshot com conteúdo', () async {
      final svc = ProfileSnapshotService(
        repository: _FakeRepo(
          skills: [Skill(id: 's', userId: 'u', name: 'Excel')],
        ),
      );
      final snap = await svc.loadGeneralResumeSnapshot('u');
      expect(GeneralResumeExport.snapshotHasContent(snap), isTrue);
      expect(snap.skills.map((s) => s.name), contains('Excel'));
    });

    // Wiring REAL de produção: runExport + loader real.
    test(
      'wiring: falha de fonte USADA → failed sem emitPdf/onExported',
      () async {
        final svc = ProfileSnapshotService(
          repository: _FakeRepo(failing: {'getSkills'}),
        );
        var emit = 0, exported = 0;
        final r = await GeneralResumeExport.runExport(
          uid: 'u',
          loadSnapshot: (id) => svc.loadGeneralResumeSnapshot(id),
          emitPdf: (_) async => emit++,
          onExported: () => exported++,
        );
        expect(r, AssistExportOutcome.failed);
        expect(emit, 0);
        expect(exported, 0);
      },
    );
    test('wiring: falha SÓ em coursework → NÃO bloqueia (ok)', () async {
      final svc = ProfileSnapshotService(
        repository: _FakeRepo(
          skills: [Skill(id: 's', userId: 'u', name: 'Excel')],
          failing: {'getCoursework'},
        ),
      );
      var emit = 0, exported = 0;
      final r = await GeneralResumeExport.runExport(
        uid: 'u',
        loadSnapshot: (id) => svc.loadGeneralResumeSnapshot(id),
        emitPdf: (_) async => emit++,
        onExported: () => exported++,
      );
      expect(r, AssistExportOutcome.ok);
      expect(emit, 1);
      expect(exported, 1);
    });
    test('wiring: loader real OK mas vazio → empty', () async {
      final svc = ProfileSnapshotService(repository: _FakeRepo());
      var emit = 0;
      final r = await GeneralResumeExport.runExport(
        uid: 'u',
        loadSnapshot: (id) => svc.loadGeneralResumeSnapshot(id),
        emitPdf: (_) async => emit++,
        onExported: () {},
      );
      expect(r, AssistExportOutcome.empty);
      expect(emit, 0);
    });
  });

  group('runExport — empty/failed/ok + concorrência', () {
    test('uid null → failed; sem emitPdf/onExported', () async {
      var emit = 0, exported = 0;
      final r = await GeneralResumeExport.runExport(
        uid: null,
        loadSnapshot: (_) async => _oneSkill(),
        emitPdf: (_) async => emit++,
        onExported: () => exported++,
      );
      expect(r, AssistExportOutcome.failed);
      expect(emit, 0);
      expect(exported, 0);
    });
    test('sucesso → emitPdf 1× + onExported 1× → ok', () async {
      var emit = 0, exported = 0;
      final r = await GeneralResumeExport.runExport(
        uid: 'u',
        loadSnapshot: (_) async => _oneSkill(),
        emitPdf: (_) async => emit++,
        onExported: () => exported++,
      );
      expect(r, AssistExportOutcome.ok);
      expect(emit, 1);
      expect(exported, 1);
    });
    test(
      'emitPdf lança (folha não abriu) → failed; onExported NÃO chamado',
      () async {
        var exported = 0;
        final r = await GeneralResumeExport.runExport(
          uid: 'u',
          loadSnapshot: (_) async => _oneSkill(),
          emitPdf: (_) async => throw Exception('cancel'),
          onExported: () => exported++,
        );
        expect(r, AssistExportOutcome.failed);
        expect(exported, 0);
      },
    );
    test(
      'concorrência: 2º export durante o 1º → failed; _busy reseta',
      () async {
        final gate = Completer<void>();
        final first = GeneralResumeExport.runExport(
          uid: 'u',
          loadSnapshot: (_) async => _oneSkill(),
          emitPdf: (_) async => gate.future,
          onExported: () {},
        );
        await Future<void>.delayed(Duration.zero);
        expect(GeneralResumeExport.isBusy, isTrue);
        final second = await GeneralResumeExport.runExport(
          uid: 'u',
          loadSnapshot: (_) async => _oneSkill(),
          emitPdf: (_) async {},
          onExported: () {},
        );
        expect(second, AssistExportOutcome.failed);
        gate.complete();
        expect(await first, AssistExportOutcome.ok);
        expect(GeneralResumeExport.isBusy, isFalse);
      },
    );
  });

  group('GeneralResumeCardView', () {
    testWidgets('com dados: Ver prévia + Exportar PDF', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: GeneralResumeCardView(hasContent: true)),
        ),
      );
      expect(find.text('Currículo geral'), findsOneWidget);
      expect(find.text('Ver prévia'), findsOneWidget);
      expect(find.text('Exportar PDF'), findsOneWidget);
      expect(find.text('Completar perfil'), findsNothing);
    });

    testWidgets('sem dados: "Completar perfil"', (tester) async {
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeneralResumeCardView(
              hasContent: false,
              onCompleteProfile: () => completed = true,
            ),
          ),
        ),
      );
      expect(
        find.text('Complete seus Dados para gerar seu currículo.'),
        findsOneWidget,
      );
      expect(find.text('Completar perfil'), findsOneWidget);
      expect(find.text('Ver prévia'), findsNothing);
      await tester.tap(find.text('Completar perfil'));
      expect(completed, isTrue);
    });

    testWidgets('carregando: skeleton, sem falso "Complete seus Dados"', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GeneralResumeCardView(hasContent: false, isLoading: true),
          ),
        ),
      );
      expect(find.text('Carregando seu perfil…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        find.text('Complete seus Dados para gerar seu currículo.'),
        findsNothing,
      );
    });

    // Branch COMPACTA (empilha): 320/360/390dp.
    for (final w in [320.0, 360.0, 390.0]) {
      testWidgets('compacto ${w.toInt()}dp: sem overflow', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: w,
                  child: const GeneralResumeCardView(hasContent: true),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Currículo geral'), findsOneWidget);
        expect(find.text('Gerado do perfil'), findsOneWidget);
      });
    }

    // Branch ROW (lado a lado): larguras acima do threshold 440.
    for (final w in [500.0, 560.0]) {
      testWidgets('Row ${w.toInt()}dp: sem overflow', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: w,
                  child: const GeneralResumeCardView(hasContent: true),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Ver prévia'), findsOneWidget);
        expect(find.text('Exportar PDF'), findsOneWidget);
      });
    }
  });

  group('GeneralResumePreviewBody — coerência com o PDF', () {
    testWidgets('só summary → mostra Resumo, NÃO empty state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GeneralResumePreviewBody(
              name: 'Ana',
              location: '',
              strengthPercent: 20,
              hubStatus: null,
              summary: 'Estudante focada em dados.',
              skills: [],
              languages: [],
              experiences: [],
              education: [],
              interests: [],
            ),
          ),
        ),
      );
      expect(find.text('Estudante focada em dados.'), findsOneWidget);
      expect(find.text('Seu currículo aparece aqui'), findsNothing);
    });

    testWidgets('só prêmio → mostra Prêmios, NÃO empty state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GeneralResumePreviewBody(
              name: 'Ana',
              location: '',
              strengthPercent: 20,
              hubStatus: null,
              skills: [],
              languages: [],
              experiences: [],
              education: [],
              awards: ['1º lugar hackathon'],
              interests: [],
            ),
          ),
        ),
      );
      expect(find.text('1º lugar hackathon'), findsOneWidget);
      expect(find.text('Seu currículo aparece aqui'), findsNothing);
    });

    testWidgets('só projeto → mostra Projetos, NÃO empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GeneralResumePreviewBody(
              name: 'Ana',
              location: '',
              strengthPercent: 20,
              hubStatus: null,
              skills: [],
              languages: [],
              experiences: [],
              education: [],
              projects: [(title: 'App de Doações', subtitle: 'Fundadora')],
              interests: [],
            ),
          ),
        ),
      );
      expect(find.text('Projetos'.toUpperCase()), findsOneWidget);
      expect(find.text('App de Doações'), findsOneWidget);
      expect(find.text('Seu currículo aparece aqui'), findsNothing);
    });

    testWidgets('perfil vazio → empty state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GeneralResumePreviewBody(
              name: '',
              location: '',
              strengthPercent: 0,
              hubStatus: null,
              skills: [],
              languages: [],
              experiences: [],
              education: [],
              interests: [],
            ),
          ),
        ),
      );
      expect(find.text('Seu currículo aparece aqui'), findsOneWidget);
    });
  });

  group('AssistantTabLayout — gating flag ON/OFF', () {
    Widget build({required bool assistEnabled}) => MaterialApp(
      home: Scaffold(
        body: AssistantTabLayout(
          assistEnabled: assistEnabled,
          keyboardOpen: false,
          assistantTopBar: (_) => const Text('Ver meu perfil'),
          legacyTopBar: (_) => CurriculoToggle(index: 0, onChanged: (_) {}),
          conversa: (_) => const Text('CONVERSA'),
          preview: (_) => const Text('PREVIEW'),
          tabIndex: 0,
        ),
      ),
    );

    testWidgets('ON: conversa única, sem CurriculoToggle nem IndexedStack', (
      tester,
    ) async {
      await tester.pumpWidget(build(assistEnabled: true));
      expect(find.byType(CurriculoToggle), findsNothing);
      expect(find.byType(IndexedStack), findsNothing);
      expect(find.text('Ver meu perfil'), findsOneWidget);
      expect(find.text('CONVERSA'), findsOneWidget);
    });

    testWidgets('OFF: shell legado com toggle + IndexedStack', (tester) async {
      await tester.pumpWidget(build(assistEnabled: false));
      expect(find.byType(CurriculoToggle), findsOneWidget);
      expect(find.byType(IndexedStack), findsOneWidget);
      expect(find.text('Ver meu perfil'), findsNothing);
    });
  });
}
