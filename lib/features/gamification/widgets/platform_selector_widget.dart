import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

class PlatformSelectorWidget extends StatefulWidget {
  final ValueChanged<List<String>> onSelect;
  final List<String> options;
  final List<String>? initialValue;

  const PlatformSelectorWidget({
    super.key,
    required this.onSelect,
    required this.options,
    this.initialValue,
  });

  @override
  State<PlatformSelectorWidget> createState() => _PlatformSelectorWidgetState();
}

class _PlatformSelectorWidgetState extends State<PlatformSelectorWidget> {
  final Map<String, String> _selectedPlatforms = {}; // Platform -> Link

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      for (var item in widget.initialValue!) {
        final parts = item.split(': ');
        if (parts.length >= 2) {
          final key = parts[0];
          final val = parts.sublist(1).join(': ');
          _selectedPlatforms[key] = val;
        }
      }
    }
  }

  void _handleOptionTap(String platform) {
    // 1. Logic for "Não tenho"
    if (platform == 'Não tenho') {
      setState(() {
         // Toggle logic
         if (_selectedPlatforms.containsKey('Não tenho')) {
           _selectedPlatforms.remove('Não tenho');
         } else {
           _selectedPlatforms.clear(); // Clear all others
           _selectedPlatforms['Não tenho'] = 'true'; // Marker
         }
      });
      _emitSelection();
      return;
    }

    // 2. Logic for others: Clear "Não tenho" if selecting something else
    if (_selectedPlatforms.containsKey('Não tenho')) {
       setState(() => _selectedPlatforms.remove('Não tenho'));
    }

    // 3. Show dialog
    _showLinkDialog(platform);
  }

  void _showLinkDialog(String platform) {
    String currentLink = _selectedPlatforms[platform] ?? '';
    final isOutro = platform == 'Outro';
    
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Padding(
          padding: MediaQuery.of(context).viewInsets,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: ScaleTransition(
                scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
                child: SingleChildScrollView(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.brandSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _getIconForPlatform(platform),
                            size: 32,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isOutro ? 'Adicionar Novo Link' : 'Link do $platform',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isOutro 
                            ? 'Cole o link do seu portfólio ou projeto abaixo.' 
                            : 'Cole o link do seu perfil no $platform.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: AppColors.textDisabled),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          autofocus: true,
                          controller: TextEditingController(text: currentLink),
                          decoration: InputDecoration(
                            hintText: 'https://...',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.secondary, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          onChanged: (val) => currentLink = val,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Cancelar', style: TextStyle(color: AppColors.textDisabled, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    if (currentLink.trim().isNotEmpty) {
                                      _selectedPlatforms[platform] = currentLink.trim();
                                    } else {
                                      _selectedPlatforms.remove(platform);
                                    }
                                  });
                                  _emitSelection();
                                  Navigator.pop(context);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(color: Color(0xFF58A700), width: 0), // Bottom border effect implied
                                  ),
                                ),
                                child: const Text('SALVAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _emitSelection() {
    // Convert Map to list of strings "Platform: Link"
    List<String> result = [];
    _selectedPlatforms.forEach((key, value) {
      result.add('$key: $value');
    });
    widget.onSelect(result);
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: widget.options.length,
      itemBuilder: (context, index) {
        final option = widget.options[index];
        final isSelected = _selectedPlatforms.containsKey(option);
        final isNone = option == 'Não tenho';

        return GestureDetector(
          onTap: () => _handleOptionTap(option),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? (isNone ? AppColors.errorSoft : AppColors.brandSoft) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? (isNone ? AppColors.error : AppColors.secondary) : AppColors.border,
                width: 2,
              ),
              boxShadow: [
                if (!isSelected)
                  const BoxShadow(
                    color: AppColors.border,
                    offset: Offset(0, 4),
                    blurRadius: 0,
                  )
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getIconForPlatform(option),
                  color: isSelected ? (isNone ? AppColors.error : AppColors.secondary) : AppColors.textSecondary,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  option,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? (isNone ? AppColors.error : AppColors.brand) : AppColors.textSecondary,
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, color: isNone ? AppColors.error : AppColors.success, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getIconForPlatform(String platform) {
    switch (platform.toLowerCase()) {
      case 'github': return Icons.code;
      case 'behance': return Icons.brush;
      case 'dribbble': return Icons.sports_basketball; // Fallback
      case 'instagram profissional': return Icons.camera_alt;
      case 'portfólio pessoal': return Icons.person;
      case 'portfólio pessoal': return Icons.person;
      case 'outro': return Icons.link;
      case 'não tenho': return Icons.block;
      default: return Icons.link;
    }
  }
}
