import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Revisão UX 28/07, achado P3-40 — o app falava com a pessoa em duas
/// segundas-pessoas ao mesmo tempo.
///
/// O caso mais claro estava numa frase só: *"Toque nas que combinam, busca ou
/// escreve a sua — escolhe até 3"* — um verbo em "você" e três em "tu", na
/// mesma linha, na tela que define as áreas de interesse. Fora dela havia
/// treze "Tenta de novo" convivendo com "Tente novamente".
///
/// A escolha foi **você**, que já era o registro dominante do app. O
/// Assistente continua informal — isso vem do vocabulário e dos emoji, não da
/// conjugação.
///
/// Copy não tem predicado para testar por mutação. O que dá para garantir é
/// que as formas exatas que estavam erradas não voltem: quem escrever "Tenta
/// de novo" de novo derruba este teste. A lista é fechada de propósito — um
/// regex genérico de 3ª pessoa acusaria "Lá você toca na vaga" e
/// "o usuário toca no botão", que são indicativos corretos.
void main() {
  /// Só o que aparece na tela. Comentário e nome de símbolo ficam de fora.
  final proibidas = <String>[
    'Tenta de novo',
    'Tenta novamente',
    'Toca de novo',
    'toca na opção',
    'toca no que precisar',
    'Toca em tudo',
    'toca duas vezes',
    'Manda o texto',
    'busca ou',
    'escreve a sua',
    'escolhe até',
  ];

  test('nenhuma forma de "tu" volta para a copy de lib/', () {
    final ofensas = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final linhas = entity.readAsLinesSync();
      for (var i = 0; i < linhas.length; i++) {
        final linha = linhas[i];
        // Linha de comentário não é copy.
        if (linha.trimLeft().startsWith('//')) continue;
        // Sem aspas, sem string — não é texto de tela.
        if (!linha.contains("'") && !linha.contains('"')) continue;
        for (final forma in proibidas) {
          if (linha.contains(forma)) {
            ofensas.add('${entity.path}:${i + 1} → "$forma"');
          }
        }
      }
    }

    expect(
      ofensas,
      isEmpty,
      reason: 'Copy em 2ª pessoa "tu". O app fala "você":\n'
          '${ofensas.join('\n')}',
    );
  });
}
