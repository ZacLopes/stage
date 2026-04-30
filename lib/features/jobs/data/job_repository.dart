import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/job.dart';
import '../models/user_preferences.dart';

class JobRepository {
  final SupabaseClient _client = Supabase.instance.client;

  static const int _pageSize = 10;

  /// Fetches active jobs, filtered by user preferences and excluding already-swiped jobs.
  /// Uses Supabase's select with `companies(*)` for the JOIN.
  Future<List<Job>> fetchJobs({
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

      // 4. Apply preference filters
      if (preferences != null && !preferences.isEmpty) {
        jobs = _applyPreferenceFilters(jobs, preferences);
      }

      // 5. Paginate
      final start = page * _pageSize;
      if (start >= jobs.length) return [];
      final end = (start + _pageSize).clamp(0, jobs.length);
      return jobs.sublist(start, end);
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
  List<Job> _applyPreferenceFilters(List<Job> jobs, UserJobPreferences prefs) {
    return jobs.where((job) {
      // Filter by areas
      if (prefs.areas.isNotEmpty) {
        if (job.area == null || !prefs.areas.contains(job.area)) {
          return false;
        }
      }

      // Filter by work model
      if (prefs.workModels.isNotEmpty) {
        if (job.workModelRaw == null || !prefs.workModels.contains(job.workModelRaw)) {
          return false;
        }
      }

      // Filter by job type
      if (prefs.jobTypes.isNotEmpty) {
        if (job.jobTypeRaw == null || !prefs.jobTypes.contains(job.jobTypeRaw)) {
          return false;
        }
      }

      // Filter by location (remote always passes)
      if (prefs.locations.isNotEmpty) {
        if (job.workModelRaw != 'remoto') {
          final jobLocation = job.locationCity ?? '';
          if (!prefs.locations.any((loc) => 
            jobLocation.toLowerCase().contains(loc.toLowerCase()))) {
            return false;
          }
        }
      }

      // Filter by minimum salary
      if (prefs.minSalary != null) {
        if (job.salaryMin == null || job.salaryMin! < prefs.minSalary!) {
          return false;
        }
      }

      return true;
    }).toList();
  }
}
