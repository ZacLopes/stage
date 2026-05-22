// LocationScreen — onde mora (cidade/estado).
// MVP: input manual. GPS via permission_handler fica como follow-up.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'work_locations_screen.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  late final TextEditingController _city;
  late final TextEditingController _state;

  @override
  void initState() {
    super.initState();
    final p = context.read<ProfileEditorViewModel>().personal;
    _city = TextEditingController(text: p?.locationCity ?? '');
    _state = TextEditingController(text: p?.locationState ?? '');
  }

  @override
  void dispose() {
    _city.dispose();
    _state.dispose();
    super.dispose();
  }

  bool get _canContinue => _city.text.trim().isNotEmpty;

  void _continue() async {
    AnalyticsService.shared.track('onboarding_preferences_location_completed');
    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    await vm.commitPersonal(base.copyWith(
      locationCity: _city.text.trim(),
      locationState: _state.text.trim().isEmpty ? null : _state.text.trim(),
      locationCountry: 'BR',
    ));
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkLocationsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Onde você mora?',
      progress: 0.84,
      onContinue: _canContinue ? _continue : null,
      child: Column(
        children: [
          TextField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Cidade *',
              hintText: 'Ex: São Paulo',
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _state,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Estado',
              hintText: 'Ex: SP',
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          ),
        ],
      ),
    );
  }
}
