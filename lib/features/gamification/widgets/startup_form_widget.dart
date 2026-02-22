import 'package:flutter/material.dart';
import 'month_year_picker_sheet.dart';

class StartupFormWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final String? initialValue;

  const StartupFormWidget({
    super.key,
    required this.onSave,
    this.initialValue,
  });

  @override
  State<StartupFormWidget> createState() => _StartupFormWidgetState();
}

class _StartupFormWidgetState extends State<StartupFormWidget> {
  final _ventureNameController = TextEditingController();
  final _roleController = TextEditingController(); // Co-founder, CTO...
  final _problemController = TextEditingController();
  final _milestonesController = TextEditingController(); // MVP, Sales...
  final _metricsController = TextEditingController(); // Traction
  
  // Tags/Badges for role could be cool later, simple text for now.
  
  String? _startDate;
  String? _endDate;
  bool _isCurrent = false;

  void _emit() {
    final data = {
      "company": _ventureNameController.text,
      "role": _roleController.text,
      "problem_solved": _problemController.text,
      "milestones": _milestonesController.text,
      "metrics": _metricsController.text,
      "start_date": _startDate,
      "end_date": _isCurrent ? "Atual" : _endDate,
      "type": "startup"
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
          // Header visual? using Rocket icon
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.rocket_launch, color: Colors.purple, size: 32),
            ),
          ),
          const SizedBox(height: 16),

          _buildTextField(_ventureNameController, 'Nome da Startup / Venture', Icons.rocket_launch_outlined),
          const SizedBox(height: 16),
          _buildTextField(_roleController, 'Seu Papel (ex: Co-founder, CTO)', Icons.badge_outlined),
          const SizedBox(height: 16),
          
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
                activeColor: Colors.purple,
                onChanged: (val) {
                  setState(() {
                    _isCurrent = val ?? false;
                    if (_isCurrent) _endDate = null;
                    _emit();
                  });
                },
              ),
              const Text('Ainda estou no projeto?'),
            ],
          ),

          const Divider(height: 32),
          
          const Text('A Dor do Mercado', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
          const SizedBox(height: 8),
          _buildTextField(_problemController, 'Qual problema vocês resolviam?', Icons.lightbulb_outline, maxLines: 3, helper: 'Descreva a oportunidade que vocês atacaram.'),
          
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          const Text('Grandes Marcos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
          const SizedBox(height: 8),
          _buildTextField(_milestonesController, 'O que vocês construíram?', Icons.flag_outlined, maxLines: 3, helper: 'MVP, Primeiros Clientes, Pivotagem...'),
          
          const SizedBox(height: 16),
          const Text('Métricas de Tração (Opcional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
          const SizedBox(height: 8),
          _buildTextField(
            _metricsController, 
            'Números que provam sucesso', 
            Icons.trending_up, 
            maxLines: 2, 
            helper: 'Ex: "10k usuários ativos", "R\$ 200k investidos", "Crescimento de 15% WoW".'
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
        prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.purple, width: 2), borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildDateSelector(String label, String? value, VoidCallback? onTap, {bool isDisabled = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: isDisabled ? const Color(0xFFF3F4F6) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(value ?? 'MM/AAAA', style: TextStyle(fontWeight: FontWeight.bold, color: value != null ? Colors.black87 : const Color(0xFFAFAFAF))),
                Icon(Icons.calendar_today, size: 16, color: isDisabled ? const Color(0xFFAFAFAF) : Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
