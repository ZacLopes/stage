import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/application.dart';

/// CRUD de `applications` (Fase 1). A máquina de estados é validada no
/// banco (trigger); aqui só fazemos as operações que o actor `user` pode:
/// criar (external_confirmed/manual), mover o próprio pipeline e reabrir.
class ApplicationsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Todas as applications do user, mais recentes primeiro.
  Future<List<Application>> fetchForUser(String userId) async {
    final rows = await _client
        .from('applications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => Application.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Marca a vaga como aplicada: cria a application `external_confirmed`
  /// ou — se já existe uma row pra (user, job), p.ex. withdrawn de um
  /// toggle anterior — REABRE (unicidade parcial: nunca segunda row).
  /// Retorna a application resultante e se foi reabertura.
  Future<({Application application, bool reopened})> markApplied({
    required String userId,
    required String jobId,
    String? applicationMethod,
  }) async {
    final existing = await _client
        .from('applications')
        .select()
        .eq('user_id', userId)
        .eq('job_id', jobId)
        .maybeSingle();

    if (existing != null) {
      final app = Application.fromJson(Map<String, dynamic>.from(existing));
      if (app.status.countsAsApplied) return (application: app, reopened: false);
      final updated = await _client
          .from('applications')
          .update({'status': ApplicationStatus.submitted.db})
          .eq('id', app.id)
          .select()
          .single();
      return (
        application: Application.fromJson(Map<String, dynamic>.from(updated)),
        reopened: true,
      );
    }

    final inserted = await _client
        .from('applications')
        .insert({
          'user_id': userId,
          'job_id': jobId,
          'type': ApplicationType.externalConfirmed.db,
          'status': ApplicationStatus.submitted.db,
          if (applicationMethod != null) 'application_method': applicationMethod,
        })
        .select()
        .single();
    return (
      application: Application.fromJson(Map<String, dynamic>.from(inserted)),
      reopened: false,
    );
  }

  /// Fase 3 (T3.1): move o status de uma application do próprio usuário (aba
  /// Candidaturas). A transição é validada no banco (trigger + matriz por
  /// actor); o client já filtra opções inválidas via [canTransition]. Retorna
  /// a application atualizada. Só faz sentido pra type manual/external_confirmed
  /// (stage é read-only pro user — a UI nem oferece).
  Future<Application> updateStatus({
    required String applicationId,
    required ApplicationStatus status,
  }) async {
    final updated = await _client
        .from('applications')
        .update({'status': status.db})
        .eq('id', applicationId)
        .select()
        .single();
    return Application.fromJson(Map<String, dynamic>.from(updated));
  }

  /// Desfaz o "apliquei" (toggle off) ou desiste: → withdrawn.
  /// Retorna a application atualizada, ou null se não existia.
  Future<Application?> withdraw({
    required String userId,
    required String jobId,
  }) async {
    final rows = await _client
        .from('applications')
        .update({'status': ApplicationStatus.withdrawn.db})
        .eq('user_id', userId)
        .eq('job_id', jobId)
        .neq('status', ApplicationStatus.withdrawn.db)
        .select();
    final list = rows as List;
    if (list.isEmpty) return null;
    return Application.fromJson(Map<String, dynamic>.from(list.first));
  }
}
