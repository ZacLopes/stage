import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/job.dart';
import '../models/user_preferences.dart';
import '../utils/filter_helpers.dart';

/// Resultado da fetch: lista paginada + diagnóstico do filtro pra UI poder
/// distinguir "esgotou as vagas" de "filtros muito restritos".
class JobFetchResult {
  final List<Job> jobs;

  /// Total de vagas ativas disponíveis (antes dos filtros, depois de excluir
  /// swipadas e expiradas). Se isto > 0 e jobs vazio = filtros zeraram tudo.
  final int totalAvailable;

  /// Total que sobrou depois dos filtros do user, antes da paginação.
  final int totalAfterFilters;

  const JobFetchResult({
    required this.jobs,
    required this.totalAvailable,
    required this.totalAfterFilters,
  });
}

class JobRepository {
  final SupabaseClient _client = Supabase.instance.client;

  static const int _pageSize = 10;

  /// Fetches active jobs, filtered by user preferences and excluding already-swiped jobs.
  /// Uses Supabase's select with `companies(*)` for the JOIN.
  Future<List<Job>> fetchJobs({
    UserJobPreferences? preferences,
    int page = 0,
  }) async {
    final result = await fetchJobsWithDiagnostics(
      preferences: preferences,
      page: page,
    );
    return result.jobs;
  }

  /// Versão "enriquecida" do fetch: retorna também contadores que a UI usa
  /// pra mostrar mensagem certa no empty state.
  Future<JobFetchResult> fetchJobsWithDiagnostics({
    UserJobPreferences? preferences,
    int page = 0,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // 1. Fetch swiped job IDs first so we know what to exclude
      final swipedResponse = await _client
          .from('swipe_actions')
          .select('job_id')
          .eq('user_id', userId);

      final Set<String> swipedJobIds = (swipedResponse as List)
          .map((e) => e['job_id'] as String)
          .toSet();

      // 2. Fetch active jobs with company data
      final response = await _client
          .from('jobs')
          .select('*, companies(*)')
          .eq('is_active', true)
          .order('published_at', ascending: false);

      final List<dynamic> data = response as List;
      final now = DateTime.now();

      // 3. Parse, filter expired deadlines and swiped, then apply preferences
      List<Job> jobs = data
          .where((json) {
            // Exclude already swiped jobs
            if (swipedJobIds.contains(json['id'])) return false;
            // Exclude expired deadlines
            final deadline = json['deadline'] as String?;
            if (deadline != null) {
              final deadlineDate = DateTime.tryParse(deadline);
              if (deadlineDate != null && deadlineDate.isBefore(now)) {
                return false;
              }
            }
            return true;
          })
          .map((json) => Job.fromJson(Map<String, dynamic>.from(json)))
          .toList();

      final totalAvailable = jobs.length;

      // 4. Apply preference filters
      if (preferences != null && !preferences.isEmpty) {
        jobs = _applyPreferenceFilters(jobs, preferences);
      }

      final totalAfterFilters = jobs.length;

      // 5. Paginate
      final start = page * _pageSize;
      if (start >= jobs.length) {
        return JobFetchResult(
          jobs: const [],
          totalAvailable: totalAvailable,
          totalAfterFilters: totalAfterFilters,
        );
      }
      final end = (start + _pageSize).clamp(0, jobs.length);
      return JobFetchResult(
        jobs: jobs.sublist(start, end),
        totalAvailable: totalAvailable,
        totalAfterFilters: totalAfterFilters,
      );
    } catch (e) {
      print('Error fetching jobs: $e');
      rethrow;
    }
  }

  /// Fetches a single job with full company details.
  Future<Job?> getJobById(String id) async {
    try {
      final response = await _client
          .from('jobs')
          .select('*, companies(*)')
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return Job.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      print('Error fetching job by ID: $e');
      rethrow;
    }
  }

  /// Applies user preference filters on already-fetched jobs.
  ///
  /// Filtros são **permissivos no null**: se um campo da vaga é null, não
  /// excluímos por causa daquele filtro. Isso evita perder vagas legítimas
  /// vindas de fontes externas (Greenhouse/Lever/Apify) onde `area`,
  /// `salary_min`, `location_city` etc. podem vir vazios.
  ///
  /// Toda comparação textual (área, localização) passa por
  /// [FilterHelpers.normalize] (acento-insensível) e considera sinônimos
  /// (ex: "RH" ↔ "Recursos Humanos") e mapeamento cidade↔estado.
  List<Job> _applyPreferenceFilters(List<Job> jobs, UserJobPreferences prefs) {
    return jobs.where((job) {
      if (!FilterHelpers.isAreaMatch(job.area, prefs.areas)) return false;
      if (!FilterHelpers.isWorkModelMatch(job.workModelRaw, prefs.workModels)) return false;
      if (!FilterHelpers.isJobTypeMatch(job.jobTypeRaw, prefs.jobTypes)) return false;
      final locationOk = FilterHelpers.isLocationMatch(
        userLocations: prefs.locations,
        jobCity: job.locationCity,
        jobState: job.locationState,
        workModelRaw: job.workModelRaw,
      );
      if (!locationOk) return false;
      if (!FilterHelpers.isSalaryMatch(job.salaryMin, prefs.minSalary)) return false;
      return true;
    }).toList();
  }
}
