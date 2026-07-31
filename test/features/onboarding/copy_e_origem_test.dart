import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/onboarding/domain/location_key.dart';

/// Revisão UX 28/07, achados P2-23 e P2-27.
void main() {
  group('P2-23 · reconhecer o card que o APP semeou', () {
    test('mesma cidade+UF casa, mesmo com caixa e espaço diferentes', () {
      // O nome chega capitalizado do perfil e cru do catálogo de busca.
      expect(locationKey('São Paulo', 'SP'), locationKey(' são paulo ', 'SP'));
    });

    test('mesma cidade em UF diferente NÃO casa', () {
      // Senão o card de Campinas/RJ ganharia "Onde você mora" por engano.
      expect(
        locationKey('Campinas', 'SP') == locationKey('Campinas', 'RJ'),
        isFalse,
      );
    });

    test('cidade sem UF não colide com cidade com UF', () {
      expect(locationKey('Recife', null) == locationKey('Recife', 'PE'), isFalse);
    });

    test('nulo não explode e não casa com cidade real', () {
      expect(locationKey(null, null), '|');
      expect(locationKey(null, null) == locationKey('Recife', 'PE'), isFalse);
    });
  });

  test('P2-27 · nenhum jargão de fora do público na copy de lib/', () {
    // Num app pt-BR para estagiários, os modelos de currículo eram descritos
    // como "banking, consultoria e MBA", "GPA prominente", "sidebar de
    // contato/skills" e "accent azul cobalt". Três dos cinco descreviam um
    // público — IB, MBA, FAANG — que não é o do produto.
    //
    // Lista fechada com o que estava lá. Termos que também aparecem em nome
    // de símbolo ou de arquivo ficam de fora: o alvo é a frase que a pessoa lê.
    final proibidos = <String>[
      'FAANG',
      'early-career',
      'IB/Consulting',
      'Banking/MBA',
      'GPA prominente',
      'accent azul',
      'sidebar de',
    ];

    final ofensas = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final linhas = entity.readAsLinesSync();
      for (var i = 0; i < linhas.length; i++) {
        final linha = linhas[i];
        if (linha.trimLeft().startsWith('//')) continue;
        if (!linha.contains("'") && !linha.contains('"')) continue;
        for (final termo in proibidos) {
          if (linha.contains(termo)) {
            ofensas.add('${entity.path}:${i + 1} → "$termo"');
          }
        }
      }
    }

    expect(ofensas, isEmpty, reason: 'Jargão na copy:\n${ofensas.join('\n')}');
  });
}
