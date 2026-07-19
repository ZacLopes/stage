# Fase 3 — Gate 3.0I: import/conflict wiring (o blocker confirmado do §6.1)

## Status

**Planejado** (audit read-only). NÃO iniciado em código. Branch
`refactor/ia-fase-2-fechamento`, sobre `4233882` (3.0H fatia 2). É o **maior e
mais delicado** gate restante; este plano existe para ser revisado ANTES de
codar. Flag OFF; sem operação remota.

## O blocker (confirmado, handoff §6.1)

`TrilhaChatController.applyConflicts(cardId)` (controller ~2022-2054) aplica as
escolhas aceitas **uma a uma** via `assistConflictApplier`
(`assistApplyConflictRow`), **captura exceção por linha (`catch (_) {}`)** e
**sempre** termina o card como `AssistEditStatus.applied` — mesmo que parte (ou
tudo) falhe. É falso sucesso em falha parcial.

## A RPC pronta (fundação 14/07)

`apply_reviewed_conflicts_and_promote(p_candidate_id, p_attempt_id, p_choices)`
(migration `20260714130000:1698`, sem caller Flutter):
- auth + advisory lock; valida candidata (imported/ready/attempt/payload não
  vazio/perfil protegido);
- **idempotente** por `(candidate, attempt)` + hash canônico das choices
  (recibo em `import_apply_receipts`); replay retorna o mesmo recibo;
- aplica o lote numa transação com **sub-savepoint por escolha** (item ruim é
  `rejected`, o lote segue; falha inesperada fora do laço desfaz tudo e NÃO
  promove);
- **promove** a candidata como fonte atual + cache, na MESMA transação;
- retorna agregado honesto: `{applied, stale, rejected, failed, promoted}`.
- Kinds de choice: `personal` (escalar), `add` (skill/interest/coursework/
  award/project), `add_cert`, e educação/experiência/idioma.

## O que falta ligar (escopo do gate)

1. **Plumbing de ids:** `ImportConflictItem` precisa carregar `candidate_id` e
   `attempt_id` (hoje não carrega) — trazê-los do fluxo que cria o card
   (import → revisão). Ver `loadCvConflicts`/`assistApplyConflictRow` e a
   origem em `resume_tab`.
2. **Mapa de choices:** converter cada `ConflictChoice`/`ConflictRow` aceito no
   objeto `{kind, …}` no formato EXATO da RPC (por seção). Fail-closed: uma
   linha que não mapeia não pode virar sucesso silencioso.
   **CORREÇÃO (audit 2ª passada):** os campos compostos JÁ são tratados. O RPC
   de revisão usa o helper interno `_cas_write_personal_field` (14/07:1591), que
   parte `name`→first+last, `city`→cidade/UF (+limpa CEP) e `phone`→número+DDI,
   com CAS contra o valor VIVO composto. (Eu tinha lido `cas_write_profile_scalar`
   por engano.) Portanto o kind `personal` cobre name/phone/city/summary/
   linkedin/website; **não é preciso migration de campos compostos.**
   Restam detalhes normais do mapa: `personal` precisa de `expected`
   (=`row.currentText`) e, para phone, `expected_country_code`/`country_code`;
   adições de experiência/educação têm formato próprio (espelhar a rejeição por
   data). Fail-closed: linha que não mapeia não vira sucesso silencioso.
3. **Chamada única + agregado honesto:** substituir o laço por-item por 1 RPC;
   o card reflete `{applied, stale, rejected, failed, promoted}` — **nunca**
   `applied` cego. Mensagens honestas por resultado.
4. **Undo (decisão de design):** a RPC **promove** o import. O undo atual é
   por-linha (`assistApplyConflictRow` devolve restore). Undo de um import
   PROMOVIDO ≠ desfazer campos um a um. Opções: (a) desabilitar undo do card
   reviewed (promoção é terminal); (b) um contrato de reversão de promoção
   (novo, fora deste escopo). **Precisa de decisão antes de codar.**
5. **Escalares "desde o diff" (herança do 3.0H):** `cas_write_profile_scalar`
   encaixa aqui — o "esperado" vem do diff da revisão. Cobre a parte escalar
   que ficou de fora do 3.0H.

## Testes previstos

- Harness SQL: `apply_reviewed_conflicts_and_promote` (aplica/rejeita/stale/
  promove/idempotência) — verificar se já há cobertura no promote test; senão
  adicionar.
- Flutter: mapa de choices (cada seção → objeto correto), parsing do agregado,
  o card refletindo falha parcial (NÃO applied cego), idempotência do retry.

## Riscos / condições de parada

- **Undo do reviewed** é a decisão de design aberta (item 4) — parar e decidir
  antes de codar.
- O **mapa de choices** precisa bater 1:1 com o formato da RPC por kind — alto
  cuidado (erro aqui = escolha silenciosamente perdida).
- Co-deploy: a RPC só existe na migration local 14/07 (3.0J).
- É gate grande e sensível (fluxo de import, mesmo atrás da flag) — recomendado
  como esforço FOCADO, não no fim de uma sessão longa.

## Recomendação

Fazer 3.0I como um passo focado, começando por: (1) decidir a semântica de undo
do reviewed; (2) o mapa de choices com teste; (3) a chamada única + agregado;
(4) os escalares "desde o diff". Cada sub-passo verificado antes do seguinte.
