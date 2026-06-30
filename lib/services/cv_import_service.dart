import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/models.dart' show SavedResumeSource;
import '../features/auth/user_viewmodel.dart';
import '../features/profile/profile_viewmodel.dart';
import 'analytics_service.dart';
import 'cv_content_validator.dart';
import 'pdf_text_extractor.dart';
import 'profile_events.dart';

/// Resultado de uma importação de CV. UI pode usar `success` pra decidir
/// se fecha o picker / mostra confirmação, e os contadores pra mostrar
/// "extraímos N chars do seu CV".
class CvImportResult {
  final bool success;
  final String? errorMessage;
  final String? title;

  /// Nome real do arquivo PDF que o usuário escolheu (ex.: "Joao_Silva_CV.pdf").
  /// Distinto do [title], que é o título na biblioteca ("Meu Currículo (2)").
  final String? fileName;
  final String? savedResumeId;
  final int extractedTextLength;
  final bool textWasUsable;

  const CvImportResult({
    required this.success,
    this.errorMessage,
    this.title,
    this.fileName,
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

      // 1. Pre-extract: extrai texto e valida conteúdo ANTES de salvar PDF
      // na biblioteca. Se for extrato bancário / doc gov.br / holerite,
      // rejeita sem deixar nada salvo no Storage nem no banco. Caso real
      // motivador: usuária subiu extrato Nubank de 14k chars que ficou
      // salvo com dados financeiros + dados de terceiros (incidente LGPD).
      String? preExtractedText;
      try {
        preExtractedText = ResumePdfExtractor.extract(byteList);
      } catch (e) {
        debugPrint('PDF pre-extract failed (will still save PDF): $e');
      }
      if (preExtractedText != null &&
          ResumePdfExtractor.isUsable(preExtractedText)) {
        final detection = CvContentValidator.detect(preExtractedText);
        if (detection.isNonCv) {
          Analytics.shared.cvImportFailed(
            reason: 'non_cv_content:${detection.category!.name}',
          );
          return CvImportResult.error(
            CvContentValidator.messageFor(detection.category!),
          );
        }
      }

      // 2. Salva o PDF na biblioteca (Supabase Storage + tabela saved_resumes)
      if (!context.mounted) return const CvImportResult.cancelled();
      final profileVM = context.read<ProfileViewModel>();
      final title = await profileVM.resolveUniqueTitle(kImportedResumeBaseTitle);

      String? savedId;
      try {
        final saved = await profileVM.saveResume(
          title,
          byteList,
          source: SavedResumeSource.imported,
        );
        savedId = saved.id;
      } catch (e) {
        return CvImportResult.error('Erro ao salvar o currículo: $e');
      }

      // 3. Persiste raw_text em gamification_data.imported_resume
      // (não bloqueia se extração falhar — usuário ainda tem o PDF salvo,
      // só não tem o boost de match/adaptação por keyword overlap)
      final usableText = preExtractedText != null &&
              ResumePdfExtractor.isUsable(preExtractedText)
          ? preExtractedText
          : null;
      final usable = usableText != null;
      final rawTextLen = usableText?.length ?? 0;
      String? extractionError;
      try {
        if (usableText != null && context.mounted) {
          final userVM = context.read<UserViewModel>();
          final currentData = Map<String, dynamic>.from(
            userVM.user?.gamificationData ?? const {},
          );
          currentData['imported_resume'] = {
            'raw_text': usableText,
            // .toUtc() é obrigatório — `profile.created_at` é timestamptz UTC
            // no banco e cruzamentos por data ficavam off-by-3h em Brasília.
            'imported_at': DateTime.now().toUtc().toIso8601String(),
          };
          await userVM.updateProfile(gamificationData: currentData);
          // Sinaliza pro JobsSwipeScreen/JobsViewModel limparem caches de
          // match e pseudo-texto. Sem isso, `_matchCache` mantém
          // `MatchResult.noResume()` até hot-restart mesmo com o raw_text
          // já salvo. Os 2 listeners (ProfileEvents.changes em
          // jobs_swipe_screen.dart e jobs_viewmodel.dart) já estão prontos.
          ProfileEvents.instance.notifyChanged();
        }
      } catch (e) {
        extractionError = e.toString().split('\n').first;
        debugPrint('PDF raw_text persist failed (non-blocking): $e');
      }

      // Telemetria fiel ao resultado real: succeeded só quando o texto é
      // utilizável (e portanto persistido em imported_resume.raw_text). Caso
      // contrário, failed — extrator devolveu pouco/nada e a adaptação cairá
      // em profile_incomplete. Reportar succeeded aqui mascarava esses casos.
      if (usable) {
        Analytics.shared.cvImportSucceeded(extractedChars: rawTextLen);
        // Dispara extract-profile (substitui parse-cv-pdf) — manda o PDF
        // base64 direto pra Edge Function que usa GPT-4o com suporte nativo
        // a PDF e popula:
        //   1. user_profiles.gamification_data.imported_resume.parsed
        //      (formato legacy — compatível com adapt-resume-to-job e
        //      generate-resume)
        //   2. 18 tabelas relacionais (profile_personal, profile_experiences,
        //      profile_bullets, etc) via save-profile interno
        //
        // O fallback paralelo via `parse-cv` (text-only) foi removido em
        // 2026-05-26: extract-profile cobria 99% do volume (342 vs 4 nos
        // últimos 30 dias) e o fallback só inflava telemetria de
        // `cvParserFailed` sem agregar valor. Reverter via git se algum
        // user reportar regressão em CVs com layouts atípicos.
        // ignore: unawaited_futures
        CvImportService._triggerParseCvPdfInBackground(
          byteList,
          rawTextFallback: usableText,
        );
      } else {
        Analytics.shared.cvImportFailed(
          reason: extractionError ?? 'unusable_text:$rawTextLen',
        );
      }
      return CvImportResult(
        success: true,
        title: title,
        fileName: file.name,
        savedResumeId: savedId,
        extractedTextLength: rawTextLen,
        textWasUsable: usable,
      );
    } catch (e) {
      Analytics.shared.cvImportFailed(reason: e.toString().split('\n').first);
      return CvImportResult.error('Falha inesperada: $e');
    }
  }

  /// Semana 1 profile-first: dispara `extract-profile` (sucessor de
  /// `parse-cv-pdf`) mandando o PDF base64 direto. A edge function:
  ///   1. Roda GPT-4o com Structured Outputs (schema rico — first/last
  ///      separados, phone country code, gender, age_range, confidence
  ///      per-item, bullets categorizáveis)
  ///   2. Persiste o subset legacy em
  ///      user_profiles.gamification_data.imported_resume.parsed pra
  ///      preservar adapt-resume-to-job, generate-resume e ResumeData
  ///   3. Chama save-profile internamente que popula 18 tabelas relacionais
  ///      via save_profile_from_json RPC (modo replace, transactional)
  ///
  /// Fire-and-forget pra não bloquear o usuário no upload. parse-cv text-only
  /// roda em paralelo como fallback adicional.
  ///
  /// Tempo típico: 10-15s (extract-profile inclui dual-write síncrono).
  /// Custo: ~$0.005 por chamada.
  ///
  /// [rawTextFallback] ajuda o validador anti-invenção do edge function a
  /// checar nomes próprios. Caller deve passar o texto já extraído
  /// localmente — antes a função relia do cache `imported_resume.raw_text`
  /// no `user_profiles`, mas pós migração profile-first esse cache é
  /// write-only e pode estar vazio/stale.
  static Future<void> _triggerParseCvPdfInBackground(
    Uint8List pdfBytes, {
    String? rawTextFallback,
  }) async {
    const invokeTimeout = Duration(seconds: 75);
    try {
      final pdfBase64 = base64Encode(pdfBytes);

      final response = await Supabase.instance.client.functions
          .invoke(
            'extract-profile',
            body: {
              'pdf_base64': pdfBase64,
              if (rawTextFallback != null) 'raw_text_fallback': rawTextFallback,
            },
          )
          .timeout(invokeTimeout);
      final data = response.data;
      if (data is! Map) {
        Analytics.shared.cvParserFailed(
          source: 'pdf',
          stage: 'response',
          reason: 'invalid_response_shape',
        );
        return;
      }
      if (data['error'] != null) {
        Analytics.shared.cvParserFailed(
          source: 'pdf',
          stage: 'response',
          reason: data['error'].toString(),
        );
        return;
      }
      final fieldsFilled = (data['fields_filled'] as num?)?.toInt() ?? 0;
      final cached = data['cached'] == true;
      final parsed = data['parsed'];
      final hasExperiences = parsed is Map &&
          parsed['experiences'] is List &&
          (parsed['experiences'] as List).isNotEmpty;
      final hasEducation = parsed is Map &&
          parsed['education'] is List &&
          (parsed['education'] as List).isNotEmpty;
      Analytics.shared.cvImportParsed(
        fieldsFilled: fieldsFilled,
        cached: cached,
        hasExperiences: hasExperiences,
        hasEducation: hasEducation,
      );
    } on TimeoutException catch (e) {
      Analytics.shared.cvParserFailed(
        source: 'pdf',
        stage: 'invoke',
        reason: 'timeout:${invokeTimeout.inSeconds}s',
      );
      debugPrint('extract-profile invoke timed out: $e');
    } catch (e) {
      Analytics.shared.cvParserFailed(
        source: 'pdf',
        stage: 'invoke',
        reason: e.toString().split('\n').first,
      );
      debugPrint('extract-profile background call failed (non-blocking): $e');
    }
  }

  // _triggerParseCvInBackground (text-only fallback) removido em 2026-05-26.
  // O extract-profile (path PDF nativo via GPT-4o) cobria 99% do volume
  // de parsing (342 vs 4 escritas nos últimos 30 dias) e o fallback paralelo
  // só inflava telemetria de `cvParserFailed` sem agregar valor.
  // A edge function `parse-cv` continua deployada por segurança (rollback
  // rápido se precisar) e será removida em onda 3 da migração profile-first.
}
