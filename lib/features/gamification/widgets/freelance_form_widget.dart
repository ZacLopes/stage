import 'dart:convert';
import 'package:flutter/material.dart';
import 'month_year_picker_sheet.dart';
import '../../../core/theme/theme.dart';

class FreelanceFormWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final String? initialValue;

  const FreelanceFormWidget({
    super.key,
    required this.onSave,
    this.initialValue,
  });

  @override
  State<FreelanceFormWidget> createState() => _FreelanceFormWidgetState();
}

class _FreelanceFormWidgetState extends State<FreelanceFormWidget> {
  final _roleController = TextEditingController(); // Papel (ex: Tradutor)
  final _scopeController = TextEditingController(); // O que fazia
  final _metricsController = TextEditingController();
  
  String? _frequency; // Ocasionalmente, Frequentemente, Sempre
  
  String? _startDate;
  String? _endDate;
  bool _isOngoing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final dynamic decoded = jsonDecode(widget.initialValue!);
        if (decoded is Map<String, dynamic>) {
          _roleController.text = decoded['role'] ?? '';
          _frequency = decoded['frequency'];
          _scopeController.text = decoded['description'] ?? '';
          _metricsController.text = decoded['metrics'] ?? decoded['quantitative_results'] ?? '';
          _startDate = decoded['startDate'];
          _endDate = decoded['endDate'];
          _isOngoing = decoded['isOngoing'] == true;
        }
      } catch (_) {}
    }
  }
  
  void _emit() {
    // Validation: Check if all required fields are filled
    bool isValid = _roleController.text.isNotEmpty &&
                   _frequency != null &&
                   _scopeController.text.isNotEmpty &&
                   _startDate != null &&
                   (_isOngoing || _endDate != null);

    if (isValid) {
      final data = {
        "role": _roleController.text,
        "frequency": _frequency,
        "description": _scopeController.text, // Key must match QuestionScreen expectation
        "metrics": _metricsController.text,
        "startDate": _startDate,
        "endDate": _isOngoing ? "Atualmente" : _endDate,
        "isOngoing": _isOngoing,
        "type": "freelance"
      };
      widget.onSave(data);
    } else {
      // Send empty map to indicate invalid/clear state
      widget.onSave({});
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    DateTime initialDate = now;
    DateTime? firstDate;
    
    // Determine initial date based on current value
    String? currentValue = isStart ? _startDate : _endDate;
    if (currentValue != null && currentValue != "Atualmente") {
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
        if (isStart) {
          _startDate = formatted;
          
          if (_endDate != null) {
             try {
               final startParts = formatted.split('/');
               final startDt = DateTime(int.parse(startParts[1]), int.parse(startParts[0]));
               
               final endParts = _endDate!.split('/');
               final endDt = DateTime(int.parse(endParts[1]), int.parse(endParts[0]));
               
               if (endDt.isBefore(startDt)) {
                 _endDate = null;
               }
             } catch (_) {}
          }
        } else {
          _endDate = formatted;
        }
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
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.handshake, color: Colors.orange, size: 32),
            ),
          ),
          const SizedBox(height: 24),

          _buildTextField(_roleController, 'Qual era o seu papel?', Icons.design_services, helper: 'Ex: Designer Gráfico, Redator...'),

          const SizedBox(height: 24),
          const Text('Com que frequência você pegava projetos?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
          const SizedBox(height: 12),
          _buildFrequencySelector(),

          const SizedBox(height: 24),
          const Text('O que você fazia?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
          const SizedBox(height: 8),
          _buildTextField(_scopeController, 'Descreva os projetos...', Icons.list_alt, maxLines: 3),

          const SizedBox(height: 24),
          const Text('Resultados e Números (Opcional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
          const SizedBox(height: 8),
          _buildTextField(
            _metricsController, 
            'Entregas quantitativas', 
            Icons.data_usage, 
            maxLines: 2, 
            helper: 'Ex: "10 sites publicados", "5 clientes fixos", "Nota 5.0 no Workana".'
          ),

          const SizedBox(height: 24),
          const Text('Quando isso aconteceu?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: _buildDateSelector('Início', _startDate, () => _pickDate(true)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _isOngoing 
                  ? Container(
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: const Text('Atualmente', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    )
                  : _buildDateSelector('Fim', _endDate, () => _pickDate(false)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                _isOngoing = !_isOngoing;
                if (_isOngoing) _endDate = null;
                _emit();
              });
            },
            child: Row(
              children: [
                Icon(
                  _isOngoing ? Icons.check_box : Icons.check_box_outline_blank,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                const Text('Ainda faço projetos assim', style: TextStyle(fontSize: 16)),
              ],
            ),
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
        prefixIcon: Icon(icon, color: AppColors.textDisabled),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.orange, width: 2), borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildFrequencySelector() {
    return Column(
      children: [
        _buildFreqOption('Ocasionalmente', '1 ou 2 vezes, bicos esporádicos'),
        const SizedBox(height: 8),
        _buildFreqOption('Frequentemente', 'Tinha clientes recorrentes'),
        const SizedBox(height: 8),
        _buildFreqOption('Sempre / Constantemente', 'Era minha atividade principal'),
      ],
    );
  }

  Widget _buildFreqOption(String title, String subtitle) {
    final bool isSelected = _frequency == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          _frequency = title;
          _emit();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.orange : AppColors.border, width: 2),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? Colors.orange : AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.orange[800] : AppColors.textSecondary)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector(String label, String? value, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
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
                const Icon(Icons.calendar_today, size: 16, color: Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
