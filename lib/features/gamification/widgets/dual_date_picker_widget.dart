import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'month_year_picker_sheet.dart';
import '../../../core/theme/theme.dart';

enum DatePickerViewMode { dual, startOnly, endOnly }

class DualWheelDateWidget extends StatefulWidget {
  final Function(Map<String, String>) onSelect;
  final DatePickerViewMode viewMode;
  final String? initialValue;

  const DualWheelDateWidget({
    super.key, 
    required this.onSelect,
    this.viewMode = DatePickerViewMode.dual,
    this.initialValue,
  });

  @override
  State<DualWheelDateWidget> createState() => _DualWheelDateWidgetState();
}

class _DualWheelDateWidgetState extends State<DualWheelDateWidget> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 365 * 4));

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _restoreState();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyChange();
    });
  }

  void _restoreState() {
    try {
      final Map<String, dynamic> data = jsonDecode(widget.initialValue!);
      
      final startStr = data['course_start_mm_yyyy'] ?? data['start_date'];
      final endStr = data['course_end_mm_yyyy'] ?? data['end_date'];

      if (startStr != null) _startDate = _parseDate(startStr);
      if (endStr != null) _endDate = _parseDate(endStr);
      
      // Validation to ensure logical dates if possible, but trust stored data mostly
    } catch (e) { 
      print("Error restoring date: $e");
    }
  }

  DateTime _parseDate(String dateStr) {
    try {
      final parts = dateStr.split('/');
      if (parts.length == 2) {
        final month = int.parse(parts[0]);
        final year = int.parse(parts[1]);
        return DateTime(year, month);
      }
    } catch (_) {}
    return DateTime.now();
  }

  void _notifyChange() {
    final startStr = "${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}";
    final endStr = "${_endDate.month.toString().padLeft(2, '0')}/${_endDate.year}";
    
    // Calculate duration only if we have both, otherwise 0 or partial
    int months = 0;
    if (widget.viewMode != DatePickerViewMode.startOnly) {
       months = (_endDate.year - _startDate.year) * 12 + _endDate.month - _startDate.month;
       if (months < 0) months = 0;
    }
    
    widget.onSelect({
      'course_start_mm_yyyy': startStr, // Always send start (mocked if endOnly)
      'course_end_mm_yyyy': endStr,     // Always send end (mocked if startOnly)
      'duration_months': months.toString(),
      'mode': widget.viewMode.toString(),
      // Specific keys for single mode
      if (widget.viewMode == DatePickerViewMode.startOnly) 'start_date': startStr,
      if (widget.viewMode == DatePickerViewMode.endOnly) 'end_date': endStr,
    });
    setState(() {});
  }

  Future<void> _showDatePicker(BuildContext context, bool isStart) async {
    final picked = await showMonthYearPickerSheet(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
    );
    
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = DateTime(_startDate.year + 1, _startDate.month);
          }
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _startDate = DateTime(_endDate.year - 1, _endDate.month);
          }
        }
      });
      _notifyChange();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Only show Duration in Dual Mode
        if (widget.viewMode == DatePickerViewMode.dual)
          _buildDurationHeader(),
        
        const SizedBox(height: 24),
        
        Row(
          children: [
            if (widget.viewMode == DatePickerViewMode.dual || widget.viewMode == DatePickerViewMode.startOnly)
              Expanded(
                child: _buildDateCard('INÍCIO', _startDate, true),
              ),
            
            if (widget.viewMode == DatePickerViewMode.dual)
               const SizedBox(width: 16),

            if (widget.viewMode == DatePickerViewMode.dual || widget.viewMode == DatePickerViewMode.endOnly)
              Expanded(
                child: _buildDateCard('FIM', _endDate, false),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDurationHeader() {
    int totalMonths = (_endDate.year - _startDate.year) * 12 + _endDate.month - _startDate.month;
    if (totalMonths < 0) totalMonths = 0;
    
    int years = (totalMonths / 12).floor();
    int months = totalMonths % 12;
    
    String durationText = '';
    if (years > 0) durationText += '$years anos ';
    if (months > 0) durationText += '$months meses';
    if (durationText.isEmpty) durationText = '0 meses';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 8),
          Text(
            'Duração Total: $durationText',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateCard(String label, DateTime date, bool isStart) {
    return GestureDetector(
      onTap: () => _showDatePicker(context, isStart),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 2),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textDisabled,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "${date.month.toString().padLeft(2, '0')}/${date.year}",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
