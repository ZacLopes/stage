# Plano — IA/Perfil: fechamento da Fase 2 original

**Status:** implementado no working tree; checkpoint técnico concluído em
17/07/2026. Flag permanece OFF/0 e o rollout aguarda a fundação da Fase 3.

Este plano usa a numeração do roadmap de arquitetura da informação
(`Assistente assume a terceira aba`), e não a numeração do plano-mãe de
produto. A fundação de fontes importadas, correspondente à Fase 5 deste
roadmap, foi estacionada em `refactor/perfil-central-fase-3` antes deste
trabalho. Nenhuma migration ou Edge dessa linha será levada junto.

## Estado verificado antes desta implementação

- A conversa já é a superfície principal da terceira aba quando
  `trilha_assist_v1` está ligada.
- Antes desta fase, `ConversationController.submit` capturava a falha do
  write-back e avançava o passo.
- Antes desta fase, o apply em lote podia concluir o card apesar de falhas por
  item.
- O stepper continua sempre exposto no topo da aba.
- A chave `trilha_assist_v1` existe no cliente, mas não tem seed versionado em
  `app_feature_flags`.
- Progresso e rascunho possuem persistência, mas o contexto recente da conversa
  é apenas de memória.

## Escopo, na ordem

### F2.1 — Write-back honesto e recuperável

- Tornar `ConversationController.submit` fail-closed: falha de persistência não
  avança, não entra no histórico e deixa a mesma resposta disponível para retry.
- Expor estado/erro tipado suficiente para a UI mostrar falha e tentar novamente.
- No apply em lote, agregar resultados reais; qualquer falha mantém o card fora
  de `applied` e nunca oferece desfazer de uma operação que não concluiu.
- Preservar o comportamento de rollback quando `trilha_assist_v1` estiver OFF.

### F2.2 — Flag estrutural e rollback

- Criar migration aditiva/idempotente que semeia `trilha_assist_v1` como
  `enabled=false`, `rollout_pct=0`.
- Atualizar o manifest de migrations.
- Manter a flag aninhada ao gate pai existente e documentar rollout
  `10 → 50 → 100`, sem ativá-lo nesta rodada.

### F2.3 — Stepper recolhido

- Com a flag ON, substituir o stepper sempre aberto por uma entrada compacta
  `Fortalecer perfil`, expansível e acessível.
- Com a flag OFF, preservar exatamente o header/stepper/toggle legado.
- Manter acesso a status e seções sem ocupar permanentemente o topo da conversa.

### F2.4 — Contexto mínimo da conversa

- Persistir somente o contexto necessário para retomar a experiência; não criar
  um arquivo indefinido de conversa nem enviar texto para analytics.
- Preferir armazenamento local versionado e limitado, sem migration, se a
  auditoria confirmar que ele é suficiente e não conflita entre usuários.
- Isolar por `user_id`, limitar quantidade/tamanho e falhar de modo best-effort:
  erro de cache não pode impedir a conversa nem fingir persistência de perfil.

## Fora de escopo

- Fonte importada em Perfil → Dados e biblioteca outputs-only (Fase 5).
- Completar todos os campos editáveis e unificar completude (Fase 3).
- Persistir/versionar o Currículo geral (Fase 4).
- Deploy, push, ativação de flag ou migration remota.
- Refatorar Provider/Navigator ou remover caminhos legados.

## Critérios de pronto

1. Falha de qualquer write-back testado nunca avança o passo nem mostra
   sucesso; retry bem-sucedido avança uma vez, sem duplicar.
2. Apply em lote parcial tem resultado honesto e recuperável.
3. `trilha_assist_v1` possui seed OFF/0 idempotente e rollback visual OFF.
4. Flag ON abre a conversa como Assistente e deixa o stepper recolhido em
   `Fortalecer perfil`.
5. Fechar/reabrir restaura apenas o contexto curto definido, separado por
   usuário; logout/troca de conta não vaza contexto.
6. Testes unitários e de widget dos caminhos críticos, `flutter test`, analyzer,
   checks de migration/ambiente e `git diff --check` verdes.
7. Nenhum commit, push ou deploy final sem um novo checkpoint de revisão.

## Decisões de implementação e rollout

- A terceira aba ON é somente **Assistente**; a prévia do Currículo geral fica
  em Perfil → Currículos. O shell legado continua inteiro com a flag OFF.
- O stepper ON nasce recolhido em **Fortalecer perfil**, com progresso `N/5` e
  acesso por teclado/leitor de tela.
- O contexto local guarda no máximo 3 turnos curtos por usuário, com TTL de 7
  dias, limite de 8 KiB e redação. Cards, ferramentas e respostas de coleta não
  viram memória conversacional.
- Importar CV pelo Assistente fica honestamente indisponível nesta fase. O gate
  legado OFF continua intacto; a superfície segura de **Fonte importada** pertence
  à Fase 5.
- Áreas são direcionadas a Perfil → Objetivos; interesses, a Perfil →
  Dados. Os callbacks replace-all desses editores não são injetados na
  composição de produção.
- Leitura de confirmação de skills/idiomas é estrita. Falha de rede nunca vira
  lista vazia nem recibo de sucesso. Lotes parciais não podem ser cancelados
  como se nada tivesse mudado; retry e undo são protegidos pelo estado vivo
  observado.
- Updates de campo, item e bullet recusam apply/undo quando o valor vivo mudou;
  diferenças de capitalização contam no recibo de persistência.

### Pré-requisito obrigatório antes de qualquer rollout

O seed OFF/0 é intencional. **Não iniciar 10% ainda.** A base atual possui
writers cliente `get → replace` e operações compostas sem CAS/transação para
skills, áreas, interesses e alguns undos. As proteções locais fecham falso
sucesso e muitos casos stale, mas não eliminam a janela entre leitura e escrita.

Ordem segura:

1. concluir este checkpoint da Fase 2 com a flag OFF;
2. na Fase 3, criar writers/RPCs transacionais e CAS para as mutações guiadas e
   seus recibos de undo, preservando sempre a edição manual mais recente;
3. repetir testes adversariais de concorrência e rollback;
4. somente então considerar `10 → 50 → 100`, em checkpoints separados.
