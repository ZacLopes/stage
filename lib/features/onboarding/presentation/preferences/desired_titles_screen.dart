// DesiredTitlesScreen — cargos desejados com smart suggestions "Do seu currículo".

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'countries_screen.dart';

class DesiredTitlesScreen extends StatefulWidget {
  const DesiredTitlesScreen({super.key});
  @override
  State<DesiredTitlesScreen> createState() => _DesiredTitlesScreenState();
}

class _DesiredTitlesScreenState extends State<DesiredTitlesScreen> {
  final TextEditingController _input = TextEditingController();
  final List<DesiredTitle> _selected = [];

  @override
  void initState() {
    super.initState();
    _selected.addAll(context.read<PreferencesViewModel>().desiredTitles);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  List<String> get _fromResume {
    final exps = context.read<ProfileEditorViewModel>().experiences;
    return exps.take(3).map((e) => e.title).where((t) => t.isNotEmpty).toList();
  }

  void _add(String title, {DesiredTitleSource source = DesiredTitleSource.userAdded}) {
    final clean = title.trim();
    if (clean.isEmpty) return;
    if (_selected.any((s) => s.title.toLowerCase() == clean.toLowerCase())) return;
    if (_selected.length >= 10) return;
    setState(() {
      _selected.add(DesiredTitle(
        id: '',
        userId: Supabase.instance.client.auth.currentUser?.id ?? '',
        title: clean,
        source: source,
        orderIndex: _selected.length,
      ));
      _input.clear();
    });
  }

  void _continue() async {
    AnalyticsService.shared.track('onboarding_preferences_desired_titles_completed',
        props: {'count': _selected.length});
    await context.read<PreferencesViewModel>().replaceDesiredTitles(_selected);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CountriesScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final fromResume = _fromResume.where((t) =>
        !_selected.any((s) => s.title.toLowerCase() == t.toLowerCase())).toList();

    return OnboardingScaffold(
      title: 'Quais cargos procura?',
      subtitle: 'Você pode adicionar até 10.',
      progress: 0.8,
      onContinue: _selected.isEmpty ? null : _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Ex: Analista de Marketing',
                    filled: true, fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                  onSubmitted: _add,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFF00C27A), size: 32),
                onPressed: () => _add(_input.text),
              ),
            ],
          ),
          if (fromResume.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Do seu currículo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: fromResume
                  .map((t) => ActionChip(
                        label: Text(t),
                        avatar: const Icon(Icons.add, size: 16, color: Color(0xFF00C27A)),
                        backgroundColor: const Color(0xFF00C27A).withValues(alpha: 0.08),
                        side: const BorderSide(color: Color(0xFF00C27A)),
                        onPressed: () => _add(t, source: DesiredTitleSource.fromResume),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          if (_selected.isNotEmpty) ...[
            const Text('Selecionados', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: _selected
                  .map((s) => Chip(
                        label: Text(s.title),
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(() => _selected.remove(s)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
