// AgeRangeScreen — pergunta data de nascimento.
//
// Captura DD/MM/AAAA via input formatado. Persiste a data exata em
// `date_of_birth` e deriva `age_range` automaticamente pra manter
// compatibilidade com filtros agregados existentes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/extraction_status_view_model.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../all_set_screen.dart';
import '../onboarding_scaffold.dart';
import '../preferences/desired_titles_screen.dart';

class AgeRangeScreen extends StatefulWidget {
  const AgeRangeScreen({super.key});
  @override
  State<AgeRangeScreen> createState() => _AgeRangeScreenState();
}

class _AgeRangeScreenState extends State<AgeRangeScreen> {
  final _controller = TextEditingController();
  DateTime? _parsed;
  String? _error;

  @override
  void initState() {
    super.initState();
    final dob = context.read<ProfileEditorViewModel>().personal?.dateOfBirth;
    if (dob != null) {
      _controller.text = _formatDob(dob);
      _parsed = dob;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _formatDob(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  void _onChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) {
      setState(() {
        _parsed = null;
        _error = null;
      });
      return;
    }
    final day = int.tryParse(digits.substring(0, 2));
    final month = int.tryParse(digits.substring(2, 4));
    final year = int.tryParse(digits.substring(4, 8));
    if (day == null || month == null || year == null) {
      setState(() {
        _parsed = null;
        _error = 'Data inválida';
      });
      return;
    }

    // DateTime aceita day/month fora do intervalo e "rola" pra próximo
    // mês — usamos isso pra detectar valores impossíveis (31/02 vira 03/03).
    final candidate = DateTime(year, month, day);
    if (candidate.day != day || candidate.month != month || candidate.year != year) {
      setState(() {
        _parsed = null;
        _error = 'Data inválida';
      });
      return;
    }

    final now = DateTime.now();
    if (candidate.isAfter(now)) {
      setState(() {
        _parsed = null;
        _error = 'Data no futuro';
      });
      return;
    }
    final age = ageRangeFromDate(candidate, now: now);
    if (age == null || year < 1900) {
      setState(() {
        _parsed = null;
        _error = 'Ano inválido';
      });
      return;
    }

    setState(() {
      _parsed = candidate;
      _error = null;
    });
  }

  Future<void> _continue() async {
    final dob = _parsed;
    if (dob == null) return;
    HapticFeedback.lightImpact();
    AnalyticsService.shared.track('onboarding_masking_question_answered',
        props: {'question': 'date_of_birth'});

    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    final derived = ageRangeFromDate(dob);
    await vm.commitPersonal(base.copyWith(
      dateOfBirth: dob,
      ageRange: derived,
    ));
    if (!mounted) return;

    // Bifurca conforme origem:
    //  - Upload (extração rodou) → AllSetScreen → revisar dados do CV
    //  - Trail (sem CV) → pula AllSetScreen e a revisão (não há nada extraído
    //    pra revisar), vai direto pras preferências de vaga.
    final extraction = context.read<ExtractionStatusViewModel>();
    final cameFromUpload = extraction.status != ExtractionStatus.notStarted;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => cameFromUpload
            ? const AllSetScreen()
            : const DesiredTitlesScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual sua data de nascimento?',
      subtitle: 'Algumas vagas pedem idade mínima.',
      progress: 0.5,
      onContinue: _parsed == null ? null : _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [_DateFormatter()],
            onChanged: _onChanged,
            autofocus: true,
            style: const TextStyle(fontSize: 18, letterSpacing: 1),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'DD/MM/AAAA',
              hintStyle: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 18,
                letterSpacing: 1,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _error != null
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _error != null
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _error != null
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF29B6D2),
                  width: 1.5,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _DateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buf = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(limited[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
