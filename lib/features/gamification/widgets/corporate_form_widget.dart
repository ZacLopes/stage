import 'package:flutter/material.dart';
import 'month_year_picker_sheet.dart';
import '../../../core/theme/theme.dart';

class CorporateFormWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final String? initialValue;

  const CorporateFormWidget({
    super.key,
    required this.onSave,
    this.initialValue,
  });

  @override
  State<CorporateFormWidget> createState() => _CorporateFormWidgetState();
}

class _CorporateFormWidgetState extends State<CorporateFormWidget> {
  final _companyController = TextEditingController();
  final _roleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _resultsController = TextEditingController();
  final _metricsController = TextEditingController();
  
  String? _startDate;
  String? _endDate;
  bool _isCurrent = false;

  @override
  void initState() {
    super.initState();
    // TODO: Parse initialValue JSON if needed
  }

  void _emit() {
    final data = {
      "company": _companyController.text,
      "role": _roleController.text,
      // "role": _roleController.text, // Removed
      // "location": _locationController.text, // Removed
      "start_date": _startDate,
      "end_date": _isCurrent ? "Atual" : _endDate,
      "description": _descriptionController.text,
      "results": _resultsController.text,
      "metrics": _metricsController.text, // New quantitative field
      "type": "corporate"
    };
    widget.onSave(data);
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
        if (parts.length == 3) {
          // Format was dd/MM/yyyy
          initialDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        } else if (parts.length == 2) {
          // Format is MM/yyyy
          initialDate = DateTime(int.parse(parts[1]), int.parse(parts[0]));
        }
      } catch (_) {}
    }

    // If picking End Date, enforce firstDate >= StartDate
    if (!isStart && _startDate != null) {
      try {
        final parts = _startDate!.split('/');
        if (parts.length == 3) {
          firstDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        } else if (parts.length == 2) {
          firstDate = DateTime(int.parse(parts[1]), int.parse(parts[0]));
        }
        
        if (initialDate.isBefore(firstDate!)) {
           initialDate = firstDate!;
        }
      } catch (_) {}
    }

    final picked = await showMonthYearPickerSheet(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: now,
    );

    if (picked != null) {
      setState(() {
        // Save as MM/yyyy
        final formatted = "${picked.month.toString().padLeft(2, '0')}/${picked.year}";
        if (isStart) _startDate = formatted;
        else _endDate = formatted;
        _emit();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(_companyController, 'Nome da Empresa', Icons.business),
          const SizedBox(height: 16),
          // Role field removed as per request
          
          Row(
            children: [
              Expanded(child: _buildDateSelector('Início', _startDate, () => _pickDate(true))),
              const SizedBox(width: 12),
              Expanded(child: _buildDateSelector('Fim', _isCurrent ? 'Atual' : _endDate, _isCurrent ? null : () => _pickDate(false), isDisabled: _isCurrent)),
            ],
          ),
          
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
              const Text('Trabalho atual?'),
            ],
          ),

          const Divider(height: 32),
          
          const Text('Atividades do dia a dia', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _buildTextField(_descriptionController, 'O que você fazia lá?', Icons.description, maxLines: 4, helper: 'Comece com verbos: "Gerenciei", "Liderei"...'),
          
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          const Text('Resultados Entregues', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _buildTextField(_resultsController, 'Qual impacto você gerou?', Icons.emoji_events_outlined, maxLines: 3, helper: 'Ex: "Liderei projeto de migração", "Aumentei retenção"...'),

          const SizedBox(height: 16),
          const Text('Números e Dados (Opcional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _buildTextField(
            _metricsController, 
            'Quantifique seus resultados', 
            Icons.analytics_outlined, 
            maxLines: 2, 
            helper: 'Ex: "+20% vendas", "R\$ 500k faturados", "50 novos clientes".\nNúmeros chamam atenção no currículo!'
          ),
          
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, {int maxLines = 1, String? helper}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      onChanged: (_) => _emit(),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: Icon(icon, color: AppColors.textDisabled),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildDateSelector(String label, String? value, VoidCallback? onTap, {bool isDisabled = false}) {
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
                Text(value ?? 'MM/AAAA', style: TextStyle(fontWeight: FontWeight.bold, color: value != null ? Colors.black87 : AppColors.textDisabled)),
                Icon(Icons.calendar_today, size: 16, color: isDisabled ? AppColors.textDisabled : AppColors.success),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
