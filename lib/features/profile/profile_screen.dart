import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'profile_viewmodel.dart';
import '../auth/user_viewmodel.dart';
import '../settings/settings_screen.dart';
import 'profile_edit_screen.dart';
import 'resume_preview_screen.dart';
import '../../data/models/models.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final userVM = context.watch<UserViewModel>();
    final user = userVM.user;

    return Consumer<ProfileViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          body: Column(
            children: [
              _buildModernHeader(context),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => viewModel.loadSavedResumes(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        _buildUserIdentity(context, user),
                        const SizedBox(height: 32),
                        
                        Text(
                          'Sua Biblioteca',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        if (viewModel.savedResumes.isEmpty)
                          _buildEmptyState()
                        else
                          _buildResumeList(viewModel),
                          
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 16, right: 16, bottom: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Meu Perfil',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gerencie sua biblioteca de currículos',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: Container(
               padding: const EdgeInsets.all(8),
                 decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
              child: const Icon(Icons.settings, color: Color(0xFF9CA3AF), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserIdentity(BuildContext context, UserProfile? user) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
               BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
            ],
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFF3F4F6),
            child: Text(
              user?.name.isNotEmpty == true ? user!.name.substring(0, 1).toUpperCase() : 'U',
              style: const TextStyle(fontSize: 20, color: Color(0xFF4F46E5), fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          user?.name ?? 'Usuário',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.folder_open_rounded, size: 32, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum currículo salvo',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Seus currículos gerados aparecerão aqui para você baixar ou editar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumeList(ProfileViewModel viewModel) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: viewModel.savedResumes.length,
      itemBuilder: (context, index) {
        final resume = viewModel.savedResumes[index];
        return _ResumeCard(
          resume: resume,
          viewModel: viewModel,
          onDelete: () => _showDeleteConfirmation(context, viewModel, resume),
        );
      },
    );
  }

  Future<void> _showDeleteConfirmation(BuildContext context, ProfileViewModel vm, SavedResume resume) async {
    final confirmed = await showDialog<bool>(
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
              // Icon Header (Warning/Delete)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2), // Very light red
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFDC2626), // Sharp red
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              Text(
                'Excluir Currículo?',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              
              // Subtitle
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'Deseja realmente excluir '),
                    TextSpan(
                      text: '"${resume.title}"',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                    ),
                    const TextSpan(text: ' da sua biblioteca? Esta ação não pode ser desfeita.'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Actions
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        'Manter',
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
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        'Excluir',
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

    if (confirmed == true) {
      await vm.deleteResume(resume);
    }
  }
}

class _ResumeCard extends StatefulWidget {
  final SavedResume resume;
  final ProfileViewModel viewModel;
  final VoidCallback onDelete;

  const _ResumeCard({
    required this.resume,
    required this.viewModel,
    required this.onDelete,
  });

  @override
  State<_ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends State<_ResumeCard> {
  bool _isOpening = false;

  void _handlePreview() async {
    setState(() => _isOpening = true);
    final bytes = await widget.viewModel.downloadResumeBytes(widget.resume);
    setState(() => _isOpening = false);

    if (bytes != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResumePreviewScreen(
            title: widget.resume.title,
            pdfBytes: bytes,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = '${widget.resume.createdAt.day.toString().padLeft(2, '0')}/${widget.resume.createdAt.month.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: _handlePreview,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview Area (Capinha)
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: const Color(0xFFF9FAFB),
                child: Stack(
                  children: [
                    // Mock Document Design
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 40, height: 6, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 8),
                          Container(width: double.infinity, height: 4, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 4),
                          Container(width: double.infinity, height: 4, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Expanded(child: Container(height: 4, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(2)))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(width: 60, height: 4, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(2))),
                        ],
                      ),
                    ),
                    
                    // Loading Overlay
                    if (_isOpening)
                      Container(
                        color: Colors.white.withOpacity(0.8),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32)),
                        ),
                      ),
                    
                    // Quick Action Link
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.transparent,
                        child: PopupMenuButton<String>(
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF6B7280)),
                          onSelected: (value) {
                            if (value == 'delete') {
                              widget.onDelete();
                            } else if (value == 'share') {
                              widget.viewModel.downloadAndShareResume(widget.resume);
                            } else if (value == 'open') {
                              _handlePreview();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'open',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF4B5563)),
                                  SizedBox(width: 8),
                                  Text('Visualizar'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'share',
                              child: Row(
                                children: [
                                  Icon(Icons.share_outlined, size: 18, color: Color(0xFF4B5563)),
                                  SizedBox(width: 8),
                                  Text('Compartilhar'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Excluir', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Info Area
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.resume.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 10, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
