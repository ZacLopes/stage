import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        // F2 da reformulação: dispara parse-cv (text-only) em background.
        // F3 da reformulação: também dispara parse-cv-vision com PDF
        // rasterizado em PNG (1-3 páginas, 150 DPI). Vision tem precedência
        // sobre text-only — quando ela termina, sobrescreve imported_resume.parsed.
        // Ambas fire-and-forget. Se vision falhar (rasterização não suportada
        // no device, PDF protegido, OpenAI timeout), text-only ainda popula
        // o parsed. Se text-only falhar, raw_text + pre-parser legacy
        // continua como último fallback.
        // ignore: unawaited_futures
        CvImportService._triggerParseCvInBackground();
        // ignore: unawaited_futures
        CvImportService._triggerParseCvVisionInBackground(byteList);
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

  /// F3 da reformulação: rasteriza o PDF em PNG (até 3 páginas, 150 DPI)
  /// e dispara `parse-cv-vision` em background. Vision lê layout (colunas,
  /// tabelas) muito melhor que o text extractor do Syncfusion + parse-cv
  /// text-only — caso real do Zac (3 experiências num CV em coluna que o
  /// Syncfusion embaralhou) deve ser resolvido aqui.
  ///
  /// Fire-and-forget. Se rasterização falhar (PDF protegido, device sem
  /// suporte) ou Vision API der erro, parse-cv text-only ainda popula
  /// o parsed normalmente.
  ///
  /// Tempo típico: 8-15s (rasterização ~2-4s + Vision ~6-10s).
  /// Custo: ~$0.005-0.01 por chamada (gpt-4o + imagens detail=high).
  static Future<void> _triggerParseCvVisionInBackground(Uint8List pdfBytes) async {
    try {
      // Rasteriza até 3 primeiras páginas em 150 DPI. CVs raramente têm
      // mais de 2 páginas — corte conservador pra reduzir custo OpenAI
      // (cada imagem detail=high = ~765 tokens).
      final pages = <String>[];
      var i = 0;
      await for (final page in Printing.raster(pdfBytes, dpi: 150, pages: [0, 1, 2])) {
        if (i >= 3) break;
        final pngBytes = await page.toPng();
        final b64 = base64Encode(pngBytes);
        // ~1MB por imagem (limite da Edge Function) cobre 150 DPI A4.
        if (b64.length > 1_500_000) {
          debugPrint('parse-cv-vision: page $i too large (${b64.length} bytes), skipping');
          continue;
        }
        pages.add(b64);
        i++;
      }
      if (pages.isEmpty) {
        debugPrint('parse-cv-vision: no pages rasterized (non-blocking)');
        return;
      }

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

      final response = await Supabase.instance.client.functions.invoke(
        'parse-cv-vision',
        body: {
          'images_base64': pages,
          if (rawText != null) 'raw_text_fallback': rawText,
        },
      );
      final data = response.data;
      if (data is! Map) return;
      final fieldsFilled = (data['fields_filled'] as num?)?.toInt() ?? 0;
      final cached = data['cached'] == true;
      final parsed = data['parsed'];
      final hasExperiences = parsed is Map &&
          parsed['experiences'] is List &&
          (parsed['experiences'] as List).isNotEmpty;
      final hasEducation = parsed is Map &&
          parsed['education'] is List &&
          (parsed['education'] as List).isNotEmpty;
      // Emite o mesmo evento de cv_import_parsed pra unificar dashboards —
      // dá pra distinguir por property `source` no evento (vision vs text).
      Analytics.shared.cvImportParsed(
        fieldsFilled: fieldsFilled,
        cached: cached,
        hasExperiences: hasExperiences,
        hasEducation: hasEducation,
      );
    } catch (e) {
      debugPrint('parse-cv-vision background call failed (non-blocking): $e');
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
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'parse-cv',
        body: const {},
      );
      final data = response.data;
      if (data is! Map) return;
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
    } catch (e) {
      // 404 profile_not_found pode acontecer logo após signup (race com
      // criação on-demand do user_profile). É esperado e benigno — o
      // parse-cv-vision em paralelo cobre o caso. Silenciar no caminho
      // esperado pra não poluir logs.
      final msg = e.toString();
      if (!msg.contains('profile_not_found')) {
        debugPrint('parse-cv background call failed (non-blocking): $e');
      }
    }
  }
}
