import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/application.dart';
import 'package:career_gamification/features/jobs/widgets/manual_application_card.dart';

/// C5 do device-test + achado do review de 27/07.
///
/// O C5 era testado só no enum (`ApplicationType.label`), nunca no widget que
/// desenha o selo — reverter o card para o literal `'manual'` mantinha tudo
/// verde. Aqui a asserção mira o que a tela realmente pinta.
///
/// E o C5 tem um custo de layout: o selo passou de 6 para 19 caracteres numa
/// Row que divide espaço com o título digitado pelo usuário. Os casos abaixo
/// medem esse custo em vez de argumentar sobre ele.
void main() {
  Application manual({
    String title = 'Estagio de Dados',
    String company = 'Nubank',
    ApplicationStatus status = ApplicationStatus.submitted,
  }) {
    final now = DateTime(2026, 7, 27);
    return Application(
      id: 'app-1',
      userId: 'user-1',
      jobId: null,
      type: ApplicationType.manual,
      status: status,
      externalCompany: company,
      externalTitle: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  Widget host(Application app, {double textScale = 1.0}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Padding(
              // Espelha o padding real da lista da aba Candidaturas.
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ManualApplicationCard(
                application: app,
                statusOptions: const [
                  ApplicationStatus.inReview,
                  ApplicationStatus.interview,
                ],
                onStatusSelected: (_) {},
              ),
            ),
          ),
        ),
      );

  /// iPhone 13 / 14 / 15 — a largura mais comum da base.
  Future<void> phone(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('C5 — o selo mostra o rótulo pt-BR, nunca o valor de banco',
      (tester) async {
    await phone(tester);
    await tester.pumpWidget(host(manual()));

    expect(find.text('Adicionada por você'), findsOneWidget);
    expect(find.text('manual'), findsNothing);
  });

  testWidgets('o selo não tira largura do título digitado pelo usuário',
      (tester) async {
    // O rótulo do C5 é bem mais largo que o `'manual'` antigo. Enquanto era o
    // terceiro filho RÍGIDO da Row, essa largura saía do `Expanded` — ou seja,
    // do dado que a própria pessoa digitou.
    //
    // A asserção mede a LARGURA DISPONÍVEL para o título, não quantas linhas
    // ele ocupou: `didExceedMaxLines` dependeria da fonte, e no flutter_test
    // cada glifo é um quadrado de `fontSize` (uma string de 39 chars a 15px
    // "mede" 585px), o que não diz nada sobre Outfit no aparelho real.
    await phone(tester);
    const titulo = 'Assistente Administrativo Financeiro Jr';
    await tester.pumpWidget(host(manual(title: titulo)));

    final cardW = tester.getSize(find.byType(ManualApplicationCard)).width;
    final disponivel = tester
        .renderObject<RenderParagraph>(find.text(titulo))
        .constraints
        .maxWidth;

    // Descontando a borda (1+1), o padding do card (12+12) e o ícone com o gap
    // (40+12), o título tem que ficar com TODO o resto. Medido: 280 de 358.
    expect(disponivel, moreOrLessEquals(cardW - 2 - 24 - 52, epsilon: 1.0),
        reason: 'o selo voltou a disputar a linha do título');
  });

  testWidgets('não estoura com Dynamic Type grande', (tester) async {
    // Com o selo rígido na mesma Row, escalas de acessibilidade levavam o card
    // a RenderFlex overflow — com `'manual'` isso praticamente nunca acontecia.
    await phone(tester);
    await tester.pumpWidget(host(manual(), textScale: 2.5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empresa vazia não deixa o card quebrado', (tester) async {
    await phone(tester);
    await tester.pumpWidget(host(manual(company: '')));
    expect(find.text('Estagio de Dados'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
