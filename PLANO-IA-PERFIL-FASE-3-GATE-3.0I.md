# Fase 3 — Gate 3.0I: import/conflict wiring (o blocker confirmado do §6.1)

## Status

**Planejado** (audit read-only). NÃO iniciado em código. Branch
`refactor/ia-fase-2-fechamento`, sobre `4233882` (3.0H fatia 2). É o **maior e
mais delicado** gate restante; este plano existe para ser revisado ANTES de
codar. Flag OFF; sem operação remota.

## ⚠️ ACHADO CRÍTICO (18/07, "o fato vence") — o fluxo do card está DORMENTE

Verificado por grep próprio (não só pelo explorador):
- **`loadCvConflicts`** (`trilha_session.dart:286`) tem **ZERO chamadores** em `lib/`
  — só a definição. Nada o invoca em produção.
- **`assistImportCv`** (callback que criaria o `ImportConflictItem`) é declarado
  (`trilha_chat_controller.dart:524/681`) e usado (1698) mas **NUNCA atribuído**:
  o `TrilhaChatController(` do `resume_tab.dart:172` não o passa, e não há outra
  construção que passe → em produção é sempre `null` → a ação de import volta
  `failed` e **nenhum `ImportConflictItem` é criado**.
- **`attempt_id`** (= `saved_resumes.extraction_attempt_id`) tem **ZERO**
  ocorrências em `lib/` — é gerado server-side e nunca retorna ao cliente. O
  `candidate_id` só existe no caminho PERSISTIDO (`pickAndImport` →
  `CvImportResult.savedResumeId`), que é OUTRO caminho e não alimenta o card.
- O caminho do card (`loadCvConflicts`) usa extração **dry-run** (`save:false`)
  → não cria candidata → **não há candidate_id nem attempt_id em escopo** no
  `applyConflicts`.

**Consequência:** o blocker do §6.1 (`applyConflicts` marca `applied` cego) é
**real no código, mas está em código MORTO/dormente** — não pode disparar em
produção hoje. "Terminar o 3.0I" fiando o RPC exigiria: reviver o fluxo
(atribuir `assistImportCv`, chamar `loadCvConflicts` de um caminho real), trazer
`candidate_id`, **mudar o `extract-profile` para devolver `attempt_id`** (não
chega ao cliente hoje) e carregá-lo até o card. Isso é trabalho NET-NEW +
mais uma mudança de Edge — **não** é "tornar seguro um caminho que já roda".

**O que JÁ está pronto e é reutilizável:** o mapa puro `conflictRowToRpcChoice`
(todas as seções, `lang_level` incluso), testado e verificado 1:1 contra o RPC
real (promote test). Fica pronto para o dia em que o fluxo for revivido.

**Decisão do fundador (pendente):** (a) parar o 3.0I aqui e ir para caminhos
VIVOS; (b) reviver+fiar o fluxo inteiro (net-new + Edge); (c) só deixar o código
morto fail-closed como salvaguarda. Ver relatório.

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

## Mapa de choices — SPEC COMPLETO (audit fechado)

Fonte: `ConflictChoice` (`.row`, `.effectiveValue`) + `ConflictRow`
(`section, kind, field, value, currentText, extra, refId, cvItem`). `value` do
choice = `effectiveValue` (editado); `source` = `row.value` (valor ORIGINAL,
para o vínculo com o payload). Por seção:

| Seção (kind) | Choice `{...}` |
|---|---|
| name/phone/city/summary/linkedin/website (conflict) | `{kind:'personal', field:row.field, expected:row.currentText, value:effectiveValue}` (+ phone: `expected_country_code`/`country_code` se a linha carregar) |
| skill/interest/coursework/award/project (addition) | `{kind:'add', section:row.section.name, value:effectiveValue, source:row.value}` |
| certification (addition) | `{kind:'add_cert', name:effectiveValue, issuer:row.extra?, source:row.value}` |
| language (addition) | `{kind:'add_lang', name:effectiveValue, source:row.value}` (nível vem do payload, NÃO do cliente) |
| language (conflict de nível) | `{kind:'lang_level', name:effectiveValue, expected:<ID do nível observado>}` — **ver LACUNA abaixo** |
| experience (conflict) | `{kind:'item_field', section:'experience', field:row.field, expected:row.currentText, value:effectiveValue, ref_id:row.refId}` |
| experience (addition) | `{kind:'add_experience', company:cvItem.company, title:cvItem.title}` |
| education (conflict) | `{kind:'item_field', section:'education', field:row.field, expected:row.currentText, value:effectiveValue, ref_id:row.refId}` |
| education (addition) | `{kind:'add_education', institution:cvItem.institution, degree:cvItem.degree}` |

**LACUNA (decisão pendente) — `lang_level`:** o RPC exige `expected` = o **ID**
do nível observado (ex.: `basic`). A `ConflictRow` de conflito de idioma só tem
`currentText` = **rótulo** (`existing.proficiencyLabel`, ex.: "Avançado") e
`extra` = o novo id do CV — não o id observado. Opções: (a) adicionar o id
observado à `ConflictRow` (mexe em `cv_conflict.dart` detecção); (b) traduzir
rótulo→id (frágil); (c) manter conflito de nível no caminho legado por ora.

**Verificação obrigatória antes de fiar:** rodar CADA tipo de choice mapeado
pelo `apply_reviewed_conflicts_and_promote` REAL num harness SQL (aplica/
rejeita/stale) — pega qualquer erro do mapa contra a RPC de verdade, não contra
o entendimento.

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
