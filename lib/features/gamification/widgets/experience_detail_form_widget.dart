import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'month_year_picker_sheet.dart';
import '../../../core/theme/theme.dart';

/// D1 form: org name, role, start/end dates, city.
/// [categoryCode] is used for contextual placeholder hints.
class ExperienceDetailFormWidget extends StatefulWidget {
  final Function(String) onSelect;
  final String categoryCode;
  final String? initialValue;

  const ExperienceDetailFormWidget({
    super.key,
    required this.onSelect,
    required this.categoryCode,
    this.initialValue,
  });

  @override
  State<ExperienceDetailFormWidget> createState() =>
      _ExperienceDetailFormWidgetState();
}

class _ExperienceDetailFormWidgetState
    extends State<ExperienceDetailFormWidget> {
  final _orgController = TextEditingController();
  final _roleController = TextEditingController();
  final _cityController = TextEditingController();
  DateTime _startDate = DateTime(DateTime.now().year - 1, 3);
  DateTime? _endDate;
  bool _ongoing = false;

  static const _orgLabels = {
    'stage': 'EMPRESA / ORGANIZAÇÃO',
    'emp':   'EMPRESA / ORGANIZAÇÃO',
    'free':  'PROJETO / CLIENTE',
    'proj':  'NOME DO PROJETO',
    'lead':  'ENTIDADE / LIGA / ATLÉTICA',
    'vol':   'ORGANIZAÇÃO / ONG',
    'res':   'LABORATÓRIO / PROGRAMA',
    'spo':   'TIME / CLUBE / SELEÇÃO',
  };

  static const _roleLabels = {
    'stage': 'SEU CARGO / FUNÇÃO',
    'emp':   'SEU CARGO / FUNÇÃO',
    'free':  'SEU PAPEL NO PROJETO',
    'proj':  'SEU PAPEL / FUNÇÃO',
    'lead':  'SEU CARGO NA ENTIDADE',
    'vol':   'SEU PAPEL / FUNÇÃO',
    'res':   'SEU PAPEL NA PESQUISA',
    'spo':   'SEU PAPEL / POSIÇÃO',
  };

  static const _orgHints = {
    'stage': 'Ex: Bradesco, StartupXYZ, Governo SP...',
    'emp': 'Ex: Magazine Luiza, Shopify, Prefeitura...',
    'free': 'Ex: Projeto próprio / clientes diversos',
    'proj': 'Ex: App de finanças pessoais, Site de portfolio...',
    'lead': 'Ex: Atlética de Direito USP, CA de Engenharia...',
    'vol': 'Ex: ONG Aldeias Infantis, Graacc, AACD...',
    'res': 'Ex: Lab de Neurociência UNIFESP, PIBIC...',
    'spo': 'Ex: Seleção Paulista de Basquete, Clube Hebraica...',
  };

  static const _roleHints = {
    'stage': 'Ex: Estagiário de Produto, Analista de Dados Jr...',
    'emp': 'Ex: Analista de Marketing, Desenvolvedor Full Stack...',
    'free': 'Ex: Designer freelancer, Consultor de growth...',
    'proj': 'Ex: Fundador, Desenvolvedor principal...',
    'lead': 'Ex: Presidente, Diretor Financeiro, Coordenador...',
    'vol': 'Ex: Voluntário de captação, Mentor de alunos...',
    'res': 'Ex: Pesquisador de Iniciação Científica, Bolsista...',
    'spo': 'Ex: Atleta profissional, Capitão do time...',
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final data = jsonDecode(widget.initialValue!);
        _orgController.text = data['org'] ?? '';
        _roleController.text = data['role'] ?? '';
        _cityController.text = data['city'] ?? '';
        _ongoing = data['ongoing'] == true;
        if (data['start'] != null) _startDate = _parseDate(data['start']);
        if (data['end'] != null) _endDate = _parseDate(data['end']);
      } catch (_) {}
    }
    _orgController.addListener(_emitIfValid);
    _roleController.addListener(_emitIfValid);
    _cityController.addListener(_emitIfValid);
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitIfValid());
  }

  @override
  void dispose() {
    _orgController.dispose();
    _roleController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  DateTime _parseDate(String s) {
    try {
      final parts = s.split('/');
      return DateTime(int.parse(parts[1]), int.parse(parts[0]));
    } catch (_) {
      return DateTime.now();
    }
  }

  String _formatDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool get _isValid =>
      _orgController.text.trim().length >= 2 &&
      _roleController.text.trim().length >= 2 &&
      (_ongoing || _endDate != null);

  void _emitIfValid() {
    if (!_isValid) return;
    widget.onSelect(jsonEncode({
      'org': _orgController.text.trim(),
      'role': _roleController.text.trim(),
      'start': _formatDate(_startDate),
      'end': _ongoing ? null : (_endDate != null ? _formatDate(_endDate!) : null),
      'ongoing': _ongoing,
      'city': _cityController.text.trim(),
    }));
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showMonthYearPickerSheet(
      context: context,
      initialDate: isStart ? _startDate : (_endDate ?? DateTime.now()),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
      _emitIfValid();
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgHint = _orgHints[widget.categoryCode] ?? 'Nome da organização';
    final roleHint = _roleHints[widget.categoryCode] ?? 'Seu cargo ou função';
    final orgLabel = _orgLabels[widget.categoryCode] ?? 'ORGANIZAÇÃO / EMPRESA';
    final roleLabel = _roleLabels[widget.categoryCode] ?? 'SEU CARGO / FUNÇÃO';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Organization field
        _fieldLabel(orgLabel),
        const SizedBox(height: 8),
        _textField(
          controller: _orgController,
          hint: orgHint,
          icon: Icons.business_outlined,
        ),

        const SizedBox(height: 20),

        // Role field
        _fieldLabel(roleLabel),
        const SizedBox(height: 8),
        _textField(
          controller: _roleController,
          hint: roleHint,
          icon: Icons.work_outline,
        ),

        const SizedBox(height: 20),

        // Dates
        _fieldLabel('PERÍODO'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _dateCard('INÍCIO', _startDate, true)),
          const SizedBox(width: 12),
          if (!_ongoing)
            Expanded(
              child: _dateCard(
                'FIM',
                _endDate ?? DateTime.now(),
                false,
                isEmpty: _endDate == null,
              ),
            )
          else
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.successSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.success, width: 2),
                ),
                child: const Column(
                  children: [
                    Text('ATÉ HOJE',
                        style: TextStyle(
                            color: AppColors.textDisabled,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text('Em andamento',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success)),
                  ],
                ),
              ),
            ),
        ]),
        const SizedBox(height: 10),

        // "Ainda em andamento" toggle
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _ongoing = !_ongoing);
            _emitIfValid();
          },
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _ongoing ? AppColors.success : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _ongoing
                        ? AppColors.success
                        : AppColors.borderStrong,
                    width: 2,
                  ),
                ),
                child: _ongoing
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              const Text(
                'Ainda em andamento',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // City (optional)
        _fieldLabel('CIDADE (opcional)'),
        const SizedBox(height: 8),
        _textField(
          controller: _cityController,
          hint: 'Ex: São Paulo, Remoto...',
          icon: Icons.location_on_outlined,
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.borderStrong, fontSize: 14),
          prefixIcon: Icon(icon, color: AppColors.success, size: 20),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }

  Widget _dateCard(String label, DateTime date, bool isStart,
      {bool isEmpty = false}) {
    return GestureDetector(
      onTap: () => _pickDate(isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isEmpty ? AppColors.border : AppColors.border,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              isEmpty ? 'Selecionar' : _formatDate(date),
              style: TextStyle(
                fontSize: isEmpty ? 13 : 18,
                fontWeight: FontWeight.bold,
                color: isEmpty
                    ? AppColors.borderStrong
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Icon(Icons.calendar_today, color: AppColors.success, size: 16),
          ],
        ),
      ),
    );
  }
}
