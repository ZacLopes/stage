# PLANO-FASE-7 · Onda 2 — Destravar a venda (consent in-app + export v2)

> **Status:** ESCOPO REVISADO pelo fundador (06/07) e IMPLEMENTADO na branch `fase-7-onda-2-venda` — aguardando aprovação de deploy.
> **Antecede:** Onda 1 (higiene) — flip match v13, COALESCE de cidade, candidaturas de `applications`. **EM PROD** (edges deployadas, PR #15 aberto).
> **Fonte:** `ANALISE-COLETA-MATCH-SHORTLIST.md` (seções C, J.6, J.7, E4-15, K1.1, K2.10, K2.11, K3.8).

---

## 0. Escopo revisado (decisões do fundador, 06/07) — o que vale sobre as seções abaixo

Este é um **teste** do modelo de negócio (ainda não é a operação comercial validada), então o fundador enxugou o escopo:

**FEITO (nesta branch):**
- **Frente A — Export v2 (T-A1..A4):** CSV rico (curso/instituição/semestre/formatura/nível/modalidade/tipo/cargo desejado/idiomas/skills/LinkedIn/disponibilidade/resumo/**score/motivo**/**link do CV**), sanitização anti-injeção de fórmula, filtro de e-mail sintético e de conta de teste interna.
- **Export IGNORA o consent** — sem gate de `granted` (decisão consciente; LGPD reconhecida, mas é teste).
- **Frente C parcial:** **cliente obrigatório** na criação de lista (T-C2) + `client_id` no log de export; **resultado por candidato** (T-C3, `outcome` + controle no admin).

**FORA (decisão do fundador):**
- ❌ Backfill de headline/resumo dos usuários **antigos/inativos** (T-A6) — não são mais ativos nem buscam estágio; o foco é a base ficar pronta pros **novos** (o pipeline da trilha enche os perfis que chegam).
- ❌ Toda a **Frente B** (telinha de consent no app), banner, push, campanha retroativa (T-C4).
- ❌ **Ciclo de vida do consent** (T-C1: expired/expires_at/histórico).

O restante do documento (seções 1–8) é o plano original completo — mantido como referência; onde divergir desta seção 0, **vale a seção 0**.

---

## 1. Objetivo

Transformar a shortlist de **artefato não-vendável** em **produto de triagem defensável**, atacando os dois gargalos terminais da cadeia coleta→venda:

1. **Consent** — hoje **2 candidatos** `granted` em 1.715 (0,12%), coletados à mão por WhatsApp. O universo exportável de QUALQUER lista é ≤2. É o bloqueador nº 1 da receita.
2. **Apresentação** — o CSV entrega 7 campos (`nome;email;telefone;cidade;estado;headline;skills`), sem score, sem justificativa, sem educação, sem CV — e `headline` existe em só 10,7% da base. Uma lista telefônica, não uma shortlist.

**Meta mensurável:** universo exportável por lista de ≤2 → **≥30% da coorte ativa (60d)**; CSV de 7 campos → entregável com educação + score + justificativa + link de CV; 0 vazamentos de PII fora do escopo consentido.

## 2. Fatos que ancoram o plano (verificados)

- [FATO] O schema `candidate_data_sharing_consents` **já aceita `granted_via='in_app'`** (migration 20260610160200) — falta só o app perguntar. Zero referência a consent em `lib/`.
- [FATO] O export exige `status='approved'` E consent `granted` (`admin-candidate-lists/index.ts:522`) — gate LGPD correto; o que falta é coleta.
- [FATO] O export **ignora o array `scope`** (default `{contact_info}`) e mesmo assim exporta headline+skills → excede o escopo consentido.
- [FATO] `csvEscape` só duplica aspas → **injeção de fórmula** no Excel do RH (campos controlados pelo candidato começando com `=`,`+`,`-`,`@`).
- [FATO] O export já **carrega educação e desiredTitles** em `buildCandidateProfiles` e os **descarta** nos headers; `score_breakdown` existe por item e não sai; 1.284 CVs em `saved_resumes` sem link.
- [FATO] `employer_clients` = 0 rows; a operação B2B roda sem entidade cliente.
- [FATO] E-mail sintético (`phone_*@stage.app`) pode vazar no CSV; a base tem `education_level='school'` (possíveis menores de 18).

## 3. Escopo — 3 frentes por dependência de release

A separação é deliberada: a **Frente A entrega valor SEM esperar release de app** (é só edge/SQL, como a Onda 1). A Frente B precisa do próximo build. A Frente C amarra o funil comercial.

### Frente A — Export v2 + higiene do gate (SERVER, sem release) 🟢

Deployável imediatamente. Faz cada consent futuro valer muito mais.

- **T-A1 · CSV v2 rico.** Adicionar ao export: `curso;instituicao;semestre;previsao_formatura;nivel;modalidade;tipo;idiomas;linkedin;disponibilidade;score;motivo`. Curso via `degree`+majors (mesma união do fix de busca da Onda 1). `motivo` = 2-3 bullets derivados do `score_breakdown` (já persistido) ou das `reasons` do `analyze-match` v13. ONDE: `admin-candidate-lists` export. POR QUÊ: responde as 3 perguntas do RH ("serve? por que ele? consigo agir?").
- **T-A2 · Link assinado do CV.** Signed URL de `saved_resumes` (expira 7-14 dias, auditada) como coluna do CSV, só sob consent. ONDE: edge. POR QUÊ: o CV é o artefato que o RH realmente avalia; já está no bucket.
- **T-A3 · Respeitar `scope`.** Export filtra campos pelo array `scope` do consent (contact_info / resume / profile_summary). Sem escopo suficiente → coluna vazia, não vaza. ONDE: edge. LGPD.
- **T-A4 · Sanitização anti-fórmula** (prefixo `'` em campos começando com `=`,`+`,`-`,`@`) + **filtrar e-mail sintético** (troca por vazio/telefone) + **excluir conta interna de teste** + **bloquear export de menores de 18** (DOB já coletada). ONDE: edge + `_shared/admin.ts`.
- **T-A5 · Resumo comercial por candidato (opcional, IA).** Reusar `generate-profile-summary` com prompt "para recrutador" (2-3 linhas), sob revisão do admin, cacheado. ONDE: edge + admin UI. POR QUÊ: é a linha que humaniza a lista.
- **T-A6 · Backfill de headline/summary por IA** nos ~773 perfis com experiência (headline hoje 10,7%). ONDE: job batch. POR QUÊ: enche a vitrine antes do 1º export v2.

### Frente B — Consent in-app (CLIENT, próximo release) 🔴

O desbloqueio real. Precisa de build — pode ir junto do **+10** ou num build dedicado.

- **T-B1 · Sheet de consent no 1º like/apply.** Não-bloqueante, 1 tap, momento de intenção máxima: *"Quer que empresas te encontrem? Quando seu perfil combinar com uma vaga, o Stage pode te indicar direto — a empresa recebe seu nome, contato e currículo."* → grava `granted`/`asked`, `granted_via='in_app'`, `scope` conforme copy. ONDE: `lib/features/jobs`. LGPD: opt-in explícito, propósito determinado, nunca pré-marcado.
- **T-B2 · Toggle em Perfil→Privacidade** (revogação a qualquer tempo, art. 8º §5º) + registro de `consent_text_version` + timestamp (art. 8º §2º, ônus da prova do controlador). ONDE: `lib/features/settings`/profile.
- **T-B3 · Benefício explícito** ligando lacuna→shortlist na tela final do onboarding e na trilha ("perfis 80%+ entram nas listas que enviamos"). Aumenta a taxa de aceite do consent. ONDE: onboarding/trilha.

### Frente C — Máquina de estados + memória comercial (SERVER + ops) 🟡

- **T-C1 · Ciclo de vida do consent.** Adicionar `expired` + `expires_at` (12 meses, re-ask 30d antes); histórico append-only (**parar de apagar `granted_at` na revogação** — bug atual em `admin-users`); export valida `granted AND expires_at > now()`. ONDE: migration + edges.
- **T-C2 · `employer_clients` de verdade.** Cliente obrigatório na criação de lista (criação inline); `client_id` no `candidate_list_exports` (rastreabilidade LGPD de PARA QUEM cada PII foi). ONDE: admin + migration.
- **T-C3 · Outcome por item.** `interviewed/hired/rejected` em `candidate_list_items` (ou `placement_outcomes`) — o único ground truth do valor da shortlist e base de pricing por resultado. ONDE: admin (+ futuro: empresa).
- **T-C4 · Campanha retroativa de consent.** Push + banner na Home pra base existente (1.7k) — **depende da Frente B** (precisa da UI de consent). Mesmo 20% de aceite ≈ 340 exportáveis (170× o de hoje). ONDE: OneSignal + app.

## 4. Aceites medidos (R1 — "verificado, não declarado")

- **A1 (Frente A):** um export de shortlist de teste sai com todas as colunas novas preenchidas para um candidato com perfil rico; e-mail sintético/menor de 18/conta interna **não** aparecem; um candidato com nome começando por `=` sai sanitizado (`'=`). Colado no relatório.
- **A2 (scope):** candidato com consent `scope={contact_info}` exporta contato mas **não** headline/skills; com `scope` ampliado, exporta. Query + export colados.
- **A3 (Frente B):** conta interna dá 1 like → sheet aparece → aceita → `SELECT` mostra row `granted`, `granted_via='in_app'`, `scope` correto; toggle em Privacidade revoga e o export deixa de incluí-lo.
- **A4 (Frente C):** revogar consent **preserva** `granted_at` no histórico; export de lista sem cliente é bloqueado até vincular `employer_clients`.
- **KPI de negócio:** % exportável da coorte ativa 60d (baseline 0,12%) medido antes/depois da Frente B.

## 5. LGPD (base legal e limites)

- Base legal = **consentimento** (art. 7º I), destacado, específico e informado (art. 8º §4º), **revogável** (art. 8º §5º).
- Menores: base tem ensino médio → possíveis <18 (art. 14 exige melhor interesse + consentimento parental) → **bloquear export de <18** até tratamento específico (T-A4).
- Rastreabilidade do compartilhamento (`client_id` por export, T-C2).
- Escopo do consent deve cobrir "perfil profissional + currículo" — não só `contact_info` (corrigir a copy do consent e o gate juntos).

## 6. Flags & rollout (R4)

- Export v2 atrás de flag de admin (`export_v2`) ou versão de template — rollout direto (admin é interno).
- Consent sheet (Frente B) atrás de flag `consent_prompt_v1` (10→50→100).
- Campanha retroativa (T-C4) só após Frente B em 100% + validação device.

## 7. O que NÃO fazer nesta onda (evitar over-engineering)

- **Portal B2B completo** (auth, self-service, dashboards) — o CSV v2 + futuro link-web (Onda 3) entregam 80% por 5% do custo.
- **Consent por-empresa** — exige portal; nesta onda é consent geral com escopo de campos + log por export. Por-empresa vira premium depois.
- **Reintroduzir pretensão salarial** — no máximo como INFORMAÇÃO opcional na shortlist, nunca dimensão de match (decisão "realismo > inflação" mantida).
- Depender do build +10 para a Frente A — ela é server-only de propósito.

## 8. Dependências e sequência sugerida

```
Já (server, sem release):   Frente A (T-A1..A6) + T-C1/T-C2 (migrations)  → deploy + aceites
Próximo build de app:       Frente B (T-B1..B3)  → rollout consent_prompt_v1
Após consent no ar:         T-C4 (retroativo) + T-C3 (outcome)  → medir KPI exportável
```

**Regra de corte:** tudo que destrava export vendável (Frente A) vence tudo que é cosmético; a Frente B é o gargalo de receita e deve pegar o próximo release disponível (não esperar um build "perfeito").

---

*Aprovação do fundador pendente. Ao aprovar: branch `fase-7-onda-2-venda`, PRs pequenos por frente (R8), golden_set N/A (não toca adapt), migrations via CLI (R2).*
