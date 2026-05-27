// PendingResumeUploadService — rede de segurança pra uploads de CV que
// falham no Storage.
//
// O fluxo de upload em UploadPreviewSheet é fire-and-forget (não bloqueia
// extração). Sem esse service, se a primeira tentativa falhar (rede ruim,
// Storage indisponível, RLS bloqueando, arquivo grande), o PDF some pra
// sempre e o user nem sabe — features que dependem do PDF original (CV
// Adaptado por Vaga, biblioteca) quebram silenciosamente.
//
// Estratégia:
//   1. Salvar os bytes do PDF + filename em arquivo local + flag em
//      SharedPreferences ANTES de tentar o upload.
//   2. Após sucesso no Storage: deletar o arquivo local + limpar flag.
//   3. Se falhar: arquivo local permanece, flag fica setada.
//   4. PendingUploadBanner consulta a flag e oferece retry pro user.
//
// Por user — cada chave SharedPreferences inclui user_id pra não vazar
// entre contas no mesmo device.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingResumeUploadService {
  static final PendingResumeUploadService shared = PendingResumeUploadService._();
  PendingResumeUploadService._();

  // Chaves no SharedPreferences. Prefixo + user_id pra isolar contas.
  static const _kPrefix = 'pending_resume_upload_';
  static const _kFileSuffix = '_file';
  static const _kFilenameSuffix = '_filename';
  static const _kAttemptsSuffix = '_attempts';
  static const _kLastErrorSuffix = '_last_error';

  String _fileKey(String userId) => '$_kPrefix$userId$_kFileSuffix';
  String _filenameKey(String userId) => '$_kPrefix$userId$_kFilenameSuffix';
  String _attemptsKey(String userId) => '$_kPrefix$userId$_kAttemptsSuffix';
  String _lastErrorKey(String userId) => '$_kPrefix$userId$_kLastErrorSuffix';

  /// Salva os bytes do PDF em arquivo local + marca flag "pending" em prefs.
  /// Chama ANTES de tentar o upload no Storage — assim, se o upload falhar,
  /// temos os bytes pra retry. Se o app fechar no meio, sobrevive.
  Future<File> stash({
    required String userId,
    required Uint8List pdfBytes,
    required String filename,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final pendingDir = Directory('${dir.path}/pending_uploads');
    if (!await pendingDir.exists()) {
      await pendingDir.create(recursive: true);
    }
    final file = File('${pendingDir.path}/$userId.pdf');
    await file.writeAsBytes(pdfBytes);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fileKey(userId), file.path);
    await prefs.setString(_filenameKey(userId), filename);
    // attempts e last_error ficam zerados; setados depois se houver falha.
    await prefs.remove(_attemptsKey(userId));
    await prefs.remove(_lastErrorKey(userId));

    debugPrint('[PendingResumeUpload] stash ok user=$userId path=${file.path}');
    return file;
  }

  /// Marca uma falha no upload. Incrementa contador + grava motivo.
  /// O arquivo local NÃO é removido — fica disponível pro retry.
  Future<void> recordFailure({
    required String userId,
    required String error,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt(_attemptsKey(userId)) ?? 0) + 1;
    await prefs.setInt(_attemptsKey(userId), attempts);
    await prefs.setString(_lastErrorKey(userId), error);
    debugPrint(
      '[PendingResumeUpload] failure recorded user=$userId attempts=$attempts error=$error',
    );
  }

  /// Limpa TUDO: deleta o arquivo local e remove as chaves do prefs.
  /// Chamar APENAS após confirmar que o upload foi gravado no Storage.
  Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_fileKey(userId));
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('[PendingResumeUpload] clear file delete failed: $e');
      }
    }
    await prefs.remove(_fileKey(userId));
    await prefs.remove(_filenameKey(userId));
    await prefs.remove(_attemptsKey(userId));
    await prefs.remove(_lastErrorKey(userId));
    debugPrint('[PendingResumeUpload] cleared user=$userId');
  }

  /// Retorna true se há um upload pendente pra esse user.
  Future<bool> hasPending(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fileKey(userId)) != null;
  }

  /// Metadata do upload pendente pra mostrar no banner.
  /// Retorna null se não tem pending.
  Future<PendingUploadInfo?> getPendingInfo(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_fileKey(userId));
    if (path == null) return null;
    return PendingUploadInfo(
      filePath: path,
      filename: prefs.getString(_filenameKey(userId)) ?? 'currículo.pdf',
      attempts: prefs.getInt(_attemptsKey(userId)) ?? 0,
      lastError: prefs.getString(_lastErrorKey(userId)),
    );
  }

  /// Lê os bytes do PDF salvo localmente pra usar no retry.
  /// Retorna null se o arquivo sumiu (limpeza manual, app reinstalado).
  Future<Uint8List?> loadPendingBytes(String userId) async {
    final info = await getPendingInfo(userId);
    if (info == null) return null;
    final file = File(info.filePath);
    if (!await file.exists()) {
      // Arquivo sumiu mas a flag ficou — limpa tudo pra evitar zombie state.
      await clear(userId);
      return null;
    }
    return await file.readAsBytes();
  }
}

class PendingUploadInfo {
  final String filePath;
  final String filename;
  final int attempts;
  final String? lastError;

  const PendingUploadInfo({
    required this.filePath,
    required this.filename,
    required this.attempts,
    this.lastError,
  });
}
