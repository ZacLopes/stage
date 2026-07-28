import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/profile/domain/entities/entities.dart';
import 'package:career_gamification/features/profile/presentation/widgets/add_edit_certification_modal.dart';

/// Auditoria de 27/07 — a perda de dados das certificações.
///
/// A seção era a única lista do editor sem modal próprio: usava o
/// `EditListModal` genérico, que só entende texto solto. Mostrava
/// "Nome - Instituição - Ano" numa linha e, ao salvar, apagava TODAS as
/// certificações e regravava cada linha inteira no campo `name`, com `issuer` e
/// `date` nulos. Abrir e salvar sem mudar nada já destruía a estrutura.
///
/// Medido em produção no dia: 392 certificações de 126 pessoas com instituição
/// ou data a perder; 19 linhas de 13 pessoas já destruídas.
///
/// O teste central é o primeiro: ABRIR E SALVAR SEM TOCAR EM NADA não pode
/// mudar coisa alguma. Os demais cobrem a armadilha do `copyWith` (que usa `??`
/// e portanto ignoraria uma limpeza) e o campo obrigatório.
void main() {
  final base = Certification(
    id: 'cert-1',
    userId: 'user-1',
    name: 'Excel Avançado',
    issuer: 'FGV',
    date: DateTime(2024, 3),
    orderIndex: 2,
  );

  /// Monta a modal já aberta, devolvendo o que o `onSave` recebeu.
  Future<Certification?> abrirESalvar(
    WidgetTester tester, {
    Certification? initial,
    Future<void> Function(WidgetTester t)? antesDeSalvar,
  }) async {
    Certification? salvo;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddEditCertificationModal(
            initial: initial,
            onSave: (c) => salvo = c,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (antesDeSalvar != null) await antesDeSalvar(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();
    return salvo;
  }

  testWidgets('ABRIR E SALVAR SEM MUDAR NADA preserva tudo', (tester) async {
    // Este é o bug, na forma exata em que ele acontecia.
    final salvo = await abrirESalvar(tester, initial: base);

    expect(salvo, isNotNull);
    expect(salvo!.name, 'Excel Avançado',
        reason: 'o nome não pode virar a concatenação "Nome - Inst - Ano"');
    expect(salvo.issuer, 'FGV', reason: 'a instituição foi perdida');
    expect(salvo.date, DateTime(2024, 3), reason: 'a data foi perdida');
    expect(salvo.id, 'cert-1', reason: 'virou uma linha nova em vez de editar');
    expect(salvo.userId, 'user-1');
    expect(salvo.orderIndex, 2, reason: 'a ordem foi perdida');
  });

  testWidgets('os campos aparecem separados, não numa linha só', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddEditCertificationModal(initial: base, onSave: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Excel Avançado'), findsOneWidget);
    expect(find.text('FGV'), findsOneWidget);
    expect(find.text('03/2024'), findsOneWidget);
    // O formato antigo, de texto grudado, não pode aparecer em lugar nenhum.
    expect(find.text('Excel Avançado - FGV - 2024'), findsNothing);
  });

  testWidgets('trocar só o nome não derruba instituição nem data',
      (tester) async {
    final salvo = await abrirESalvar(
      tester,
      initial: base,
      antesDeSalvar: (t) async {
        await t.enterText(
            find.widgetWithText(TextField, 'Excel Avançado'), 'Excel Pro');
        await t.pumpAndSettle();
      },
    );

    expect(salvo!.name, 'Excel Pro');
    expect(salvo.issuer, 'FGV');
    expect(salvo.date, DateTime(2024, 3));
  });

  testWidgets('APAGAR a instituição realmente apaga (a armadilha do copyWith)',
      (tester) async {
    // `Certification.copyWith` usa `??`, então passar null nele MANTERIA o
    // valor antigo — a limpeza seria silenciosamente ignorada. Por isso a modal
    // constrói a entidade direto.
    final salvo = await abrirESalvar(
      tester,
      initial: base,
      antesDeSalvar: (t) async {
        await t.enterText(find.widgetWithText(TextField, 'FGV'), '');
        await t.pumpAndSettle();
      },
    );

    expect(salvo!.issuer, isNull, reason: 'a instituição apagada voltou');
    expect(salvo.name, 'Excel Avançado');
    expect(salvo.date, DateTime(2024, 3));
  });

  testWidgets('espaço em branco na instituição vira null, não string vazia',
      (tester) async {
    final salvo = await abrirESalvar(
      tester,
      initial: base,
      antesDeSalvar: (t) async {
        await t.enterText(find.widgetWithText(TextField, 'FGV'), '   ');
        await t.pumpAndSettle();
      },
    );
    expect(salvo!.issuer, isNull);
  });

  testWidgets('"Limpar" remove a data e ela fica removida', (tester) async {
    // Sem esse botão, uma data errada (posta por engano ou vinda de uma
    // importação ruim) seria impossível de tirar pela interface.
    final salvo = await abrirESalvar(
      tester,
      initial: base,
      antesDeSalvar: (t) async {
        expect(find.text('Limpar'), findsOneWidget);
        await t.tap(find.text('Limpar'));
        await t.pumpAndSettle();
        expect(find.text('--/--'), findsOneWidget);
      },
    );

    expect(salvo!.date, isNull, reason: 'a data limpa voltou');
    expect(salvo.issuer, 'FGV', reason: 'limpar a data não pode afetar o resto');
  });

  testWidgets('sem data não existe "Limpar" para tocar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddEditCertificationModal(
            initial: Certification(
                id: 'c', userId: 'u', name: 'Curso', issuer: 'X'),
            onSave: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('--/--'), findsOneWidget);
    expect(find.text('Limpar'), findsNothing);
  });

  testWidgets('nome vazio não deixa salvar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddEditCertificationModal(initial: base, onSave: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Excel Avançado'), '');
    await tester.pumpAndSettle();

    final botao =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Salvar'));
    expect(botao.onPressed, isNull, reason: 'salvaria uma certificação sem nome');
  });

  testWidgets('uma certificação já destruída pode ser consertada à mão',
      (tester) async {
    // As 19 linhas que o bug antigo já concatenou chegam assim: nome poluído,
    // campos vazios. A modal tem que permitir desfazer isso manualmente — não
    // adivinhamos onde termina o nome e começa a instituição.
    final destruida = Certification(
      id: 'cert-9',
      userId: 'user-1',
      name: 'Excel Avançado - FGV - 2024',
    );
    final salvo = await abrirESalvar(
      tester,
      initial: destruida,
      antesDeSalvar: (t) async {
        await t.enterText(
            find.widgetWithText(TextField, 'Excel Avançado - FGV - 2024'),
            'Excel Avançado');
        await t.enterText(
            find.widgetWithText(TextField, 'Quem emitiu — Ex: FGV, Alura, Google'),
            'FGV');
        await t.pumpAndSettle();
      },
    );

    expect(salvo!.name, 'Excel Avançado');
    expect(salvo.issuer, 'FGV');
    expect(salvo.id, 'cert-9');
  });
}
