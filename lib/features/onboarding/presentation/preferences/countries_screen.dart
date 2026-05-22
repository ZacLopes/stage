// CountriesScreen — Brasil default + work auth status por país.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'location_screen.dart';

const _commonCountries = [
  ('BR', 'Brasil'),
  ('US', 'Estados Unidos'),
  ('PT', 'Portugal'),
  ('CA', 'Canadá'),
  ('UK', 'Reino Unido'),
  ('DE', 'Alemanha'),
  ('IE', 'Irlanda'),
  ('ES', 'Espanha'),
];

class CountriesScreen extends StatefulWidget {
  const CountriesScreen({super.key});
  @override
  State<CountriesScreen> createState() => _CountriesScreenState();
}

class _CountriesScreenState extends State<CountriesScreen> {
  final List<ApplicationCountry> _countries = [];

  @override
  void initState() {
    super.initState();
    final vm = context.read<PreferencesViewModel>();
    if (vm.countries.isNotEmpty) {
      _countries.addAll(vm.countries);
    } else {
      // Brasil default
      _countries.add(ApplicationCountry(
        id: '',
        userId: Supabase.instance.client.auth.currentUser?.id ?? '',
        countryCode: 'BR',
        workAuth: WorkAuth.citizen,
      ));
    }
  }

  Future<void> _addCountry() async {
    final result = await showModalBottomSheet<ApplicationCountry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddCountrySheet(
        existingCodes: _countries.map((c) => c.countryCode).toSet(),
      ),
    );
    if (result != null) {
      setState(() => _countries.add(result));
    }
  }

  void _continue() async {
    AnalyticsService.shared.track('onboarding_preferences_countries_completed');
    await context.read<PreferencesViewModel>().replaceApplicationCountries(_countries);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LocationScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Em quais países pretende aplicar?',
      progress: 0.82,
      onContinue: _continue,
      child: Column(
        children: [
          ..._countries.map((c) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_countryLabel(c.countryCode), style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (c.workAuth != null)
                            Text(_workAuthLabel(c.workAuth!), style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                        ],
                      ),
                    ),
                    if (_countries.length > 1)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _countries.remove(c)),
                      ),
                  ],
                ),
              )),
          OutlinedButton.icon(
            icon: const Icon(Icons.add, color: Color(0xFF00C27A)),
            label: const Text('Adicionar país', style: TextStyle(color: Color(0xFF00C27A))),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF00C27A)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _addCountry,
          ),
        ],
      ),
    );
  }

  String _countryLabel(String code) {
    return _commonCountries.firstWhere(
      (t) => t.$1 == code,
      orElse: () => (code, code),
    ).$2;
  }

  String _workAuthLabel(WorkAuth a) {
    switch (a) {
      case WorkAuth.citizen: return 'Cidadão';
      case WorkAuth.authorized: return 'Tenho permissão de trabalho';
      case WorkAuth.sponsorshipNeeded: return 'Preciso de patrocínio';
    }
  }
}

class _AddCountrySheet extends StatefulWidget {
  final Set<String> existingCodes;
  const _AddCountrySheet({required this.existingCodes});
  @override
  State<_AddCountrySheet> createState() => _AddCountrySheetState();
}

class _AddCountrySheetState extends State<_AddCountrySheet> {
  String? _selectedCode;
  WorkAuth? _selectedAuth;

  @override
  Widget build(BuildContext context) {
    final available = _commonCountries.where((c) => !widget.existingCodes.contains(c.$1)).toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Selecione o país', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedCode,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: available.map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2))).toList(),
            onChanged: (v) => setState(() => _selectedCode = v),
          ),
          const SizedBox(height: 16),
          const Text('Sua situação no país', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          RadioListTile<WorkAuth>(
            title: const Text('Cidadão'),
            value: WorkAuth.citizen,
            groupValue: _selectedAuth,
            activeColor: const Color(0xFF00C27A),
            onChanged: (v) => setState(() => _selectedAuth = v),
          ),
          RadioListTile<WorkAuth>(
            title: const Text('Tenho permissão de trabalho'),
            value: WorkAuth.authorized,
            groupValue: _selectedAuth,
            activeColor: const Color(0xFF00C27A),
            onChanged: (v) => setState(() => _selectedAuth = v),
          ),
          RadioListTile<WorkAuth>(
            title: const Text('Preciso de patrocínio'),
            value: WorkAuth.sponsorshipNeeded,
            groupValue: _selectedAuth,
            activeColor: const Color(0xFF00C27A),
            onChanged: (v) => setState(() => _selectedAuth = v),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48, width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedCode == null || _selectedAuth == null)
                  ? null
                  : () {
                      Navigator.pop(
                        context,
                        ApplicationCountry(
                          id: '',
                          userId: Supabase.instance.client.auth.currentUser?.id ?? '',
                          countryCode: _selectedCode!,
                          workAuth: _selectedAuth,
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C27A),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFD1D5DB),
              ),
              child: const Text('Adicionar'),
            ),
          ),
        ],
      ),
    );
  }
}
