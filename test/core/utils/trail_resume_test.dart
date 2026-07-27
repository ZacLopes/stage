import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/core/utils/trail_resume.dart';
import 'package:career_gamification/data/models/models.dart';
import 'package:career_gamification/features/resume/resume_viewmodel.dart';

/// Bloqueador B do device-test de 24/07.
///
/// `_isEditable` (resume_detail_screen) passou a depender de
/// `source == SavedResumeSource.trail`, mas 'trail' só existe depois da
/// migration `20260722120000`, que pela ordem de release (caminho A) sobe
/// DEPOIS do app. Sem tolerância, 91 documentos de 87 usuários perdem
/// "Editar texto", "Regerar com IA" e "Exportar PDF" — sem flag para desligar.
void main() {
  group('isTrailResume — tipo estrutural (pós-backfill)', () {
    test('source=trail é editável, independente do título', () {
      expect(
        isTrailResume(source: SavedResumeSource.trail, title: 'Qualquer coisa'),
        isTrue,
      );
    });

    test('source=trail com título vazio continua editável', () {
      expect(
        isTrailResume(source: SavedResumeSource.trail, title: ''),
        isTrue,
      );
    });
  });

  group('isTrailResume — ponte legada (banco ainda sem a migration)', () {
    // ALARME DA DÍVIDA DATADA: quando o backfill rodar em produção
    // (`select count(*) from saved_resumes where source='trail'` == 91),
    // este teste pode ser removido junto com o 2º ramo do predicado.
    test('manual + prefixo do título é editável', () {
      expect(
        isTrailResume(
          source: SavedResumeSource.manual,
          title: 'Currículo Stage',
        ),
        isTrue,
      );
    });

    test('manual + prefixo com sufixo de desambiguação é editável', () {
      // resolveUniqueTitle gera "Currículo Stage (2)", "(3)"...
      expect(
        isTrailResume(
          source: SavedResumeSource.manual,
          title: 'Currículo Stage (2)',
        ),
        isTrue,
      );
    });

    test('manual SEM o prefixo não é editável', () {
      expect(
        isTrailResume(
          source: SavedResumeSource.manual,
          title: 'Meu Currículo',
        ),
        isFalse,
      );
    });

    test('o prefixo é lido do mesmo literal que o writer usa', () {
      // Se alguém mudar o título gerado sem mudar o predicado (ou vice-versa),
      // a ponte legada silenciosamente para de casar. Uma fonte, um teste.
      expect(ResumeViewModel.kTrailResumeBaseTitle, kTrailResumeTitlePrefix);
      expect(
        isTrailResume(
          source: SavedResumeSource.manual,
          title: ResumeViewModel.kTrailResumeBaseTitle,
        ),
        isTrue,
      );
    });
  });

  group('isTrailResume — o ramo legado NÃO vaza para outros tipos', () {
    // Medido em prod (26/07): o prefixo 'Currículo Stage' só existe em linhas
    // `manual` (91 linhas / 87 usuários; zero em imported/adapted). Restringir
    // o OR a `manual` impede que um documento de outro tipo com esse título
    // vire editável — o que exporia editar/regerar sobre uma FONTE ou sobre um
    // snapshot de saída.
    test('imported com o prefixo NÃO é editável', () {
      expect(
        isTrailResume(
          source: SavedResumeSource.imported,
          title: 'Currículo Stage',
        ),
        isFalse,
      );
    });

    test('adapted com o prefixo NÃO é editável', () {
      expect(
        isTrailResume(
          source: SavedResumeSource.adapted,
          title: 'Currículo Stage',
        ),
        isFalse,
      );
    });

    test('general com o prefixo NÃO é editável', () {
      // Snapshot de saída (regra de domínio 9): não realimenta o perfil.
      expect(
        isTrailResume(
          source: SavedResumeSource.general,
          title: 'Currículo Stage',
        ),
        isFalse,
      );
    });
  });

  group('isTrailResume — paridade com o comportamento de produção HOJE', () {
    // O predicado antigo era `title.startsWith(kTrailResumeBaseTitle)`.
    // Como em prod o prefixo só existe em linhas `manual`, o predicado novo
    // precisa dar o MESMO resultado para todas as linhas reais de hoje.
    test('reproduz o predicado antigo para as linhas que existem em prod', () {
      final linhasReaisDeProd = <(SavedResumeSource, String, bool)>[
        // (source, title, editável no app de hoje)
        (SavedResumeSource.manual, 'Currículo Stage', true),
        (SavedResumeSource.manual, 'Currículo Stage (2)', true),
        (SavedResumeSource.manual, 'Meu Currículo', false),
        (SavedResumeSource.imported, 'cv_maria.pdf', false),
        (SavedResumeSource.adapted, 'CV adaptado - Dev - Nubank', false),
      ];

      for (final (source, title, esperado) in linhasReaisDeProd) {
        expect(
          isTrailResume(source: source, title: title),
          esperado,
          reason: 'source=$source title="$title"',
        );
        // E confere contra o predicado antigo, literalmente.
        final predicadoAntigo =
            title.startsWith(ResumeViewModel.kTrailResumeBaseTitle);
        expect(
          isTrailResume(source: source, title: title),
          predicadoAntigo,
          reason: 'divergiu do predicado antigo em source=$source "$title"',
        );
      }
    });
  });
}
