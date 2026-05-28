import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../../core/theme/theme.dart';

class IdCardBuilderWidget extends StatefulWidget {
  final Function(Map<String, String>) onSelect;
  final String cardTitle;
  final String field1Label;
  final String field1Icon;
  final String field2Label;
  final String field2Icon;
  final String moduleTag;
  final String? initialValue;

  const IdCardBuilderWidget({
    super.key, 
    required this.onSelect,
    this.cardTitle = 'CARTEIRINHA ESTUDANTIL',
    this.field1Label = 'Instituição de Ensino',
    this.field1Icon = 'school', 
    this.field2Label = 'Nome do Curso',
    this.field2Icon = 'book',
    this.moduleTag = 'Módulo 2',
    this.initialValue,
  });

  @override
  State<IdCardBuilderWidget> createState() => _IdCardBuilderWidgetState();
}

class _IdCardBuilderWidgetState extends State<IdCardBuilderWidget> {
  final TextEditingController _field1Controller = TextEditingController();
  final TextEditingController _field2Controller = TextEditingController();
  String _status = 'Cursando';

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(widget.initialValue!);
        _field1Controller.text = data['field1'] ?? data['institution_name'] ?? data['company_name'] ?? '';
        _field2Controller.text = data['field2'] ?? data['course_name'] ?? data['role_name'] ?? '';
        _status = data['status'] ?? data['course_status'] ?? data['work_status'] ?? 'Cursando';
      } catch (e) {
        print('Error parsing initialValue for IdCardBuilder: $e');
      }
    }
    _field1Controller.addListener(_updateSelection);
    _field2Controller.addListener(_updateSelection);
  }

  @override
  void dispose() {
    _field1Controller.dispose();
    _field2Controller.dispose();
    super.dispose();
  }

  void _updateSelection() {
    if (_field1Controller.text.length >= 2 && _field2Controller.text.length >= 2) {
      widget.onSelect({
        'field1': _field1Controller.text, // Generic keys now
        'field2': _field2Controller.text,
        'status': _status,
        // Keep backward compat keys for existing logic if needed (or map them later)
        if (widget.cardTitle.contains('ESTUDANTIL')) ...{
           'institution_name': _field1Controller.text,
           'course_name': _field2Controller.text,
           'course_status': _status,
        } else ...{
           'company_name': _field1Controller.text,
           'role_name': _field2Controller.text,
           'work_status': _status,
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.cardTitle.contains('ESTUDANTIL') 
              ? [AppColors.primary, AppColors.info]
              : [const Color(0xFFF97316), const Color(0xFFEC4899)], // Orange/Pink for Work
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.cardTitle.contains('ESTUDANTIL') ? Icons.badge : Icons.work, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.cardTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
// Module tag removed per user request
            ],
          ),
          const SizedBox(height: 24),
          _buildTextField(widget.field1Label, _field1Controller, Icons.account_balance),
          const SizedBox(height: 16),
          _buildTextField(widget.field2Label, _field2Controller, widget.cardTitle.contains('ESTUDANTIL') ? Icons.menu_book : Icons.badge),
          const SizedBox(height: 24),
          const Text(
            'STATUS',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusChip(widget.cardTitle.contains('ESTUDANTIL') ? 'Cursando' : 'Ativo', Icons.check_circle_outline),
                const SizedBox(width: 8),
                _buildStatusChip(widget.cardTitle.contains('ESTUDANTIL') ? 'Concluído' : 'Saí', Icons.check_circle),
                // Only show trancado for student
                if (widget.cardTitle.contains('ESTUDANTIL')) ...[
                   const SizedBox(width: 8),
                   _buildStatusChip('Trancado', Icons.pause_circle),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Digite aqui...',
              hintStyle: TextStyle(color: AppColors.textDisabled),
              prefixIcon: Icon(icon, color: AppColors.primary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, IconData icon) {
    final isSelected = _status == label;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _status = label);
        _updateSelection();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.primary : Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
