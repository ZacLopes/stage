// Fase 2 (casa única do perfil): exportação COMPARTILHADA do currículo geral.
//
// O CONTEÚDO do currículo geral é uma projeção VIRTUAL e EXCLUSIVA do perfil
// canônico (profile_*, via ProfileSnapshot) — o render sai sempre do snapshot,
// e NÃO considera o resumeData legado (gamificação desligada).
//
// F4.3: com a flag `trilha_assist_v1` ON, o export TAMBÉM persiste uma VERSÃO
// do documento em saved_resumes (source='general', via GeneralResumeVersionWriter
// → RPC `save_general_resume_version_v1`, com noop honesto). Isso não muda o
// render (que segue virtual): é um snapshot de saída versionado. Flag OFF
// (rollback) → nada é persistido, comportamento idêntico ao histórico. A falha
// do save NUNCA quebra o share do PDF (fail-closed, aviso honesto).
// Fonte única usada por:
//   1. Botão "Exportar PDF" do card "Currículo geral" em Perfil → Currículos.
//   2. Botão da tela de prévia (GeneralResumePreviewScreen).
//   3. Tool `export_pdf` do Assistente (via ResumeTab._exportForAssistant).
//   4. Caminho de rollback da prévia antiga (ResumeTab com trilha_assist_v1 OFF).
//
// CONTRATO ÚNICO DE CONTEÚDO (§ correção Fase 2). "Tem conteúdo profissional" é
// definido UMA vez ([_hasRenderableContent], reusado por snapshotHasContent e
// profileHasContent) e o ResumeData do PDF sai SÓ do snapshot
// (snapshot.toResumeData). As MESMAS seções aparecem na prévia e no PDF,
// INDEPENDENTE de templates_v2:
//   INCLUÍDOS: summary, experiências, formação, skills, idiomas, certificações
//   (→courses), PROJETOS (→academicProjects), PRÊMIOS (→ResumeData.awards) e
//   interesses. Todos têm seção renderável própria no PdfService. Prêmios e
//   projetos são seções INDEPENDENTES (nenhum suprime o outro) — aparecem
//   SIMULTANEAMENTE. Prêmios saem em ResumeData.awards (seção "Prêmios e
//   Reconhecimentos"), NÃO em achievements (que dividiria a área de projetos).
//   EXCLUÍDOS (documentado; a exclusão vale no predicate, na prévia e no PDF):
//   HEADLINE — toResumeData mapeia só `personal.summary`; COURSEWORK — não
//   mapeado nesta fase (fica de fora de propósito). Itens cujo texto fica vazio
//   após trim NÃO habilitam o currículo nem geram seção/linha/chip vazio.
//
// AUTORIDADE + FLAG-INDEPENDÊNCIA: o export carrega o snapshot do currículo
// geral ([loadGeneralResumeSnapshot] — as fontes USADAS são estritas: qualquer
// uma que falhar invalida a carga; coursework, por ficar de fora, é
// best-effort) e renderiza com `forceFallback:true`, então o ResumeRenderer usa
// ESTE snapshot como única fonte (origem `canonicalProfileSnapshot`), sem re-ler
// ProfilePdfData. snapshot vazio → empty; falha de carga → failed; em ambos NÃO
// gera PDF, NÃO compartilha e NÃO dispara cv_exported.

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/resume_filename.dart';
import '../../../core/utils/safe_error_text.dart';
import '../../../services/analytics_service.dart';
import '../../../services/feature_flags_service.dart';
import '../../../services/profile_snapshot_service.dart';
import '../../auth/user_viewmodel.dart';
import '../../jobs/models/adapted_resume.dart' show AdaptedResume;
import '../../profile/application/profile_editor_view_model.dart';
import '../../profile/domain/entities/entities.dart';
import '../../trilha/presentation/trilha_chat_controller.dart'
    show AssistExportOutcome;
import '../data/profile_pdf_data_loader.dart' show ProfilePdfData;
import '../resume_viewmodel.dart';
import 'general_resume_version_writer.dart';
import 'resume_renderer.dart';

class GeneralResumeExport {
  GeneralResumeExport._();

  /// Guarda global contra exportação simultânea entre superfícies (card,
  /// prévia, assistente). Uma exportação por vez.
  static bool _busy = false;
  static bool get isBusy => _busy;

  /// Definição ÚNICA de "tem conteúdo profissional renderável" — reusada pelo
  /// snapshot (export, autoridade) e pelo ViewModel (card/prévia). Só conta
  /// itens com texto após trim (projetos usam [ProfilePdfData.projectHasRenderableText],
  /// o MESMO critério do mapper e da prévia); NÃO conta headline nem coursework
  /// (ver contrato no topo do arquivo).
  static bool _hasRenderableContent({
    required bool hasSummary,
    required List<Experience> experiences,
    required List<Education> education,
    required List<Skill> skills,
    required List<Language> languages,
    required List<Certification> certifications,
    required List<Project> projects,
    required List<Award> awards,
    required List<Interest> interests,
  }) {
    return hasSummary ||
        experiences.any(
          (e) => e.title.trim().isNotEmpty || e.company.trim().isNotEmpty,
        ) ||
        education.any(
          (e) =>
              e.institution.trim().isNotEmpty ||
              (e.degree ?? '').trim().isNotEmpty ||
              e.majors.any((m) => m.name.trim().isNotEmpty),
        ) ||
        skills.any((s) => s.name.trim().isNotEmpty) ||
        languages.any((l) => l.name.trim().isNotEmpty) ||
        certifications.any((c) => c.name.trim().isNotEmpty) ||
        projects.any(ProfilePdfData.projectHasRenderableText) ||
        awards.any((a) => a.name.trim().isNotEmpty) ||
        interests.any((i) => i.name.trim().isNotEmpty);
  }

  /// Autoridade do export: o snapshot fresco tem conteúdo renderável?
  static bool snapshotHasContent(ProfileSnapshot s) => _hasRenderableContent(
    hasSummary: (s.personal?.summary ?? '').trim().isNotEmpty,
    experiences: s.experiences,
    education: s.education,
    skills: s.skills,
    languages: s.languages,
    certifications: s.certifications,
    projects: s.projects,
    awards: s.awards,
    interests: s.interests,
  );

  /// Mesma definição a partir do ProfileEditorViewModel (fonte reativa do card e
  /// da prévia). NÃO considera resumeData legado.
  static bool profileHasContent(ProfileEditorViewModel p) =>
      _hasRenderableContent(
        hasSummary: (p.personal?.summary ?? '').trim().isNotEmpty,
        experiences: p.experiences,
        education: p.education,
        skills: p.skills,
        languages: p.languages,
        certifications: p.certifications,
        projects: p.projects,
        awards: p.awards,
        interests: p.interests,
      );

  /// Núcleo testável do export, com dependências injetáveis. NÃO toca em
  /// saved_resumes. Ordem: guarda de concorrência → snapshot fresco (autoridade)
  /// → conteúdo? → gera+compartilha → cv_exported.
  ///
  /// - uid null → failed (sessão expirada).
  /// - loadSnapshot lança (consulta falhou) → failed (sem PDF, sem analytics).
  /// - snapshot sem conteúdo → empty (sem PDF, sem analytics).
  /// - emitPdf lança (folha não abriu) → failed, sem cv_exported.
  /// - sucesso → onExported() 1× → ok.
  static Future<AssistExportOutcome> runExport({
    required String? uid,
    required Future<ProfileSnapshot> Function(String uid) loadSnapshot,
    required Future<void> Function(ProfileSnapshot snapshot) emitPdf,
    required void Function() onExported,
    void Function(Object error)? onError,
    void Function(bool)? onBusyChanged,
  }) async {
    if (_busy) return AssistExportOutcome.failed;
    _busy = true;
    try {
      // Dentro do try: se onBusyChanged lançar, o finally ainda reseta _busy
      // (a guarda é estática/global — não pode "grudar" e travar o export).
      onBusyChanged?.call(true);

      if (uid == null) {
        onError?.call(
          Exception('Sessão expirada — entre novamente para exportar.'),
        );
        return AssistExportOutcome.failed;
      }

      // Autoridade final: snapshot ESTRITO. Falha de consulta propaga aqui.
      ProfileSnapshot snapshot;
      try {
        snapshot = await loadSnapshot(uid);
      } catch (e) {
        onError?.call(e);
        return AssistExportOutcome.failed;
      }

      // Snapshot carregado (todas as consultas OK) mas vazio → não gera PDF.
      if (!snapshotHasContent(snapshot)) {
        return AssistExportOutcome.empty;
      }

      try {
        await emitPdf(snapshot);
        // cv_exported só DEPOIS que a folha de compartilhar abriu.
        onExported();
        return AssistExportOutcome.ok;
      } catch (e) {
        onError?.call(e);
        return AssistExportOutcome.failed;
      }
    } finally {
      _busy = false;
      onBusyChanged?.call(false);
    }
  }

  /// Exporta o currículo geral como PDF compartilhável, lendo as dependências de
  /// produção do [context]. [loadSnapshot] é injetável (default: loader ESTRITO)
  /// — solução específica pra este export, sem afetar o loadSnapshot best-effort.
  static Future<AssistExportOutcome> export(
    BuildContext context, {
    void Function(bool)? onBusyChanged,
    Future<ProfileSnapshot> Function(String uid)? loadSnapshot,
    GeneralResumeVersionWriter? versionWriter,
    /// Template do Currículo geral, explícito.
    ///
    /// Antes o export lia SEMPRE o `selectedTemplateId` global — o mesmo
    /// singleton do CV adaptado e do CV da trilha —, e o card escrevia nele ao
    /// montar. Passar explícito mantém a escolha do Currículo geral contida
    /// nele (code-review 27/07). Null ⇒ mantém o comportamento anterior.
    String? templateId,
  }) async {
    final userVM = context.read<UserViewModel>();
    final resumeVM = context.read<ResumeViewModel>();
    final user = userVM.user;
    final uid = user?.id ?? Supabase.instance.client.auth.currentUser?.id;
    final effectiveTemplateId =
        templateId ?? resumeVM.selectedTemplateId; // padrão: harvard_ats

    // F4.3: com a flag ON, o export também persiste uma versão. Flag OFF
    // (rollback) → não instancia writer nem salva (comportamento idêntico ao
    // histórico). A falha do save nunca quebra o share.
    // 20/08/2026: era `isTrilhaAssistEnabledForUser`, e o resultado medido foi
    // ZERO linhas `source='general'` na base inteira — o app gerava o PDF,
    // compartilhava e não guardava cópia. Agora tem chave própria (aninhada
    // no Assistente), pra poder ligar sem arrastar as outras consequências.
    final saveEnabled = FeatureFlagsService.instance
        .isGeneralResumeSaveEnabledForUser(uid);
    final writer = saveEnabled
        ? (versionWriter ?? GeneralResumeVersionWriter.production())
        : null;
    GeneralResumeSaveStatus? saveStatus;

    final outcome = await runExport(
      uid: uid,
      loadSnapshot:
          loadSnapshot ??
          (id) => ProfileSnapshotService().loadGeneralResumeSnapshot(id),
      emitPdf: (snapshot) async {
        // Contrato único: o ResumeData vem SÓ do snapshot (mesmas seções da
        // prévia). forceFallback → renderiza este snapshot (flag-independente,
        // sem re-ler ProfilePdfData).
        final resume = snapshot.toResumeData(userFallbackName: user?.name);
        final rendered = await ResumeRenderer.render(
          userId: uid,
          user: user,
          fallbackResume: resume,
          templateId: effectiveTemplateId,
          purpose: 'export',
          forceFallback: true,
        );
        // Auto-save da versão ANTES do share (flag ON). O writer nunca lança:
        // falha vira status.failed e o share segue normal.
        if (writer != null && uid != null) {
          final receipt = await writer.save(
            uid: uid,
            resumeData: AdaptedResume.serializeResumeData(resume),
            templateId: effectiveTemplateId,
            pdfBytes: rendered.bytes,
            title: 'Currículo geral',
          );
          saveStatus = receipt.status;
          Analytics.shared.generalResumeVersionSaved(
            status: receipt.status.name,
            templateId: effectiveTemplateId,
          );
        }
        // B1: `user.name` é '' (não NULL) para 110 usuários em prod — o `??`
        // não disparava e o arquivo saía `curriculo_.pdf`. A política agora é
        // única e cai no nome impresso NO documento antes do nome da conta.
        await Printing.sharePdf(
          bytes: rendered.bytes,
          filename: ResumeFilename.build(
            preferredName: resume.fullName,
            accountName: user?.name,
          ),
        );
      },
      onExported: () => Analytics.shared.cvExported(templateId: effectiveTemplateId),
      onError: (e) {
        // A3 (device-test §9) reaberto pelo code-review de 27/07: interpolar
        // `$e` aqui punha `ClientException … uri=https://<projeto>.supabase.co`
        // na tela. O detalhe técnico fica no log; a UI recebe texto humano.
        debugPrint('[GeneralResumeExport] falha no export: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                SafeErrorText.orFallback(
                  e,
                  'Não consegui gerar o PDF agora. Tente de novo.',
                ),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      },
      onBusyChanged: onBusyChanged,
    );

    // Save falhou mas o PDF foi compartilhado (outcome ok): fala a verdade sem
    // quebrar o fluxo — o share aconteceu.
    if (outcome == AssistExportOutcome.ok &&
        saveStatus == GeneralResumeSaveStatus.failed &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'PDF exportado, mas não consegui salvar esta versão no seu perfil.',
          ),
        ),
      );
    }
    return outcome;
  }
}
