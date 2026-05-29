import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../services/analytics_events.dart';
import '../../services/analytics_service.dart';
import 'profile_viewmodel.dart';
import 'profile_tab_prefs.dart';
import 'application/profile_editor_view_model.dart';
import '../home/home_viewmodel.dart';
import '../settings/settings_screen.dart';
import 'resume_detail_screen.dart';
import 'presentation/widgets/personal_info_form.dart';
import 'presentation/widgets/preferences_tab.dart';
import 'presentation/widgets/profile_section_list.dart';
import '../../data/models/models.dart';
import '../../core/widgets/pii_mask.dart';
import '../../core/theme/theme.dart';

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
    AppColors.primary, // azul Stage
    Icons.edit_rounded,
  ),
  SavedResumeSource.imported: _SourceMeta(
    'Importado',
    AppColors.info, // sky blue
    Icons.cloud_upload_rounded,
  ),
  SavedResumeSource.adapted: _SourceMeta(
    'Adaptado (IA)',
    AppColors.success, // emerald — diferencia o badge "feito por IA"
    Icons.auto_awesome_rounded,
  ),
};

class _ProfileScreenState extends State<ProfileScreen>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        ScreenTrackingMixin {
  @override
  String get screenName => 'profile';

  @override
  bool get wantKeepAlive => true;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      // Clamp pra evitar IndexError em users com lastIndex=1 (antiga
      // ordem Info/Currículos). Nova ordem é Info/Preferências/Currículos.
      // Na primeira abertura após o update, quem tinha Currículos (1) cai
      // em Preferências (1) — não-bloqueante, próxima sessão fica certo.
      initialIndex: ProfileTabPrefs.shared.lastIndex.clamp(0, 2),
    );
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    final idx = _tabController.index;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    ProfileTabPrefs.shared.save(uid, idx);
    final tabName = switch (idx) {
      0 => 'info',
      1 => 'preferences',
      _ => 'resumes',
    };
    Analytics.shared.track(evProfileTabChanged, props: {'tab': tabName});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PiiMask(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            _buildModernHeader(context),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _InfoTab(),
                  PreferencesTab(),
                  _ResumesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
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
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gerencie seus currículos e informações',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
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
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
              child: const Icon(Icons.settings, color: AppColors.textDisabled, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppColors.background,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textDisabled,
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        labelStyle: const TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        tabs: const [
          Tab(text: 'Informações'),
          Tab(text: 'Preferências'),
          Tab(text: 'Currículos'),
        ],
      ),
    );
  }
}

// =============================================================================
// _ResumesTab — biblioteca de currículos (conteúdo histórico da aba Perfil).
// =============================================================================

class _ResumesTab extends StatefulWidget {
  const _ResumesTab();

  @override
  State<_ResumesTab> createState() => _ResumesTabState();
}

class _ResumesTabState extends State<_ResumesTab> {
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
    final homeVM = context.watch<HomeViewModel>();
    final highlightId = homeVM.pendingHighlightResumeId;

    if (highlightId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<HomeViewModel>().clearProfileHighlight();
      });
    }

    return Consumer<ProfileViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: () => viewModel.loadSavedResumes(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sua Biblioteca',
                        style: TextStyle(fontFamily: 'Outfit',
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
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
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.folder_open_rounded, size: 32, color: AppColors.textDisabled),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum currículo salvo',
            style: TextStyle(fontFamily: 'Outfit',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Seus currículos gerados aparecerão aqui para você baixar ou editar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
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
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_sort.icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                _sort.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.unfold_more_rounded, size: 14, color: AppColors.textTertiary),
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
                  color: AppColors.border,
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
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              for (final opt in _ResumeSort.values)
                ListTile(
                  leading: Icon(opt.icon,
                      color: opt == _sort ? AppColors.primary : AppColors.textTertiary),
                  title: Text(
                    opt.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: opt == _sort ? FontWeight.w800 : FontWeight.w500,
                      color: opt == _sort ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                  trailing: opt == _sort
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: AppColors.error,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Excluir Currículo?',
                style: TextStyle(fontFamily: 'Outfit',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppColors.textTertiary,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'Deseja realmente excluir '),
                    TextSpan(
                      text: '"${resume.title}"',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const TextSpan(text: ' da sua biblioteca? Esta ação não pode ser desfeita.'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.base,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.brLg,
                        ),
                      ),
                      child: Text(
                        'Manter',
                        style: AppTextStyles.labelLg.copyWith(
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.base,
                        ),
                        elevation: 0,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.brLg,
                        ),
                      ),
                      child: Text(
                        'Excluir',
                        style: AppTextStyles.labelLg.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.bold,
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

// =============================================================================
// _InfoTab — editor estruturado do perfil (antigo ProfileEditorScreen).
// =============================================================================

class _InfoTab extends StatefulWidget {
  const _InfoTab();

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  bool _personalExpanded = false;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileEditorViewModel>();
    return vm.isLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => vm.load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                _header(vm),
                const SizedBox(height: 16),
                _personalCard(vm),
                const SizedBox(height: 12),
                const ProfileSectionList(
                  showLowConfidenceBadges: false,
                ),
              ],
            ),
          );
  }

  Widget _header(ProfileEditorViewModel vm) {
    final p = vm.personal;
    final name = p?.fullName ?? '';
    final headline = p?.headline ?? '';
    final location = p?.formattedLocation ?? '';
    final score = vm.completenessScore;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Seu nome' : name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    if (headline.isNotEmpty || location.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [headline, location].where((s) => s.isNotEmpty).join(' • '),
                          style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              // Indicador de salvamento — substitui o que ficava no AppBar
              // do antigo ProfileEditorScreen. AnimatedSwitcher suaviza a
              // transição idle → saving → saved → idle (some sozinho em 2s
              // via lógica no view model).
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _saveIndicator(vm.saveStatus),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    backgroundColor: AppColors.border,
                    color: AppColors.success,
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$score% completo',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _saveIndicator(SaveStatus status) {
    String label;
    Color color;
    IconData icon;
    switch (status) {
      case SaveStatus.saving:
        label = 'Salvando';
        color = AppColors.textTertiary;
        icon = Icons.sync;
        break;
      case SaveStatus.saved:
        label = 'Salvo';
        color = AppColors.success;
        icon = Icons.check_circle_outline;
        break;
      case SaveStatus.error:
        label = 'Erro';
        color = AppColors.error;
        icon = Icons.error_outline;
        break;
      case SaveStatus.idle:
        return const SizedBox.shrink(key: ValueKey('idle'));
    }
    return Padding(
      key: ValueKey(status),
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _personalCard(ProfileEditorViewModel vm) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _personalExpanded = !_personalExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: AppColors.textTertiary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Informações pessoais',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    _personalExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_personalExpanded && vm.personal != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: PersonalInfoForm(
                initial: vm.personal,
                onChanged: (draft) => vm.updatePersonalDraft(draft),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// _ResumeCard — card individual de um currículo na biblioteca.
// =============================================================================

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
      _controller.value = 1.0;
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
                border: Border.all(color: sourceMeta.color.withOpacity(0.35), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                  if (_glow.value > 0)
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.45 * _glow.value),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                ],
              ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: AppColors.surfaceVariant,
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 40, height: 6, decoration: BoxDecoration(color: AppColors.borderStrong, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 8),
                          Container(width: double.infinity, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 4),
                          Container(width: double.infinity, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(width: 12, height: 12, decoration: BoxDecoration(color: AppColors.border, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Expanded(child: Container(height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(width: 60, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
                        ],
                      ),
                    ),
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
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.transparent,
                        child: PopupMenuButton<String>(
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert_rounded, color: AppColors.textTertiary),
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
                                  Icon(Icons.visibility_outlined, size: 18, color: AppColors.textSecondary),
                                  SizedBox(width: 8),
                                  Text('Visualizar'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'share',
                              child: Row(
                                children: [
                                  Icon(Icons.share_outlined, size: 18, color: AppColors.textSecondary),
                                  SizedBox(width: 8),
                                  Text('Compartilhar'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                                  SizedBox(width: 8),
                                  Text('Excluir', style: TextStyle(color: AppColors.error)),
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
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 10, color: AppColors.textDisabled),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
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
