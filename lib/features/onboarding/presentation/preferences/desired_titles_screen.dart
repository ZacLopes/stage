// DesiredTitlesScreen — áreas desejadas. Catálogo importado de
// `lib/core/constants/job_areas.dart` (single source of truth no Dart).
// Pra adicionar/remover/renomear área, ver instruções nesse arquivo.
// (legado: nome do arquivo + entidade ainda usam "title", mas a semântica é "área")

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/job_areas.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'location_screen.dart';

const _kBorderColor = Color(0xFFE5E7EB);
const _kLabelColor = Color(0xFF6B7280);
const _kTextColor = Color(0xFF111827);
const _kAccent = Color(0xFF29B6D2);
const _kChipBg = Color(0xFFF3F4F6);

class DesiredTitlesScreen extends StatefulWidget {
  const DesiredTitlesScreen({super.key});
  @override
  State<DesiredTitlesScreen> createState() => _DesiredTitlesScreenState();
}

class _DesiredTitlesScreenState extends State<DesiredTitlesScreen> {
  final Set<String> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Fonte primária: user_preferences.areas (115 users com áreas salvas
    // pós-Semana 2). Fonte secundária: profile_desired_titles legacy
    // (substring match). Sem o fetch da fonte primária, a tela abre vazia
    // pros 115 users que já tinham áreas configuradas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrateFromExistingPrefs();
    });
  }

  Future<void> _hydrateFromExistingPrefs() async {
    final selected = <String>{};

    // 1. Fonte primária: user_preferences.areas (array de strings que JÁ
    //    casam exatamente com os labels de kJobAreas — populadas via fluxo de
    //    job preferences). Match direto, sem heurística.
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final row = await Supabase.instance.client
            .from('user_preferences')
            .select('areas')
            .eq('user_id', userId)
            .maybeSingle();
        final rawAreas = row?['areas'];
        if (rawAreas is List) {
          final validLabels = kJobAreas.map((a) => a.label).toSet();
          for (final a in rawAreas) {
            final label = a?.toString() ?? '';
            if (validLabels.contains(label)) selected.add(label);
          }
        }
      }
    } catch (_) {
      // Falha silenciosa — cai pra fonte secundária. Não bloqueia onboarding.
    }

    // 2. Fonte secundária: profile_desired_titles legacy. Substring match
    //    pra entries tipo "Analista de Marketing" → "Marketing". Mantido
    //    pra cobrir users que tinham desired_titles mas não areas em
    //    user_preferences (edge case raro pós-Semana 2).
    if (!mounted) return;
    final existing = context.read<PreferencesViewModel>().desiredTitles;
    for (final t in existing) {
      final lower = t.title.toLowerCase();
      for (final area in kJobAreas) {
        if (selected.contains(area.label)) continue;
        if (lower.contains(area.label.toLowerCase())) {
          selected.add(area.label);
        }
      }
    }

    if (!mounted || selected.isEmpty) return;
    setState(() {
      _selected.addAll(selected);
    });
  }

  void _toggle(String label) {
    setState(() {
      if (_selected.contains(label)) {
        _selected.remove(label);
      } else {
        _selected.add(label);
      }
    });
  }

  Future<void> _continue() async {
    if (_saving) return;
    AnalyticsService.shared.track('onboarding_preferences_desired_titles_completed',
        props: {'count': _selected.length});
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
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
    final vm = context.read<PreferencesViewModel>();
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.replaceDesiredTitles(entries),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LocationScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Em quais áreas você quer atuar?',
      subtitle: 'Toca nas que combinam com você.',
      progress: 0.69,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_selected.isEmpty || _saving) ? null : _continue,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: kJobAreas.map((area) {
          final selected = _selected.contains(area.label);
          return _AreaChip(
            label: area.label,
            icon: area.icon,
            selected: selected,
            onTap: () => _toggle(area.label),
          );
        }).toList(),
      ),
    );
  }
}

class _AreaChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AreaChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _kAccent : _kChipBg;
    final fg = selected ? Colors.white : _kTextColor;
    final iconColor = selected ? Colors.white : _kLabelColor;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? _kAccent : _kBorderColor,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
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
