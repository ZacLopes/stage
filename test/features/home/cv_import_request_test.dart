import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/home/home_viewmodel.dart'
    show HomeTabs;

// F5.4 — pedido de importar CV entre abas. O card "Fonte importada" (Perfil →
// Dados) é a casa da fonte, mas a REVISÃO do import vive no Assistente; o card
// pede a troca de aba + o cartão de import. Aqui garantimos o contrato do
// índice de aba (o resto do idioma request/clear é exercitado pelo app).
void main() {
  test('a aba do Assistente é HomeTabs.resume (destino do pedido)', () {
    // Se alguém reordenar as abas, este teste quebra ANTES de o pedido levar o
    // usuário pra aba errada.
    expect(HomeTabs.resume, 2);
    expect(HomeTabs.profile, 3);
    expect(HomeTabs.jobs, 0);
    expect(HomeTabs.saved, 1);
  });
}
