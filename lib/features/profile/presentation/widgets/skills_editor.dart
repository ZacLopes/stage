import 'package:flutter/material.dart';

import '../../domain/skill_name_normalizer.dart';
import 'edit_list_modal.dart';

/// Texto de orientação do editor de habilidades.
///
/// Público para o teste poder afirmar sobre a faixa sem repetir a string —
/// e para os números virem das MESMAS constantes que o `maxItems` usa.
const String kSkillsEditorGuidance =
    'Priorize de $kRecommendedMinProfileSkills a $kMaxProfileSkills '
    'habilidades que você realmente usa e que são relevantes para as vagas '
    'que busca.';

/// Abre o editor de habilidades do perfil, sempre com a MESMA configuração.
///
/// Revisão UX 28/07, achado P1-3: quem esbarrava no gate de skills do adapt era
/// mandado pra Perfil → Dados → Habilidades por deep-link (troca de aba +
/// scroll + abrir o editor). O destino estava certo, mas era só de ida: depois
/// de salvar, a pessoa estava em outra aba do app, com a sheet da vaga já
/// fechada, e precisava reencontrar a vaga no feed pra tentar de novo — só que
/// o feed é um baralho, não uma lista com histórico. O botão prometia
/// destravar a adaptação e entregava um beco sem saída.
///
/// Agora a sheet de adaptação abre este mesmo editor POR CIMA dela. Não há
/// "caminho de volta" a construir: fechar o modal já devolve a pessoa à vaga.
///
/// A função existe (em vez de duas chamadas iguais) porque `guidanceText`,
/// `recommendedMinItems` e `maxItems` precisam ser os mesmos nos dois lugares.
/// O achado P2-28 foi exatamente isso: dois limiares para a mesma tarefa, a um
/// minuto de distância um do outro.
///
/// Recebe listas e callback em vez do `ProfileEditorViewModel` inteiro porque
/// o VM toca o cliente Supabase no construtor — pedir só o que se usa é o que
/// torna esta configuração testável.
Future<void> showSkillsEditor(
  BuildContext context, {
  required List<String> initialSkills,
  required List<String> suggestions,
  required void Function(List<String>) onSave,
}) {
  return EditListModal.show(
    context: context,
    title: 'Editar habilidades',
    inputLabel: 'Habilidade',
    initialItems: initialSkills,
    suggestions: suggestions,
    guidanceText: kSkillsEditorGuidance,
    recommendedMinItems: kRecommendedMinProfileSkills,
    maxItems: kMaxProfileSkills,
    onSave: onSave,
  );
}
