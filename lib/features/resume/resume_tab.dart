import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/models.dart';
import '../auth/user_viewmodel.dart';
import 'resume_viewmodel.dart';
import 'pdf_service.dart';
import 'docx_service.dart';
import 'web_service.dart';
import 'resume_edit_screen.dart';
import 'resume_templates.dart';
import 'widgets/ai_consent_modal.dart';
import 'dart:async';

class ResumeTab extends StatefulWidget {
  final Function(int)? onTabChange;

  const ResumeTab({super.key, this.onTabChange});

  @override
  State<ResumeTab> createState() => _ResumeTabState();
}

class _ResumeTabState extends State<ResumeTab> {
  bool _isGeneratingPdf = false;
  String _selectedTemplate = 'quickcv';

  Future<void> _exportToPdf(UserProfile? user, ResumeData resume) async {
    setState(() => _isGeneratingPdf = true);
    try {
      // Resolve Template ID
      final vm = context.read<ResumeViewModel>();
      String finalTemplateId = 'quickcv';


      // Standard/QuickCV is the default behavior.
      // Removed area-based template logic.

      print('DEBUG: Calling PdfService with templateId: $finalTemplateId');
      await PdfService.generateResume(user, resume, finalTemplateId);
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

  @override
  void initState() {
    super.initState();
    // Refresh data when tab opens to ensure latest answers (Area detection) are picked up
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<ResumeViewModel>();
      final userVM = context.read<UserViewModel>();
      
      // If course is completed but no resume content exists, we'll need AI.
      // Check for consent BEFORE triggering loadResumeData which might trigger AI.
      if (vm.isCourseCompleted && vm.resumeContent == null) {
        if (await _checkAndShowAIConsent(context, vm)) {
          vm.loadResumeData();
        }
      } else {
        vm.loadResumeData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<UserViewModel, ResumeViewModel>(
      builder: (context, userVM, resumeVM, child) {
        final user = userVM.user;
        final resume = resumeVM.resumeData;
        final currentLevel = userVM.currentLevelInfo.level;
        
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
                               Container(
                                 height: MediaQuery.of(context).size.height * 0.5,
                                 alignment: Alignment.center,
                                 child: Column(
                                   mainAxisAlignment: MainAxisAlignment.center,
                                   children: [
                                     Container(
                                       padding: const EdgeInsets.all(24),
                                       decoration: BoxDecoration(
                                         color: Colors.grey[100],
                                         shape: BoxShape.circle,
                                       ),
                                       child: Icon(Icons.lock_rounded, size: 64, color: Colors.grey[400]),
                                     ),
                                     const SizedBox(height: 24),
                                     Text(
                                       'Currículo Bloqueado',
                                       style: TextStyle(
                                         fontSize: 24,
                                         fontWeight: FontWeight.w800,
                                         color: Color(0xFF1F2937),
                                         fontFamily: 'Outfit',
                                         letterSpacing: -0.5,
                                       ),
                                     ),
                                     const SizedBox(height: 12),
                                     Padding(
                                       padding: const EdgeInsets.symmetric(horizontal: 40),
                                       child: Text(
                                         'Complete todas as etapas da sua jornada para desbloquear o gerador de currículo com IA.',
                                         textAlign: TextAlign.center,
                                         style: TextStyle(
                                           fontSize: 16,
                                           color: Colors.grey[600],
                                           height: 1.5,
                                         ),
                                       ),
                                     ),
                                     const SizedBox(height: 32),
                                     SizedBox(
                                       width: 200,
                                       child: ElevatedButton.icon(
                                         onPressed: () {
                                            if (widget.onTabChange != null) {
                                              widget.onTabChange!(0);
                                            }
                                         },
                                         style: ElevatedButton.styleFrom(
                                           backgroundColor: const Color(0xFF4F46E5),
                                           foregroundColor: Colors.white,
                                           padding: const EdgeInsets.symmetric(vertical: 16),
                                           shape: RoundedRectangleBorder(
                                             borderRadius: BorderRadius.circular(16),
                                           ),
                                           elevation: 4,
                                           shadowColor: const Color(0xFF4F46E5).withOpacity(0.4),
                                         ),
                                         icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                                         label: const Text(
                                           'Voltar para a Jornada',
                                           style: TextStyle(fontWeight: FontWeight.bold),
                                         ),
                                       ),
                                     ),
                                   ],
                                 ),
                               )
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
                                                        // Always return QuickCV Template
                                                        return QuickCvResumeTemplate(user: user, resume: resume);
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
          Column(
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
              ),
            ],
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

               return PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFF4F46E5)),
                  ),
                  tooltip: 'IA: Atualizar ou Reescrever',
                  onSelected: (value) async {
                    if (value == 'update') {
                      if (await _checkAndShowAIConsent(context, vm)) {
                        vm.updateResumeWithAI();
                      }
                    } else if (value == 'rewrite') {
                      _showRewriteConfirmation(context, vm);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'rewrite',
                      child: Row(children: [
                        Icon(Icons.autorenew, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Text('Reescrever tudo (Zero)'),
                      ]),
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
