import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/services/profile_events.dart';

/// Separação dos dois canais (27/07, decisão do fundador).
///
/// A correção do Bloqueador A fez a coleta guiada avisar a cada passo
/// respondido. Com um canal só, cada passo pagava o custo caro — invalidar
/// match e, dependendo dos filtros, refazer o fetch do FEED INTEIRO. Numa
/// sessão de 8 perguntas, 8 vezes.
void main() {
  test('notifyChanged() emite nos DOIS canais por padrão', () async {
    final events = <String>[];
    final a = ProfileEvents.instance.changes.listen((_) => events.add('barato'));
    final b = ProfileEvents.instance.matchInputsChanged
        .listen((_) => events.add('caro'));
    addTearDown(() {
      a.cancel();
      b.cancel();
    });

    ProfileEvents.instance.notifyChanged();
    await Future<void>.delayed(Duration.zero);

    // Default preserva o comportamento de TODOS os emissores preexistentes
    // (editor manual, preferências, import, bridge da gamificação).
    expect(events, containsAll(<String>['barato', 'caro']));
    expect(events.length, 2);
  });

  test('affectsMatch: false emite SÓ o canal barato', () async {
    final events = <String>[];
    final a = ProfileEvents.instance.changes.listen((_) => events.add('barato'));
    final b = ProfileEvents.instance.matchInputsChanged
        .listen((_) => events.add('caro'));
    addTearDown(() {
      a.cancel();
      b.cancel();
    });

    ProfileEvents.instance.notifyChanged(affectsMatch: false);
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>['barato']);
    expect(events.contains('caro'), isFalse);
  });

  test('um burst de 8 passos custa 8 baratos e 1 caro no fim', () async {
    var barato = 0;
    var caro = 0;
    final a = ProfileEvents.instance.changes.listen((_) => barato++);
    final b = ProfileEvents.instance.matchInputsChanged.listen((_) => caro++);
    addTearDown(() {
      a.cancel();
      b.cancel();
    });

    // Coleta guiada: um aviso barato por passo respondido.
    for (var i = 0; i < 8; i++) {
      ProfileEvents.instance.notifyChanged(affectsMatch: false);
    }
    // Fim da seção/trilha: um aviso completo.
    ProfileEvents.instance.notifyChanged();
    await Future<void>.delayed(Duration.zero);

    expect(barato, 9); // 8 passos + o fecho
    expect(caro, 1); // era 9 antes da separação
  });
}
