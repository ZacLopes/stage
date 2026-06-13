// feed_parity — lado CLIENT do harness (Fase 2, T2.1).
//
// Roda o pipeline Dart REAL sobre o snapshot de prod:
//   fetchJobsWithDiagnostics (exclui swipadas + deadline vencida)
//   → _loadProfilePrefs (relacional → prefs; work_mode EN→PT)
//   → _applyPreferenceFilters (FilterHelpers — IMPORT DIRETO do app).
// Saída por usuário: count + md5 dos ids ordenados (mesmo formato do
// rpc_parity.sql — comparar linha a linha).
//
// Uso: dart run tools/feed_parity/parity_check.dart tools/feed_parity/snapshot.json
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:career_gamification/features/jobs/utils/filter_helpers.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'tools/feed_parity/snapshot.json';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('snapshot não encontrado: $path (rode fetch_snapshot.sql antes)');
    exit(1);
  }
  final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  // O execute_sql devolve [{"snapshot": {...}}]; o Studio devolve o objeto.
  final snapshot = root.containsKey('snapshot')
      ? root['snapshot'] as Map<String, dynamic>
      : root;

  final jobs = (snapshot['jobs'] as List).cast<Map<String, dynamic>>();
  final users = (snapshot['users'] as List).cast<Map<String, dynamic>>();
  final now = DateTime.now();

  print('snapshot: ${snapshot['fetched_at']}  jobs ativas: ${jobs.length}');
  print('user_id                               n    md5');

  for (final u in users) {
    final swiped =
        (u['swiped_job_ids'] as List).map((e) => e.toString()).toSet();

    // fetchJobsWithDiagnostics: is_active já garantido no snapshot;
    // exclui swipadas e deadline vencida (job_repository.dart:81-96).
    var candidates = jobs.where((j) {
      if (swiped.contains(j['id'])) return false;
      final dl = j['deadline'] as String?;
      if (dl != null) {
        final d = DateTime.tryParse(dl);
        if (d != null && d.isBefore(now)) return false;
      }
      return true;
    }).toList();

    // _loadProfilePrefs (jobs_viewmodel.dart:480-570): listas com check de
    // vazio CRU (isNotEmpty, sem trim) — espelhado também no RPC.
    final areas = (u['desired_titles'] as List)
        .map((e) => e?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    final jp = u['job_preferences'] as Map<String, dynamic>?;
    final locations = <String>[];
    final primaryCity = jp?['primary_location_city']?.toString();
    if (primaryCity != null && primaryCity.isNotEmpty) {
      locations.add(primaryCity);
    }
    for (final c in (u['other_locations'] as List)) {
      final s = c?.toString();
      if (s != null && s.isNotEmpty) locations.add(s);
    }

    final workModels =
        ((jp?['work_mode'] as List?)?.cast<dynamic>() ?? const []).map((wm) {
      final s = wm.toString();
      switch (s) {
        case 'remote':
          return 'remoto';
        case 'hybrid':
          return 'hibrido';
        case 'in_person':
          return 'presencial';
        default:
          return s; // já em PT ou desconhecido
      }
    }).toList();

    final jobTypes = (jp?['job_types'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    final hasPrefs = !(areas.isEmpty &&
        locations.isEmpty &&
        workModels.isEmpty &&
        jobTypes.isEmpty);

    // _applyPreferenceFilters (job_repository.dart:161-176); minSalary é
    // null no relacional (morreu no merge F1 — fato B9 do plano).
    if (hasPrefs) {
      candidates = candidates.where((j) {
        final workModelRaw = j['work_model'] as String?;
        if (!FilterHelpers.isAreaMatch(j['area'] as String?, areas)) {
          return false;
        }
        if (!FilterHelpers.isWorkModelMatch(workModelRaw, workModels)) {
          return false;
        }
        if (!FilterHelpers.isJobTypeMatch(j['job_type'] as String?, jobTypes)) {
          return false;
        }
        if (!FilterHelpers.isLocationMatch(
          userLocations: locations,
          jobCity: j['location_city'] as String?,
          jobState: j['location_state'] as String?,
          workModelRaw: workModelRaw,
        )) {
          return false;
        }
        if (!FilterHelpers.isSalaryMatch(j['salary_min'] as int?, null)) {
          return false;
        }
        return true;
      }).toList();
    }

    final ids = candidates.map((j) => j['id'] as String).toList()..sort();
    final digest = md5.convert(utf8.encode(ids.join(','))).toString();
    print('${u['user_id']}  ${ids.length.toString().padLeft(3)}  $digest');
  }
}
