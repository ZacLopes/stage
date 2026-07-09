# PLANO — Assistente de IA na barra da trilha

**Status:** aprovado pelo fundador em 09/07/2026 (R1). Fase A em execução.
**Flag:** `trilha_assist_v1` (aninhada em `trilha_coleta_v1`, OFF em prod, rollout 10→50→100).

## Decisões do fundador
1. **Escopo das respostas:** currículo / carreira / vagas / o app. Fora disso → recusa gentil (`out_of_scope`).
2. **Aplicar alterações (Fase B):** o assistente **PROPÕE → o usuário CONFIRMA → aplica → e ainda fica o "Desfazer"**. (confirmar-antes + desfazer-depois; nunca grava mutação direto.)
3. **Começar pela Fase A.**
4. Técnicas (assumidas): cidade sempre canonizada (IBGE); `rewrite_summary` com `mode:'preview'`; `improve_bullet` dentro da própria edge; nome da flag `trilha_assist_v1`.

## Visão
A barra "Escreva uma mensagem…" deixa de só responder o passo aberto e vira assistente de currículo: tira dúvida, aconselha, sabe o que falta, entrega as perguntas certas quando o usuário quer preencher, e (Fase B) altera o perfil sob confirmação, sempre mostrando o que mudou + Desfazer.

## Princípios inegociáveis (guardrails)
- O LLM **propõe, nunca escreve**. Escrita = roteamento determinístico que já existe (`TrilhaWriteback.save(StepAnswer)`).
- Só campo real, só valor validado (allowlist = rotas do write-back; enums/ids por `_xFromId`/`validIds`). Nunca inventa dado.
- Toda mutação visível (diff + Desfazer); destrutivo confirma antes (bloqueante).
- Failure-safe: timeout/erro/baixa confiança → cai no fluxo roteirizado ou pede toque; nunca sucesso calado; nunca estado meio-salvo.
- PII fora da telemetria; contexto minimizado ao modelo; auth JWT + RLS. Texto do usuário entra em bloco DADO delimitado (anti-injeção).
- Um turno por seção `_busy`; o assistente enfileira no plano, não abre fluxo paralelo.

## Arquitetura
- **Edge nova `supabase/functions/trilha-assistant/index.ts`** — espelha `interpret-step-answer` (JWT, `withEdgeAnalytics`, gpt-4o-mini, temp 0). Function-calling nativo, `tool_choice:'required'`, 1 tool/turno; cada tool carrega `reply` (frase pt-BR). Servidor decide `needsConfirm`/`diff`. `PROMPT_VERSION='assistant_v1'` no envelope (R5). Absorve `interpret-step-answer` (vira `answer_current_step`, mantendo o filtro `validIds`).
- **Envelope:** `{intent, tool, args, reply, needsConfirm, confirmPrompt?, diff?, promptVersion}`.
- **Cliente:** `AIService.assistantTurn(...)`; orquestração em `TrilhaChatController.submitFreeText` (bifurcação fast-lane/IA; remover o early-return `if (step==null) return`); `_executeTool(envelope)`.
- **Registry de tools = rotas do write-back** (sintetiza `StepAnswer` → `saveAnswer`). Zero migration.
- **Grounding** (da memória da sessão, sem novo round-trip): `openStep`, `gaps` (ProfileGaps.all compacto), `inventory` (do ProfileSnapshot), `history` (~6 falas).

## Roteamento passo-aberto vs conversa livre
- **Nível 0 (local, sem IA):** passo de texto aberto + mensagem sem marcadores de comando (não termina em "?", não começa com imperativo de meta, não cita outra seção) → `StepAnswer.text` direto (custo zero, = hoje).
- **Nível 1 (IA roteia):** senão, a edge recebe `openStep` + todos os tools (incl. `answer_current_step`) e decide. Na dúvida entre responder o passo e conversar → responde o passo.
- **Regra de ouro:** comando **nunca** descarta o passo aberto em silêncio — parqueia (1 nível), atende, e `_reveal()` re-exibe o passo pendente.

## FASE A (em execução) — ler / responder / conduzir (SEM mutar)
Tools: `answer_current_step` (absorve interpret-step-answer), `answer_question`, `give_advice`, `show_gaps`, `show_profile_summary`, `explain_step`, `skip_step`, `out_of_scope`, `start_section`.
Peças:
1. Flag `trilha_assist_v1`.
2. Constantes de telemetria `evTrilhaAssist*` (subset A) + emissores.
3. `sectionSteps(LacunaKey, {searchers})` público em `conversation_plan.dart` (extrai builders privados; ignora o gate por lacuna) + `ConversationController.injectNext(steps)` (= mecânica do expand).
4. Edge `trilha-assistant` (escopo fechado; function-calling).
5. `AIService.assistantTurn` (failure-safe, timeout 20s).
6. `submitFreeText`: fast-lane + roteador + `_executeTool` (só read-only/navegação) + parquear/retomar.
7. Testes: classificador de marcadores (fast-lane), tool→ação (read-only), `sectionSteps`, parquear/retomar, `injectNext`; deno com modelo mockado.
**Sem escrita fora do write-back que já existe → risco baixo, valor alto.**

## FASE B — alterações com confirmar → aplicar → desfazer
Tools de escrita: `update_field`, `add_item`, `remove_item` (destrutivo), `rewrite_summary` (`mode:'preview'`), `improve_bullet`. Peças novas: `ConfirmItem`/`ChangeItem`/`DiffItem` no fio; pilha `_UndoOp` (LIFO); op inversa de write-back (delete + `id` guardado no `addX` + idempotency key); resolução ref→row id com desambiguação obrigatória. **Toda mutação: confirma antes, aplica, e deixa Desfazer** (decisão do fundador).

## FASE C — proativo / polimento
Sugerir próximo ganho (bullet fraco, skill pela área via `suggest-profile-skills`), celebrar shortlist-ready, extração de bloco multi-campo (card espelhando `ImportSummaryItem`), streaming.

## Telemetria (R7 — constante + emissor no mesmo PR; nunca o texto)
`trilha_assist_message_sent`, `trilha_assist_intent_classified`, `trilha_assist_answer_returned`, `trilha_assist_section_handoff`, `trilha_assist_step_conflict`, `trilha_assist_out_of_scope`, `trilha_assist_error`, `trilha_assist_clarify_requested` (Fase A). Fase B: `_edit_proposed/_applied/_cancelled/_undone`, `_destructive_confirm_*`, `_writeback_partial`, `_injection_blocked`, `_rate_limited`. Server: `trackAIGeneration({generationType:'assistant_turn'})`.

## Testes / prompt / flag
R3 unit puros (interpret injetável). R5: `PROMPT_VERSION='assistant_v1'` na edge; `generate-profile-summary` só bumpa se tocar no texto (o `mode` não toca). R4: flag OFF em prod, rollout gradual, kill-switch. Não encosta em `adapt-*` (golden_set N/A).
