import 'package:flutter/material.dart';
import 'month_year_picker_sheet.dart';

class SocialFormWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final String? initialValue;

  const SocialFormWidget({
    super.key,
    required this.onSave,
    this.initialValue,
  });

  @override
  State<SocialFormWidget> createState() => _SocialFormWidgetState();
}

class _SocialFormWidgetState extends State<SocialFormWidget> {
  final _orgController = TextEditingController();
  final _roleController = TextEditingController(); // Voluntário...
  final _activitiesController = TextEditingController();
  final _impactController = TextEditingController();
  final _metricsController = TextEditingController();
  
  String? _startDate;
  String? _endDate;
  bool _isCurrent = false;

  void _emit() {
    // Validation: Check if all required fields are filled
    bool isValid = _orgController.text.isNotEmpty &&
                   _roleController.text.isNotEmpty &&
                   _activitiesController.text.isNotEmpty &&
                   _impactController.text.isNotEmpty && // Now required
                   _startDate != null &&
                   (_isCurrent || _endDate != null);

    if (isValid) {
      final data = {
        "company": _orgController.text,
        "role": _roleController.text,
        "description": _activitiesController.text,
        "results": _impactController.text,
        "metrics": _metricsController.text,
        "start_date": _startDate,
        "end_date": _isCurrent ? "Atual" : _endDate,
        "type": "social"
      };
      widget.onSave(data);
    } else {
       widget.onSave({});
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
          // If start date changed, validate existing end date
          if (_endDate != null) {
             try {
                final sParts = formatted.split('/');
                final sDt = DateTime(int.parse(sParts[1]), int.parse(sParts[0]));
                
                final eParts = _endDate!.split('/');
                final eDt = DateTime(int.parse(eParts[1]), int.parse(eParts[0]));
                
                if (eDt.isBefore(sDt)) {
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
              decoration: BoxDecoration(color: Colors.pink.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.volunteer_activism, color: Colors.pink, size: 32),
            ),
          ),
          const SizedBox(height: 16),

          _buildTextField(_orgController, 'Nome da ONG / Organização', Icons.group),
          const SizedBox(height: 16),
          _buildTextField(_roleController, 'Seu Papel (ex: Voluntário)', Icons.person),
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
                activeColor: Colors.pink,
                onChanged: (val) {
                  setState(() {
                    _isCurrent = val ?? false;
                    if (_isCurrent) _endDate = null;
                    _emit();
                  });
                },
              ),
              const Text('Ainda participo?'),
            ],
          ),

          const Divider(height: 32),
          
          const Text('Mão na Massa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.pink)),
          const SizedBox(height: 8),
          _buildTextField(_activitiesController, 'Quais atividades você realizou?', Icons.handyman_outlined, maxLines: 3),
          
          const SizedBox(height: 16),
          const Text('Impacto Social', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.pink)),
          const SizedBox(height: 8),
          _buildTextField(_impactController, 'Quem você ajudou?', Icons.favorite_border, maxLines: 3, helper: 'Comunidade impactada, transformação gerada...'),

          const SizedBox(height: 16),
          const Text('Dados do Impacto (Opcional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.pink)),
          const SizedBox(height: 8),
          _buildTextField(
            _metricsController, 
            'Números do impacto', 
            Icons.people_outline, 
            maxLines: 2, 
            helper: 'Ex: "150 crianças atendidas", "R\$ 10k arrecadados", "3 eventos organizados".'
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
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.pink, width: 2), borderRadius: BorderRadius.circular(12)),
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
                Icon(Icons.calendar_today, size: 16, color: isDisabled ? const Color(0xFFAFAFAF) : Colors.pink),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
