import 'package:flutter/material.dart';
import 'dart:convert';
import 'month_year_picker_sheet.dart';
import '../../../core/theme/theme.dart';

class RetroIdCardWidget extends StatefulWidget {
  final Function(String) onSave;
  final String? initialValue;

  const RetroIdCardWidget({super.key, required this.onSave, this.initialValue});

  @override
  State<RetroIdCardWidget> createState() => _RetroIdCardWidgetState();
}

class _RetroIdCardWidgetState extends State<RetroIdCardWidget> with SingleTickerProviderStateMixin {
  final _institutionController = TextEditingController();
  final _courseController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  String? _status; 
  AnimationController? _stampController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _opacityAnimation;
  bool _showStamp = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    if (widget.initialValue != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(widget.initialValue!);
        _institutionController.text = data['institution'] ?? '';
        _courseController.text = data['course'] ?? '';
        _startDateController.text = data['startDate'] ?? '';
        _endDateController.text = data['endDate'] ?? '';
        _status = data['status'];
        if (_status != null) {
          // Optionally show stamp immediately if it was saved?
          // _showStamp = true; 
          // But maybe user wants to edit. Let's not auto-stamp to allow editing, 
          // or auto-stamp if it looks complete?
          // Usually state restoration implies returning to where they left off.
          // If they saved, it's done. But they might want to change it.
          // Let's just populate fields.
        }
      } catch (e) {
        // Fallback
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initAnimations(); // Ensures init if hot reload skipped initState
  }

  void _initAnimations() {
    if (_stampController != null) return;
    
    _stampController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnimation = Tween<double>(begin: 2.0, end: 1.0).animate(
      CurvedAnimation(parent: _stampController!, curve: Curves.bounceOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _stampController!, curve: const Interval(0.0, 0.5)),
    );
  }

  @override
  void dispose() {
    _stampController?.dispose();
    _institutionController.dispose();
    _courseController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_institutionController.text.isNotEmpty && 
        _courseController.text.isNotEmpty && 
        _startDateController.text.isNotEmpty &&
        _endDateController.text.isNotEmpty &&
        _status != null) {
      
      // Ensure initialized just in case
      _initAnimations();

      // Trigger Animation
      setState(() => _showStamp = true);
      await _stampController!.forward();
      
      // Wait a moment for user to see it
      await Future.delayed(const Duration(milliseconds: 500));

      // Serialize and Save
      final jsonString = '{"institution": "${_institutionController.text}", "course": "${_courseController.text}", "startDate": "${_startDateController.text}", "endDate": "${_endDateController.text}", "status": "$_status"}';
      widget.onSave(jsonString);
    } else {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha os campos e selecione um status para carimbar.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _initAnimations(); // Ensure initialized (lazy init safety)

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          // ... (content remains same)
          decoration: BoxDecoration(
            color: const Color(0xFFF3EAD3), // Beige/Retro paper color
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                offset: const Offset(4, 4),
                blurRadius: 10,
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.school, color: Color(0xFF8B7355), size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'REGISTRO ACADÊMICO ANTIGO',
                      style: TextStyle(
                        fontFamily: 'Courier', 
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: const Color(0xFF8B7355).withOpacity(0.8),
                        letterSpacing: 1.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildField('INSTITUIÇÃO', _institutionController),
              const SizedBox(height: 24),
              _buildField('CURSO ANTERIOR', _courseController),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _buildField('INÍCIO', _startDateController, isDate: true)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildField('FIM', _endDateController, isDate: true)),
                ],
              ),
              const SizedBox(height: 32),
              const Text(
                'STATUS DO REGISTRO',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B7355),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildStamp('Concluído', AppColors.success)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStamp('Interrompido', AppColors.warning)),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _showStamp ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5D4037),
                    foregroundColor: const Color(0xFFF3EAD3),
                    disabledBackgroundColor: AppColors.textDisabled,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_showStamp ? 'REGISTRO SALVO' : 'CARIMBAR E SALVAR'),
                ),
              ),
            ],
          ),
        ),
        if (_showStamp && _stampController != null)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _stampController!,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation!.value,
                  child: Opacity(
                    opacity: _opacityAnimation!.value,
                    child: Transform.rotate(
                      angle: -0.2, // Slight tilt
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.success.withOpacity(0.8), width: 4),
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.success.withOpacity(0.1),
                        ),
                        child: const Text(
                          'VALIDADO',
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _selectDate(TextEditingController controller) async {
    if (_showStamp) return;
    
    DateTime initialDate = DateTime.now();
    if (controller.text.isNotEmpty) {
      try {
        final parts = controller.text.split('/');
        if (parts.length == 3) {
          initialDate = DateTime(int.parse(parts[2]), int.parse(parts[1]));
        } else if (parts.length == 2) {
          initialDate = DateTime(int.parse(parts[1]), int.parse(parts[0]));
        }
      } catch (_) {}
    }

    final DateTime? picked = await showMonthYearPickerSheet(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    
    if (picked != null) {
      setState(() {
        controller.text = "${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  Widget _buildField(String label, TextEditingController controller, {bool isDate = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF8B7355),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: _showStamp || isDate,
          onTap: isDate ? () => _selectDate(controller) : null,
          style: const TextStyle(
            fontFamily: 'Courier',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3E2723),
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF8B7355), width: 2),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF5D4037), width: 3),
            ),
            hintText: isDate ? 'mm/aaaa' : 'Digite aqui...',
            hintStyle: TextStyle(
              fontFamily: 'Courier',
              color: const Color(0xFF8B7355).withOpacity(0.4),
            ),
            suffixIcon: isDate ? const Icon(Icons.calendar_today, size: 16, color: Color(0xFF8B7355)) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildStamp(String label, Color color) {
    final isSelected = _status == label;
    return GestureDetector(
      onTap: _showStamp ? null : () => setState(() => _status = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.3),
            width: 3,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                  fontSize: 12, // Reduced font size
                  color: isSelected ? color : color.withOpacity(0.5),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
