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
        // Semana 1 da migração profile-first: dispara extract-profile
        // (substitui parse-cv-pdf) — manda o PDF base64 direto pra Edge
        // Function que usa GPT-4o com suporte nativo a PDF e popula:
        //   1. user_profiles.gamification_data.imported_resume.parsed
        //      (formato legacy — compatível com adapt-resume-to-job e
        //      generate-resume)
        //   2. 18 tabelas relacionais (profile_personal, profile_experiences,
        //      profile_bullets, etc) via save-profile interno
        // parse-cv (text-only) também é disparado em paralelo como fallback
        // — escreve só o JSONB legacy.
        // ignore: unawaited_futures
        CvImportService._triggerParseCvInBackground();
        // ignore: unawaited_futures
        CvImportService._triggerParseCvPdfInBackground(byteList);
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
  static Future<void> _triggerParseCvPdfInBackground(Uint8List pdfBytes) async {
    const invokeTimeout = Duration(seconds: 75);
    try {
      final pdfBase64 = base64Encode(pdfBytes);

      // raw_text_fallback ajuda o validador anti-invenção do edge function
      // a checar nomes próprios. Lê do user atual.
      final user = Supabase.instance.client.auth.currentUser;
      String? rawText;
      if (user != null) {
        final profileResp = await Supabase.instance.client
            .from('user_profiles')
            .select('gamification_data')
            .eq('id', user.id)
            .maybeSingle();
        final gd = profileResp?['gamification_data'] as Map<String, dynamic>?;
        final imported = gd?['imported_resume'] as Map<String, dynamic>?;
        rawText = imported?['raw_text'] as String?;
      }

      final response = await Supabase.instance.client.functions
          .invoke(
            'extract-profile',
            body: {
              'pdf_base64': pdfBase64,
              if (rawText != null) 'raw_text_fallback': rawText,
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

  /// Dispara a Edge Function `parse-cv` para estruturar o raw_text recém
  /// persistido em JSON e gravar em `imported_resume.parsed`. Fire-and-forget:
  /// se falhar, o pipeline de adaptação ainda funciona via raw_text + pre-parser
  /// legacy. Não retorna nada — telemetria via PostHog event
  /// `cv_import_parsed` emitido aqui (sucesso) ou silêncio (falha).
  ///
  /// Roda em background — não bloqueia a UX do import. Tempo típico: 4-8s.
  /// Custo OpenAI: ~$0.0005 por chamada.
  static Future<void> _triggerParseCvInBackground() async {
    // Timeout cobre o caso onde a edge não responde (Vision pode demorar,
    // text-only é rápido — 45s é folga generosa).
    const invokeTimeout = Duration(seconds: 45);
    // Retry cobre a race condition documentada: parse-cv chamado logo após
    // signup pode falhar com 404 profile_not_found porque o user_profile
    // ainda não foi criado on-demand. 4 CVs reais foram observados sem
    // parsed por esse motivo até hoje.
    const maxRetries = 2;
    const retryDelay = Duration(seconds: 3);

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await Supabase.instance.client.functions
            .invoke('parse-cv', body: const {})
            .timeout(invokeTimeout);
        final data = response.data;
        if (data is! Map) {
          Analytics.shared.cvParserFailed(
            source: 'text',
            stage: 'response',
            reason: 'invalid_response_shape',
          );
          return;
        }
        if (data['error'] != null) {
          final errorStr = data['error'].toString();
          // profile_not_found = race com criação on-demand; tenta de novo
          // após delay. Outros erros não são transientes — desiste.
          if (errorStr.contains('profile_not_found') && attempt < maxRetries) {
            await Future.delayed(retryDelay);
            continue;
          }
          Analytics.shared.cvParserFailed(
            source: 'text',
            stage: 'response',
            reason: errorStr,
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
        return;
      } on TimeoutException catch (e) {
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
          continue;
        }
        Analytics.shared.cvParserFailed(
          source: 'text',
          stage: 'invoke',
          reason: 'timeout:${invokeTimeout.inSeconds}s',
        );
        debugPrint('parse-cv invoke timed out: $e');
        return;
      } catch (e) {
        final msg = e.toString();
        // profile_not_found também pode vir como exception em vez de
        // status code, dependendo do supabase_flutter — retry mesmo assim.
        if (msg.contains('profile_not_found') && attempt < maxRetries) {
          await Future.delayed(retryDelay);
          continue;
        }
        Analytics.shared.cvParserFailed(
          source: 'text',
          stage: 'invoke',
          reason: msg.split('\n').first,
        );
        debugPrint('parse-cv background call failed (non-blocking): $e');
        return;
      }
    }
  }
}
