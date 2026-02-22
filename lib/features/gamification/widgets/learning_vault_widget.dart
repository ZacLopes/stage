import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class LearningVaultWidget extends StatefulWidget {
  final Function(List<Map<String, String>>) onSave;
  final List<dynamic>? initialValue;

  const LearningVaultWidget({
    Key? key,
    required this.onSave,
    this.initialValue,
  }) : super(key: key);

  @override
  State<LearningVaultWidget> createState() => _LearningVaultWidgetState();
}

class _LearningVaultWidgetState extends State<LearningVaultWidget> {
  final List<Map<String, String>> _courses = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      try {
        for (var item in widget.initialValue!) {
          if (item is Map) {
             _courses.add(Map<String, String>.from(item));
          } else if (item is String) {
            try {
               final parsed = jsonDecode(item);
               if (parsed is Map) {
                 _courses.add(Map<String, String>.from(parsed));
               }
            } catch (_) {}
          }
        }
      } catch (e) {
        print('Error parsing initial value for LearningVault: $e');
      }
    }
  }

  void _emit() {
    widget.onSave(_courses);
  }

  void _addCourse(String title, String institution, String year) {
    setState(() {
      _courses.add({
        'title': title,
        'institution': institution,
        'year': year,
      });
    });
    _emit();
  }

  void _removeCourse(int index) {
    setState(() {
      _courses.removeAt(index);
    });
    _emit();
  }

  void _showAddDialog() {
    final titleController = TextEditingController();
    final institutionController = TextEditingController();
    final yearController = TextEditingController();
    final _formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 20,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7), // Light green
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.school, color: Color(0xFF16A34A), size: 28),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Adicionar Curso',
                                style: TextStyle(
                                  fontSize: 22, 
                                  fontWeight: FontWeight.bold, 
                                  color: Color(0xFF374151)
                                ),
                              ),
                              Text(
                                'Preencha os dados da certificação',
                                style: TextStyle(
                                  fontSize: 14, 
                                  color: Color(0xFF6B7280)
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // Fields
                    _buildFancyTextField(
                      controller: titleController,
                      label: 'Nome do Curso',
                      hint: 'Ex: Liderança Ágil',
                      icon: Icons.menu_book_rounded,
                    ),
                    const SizedBox(height: 16),
                    _buildFancyTextField(
                      controller: institutionController,
                      label: 'Instituição / Emissor',
                      hint: 'Ex: Google, Alura, USP',
                      icon: Icons.account_balance_rounded,
                    ),
                    const SizedBox(height: 16),
                    _buildFancyTextField(
                      controller: yearController,
                      label: 'Ano de Conclusão',
                      hint: 'Ex: 2023',
                      icon: Icons.calendar_today_rounded,
                      isNumber: true,
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(
                                fontSize: 16, 
                                fontWeight: FontWeight.bold, 
                                color: Color(0xFF6B7280)
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                _addCourse(titleController.text, institutionController.text, yearController.text);
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF58CC02),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: Color(0xFF46A302), width: 0), // Slight border logic
                              ),
                              shadowColor: const Color(0xFF46A302), // Bottom shade color logic simulation
                            ),
                            child: const Text(
                              'Adicionar',
                              style: TextStyle(
                                fontSize: 16, 
                                fontWeight: FontWeight.bold
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFancyTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14, 
            fontWeight: FontWeight.bold, 
            color: Color(0xFF374151)
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          inputFormatters: isNumber 
              ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)]
              : [TextCapitalization.sentences == TextCapitalization.words ? FilteringTextInputFormatter.singleLineFormatter : FilteringTextInputFormatter.deny(RegExp(''))], // Hacky simple pass-through or proper capitalization
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.w500, 
            color: Color(0xFF111827)
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 22),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF58CC02), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          validator: (val) {
             if (val == null || val.trim().isEmpty) return 'Este campo é obrigatório';
             if (isNumber && val.length != 4) return 'Digite um ano válido (4 dígitos)';
             return null;
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_courses.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
            ),
            child: Column(
              children: [
                const Icon(Icons.school_outlined, size: 64, color: Color(0xFF9CA3AF)),
                const SizedBox(height: 16),
                const Text(
                  'Sua estante está vazia.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Adicione cursos, certificações ou workshops que você realizou!',
                  style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _courses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final course = _courses[index];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
                  boxShadow: const [BoxShadow(color: Color(0xFFE5E7EB), offset: Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF), // Light blue bg
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.workspace_premium, color: Color(0xFF3B82F6), size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course['title'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF374151)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${course['institution']} • ${course['year']}',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                      onPressed: () => _removeCourse(index),
                    ),
                  ],
                ),
              );
            },
          ),
        
        const SizedBox(height: 24),
        
        ElevatedButton.icon(
          onPressed: _showAddDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF58CC02),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF58CC02), width: 2),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.add_circle_outline),
          label: const Text(
            'ADICIONAR CURSO',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0),
          ),
        ),
      ],
    );
  }
}
