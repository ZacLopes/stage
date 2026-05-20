import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import '../features/auth/user_viewmodel.dart';
import '../features/profile/profile_viewmodel.dart';
import 'analytics_service.dart';
import 'pdf_text_extractor.dart';

/// Resultado de uma importação de CV. UI pode usar `success` pra decidir
/// se fecha o picker / mostra confirmação, e os contadores pra mostrar
/// "extraímos N chars do seu CV".
class CvImportResult {
  final bool success;
  final String? errorMessage;
  final String? title;
  final String? savedResumeId;
  final int extractedTextLength;
  final bool textWasUsable;

  const CvImportResult({
    required this.success,
    this.errorMessage,
    this.title,
    this.savedResumeId,
    this.extractedTextLength = 0,
    this.textWasUsable = false,
  });

  const CvImportResult.cancelled() : this(success: false);
  const CvImportResult.error(String msg) : this(success: false, errorMessage: msg);
}

/// Default base title for imported PDFs in the library. The first import
/// is saved as exactly this; subsequent imports get "(2)", "(3)", ...
const String kImportedResumeBaseTitle = 'Meu Currículo';

/// Serviço único pra importar CV em PDF. Usado em:
/// - Onboarding (completion_screen)
/// - Aba Currículo (botão "Importar CV existente")
/// - Sheet de adaptação (quando perfil incompleto)
///
/// Pipeline:
/// 1. FilePicker pra PDF
/// 2. Upload pro Supabase Storage via ProfileViewModel.saveResume
/// 3. Extração de texto via ResumePdfExtractor (não-IA, só keyword overlap)
/// 4. Persistência do texto em gamification_data.imported_resume.raw_text
///    pra IA de match e adaptação consumirem
///
/// Idempotente: pode chamar quantas vezes quiser; cada chamada adiciona
/// uma nova entrada na biblioteca de currículos do user e atualiza o
/// raw_text (sobrescreve).
class CvImportService {
  /// Abre o picker e processa o PDF selecionado. Retorna [CvImportResult].
  /// Não navega nem mostra UI — caller decide o que fazer.
  static Future<CvImportResult> pickAndImport(BuildContext context) async {
    Analytics.shared.cvImportStarted();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return const CvImportResult.cancelled();
      }

      final file = result.files.single;
      final bytes = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);

      if (bytes == null) {
        return const CvImportResult.error('Não foi possível ler o arquivo.');
      }

      final byteList = Uint8List.fromList(bytes);

      // 1. Salva o PDF na biblioteca (Supabase Storage + tabela saved_resumes)
      if (!context.mounted) return const CvImportResult.cancelled();
      final profileVM = context.read<ProfileViewModel>();
      final title = await profileVM.resolveUniqueTitle(kImportedResumeBaseTitle);

      String? savedId;
      try {
        final saved = await profileVM.saveResume(title, byteList);
        savedId = saved.id;
      } catch (e) {
        return CvImportResult.error('Erro ao salvar o currículo: $e');
      }

      // 2. Extrai texto + persiste em gamification_data.imported_resume
      // (não bloqueia se extração falhar — usuário ainda tem o PDF salvo,
      // só não tem o boost de match/adaptação por keyword overlap)
      var rawTextLen = 0;
      var usable = false;
      String? extractionError;
      try {
        final rawText = ResumePdfExtractor.extract(byteList);
        rawTextLen = rawText.length;
        usable = ResumePdfExtractor.isUsable(rawText);
        if (usable && context.mounted) {
          final userVM = context.read<UserViewModel>();
          final currentData = Map<String, dynamic>.from(
            userVM.user?.gamificationData ?? const {},
          );
          currentData['imported_resume'] = {
            'raw_text': rawText,
            'imported_at': DateTime.now().toIso8601String(),
          };
          await userVM.updateProfile(gamificationData: currentData);
        }
      } catch (e) {
        extractionError = e.toString().split('\n').first;
        debugPrint('PDF text extraction failed (non-blocking): $e');
      }

      // Telemetria fiel ao resultado real: succeeded só quando o texto é
      // utilizável (e portanto persistido em imported_resume.raw_text). Caso
      // contrário, failed — extrator devolveu pouco/nada e a adaptação cairá
      // em profile_incomplete. Reportar succeeded aqui mascarava esses casos.
      if (usable) {
        Analytics.shared.cvImportSucceeded(extractedChars: rawTextLen);
      } else {
        Analytics.shared.cvImportFailed(
          reason: extractionError ?? 'unusable_text:$rawTextLen',
        );
      }
      return CvImportResult(
        success: true,
        title: title,
        savedResumeId: savedId,
        extractedTextLength: rawTextLen,
        textWasUsable: usable,
      );
    } catch (e) {
      Analytics.shared.cvImportFailed(reason: e.toString().split('\n').first);
      return CvImportResult.error('Falha inesperada: $e');
    }
  }
}
