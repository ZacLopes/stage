// WorkLocationsScreen — localizações desejadas + raio, ou "Aberto a qualquer lugar".

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'work_mode_screen.dart';

class WorkLocationsScreen extends StatefulWidget {
  const WorkLocationsScreen({super.key});
  @override
  State<WorkLocationsScreen> createState() => _WorkLocationsScreenState();
}

class _WorkLocationsScreenState extends State<WorkLocationsScreen> {
  bool _openToAnywhere = false;
  final List<OtherLocation> _locations = [];

  @override
  void initState() {
    super.initState();
    final vm = context.read<PreferencesViewModel>();
    _locations.addAll(vm.otherLocations);
  }

  Future<void> _addLocation() async {
    final result = await showModalBottomSheet<OtherLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _AddLocationSheet(),
    );
    if (result != null) {
      setState(() => _locations.add(result));
    }
  }

  void _next() async {
    AnalyticsService.shared.track('onboarding_preferences_work_locations_completed');
    final vm = context.read<PreferencesViewModel>();
    await vm.replaceOtherLocations(_openToAnywhere ? [] : _locations);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkModeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Onde quer trabalhar?',
      progress: 0.86,
      onContinue: _next,
      skipButton: TextButton(onPressed: _next, child: const Text('Pular')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            title: const Text('Aberto a qualquer lugar', style: TextStyle(fontWeight: FontWeight.w600)),
            value: _openToAnywhere,
            activeThumbColor: const Color(0xFF00C27A),
            onChanged: (v) => setState(() => _openToAnywhere = v),
          ),
          if (!_openToAnywhere) ...[
            const SizedBox(height: 8),
            ..._locations.map((l) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Color(0xFF6B7280)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          [l.city, l.state, l.country].where((s) => s != null && s.isNotEmpty).join(', '),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text('${l.radiusKm} km', style: const TextStyle(color: Color(0xFF6B7280))),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _locations.remove(l)),
                      ),
                    ],
                  ),
                )),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, color: Color(0xFF00C27A)),
              label: const Text('Adicionar localização', style: TextStyle(color: Color(0xFF00C27A))),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF00C27A)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _addLocation,
            ),
          ],
        ],
      ),
    );
  }
}

class _AddLocationSheet extends StatefulWidget {
  const _AddLocationSheet();
  @override
  State<_AddLocationSheet> createState() => _AddLocationSheetState();
}

class _AddLocationSheetState extends State<_AddLocationSheet> {
  final _city = TextEditingController();
  final _state = TextEditingController();
  int _radius = 50;

  @override
  void dispose() {
    _city.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'Cidade', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _state,
            decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Raio: '),
              Expanded(
                child: Slider(
                  value: _radius.toDouble(),
                  min: 5, max: 200, divisions: 39,
                  label: '$_radius km',
                  activeColor: const Color(0xFF00C27A),
                  onChanged: (v) => setState(() => _radius = v.toInt()),
                ),
              ),
              Text('$_radius km'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48, width: double.infinity,
            child: ElevatedButton(
              onPressed: _city.text.isEmpty
                  ? null
                  : () {
                      Navigator.pop(
                        context,
                        OtherLocation(
                          id: '',
                          userId: Supabase.instance.client.auth.currentUser?.id ?? '',
                          city: _city.text.trim(),
                          state: _state.text.trim().isEmpty ? null : _state.text.trim(),
                          country: 'BR',
                          radiusKm: _radius,
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C27A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Adicionar'),
            ),
          ),
        ],
      ),
    );
  }
}
