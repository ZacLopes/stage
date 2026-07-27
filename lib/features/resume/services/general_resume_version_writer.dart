// Fase 4 (IA/Perfil) — F4.3: writer da VERSÃO persistida do Currículo geral.
//
// Junta F4.1 (RPC `save_general_resume_version_v1`, com noop honesto sob lock)
// e F4.2 (serializer completo de ResumeData) no fluxo de export. Contrato:
//   - fail-closed: qualquer falha (upload, RPC, recibo malformado) vira
//     `failed` — NUNCA falso `applied`; o caller decide o aviso e o share do
//     PDF nunca quebra por causa disto;
//   - fingerprint sha256 da serialização canônica do resume_data, computado e
//     comparado SEMPRE no client (mesma camada — lição do analyze-match);
//   - noop honesto: última versão com MESMO fingerprint E template ⇒ não cria
//     versão nova (a RPC é a autoridade sob lock; o pré-check local é só uma
//     otimização pra não subir blob à toa);
//   - Storage e Postgres não são transacionais juntos (§8.4 do handoff): o modo
//     de falha aceito é blob órfão (nunca linha sem blob). Blob órfão de noop/
//     erro é removido best-effort.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Status do save de uma versão. Fail-closed: recibo desconhecido/malformado
/// vira `failed`.
enum GeneralResumeSaveStatus { applied, noop, failed }

/// Recibo tipado do save. `version`/`id` vêm preenchidos em applied e noop
/// (a versão vigente); ausentes em failed.
class GeneralResumeSaveReceipt {
  final GeneralResumeSaveStatus status;
  final int? version;
  final String? id;
  const GeneralResumeSaveReceipt(this.status, {this.version, this.id});

  static const failed =
      GeneralResumeSaveReceipt(GeneralResumeSaveStatus.failed);
}

/// Fingerprint canônico e determinístico do resume_data. sha256 da
/// serialização com chaves ORDENADAS recursivamente; listas preservam a ordem
/// (ordem das seções é semântica). Como é computado e comparado sempre no
/// client, nunca precisa casar com um cômputo server-side.
String computeResumeFingerprint(Map<String, dynamic> resumeData) {
  final canonical = _canonicalJson(resumeData);
  return sha256.convert(utf8.encode(canonical)).toString();
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    final buf = StringBuffer('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) buf.write(',');
      buf.write(jsonEncode(keys[i]));
      buf.write(':');
      buf.write(_canonicalJson(value[keys[i]]));
    }
    buf.write('}');
    return buf.toString();
  }
  if (value is List) {
    final buf = StringBuffer('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) buf.write(',');
      buf.write(_canonicalJson(value[i]));
    }
    buf.write(']');
    return buf.toString();
  }
  return jsonEncode(value); // String/num/bool/null
}

/// Gera um uuid v4 minúsculo (casa com o regex de path da RPC: `[0-9a-f-]{36}`).
/// Local de propósito (mesmo motivo de `importClientId`): o pacote `uuid` é só
/// dependência transitiva. [rng] injetável pra teste determinístico.
String generalVersionFileId([Random? rng]) {
  final r = rng ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // versão 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante 10xx
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = [for (var i = 0; i < 16; i++) h(i)].join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}'
      '-${s.substring(16, 20)}-${s.substring(20)}';
}

typedef ResumeUploadFn = Future<void> Function(String path, Uint8List bytes);
typedef ResumeRpcFn = Future<dynamic> Function(
    String fn, Map<String, dynamic> params);
typedef ResumeRemoveFn = Future<void> Function(String path);
typedef ResumeLastVersionFn = Future<Map<String, dynamic>?> Function(String uid);

class GeneralResumeVersionWriter {
  final ResumeUploadFn _upload;
  final ResumeRpcFn _rpc;
  final ResumeRemoveFn _remove;
  final ResumeLastVersionFn _fetchLastVersion;
  final String Function() _newFileId;

  GeneralResumeVersionWriter({
    required ResumeUploadFn upload,
    required ResumeRpcFn rpc,
    required ResumeRemoveFn remove,
    required ResumeLastVersionFn fetchLastVersion,
    String Function()? newFileId,
  })  : _upload = upload,
        _rpc = rpc,
        _remove = remove,
        _fetchLastVersion = fetchLastVersion,
        _newFileId = newFileId ?? generalVersionFileId;

  /// Writer de produção contra o Supabase (bucket `resumes`, RPC
  /// `save_general_resume_version_v1`, SELECT da última versão own-row via RLS).
  factory GeneralResumeVersionWriter.production() {
    final sb = Supabase.instance.client;
    return GeneralResumeVersionWriter(
      upload: (path, bytes) => sb.storage.from('resumes').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
                contentType: 'application/pdf', upsert: true),
          ),
      rpc: (fn, params) => sb.rpc(fn, params: params),
      remove: (path) => sb.storage.from('resumes').remove([path]),
      fetchLastVersion: (uid) async {
        // .eq('user_id') é redundante com o RLS own-row, mas é defesa em
        // profundidade explícita (não depender só da policy).
        final row = await sb
            .from('saved_resumes')
            .select('id, version, profile_fingerprint, template_id')
            .eq('user_id', uid)
            .eq('source', 'general')
            .order('version', ascending: false)
            .limit(1)
            .maybeSingle();
        return row;
      },
    );
  }

  /// Salva (ou reconhece noop de) uma versão do Currículo geral. NUNCA lança —
  /// toda falha vira `GeneralResumeSaveStatus.failed`. O caller decide o aviso;
  /// o share do PDF é independente e nunca quebra por causa deste método.
  Future<GeneralResumeSaveReceipt> save({
    required String uid,
    required Map<String, dynamic> resumeData,
    required String templateId,
    required Uint8List pdfBytes,
    String? title,
  }) async {
    final fingerprint = computeResumeFingerprint(resumeData);

    // Pré-check barato: última versão com MESMO fingerprint E template ⇒ noop
    // garantido, sem subir blob. Falha da leitura NÃO decide nada (a RPC é
    // autoritativa); só cai pro caminho de upload+RPC.
    try {
      final last = await _fetchLastVersion(uid);
      if (last != null &&
          last['profile_fingerprint'] == fingerprint &&
          last['template_id'] == templateId) {
        return GeneralResumeSaveReceipt(
          GeneralResumeSaveStatus.noop,
          version: (last['version'] as num?)?.toInt(),
          id: last['id']?.toString(),
        );
      }
    } catch (_) {
      /* pré-check é best-effort */
    }

    final path = '$uid/general/${_newFileId()}.pdf';
    try {
      await _upload(path, pdfBytes);
    } catch (_) {
      return GeneralResumeSaveReceipt.failed;
    }

    dynamic raw;
    try {
      raw = await _rpc('save_general_resume_version_v1', {
        'p_title': title,
        'p_file_path': path,
        'p_resume_data': resumeData,
        'p_template_id': templateId,
        'p_fingerprint': fingerprint,
      });
    } catch (_) {
      // RPC falhou após o upload → blob órfão. Remove best-effort. failed.
      await _removeBestEffort(path);
      return GeneralResumeSaveReceipt.failed;
    }

    final receipt = _parseReceipt(raw);
    // noop após upload = corrida (outra sessão salvou a MESMA versão entre o
    // pré-check e a RPC): o blob que subimos aponta pra lugar nenhum → remove.
    // recibo malformado após upload também deixa blob órfão → remove.
    if (receipt.status != GeneralResumeSaveStatus.applied) {
      await _removeBestEffort(path);
    }
    return receipt;
  }

  Future<void> _removeBestEffort(String path) async {
    try {
      await _remove(path);
    } catch (_) {
      /* blob órfão é o modo de falha aceito (§8.4 do handoff) */
    }
  }

  static GeneralResumeSaveReceipt _parseReceipt(dynamic raw) {
    if (raw is! Map) return GeneralResumeSaveReceipt.failed;
    final m = Map<String, dynamic>.from(raw);
    final status = m['status']?.toString();
    if (status == 'applied' || status == 'noop') {
      return GeneralResumeSaveReceipt(
        status == 'applied'
            ? GeneralResumeSaveStatus.applied
            : GeneralResumeSaveStatus.noop,
        version: (m['version'] as num?)?.toInt(),
        id: m['id']?.toString(),
      );
    }
    return GeneralResumeSaveReceipt.failed; // desconhecido/ausente → fail-closed
  }
}
