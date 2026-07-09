// Roteiro de DEMONSTRAÇÃO da Trilha de Coleta (Increment 1, PLANO-FASE-6 T6.3).
//
// Uma conversa roteirizada que mostra a "cara" da experiência (bolhas da IA +
// widgets inline + reações), sem ainda gravar em profile_* nem ser dirigida
// pelo cérebro de lacunas — isso vem nos próximos incrementos. Serve pra você
// sentir o ritmo e o tom no device.

import '../domain/conversation_step.dart';

List<ConversationStep> buildDemoConversation() => [
      ConversationStep.single(
        id: 'demo.start',
        aiMessage:
            'Oi! Sou seu copiloto de carreira. Em uns minutinhos a gente deixa '
            'seu perfil forte o bastante pra empresas te acharem. Bora?',
        input: const ChoiceInput(
          options: [StepOption(id: 'go', label: 'Bora começar')],
        ),
      ),
      ConversationStep.single(
        id: 'demo.skills',
        aiMessage:
            'Começando pelas suas habilidades — toque em tudo que você manja '
            '(pode ser mais de uma).',
        input: const ChoiceInput(
          multi: true,
          options: [
            StepOption(id: 'excel', label: 'Excel'),
            StepOption(id: 'python', label: 'Python'),
            StepOption(id: 'sql', label: 'SQL'),
            StepOption(id: 'canva', label: 'Canva'),
            StepOption(id: 'vendas', label: 'Vendas'),
            StepOption(id: 'powerbi', label: 'Power BI'),
            StepOption(id: 'comunicacao', label: 'Comunicação'),
            StepOption(id: 'social', label: 'Redes sociais'),
          ],
        ),
        acknowledgement:
            'Boa! Já dá pra te conectar com vagas que pedem essas habilidades.',
      ),
      ConversationStep.single(
        id: 'demo.has_experience',
        aiMessage:
            'Você já trabalhou, estagiou, fez algum projeto ou voluntariado? '
            'Vale qualquer coisa — mesmo curta ou informal.',
        input: const ChoiceInput(
          options: [
            StepOption(id: 'yes', label: 'Já sim'),
            StepOption(id: 'no', label: 'Ainda não'),
          ],
        ),
      ),
      ConversationStep.single(
        id: 'demo.exp_highlight',
        aiMessage:
            'Me conta uma coisa concreta que você fez e tem orgulho. Pode '
            'escrever do seu jeito, desorganizado — eu organizo pra você.',
        input: const GuidedTextInput(
          example: 'Organizei um evento com 200 pessoas e captei 3 patrocínios',
          maxLength: 240,
          minLines: 3,
        ),
        acknowledgement:
            'Isso é ótimo material — depois eu transformo num bullet '
            'profissional pra brilhar no seu CV. ✨',
      ),
      ConversationStep.single(
        id: 'demo.english',
        aiMessage: 'Última: qual seu nível de inglês?',
        input: const ChoiceInput(
          options: [
            StepOption(id: 'basic', label: 'Básico'),
            StepOption(id: 'intermediate', label: 'Intermediário'),
            StepOption(id: 'advanced', label: 'Avançado'),
            StepOption(id: 'fluent', label: 'Fluente / Nativo'),
          ],
        ),
        acknowledgement: 'Fechou! 👇',
      ),
    ];
