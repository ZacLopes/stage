// Catálogo de áreas de atuação — 13 categorias usadas em:
//   - Onboarding (DesiredTitlesScreen): user escolhe quais áreas quer
//   - Aba Preferências (PreferencesTab): edição pós-onboarding
//   - Match score: cruza essa lista com `area` das vagas no banco
//
// ─────────────────────────────────────────────────────────────────────
// ⚠️ SINCRONIZAÇÃO CROSS-LANGUAGE — LEIA ANTES DE EDITAR
// ─────────────────────────────────────────────────────────────────────
//
// Essas categorias precisam existir TAMBÉM no backend pro pipeline de
// sync de vagas classificar vagas com áreas que o user consiga escolher.
// A função de classificação está em:
//
//   supabase/functions/_shared/jobs.ts → `inferArea`
//
// Se mudar essa lista (adicionar/remover/renomear área):
//   1. Atualiza aqui (Dart)
//   2. Atualiza o regex em `inferArea` (TypeScript)
//   3. Sem isso, o user pode:
//      - escolher área nova que nenhuma vaga tem (feed vazio), ou
//      - perder vagas porque elas caem em "Geral" sem categoria correta
//
// DRIFT ATUAL CONHECIDO (2026-05-26):
//   • "Design" existe aqui no Dart mas NÃO tem categoria própria no
//     backend — `inferArea` em jobs.ts classifica vagas de design como
//     "Produto" (regex inclui "design|ux|ui").
//
//     Por que isso ainda funciona: FilterHelpers._areaSynonyms em
//     features/jobs/utils/filter_helpers.dart mapeia Design ↔ Produto
//     bidirecionalmente. User que escolhe "Design" vê todas as vagas
//     de Produto (incluindo as 8 que mencionam design no título).
//
//     Trade-off: "Design" vira sinônimo grosso de "Produto" — user que
//     quer SÓ design vê também Product Manager, Estágio de Produto, etc.
//     Pra ter filtro estrito de Design, precisaria:
//       1. Adicionar regex próprio em `inferArea` (jobs.ts)
//       2. Reclassificar vagas existentes via SQL
//       3. Remover Design dos sinônimos de Produto em filter_helpers.dart
//     Decisão pendente — sem urgência porque o fluxo atual funciona.

import 'package:flutter/material.dart';

class JobArea {
  final String label;
  final IconData icon;
  const JobArea(this.label, this.icon);
}

const List<JobArea> kJobAreas = <JobArea>[
  JobArea('Tecnologia', Icons.computer_rounded),
  JobArea('Engenharia', Icons.engineering_rounded),
  JobArea('Design', Icons.palette_rounded),
  JobArea('Produto', Icons.widgets_rounded),
  JobArea('Marketing', Icons.campaign_rounded),
  JobArea('Vendas', Icons.trending_up_rounded),
  JobArea('Finanças', Icons.attach_money_rounded),
  JobArea('Recursos Humanos', Icons.groups_rounded),
  JobArea('Operações', Icons.settings_rounded),
  JobArea('Jurídico', Icons.gavel_rounded),
  JobArea('Administrativo', Icons.folder_rounded),
  JobArea('Saúde', Icons.local_hospital_rounded),
  JobArea('Geral', Icons.work_rounded),
];

/// Lista só dos labels — útil pra validação ("a área X está no catálogo?").
List<String> get kJobAreaLabels => kJobAreas.map((a) => a.label).toList();
