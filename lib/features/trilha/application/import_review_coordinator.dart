// Gate 3.0I — coordenador do INÍCIO do fluxo de revisão de importação de CV.
//
// Sequência (o desenho da fundação 14/07; a parte do servidor já está provada
// no promote test):
//   1. gera um client_import_id (uuid v4) e sobe o PDF no path CANÔNICO que o
//      servidor exige — `<uid>/imports/<client_import_id>.pdf` (upsert ⇒ replay
//      do mesmo token é determinístico);
//   2. `begin_import_source` reserva a candidata → {candidate_id, attempt_id}
//      (idempotente por client_import_id: um retry devolve os mesmos ids);
//   3. `extract-profile` com save:false + os ids → a Edge persiste o payload NA
//      CANDIDATA (`complete_import_extraction`, status→ready) SEM tocar o perfil,
//      e devolve o profile_data pra montar o diff.
//
// Fail-closed: qualquer falha ⇒ null. O card de revisão NUNCA é montado sobre um
// estado incerto (sem candidata ready não há o que aplicar depois).

import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/cv_import_service.dart';
import '../../../services/pdf_text_extractor.dart';
import '../../../services/profile_snapshot_service.dart';
import 'cv_conflict.dart';

/// Início do fluxo de revisão: ids da candidata reservada + o payload extraído
/// (profile_data) pra construir o diff.
class ImportReviewStart {
  final String candidateId;
  final String attemptId;
  final Map<String, dynamic> profileData;
  const ImportReviewStart({
    required this.candidateId,
    required this.attemptId,
    required this.profileData,
  });
}

/// Gera um uuid v4 (client_import_id). Local de propósito — o pacote `uuid` é só
/// dependência transitiva; importá-lo direto sujaria o analyzer. [rng] injetável
/// pra teste determinístico. Versão (4) e variante (10) marcadas per RFC 4122.
String importClientId([Random? rng]) {
  final r = rng ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // versão 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante 10xx
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = [for (var i = 0; i < 16; i++) h(i)].join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}'
      '-${s.substring(16, 20)}-${s.substring(20)}';
}

/// O path canônico que `begin_import_source` valida (`invalid_file_path` se
/// divergir). O servidor recomputa o mesmo — o cliente TEM que subir aqui.
String importCanonicalPath(String userId, String clientImportId) =>
    '$userId/imports/$clientImportId.pdf';

/// Extrai {candidate_id, attempt_id} do retorno do `begin_import_source`.
/// null quando o retorno não tem os dois (fail-closed).
({String candidateId, String attemptId})? parseBeginImportResult(dynamic raw) {
  if (raw is! Map) return null;
  final candidateId = (raw['candidate_id'] ?? '').toString().trim();
  final attemptId = (raw['attempt_id'] ?? '').toString().trim();
  if (candidateId.isEmpty || attemptId.isEmpty) return null;
  return (candidateId: candidateId, attemptId: attemptId);
}

/// Orquestra os 3 passos. [client]/[rng] injetáveis; sem eles usa os singletons.
/// [pdfBytes] são os bytes já lidos do PDF escolhido.
Future<ImportReviewStart?> startImportReview(
  Uint8List pdfBytes, {
  String? title,
  String? originalFilename,
  String? rawTextFallback,
  SupabaseClient? client,
  Random? rng,
}) async {
  final sb = client ?? Supabase.instance.client;
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return null;
  try {
    final clientImportId = importClientId(rng);
    final path = importCanonicalPath(uid, clientImportId);

    // 1. Upload no path canônico (upsert ⇒ replay determinístico do token).
    await sb.storage.from('resumes').uploadBinary(
          path,
          pdfBytes,
          fileOptions:
              const FileOptions(contentType: 'application/pdf', upsert: true),
        );

    // 2. Reserva a candidata (idempotente por client_import_id).
    final begin = await sb.rpc('begin_import_source', params: {
      'p_title': (title == null || title.trim().isEmpty)
          ? 'Currículo importado'
          : title.trim(),
      'p_file_path': path,
      'p_original_filename': originalFilename,
      'p_client_import_id': clientImportId,
    });
    final ids = parseBeginImportResult(begin);
    if (ids == null) return null;

    // 3. Extrai + persiste NA CANDIDATA (save:false ⇒ perfil intacto). O
    //    rawText ajuda o validador anti-invenção da Edge; extrai localmente se
    //    o caller não passou.
    var rawText = rawTextFallback;
    if (rawText == null || rawText.isEmpty) {
      try {
        final t = ResumePdfExtractor.extract(pdfBytes);
        if (ResumePdfExtractor.isUsable(t)) rawText = t;
      } catch (_) {
        /* rawText é best-effort */
      }
    }
    final profileData = await CvImportService.extractProfile(
      pdfBytes,
      save: false,
      rawTextFallback: rawText,
      candidateId: ids.candidateId,
      attemptId: ids.attemptId,
    );
    if (profileData == null) return null;

    return ImportReviewStart(
      candidateId: ids.candidateId,
      attemptId: ids.attemptId,
      profileData: profileData,
    );
  } catch (_) {
    // fail-closed: nunca monta o card sobre estado incerto.
    return null;
  }
}

/// Diff do fluxo de revisão + ids da candidata — application-level (sem tipo de
/// UI). A camada de apresentação embrulha num AssistImportResult pro card.
class ImportReviewConflicts {
  final List<ConflictRow> rows;
  final String candidateId;
  final String attemptId;
  const ImportReviewConflicts({
    required this.rows,
    required this.candidateId,
    required this.attemptId,
  });
}

/// Inicia a revisão E monta o diff: reserva+persiste a candidata
/// ([startImportReview]) e diffa o profile_data contra o perfil atual. Retorna
/// as linhas + os ids da candidata, ou null em falha (fail-closed). Uma
/// candidata 'ready' sem card (diff vazio / erro do diff) é inofensiva — fica na
/// biblioteca sem ser promovida.
Future<ImportReviewConflicts?> loadImportReviewConflicts(
  String userId,
  Uint8List pdfBytes, {
  String? title,
  String? originalFilename,
  String? rawTextFallback,
  SupabaseClient? client,
  Random? rng,
  ProfileSnapshotService? snapshotService,
}) async {
  final start = await startImportReview(
    pdfBytes,
    title: title,
    originalFilename: originalFilename,
    rawTextFallback: rawTextFallback,
    client: client,
    rng: rng,
  );
  if (start == null) return null;
  try {
    final snapSvc = snapshotService ?? ProfileSnapshotService();
    final snapshot = await snapSvc.loadSnapshot(userId);
    final rows = CvConflictDiff.compute(start.profileData, snapshot);
    return ImportReviewConflicts(
      rows: rows,
      candidateId: start.candidateId,
      attemptId: start.attemptId,
    );
  } catch (_) {
    return null;
  }
}
