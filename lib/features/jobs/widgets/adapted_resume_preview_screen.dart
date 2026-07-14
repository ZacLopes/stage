import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/models.dart' show ResumeCourse, SavedResumeSource;
import '../../../services/analytics_service.dart';
import '../../auth/user_viewmodel.dart';
import '../../profile/profile_viewmodel.dart';
import '../../resume/services/resume_renderer.dart';
import '../../resume/resume_viewmodel.dart';
import '../job_swipe_context.dart';
import '../models/adapted_resume.dart';
import '../models/job.dart';
import '../pending_adapted_cv_tracker.dart';
import 'resume_block_editor.dart';
import '../../../core/theme/theme.dart';

/// Tela full-screen de preview do CV adaptado pela IA (F1 da reformulação).
///
/// Substitui a lista de "changes" diff da sheet anterior por uma visualização
/// editável do currículo inteiro. Princípios:
/// - Usuário nunca baixa PDF "no escuro" — vê o resultado renderizado antes.
/// - Cada bloco é editável; tap em qualquer campo abre TextField inline.
/// - Toggle "Adaptado | Original | Lado a lado" pra comparar.
/// - Botão "Voltar ao original" por campo (chip "Mudou") + global.
/// - Telemetria via [Analytics.cvAdaptationUserEdited] alimenta o sinal
///   "o que a IA está errando" pra próximas fases (validador semântico).
///
/// Renderização: Flutter nativo (não WebView). Permite edição direta sem
/// JavaScript bridge e garante consistência cross-platform.
class AdaptedResumePreviewScreen extends StatefulWidget {
  /// Adaptação original vinda do servidor (com IA aplicada).
  final AdaptedResume adapted;

  /// Vaga alvo da adaptação. Usado no header e na telemetria.
  final Job job;

  /// CV "original" do usuário antes de qualquer adaptação, usado no toggle
  /// "Original | Adaptado". Pós Fase 2 da migração profile-first vem do
  /// snapshot das tabelas relacionais `profile_*` (via
  /// `ProfileSnapshotService` no caller). Se null, o toggle cai no
  /// fallback (mostra adapted como original).
  final ResumeData? originalResumeData;

  const AdaptedResumePreviewScreen({
    super.key,
    required this.adapted,
    required this.job,
    this.originalResumeData,
  });

  @override
  State<AdaptedResumePreviewScreen> createState() =>
      _AdaptedResumePreviewScreenState();
}

/// Metadata dos 4 templates exibidos no seletor inline. Mantém em sync com
/// `_templates` em `resume_template_selector.dart` e o switch em
/// `PdfService.generateResumeBytes`.
const List<_AdaptedTemplateOption> _kAdaptedTemplates = [
  _AdaptedTemplateOption(
    id: 'harvard_ats',
    label: 'Harvard ATS',
    description: 'Clássico, ideal pra IB/Consulting/Corporate',
    thumbnail: 'assets/images/templates/harvard_ats.png',
  ),
  _AdaptedTemplateOption(
    id: 'jakes_resume',
    label: "Jake's Resume",
    description: 'Tech/dev, FAANG-friendly',
    thumbnail: 'assets/images/templates/jakes_resume.png',
  ),
  _AdaptedTemplateOption(
    id: 'forte_foundation',
    label: 'Forte Foundation',
    description: 'Banking/MBA, conservador',
    thumbnail: 'assets/images/templates/forte_foundation.png',
  ),
  _AdaptedTemplateOption(
    id: 'one_page_compact',
    label: 'One-Page Compact',
    description: 'Estudante early-career, sans-serif moderno',
    thumbnail: 'assets/images/templates/one_page_compact.png',
  ),
  _AdaptedTemplateOption(
    id: 'cobalt_modern',
    label: 'Cobalt Modern',
    description: '2 colunas com sidebar, sans-serif moderno, accent azul cobalt',
    thumbnail: 'assets/images/templates/cobalt_modern.png',
  ),
];

class _AdaptedTemplateOption {
  final String id;
  final String label;
  final String description;
  final String thumbnail;
  const _AdaptedTemplateOption({
    required this.id,
    required this.label,
    required this.description,
    required this.thumbnail,
  });
}

class _AdaptedResumePreviewScreenState extends State<AdaptedResumePreviewScreen> {
  late ResumeData _current;
  late final ResumeData _aiAdapted;
  late final ResumeData _original;
  _ViewMode _mode = _ViewMode.adapted;
  bool _isExporting = false;

  // Quando true, mostra widgets editáveis em vez do PDF preview na aba
  // "Adaptado". Default false (preview do PDF real) — user clica em "Editar"
  // pra entrar no modo edição. Quando ele edita, _invalidatePreviewPdfs
  // garante que o PDF re-renderiza pra refletir a mudança quando volta.
  bool _editingAdapted = false;

  // Template selecionado PRA ESSA VAGA especificamente. Default = preferência
  // global do user (`ResumeViewModel.selectedTemplateId`), mas user pode
  // trocar pra esse job sem afetar a global. Persistido em SharedPreferences
  // com key `_adapted_template_<jobId>`.
  late String _selectedTemplateId;

  // Cache de PDFs renderizados por template. Gerado em background no
  // initState (1 task por template). Quando user troca template no seletor,
  // mostra o PDF correspondente cacheado aqui. Se ainda não terminou, mostra
  // spinner até `_previewPdfBytes[templateId]` ficar disponível.
  final Map<String, Uint8List> _previewPdfBytes = {};
  final Set<String> _previewPdfLoading = {};

  // Tier 2.6: PDF binário do CV importado (do saved_resumes Storage).
  // Mostrado na aba "Original" pra evitar o bug do Syncfusion ("Ci"
  // inserido em palavras) — o PDF binário não passa por extração textual.
  // null enquanto carrega ou se Storage não tem arquivo (fallback ao
  // render do ResumeData legacy).
  Uint8List? _originalPdfBytes;
  bool _originalPdfFetchAttempted = false;

  static String _templatePrefKey(String jobId) => '_adapted_template_$jobId';

  @override
  void initState() {
    super.initState();
    _aiAdapted = widget.adapted.resumeData;
    _current = widget.adapted.effectiveResumeData;
    // Default template: preferência global; sobrescrita por escolha
    // específica deste job (carregada em _loadSelectedTemplate).
    _selectedTemplateId = context.read<ResumeViewModel>().selectedTemplateId;
    _loadSelectedTemplate();
    // Ordem de preferência pro CV "original" no toggle:
    //   1. Injetado pelo caller (snapshot das tabelas profile_* via
    //      ProfileSnapshotService).
    //   2. ResumeData do ResumeViewModel (caso o user tenha criado CV
    //      via editor/trilha em vez de importar PDF).
    //   3. Fallback pro próprio adapted (toggle perde a função mas a
    //      tela continua usável).
    _original = widget.originalResumeData ??
        context.read<ResumeViewModel>().resumeData ??
        _aiAdapted;
    // Dispara fetch do PDF binário do Storage em background. Se sucesso,
    // a aba "Original" troca pro PDF real. Se falhar, mantém fallback
    // (render do _original ResumeData via widgets nativos).
    _fetchOriginalPdfBytes();

    // Pre-render dos 5 templates em background. Quando user troca template
    // no seletor inline, mostra o PDF cacheado aqui — preview real do que
    // vai sair no "Baixar PDF". Prioriza o template selecionado primeiro
    // pra ele aparecer rápido; outros vão ficando prontos enquanto user
    // interage com a tela.
    _startPdfPreviewGeneration();
    // T2.3 — diff do CV adaptado exibido (tela de preview). Step do meio do
    // funil adapt→apply. adapt_diff_shown não tinha emissor no app.
    Analytics.shared.adaptDiffShown(
      jobId: widget.job.id,
      bulletsChangedCount: widget.adapted.changes.length,
      additionsCount: widget.adapted.extraSkillsUsed.length,
    );
  }

  /// Dispara render dos 5 templates em sequência (não paralelo — render é
  /// pesado, paralelo pode travar UI). Prioriza o template SELECIONADO
  /// primeiro pra latência percebida ser baixa. Cada PDF é cacheado em
  /// `_previewPdfBytes`. Re-render quando user edita `_current`.
  Future<void> _startPdfPreviewGeneration() async {
    // Ordem: selected primeiro, depois os outros.
    final order = <String>[
      _selectedTemplateId,
      ..._kAdaptedTemplates
          .map((t) => t.id)
          .where((id) => id != _selectedTemplateId),
    ];
    for (final templateId in order) {
      if (!mounted) return;
      await _generatePdfForTemplate(templateId);
    }
  }

  /// Render de UM template específico. Idempotente: se já existe no cache
  /// E `_current` não mudou, retorna sem fazer nada. Em caso de erro,
  /// fallback silencioso — aba mostra widgets nativos (legacy path).
  Future<void> _generatePdfForTemplate(String templateId) async {
    if (_previewPdfBytes.containsKey(templateId)) return;
    if (_previewPdfLoading.contains(templateId)) return;
    if (!mounted) return;
    setState(() => _previewPdfLoading.add(templateId));
    try {
      final user = context.read<UserViewModel>().user;
      final rendered = await ResumeRenderer.render(
        userId: user?.id,
        user: user,
        fallbackResume: _current,
        templateId: templateId,
        // Render auxiliar pro template picker — não conta como
        // `pdf_generated` (Bug 4: evitar inflar count com thumbnails).
        purpose: 'preview',
      );
      if (!mounted) return;
      setState(() {
        _previewPdfBytes[templateId] = rendered.bytes;
        _previewPdfLoading.remove(templateId);
      });
    } catch (e) {
      if (!mounted) return;
      // ignore: avoid_print
      print('[AdaptedResumePreviewScreen] preview render failed for $templateId: $e');
      setState(() => _previewPdfLoading.remove(templateId));
    }
  }

  /// Invalida cache de previews quando `_current` muda (user editou um
  /// campo no resume_block_editor). Re-dispara generation pra refletir
  /// edits no PDF preview. setState garante que o UI rebuilde mostrando
  /// loading state imediatamente (em vez de continuar mostrando PDF stale).
  void _invalidatePreviewPdfs() {
    if (!mounted) return;
    setState(() {
      _previewPdfBytes.clear();
      _previewPdfLoading.clear();
    });
    // ignore: unawaited_futures
    _startPdfPreviewGeneration();
  }

  /// Carrega template específico desse job de SharedPreferences. Se nada
  /// salvo, mantém o default (`_selectedTemplateId` já setado em initState
  /// pra preferência global). Async — não bloqueia render inicial.
  Future<void> _loadSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_templatePrefKey(widget.job.id));
      if (saved == null || saved.isEmpty) return;
      // Valida que é um dos templates conhecidos (case o user tenha CV
      // antigo com template removido).
      final valid = _kAdaptedTemplates.any((t) => t.id == saved);
      if (!valid) return;
      if (!mounted) return;
      setState(() => _selectedTemplateId = saved);
    } catch (_) {
      // Falha silenciosa — mantém default global.
    }
  }

  /// User trocou template no seletor inline. Persiste pra esse job, mostra
  /// o PDF cacheado do template novo (se já gerado), e dispara render dele
  /// se ainda não estiver no cache.
  Future<void> _changeTemplate(String newTemplateId) async {
    if (newTemplateId == _selectedTemplateId) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedTemplateId = newTemplateId);
    // ignore: unawaited_futures
    Analytics.shared.cvTemplateChanged(templateId: newTemplateId);
    // Se ainda não tem o PDF do template novo no cache, gera agora
    // (prioritário porque user acabou de pedir).
    // ignore: unawaited_futures
    _generatePdfForTemplate(newTemplateId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_templatePrefKey(widget.job.id), newTemplateId);
    } catch (_) {
      // Falha silenciosa — escolha vale só pra sessão atual.
    }
  }

  Future<void> _fetchOriginalPdfBytes() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        _originalPdfFetchAttempted = true;
        return;
      }
      // Busca o saved_resume mais recente com source='imported' ou 'manual'.
      // Mesma query usada por backfill_extract_profile.ts.
      final rows = await Supabase.instance.client
          .from('saved_resumes')
          .select('file_path')
          .eq('user_id', userId)
          .inFilter('source', ['imported', 'manual'])
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final filePath = (rows.first as Map)['file_path'] as String?;
        if (filePath != null && filePath.isNotEmpty) {
          final bytes = await Supabase.instance.client.storage
              .from('resumes')
              .download(filePath);
          if (mounted) {
            setState(() {
              _originalPdfBytes = bytes;
              _originalPdfFetchAttempted = true;
            });
          }
          return;
        }
      }
    } catch (e) {
      // Falha silenciosa: aba "Original" cai pro fallback render do
      // ResumeData. Log só pra debug.
      // ignore: avoid_print
      print('[AdaptedResumePreviewScreen] fetch original PDF failed: $e');
    }
    if (mounted) {
      setState(() => _originalPdfFetchAttempted = true);
    }
  }

  /// Substitui o `_current` por um clone com uma mudança específica.
  /// Notifica PostHog para alimentar dashboards de qualidade.
  void _update({
    required String field,
    required ResumeData Function(ResumeData) mutate,
    String editType = 'replace',
  }) {
    final before = _current;
    final after = mutate(_current);
    if (identical(before, after)) return;
    setState(() => _current = after);
    // PDF previews cacheados estão stale agora — invalida e re-dispara
    // geração pra refletir o edit. Async, não bloqueia o feedback de edit.
    _invalidatePreviewPdfs();
    // Telemetria assíncrona — não bloqueia UI.
    // ignore: unawaited_futures
    Analytics.shared.cvAdaptationUserEdited(
      jobId: widget.job.id,
      field: field,
      editType: editType,
      charDiff: _measureDiff(before, after, field),
    );
  }

  int _measureDiff(ResumeData before, ResumeData after, String field) {
    // Heurística simples: para campos string-puros, diferença de length.
    // Para listas e nested, retorna 0 (sinal só de "houve mudança").
    String? bv;
    String? av;
    switch (field) {
      case 'summary':
        bv = before.summary;
        av = after.summary;
        break;
      case 'phone':
        bv = before.phone;
        av = after.phone;
        break;
      case 'email':
        bv = before.email;
        av = after.email;
        break;
      case 'location':
        bv = before.location;
        av = after.location;
        break;
      case 'linkedin':
        bv = before.linkedin;
        av = after.linkedin;
        break;
    }
    if (bv == null || av == null) return 0;
    return av.length - bv.length;
  }

  /// Dialog de confirmação animado pós-save. Mostra check verde com
  /// bounce, título "CV salvo na biblioteca", subtítulo orientando
  /// onde achar, e 2 CTAs: "Ver na biblioteca" (não implementa
  /// navegação cross-tab daqui — apenas fecha; user vai na aba Perfil)
  /// e "Fechar".
  Future<void> _showSavedConfirmation() async {
    HapticFeedback.lightImpact();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => _SavedConfirmationDialog(jobTitle: widget.job.title),
    );
  }

  /// Sanitiza nome de vaga/empresa pra título da biblioteca. Remove
  /// caracteres problemáticos pra filename e trunca pra não estourar UI.
  String _sanitizeForTitle(String s) {
    final cleaned = s
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.length > 60 ? '${cleaned.substring(0, 57)}…' : cleaned;
  }

  Future<void> _approveAndDownload() async {
    // Fix QA Dia 8: early return contra double-tap. O botão tem guard
    // `_isExporting ? null` no onPressed, mas em taps muito rápidos (mesmo
    // frame, antes do rebuild) o Flutter dispara duas vezes. Resultado
    // observado: 2x `adapt_pdf_downloaded` em sequência (~18s) + `RangeError`
    // do PdfPreview rasterizando uma State já em disposal. Guard sincrono
    // aqui é a única forma de cortar antes do `setState` agendar o rebuild.
    if (_isExporting) return;
    HapticFeedback.mediumImpact();
    setState(() => _isExporting = true);
    try {
      final user = context.read<UserViewModel>().user;
      // Usa o template selecionado PRA ESSA VAGA. Default vem do preferred
      // global do user, mas pode ter sido trocado no seletor inline.
      final templateId = _selectedTemplateId;
      final profileVM = context.read<ProfileViewModel>();

      // F8: gera bytes uma vez, salva na biblioteca COM nome da vaga, e
      // depois compartilha. O save substitui o antigo banner persistente
      // ("Seu CV pra X tá pronto") — agora o CV adaptado fica permanente
      // na biblioteca, com source='adapted' pra UI colorir distintamente.
      // ResumeRenderer respeita feature flag templates_v2 + fallback v1.
      final rendered = await ResumeRenderer.render(
        userId: user?.id,
        user: user,
        fallbackResume: _current,
        templateId: templateId,
        // Download de CV adaptado pra vaga (B.15 → pdf_generated meaningful).
        purpose: 'adapt_download',
      );
      final bytes = rendered.bytes;

      final jobTitle = _sanitizeForTitle(widget.job.title);
      final company = _sanitizeForTitle(widget.job.companyName);
      final libraryTitle = company.isEmpty
          ? 'CV adaptado - $jobTitle'
          : 'CV adaptado - $jobTitle - $company';

      // C5: save na biblioteca — antes era catch silencioso, agora
      // rastreamos falha e avisamos o user. Save é não-fatal pro download
      // (PDF é compartilhado mesmo se save falhar), mas user precisa saber
      // que biblioteca não persistiu — senão volta esperando o CV lá.
      //
      // Persiste o `resume_data` estruturado + `template_id` pra habilitar
      // troca de template depois (biblioteca → detail screen → seletor).
      // Migration 20260526 adicionou essas colunas.
      bool savedToLibrary = false;
      try {
        await profileVM.saveResume(
          libraryTitle,
          bytes,
          source: SavedResumeSource.adapted,
          resumeData: AdaptedResume.serializeResumeData(_current),
          templateId: templateId,
        );
        savedToLibrary = true;
      } catch (e, stack) {
        debugPrint('[adapted_preview] saveResume failed: $e\n$stack');
        // ignore: unawaited_futures
        Analytics.shared.cvLibrarySaveFailed(
          jobId: widget.job.id,
          error: e.toString(),
        );
      }

      // Compartilha o PDF via share sheet nativo. Mesmo se o save falhar,
      // o usuário ainda recebe o arquivo.
      final safeName = (user?.name ?? 'profissional').replaceAll(' ', '_');
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'curriculo_${safeName}_${widget.job.id.substring(0, 6)}.pdf',
      );

      // ignore: unawaited_futures
      Analytics.shared.cvAdaptationPdfDownloaded(jobId: widget.job.id);
      // Fix QA Dia 8 (Bug 1): marca essa vaga como "user adaptou CV" num
      // storage persistente. Sem isso, `used_adapted_cv` no apply (Curtidas)
      // sempre vinha null, quebrando a métrica do pitch.
      // ignore: unawaited_futures
      JobSwipeContext.shared.markAdapted(widget.job.id);
      // ignore: unawaited_futures
      PendingAdaptedCvTracker.shared.clear();
      if (!mounted) return;

      // Se save falhou, mostra toast informativo. User recebeu o PDF mas
      // não terá o CV na biblioteca — precisa saber pra não esperar achar
      // depois.
      if (!savedToLibrary) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'PDF gerado, mas não consegui guardar uma cópia em Currículos.',
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
        // ignore: unawaited_futures
        Navigator.of(context).pop(true);
        return;
      }

      // F8: confirmação animada antes do pop. Dá feedback explícito
      // que o CV ficou salvo permanente na biblioteca (sinal que
      // substitui o antigo banner persistente).
      await _showSavedConfirmation();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar PDF: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _restoreAllToOriginal() {
    HapticFeedback.mediumImpact();
    setState(() => _current = _aiAdapted);
    // ignore: unawaited_futures
    Analytics.shared.cvAdaptationUserEdited(
      jobId: widget.job.id,
      field: 'all',
      editType: 'restore_original',
      charDiff: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildModeToggle(),
            Expanded(child: _buildBody()),
            _buildFooter(mq),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Revisar antes de baixar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (_hasEdits)
            TextButton.icon(
              onPressed: _restoreAllToOriginal,
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: const Text(
                'Voltar tudo',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandCyan,
              ),
            ),
          // Toggle Editar/Visualizar — só visível na aba "Adaptado". Em
          // "Original" não faz sentido (PDF do user é imutável aqui).
          if (_mode == _ViewMode.adapted)
            IconButton(
              tooltip: _editingAdapted ? 'Voltar ao preview' : 'Editar campos',
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _editingAdapted = !_editingAdapted);
              },
              icon: Icon(
                _editingAdapted
                    ? Icons.visibility_rounded
                    : Icons.edit_rounded,
                size: 20,
                color: _editingAdapted
                    ? AppColors.brandCyan
                    : AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  bool get _hasEdits {
    final a = _aiAdapted;
    final c = _current;
    return a.fullName != c.fullName ||
        a.email != c.email ||
        a.phone != c.phone ||
        a.linkedin != c.linkedin ||
        a.location != c.location ||
        a.summary != c.summary ||
        !_listEq(a.skills, c.skills) ||
        !_listEq(a.achievements, c.achievements) ||
        !_listEq(a.interests, c.interests) ||
        !_experienceListEq(a.experiences, c.experiences) ||
        !_educationListEq(a.education, c.education) ||
        !_coursesEq(a.courses, c.courses);
  }

  bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _experienceListEq(List<ExperienceItem> a, List<ExperienceItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].role != b[i].role ||
          a[i].company != b[i].company ||
          a[i].period != b[i].period ||
          a[i].description != b[i].description ||
          a[i].location != b[i].location) return false;
    }
    return true;
  }

  bool _coursesEq(List<ResumeCourse> a, List<ResumeCourse> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].title != b[i].title) return false;
    }
    return true;
  }

  bool _educationListEq(List<EducationItem> a, List<EducationItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].degree != b[i].degree ||
          a[i].institution != b[i].institution ||
          a[i].period != b[i].period ||
          a[i].details != b[i].details ||
          a[i].location != b[i].location) return false;
    }
    return true;
  }

  Widget _buildModeToggle() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          // Toggle Adaptado/Original — ocupa o espaço disponível
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  _buildToggleButton(_ViewMode.adapted, 'Adaptado'),
                  _buildToggleButton(_ViewMode.original, 'Original'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botão de selecionar template — abre bottom sheet com 4 opções.
          // Só faz sentido na aba "Adaptado" (Original usa PDF binário do
          // Storage, não re-renderiza). Mas mantemos sempre visível pra
          // não causar layout shift quando trocar de aba.
          _buildTemplateButton(),
        ],
      ),
    );
  }

  /// Botão compacto que abre o bottom sheet de seleção de template.
  Widget _buildTemplateButton() {
    final selected = _kAdaptedTemplates.firstWhere(
      (t) => t.id == _selectedTemplateId,
      orElse: () => _kAdaptedTemplates.first,
    );
    return GestureDetector(
      onTap: _openTemplatePicker,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.dashboard_customize_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              selected.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet com os 4 templates + thumbnails. User clica em um,
  /// sheet fecha, e o preview re-renderiza com o novo template.
  void _openTemplatePicker() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Escolher modelo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'O modelo afeta só o visual — o conteúdo adaptado fica o mesmo.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ..._kAdaptedTemplates.map((t) {
                  final isSelected = t.id == _selectedTemplateId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _changeTemplate(t.id);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.brandCyan.withOpacity(0.06)
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.brandCyan
                                : AppColors.border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.asset(
                                t.thumbnail,
                                width: 56,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 56,
                                  height: 72,
                                  color: AppColors.border,
                                  child: const Icon(
                                    Icons.description_outlined,
                                    color: AppColors.textDisabled,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t.label,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: isSelected
                                                ? AppColors.brandCyan
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle_rounded,
                                          size: 18,
                                          color: AppColors.brandCyan,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    t.description,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textTertiary,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToggleButton(_ViewMode mode, String label) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _mode = mode);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.textPrimary : AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    // Tier 2.6: aba "Original" mostra o PDF binário do user direto do
    // Storage (saved_resumes). Bypassa o ResumeData legacy + Syncfusion
    // text extraction (que insere "Ci" em palavras). Resultado: aba
    // "Original" = exatamente o PDF que o user subiu.
    if (_mode == _ViewMode.original && _originalPdfBytes != null) {
      return _buildOriginalPdfView(_originalPdfBytes!);
    }

    // Aba "Adaptado": prioriza mostrar o PDF real renderizado (do cache
    // `_previewPdfBytes`). Assim a troca de template é visualmente óbvia
    // — o user vê EXATAMENTE o que vai sair no "Baixar PDF". Edição
    // continua acessível via toggle "Editar" no header.
    if (_mode == _ViewMode.adapted && !_editingAdapted) {
      final bytes = _previewPdfBytes[_selectedTemplateId];
      if (bytes != null) {
        return _buildAdaptedPdfView(bytes);
      }
      // Sem PDF ainda — em geração ou inicial. Mostra spinner com label
      // do template que está sendo gerado pra dar contexto.
      if (_previewPdfLoading.contains(_selectedTemplateId) ||
          _previewPdfBytes.isEmpty) {
        return _buildAdaptedPdfLoading();
      }
      // Edge case: cache sem essa key e não está loading. Cai pro
      // editable view (legacy fallback) e re-dispara render em background.
      // ignore: unawaited_futures
      _generatePdfForTemplate(_selectedTemplateId);
    }

    // Modo edição ou fallback: renderiza widgets editáveis nativos.
    final data = _mode == _ViewMode.original ? _original : _current;
    final readOnly = _mode == _ViewMode.original;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          children: [
            _buildResumeCard(data: data, readOnly: readOnly),
          ],
        ),
        if (_mode == _ViewMode.original && !_originalPdfFetchAttempted)
          const Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brandCyan,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Render do PDF adaptado pelo template selecionado via `PdfPreview`.
  /// Read-only — pra editar, user clica em "Editar" no header (toggle
  /// `_editingAdapted = true`).
  Widget _buildAdaptedPdfView(Uint8List bytes) {
    return Container(
      color: AppColors.border,
      child: PdfPreview(
        // Key força recriação do widget quando trocamos template/bytes —
        // sem isso, PdfPreview pode cachear o PDF anterior internamente.
        key: ValueKey('adapted_pdf_${_selectedTemplateId}_${bytes.length}'),
        build: (_) => bytes,
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        loadingWidget: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.brandCyan,
          ),
        ),
      ),
    );
  }

  /// Loading state enquanto o PDF do template selecionado está sendo
  /// gerado em background. Mostra spinner + nome do template pra dar
  /// contexto ao user.
  Widget _buildAdaptedPdfLoading() {
    final selected = _kAdaptedTemplates.firstWhere(
      (t) => t.id == _selectedTemplateId,
      orElse: () => _kAdaptedTemplates.first,
    );
    return Container(
      color: AppColors.border,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 36,
              width: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.brandCyan,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Gerando preview de "${selected.label}"...',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Render real do PDF — leva 1-2s',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Render do PDF original do Storage via PdfPreview do package `printing`.
  /// Read-only — sem botões de export/print (a tela já tem o botão
  /// principal "Baixar PDF" pro adaptado).
  Widget _buildOriginalPdfView(Uint8List bytes) {
    return Container(
      color: AppColors.border,
      child: PdfPreview(
        build: (_) => bytes,
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        loadingWidget: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.brandCyan,
          ),
        ),
      ),
    );
  }

  Widget _buildResumeCard({required ResumeData data, required bool readOnly}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(data, readOnly),
          const SizedBox(height: 18),
          if (data.summary.isNotEmpty || !readOnly) ...[
            _buildSectionTitle('Resumo'),
            ResumeBlockEditor(
              value: data.summary,
              original: _aiAdapted.summary,
              hint: 'Resumo profissional',
              multiline: true,
              readOnly: readOnly,
              maxLength: 600,
              textStyle: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary),
              onChanged: (v) => _update(
                field: 'summary',
                mutate: (d) => d.copyWith(summary: v),
              ),
              onRestoreOriginal: _aiAdapted.summary != data.summary
                  ? () => _update(
                        field: 'summary',
                        editType: 'restore_original',
                        mutate: (d) => d.copyWith(summary: _aiAdapted.summary),
                      )
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (data.skills.isNotEmpty || !readOnly) ...[
            ResumeListEditor(
              value: data.skills,
              original: _aiAdapted.skills,
              label: 'HABILIDADES',
              addHint: 'Nova habilidade',
              onChanged: (v) => _update(
                field: 'skills',
                mutate: (d) => d.copyWith(skills: v),
              ),
              onRestoreOriginal: !_listEq(_aiAdapted.skills, data.skills)
                  ? () => _update(
                        field: 'skills',
                        editType: 'restore_original',
                        mutate: (d) => d.copyWith(skills: _aiAdapted.skills),
                      )
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (data.experiences.isNotEmpty) ...[
            _buildSectionTitle('Experiência'),
            ...List.generate(data.experiences.length, (i) {
              final exp = data.experiences[i];
              final origExp = i < _aiAdapted.experiences.length
                  ? _aiAdapted.experiences[i]
                  : exp;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildExperienceBlock(exp, origExp, i, readOnly),
              );
            }),
            const SizedBox(height: 4),
          ],
          if (data.education.isNotEmpty) ...[
            _buildSectionTitle('Formação'),
            ...List.generate(data.education.length, (i) {
              final ed = data.education[i];
              final origEd = i < _aiAdapted.education.length
                  ? _aiAdapted.education[i]
                  : ed;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildEducationBlock(ed, origEd, i, readOnly),
              );
            }),
            const SizedBox(height: 4),
          ],
          if (data.achievements.isNotEmpty || !readOnly) ...[
            ResumeListEditor(
              value: data.achievements,
              original: _aiAdapted.achievements,
              label: 'CONQUISTAS',
              addHint: 'Nova conquista',
              onChanged: (v) => _update(
                field: 'achievements',
                mutate: (d) => d.copyWith(achievements: v),
              ),
              onRestoreOriginal: !_listEq(_aiAdapted.achievements, data.achievements)
                  ? () => _update(
                        field: 'achievements',
                        editType: 'restore_original',
                        mutate: (d) => d.copyWith(achievements: _aiAdapted.achievements),
                      )
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (data.courses.isNotEmpty || !readOnly) ...[
            ResumeListEditor(
              value: data.courses.map((c) => c.title).toList(),
              original: _aiAdapted.courses.map((c) => c.title).toList(),
              label: 'CERTIFICAÇÕES',
              addHint: 'Ex: Modelagem Financeira - Wall Street Prep - 2025',
              onChanged: (v) => _update(
                field: 'certifications',
                mutate: (d) => d.copyWith(
                  courses: v
                      .map((s) => ResumeCourse(
                            title: s,
                            institution: '',
                            period: '',
                          ))
                      .toList(),
                ),
              ),
              onRestoreOriginal: !_coursesEq(_aiAdapted.courses, data.courses)
                  ? () => _update(
                        field: 'certifications',
                        editType: 'restore_original',
                        mutate: (d) => d.copyWith(courses: _aiAdapted.courses),
                      )
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (data.interests.isNotEmpty || !readOnly) ...[
            ResumeListEditor(
              value: data.interests,
              original: _aiAdapted.interests,
              label: 'INTERESSES',
              addHint: 'Novo interesse',
              onChanged: (v) => _update(
                field: 'interests',
                mutate: (d) => d.copyWith(interests: v),
              ),
              onRestoreOriginal: !_listEq(_aiAdapted.interests, data.interests)
                  ? () => _update(
                        field: 'interests',
                        editType: 'restore_original',
                        mutate: (d) => d.copyWith(interests: _aiAdapted.interests),
                      )
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderSection(ResumeData data, bool readOnly) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResumeBlockEditor(
          value: data.fullName,
          original: _aiAdapted.fullName,
          hint: 'Nome completo',
          readOnly: readOnly,
          textStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
            height: 1.1,
          ),
          onChanged: (v) => _update(
            field: 'fullName',
            mutate: (d) => d.copyWith(fullName: v),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _buildContactEditor(
              data.location,
              _aiAdapted.location,
              'Localização',
              readOnly,
              (v) => _update(field: 'location', mutate: (d) => d.copyWith(location: v)),
            ),
            _buildContactEditor(
              data.phone,
              _aiAdapted.phone,
              'Telefone',
              readOnly,
              (v) => _update(field: 'phone', mutate: (d) => d.copyWith(phone: v)),
            ),
            _buildContactEditor(
              data.email,
              _aiAdapted.email,
              'Email',
              readOnly,
              (v) => _update(field: 'email', mutate: (d) => d.copyWith(email: v)),
            ),
            _buildContactEditor(
              data.linkedin,
              _aiAdapted.linkedin,
              'LinkedIn',
              readOnly,
              (v) => _update(field: 'linkedin', mutate: (d) => d.copyWith(linkedin: v)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContactEditor(
    String value,
    String original,
    String hint,
    bool readOnly,
    ValueChanged<String> onChanged,
  ) {
    if (value.isEmpty && readOnly) return const SizedBox.shrink();
    return SizedBox(
      width: 220,
      child: ResumeBlockEditor(
        value: value,
        original: original,
        hint: hint,
        readOnly: readOnly,
        textStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Divider(color: AppColors.border, height: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildExperienceBlock(
    ExperienceItem exp,
    ExperienceItem orig,
    int index,
    bool readOnly,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ResumeBlockEditor(
                  value: exp.role,
                  original: orig.role,
                  hint: 'Cargo',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  onChanged: (v) => _update(
                    field: 'experiences.$index.role',
                    mutate: (d) {
                      final list = List<ExperienceItem>.from(d.experiences);
                      list[index] = ExperienceItem(
                        role: v,
                        company: exp.company,
                        period: exp.period,
                        description: exp.description,
                        location: exp.location,
                      );
                      return d.copyWith(experiences: list);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: ResumeBlockEditor(
                  value: exp.period,
                  original: orig.period,
                  hint: 'Período',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (v) => _update(
                    field: 'experiences.$index.period',
                    mutate: (d) {
                      final list = List<ExperienceItem>.from(d.experiences);
                      list[index] = ExperienceItem(
                        role: exp.role,
                        company: exp.company,
                        period: v,
                        description: exp.description,
                        location: exp.location,
                      );
                      return d.copyWith(experiences: list);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ResumeBlockEditor(
                  value: exp.company,
                  original: orig.company,
                  hint: 'Empresa',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                  onChanged: (v) => _update(
                    field: 'experiences.$index.company',
                    mutate: (d) {
                      final list = List<ExperienceItem>.from(d.experiences);
                      list[index] = ExperienceItem(
                        role: exp.role,
                        company: v,
                        period: exp.period,
                        description: exp.description,
                        location: exp.location,
                      );
                      return d.copyWith(experiences: list);
                    },
                  ),
                ),
              ),
              if (exp.location.isNotEmpty || !readOnly) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: ResumeBlockEditor(
                    value: exp.location,
                    original: orig.location,
                    hint: 'Cidade',
                    readOnly: readOnly,
                    textStyle: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                    onChanged: (v) => _update(
                      field: 'experiences.$index.location',
                      mutate: (d) {
                        final list = List<ExperienceItem>.from(d.experiences);
                        list[index] = ExperienceItem(
                          role: exp.role,
                          company: exp.company,
                          period: exp.period,
                          description: exp.description,
                          location: v,
                        );
                        return d.copyWith(experiences: list);
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ResumeBlockEditor(
            value: exp.description,
            original: orig.description,
            hint: 'Descrição / bullets (uma por linha)',
            multiline: true,
            readOnly: readOnly,
            textStyle: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
            onChanged: (v) => _update(
              field: 'experiences.$index.description',
              mutate: (d) {
                final list = List<ExperienceItem>.from(d.experiences);
                list[index] = ExperienceItem(
                  role: exp.role,
                  company: exp.company,
                  period: exp.period,
                  description: v,
                  location: exp.location,
                );
                return d.copyWith(experiences: list);
              },
            ),
            onRestoreOriginal: orig.description != exp.description
                ? () => _update(
                      field: 'experiences.$index.description',
                      editType: 'restore_original',
                      mutate: (d) {
                        final list = List<ExperienceItem>.from(d.experiences);
                        list[index] = ExperienceItem(
                          role: exp.role,
                          company: exp.company,
                          period: exp.period,
                          description: orig.description,
                          location: exp.location,
                        );
                        return d.copyWith(experiences: list);
                      },
                    )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildEducationBlock(
    EducationItem ed,
    EducationItem orig,
    int index,
    bool readOnly,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ResumeBlockEditor(
                  value: ed.institution,
                  original: orig.institution,
                  hint: 'Instituição',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  onChanged: (v) => _update(
                    field: 'education.$index.institution',
                    mutate: (d) {
                      final list = List<EducationItem>.from(d.education);
                      list[index] = EducationItem(
                        degree: ed.degree,
                        institution: v,
                        period: ed.period,
                        details: ed.details,
                        location: ed.location,
                      );
                      return d.copyWith(education: list);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: ResumeBlockEditor(
                  value: ed.period,
                  original: orig.period,
                  hint: 'Período',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (v) => _update(
                    field: 'education.$index.period',
                    mutate: (d) {
                      final list = List<EducationItem>.from(d.education);
                      list[index] = EducationItem(
                        degree: ed.degree,
                        institution: ed.institution,
                        period: v,
                        details: ed.details,
                        location: ed.location,
                      );
                      return d.copyWith(education: list);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ResumeBlockEditor(
                  value: ed.degree,
                  original: orig.degree,
                  hint: 'Curso/Grau',
                  readOnly: readOnly,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                  onChanged: (v) => _update(
                    field: 'education.$index.degree',
                    mutate: (d) {
                      final list = List<EducationItem>.from(d.education);
                      list[index] = EducationItem(
                        degree: v,
                        institution: ed.institution,
                        period: ed.period,
                        details: ed.details,
                        location: ed.location,
                      );
                      return d.copyWith(education: list);
                    },
                  ),
                ),
              ),
              if (ed.location.isNotEmpty || !readOnly) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: ResumeBlockEditor(
                    value: ed.location,
                    original: orig.location,
                    hint: 'Cidade',
                    readOnly: readOnly,
                    textStyle: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                    onChanged: (v) => _update(
                      field: 'education.$index.location',
                      mutate: (d) {
                        final list = List<EducationItem>.from(d.education);
                        list[index] = EducationItem(
                          degree: ed.degree,
                          institution: ed.institution,
                          period: ed.period,
                          details: ed.details,
                          location: v,
                        );
                        return d.copyWith(education: list);
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (ed.details.isNotEmpty || !readOnly) ...[
            const SizedBox(height: 6),
            ResumeBlockEditor(
              value: ed.details,
              original: orig.details,
              hint: 'Detalhes (opcional)',
              multiline: true,
              readOnly: readOnly,
              textStyle: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
              onChanged: (v) => _update(
                field: 'education.$index.details',
                mutate: (d) {
                  final list = List<EducationItem>.from(d.education);
                  list[index] = EducationItem(
                    degree: ed.degree,
                    institution: ed.institution,
                    period: ed.period,
                    details: v,
                    location: ed.location,
                  );
                  return d.copyWith(education: list);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(MediaQueryData mq) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_hasEdits)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.brandCyan,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Editado',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandCyan,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ElevatedButton(
              onPressed: _isExporting ? null : _approveAndDownload,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandCyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isExporting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _hasEdits ? 'Aprovar e baixar' : 'Baixar PDF',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ViewMode { adapted, original }

/// Dialog animado de confirmação pós-save. Sequência:
///   1. Scale-in do card (300ms easeOutBack — bounce sutil).
///   2. Check verde aparece com elastic-out (450ms) + haptic.
///   3. Textos fade-in.
///   4. CTAs aparecem por último.
/// Auto-close em 4s caso o usuário não interaja.
class _SavedConfirmationDialog extends StatefulWidget {
  final String jobTitle;
  const _SavedConfirmationDialog({required this.jobTitle});

  @override
  State<_SavedConfirmationDialog> createState() =>
      _SavedConfirmationDialogState();
}

class _SavedConfirmationDialogState extends State<_SavedConfirmationDialog>
    with TickerProviderStateMixin {
  late final AnimationController _cardCtrl;
  late final AnimationController _checkCtrl;
  late final AnimationController _textCtrl;
  late final Animation<double> _cardScale;
  late final Animation<double> _checkScale;
  late final Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();
    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _cardScale = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutBack);
    _checkScale = CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut);
    _textOpacity = CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut);

    _runSequence();
  }

  Future<void> _runSequence() async {
    _cardCtrl.forward();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    HapticFeedback.mediumImpact();
    _checkCtrl.forward();
    await Future<void>.delayed(const Duration(milliseconds: 240));
    _textCtrl.forward();
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    _checkCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([_cardCtrl, _checkCtrl, _textCtrl]),
        builder: (context, _) {
          return Transform.scale(
            scale: 0.85 + 0.15 * _cardScale.value,
            child: Opacity(
              opacity: _cardCtrl.value.clamp(0.0, 1.0),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: _checkScale.value,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: AppColors.success, // emerald (mesmo do brand adapted)
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x4010B981),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Opacity(
                      opacity: _textOpacity.value,
                      child: Column(
                        children: [
                          const Text(
                            'CV salvo!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sua versão adaptada para ${widget.jobTitle.length > 38 ? '${widget.jobTitle.substring(0, 35)}…' : widget.jobTitle} ficou em Perfil → Currículos.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Opacity(
                      opacity: _textOpacity.value,
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandCyan,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Entendi',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
