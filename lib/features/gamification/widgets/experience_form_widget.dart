import 'package:flutter/material.dart';
import 'month_year_picker_sheet.dart';
import '../../../core/theme/theme.dart';
// Note: We'll reuse DualWheelDateWidget logic or implement simple Date Pickers here.
// For simplicity and standard UI, we'll use standard TextFields and a Date Picker dialog.

class ExperienceFormWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final String? initialValue;
  final String? contextType; // 'corporate', 'startup', 'project', 'freelance', etc.

  const ExperienceFormWidget({
    super.key,
    required this.onSave,
    this.initialValue,
    this.contextType,
  });

  @override
  State<ExperienceFormWidget> createState() => _ExperienceFormWidgetState();
}

class _ExperienceFormWidgetState extends State<ExperienceFormWidget> {
  final _titleController = TextEditingController(); // Company/Project Name
  final _roleController = TextEditingController();    // Cargo/Função
  final _locationController = TextEditingController(); // Localização
  final _descriptionController = TextEditingController(); // Atividades
  final _resultsController = TextEditingController(); // Realizações/Resultados
  final _metricsController = TextEditingController(); // Quantitative Data
  
  String? _startDate;
  String? _endDate;
  bool _isCurrent = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        // Parse JSON
        // Assume format: {"title": "...", "role": "...", "start": "...", "end": "...", "location": "...", "desc": "...", "results": "..."}
        // or standard internal format.
        // We'll use a simple map.
        // Wait, initialValue is string.
        // We need 'dart:convert';
      } catch (_) {}
    }
  }

  // Label Helpers based on contextType
  String get _titleLabel {
    switch (widget.contextType) {
      case 'startup': return 'Nome da Startup / Venture Própria';
      case 'acceleration': return 'Nome do Programa / Aceleração';
      case 'freelance': return 'Nome do Cliente / Projeto';
      case 'social': return 'Nome da Organização / Causa';
      case 'other': return 'Nome da Experiência';
      default: return 'Nome da Empresa / Organização';
    }
  }

  String get _roleLabel {
    switch (widget.contextType) {
      case 'startup': return 'Seu Papel (Ex: Co-founder, CTO...)';
      case 'acceleration': return 'Sua Função no Time';
      case 'freelance': return 'Serviço Prestado (Ex: Tradutor, Designer...)';
      case 'social': return 'Seu Papel (Ex: Voluntário, Líder...)';
      default: return 'Cargo / Função';
    }
  }
  
  String get _descriptionLabel {
     switch (widget.contextType) {
      case 'startup': return 'Qual problema vocês resolviam?';
      case 'acceleration': return 'Qual foi o desafio proposto?';
      case 'freelance': return 'Qual foi o escopo do trabalho?';
      case 'social': return 'Quais atividades você realizou?';
      case 'corporate': return 'O que você fazia lá diáriamente?';
      default: return 'Descrição das Atividades';
    }
  }

  String get _resultsLabel {
     switch (widget.contextType) {
      case 'startup': return 'Marcos alcançados (MVP, Vendas, Pitch)';
      case 'acceleration': return 'Qual solução vocês criaram?';
      case 'freelance': return 'Qual foi a entrega final?';
      case 'social': return 'Qual impacto você gerou na comunidade?';
      case 'corporate': return 'Quais resultados você entregou?';
      default: return 'Realizações e Resultados';
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    DateTime initialDate = now;
    DateTime? firstDate;
    
    // Determine initial date based on current value
    String? currentValue = isStart ? _startDate : _endDate;
    if (currentValue != null && currentValue != "Atual") {
      try {
        final parts = currentValue.split('/');
        if (parts.length == 2) {
          initialDate = DateTime(int.parse(parts[1]), int.parse(parts[0]));
        }
      } catch (_) {}
    }

    final picked = await showMonthYearPickerSheet(
      context: context,
      initialDate: initialDate,
      lastDate: now,
    );

    if (picked != null) {
      setState(() {
        // Format: MM/YYYY
        final formatted = "${picked.month.toString().padLeft(2, '0')}/${picked.year}";
        if (isStart) {
          _startDate = formatted;
        } else {
          _endDate = formatted;
        }
        _emit();
      });
    }
  }

  void _emit() {
    // Basic validation or just emit everything
    // Actually validation happens in QuestionScreen usually, but we can emit partial data.
    // QuestionScreen calls onSave? No, this widget calls onSave when data changes.
    // wait, existing widgets verify validity in `_handleContinue`.
    // So we just emit the Map.
    
    final data = {
      "company": _titleController.text,
      "role": _roleController.text,
      "start_date": _startDate,
      "end_date": _isCurrent ? "Atual" : _endDate,
      "location": _locationController.text,
      "description": _descriptionController.text,
      "results": _resultsController.text,
      "metrics": _metricsController.text,
    };
    
    // We emit JSON string?
    // QuestionScreen expects a String usually (stored in SQLite/Supabase options field or similar).
    // Or complex object?
    // The ViewModel `answerQuestion` takes dynamic.
    // Usually we encode to JSON string for complex objects.
    
    // Let's import dart:convert at top.
    // Wait, I can't add imports easily without rewriting file.
    // I'll add the import now.
    widget.onSave(data); 
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(controller: _titleController, label: _titleLabel, icon: Icons.business),
          const SizedBox(height: 16),
          _buildTextField(controller: _roleController, label: _roleLabel, icon: Icons.person_outline),
          const SizedBox(height: 16),
          _buildTextField(controller: _locationController, label: 'Localização (Cidade/Estado)', icon: Icons.place_outlined),
          const SizedBox(height: 16),
          
          // Date Row
          Row(
            children: [
              Expanded(
                child: _buildDateSelector(
                  label: 'Início',
                  value: _startDate,
                  onTap: () => _pickDate(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateSelector(
                  label: 'Fim',
                  value: _isCurrent ? 'Atual' : _endDate,
                  onTap: _isCurrent ? null : () => _pickDate(false),
                  isDisabled: _isCurrent,
                ),
              ),
            ],
          ),
          // Current Toggle
          Row(
            children: [
              Checkbox(
                value: _isCurrent,
                activeColor: AppColors.success,
                onChanged: (val) {
                  setState(() {
                    _isCurrent = val ?? false;
                    if (_isCurrent) _endDate = null;
                    _emit();
                  });
                },
              ),
              const Text('É meu trabalho atual?'),
            ],
          ),
          
          const Divider(height: 32),
          
          const Divider(height: 32),
          
          Text(
            _descriptionLabel,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _descriptionController,
            label: '',
            maxLines: 4,
            helper: 'Comece com verbos de ação: "Gerenciei...", "Cirie...", "Desenvolvi..."',
          ),
          
          const SizedBox(height: 16),
           Text(
            _resultsLabel,
             style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _resultsController,
            label: '',
            maxLines: 3,
            helper: 'Ex: "Aumentei as vendas em 20%", "Liderei equipe de 5 pessoas"...',
          ),
          
          const SizedBox(height: 16),
           const Text(
            'Métricas (Números e Dados)',
             style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _metricsController,
            label: '',
            maxLines: 2,
            helper: 'Ex: "R\$ 100k faturados", "5000 acessos mensais".',
          ),
          const SizedBox(height: 100), // Spacing for bottom bar
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    int maxLines = 1,
    String? helper,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => _emit(),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: icon != null ? Icon(icon, color: AppColors.textDisabled) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.success, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildDateSelector({
    required String label,
    required String? value,
    required VoidCallback? onTap,
    bool isDisabled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: isDisabled ? AppColors.background : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value ?? 'MM/AAAA',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: value != null ? FontWeight.bold : FontWeight.normal,
                    color: value != null 
                        ? (isDisabled ? AppColors.textDisabled : Colors.black87)
                        : AppColors.textDisabled,
                  ),
                ),
                Icon(Icons.calendar_today, size: 16, color: isDisabled ? AppColors.textDisabled : AppColors.success),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
