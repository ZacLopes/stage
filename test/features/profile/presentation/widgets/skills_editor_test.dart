import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/profile/domain/skill_name_normalizer.dart';
import 'package:career_gamification/features/profile/presentation/widgets/skills_editor.dart';

/// Revisão UX 28/07, achado P1-3 — "depois de salvar as skills, não há volta
/// para a vaga".
///
/// O defeito não era o destino, era o trajeto: o CTA da sheet de adaptação
/// fazia `Navigator.pop()` + troca de aba + deep-link de seção. A pessoa
/// salvava as habilidades e estava em OUTRA aba do app, com a vaga fechada —
/// e o feed é um baralho, então reencontrar aquela vaga podia ser impossível.
///
/// A correção é abrir o MESMO editor por cima de quem chamou. O que este
/// arquivo prova é justamente isso: a tela de origem continua montada embaixo
/// e volta a ser a tela ativa quando o editor fecha. Se alguém trocar o modal
/// por uma navegação que substitui a rota, o primeiro teste cai.
void main() {
  /// Host mínimo: uma tela com um marcador próprio e um botão que abre o
  /// editor. Faz o papel da sheet de adaptação sem arrastar AIService,
  /// Supabase e os cinco providers que ela precisa.
  Widget host({
    List<String> initial = const [],
    List<String> suggestions = const [],
    void Function(List<String>)? onSave,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              const Text('TELA DE ORIGEM'),
              ElevatedButton(
                onPressed: () => showSkillsEditor(
                  context,
                  initialSkills: initial,
                  suggestions: suggestions,
                  onSave: onSave ?? (_) {},
                ),
                child: const Text('Adicionar habilidades'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('abre POR CIMA: a tela de origem continua montada', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(find.text('TELA DE ORIGEM'), findsOneWidget);

    await tester.tap(find.text('Adicionar habilidades'));
    await tester.pumpAndSettle();

    // O editor está na tela...
    expect(find.text('Editar habilidades'), findsOneWidget);
    // ...E a origem NÃO foi destruída. Era este o achado: o caminho antigo
    // dava pop na sheet da vaga antes de navegar.
    expect(find.text('TELA DE ORIGEM'), findsOneWidget);
  });

  testWidgets('fechar devolve a pessoa à tela de origem', (tester) async {
    var salvo = <String>[];
    await tester.pumpWidget(host(onSave: (l) => salvo = l));

    await tester.tap(find.text('Adicionar habilidades'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Python');
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(salvo, contains('Python'));
    // Editor fechado, origem ativa: o ciclo "faltou skill → resolvo → volto
    // pra vaga" fecha sem a pessoa ter que reencontrar a vaga no feed.
    expect(find.text('Editar habilidades'), findsNothing);
    expect(find.text('TELA DE ORIGEM'), findsOneWidget);
  });

  testWidgets('leva a MESMA faixa recomendada dos dois call sites', (
    tester,
  ) async {
    await tester.pumpWidget(host(initial: const ['Python', 'SQL']));
    await tester.tap(find.text('Adicionar habilidades'));
    await tester.pumpAndSettle();

    // P2-28: o gate do adapt e o editor precisam citar a mesma faixa. Aqui a
    // origem é a constante, não uma string solta — se alguém mudar o número
    // num lugar só, este expect cai.
    expect(
      find.textContaining(
        'de $kRecommendedMinProfileSkills a $kMaxProfileSkills',
      ),
      findsWidgets,
    );
    expect(kSkillsEditorGuidance, contains('de 6 a 12'));
  });
}
