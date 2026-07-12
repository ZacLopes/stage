// PreferencesTab — sub-aba da aba Perfil que mostra as 5 preferências de
// vaga editáveis (áreas, modo, tipos, localização, cidades) e abre sheets
// modais pra editar cada uma.
//
// As preferências coletadas no onboarding (DesiredTitlesScreen,
// WorkModeScreen, etc.) eram imutáveis até existir esta tela. Agora o user
// pode trocar a qualquer momento — útil quando muda de cidade, decide
// trabalhar remoto, ou descobre interesse em outra área.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../auth/auth_session.dart';

import '../../../../core/constants/job_areas.dart';
import '../../../trilha/application/area_canonical.dart'
    show isCanonicalArea, canonicalArea;
import '../../../../services/analytics_service.dart';
import '../../application/preferences_view_model.dart';
import '../../application/profile_editor_view_model.dart';
import '../../domain/entities/entities.dart';
import '../../../../core/theme/theme.dart';

const _kAccent = AppColors.primary;
const _kBorderColor = AppColors.border;
const _kLabelColor = AppColors.textTertiary;
const _kHintColor = AppColors.textDisabled;
const _kTextColor = AppColors.textPrimary;
const _kCardBg = AppColors.surfaceVariant;
const _kError = AppColors.error;

class PreferencesTab extends StatefulWidget {
  const PreferencesTab({super.key});

  @override
  State<PreferencesTab> createState() => _PreferencesTabState();
}

class _PreferencesTabState extends State<PreferencesTab> {
  @override
  void initState() {
    super.initState();
    // Carrega no postFrame pra evitar setState durante build do parent.
    // PreferencesViewModel é singleton no MultiProvider — load() é
    // idempotente e necessário pra trazer dados quando a aba abre.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PreferencesViewModel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefsVm = context.watch<PreferencesViewModel>();
    final profileVm = context.watch<ProfileEditorViewModel>();

    if (prefsVm.isLoading && prefsVm.prefs == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => prefsVm.load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          _PrefCard(
            icon: Icons.work_outline_rounded,
            title: 'Áreas desejadas',
            emptyHint: 'Nenhuma área selecionada',
            chips: prefsVm.desiredTitles.map((t) => t.title).toList(),
            onEdit: () => _editAreas(context),
          ),
          const SizedBox(height: 10),
          _PrefCard(
            icon: Icons.home_work_outlined,
            title: 'Modo de trabalho',
            emptyHint: 'Não definido',
            chips: (prefsVm.prefs?.workMode ?? const [])
                .map(_workModeLabel)
                .toList(),
            onEdit: () => _editWorkMode(context),
          ),
          const SizedBox(height: 10),
          _PrefCard(
            icon: Icons.badge_outlined,
            title: 'Tipos de vaga',
            emptyHint: 'Não definido',
            chips: (prefsVm.prefs?.jobTypes ?? const [])
                .map(_jobTypeLabel)
                .toList(),
            onEdit: () => _editJobTypes(context),
          ),
          const SizedBox(height: 10),
          _PrefCard(
            icon: Icons.location_on_outlined,
            title: 'Onde você mora',
            emptyHint: 'Não informado',
            chips: [
              if ((profileVm.personal?.locationCity ?? '').isNotEmpty)
                [
                  profileVm.personal?.locationCity,
                  profileVm.personal?.locationState,
                ].where((s) => s != null && s.isNotEmpty).join(', '),
            ],
            onEdit: () => _editHomeLocation(context),
          ),
          const SizedBox(height: 10),
          _PrefCard(
            icon: Icons.travel_explore_rounded,
            title: 'Cidades onde quer trabalhar',
            emptyHint: 'Nenhuma cidade adicionada',
            chips: prefsVm.otherLocations
                .where((l) => (l.city ?? '').isNotEmpty)
                .map((l) =>
                    [l.city, l.state].where((s) => (s ?? '').isNotEmpty).join(', '))
                .toList(),
            onEdit: () => _editWorkLocations(context),
          ),
        ],
      ),
    );
  }

  // ── Editores (BottomSheets) ─────────────────────────────────────────────

  Future<void> _editAreas(BuildContext context) {
    AnalyticsService.shared.track('prefs_tab_edit_opened', props: {'section': 'areas'});
    return _showSheet(context, const _AreasSheet());
  }

  Future<void> _editWorkMode(BuildContext context) {
    AnalyticsService.shared.track('prefs_tab_edit_opened', props: {'section': 'work_mode'});
    return _showSheet(context, const _WorkModeSheet());
  }

  Future<void> _editJobTypes(BuildContext context) {
    AnalyticsService.shared.track('prefs_tab_edit_opened', props: {'section': 'job_types'});
    return _showSheet(context, const _JobTypesSheet());
  }

  Future<void> _editHomeLocation(BuildContext context) {
    AnalyticsService.shared.track('prefs_tab_edit_opened', props: {'section': 'home_location'});
    return _showSheet(context, const _HomeLocationSheet());
  }

  Future<void> _editWorkLocations(BuildContext context) {
    AnalyticsService.shared.track('prefs_tab_edit_opened', props: {'section': 'work_locations'});
    return _showSheet(context, const _WorkLocationsSheet());
  }

  Future<void> _showSheet(BuildContext context, Widget child) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      // Constrange o sheet a 85% da tela — sem isso, isScrollControlled
      // permite consumir 100% e o título fica embaixo da status bar/
      // dynamic island.
      constraints: BoxConstraints(maxHeight: maxHeight),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: child,
      ),
    );
  }
}

// =============================================================================
// _PrefCard — card de leitura com botão Editar
// =============================================================================

class _PrefCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String emptyHint;
  final List<String> chips;
  final VoidCallback onEdit;

  const _PrefCard({
    required this.icon,
    required this.title,
    required this.emptyHint,
    required this.chips,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = chips.isNotEmpty && chips.any((c) => c.isNotEmpty);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onEdit();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: _kAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _kTextColor,
                      ),
                    ),
                  ),
                  Text(
                    'Editar',
                    style: TextStyle(
                      color: _kAccent.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _kAccent.withValues(alpha: 0.9),
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!hasContent)
                Padding(
                  padding: const EdgeInsets.only(left: 44),
                  child: Text(
                    emptyHint,
                    style: const TextStyle(color: _kHintColor, fontSize: 13),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 44),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: chips.where((c) => c.isNotEmpty).map((c) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _kCardBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          c,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _kTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// _SheetShell — wrapper visual padrão dos sheets de edição
// =============================================================================

class _SheetShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  const _SheetShell({
    required this.title,
    this.subtitle,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    // useSafeArea no showModalBottomSheet já cuida do top inset (status bar/
    // dynamic island). Aqui só adicionamos padding interno + handle visual.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _kBorderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _kTextColor,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(color: _kLabelColor, fontSize: 14),
              ),
            ],
            const SizedBox(height: 16),
            Flexible(child: child),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

Widget _saveButton({
  required bool enabled,
  required bool loading,
  required VoidCallback onPressed,
  String label = 'Salvar',
}) {
  return SizedBox(
    height: 52,
    width: double.infinity,
    child: ElevatedButton(
      onPressed: (!enabled || loading) ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _kAccent.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
    ),
  );
}

// =============================================================================
// _AreasSheet — Áreas desejadas (multi-select)
// Catálogo importado de `lib/core/constants/job_areas.dart` — single source
// of truth. Mudar a lista lá reflete aqui e no DesiredTitlesScreen do
// onboarding. Ver instruções de sync cross-language no arquivo.
// =============================================================================

class _AreasSheet extends StatefulWidget {
  const _AreasSheet();

  @override
  State<_AreasSheet> createState() => _AreasSheetState();
}

class _AreasSheetState extends State<_AreasSheet> {
  late Set<String> _selected;
  late Set<String> _initial;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = context.read<PreferencesViewModel>().desiredTitles;
    // Canoniza a CAIXA das canônicas ("finanças" → "Finanças") pra elas casarem
    // o chip; área custom ("direito") fica como está e vira um chip EXTRA.
    _initial = current
        .map((t) => isCanonicalArea(t.title) ? canonicalArea(t.title) : t.title)
        .toSet();
    _selected = Set.of(_initial);
  }

  bool get _isDirty =>
      _selected.length != _initial.length ||
      !_selected.containsAll(_initial);

  Future<void> _save() async {
    final userId = currentUserIdOrNull();
    if (userId == null) {
      // ignore: unawaited_futures
      handleSessionLost(context);
      return;
    }
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    final entries = _selected
        .toList()
        .asMap()
        .entries
        .map((e) => DesiredTitle(
              id: '',
              userId: userId,
              title: e.value,
              source: DesiredTitleSource.userAdded,
              orderIndex: e.key,
            ))
        .toList();
    try {
      await context.read<PreferencesViewModel>().replaceDesiredTitles(entries);
      if (!mounted) return;
      AnalyticsService.shared.track('prefs_tab_areas_saved',
          props: {'count': _selected.length});
      Navigator.pop(context);
      _snack(context, 'Áreas atualizadas');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Áreas desejadas',
      subtitle: 'Toca pra escolher onde você quer atuar.',
      action: _saveButton(
        enabled: _isDirty,
        loading: _saving,
        onPressed: _save,
      ),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final area in kJobAreas)
              _ChipToggle(
                label: area.label,
                icon: area.icon,
                selected: _selected.contains(area.label),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (_selected.contains(area.label)) {
                      _selected.remove(area.label);
                    } else {
                      _selected.add(area.label);
                    }
                  });
                },
              ),
            // Áreas CUSTOM que o user adicionou pela trilha (ex.: "direito") —
            // sempre selecionadas; tocar remove (senão ficavam invisíveis + sem
            // como tirar).
            for (final custom
                in _selected.where((t) => !isCanonicalArea(t)).toList())
              _ChipToggle(
                label: custom,
                icon: Icons.label_outline,
                selected: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selected.remove(custom));
                },
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _WorkModeSheet — Modo de trabalho (Remoto/Híbrido/Presencial)
// =============================================================================

class _WorkModeSheet extends StatefulWidget {
  const _WorkModeSheet();
  @override
  State<_WorkModeSheet> createState() => _WorkModeSheetState();
}

class _WorkModeSheetState extends State<_WorkModeSheet> {
  late Set<WorkMode> _selected;
  late Set<WorkMode> _initial;
  bool _saving = false;

  static const _options = <(WorkMode, String, IconData)>[
    (WorkMode.remote, 'Remoto', Icons.home_outlined),
    (WorkMode.hybrid, 'Híbrido', Icons.sync_alt_outlined),
    (WorkMode.inPerson, 'Presencial', Icons.business_outlined),
  ];

  @override
  void initState() {
    super.initState();
    final current = context.read<PreferencesViewModel>().prefs?.workMode ?? const [];
    _initial = current.toSet();
    _selected = Set.of(_initial);
  }

  bool get _isDirty =>
      _selected.length != _initial.length ||
      !_selected.containsAll(_initial);

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      await context.read<PreferencesViewModel>().setWorkMode(_selected.toList());
      if (!mounted) return;
      AnalyticsService.shared.track('prefs_tab_work_mode_saved',
          props: {'count': _selected.length});
      Navigator.pop(context);
      _snack(context, 'Modo de trabalho atualizado');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Modo de trabalho',
      subtitle: 'Pode selecionar mais de um.',
      action: _saveButton(
        enabled: _isDirty,
        loading: _saving,
        onPressed: _save,
      ),
      child: Column(
        children: _options.map((t) {
          final value = t.$1;
          final label = t.$2;
          final icon = t.$3;
          final selected = _selected.contains(value);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ListTile(
              icon: icon,
              label: label,
              selected: selected,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (selected) {
                    _selected.remove(value);
                  } else {
                    _selected.add(value);
                  }
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================================
// _JobTypesSheet — Tipos de vaga (Estágio/Trainee/CLT/Temporário)
// =============================================================================

class _JobTypesSheet extends StatefulWidget {
  const _JobTypesSheet();
  @override
  State<_JobTypesSheet> createState() => _JobTypesSheetState();
}

class _JobTypesSheetState extends State<_JobTypesSheet> {
  late Set<JobType> _selected;
  late Set<JobType> _initial;
  bool _saving = false;

  static const _options = <(JobType, String, IconData)>[
    (JobType.internship, 'Estágio', Icons.school_rounded),
    (JobType.trainee, 'Trainee', Icons.rocket_launch_rounded),
    (JobType.juniorFullTime, 'CLT Júnior', Icons.badge_rounded),
    (JobType.temporary, 'Temporário', Icons.schedule_rounded),
  ];

  @override
  void initState() {
    super.initState();
    final current = context.read<PreferencesViewModel>().prefs?.jobTypes ?? const [];
    _initial = current.toSet();
    _selected = Set.of(_initial);
  }

  bool get _isDirty =>
      _selected.length != _initial.length ||
      !_selected.containsAll(_initial);

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      await context.read<PreferencesViewModel>().setJobTypes(_selected.toList());
      if (!mounted) return;
      AnalyticsService.shared.track('prefs_tab_job_types_saved',
          props: {'count': _selected.length});
      Navigator.pop(context);
      _snack(context, 'Tipos de vaga atualizados');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Tipos de vaga',
      subtitle: 'Pode selecionar mais de um.',
      action: _saveButton(
        enabled: _isDirty,
        loading: _saving,
        onPressed: _save,
      ),
      child: Column(
        children: _options.map((t) {
          final value = t.$1;
          final label = t.$2;
          final icon = t.$3;
          final selected = _selected.contains(value);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ListTile(
              icon: icon,
              label: label,
              selected: selected,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (selected) {
                    _selected.remove(value);
                  } else {
                    _selected.add(value);
                  }
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================================
// _HomeLocationSheet — Cidade onde mora (CEP + ViaCEP lookup)
// =============================================================================

class _HomeLocationSheet extends StatefulWidget {
  const _HomeLocationSheet();
  @override
  State<_HomeLocationSheet> createState() => _HomeLocationSheetState();
}

class _HomeLocationSheetState extends State<_HomeLocationSheet> {
  final _cep = TextEditingController();
  String? _resolvedCity;
  String? _resolvedState;
  Timer? _debounce;
  bool _cepLoading = false;
  bool _saving = false;
  String? _hint;

  // Snapshot do estado inicial pra calcular dirty.
  String? _initialCity;
  String? _initialState;
  String _initialCep = '';

  @override
  void initState() {
    super.initState();
    final p = context.read<ProfileEditorViewModel>().personal;
    final initialCep = p?.locationPostalCode ?? '';
    _resolvedCity = p?.locationCity;
    _resolvedState = p?.locationState;
    _initialCity = p?.locationCity;
    _initialState = p?.locationState;
    _initialCep = initialCep;
    if (initialCep.isNotEmpty) {
      _cep.text = _formatCep(initialCep);
    }
    _cep.addListener(_onCepTyped);
  }

  bool get _isDirty {
    if ((_resolvedCity ?? '') != (_initialCity ?? '')) return true;
    if ((_resolvedState ?? '') != (_initialState ?? '')) return true;
    final currentCep = _cep.text.replaceAll(RegExp(r'\D'), '');
    final initialCepDigits = _initialCep.replaceAll(RegExp(r'\D'), '');
    if (currentCep != initialCepDigits) return true;
    return false;
  }

  @override
  void dispose() {
    _cep.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  static String _formatCep(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    final c = d.length > 8 ? d.substring(0, 8) : d;
    return c.length > 5 ? '${c.substring(0, 5)}-${c.substring(5)}' : c;
  }

  void _onCepTyped() {
    final digits = _cep.text.replaceAll(RegExp(r'\D'), '');
    _debounce?.cancel();
    if (digits.length == 8) {
      _debounce = Timer(const Duration(milliseconds: 350), () => _lookup(digits));
    } else if (_resolvedCity != null) {
      setState(() {
        _resolvedCity = null;
        _resolvedState = null;
        _hint = null;
      });
    }
  }

  Future<void> _lookup(String cep) async {
    setState(() {
      _cepLoading = true;
      _hint = null;
    });
    try {
      final res = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        setState(() {
          _hint = 'Não consegui buscar o CEP';
          _cepLoading = false;
        });
        return;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['erro'] == true) {
        setState(() {
          _hint = 'CEP não encontrado';
          _resolvedCity = null;
          _resolvedState = null;
          _cepLoading = false;
        });
        return;
      }
      setState(() {
        _resolvedCity = json['localidade'] as String?;
        _resolvedState = json['uf'] as String?;
        _cepLoading = false;
      });
    } catch (_) {
      setState(() {
        _hint = 'Erro ao buscar CEP';
        _cepLoading = false;
      });
    }
  }

  /// Pode salvar quando tem cidade resolvida E o user mudou algo. Sem
  /// dirty check, o user poderia "salvar" o mesmo estado e parecer que
  /// algo aconteceu.
  bool get _canSave =>
      (_resolvedCity != null && _resolvedCity!.isNotEmpty) &&
      !_saving &&
      _isDirty;

  Future<void> _save() async {
    if (!_canSave) return;
    final userId = currentUserIdOrNull();
    if (userId == null) {
      // ignore: unawaited_futures
      handleSessionLost(context);
      return;
    }
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    final vm = context.read<ProfileEditorViewModel>();
    final base = vm.personal ?? PersonalInfo(userId: userId);
    try {
      await vm.commitPersonal(base.copyWith(
        locationCity: _resolvedCity,
        locationState: _resolvedState,
        locationCountry: 'BR',
        locationPostalCode: _cep.text.trim().isEmpty ? null : _cep.text.trim(),
      ));
      if (!mounted) return;
      AnalyticsService.shared.track('prefs_tab_home_location_saved');
      Navigator.pop(context);
      _snack(context, 'Localização atualizada');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Onde você mora',
      subtitle: 'Vamos usar pra mostrar vagas próximas.',
      action: _saveButton(
        enabled: _canSave,
        loading: _saving,
        onPressed: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'CEP',
            style: TextStyle(
              fontSize: 13,
              color: _kLabelColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _cep,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _kTextColor,
            ),
            decoration: InputDecoration(
              hintText: '12345-678',
              hintStyle: const TextStyle(
                color: _kHintColor,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              filled: true,
              fillColor: _kCardBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              suffixIcon: _cepLoading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBorderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kAccent, width: 1.5),
              ),
            ),
            // Reaplica formatação ao digitar (sem inputFormatter pra evitar
            // conflito com listener — formatação manual)
            onChanged: (v) {
              final formatted = _formatCep(v);
              if (formatted != v) {
                _cep.value = TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
              }
            },
          ),
          if (_hint != null) ...[
            const SizedBox(height: 8),
            Text(_hint!, style: const TextStyle(fontSize: 12, color: _kError)),
          ],
          if (_resolvedCity != null && _resolvedCity!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 18, color: _kLabelColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [_resolvedCity, _resolvedState, 'Brasil']
                        .where((s) => s != null && s.isNotEmpty)
                        .join(', '),
                    style: const TextStyle(
                      fontSize: 15,
                      color: _kLabelColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// _WorkLocationsSheet — Cidades onde quer trabalhar (busca IBGE)
// =============================================================================

class _WorkLocationsSheet extends StatefulWidget {
  const _WorkLocationsSheet();
  @override
  State<_WorkLocationsSheet> createState() => _WorkLocationsSheetState();
}

class _WorkLocationsSheetState extends State<_WorkLocationsSheet> {
  late List<OtherLocation> _locations;
  late Set<String> _initialKeys;
  bool _saving = false;

  // Chave determinística por cidade pra comparar listas sem depender
  // do `id` (registros novos têm id='').
  static String _keyOf(OtherLocation l) =>
      '${(l.city ?? '').toLowerCase()}|${l.state ?? ''}|${l.country ?? ''}';

  @override
  void initState() {
    super.initState();
    final current = context.read<PreferencesViewModel>().otherLocations;
    _locations = List.of(current);
    _initialKeys = current.map(_keyOf).toSet();
  }

  bool get _isDirty {
    final currentKeys = _locations.map(_keyOf).toSet();
    return currentKeys.length != _initialKeys.length ||
        !currentKeys.containsAll(_initialKeys);
  }

  Future<void> _addCity() async {
    final pick = await Navigator.of(context).push<_CitySelection>(
      MaterialPageRoute(builder: (_) => const _CitySearchScreen()),
    );
    if (pick == null || !mounted) return;
    final exists = _locations.any((l) =>
        (l.city?.toLowerCase() ?? '') == pick.city.toLowerCase() &&
        (l.state ?? '') == pick.uf);
    if (exists) return;
    setState(() {
      _locations.add(OtherLocation(
        id: '',
        // user_id é re-carimbado pelo repo no insert; placeholder seguro.
        userId: currentUserIdOrNull() ?? '',
        city: pick.city,
        state: pick.uf,
        country: 'BR',
      ));
    });
  }

  void _remove(OtherLocation loc) {
    setState(() => _locations.remove(loc));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      await context.read<PreferencesViewModel>().replaceOtherLocations(_locations);
      if (!mounted) return;
      AnalyticsService.shared.track('prefs_tab_work_locations_saved',
          props: {'count': _locations.length});
      Navigator.pop(context);
      _snack(context, 'Cidades atualizadas');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Cidades onde quer trabalhar',
      subtitle: 'Sem cidades = aberto a qualquer lugar.',
      action: _saveButton(
        enabled: _isDirty,
        loading: _saving,
        onPressed: _save,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._locations.map((loc) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    decoration: BoxDecoration(
                      color: _kCardBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            [loc.city, loc.state]
                                .where((s) => (s ?? '').isNotEmpty)
                                .join(', '),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _kTextColor,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: _kError,
                            size: 22,
                          ),
                          onPressed: () => _remove(loc),
                        ),
                      ],
                    ),
                  ),
                )),
            Material(
              color: _kAccent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _addCity,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kAccent, width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kAccent,
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Adicionar cidade',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _kAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Busca IBGE de cidades (reutilizada do onboarding) ────────────────────

class _CitySelection {
  final String city;
  final String uf;
  const _CitySelection({required this.city, required this.uf});
}

class _IbgeCity {
  final String name;
  final String uf;
  const _IbgeCity({required this.name, required this.uf});
}

/// Cache em memória da lista de municípios. ~5.570 entries (~250kb),
/// 1 fetch por sessão do app.
List<_IbgeCity>? _ibgeCache;

class _CitySearchScreen extends StatefulWidget {
  const _CitySearchScreen();
  @override
  State<_CitySearchScreen> createState() => _CitySearchScreenState();
}

class _CitySearchScreenState extends State<_CitySearchScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  List<_IbgeCity> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQuery);
    _ensureCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _ensureCache() async {
    if (_ibgeCache != null) return;
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse(
              'https://servicodados.ibge.gov.br/api/v1/localidades/municipios?orderBy=nome'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Não consegui carregar a lista de cidades';
          _loading = false;
        });
        return;
      }
      final list = jsonDecode(res.body) as List;
      _ibgeCache = list.map((j) {
        final m = j as Map<String, dynamic>;
        final uf =
            (m['microrregiao']?['mesorregiao']?['UF']?['sigla'] as String?) ?? '';
        return _IbgeCity(name: m['nome'] as String, uf: uf);
      }).toList();
      setState(() => _loading = false);
    } catch (_) {
      setState(() {
        _error = 'Erro de conexão';
        _loading = false;
      });
    }
  }

  void _onQuery() {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    final cache = _ibgeCache;
    if (cache == null) return;
    final normalized = _strip(q);
    final matches = <_IbgeCity>[];
    for (final c in cache) {
      final cityNorm = _strip(c.name.toLowerCase());
      if (cityNorm.startsWith(normalized) || cityNorm.contains(' $normalized')) {
        matches.add(c);
        if (matches.length >= 30) break;
      }
    }
    if (matches.isEmpty) {
      for (final c in cache) {
        if (_strip(c.name.toLowerCase()).contains(normalized)) {
          matches.add(c);
          if (matches.length >= 30) break;
        }
      }
    }
    setState(() => _results = matches);
  }

  String _strip(String s) {
    const ac = 'áàâãäåéèêëíìîïóòôõöúùûüçÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const rp = 'aaaaaaeeeeiiiiooooouuuucAAAAAAEEEEIIIIOOOOOUUUUC';
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      final i = ac.indexOf(ch);
      buf.write(i >= 0 ? rp[i] : ch);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: _kTextColor,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _kCardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _query,
                        focusNode: _focus,
                        style: const TextStyle(fontSize: 17, color: _kTextColor),
                        decoration: const InputDecoration(
                          hintText: 'Digite uma cidade',
                          hintStyle: TextStyle(
                            color: _kHintColor,
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _ibgeCache == null) {
      return const Center(
        child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2.5),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, color: _kHintColor, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kLabelColor, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() => _error = null);
                  _ensureCache();
                },
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }
    if (_query.text.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_rounded, color: _kHintColor, size: 56),
              SizedBox(height: 12),
              Text(
                'Comece a digitar pra buscar',
                style: TextStyle(color: _kLabelColor, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'Nenhuma cidade encontrada',
            style: TextStyle(
              color: _kLabelColor.withValues(alpha: 0.9),
              fontSize: 14,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: _kBorderColor),
      itemBuilder: (_, i) {
        final c = _results[i];
        return InkWell(
          onTap: () => Navigator.pop(
            context,
            _CitySelection(city: c.name, uf: c.uf),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _kTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${c.uf}, Brasil',
                        style: const TextStyle(
                          fontSize: 14,
                          color: _kLabelColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.near_me_outlined,
                  color: _kHintColor,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Widgets compartilhados (chips, tiles, helpers)
// =============================================================================

class _ChipToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ChipToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _kAccent : AppColors.background;
    final fg = selected ? Colors.white : _kTextColor;
    final iconColor = selected ? Colors.white : _kLabelColor;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? _kAccent : _kBorderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ListTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _kAccent.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _kAccent : _kBorderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? _kAccent : _kLabelColor,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? _kAccent : _kTextColor,
                ),
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? _kAccent : Colors.white,
                border: Border.all(
                  color: selected ? _kAccent : AppColors.borderStrong,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// Labels pros enums (consistente com onboarding)
String _workModeLabel(WorkMode m) {
  switch (m) {
    case WorkMode.remote:
      return 'Remoto';
    case WorkMode.hybrid:
      return 'Híbrido';
    case WorkMode.inPerson:
      return 'Presencial';
  }
}

String _jobTypeLabel(JobType t) {
  switch (t) {
    case JobType.internship:
      return 'Estágio';
    case JobType.trainee:
      return 'Trainee';
    case JobType.juniorFullTime:
      return 'CLT Júnior';
    case JobType.temporary:
      return 'Temporário';
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}
