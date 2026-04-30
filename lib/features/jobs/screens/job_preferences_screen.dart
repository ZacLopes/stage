import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../jobs_viewmodel.dart';
import '../models/user_preferences.dart';

class JobPreferencesScreen extends StatefulWidget {
  const JobPreferencesScreen({super.key});

  @override
  State<JobPreferencesScreen> createState() => _JobPreferencesScreenState();
}

class _JobPreferencesScreenState extends State<JobPreferencesScreen> {
  // Local state mirrors what's in the ViewModel — we commit on save.
  List<String> _areas = [];
  List<String> _locations = [];
  Set<String> _selectedWorkModels = {};
  Set<String> _selectedJobTypes = {};
  int? _minSalary;
  bool _loaded = false;
  bool _saving = false;

  // Maps raw DB values ↔ display labels
  static const _workModelMap = {
    'remoto': 'Remoto',
    'hibrido': 'Híbrido',
    'presencial': 'Presencial',
  };
  static const _jobTypeMap = {
    'estagio': 'Estágio',
    'trainee': 'Trainee',
    'clt_junior': 'CLT Júnior',
    'temporario': 'Temporário',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _loadFromViewModel();
    }
  }

  void _loadFromViewModel() {
    final vm = context.read<JobsViewModel>();
    final prefs = vm.preferences;
    if (prefs != null) {
      setState(() {
        _areas = List<String>.from(prefs.areas);
        _locations = List<String>.from(prefs.locations);
        _selectedWorkModels = Set<String>.from(prefs.workModels);
        _selectedJobTypes = Set<String>.from(prefs.jobTypes);
        _minSalary = prefs.minSalary;
      });
    }
  }

  Future<void> _saveAndClose() async {
    final vm = context.read<JobsViewModel>();
    setState(() => _saving = true);

    try {
      final prefs = UserJobPreferences(
        userId: vm.userId ?? '',
        areas: List<String>.from(_areas),
        locations: List<String>.from(_locations),
        workModels: _selectedWorkModels.toList(),
        jobTypes: _selectedJobTypes.toList(),
        minSalary: _minSalary,
      );
      await vm.savePreferences(prefs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao salvar preferências.')),
        );
      }
    } finally {
      setState(() => _saving = false);
    }

    if (mounted) Navigator.pop(context);
  }

  void _clearAll() {
    setState(() {
      _areas = [];
      _locations = [];
      _selectedWorkModels = {};
      _selectedJobTypes = {};
      _minSalary = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 28),
                  onPressed: () => Navigator.pop(context),
                  color: const Color(0xFF374151),
                ),
                const Text(
                  'Preferências de Vagas',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                TextButton(
                  onPressed: _clearAll,
                  child: const Text(
                    'Limpar',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Areas de interesse
                _buildSectionHeader('Áreas de interesse', infoText: '(${_areas.length}/5)'),
                const SizedBox(height: 12),
                _buildTagBox(
                  items: _areas,
                  maxItems: 5,
                  emptyLabel: 'Adicionar áreas para encontrar vagas',
                  emptyButtonLabel: 'Adicionar Área',
                  addMoreLabel: 'área',
                  onAdd: _showAreaPicker,
                  onRemove: (item) => setState(() => _areas.remove(item)),
                ),
                const SizedBox(height: 24),

                // Localização
                _buildSectionHeader('Localização', infoText: '(${_locations.length}/5)'),
                const SizedBox(height: 12),
                _buildTagBox(
                  items: _locations,
                  maxItems: 5,
                  emptyLabel: 'Adicionar locais (máximo 5)',
                  emptyButtonLabel: 'Adicionar Localização',
                  addMoreLabel: 'local',
                  onAdd: _showLocationPicker,
                  onRemove: (item) => setState(() => _locations.remove(item)),
                ),
                const SizedBox(height: 32),

                // Premium Filters indicator
                Row(
                  children: [
                    const Text(
                      'Filtros Premium',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Novo',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Work model
                _buildSectionHeader('Modelo de trabalho'),
                const SizedBox(height: 12),
                _buildChipGroup(
                  options: _workModelMap,
                  selectedOptions: _selectedWorkModels,
                ),
                const SizedBox(height: 24),

                // Job type
                _buildSectionHeader('Tipo de vaga'),
                const SizedBox(height: 12),
                _buildChipGroup(
                  options: _jobTypeMap,
                  selectedOptions: _selectedJobTypes,
                ),
                const SizedBox(height: 24),

                // Salary
                _buildSectionHeader('Bolsa mínima'),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _showSalaryPicker,
                  child: Row(
                    children: [
                      Text(
                        _minSalary != null
                            ? 'R\$ ${(_minSalary! / 100).toStringAsFixed(0)}'
                            : 'Definir bolsa mínima',
                        style: TextStyle(
                          fontSize: 16,
                          color: _minSalary != null
                              ? const Color(0xFF111827)
                              : const Color(0xFF9CA3AF),
                          fontWeight: _minSalary != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _minSalary != null ? Icons.check_circle : Icons.edit,
                        size: 16,
                        color: _minSalary != null
                            ? const Color(0xFF10B981)
                            : const Color(0xFF9CA3AF),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // Save button
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveAndClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Aplicar Filtros',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // PICKERS (Multi-select)
  // ============================================

  void _showAreaPicker() {
    final availableAreas = [
      'Marketing', 'Tecnologia', 'Finanças', 'Design',
      'Engenharia', 'RH', 'Vendas', 'Geral',
    ];

    // Use a local copy for multi-select within the sheet
    final selected = Set<String>.from(_areas);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selecionar Áreas',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Máximo 5 • ${selected.length} selecionada(s)',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableAreas.map((area) {
                  final isSelected = selected.contains(area);
                  return GestureDetector(
                    onTap: () {
                      setSheetState(() {
                        if (isSelected) {
                          selected.remove(area);
                        } else if (selected.length < 5) {
                          selected.add(area);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF10B981).withOpacity(0.1)
                            : const Color(0xFFF3F4F6),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        area,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF10B981) : const Color(0xFF374151),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _areas = selected.toList());
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Confirmar (${selected.length})'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLocationPicker() {
    final availableLocations = [
      'São Paulo', 'Rio de Janeiro', 'Belo Horizonte', 'Curitiba',
      'Porto Alegre', 'Brasília', 'Campinas', 'Recife',
    ];

    final selected = Set<String>.from(_locations);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selecionar Localização',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Máximo 5 • ${selected.length} selecionada(s)',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableLocations.map((loc) {
                  final isSelected = selected.contains(loc);
                  return GestureDetector(
                    onTap: () {
                      setSheetState(() {
                        if (isSelected) {
                          selected.remove(loc);
                        } else if (selected.length < 5) {
                          selected.add(loc);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF10B981).withOpacity(0.1)
                            : const Color(0xFFF3F4F6),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        loc,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF10B981) : const Color(0xFF374151),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _locations = selected.toList());
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Confirmar (${selected.length})'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSalaryPicker() {
    double currentValue = (_minSalary ?? 0) / 100;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bolsa Mínima: R\$ ${currentValue.toInt()}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Slider(
                value: currentValue,
                min: 0,
                max: 10000,
                divisions: 100,
                activeColor: const Color(0xFF10B981),
                label: 'R\$ ${currentValue.toInt()}',
                onChanged: (val) {
                  setSheetState(() => currentValue = val);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _minSalary = null);
                        Navigator.pop(ctx);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Limpar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _minSalary = currentValue > 0 ? (currentValue * 100).toInt() : null;
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Aplicar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // SHARED WIDGETS
  // ============================================

  Widget _buildSectionHeader(String title, {String? infoText}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
        if (infoText != null) ...[
          const SizedBox(width: 8),
          Text(
            infoText,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Icon(Icons.info_outline, size: 16, color: Colors.grey[400]),
      ],
    );
  }

  /// Generic tag box that displays items with X buttons and an add more action.
  Widget _buildTagBox({
    required List<String> items,
    required int maxItems,
    required String emptyLabel,
    required String emptyButtonLabel,
    required String addMoreLabel,
    required VoidCallback onAdd,
    required void Function(String) onRemove,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.map((item) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF065F46),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => onRemove(item),
                      child: const Icon(Icons.close, size: 16, color: Color(0xFF065F46)),
                    ),
                  ],
                ),
              )).toList(),
            ),
            if (items.length < maxItems)
              GestureDetector(
                onTap: onAdd,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 16, color: Color(0xFF10B981)),
                      const SizedBox(width: 4),
                      Text(
                        'Adicionar $addMoreLabel',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ] else ...[
            Center(
              child: GestureDetector(
                onTap: onAdd,
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_circle, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        Text(
                          emptyButtonLabel,
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      emptyLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChipGroup({
    required Map<String, String> options,
    required Set<String> selectedOptions,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: options.entries.map((entry) {
        final rawValue = entry.key;
        final displayLabel = entry.value;
        final isSelected = selectedOptions.contains(rawValue);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                selectedOptions.remove(rawValue);
              } else {
                selectedOptions.add(rawValue);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF4F46E5).withOpacity(0.1) : const Color(0xFFF3F4F6),
              border: Border.all(
                color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              displayLabel,
              style: TextStyle(
                color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF374151),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
