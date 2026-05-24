# Inventário de cleanup v1 — pós-Semana 3

> **NÃO REMOVER NADA AQUI NA SEMANA 3.** Este doc é input pra Semana 4,
> quando os flags v2 atingirem 100% e tivermos dashboards confirmando
> paridade. `raw_text` em particular continua no banco como fallback
> eterno mesmo após Semana 4 — apenas os call sites em **código novo**
> são candidatos a remoção.

Gerado em 2026-05-23 via:

```bash
grep -rn "raw_text\|imported_resume\|gamification_data" career_gamification/lib/
grep -rn "raw_text\|imported_resume\|gamification_data" career_gamification/supabase/functions/
```

Total: **53 menções em 14 arquivos** lib/ + edge functions:
adapt-resume-to-job (32), analyze-match (6), parse-cv-pdf (?),
extract-profile (?), generate-summary (?), generate-bullets (?),
extract-job-skills (?), parse-cv (?), parse-cv-vision (?),
daily-report/queries (?), _shared/cv_text (?), _shared/cv_schema (?),
_shared/profile_schema (?).

## Edge functions

| Arquivo | Linhas | Uso | Status Semana 3 | Decisão Semana 4 |
|---|---|---|---|---|
| `supabase/functions/extract-profile/index.ts` | múltiplas | Lê CV bruto (raw_text input), grava `gamification_data.imported_resume.raw_text` + 18 tabelas | **MANTER FOREVER** — extract-profile é o único point que LEGITIMAMENTE escreve `raw_text` (fonte original do CV importado) | Não tocar |
| `supabase/functions/parse-cv-pdf/index.ts` + `parse-cv/index.ts` + `parse-cv-vision/index.ts` | múltiplas | Deprecated mas mantidos como fallback do extract-profile | Manter dormente | Avaliar remoção se extract-profile estável por 60 dias |
| `supabase/functions/adapt-resume-to-job/index.ts` | 2.874 | Lê `gamification_data` + pre-parser de raw_text como input principal | **TARGET DO BLOCO C v2** — Semana 3 substitui leitura por schema relacional, mantém fallback raw_text | Após `adapt_v2_enabled` em 100% por 30 dias: remover pre-parser de raw_text (~400 linhas) |
| `supabase/functions/analyze-match/index.ts` | 504 | Lê `whoIAm.derived` + raw_text do `gamification_data` | **TARGET DO BLOCO D v2** — Semana 3 substitui por `profile_skills`/`profile_personal.summary`, fallback raw_text só pra órfãos | Após `match_v2_enabled` em 100%: remover blocos cenário A/B do CV-only legacy |
| `supabase/functions/generate-bullets/index.ts` | múltiplas | Lê `gamification_data` pra contexto de geração | Manter — bullets ainda escrevem em `bullet_versions` legacy (forward-only desde 2026-05-23) | Manter dual-write até cleanup geral de bullets legacy |
| `supabase/functions/generate-summary/index.ts` | múltiplas | Lê `gamification_data` pra gerar summary | Não tocar Semana 3 | Avaliar refactor pra `profile_personal` + `profile_experiences` quando schema estabilizar |
| `supabase/functions/extract-job-skills/index.ts` | múltiplas | Provavelmente lê descrição da vaga, não user data | Verificar | Provavelmente sem refator necessário |
| `supabase/functions/daily-report/queries.ts` | múltiplas | Query agregada de `gamification_data` pra métricas all-time | Manter — métricas históricas precisam da fonte legacy enquanto coexistir | Refazer queries pra `profile_*` quando todas as features lerem do schema |
| `supabase/functions/_shared/cv_text.ts` | múltiplas | `flatten()`, `jaroWinklerSimilarity()` usadas pelo adapt-resume-to-job pra validação anti-invenção | **MANTER** — utilitário compartilhado, não acopla a v1 | Não remover |
| `supabase/functions/_shared/cv_schema.ts` | múltiplas | Schema TS do `imported_resume.parsed` JSONB | Manter Semana 3 (extract-profile + parse-cv ainda usam) | Manter — schema é fonte do format JSON do raw output |
| `supabase/functions/_shared/profile_schema.ts` | múltiplas | Schema TS do JSON estruturado novo (sai do extract-profile, alimenta save_profile_from_json) | **MANTER FOREVER** — schema é interface do mundo profile-first | Não tocar |

## Flutter (lib/)

| Arquivo | Linhas chave | Uso | Status Semana 3 | Decisão Semana 4 |
|---|---|---|---|---|
| `lib/services/cv_import_service.dart` | 56, 61, 129, 145-155, 167, 202, 217, 224-237, 290 | Pipeline de import — extrai PDF→texto, persiste em `gamification_data.imported_resume.raw_text`, chama `parse-cv` | **MANTER** — é o entrypoint legítimo do raw_text (fonte original) | Não remover |
| `lib/features/auth/user_viewmodel.dart` | 47, 58 | Lê `imported_resume` na checagem de "tem CV importado?" | Manter — checagem rápida sem precisar de query relacional | Substituir por check em `profile_personal.profile_source = 'imported'` quando confiável |
| `lib/data/supabase_repository.dart` | múltiplas | Persistência de `gamification_data` (whoIAm, imported_resume) via update no `user_profiles` | Manter Semana 3 — trilha gamificada ainda escreve aqui (não é alvo desta semana) | Refator pra escrever em `profile_*` quando trilha for migrada |
| `lib/data/models/models.dart` | classe `UserProfile.gamificationData` | Modelo legacy JSONB | Manter — usado em 50+ lugares; remoção é trabalho dedicado | Substituir gradual por entities de `lib/features/profile/domain/entities/` |
| `lib/services/cv_content_validator.dart` | (não listado mas referencia) | Validação se um upload é CV (não LinkedIn, não foto) | Manter — agnóstico ao formato de armazenamento | Não tocar |
| `lib/features/profile/application/extraction_status_view_model.dart` | múltiplas | Tracker de progresso da extração — lê `profile_extraction_logs` (já profile-first!) + status do JSONB legacy | Manter dual-read enquanto extract-profile gera ambos | Remover leitura JSONB quando logs sustentarem 100% das telas |
| `lib/features/jobs/utils/match_score.dart` | múltiplas | Fallback determinístico do match (executado quando edge function `analyze-match` falha) | Mantém leitura `gamification_data` enquanto match v2 ainda tem fallback raw_text | Após D 100%: refator pra ler `profile_*` |
| `lib/features/jobs/models/adapted_resume.dart` | múltiplas | Modelo do CV adaptado — herda estrutura do `gamification_data` legacy | Mantém Semana 3 | Refator quando adapt v2 estável |
| `lib/features/jobs/widgets/adapted_resume_preview_screen.dart` | múltiplas | UI de preview do CV adaptado — chama `PdfService.generateResumeBytes` direto (não passa pelo `ResumeRenderer`) | **TODO esta semana**: wirear pelo renderer pra que CV adaptado também respeite a flag `templates_v2_enabled` | Sem dependência v1 após wiring |
| `lib/features/jobs/widgets/resume_adaptation_sheet.dart` | múltiplas | Caller que dispara adapt-resume-to-job edge function | Espera Bloco C — quando edge function v2 estiver pronta, atualizar payload pra `{user_id, job_id}` | Remover construção de `raw_text` payload |
| `lib/features/jobs/jobs_viewmodel.dart` + `jobs_swipe_screen.dart` | múltiplas | Leitura de match score / contexto pra UI de vagas | Manter — leituras são via campos do `match_analyses` (já cacheada), não direto de gamification_data | Não precisa cleanup |
| `lib/features/jobs/models/job_skills_extraction.dart` | múltiplas | Modelo de skills extraídas da vaga (não do user) | Manter — não é dado de candidato | Sem ação |
| `lib/services/analytics_service.dart` | 1 menção | Provavelmente `track` com prop `gamification_data` (instrumentação) | Manter | Sem ação |
| `lib/features/resume/data/profile_pdf_data_loader.dart` | 0 (criado nesta semana) | NOVO da Semana 3 — fonte profile-first dos PDFs | N/A — é o substituto v2 | N/A |

## Critério de remoção pra cada categoria

1. **Edge function v2 (adapt + match)**: remover fallback raw_text só quando:
   - Flag em 100% por ≥30 dias
   - Dashboards confirmando paridade ≥95% (não pode regredir)
   - Zero rollback executado no período

2. **Models JSONB (UserProfile.gamificationData, AdaptedResume legacy)**:
   - Espera Semana 4-5
   - Refator carrega risco — schedule pra janela de baixa atividade

3. **`raw_text` no banco** (`user_profiles.gamification_data.imported_resume.raw_text`):
   - **NUNCA REMOVER**. Continua como fallback eterno + auditoria.

4. **Tabelas dormentes**:
   - `profile_coursework` (148 entries migrados pra `profile_skills` em 2026-05-22) → manter dormente
   - `user_experiences`, `experience_raw_responses`, `bullet_versions` (rows=0) → candidatos a DROP quando confirmar zero escritas por 30 dias

## Próximos passos

Esta lista vai ser revisitada na Semana 4 com os números atualizados de
rollout. Antes de remover qualquer item, fazer PR específico de cleanup
com:

1. Verificação por grep de zero usos no código.
2. Migration SQL com `DROP COLUMN`/`DROP TABLE` separada.
3. Backup snapshot da tabela antes de qualquer DROP destrutivo.
