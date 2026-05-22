// DesiredTitlesScreen — áreas desejadas. Catálogo fixo de 12 áreas alinhado
// com job_preferences_screen + inferArea() dos edge functions de sync.
// (legado: nome do arquivo + entidade ainda usam "title", mas a semântica é "área")

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'location_screen.dart';

const _kBorderColor = Color(0xFFE5E7EB);
const _kLabelColor = Color(0xFF6B7280);
const _kTextColor = Color(0xFF111827);
const _kAccent = Color(0xFF00C27A);
const _kChipBg = Color(0xFFF3F4F6);

class _Area {
  final String label;
  final IconData icon;
  const _Area(this.label, this.icon);
}

// Lista alinhada com job_preferences_screen._areas e inferArea() das edge
// functions de sync (sync-jobs-ats, sync-jobs-apify).
const List<_Area> _areas = [
  _Area('Tecnologia', Icons.computer_rounded),
  _Area('Engenharia', Icons.engineering_rounded),
  _Area('Design', Icons.palette_rounded),
  _Area('Produto', Icons.widgets_rounded),
  _Area('Marketing', Icons.campaign_rounded),
  _Area('Vendas', Icons.trending_up_rounded),
  _Area('Finanças', Icons.attach_money_rounded),
  _Area('Recursos Humanos', Icons.groups_rounded),
  _Area('Operações', Icons.settings_rounded),
  _Area('Jurídico', Icons.gavel_rounded),
  _Area('Administrativo', Icons.folder_rounded),
  _Area('Geral', Icons.work_rounded),
];

class DesiredTitlesScreen extends StatefulWidget {
  const DesiredTitlesScreen({super.key});
  @override
  State<DesiredTitlesScreen> createState() => _DesiredTitlesScreenState();
}

class _DesiredTitlesScreenState extends State<DesiredTitlesScreen> {
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _hydrateFromExistingPrefs();
  }

  /// Pré-seleciona áreas baseado em desired_titles antigos. Se o user já tinha
  /// "Analista de Marketing" salvo, infere "Marketing". Substring match
  /// case-insensitive — perde precisão pra entries que não mapeiam (ex:
  /// "Software Engineer" não pega "Tecnologia"), mas é melhor que nada.
  void _hydrateFromExistingPrefs() {
    final existing = context.read<PreferencesViewModel>().desiredTitles;
    for (final t in existing) {
      final lower = t.title.toLowerCase();
      for (final area in _areas) {
        if (_selected.contains(area.label)) continue;
        if (lower.contains(area.label.toLowerCase())) {
          _selected.add(area.label);
        }
      }
    }
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
    await context.read<PreferencesViewModel>().replaceDesiredTitles(entries);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LocationScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Em quais áreas você quer atuar?',
      subtitle: 'Toca nas que combinam com você.',
      progress: 0.69,
      onContinue: _selected.isEmpty ? null : _continue,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _areas.map((area) {
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
