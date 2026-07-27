import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/application.dart';
import 'package:career_gamification/features/jobs/widgets/tracker_segment_bar.dart';

/// C4 do device-test + achados do review de 27/07.
///
/// Os testes existentes rodavam só na superfície padrão do flutter_test
/// (800x600), o que deixava a máquina de estado nova — ScrollController,
/// `_canScrollRight`, ShaderMask, reveal do segmento — praticamente sem
/// cobertura. Aqui a superfície é EXPLÍCITA nos dois extremos.
///
/// Medido ao escrever: com contagens de 2 dígitos, 800px NÃO comporta as 4
/// pílulas (sobram ~23px de overflow) — por isso o caso "cabe tudo" força
/// 1200px em vez de confiar no padrão.
void main() {
  Widget host(
    ApplicationSegment selected, {
    ValueChanged<ApplicationSegment>? onSelected,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: TrackerSegmentBar(
            selected: selected,
            counts: const {
              ApplicationSegment.salvas: 12,
              ApplicationSegment.enviadas: 34,
              ApplicationSegment.emProcesso: 56,
              ApplicationSegment.finalizadas: 78,
            },
            onSelected: onSelected ?? (_) {},
          ),
        ),
      );

  Future<void> narrow(WidgetTester tester) async {
    // Estreita o suficiente para as 4 pílulas NÃO caberem.
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('em tela estreita a régua É rolável (o ramo com fade existe)',
      (tester) async {
    await narrow(tester);
    await tester.pumpWidget(host(ApplicationSegment.salvas));
    await tester.pumpAndSettle();

    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable).first);
    expect(scrollable.controller!.position.maxScrollExtent, greaterThan(0),
        reason: 'o teste precisa de overflow para valer alguma coisa');
  });

  testWidgets('rolar até a borda NÃO reseta a posição', (tester) async {
    // Regressão do review: o ShaderMask era aplicado condicionalmente, o que
    // trocava o TIPO do widget no slot, re-inflava a ListView e zerava o
    // scroll exatamente quando o usuário chegava à direita.
    await narrow(tester);
    await tester.pumpWidget(host(ApplicationSegment.salvas));
    await tester.pumpAndSettle();

    final controller =
        tester.widget<Scrollable>(find.byType(Scrollable).first).controller!;

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    // O invariante é "continua no fim", medido contra o extent VIGENTE — o
    // rebuild disparado por `_canScrollRight` pode reflowar a barra, então
    // comparar com um extent capturado antes seria frágil.
    final pos = controller.position;
    expect(pos.pixels, greaterThan(0),
        reason: 'a régua voltou ao começo ao chegar na borda');
    expect(pos.pixels, moreOrLessEquals(pos.maxScrollExtent, epsilon: 1.0),
        reason: 'a régua não ficou no fim');
  });

  testWidgets('o ShaderMask está SEMPRE presente — a árvore não troca de tipo',
      (tester) async {
    // É isto que impede o reset: o que muda é o gradiente, não o widget.
    await narrow(tester);
    await tester.pumpWidget(host(ApplicationSegment.salvas));
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsOneWidget);

    final controller =
        tester.widget<Scrollable>(find.byType(Scrollable).first).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('tela larga: tudo cabe, nada rola, nada quebra', (tester) async {
    // 800x600 (padrão do flutter_test) NÃO comporta as 4 pílulas com contagens
    // de 2 dígitos — sobram ~23px. Medido ao escrever este teste; por isso a
    // superfície larga é explícita, em vez de assumida.
    await tester.binding.setSurfaceSize(const Size(1200, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(ApplicationSegment.salvas));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<Scrollable>(find.byType(Scrollable).first).controller!;
    expect(controller.position.maxScrollExtent, 0);
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trocar o segmento por FORA (sem toque) traz a pílula à vista',
      (tester) async {
    // O C1 reposiciona a aba sozinho. Sem o reveal, o filtro ativo podia ficar
    // fora da viewport e a tela parecia mudar sem explicação.
    await narrow(tester);
    await tester.pumpWidget(host(ApplicationSegment.salvas));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<Scrollable>(find.byType(Scrollable).first).controller!;
    expect(controller.position.pixels, 0);

    // A pílula do último segmento começa FORA da vista — sem isso o teste não
    // teria o que provar. "Fora da vista" tem duas formas: a ListView é
    // preguiçosa, então além do cacheExtent a pílula sequer existe na árvore;
    // logo depois dele ela existe mas transborda à direita. As duas contam.
    final viewport = tester.getRect(find.byType(TrackerSegmentBar));
    final alvo = find.text('Finalizadas');
    final foraDaVista = alvo.evaluate().isEmpty ||
        tester.getRect(alvo).right > viewport.right + 0.5;
    expect(foraDaVista, isTrue,
        reason: 'a superfície precisa ser estreita o bastante para esconder');

    await tester.pumpWidget(host(ApplicationSegment.finalizadas));
    await tester.pumpAndSettle();

    expect(alvo, findsOneWidget,
        reason: 'a pílula selecionada nem chegou a ser construída');

    // O que o nome promete é VISIBILIDADE, não `pixels > 0`: a versão anterior
    // deste teste só afirmava que a régua se mexeu, então a matemática de
    // `_revealSelected` podia parar antes ou passar do alvo sem ninguém notar.
    final pill = tester.getRect(alvo);
    expect(pill.left, greaterThanOrEqualTo(viewport.left - 0.5),
        reason: 'a pílula selecionada ficou cortada à esquerda');
    expect(pill.right, lessThanOrEqualTo(viewport.right + 0.5),
        reason: 'a pílula selecionada continuou fora da viewport à direita');
  });

  testWidgets('dispose realmente descarta o ScrollController', (tester) async {
    // A versão anterior só fazia `expect(takeException(), isNull)` depois de
    // desmontar — e um controller VAZADO não lança nada com leak-tracking
    // desligado (o padrão). Medido por mutação em 27/07: esvaziar o `dispose()`
    // inteiro mantinha o teste verde.
    await narrow(tester);
    await tester.pumpWidget(host(ApplicationSegment.salvas));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<Scrollable>(find.byType(Scrollable).first).controller!;

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pumpAndSettle();

    // Um ChangeNotifier descartado rejeita novos listeners — é isto que
    // distingue "foi descartado" de "só saiu da árvore".
    expect(() => controller.addListener(() {}), throwsFlutterError);
    expect(tester.takeException(), isNull);
  });

  group('fadeStops — o esmaecimento em si (C4)', () {
    // O `ui.Shader` é opaco e o ShaderMask é incondicional de propósito, então
    // nenhuma asserção de árvore consegue ver o gradiente. Estes testes miram a
    // função pura, que é onde a decisão do C4 realmente mora.
    test('com conteúdo à direita, ALGO é esmaecido', () {
      final s = fadeStops(canScrollRight: true);
      expect(s.last, 1.0);
      expect(s[1], lessThan(1.0),
          reason: 'sem faixa entre o meio e o fim não há desvanecimento algum');
    });

    test('sem conteúdo à direita, a régua fica 100% opaca', () {
      final s = fadeStops(canScrollRight: false);
      expect(s[1], 1.0,
          reason: 'a transição cairia dentro do retângulo e esmaecia à toa');
    });

    test('os dois ramos DIFEREM — igualá-los ressuscita o C4', () {
      expect(fadeStops(canScrollRight: true),
          isNot(fadeStops(canScrollRight: false)));
    });

    test('são stops válidos: crescentes e dentro de [0,1]', () {
      for (final can in [true, false]) {
        final s = fadeStops(canScrollRight: can);
        expect(s.first, 0.0, reason: '$can');
        expect(s.length, 3, reason: 'o gradiente tem 3 cores');
        for (var i = 1; i < s.length; i++) {
          expect(s[i], greaterThanOrEqualTo(s[i - 1]), reason: '$can em $i');
        }
        expect(s.every((v) => v >= 0.0 && v <= 1.0), isTrue, reason: '$can');
      }
    });
  });
}
