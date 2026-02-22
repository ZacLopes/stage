import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'month_year_picker_sheet.dart';

class ExperienceTypeSelectWidget extends StatefulWidget {
  final Function(List<String>) onSelect; 
  final List<dynamic> options;
  final dynamic initialValue;

  const ExperienceTypeSelectWidget({
    super.key,
    required this.onSelect,
    required this.options,
    this.initialValue,
  });

  @override
  State<ExperienceTypeSelectWidget> createState() => _ExperienceTypeSelectWidgetState();
}

class _ExperienceTypeSelectWidgetState extends State<ExperienceTypeSelectWidget> {
  final List<String> _selectedIds = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      if (widget.initialValue is String) {
        // Stored as a single JSON array string "[...]"
        try {
           final parsed = jsonDecode(widget.initialValue);
           if (parsed is List) {
             _selectedIds.addAll(parsed.map((e) => e.toString()));
           }
        } catch (_) {
           // Fallback if not JSON or different format
           _selectedIds.add(widget.initialValue.toString());
        }
      } else if (widget.initialValue is List) {
         _selectedIds.addAll((widget.initialValue as List).map((e) => e.toString()));
      }
    }
  }


  void _handleSelect(Map<String, dynamic> option) {
    HapticFeedback.lightImpact();
    final id = option['id'].toString();

    if (id == 'other') {
      _showCustomExperienceDialog();
      return;
    }

    if (id == 'none') {
      if (_selectedIds.contains('none')) {
         // Deselecting none
         setState(() {
           _selectedIds.remove('none');
         });
         _emit();
      } else {
         _showNoExperienceDialog();
      }
      return;
    }

    setState(() {
      // If adding a normal option, remove 'none' if present
      _selectedIds.remove('none');
      _selectedIds.add(id);
    });
    _emit();
  }

  void _removeAt(int index) {
    setState(() {
      _selectedIds.removeAt(index);
    });
    _emit();
  }

  void _emit() {
    if (_selectedIds.contains('none')) {
      widget.onSelect(['NO_EXPERIENCE']);
    } else {
      widget.onSelect(_selectedIds);
    }
  }

  void _showCustomExperienceDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String? startDate;
    String? endDate;
    bool isOngoing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
            
          Future<void> pickDate(bool isStart) async {
            final now = DateTime.now();
            DateTime initialDate = now;
            DateTime? firstDate;

            // Determine initial date
            String? currentValue = isStart ? startDate : endDate;
            if (currentValue != null && currentValue != "Atual") {
              try {
                final parts = currentValue.split('/');
                if (parts.length == 3) {
                   initialDate = DateTime(int.parse(parts[2]), int.parse(parts[1]));
                } else if (parts.length == 2) {
                   initialDate = DateTime(int.parse(parts[1]), int.parse(parts[0]));
                }
              } catch (_) {}
            }

            // End Date Logic
            if (!isStart && startDate != null) {
              try {
                final parts = startDate!.split('/');
                if (parts.length == 3) {
                  firstDate = DateTime(int.parse(parts[2]), int.parse(parts[1]));
                } else if (parts.length == 2) {
                  firstDate = DateTime(int.parse(parts[1]), int.parse(parts[0]));
                }
                if (initialDate.isBefore(firstDate!)) initialDate = firstDate!;
              } catch (_) {}
            }

            final picked = await showMonthYearPickerSheet(
              context: context,
              initialDate: initialDate,
              firstDate: firstDate,
              lastDate: now,
            );

            if (picked != null) {
              HapticFeedback.lightImpact();
              setState(() {
                final formatted = "${picked.month.toString().padLeft(2, '0')}/${picked.year}";
                if (isStart) {
                  startDate = formatted;
                  if (endDate != null) {
                     // Check invalid end date
                     try {
                        final sParts = formatted.split('/');
                        final sDt = DateTime(int.parse(sParts[1]), int.parse(sParts[0]));
                        final eParts = endDate!.split('/');
                        final eDt = DateTime(int.parse(eParts[1]), int.parse(eParts[0]));
                        if (eDt.isBefore(sDt)) endDate = null;
                     } catch (_) {}
                  }
                } else {
                  endDate = formatted;
                }
              });
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Nova Experiência', style: TextStyle(fontWeight: FontWeight.bold)),
            content: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Dê um nome para essa vivência e descreva brevemente o que foi.', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Título da Experiência',
                          border: OutlineInputBorder(),
                          hintText: 'Ex: Projeto de Extensão...',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descController,
                        decoration: const InputDecoration(
                          labelText: 'Descrição Curta',
                          border: OutlineInputBorder(),
                          hintText: 'Comece com um verbo (ex: Liderei, Criei)...',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      const Text('Quando aconteceu?', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => pickDate(true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(startDate ?? 'Início', style: TextStyle(color: startDate != null ? Colors.black : Colors.grey)),
                                    const Icon(Icons.calendar_today, size: 16, color: Color(0xFF58CC02)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: isOngoing ? null : () => pickDate(false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300), 
                                  borderRadius: BorderRadius.circular(8),
                                  color: isOngoing ? Colors.grey.shade100 : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(isOngoing ? 'Atual' : (endDate ?? 'Fim'), style: TextStyle(color: (endDate != null || isOngoing) ? Colors.black : Colors.grey)),
                                    if (!isOngoing) const Icon(Icons.calendar_today, size: 16, color: Color(0xFF58CC02)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Checkbox(
                            value: isOngoing,
                            activeColor: const Color(0xFF58CC02),
                            onChanged: (val) {
                              setState(() {
                                isOngoing = val ?? false;
                                if (isOngoing) endDate = null;
                              });
                            },
                          ),
                          const Text('Ainda acontece?'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  if (titleController.text.isNotEmpty && descController.text.isNotEmpty && startDate != null && (isOngoing || endDate != null)) {
                    // Emit custom JSON
                    final json = '{"id": "other", "customTitle": "${titleController.text}", "customDesc": "${descController.text}", "startDate": "$startDate", "endDate": "${isOngoing ? 'Atual' : endDate}", "type": "other"}';
                    // We need to call setState of the parent widget to update selectedIds
                    this.setState(() {
                        _selectedIds.remove('none');
                        _selectedIds.add(json);
                    });
                    _emit();
                    Navigator.pop(ctx);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF58CC02), foregroundColor: Colors.white),
                child: const Text('Confirmar'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showNoExperienceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lightbulb, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Expanded(child: Text('Tem certeza?', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        content: const Text(
          'Lembre-se: aquele projeto que você tirou do papel no último semestre, '
          'a startup que você está validando agora ou até trabalhos voluntários contam muito como experiência profissional!\n\n'
          'Tudo isso é válido aqui.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ah, lembrei de algo', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF58CC02))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                  _selectedIds.clear();
                  _selectedIds.add('none');
              });
              _emit();
            },
            child: const Text('Realmente não tenho', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Instructional Text
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF), // Light Blue
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDBEAFE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFF3B82F6), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(color: Color(0xFF1E40AF), fontSize: 13, height: 1.4),
                    children: [
                      TextSpan(text: 'Dica: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: 'Se você teve mais de uma experiência do mesmo tipo (ex: duas empresas diferentes), toque na opção novamente para adicionar outra!'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Summary View
        if (_selectedIds.isNotEmpty && !_selectedIds.contains('none'))
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Experiências Selecionadas:',
                  style: TextStyle(
                    fontSize: 14, 
                    fontWeight: FontWeight.bold, 
                    color: Color(0xFF6B7280)
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_selectedIds.length, (index) {
                    final id = _selectedIds[index];
                    String label = 'Experiência';
                    
                    // Try to parse label
                    if (id.startsWith('{')) {
                      try {
                         // Simple regex or parse to get title for "other"
                         // Assuming "customTitle" is first or using basic logic
                         if (id.contains('customTitle')) {
                           label = 'Outro (Custom)'; 
                           // You could parse properly but simple label is OK too
                         }
                      } catch (_) {}
                    } else {
                      // Find in options
                      final opt = widget.options.firstWhere(
                        (e) => e['id'].toString() == id, 
                        orElse: () => {'label': id}
                      );
                      label = opt['label'];
                    }

                    return Chip(
                      label: Text(label),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () => _removeAt(index),
                      backgroundColor: Colors.white,
                      surfaceTintColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      elevation: 2,
                    );
                  }),
                ),
              ],
            ),
          ),

        // Options List
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.options.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final option = widget.options[index];
            final id = option['id'].toString();
            
            final count = _selectedIds.where((s) => s == id).length;
            final isSelected = count > 0;
            
            // Special handling for "Other" visual state? 
            // Since "Other" adds a complex JSON, simple ID match won't work for count.
            // But usually we just want to tap "Other" to add another.
            
            final isNone = id == 'none';
            final isNoneSelected = _selectedIds.contains('none');
            
            Color baseColor = const Color(0xFF58CC02);
            if (isNone) baseColor = const Color(0xFFFF4B4B);

            return GestureDetector(
              onTap: () => _handleSelect(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (isSelected && !isNone) ? baseColor.withOpacity(0.05) : (isNoneSelected && isNone ? baseColor.withOpacity(0.1) : Colors.white),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (isSelected || (isNoneSelected && isNone)) ? baseColor : const Color(0xFFE5E7EB),
                    width: 2,
                  ),
                  boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: const Offset(0, 4),
                        blurRadius: 4,
                      )
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isSelected || (isNoneSelected && isNone)) ? baseColor : const Color(0xFFF3F4F6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIcon(option['icon']),
                        color: (isSelected || (isNoneSelected && isNone)) ? Colors.white : (isNone ? const Color(0xFFFF4B4B) : const Color(0xFF4B5563)),
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  option['label'],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: (isSelected || (isNoneSelected && isNone)) ? baseColor : const Color(0xFF1F2937),
                                  ),
                                ),
                              ),
                              if (count > 0 && !isNone)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: baseColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'x$count',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                            ],
                          ),
                          if (option['description'] != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              option['description'],
                              style: TextStyle(
                                fontSize: 15.5,
                                color: (isSelected || (isNoneSelected && isNone)) ? baseColor.withOpacity(0.8) : const Color(0xFF6B7280),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isSelected || (isNoneSelected && isNone))
                       Icon(Icons.add_circle, color: baseColor), // Changed to + icon to indicate adding more
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  IconData _getIcon(dynamic iconData) {
    if (iconData is IconData) return iconData;
    if (iconData is String) {
      switch (iconData) {
        case 'business': return Icons.business;
        case 'rocket_launch': return Icons.rocket_launch;
        case 'trending_up': return Icons.trending_up;
        case 'handshake': return Icons.handshake;
        case 'volunteer_activism': return Icons.volunteer_activism;
        case 'school': return Icons.school;
        case 'edit': return Icons.edit;
        case 'group': return Icons.group_work; // Legacy support
        case 'rocket': return Icons.rocket_launch; // Legacy support
        default: return Icons.work;
      }
    }
    return Icons.work;
  }
}
