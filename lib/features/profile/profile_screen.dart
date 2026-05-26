import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import 'profile_viewmodel.dart';
import 'application/profile_editor_view_model.dart';
import '../../core/utils/display_name.dart';
import '../auth/user_viewmodel.dart';
import '../home/home_viewmodel.dart';
import '../settings/settings_screen.dart';
import 'resume_detail_screen.dart';
import 'presentation/profile_editor_screen.dart';
import '../tutorial/tutorial_keys.dart';
import '../../data/models/models.dart';
import '../../core/widgets/pii_mask.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// Ordenação da biblioteca de currículos (F8 da reformulação).
enum _ResumeSort {
  newest('Mais recente', Icons.schedule_rounded),
  oldest('Mais antigo', Icons.history_rounded),
  byType('Por tipo', Icons.category_rounded),
  alphabetical('Nome (A-Z)', Icons.sort_by_alpha_rounded);

  final String label;
  final IconData icon;
  const _ResumeSort(this.label, this.icon);
}

/// Metadata visual por origem do CV. Usado em chips de legenda e badges
/// nos cards. Cores escolhidas pra harmonizar com brand cyan/indigo do app
/// e dar diferenciação clara entre os 3 tipos.
class _SourceMeta {
  final String label;
  final Color color;
  final IconData icon;
  const _SourceMeta(this.label, this.color, this.icon);
}

const Map<SavedResumeSource, _SourceMeta> _kSourceMeta = {
  SavedResumeSource.manual: _SourceMeta(
    'Editado',
    Color(0xFF6366F1), // indigo
    Icons.edit_rounded,
  ),
  SavedResumeSource.imported: _SourceMeta(
    'Importado',
    Color(0xFF0EA5E9), // sky blue
    Icons.cloud_upload_rounded,
  ),
  SavedResumeSource.adapted: _SourceMeta(
    'Adaptado (IA)',
    Color(0xFF10B981), // emerald (mesmo verde do brand)
    Icons.auto_awesome_rounded,
  ),
};

class _ProfileScreenState extends State<ProfileScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'profile';

  _ResumeSort _sort = _ResumeSort.newest;

  /// Aplica a ordenação selecionada à lista bruta do view model.
  /// Retorna uma cópia ordenada — não muta o estado do view model.
  List<SavedResume> _sortedResumes(List<SavedResume> input) {
    final list = List<SavedResume>.from(input);
    switch (_sort) {
      case _ResumeSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _ResumeSort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case _ResumeSort.byType:
        // Agrupa por source (adaptados primeiro = mais valiosos), dentro
        // de cada grupo ordena por data desc.
        const order = {
          SavedResumeSource.adapted: 0,
          SavedResumeSource.imported: 1,
          SavedResumeSource.manual: 2,
        };
        list.sort((a, b) {
          final byType = (order[a.source] ?? 99).compareTo(order[b.source] ?? 99);
          if (byType != 0) return byType;
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
      case _ResumeSort.alphabetical:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final userVM = context.watch<UserViewModel>();
    final user = userVM.user;
    final profileEditorVM = context.watch<ProfileEditorViewModel>();
    final homeVM = context.watch<HomeViewModel>();
    final highlightId = homeVM.pendingHighlightResumeId;

    // Display name — prioriza profile_personal (novo onboarding) sobre
    // user_profiles.name (legacy, que pode ser o placeholder "User" para
    // signups via Apple/Google/phone).
    final displayName = resolveDisplayName(profileEditorVM, user?.name);

    // Clear the highlight after this frame so it only plays once per
    // request. _ResumeCard reads the id on construct and animates.
    if (highlightId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<HomeViewModel>().clearProfileHighlight();
      });
    }

    return Consumer<ProfileViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return PiiMask(child: Scaffold(
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
                        _buildUserIdentity(context, displayName),
                        const SizedBox(height: 32),
                        
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Sua Biblioteca',
                                style: TextStyle(fontFamily: 'Outfit', 
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            if (viewModel.savedResumes.isNotEmpty)
                              _buildSortButton(),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (viewModel.savedResumes.isNotEmpty) ...[
                          _buildSourceLegend(viewModel),
                          const SizedBox(height: 16),
                        ],

                        if (viewModel.savedResumes.isEmpty)
                          _buildEmptyState()
                        else
                          _buildResumeList(viewModel, highlightId),
                          
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
      },
    );
  }

  Widget _buildModernHeader(BuildContext context) {
    // Header transparente — sem faixa branca chapada nem border, consistente
    // com as abas Vagas e Salvas.
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 16, right: 16, bottom: 24),
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
                  style: TextStyle(fontFamily: 'Outfit', 
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
          // Botão Editar Perfil — abre o editor estruturado profile-first.
          // Semana 2: spotlight tutorial aponta aqui na primeira abertura pós-update.
          IconButton(
            key: TutorialKeys.editProfileButton,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileEditorScreen()),
              );
            },
            tooltip: 'Editar Perfil',
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00C27A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.edit_outlined, color: Color(0xFF00C27A), size: 20),
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

  Widget _buildUserIdentity(BuildContext context, String displayName) {
    final initial = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : 'U';
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
              initial,
              style: const TextStyle(fontSize: 20, color: Color(0xFF4F46E5), fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
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
            style: TextStyle(fontFamily: 'Outfit', 
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

  Widget _buildResumeList(ProfileViewModel viewModel, String? highlightId) {
    final sorted = _sortedResumes(viewModel.savedResumes);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final resume = sorted[index];
        return _ResumeCard(
          key: ValueKey(resume.id),
          resume: resume,
          viewModel: viewModel,
          highlight: resume.id == highlightId,
          onDelete: () => _showDeleteConfirmation(context, viewModel, resume),
        );
      },
    );
  }

  /// Botão de ordenação. Tap → bottom sheet com as 4 opções de _ResumeSort.
  Widget _buildSortButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _openSortSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_sort.icon, size: 14, color: const Color(0xFF4B5563)),
              const SizedBox(width: 6),
              Text(
                _sort.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.unfold_more_rounded, size: 14, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSortSheet() async {
    final picked = await showModalBottomSheet<_ResumeSort>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ordenar por',
                    style: TextStyle(fontFamily: 'Outfit', 
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
              ),
              for (final opt in _ResumeSort.values)
                ListTile(
                  leading: Icon(opt.icon,
                      color: opt == _sort ? const Color(0xFF6366F1) : const Color(0xFF6B7280)),
                  title: Text(
                    opt.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: opt == _sort ? FontWeight.w800 : FontWeight.w500,
                      color: opt == _sort ? const Color(0xFF111827) : const Color(0xFF374151),
                    ),
                  ),
                  trailing: opt == _sort
                      ? const Icon(Icons.check_rounded, color: Color(0xFF6366F1))
                      : null,
                  onTap: () => Navigator.of(context).pop(opt),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (picked != null && picked != _sort) {
      setState(() => _sort = picked);
    }
  }

  /// Legenda visual dos 3 tipos de currículo. Mostra só os tipos
  /// presentes na biblioteca pra evitar poluir.
  Widget _buildSourceLegend(ProfileViewModel viewModel) {
    final present = viewModel.savedResumes.map((r) => r.source).toSet();
    final entries = SavedResumeSource.values
        .where((s) => present.contains(s))
        .toList();
    if (entries.length < 2) {
      // Só 1 tipo presente — não vale a pena mostrar legenda.
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final s in entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _kSourceMeta[s]!.color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _kSourceMeta[s]!.color.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_kSourceMeta[s]!.icon, size: 11, color: _kSourceMeta[s]!.color),
                const SizedBox(width: 5),
                Text(
                  _kSourceMeta[s]!.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kSourceMeta[s]!.color,
                  ),
                ),
              ],
            ),
          ),
      ],
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
                style: TextStyle(fontFamily: 'Outfit', 
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
                  style: TextStyle(fontFamily: 'Inter', 
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
                        style: TextStyle(fontFamily: 'Inter', 
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
                        style: TextStyle(fontFamily: 'Inter', 
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
  final bool highlight;

  const _ResumeCard({
    super.key,
    required this.resume,
    required this.viewModel,
    required this.onDelete,
    this.highlight = false,
  });

  @override
  State<_ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends State<_ResumeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.85, end: 1.05)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.05, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 55,
      ),
    ]).animate(_controller);
    _glow = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(_controller);

    if (widget.highlight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.value = 1.0; // settled state
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openDetail() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResumeDetailScreen(resume: widget.resume),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = '${widget.resume.createdAt.day.toString().padLeft(2, '0')}/${widget.resume.createdAt.month.toString().padLeft(2, '0')}';
    final sourceMeta = _kSourceMeta[widget.resume.source]!;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: GestureDetector(
            onTap: _openDetail,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                // F8: borda colorida discreta na cor do source — sinal
                // visual ambiente sem competir com o conteúdo do card.
                border: Border.all(color: sourceMeta.color.withOpacity(0.35), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                  if (_glow.value > 0)
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withOpacity(0.45 * _glow.value),
                      blurRadius: 24,
                      spreadRadius: 2,
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
                    
                    // F8: badge da origem (manual/imported/adapted) no
                    // canto superior esquerdo do preview. Sinal direto
                    // pro usuário identificar de relance se o CV foi
                    // adaptado por IA, importado de PDF, ou editado.
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: sourceMeta.color,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: sourceMeta.color.withOpacity(0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(sourceMeta.icon, size: 10, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              sourceMeta.label,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
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
                              _openDetail();
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
                    style: TextStyle(fontFamily: 'Inter', 
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
          ),
        );
      },
    );
  }
}
