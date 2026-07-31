import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/application.dart';
import 'package:career_gamification/features/jobs/widgets/tracker_segment_bar.dart';

/// Revisão UX 28/07, achado P3-31 — "a régua de segmentos corta 'Finaliza…'".
///
/// O relatório dava duas causas e uma delas era falsa: o esmaecimento da borda
/// direita JÁ existia desde 27/07 (C4 do device-test). O que restava era saber
/// se, na tela mais estreita que o app suporta e com a fonte de acessibilidade
/// no talo, a régua ainda se comporta como conteúdo que continua — e não como
/// layout quebrado.
///
/// É o que este arquivo mede. Ele não substitui olhar a tela; substitui
/// *lembrar* de olhar, que é o que falhou da primeira vez.
void main() {
  /// iPhone SE de pé: a menor largura que o app suporta.
  const larguraEstreita = 320.0;

  Future<void> pump(
    WidgetTester tester, {
    required double largura,
    required double escala,
  }) async {
    tester.view.physicalSize = Size(largura, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(escala)),
        child: const MaterialApp(
          home: Scaffold(
            body: TrackerSegmentBar(
              selected: ApplicationSegment.salvas,
              counts: {
                ApplicationSegment.salvas: 3,
                ApplicationSegment.enviadas: 2,
                ApplicationSegment.emProcesso: 4,
                ApplicationSegment.finalizadas: 1,
              },
              onSelected: _naoUsado,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('320pt + fonte de acessibilidade: não estoura o layout', (
    tester,
  ) async {
    // `accessibility-extra-large` do iOS ≈ 2.0× — a mesma condição do
    // `xcrun simctl ui content_size accessibility-extra-large` do relatório.
    await pump(tester, largura: larguraEstreita, escala: 2.0);

    // Overflow no Flutter vira exceção capturável. Se a régua estourar, aqui
    // aparece o "A RenderFlex overflowed by N pixels".
    expect(tester.takeException(), isNull);
  });

  testWidgets('rolando até o fim, o último rótulo aparece INTEIRO', (
    tester,
  ) async {
    await pump(tester, largura: larguraEstreita, escala: 2.0);

    // Fora da viewport a pílula sequer é construída (a ListView é preguiçosa)
    // — o que confirma que ela está mesmo fora da tela nesta largura.
    expect(find.text('Finalizadas'), findsNothing);

    // A régua tem ~1125pt de extent nesta condição (320pt de largura, fonte
    // 2×): quatro pílulas grandes numa tela pequena. Arrastar o extent
    // inteiro leva ao fim.
    await tester.drag(find.byType(ListView), const Offset(-1200, 0));
    await tester.pumpAndSettle();

    // Depois de rolar: o rótulo aparece POR EXTENSO. A pílula não reticencia
    // o próprio texto — "Finaliza…" seria um rótulo truncado, que lê como
    // defeito; cortado pela borda de uma régua rolável, com esmaecimento por
    // cima, lê como conteúdo que continua.
    expect(find.text('Finalizadas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('fadeStops · o indício de que a régua rola', () {
    test('com pílula fora da viewport, os últimos 12% desvanecem', () {
      expect(fadeStops(canScrollRight: true), const [0.0, 0.88, 1.0]);
    });

    test('quando tudo cabe, nada desvanece', () {
      // Sem isto a régua ganharia uma borda esmaecida permanente, sugerindo
      // conteúdo que não existe.
      expect(fadeStops(canScrollRight: false), const [0.0, 1.0, 1.0]);
    });
  });
}

void _naoUsado(ApplicationSegment _) {}
