import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/application.dart';
import 'package:career_gamification/features/jobs/utils/tracker_navigation.dart';

/// C1 do device-test (24/07): a aba Candidaturas nunca reposicionava o usuário.
/// Adicionar uma candidatura ou mudar um status deixava a pessoa olhando uma
/// tela vazia com o item a um toque de distância.
void main() {
  group('segmentForApplication — uma regra só', () {
    test('submitted → Enviadas', () {
      expect(segmentForApplication(ApplicationStatus.submitted),
          ApplicationSegment.enviadas);
    });

    test('os status de andamento → Em processo', () {
      for (final s in [
        ApplicationStatus.inReview,
        ApplicationStatus.shortlisted,
        ApplicationStatus.interview,
        ApplicationStatus.offer,
      ]) {
        expect(segmentForApplication(s), ApplicationSegment.emProcesso,
            reason: '$s');
      }
    });

    test('os status terminais → Finalizadas', () {
      for (final s in [
        ApplicationStatus.hired,
        ApplicationStatus.rejected,
        ApplicationStatus.withdrawn,
        ApplicationStatus.expired,
      ]) {
        expect(segmentForApplication(s), ApplicationSegment.finalizadas,
            reason: '$s');
      }
    });

    // Este teste mira `segmentForStatus`, NÃO o wrapper — de propósito.
    //
    // Afirmar que `segmentForApplication` nunca devolve `salvas` seria
    // tautológico: ele converte `salvas` em `enviadas` na última linha, então a
    // asserção passaria mesmo com a regra de baixo quebrada. O que realmente
    // pode mudar é o mapa base; se alguém acrescentar um status que caia em
    // `salvas`, é AQUI que precisa aparecer — e o guard do wrapper deixa de
    // ser decorativo e passa a ser o que segura a UI.
    test('hoje nenhum status do mapa BASE cai em Salvas (o guard é reserva)',
        () {
      for (final s in ApplicationStatus.values) {
        expect(segmentForStatus(s), isNot(ApplicationSegment.salvas),
            reason: '$s');
      }
    });

    test('se o mapa base devolvesse Salvas, o wrapper converteria', () {
      // Prova DIRETA do guard, com o mapa base injetado.
      //
      // A versão anterior deste teste iterava os status reais e afirmava
      // `isNot(salvas)` — o que passava com o guard DELETADO, porque quem
      // garante o resultado ali é o mapa base (provado no teste acima), não a
      // conversão. Confirmado por mutação em 27/07: trocar o corpo do wrapper
      // por `return seg;` mantinha os 13 testes verdes.
      ApplicationSegment tudoSalvas(ApplicationStatus _) =>
          ApplicationSegment.salvas;

      for (final s in ApplicationStatus.values) {
        expect(segmentForApplication(s, base: tudoSalvas),
            ApplicationSegment.enviadas,
            reason: '$s');
      }
    });

    test('o guard só toca em Salvas — os outros segmentos passam intactos', () {
      for (final alvo in [
        ApplicationSegment.enviadas,
        ApplicationSegment.emProcesso,
        ApplicationSegment.finalizadas,
      ]) {
        expect(
          segmentForApplication(ApplicationStatus.submitted,
              base: (_) => alvo),
          alvo,
          reason: '$alvo',
        );
      }
    });
  });

  group('nextSegmentAfterAction — nunca deixa numa tela vazia', () {
    test('o cenário exato do device-test: adicionar estando em Salvas vazia',
        () {
      // A pessoa está em "Salvas" (vazia), adiciona uma candidatura que nasce
      // em Enviadas. Antes: continuava em Salvas lendo "Nenhuma vaga salva
      // ainda" logo após cadastrar algo.
      expect(
        nextSegmentAfterAction(
          current: ApplicationSegment.salvas,
          startedAt: ApplicationSegment.salvas,
          destination: ApplicationSegment.enviadas,
          currentBecomesEmpty: true,
          isCreation: true,
        ),
        ApplicationSegment.enviadas,
      );
    });

    test('o segundo cenário: mudar status esvaziando o segmento atual', () {
      // Em "Enviadas" com só um item, muda para Entrevista → Em processo.
      // Antes: ficava em Enviadas lendo "Nenhuma candidatura enviada ainda".
      expect(
        nextSegmentAfterAction(
          current: ApplicationSegment.enviadas,
          startedAt: ApplicationSegment.enviadas,
          destination: ApplicationSegment.emProcesso,
          currentBecomesEmpty: true,
          isCreation: false,
        ),
        ApplicationSegment.emProcesso,
      );
    });

    test('trabalho em LOTE não é interrompido: sobrou item, fica onde está',
        () {
      // Cinco itens em Enviadas, move um. A pessoa segue tratando os outros.
      expect(
        nextSegmentAfterAction(
          current: ApplicationSegment.enviadas,
          startedAt: ApplicationSegment.enviadas,
          destination: ApplicationSegment.emProcesso,
          currentBecomesEmpty: false,
          isCreation: false,
        ),
        isNull,
      );
    });

    test('CRIAÇÃO sempre segue, mesmo com o segmento atual populado', () {
      // Quem acabou de cadastrar quer ver o que cadastrou.
      expect(
        nextSegmentAfterAction(
          current: ApplicationSegment.salvas,
          startedAt: ApplicationSegment.salvas,
          destination: ApplicationSegment.enviadas,
          currentBecomesEmpty: false,
          isCreation: true,
        ),
        ApplicationSegment.enviadas,
      );
    });

    test('destino IGUAL ao atual nunca pula (evita setState inútil)', () {
      for (final creation in [true, false]) {
        for (final empty in [true, false]) {
          expect(
            nextSegmentAfterAction(
              current: ApplicationSegment.emProcesso,
              startedAt: ApplicationSegment.emProcesso,
              destination: ApplicationSegment.emProcesso,
              currentBecomesEmpty: empty,
              isCreation: creation,
            ),
            isNull,
            reason: 'creation=$creation empty=$empty',
          );
        }
      }
    });

    test('a matriz completa das quatro combinações', () {
      const cur = ApplicationSegment.salvas;
      const dest = ApplicationSegment.finalizadas;
      // (isCreation, currentBecomesEmpty) → pula?
      expect(
          nextSegmentAfterAction(
              current: cur,
              startedAt: cur,
              destination: dest,
              isCreation: true,
              currentBecomesEmpty: true),
          dest);
      expect(
          nextSegmentAfterAction(
              current: cur,
              startedAt: cur,
              destination: dest,
              isCreation: true,
              currentBecomesEmpty: false),
          dest);
      expect(
          nextSegmentAfterAction(
              current: cur,
              startedAt: cur,
              destination: dest,
              isCreation: false,
              currentBecomesEmpty: true),
          dest);
      expect(
          nextSegmentAfterAction(
              current: cur,
              startedAt: cur,
              destination: dest,
              isCreation: false,
              currentBecomesEmpty: false),
          isNull);
    });

    test('quem navegou durante o request não é arrancado de onde escolheu', () {
      // A pessoa toca "Já me candidatei", e enquanto o request está no ar
      // troca de pílula com a mão. Quando a resposta chega, mandá-la para o
      // destino seria desfazer a escolha que ela acabou de fazer.
      //
      // O caso é montado no cenário MAIS forte possível: criação (que sempre
      // segue) com o segmento atual vazio (que também sempre segue). Se o
      // guard não existisse, este teste devolveria `dest`.
      expect(
        nextSegmentAfterAction(
          current: ApplicationSegment.finalizadas, // ela se moveu pra cá
          startedAt: ApplicationSegment.salvas, // disparou daqui
          destination: ApplicationSegment.enviadas,
          currentBecomesEmpty: true,
          isCreation: true,
        ),
        isNull,
      );
    });

    test('o guard vale para mudança de status também', () {
      expect(
        nextSegmentAfterAction(
          current: ApplicationSegment.salvas,
          startedAt: ApplicationSegment.enviadas,
          destination: ApplicationSegment.emProcesso,
          currentBecomesEmpty: true,
          isCreation: false,
        ),
        isNull,
      );
    });

    test('se ela voltou sozinha ao segmento de origem, o pulo volta a valer',
        () {
      // `startedAt` compara SEGMENTO, não identidade de toque: ir para outra
      // pílula e voltar deixa a pessoa exatamente onde a ação começou, e aí
      // não há escolha dela para preservar.
      expect(
        nextSegmentAfterAction(
          current: ApplicationSegment.salvas,
          startedAt: ApplicationSegment.salvas,
          destination: ApplicationSegment.enviadas,
          currentBecomesEmpty: true,
          isCreation: false,
        ),
        ApplicationSegment.enviadas,
      );
    });
  });

  group('hoistToTop — a recém-criada não nasce fora da tela', () {
    test('traz do meio para o topo', () {
      final l = ['a', 'b', 'alvo', 'c'];
      hoistToTop(l, (x) => x == 'alvo');
      expect(l, ['alvo', 'a', 'b', 'c']);
    });

    test('traz do FIM para o topo — o caso real da candidatura nova', () {
      // As manuais entram depois de todos os cards de vaga; num segmento cheio
      // a nova é literalmente a última.
      final l = ['vaga1', 'vaga2', 'vaga3', 'nova'];
      hoistToTop(l, (x) => x == 'nova');
      expect(l.first, 'nova');
      expect(l, ['nova', 'vaga1', 'vaga2', 'vaga3'],
          reason: 'a ordem relativa do resto tem que ser preservada');
    });

    test('já no topo: não mexe (nem reordena o resto)', () {
      final l = ['alvo', 'a', 'b'];
      hoistToTop(l, (x) => x == 'alvo');
      expect(l, ['alvo', 'a', 'b']);
    });

    test('alvo ausente: lista intacta', () {
      final l = ['a', 'b', 'c'];
      hoistToTop(l, (x) => x == 'nao-existe');
      expect(l, ['a', 'b', 'c']);
    });

    test('lista vazia não estoura', () {
      final l = <String>[];
      hoistToTop(l, (x) => true);
      expect(l, isEmpty);
    });

    test('com alvos repetidos, iça o primeiro e só ele', () {
      final l = ['a', 'alvo', 'b', 'alvo'];
      hoistToTop(l, (x) => x == 'alvo');
      expect(l, ['alvo', 'a', 'b', 'alvo']);
    });
  });

  group('C5 — rótulo do tipo, não o valor de banco', () {
    test('nenhum rótulo expõe o valor técnico', () {
      for (final t in ApplicationType.values) {
        expect(t.label, isNot(t.db), reason: '$t');
        expect(t.label.trim(), isNotEmpty, reason: '$t');
        // Nada de minúscula-de-jargão solta.
        expect(t.label, isNot('manual'));
      }
    });

    test('manual lê como algo que a pessoa fez', () {
      expect(ApplicationType.manual.label, 'Adicionada por você');
      // O valor de banco continua intacto — só a exibição mudou.
      expect(ApplicationType.manual.db, 'manual');
    });
  });
}
