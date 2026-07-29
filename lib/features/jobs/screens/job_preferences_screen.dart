import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/analytics/screen_tracking.dart';
import '../../../core/constants/job_areas.dart';
import '../jobs_viewmodel.dart';
import '../../auth/auth_session.dart';
import '../models/user_preferences.dart';
import '../../../core/theme/theme.dart';

/// Tela de preferências de vagas. Bottom sheet em altura ~92% da tela.
///
/// Design alinhado com `jobs_swipe_screen`:
/// gradient indigo→purple no header, cards com sombra leve, chips
/// inline (sem pickers em modal extra). Tudo num scroll só pro user
/// ver de relance o que está selecionado.
class JobPreferencesScreen extends StatefulWidget {
  const JobPreferencesScreen({super.key});

  @override
  State<JobPreferencesScreen> createState() => _JobPreferencesScreenState();
}

class _JobPreferencesScreenState extends State<JobPreferencesScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'jobs_preferences';

  // ── Local edit state (commit on save) ──────────────────────────────
  Set<String> _selectedAreas = {};
  Set<String> _selectedLocations = {};
  Set<String> _selectedWorkModels = {};
  Set<String> _selectedJobTypes = {};
  int? _minMatchScore; // 0-100, null = sem filtro
  bool _loaded = false;
  bool _saving = false;

  // ── Cores unificadas com jobs_swipe_screen ─────────────────────────
  static const _indigo = AppColors.primary;
  static const _purple = AppColors.primary;
  static const _gradient = LinearGradient(
    colors: [_indigo, _purple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _textPrimary = AppColors.textPrimary;
  static const _textSecondary = AppColors.textSecondary;
  static const _textMuted = AppColors.textTertiary;
  static const _border = AppColors.border;

  // ── Catálogo de opções ─────────────────────────────────────────────
  // Lista importada de `lib/core/constants/job_areas.dart` (single source
  // of truth). Mudar lá reflete aqui, no DesiredTitlesScreen do onboarding
  // e no PreferencesTab. FilterHelpers cuida de sinônimos (RH ↔ Recursos
  // Humanos, Design ↔ Produto) — não duplique lógica aqui.

  // Cobertura ampliada das principais capitais + cidades-polo. O matching
  // em FilterHelpers expande automaticamente: escolher "São Paulo" pega
  // todas as cidades do estado de SP (Campinas, Santos, etc.).
  static const _locations = <String>[
    'São Paulo', 'Rio de Janeiro', 'Belo Horizonte', 'Curitiba',
    'Porto Alegre', 'Brasília', 'Campinas', 'Recife',
    'Salvador', 'Fortaleza', 'Florianópolis', 'Goiânia',
    'Manaus', 'Vitória',
  ];

  static const _workModels = <_PairItem>[
    _PairItem('remoto', 'Remoto', icon: Icons.home_work_rounded),
    _PairItem('hibrido', 'Híbrido', icon: Icons.sync_alt_rounded),
    _PairItem('presencial', 'Presencial', icon: Icons.business_rounded),
  ];

  static const _jobTypes = <_PairItem>[
    _PairItem('estagio', 'Estágio', icon: Icons.school_rounded),
    _PairItem('trainee', 'Trainee', icon: Icons.rocket_launch_rounded),
    _PairItem('clt_junior', 'CLT Júnior', icon: Icons.badge_rounded),
    _PairItem('temporario', 'Temporário', icon: Icons.schedule_rounded),
  ];

  static const _maxAreas = 5;
  static const _maxLocations = 5;

  // ── Lifecycle ──────────────────────────────────────────────────────
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _hydrateFromViewModel();
    }
  }

  void _hydrateFromViewModel() {
    final vm = context.read<JobsViewModel>();
    final prefs = vm.preferences;
    if (prefs != null) {
      setState(() {
        _selectedAreas = Set<String>.from(prefs.areas);
        _selectedLocations = Set<String>.from(prefs.locations);
        _selectedWorkModels = Set<String>.from(prefs.workModels);
        _selectedJobTypes = Set<String>.from(prefs.jobTypes);
        _minMatchScore = prefs.minMatchScore;
      });
    }
  }

  // ── Counters ───────────────────────────────────────────────────────
  int get _activeFiltersCount {
    var n = 0;
    if (_selectedAreas.isNotEmpty) n++;
    if (_selectedLocations.isNotEmpty) n++;
    if (_selectedWorkModels.isNotEmpty) n++;
    if (_selectedJobTypes.isNotEmpty) n++;
    if (_minMatchScore != null && _minMatchScore! > 0) n++;
    return n;
  }

  bool get _hasUnsavedChanges {
    final vm = context.read<JobsViewModel>();
    final prefs = vm.preferences;
    if (prefs == null) {
      return _selectedAreas.isNotEmpty ||
          _selectedLocations.isNotEmpty ||
          _selectedWorkModels.isNotEmpty ||
          _selectedJobTypes.isNotEmpty ||
          (_minMatchScore != null && _minMatchScore! > 0);
    }
    return !_setEq(_selectedAreas, prefs.areas.toSet()) ||
        !_setEq(_selectedLocations, prefs.locations.toSet()) ||
        !_setEq(_selectedWorkModels, prefs.workModels.toSet()) ||
        !_setEq(_selectedJobTypes, prefs.jobTypes.toSet()) ||
        _minMatchScore != prefs.minMatchScore;
  }

  bool _setEq(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  // ── Actions ────────────────────────────────────────────────────────
  Future<void> _saveAndClose() async {
    HapticFeedback.lightImpact();
    final vm = context.read<JobsViewModel>();
    final userId = currentUserIdOrNull();
    if (userId == null) {
      // ignore: unawaited_futures
      handleSessionLost(context);
      return;
    }
    setState(() => _saving = true);

    try {
      final prefs = UserJobPreferences(
        userId: userId,
        areas: _selectedAreas.toList(),
        locations: _selectedLocations.toList(),
        workModels: _selectedWorkModels.toList(),
        jobTypes: _selectedJobTypes.toList(),
        minMatchScore: _minMatchScore,
      );
      await vm.savePreferences(prefs);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao salvar os filtros.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (mounted) Navigator.pop(context);
  }

  void _clearAll() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedAreas = {};
      _selectedLocations = {};
      _selectedWorkModels = {};
      _selectedJobTypes = {};
      _minMatchScore = null;
    });
  }

  void _toggleArea(String area) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedAreas.contains(area)) {
        _selectedAreas.remove(area);
      } else if (_selectedAreas.length < _maxAreas) {
        _selectedAreas.add(area);
      }
    });
  }

  void _toggleLocation(String loc) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedLocations.contains(loc)) {
        _selectedLocations.remove(loc);
      } else if (_selectedLocations.length < _maxLocations) {
        _selectedLocations.add(loc);
      }
    });
  }

  void _toggleWorkModel(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedWorkModels.contains(key)
          ? _selectedWorkModels.remove(key)
          : _selectedWorkModels.add(key);
    });
  }

  void _toggleJobType(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedJobTypes.contains(key)
          ? _selectedJobTypes.remove(key)
          : _selectedJobTypes.add(key);
    });
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxHeight = mq.size.height * 0.92;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDragHandle(),
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _buildSection(
                  icon: Icons.work_outline_rounded,
                  title: 'Áreas de interesse',
                  subtitle: '${_selectedAreas.length}/$_maxAreas selecionadas',
                  child: _buildAreaChips(),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  icon: Icons.location_on_outlined,
                  title: 'Localização',
                  subtitle: '${_selectedLocations.length}/$_maxLocations • Remoto sempre passa',
                  child: _buildLocationChips(),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  icon: Icons.home_work_outlined,
                  title: 'Modelo de trabalho',
                  subtitle: _selectedWorkModels.isEmpty
                      ? 'Todos os modelos'
                      : '${_selectedWorkModels.length} ${_selectedWorkModels.length == 1 ? "selecionado" : "selecionados"}',
                  child: _buildPairChips(_workModels, _selectedWorkModels, _toggleWorkModel),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  icon: Icons.assignment_ind_outlined,
                  title: 'Tipo de vaga',
                  subtitle: _selectedJobTypes.isEmpty
                      ? 'Todos os tipos'
                      : '${_selectedJobTypes.length} ${_selectedJobTypes.length == 1 ? "selecionado" : "selecionados"}',
                  child: _buildPairChips(_jobTypes, _selectedJobTypes, _toggleJobType),
                ),
                const SizedBox(height: 16),
                _buildMatchScoreSection(),
                const SizedBox(height: 8),
              ],
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  // ── Drag handle ────────────────────────────────────────────────────
  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: _border,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 24),
            color: _textSecondary,
            onPressed: () => Navigator.pop(context),
            splashRadius: 22,
          ),
          Expanded(
            child: Column(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => _gradient.createShader(bounds),
                  child: const Text(
                    'Filtros desta busca',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                if (_activeFiltersCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '$_activeFiltersCount filtro${_activeFiltersCount > 1 ? "s" : ""} ativo${_activeFiltersCount > 1 ? "s" : ""} · só nesta busca',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: _activeFiltersCount > 0 ? _clearAll : null,
            style: TextButton.styleFrom(
              foregroundColor: _indigo,
              disabledForegroundColor: _textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text(
              'Limpar',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section card wrapper ───────────────────────────────────────────
  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _indigo.withOpacity(0.12),
                      _purple.withOpacity(0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: _indigo),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── Chip groups ────────────────────────────────────────────────────
  Widget _buildAreaChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kJobAreas.map((area) {
        final selected = _selectedAreas.contains(area.label);
        final atMax = _selectedAreas.length >= _maxAreas && !selected;
        return _GradientChip(
          label: area.label,
          icon: area.icon,
          selected: selected,
          disabled: atMax,
          onTap: atMax ? null : () => _toggleArea(area.label),
        );
      }).toList(),
    );
  }

  Widget _buildLocationChips() {
    // Cidades selecionadas que vieram do Perfil (onboarding / preferências)
    // mas não estão no catálogo de 14 — aparecem primeiro como chips
    // selecionados removíveis. Sem isso ficavam invisíveis mesmo contando
    // no subtitle "X/5" (`_selectedLocations.length`).
    final outsideCatalog = _selectedLocations
        .where((loc) => !_locations.contains(loc))
        .toList();
    final atMax = _selectedLocations.length >= _maxLocations;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Cidades fora do catálogo — sempre selecionadas; tap remove.
        ...outsideCatalog.map((loc) => _GradientChip(
              label: loc,
              selected: true,
              onTap: () => _toggleLocation(loc),
            )),
        // Catálogo padrão.
        ..._locations.map((loc) {
          final selected = _selectedLocations.contains(loc);
          final disabled = atMax && !selected;
          return _GradientChip(
            label: loc,
            selected: selected,
            disabled: disabled,
            onTap: disabled ? null : () => _toggleLocation(loc),
          );
        }),
      ],
    );
  }

  Widget _buildPairChips(
    List<_PairItem> items,
    Set<String> selected,
    void Function(String) onToggle,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return _GradientChip(
          label: item.label,
          icon: item.icon,
          selected: selected.contains(item.key),
          onTap: () => onToggle(item.key),
        );
      }).toList(),
    );
  }

  // ── Match Score section ────────────────────────────────────────────
  /// Filtro por match score (0-100). null/0 = sem filtro. Score combina
  /// análise IA cacheada + fallback determinístico (calculado client-side
  /// no JobsViewModel).
  Widget _buildMatchScoreSection() {
    final hasValue = _minMatchScore != null && _minMatchScore! > 0;
    final value = (_minMatchScore ?? 0).toDouble();

    // Cor dinâmica baseada no nível selecionado (verde alto, amber médio, neutro baixo)
    final accent = !hasValue
        ? _textMuted
        : value >= 80
            ? AppColors.success
            : value >= 60
                ? AppColors.info
                : AppColors.warning;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _indigo.withOpacity(0.12),
                      _purple.withOpacity(0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 18, color: _indigo),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Match score mínimo',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Descrevia o efeito como se estivesse SEMPRE ligado,
                    // inclusive com o controle em "Qualquer" — a frase era
                    // falsa no estado padrão. Agora acompanha o estado.
                    // Revisão UX 28/07, achado P3-39.
                    Text(
                      hasValue
                          ? 'Escondendo vagas abaixo de $_minMatchScore%'
                          : 'Mostrando todas — arraste pra exigir mais afinidade',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasValue)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: _textMuted,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _minMatchScore = null);
                  },
                  splashRadius: 18,
                  tooltip: 'Limpar',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ShaderMask(
                  shaderCallback: (b) => hasValue
                      ? LinearGradient(colors: [accent, accent]).createShader(b)
                      : const LinearGradient(colors: [_textMuted, _textMuted])
                          .createShader(b),
                  child: Text(
                    hasValue ? '${value.toInt()}' : 'Off',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                      height: 1,
                    ),
                  ),
                ),
                if (hasValue)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 2),
                    child: Text(
                      '%',
                      style: TextStyle(
                        color: _textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: _border,
              thumbColor: Colors.white,
              overlayColor: accent.withOpacity(0.12),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 10,
                elevation: 4,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: value.clamp(0.0, 100.0),
              min: 0,
              max: 100,
              divisions: 20, // step de 5 em 5 — granularidade suficiente
              onChanged: (val) {
                HapticFeedback.selectionClick();
                setState(() {
                  _minMatchScore = val > 0 ? val.toInt() : null;
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('Qualquer',
                    style: TextStyle(
                        fontSize: 11,
                        color: _textMuted,
                        fontWeight: FontWeight.w600)),
                Text('Excelente fit',
                    style: TextStyle(
                        fontSize: 11,
                        color: _textMuted,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer (apply button) ──────────────────────────────────────────
  Widget _buildFooter() {
    final hasChanges = _hasUnsavedChanges;
    final label = _activeFiltersCount > 0
        ? 'Aplicar $_activeFiltersCount filtro${_activeFiltersCount > 1 ? "s" : ""}'
        : 'Ver todas as vagas';

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            14 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            border: Border(top: BorderSide(color: _border, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      gradient: _saving ? null : _gradient,
                      color: _saving ? _textMuted : null,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _saving
                          ? null
                          : [
                              BoxShadow(
                                color: _indigo.withOpacity(0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _saving ? null : _saveAndClose,
                        child: Center(
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      hasChanges
                                          ? Icons.tune_rounded
                                          : Icons.search_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Internal widgets / models
// ─────────────────────────────────────────────────────────────────────

/// Chip premium com gradient quando selecionado, neutro quando não.
class _GradientChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _GradientChip({
    required this.label,
    this.icon,
    this.selected = false,
    this.disabled = false,
    this.onTap,
  });

  static const _indigo = AppColors.primary;
  static const _purple = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final fadeOpacity = disabled ? 0.4 : 1.0;
    return Opacity(
      opacity: fadeOpacity,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: icon != null ? 12 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [_indigo, _purple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : AppColors.surfaceMuted,
            border: Border.all(
              color: selected ? Colors.transparent : AppColors.border,
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _indigo.withOpacity(0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textPrimary,
                  letterSpacing: -0.1,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Item raw value ↔ display label (modelo, tipo de vaga).
class _PairItem {
  final String key; // valor que vai pro DB
  final String label; // display
  final IconData icon;
  const _PairItem(this.key, this.label, {required this.icon});
}
