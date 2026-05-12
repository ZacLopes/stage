import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/models.dart';
import '../../services/analytics_service.dart';
import '../../services/cv_import_service.dart';
import '../auth/user_viewmodel.dart';
import 'resume_viewmodel.dart';
import 'pdf_service.dart';
import 'resume_edit_screen.dart';
import 'resume_templates.dart';
import 'widgets/ai_consent_modal.dart';
import 'widgets/import_cv_button.dart';
import 'widgets/resume_template_selector.dart';
import 'dart:async';

class ResumeTab extends StatefulWidget {
  final Function(int)? onTabChange;

  const ResumeTab({super.key, this.onTabChange});

  @override
  State<ResumeTab> createState() => _ResumeTabState();
}

class _ResumeTabState extends State<ResumeTab> {
  bool _isGeneratingPdf = false;
  // Default ATS-safe. Variável local mantida pra compat, mas o source-of-truth
  // é `ResumeViewModel.selectedTemplateId`.
  String _selectedTemplate = 'harvard_ats';

  Future<void> _exportToPdf(UserProfile? user, ResumeData resume) async {
    setState(() => _isGeneratingPdf = true);
    try {
      // Resolve Template ID
      final vm = context.read<ResumeViewModel>();
      String finalTemplateId = vm.selectedTemplateId;

      print('DEBUG: Calling PdfService with templateId: $finalTemplateId');
      await PdfService.generateResume(user, resume, finalTemplateId);
      Analytics.shared.cvExported(templateId: finalTemplateId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  Future<void> _showRewriteConfirmation(BuildContext context, ResumeViewModel viewModel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reescrever Currículo?'),
        content: const Text(
          'Isso irá gerar um novo currículo do zero, substituindo o atual. '
          'Certifique-se de que suas respostas nas trilhas estão atualizadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reescrever', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (await _checkAndShowAIConsent(context, viewModel)) {
        viewModel.rewriteResumeWithAI();
      }
    }
  }

  Future<bool> _checkAndShowAIConsent(BuildContext context, ResumeViewModel viewModel) async {
    final userVM = context.read<UserViewModel>();
    final user = userVM.user;
    
    if (user != null && user.aiConsent) {
      return true;
    }

    final completer = Completer<bool>();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, anim1, anim2) => AIConsentModal(
        onAccept: () async {
          await userVM.updateAIConsent(true);
          if (context.mounted) Navigator.pop(context);
          completer.complete(true);
        },
        onCancel: () {
          Navigator.pop(context);
          completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  bool _isModalShowing = false;
  late ResumeViewModel _resumeVM;

  void _checkAIConsentAutomatically() async {
    if (!mounted) return;
    final vm = context.read<ResumeViewModel>();
    final userVM = context.read<UserViewModel>();
    
    // Auto-trigger only if: Course Completed AND Resume is empty/placeholder AND no consent yet
    if (vm.isCourseCompleted && 
        vm.isResumeEmpty && 
        userVM.user != null && 
        !userVM.user!.aiConsent && 
        !_isModalShowing) {
      
      _isModalShowing = true;
      final accepted = await _checkAndShowAIConsent(context, vm);
      _isModalShowing = false;
      
      if (accepted && mounted) {
        // Trigger actual generation after consent
        context.read<ResumeViewModel>().loadResumeData();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _resumeVM = context.read<ResumeViewModel>();
    
    // Check AI consent when tab opens
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _checkAIConsentAutomatically();
    });

    // Also listen for changes (e.g. from completion in other tabs)
    _resumeVM.addListener(_checkAIConsentAutomatically);
  }

  @override
  void dispose() {
    _resumeVM.removeListener(_checkAIConsentAutomatically);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<UserViewModel, ResumeViewModel>(
      builder: (context, userVM, resumeVM, child) {
        final user = userVM.user;
        final resume = resumeVM.resumeData;

        return Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          body: Stack(
            children: [
              Column(
                children: [
                   _buildModernHeader(context),
                   
                   Expanded(
                     child: RefreshIndicator(
                       onRefresh: () => resumeVM.loadResumeData(),
                       child: SingleChildScrollView(
                         physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                         padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             const SizedBox(height: 24),
                             
                             if (!resumeVM.isCourseCompleted && !resumeVM.isLoading) ...[
                               _buildLockedState(context, resumeVM),
                             ] else ...[

                             const SizedBox(height: 8),
                             const SizedBox(height: 32),
                             
                             Row(
                               children: [
                                 const Icon(Icons.remove_red_eye_outlined, color: Colors.grey, size: 20),
                                 const SizedBox(width: 8),
                                 Text(
                                   'PRÉ-VISUALIZAÇÃO',
                                   style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                     color: Colors.grey,
                                     fontWeight: FontWeight.bold,
                                     letterSpacing: 1.2,
                                   ),
                                 ),
                               ],
                             ),
                             const SizedBox(height: 12),
                             
                             // Warnings Section
                             if (resumeVM.getResumeWarnings().isNotEmpty) ...[
                               Container(
                                 padding: const EdgeInsets.all(16),
                                 decoration: BoxDecoration(
                                   color: Colors.amber[50],
                                   borderRadius: BorderRadius.circular(16),
                                   border: Border.all(color: Colors.amber[200]!),
                                 ),
                                 child: Column(
                                   crossAxisAlignment: CrossAxisAlignment.start,
                                   children: [
                                     Row(
                                       children: [
                                         Icon(Icons.warning_amber_rounded, color: Colors.amber[800], size: 20),
                                         const SizedBox(width: 8),
                                         Text(
                                           'Sugestões de Melhoria',
                                           style: TextStyle(
                                             fontWeight: FontWeight.bold,
                                             color: Colors.amber[900],
                                           ),
                                         ),
                                       ],
                                     ),
                                     const SizedBox(height: 12),
                                     ...resumeVM.getResumeWarnings().map((w) => Padding(
                                       padding: const EdgeInsets.only(bottom: 4),
                                       child: Row(
                                         crossAxisAlignment: CrossAxisAlignment.start,
                                         children: [
                                           Text('• ', style: TextStyle(color: Colors.amber[900])),
                                           Expanded(
                                             child: Text(
                                               w,
                                               style: TextStyle(fontSize: 13, color: Colors.amber[900]),
                                             ),
                                           ),
                                         ],
                                       ),
                                     )),
                                   ],
                                 ),
                               ),
                               const SizedBox(height: 24),
                             ],
                             
                              // Document Preview
                              Container(
                                width: double.infinity,
                                height: 550, // Fixed height for interactive viewer
                                decoration: BoxDecoration(
                                  color: Colors.grey[200], // Neutral background
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: resumeVM.isLoading 
                                    ? const Center(child: CircularProgressIndicator())
                                    : ClipRect(
                                        child: InteractiveViewer(
                                          minScale: 0.5,
                                          maxScale: 3.0,
                                          boundaryMargin: const EdgeInsets.all(20),
                                          child: Center(
                                            child: FittedBox(
                                              fit: BoxFit.contain,
                                              child: Container(
                                                width: 794,
                                                height: 1123, // A4 Height
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.15),
                                                      blurRadius: 20,
                                                      offset: const Offset(0, 10),
                                                    ),
                                                  ],
                                                ),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(32.0),
                                                  child: AnimatedSwitcher(
                                                    duration: const Duration(milliseconds: 400),
                                                    switchInCurve: Curves.easeOut,
                                                    switchOutCurve: Curves.easeIn,
                                                    child: Builder(
                                                      builder: (context) {
                                                        // Os 4 templates ATS exportam HTML estruturalmente similar
                                                        // (1 coluna, serif/sans simples, headers padronizados).
                                                        // O preview usa o Harvard ATS como proxy visual — basta
                                                        // pro user ver se os campos estão preenchidos. As
                                                        // diferenças (fonte, spacing, alinhamento) só aparecem
                                                        // no PDF exportado.
                                                        return HarvardAtsBrasilTemplate(user: user, resume: resume);
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                             ] // End if/else
                           ],
                         ),
                       ),
                     ),
                   ),
                ],
              ),
              
              // Single-page warning banner (Harvard MCS recommendation)
              if (resumeVM.estimatePageOverflow() > 0)
                Positioned(
                  top: 100,
                  left: 16,
                  right: 16,
                  child: _SinglePageWarningBanner(vm: resumeVM),
                ),

              // Bottom Floating Action Bar
              Positioned(
                bottom: 24,
                left: 20,
                right: 20,
                child: _buildBottomActionBar(context, user, resume, resumeVM),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Estado "Currículo Bloqueado" — usuário ainda não completou a jornada.
  /// Apresenta 2 caminhos lado a lado, com hierarquia visual clara:
  ///   1. (Recomendado) Construir pela trilha — gradient indigo, sugere ação principal.
  ///   2. Importar CV existente — outlined, alternativa rápida.
  /// Sem cadeado solto/genérico, sem texto "bloqueado" — foco em ação.
  Widget _buildLockedState(BuildContext context, ResumeViewModel vm) {
    const indigo = Color(0xFF4F46E5);
    const purple = Color(0xFF7C3AED);

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero compacto ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [indigo, purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: indigo.withOpacity(0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 13),
                      SizedBox(width: 5),
                      Text(
                        'COMECE SEU CURRÍCULO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Dois jeitos de\nter seu CV pronto',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: -0.5,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Escolha o caminho que faz mais sentido pra você agora.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Caminho 1: Construir pela trilha ────────────────────────
          _buildPathCard(
            badge: 'RECOMENDADO',
            badgeColor: const Color(0xFF10B981),
            icon: Icons.route_rounded,
            iconBg: indigo,
            title: 'Construir pela trilha',
            description:
                'Responda perguntas no estilo Duolingo e a IA monta seu CV pronto pra usar — formatado, com bullets Harvard.',
            highlights: const [
              'Sem precisar saber escrever bullets',
              'Templates ATS-friendly desbloqueados',
              'Adaptação por vaga via IA',
            ],
            ctaLabel: 'Continuar trilha',
            ctaIcon: Icons.arrow_forward_rounded,
            onCtaTap: () => widget.onTabChange?.call(1),
            ctaVariant: _CtaVariant.gradient,
          ),

          const SizedBox(height: 14),

          // ── Caminho 2: Importar CV existente ────────────────────────
          _buildPathCard(
            badge: 'MAIS RÁPIDO',
            badgeColor: const Color(0xFFF59E0B),
            icon: Icons.upload_file_rounded,
            iconBg: const Color(0xFF0EA5E9),
            title: 'Importar CV em PDF',
            description:
                'Já tem um currículo? Suba o PDF e desbloqueie agora mesmo a adaptação por vaga e o match score com IA.',
            highlights: const [
              'Pronto em 5 segundos',
              'IA extrai automaticamente seus dados',
              'Funciona com qualquer template de CV',
            ],
            ctaLabel: 'Importar PDF',
            ctaIcon: Icons.upload_file_rounded,
            onCtaTap: null, // o widget de import lida internamente
            customCta: ImportCvButton(
              onImported: () => vm.loadResumeData(),
            ),
            ctaVariant: _CtaVariant.custom,
          ),

          const SizedBox(height: 12),

          // ── Nota final ──────────────────────────────────────────────
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Seus dados ficam só com você — não compartilhamos com ninguém.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
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

  /// Card de "caminho" com badge, ícone, título, lista de benefícios e CTA.
  Widget _buildPathCard({
    required String badge,
    required Color badgeColor,
    required IconData icon,
    required Color iconBg,
    required String title,
    required String description,
    required List<String> highlights,
    required String ctaLabel,
    required IconData ctaIcon,
    required VoidCallback? onCtaTap,
    required _CtaVariant ctaVariant,
    Widget? customCta,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconBg, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: badgeColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          // Highlights
          ...highlights.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 15, color: badgeColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        h,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF334155),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 14),
          // CTA
          if (ctaVariant == _CtaVariant.gradient)
            _buildCtaGradient(label: ctaLabel, icon: ctaIcon, onTap: onCtaTap)
          else if (ctaVariant == _CtaVariant.custom && customCta != null)
            customCta,
        ],
      ),
    );
  }

  Widget _buildCtaGradient({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seu Currículo',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                    fontFamily: 'Outfit',
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gerado com IA baseado na sua jornada',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // AI Actions Menu
          Consumer<ResumeViewModel>(
            builder: (context, vm, _) {
               if (vm.isGeneratingResume) {
                 return const SizedBox(
                   width: 24, 
                   height: 24, 
                   child: CircularProgressIndicator(strokeWidth: 2)
                 );
               }
               
               if (!vm.isCourseCompleted) {
                 return const SizedBox.shrink();
               }

               return Row(
                 children: [
                   // Template Selection Button
                   GestureDetector(
                     onTap: () {
                       showModalBottomSheet(
                         context: context,
                         isScrollControlled: true,
                         backgroundColor: Colors.transparent,
                         builder: (context) => const ResumeTemplateSelector(),
                       );
                     },
                     child: Container(
                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                       decoration: BoxDecoration(
                         color: const Color(0xFFF3F4F6),
                         borderRadius: BorderRadius.circular(12),
                       ),
                       child: Row(
                         children: [
                           const Icon(Icons.style_outlined, color: Color(0xFF4F46E5), size: 20),
                           const SizedBox(width: 6),
                           Text(
                             'Modelo',
                             style: GoogleFonts.inter(
                               fontSize: 13,
                               fontWeight: FontWeight.bold,
                               color: const Color(0xFF4F46E5),
                             ),
                           ),
                         ],
                       ),
                     ),
                   ),
                   const SizedBox(width: 12),
                   PopupMenuButton<String>(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.more_vert_rounded, color: Color(0xFF4F46E5)),
                      ),
                      tooltip: 'Mais ações',
                      onSelected: (value) async {
                        if (value == 'update') {
                          if (await _checkAndShowAIConsent(context, vm)) {
                            vm.updateResumeWithAI();
                          }
                        } else if (value == 'rewrite') {
                          _showRewriteConfirmation(context, vm);
                        } else if (value == 'import') {
                          final result = await CvImportService.pickAndImport(context);
                          if (!context.mounted) return;
                          if (result.success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✓ Currículo importado'),
                                backgroundColor: Color(0xFF10B981),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            vm.loadResumeData();
                          } else if (result.errorMessage != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result.errorMessage!),
                                backgroundColor: Colors.red.shade600,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'import',
                          child: Row(children: [
                            Icon(Icons.upload_file_rounded, color: Color(0xFF4F46E5), size: 20),
                            SizedBox(width: 8),
                            Text('Importar CV em PDF'),
                          ]),
                        ),
                        const PopupMenuItem(
                          value: 'rewrite',
                          child: Row(children: [
                            Icon(Icons.autorenew, color: Colors.orange, size: 20),
                            SizedBox(width: 8),
                            Text('Reescrever tudo (IA)'),
                          ]),
                        ),
                      ],
                   ),
                 ],
               );
            }
          ),
        ],
      ),
    );
  }



  Widget _buildBottomActionBar(BuildContext context, UserProfile? user, ResumeData? resume, ResumeViewModel vm) {
    final isLocked = !vm.isCourseCompleted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: isLocked ? Colors.grey[900] : const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: isLocked ? null : () {
               if (vm.resumeContent != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResumeEditScreen(
                        initialContent: vm.resumeContent!,
                        onSave: (newContent) => vm.saveManualEdit(newContent),
                      ),
                    ),
                  );
               }
            },
            icon: Icon(Icons.edit, color: isLocked ? Colors.grey : Colors.white70),
            tooltip: 'Editar Texto',
          ),
          // PT / EN language toggle
          _LanguagePill(vm: vm, locked: isLocked),
          const SizedBox(width: 4),
          
          Expanded(
            child: Row(
              children: [
                // Save to Library Button
                Expanded(
                  child: _ScaleButton(
                    onTap: (isLocked || vm.isSaving || resume == null) ? null : () => _showSaveToLibraryDialog(context, user, vm),
                    child: ElevatedButton.icon(
                      onPressed: (isLocked || vm.isSaving || resume == null) ? null : () => _showSaveToLibraryDialog(context, user, vm),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.1),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white.withOpacity(0.05),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0, 
                      ),
                      icon: vm.isSaving 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: Text(
                        vm.isSaving ? 'Salvando...' : 'Salvar',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Export PDF Button
                Expanded(
                  child: _ScaleButton(
                    onTap: (isLocked || _isGeneratingPdf || resume == null) ? null : () => _exportToPdf(user, resume!),
                    child: ElevatedButton.icon(
                      onPressed: (isLocked || _isGeneratingPdf || resume == null) ? null : () => _exportToPdf(user, resume!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white.withOpacity(0.05),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0, 
                      ),
                      icon: _isGeneratingPdf 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.download, size: 18),
                      label: Text(
                        _isGeneratingPdf ? '...' : 'PDF',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _showSaveToLibraryDialog(BuildContext context, UserProfile? user, ResumeViewModel vm) async {
    final controller = TextEditingController(text: '');
    
    final title = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bookmark_add_rounded,
                  color: Color(0xFF2E7D32),
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              Text(
                'Salvar na Biblioteca',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                'Dê um nome para esta versão do seu currículo para encontrá-la depois.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              
              // TextField
              TextField(
                controller: controller,
                autofocus: true,
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey[200]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey[200]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Actions
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        'Salvar',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (title != null && title.isNotEmpty) {
      try {
        await vm.saveToLibrary(user, title);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Salvo na sua Biblioteca com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao salvar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

}

class _ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Duration duration;
  final double scale;

  const _ScaleButton({
    super.key,
    required this.child,
    this.onTap,
    this.duration = const Duration(milliseconds: 100),
    this.scale = 0.95,
  });

  @override
  State<_ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<_ScaleButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.onTap != null ? (_) => _controller.forward() : null,
      onTapUp: widget.onTap != null ? (_) => _controller.reverse() : null,
      onTapCancel: widget.onTap != null ? () => _controller.reverse() : null,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}

/// Horizontal segmented switch (PT | EN) with a sliding background that
/// indicates which language is active. Tapping the inactive side asks for
/// confirmation (since it regenerates the resume) and then switches.
class _LanguagePill extends StatelessWidget {
  final ResumeViewModel vm;
  final bool locked;
  const _LanguagePill({required this.vm, required this.locked});

  static const _segWidth = 38.0;
  static const _segHeight = 28.0;

  Future<void> _switchTo(BuildContext context, String next) async {
    if (vm.language == next || locked) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trocar idioma do currículo?'),
        content: Text(
          next == 'en'
              ? 'Seu currículo será regerado em inglês com a IA. A versão em português fica salva e você pode voltar a qualquer momento.'
              : 'Seu currículo será regerado em português com a IA. A versão em inglês fica salva e você pode voltar a qualquer momento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
            ),
            child: Text(next == 'en' ? 'Gerar em inglês' : 'Gerar em português'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await vm.setLanguage(next);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = vm.isEnglish;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        height: _segHeight,
        decoration: BoxDecoration(
          color: locked
              ? Colors.grey.withOpacity(0.2)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(_segHeight / 2),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Stack(
          children: [
            // Sliding active background
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: isEn ? _segWidth : 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: _segWidth,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5),
                  borderRadius: BorderRadius.circular(_segHeight / 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segment(context, label: 'PT', selected: !isEn, target: 'pt'),
                _segment(context, label: 'EN', selected: isEn, target: 'en'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required bool selected,
    required String target,
  }) {
    return GestureDetector(
      onTap: locked ? null : () => _switchTo(context, target),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _segWidth,
        height: _segHeight,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white.withOpacity(0.6),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Yellow banner shown above the CV preview when the rendered output is
/// likely to exceed one A4 page. Tapping "Ver sugestões" opens a sheet with
/// concrete trim suggestions ranked by impact.
class _SinglePageWarningBanner extends StatelessWidget {
  final ResumeViewModel vm;
  const _SinglePageWarningBanner({required this.vm});

  @override
  Widget build(BuildContext context) {
    final overflow = vm.estimatePageOverflow();
    final critical = overflow >= 2;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: critical
              ? const Color(0xFFFEE2E2)
              : const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: critical
                ? const Color(0xFFFCA5A5)
                : const Color(0xFFFCD34D),
          ),
        ),
        child: Row(
          children: [
            Icon(
              critical ? Icons.warning : Icons.info_outline,
              color: critical
                  ? const Color(0xFF991B1B)
                  : const Color(0xFF92400E),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    critical
                        ? 'CV passou de 2 páginas'
                        : 'CV pode passar de 1 página',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: critical
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF92400E),
                    ),
                  ),
                  Text(
                    'Harvard MCS recomenda 1 página para estudantes.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: critical
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _showSuggestions(context),
              style: TextButton.styleFrom(
                foregroundColor: critical
                    ? const Color(0xFF991B1B)
                    : const Color(0xFF92400E),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              child: const Text(
                'Ver sugestões',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuggestions(BuildContext context) {
    final tips = vm.suggestionsToTrim();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.content_cut, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 10),
                  Text(
                    'Sugestões para encurtar',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Caracteres estimados: ${vm.estimateRenderedCharCount()}',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),
              ...tips.map((tip) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.fiber_manual_record,
                            size: 8, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tip,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF374151),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Entendi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Variantes do CTA usadas em [_buildPathCard].
enum _CtaVariant { gradient, custom }
