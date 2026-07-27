import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/resume/services/general_resume_version_writer.dart';

// F4.3 — writer da versão persistida do Currículo geral. Cobre: fingerprint
// canônico/estável, recibo fail-closed, ordem upload→RPC→limpeza-de-órfão,
// pré-check noop (sem upload), corrida (noop pós-upload remove blob).
void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);
  const uid = 'user-1';

  group('computeResumeFingerprint', () {
    test('é estável e independente da ordem das CHAVES (não das listas)', () {
      final a = {
        'summary': 'x',
        'skills': ['a', 'b'],
        'awards': [
          {'title': 'T', 'date': '2023'},
        ],
      };
      final b = {
        'awards': [
          {'date': '2023', 'title': 'T'},
        ],
        'skills': ['a', 'b'],
        'summary': 'x',
      };
      expect(computeResumeFingerprint(a), computeResumeFingerprint(b));
    });

    test('muda quando o CONTEÚDO muda', () {
      final a = {'summary': 'x'};
      final b = {'summary': 'y'};
      expect(computeResumeFingerprint(a), isNot(computeResumeFingerprint(b)));
    });

    test('a ORDEM da lista importa (seções são semânticas)', () {
      final a = {
        'skills': ['a', 'b'],
      };
      final b = {
        'skills': ['b', 'a'],
      };
      expect(computeResumeFingerprint(a), isNot(computeResumeFingerprint(b)));
    });

    test('é um hex de 64 chars (formato aceito pela RPC)', () {
      final fp = computeResumeFingerprint({'summary': 'x'});
      expect(fp, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  // Harness: registra chamadas de upload/rpc/remove e devolve respostas
  // programadas.
  GeneralResumeVersionWriter buildWriter({
    required dynamic rpcResult,
    Object? rpcThrows,
    Object? uploadThrows,
    Map<String, dynamic>? lastVersion,
    Object? lastVersionThrows,
    required List<String> uploads,
    required List<String> removes,
    required List<Map<String, dynamic>> rpcCalls,
    String fileId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  }) {
    return GeneralResumeVersionWriter(
      newFileId: () => fileId,
      upload: (path, _) async {
        uploads.add(path);
        if (uploadThrows != null) throw uploadThrows;
      },
      remove: (path) async => removes.add(path),
      fetchLastVersion: (_) async {
        if (lastVersionThrows != null) throw lastVersionThrows;
        return lastVersion;
      },
      rpc: (fn, params) async {
        rpcCalls.add({'fn': fn, ...params});
        if (rpcThrows != null) throw rpcThrows;
        return rpcResult;
      },
    );
  }

  group('save — caminho feliz e recibos', () {
    test('applied: sobe blob, chama RPC, mantém o blob', () async {
      final uploads = <String>[];
      final removes = <String>[];
      final rpcCalls = <Map<String, dynamic>>[];
      final w = buildWriter(
        rpcResult: {'status': 'applied', 'version': 1, 'id': 'row-1'},
        uploads: uploads,
        removes: removes,
        rpcCalls: rpcCalls,
      );
      final r = await w.save(
        uid: uid,
        resumeData: const {'summary': 'x'},
        templateId: 'harvard_ats',
        pdfBytes: bytes,
      );
      expect(r.status, GeneralResumeSaveStatus.applied);
      expect(r.version, 1);
      expect(r.id, 'row-1');
      expect(uploads.single,
          'user-1/general/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.pdf');
      expect(rpcCalls.single['fn'], 'save_general_resume_version_v1');
      expect(rpcCalls.single['p_file_path'], uploads.single);
      expect(rpcCalls.single['p_fingerprint'],
          computeResumeFingerprint(const {'summary': 'x'}));
      expect(removes, isEmpty); // blob mantido
    });

    test('pré-check noop: mesma fingerprint+template ⇒ SEM upload/RPC', () async {
      final uploads = <String>[];
      final removes = <String>[];
      final rpcCalls = <Map<String, dynamic>>[];
      final fp = computeResumeFingerprint(const {'summary': 'x'});
      final w = buildWriter(
        rpcResult: const {'status': 'applied'},
        lastVersion: {
          'id': 'row-old',
          'version': 3,
          'profile_fingerprint': fp,
          'template_id': 'harvard_ats',
        },
        uploads: uploads,
        removes: removes,
        rpcCalls: rpcCalls,
      );
      final r = await w.save(
        uid: uid,
        resumeData: const {'summary': 'x'},
        templateId: 'harvard_ats',
        pdfBytes: bytes,
      );
      expect(r.status, GeneralResumeSaveStatus.noop);
      expect(r.version, 3);
      expect(r.id, 'row-old');
      expect(uploads, isEmpty);
      expect(rpcCalls, isEmpty);
    });

    test('pré-check com template DIFERENTE ⇒ sobe e versiona', () async {
      final uploads = <String>[];
      final removes = <String>[];
      final rpcCalls = <Map<String, dynamic>>[];
      final fp = computeResumeFingerprint(const {'summary': 'x'});
      final w = buildWriter(
        rpcResult: const {'status': 'applied', 'version': 4},
        lastVersion: {
          'id': 'row-old',
          'version': 3,
          'profile_fingerprint': fp,
          'template_id': 'cobalt_modern', // template diferente
        },
        uploads: uploads,
        removes: removes,
        rpcCalls: rpcCalls,
      );
      final r = await w.save(
        uid: uid,
        resumeData: const {'summary': 'x'},
        templateId: 'harvard_ats',
        pdfBytes: bytes,
      );
      expect(r.status, GeneralResumeSaveStatus.applied);
      expect(uploads, hasLength(1));
      expect(rpcCalls, hasLength(1));
    });
  });

  group('save — falha SEMPRE fail-closed, blob órfão limpo', () {
    test('upload falha ⇒ failed, sem RPC', () async {
      final uploads = <String>[];
      final removes = <String>[];
      final rpcCalls = <Map<String, dynamic>>[];
      final w = buildWriter(
        rpcResult: const {'status': 'applied'},
        uploadThrows: Exception('storage down'),
        uploads: uploads,
        removes: removes,
        rpcCalls: rpcCalls,
      );
      final r = await w.save(
        uid: uid,
        resumeData: const {'summary': 'x'},
        templateId: 'harvard_ats',
        pdfBytes: bytes,
      );
      expect(r.status, GeneralResumeSaveStatus.failed);
      expect(rpcCalls, isEmpty);
    });

    test('RPC lança após upload ⇒ failed + remove o blob órfão', () async {
      final uploads = <String>[];
      final removes = <String>[];
      final rpcCalls = <Map<String, dynamic>>[];
      final w = buildWriter(
        rpcResult: const {},
        rpcThrows: Exception('rpc 500'),
        uploads: uploads,
        removes: removes,
        rpcCalls: rpcCalls,
      );
      final r = await w.save(
        uid: uid,
        resumeData: const {'summary': 'x'},
        templateId: 'harvard_ats',
        pdfBytes: bytes,
      );
      expect(r.status, GeneralResumeSaveStatus.failed);
      expect(removes.single, uploads.single); // órfão removido
    });

    test('recibo malformado/desconhecido ⇒ failed + remove órfão', () async {
      for (final bad in <dynamic>[
        {'status': 'weird'},
        {'no_status': true},
        'not a map',
        null,
      ]) {
        final uploads = <String>[];
        final removes = <String>[];
        final rpcCalls = <Map<String, dynamic>>[];
        final w = buildWriter(
          rpcResult: bad,
          uploads: uploads,
          removes: removes,
          rpcCalls: rpcCalls,
        );
        final r = await w.save(
          uid: uid,
          resumeData: const {'summary': 'x'},
          templateId: 'harvard_ats',
          pdfBytes: bytes,
        );
        expect(r.status, GeneralResumeSaveStatus.failed,
            reason: 'recibo $bad deveria falhar fechado');
        expect(removes.single, uploads.single);
      }
    });

    test('corrida: RPC devolve noop após upload ⇒ remove o blob órfão', () async {
      final uploads = <String>[];
      final removes = <String>[];
      final rpcCalls = <Map<String, dynamic>>[];
      // pré-check não pega (lastVersion divergente), mas a RPC (autoritativa)
      // vê que outra sessão já salvou a mesma versão → noop.
      final w = buildWriter(
        rpcResult: {'status': 'noop', 'version': 5, 'id': 'row-winner'},
        lastVersion: {
          'id': 'row-old',
          'version': 4,
          'profile_fingerprint': 'deadbeef',
          'template_id': 'harvard_ats',
        },
        uploads: uploads,
        removes: removes,
        rpcCalls: rpcCalls,
      );
      final r = await w.save(
        uid: uid,
        resumeData: const {'summary': 'x'},
        templateId: 'harvard_ats',
        pdfBytes: bytes,
      );
      expect(r.status, GeneralResumeSaveStatus.noop);
      expect(r.version, 5);
      expect(uploads, hasLength(1));
      expect(removes.single, uploads.single); // órfão da corrida removido
    });

    test('pré-check falhando NÃO decide nada: cai pro upload+RPC', () async {
      final uploads = <String>[];
      final removes = <String>[];
      final rpcCalls = <Map<String, dynamic>>[];
      final w = buildWriter(
        rpcResult: const {'status': 'applied', 'version': 1},
        lastVersionThrows: Exception('select down'),
        uploads: uploads,
        removes: removes,
        rpcCalls: rpcCalls,
      );
      final r = await w.save(
        uid: uid,
        resumeData: const {'summary': 'x'},
        templateId: 'harvard_ats',
        pdfBytes: bytes,
      );
      expect(r.status, GeneralResumeSaveStatus.applied);
      expect(uploads, hasLength(1));
      expect(rpcCalls, hasLength(1));
    });
  });
}
