import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import '../../../core/theme/theme.dart';

class CityStateSelectionWidget extends StatefulWidget {
  final ValueChanged<String> onSelect;
  final String? initialValue;

  const CityStateSelectionWidget({super.key, required this.onSelect, this.initialValue});

  @override
  State<CityStateSelectionWidget> createState() => _CityStateSelectionWidgetState();
}

class _CityStateSelectionWidgetState extends State<CityStateSelectionWidget> {
  String? _selectedUF;
  String? _selectedCity;
  List<String> _cities = [];
  bool _isLoadingCities = false;

  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();

  final List<String> _states = [
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 
    'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 
    'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      final parts = widget.initialValue!.split(' - ');
      if (parts.length == 2) {
        _selectedCity = parts[0];
        _selectedUF = parts[1];
        _stateController.text = _selectedUF!;
        _cityController.text = _selectedCity!;
        _fetchCities(_selectedUF!, preserveCity: true); 
      }
    }
  }

  @override
  void dispose() {
    _stateController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _fetchCities(String uf, {bool preserveCity = false}) async {
    setState(() {
      _isLoadingCities = true;
      _cities = [];
      if (!preserveCity) {
        _selectedCity = null;
        _cityController.clear();
      }
    });

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('https://servicodados.ibge.gov.br/api/v1/localidades/estados/$uf/municipios'));
      final response = await request.close();

      if (response.statusCode == 200) {
        final String responseBody = await response.transform(utf8.decoder).join();
        final List<dynamic> data = jsonDecode(responseBody);
        final List<String> fetchedCities = data.map<String>((city) => city['nome'] as String).toList();
        fetchedCities.sort();

        if (mounted) {
          setState(() {
            _cities = fetchedCities;
            if (preserveCity && _selectedCity != null && !_cities.contains(_selectedCity)) {
               _selectedCity = null;
               _cityController.clear();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching cities: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingCities = false);
      }
    }
  }

  void _updateSelection() {
    if (_selectedUF != null && _selectedCity != null) {
      widget.onSelect('$_selectedCity - $_selectedUF');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // STATE SELECTION
        _buildSearchableField(
          label: 'ESTADO',
          hint: 'Ex: SP, RJ, MG...',
          icon: Icons.map_rounded,
          controller: _stateController,
          options: _states,
          onSelected: (uf) {
            HapticFeedback.lightImpact();
            setState(() {
              _selectedUF = uf;
              _stateController.text = uf;
              _selectedCity = null;
              _cityController.clear();
            });
            _fetchCities(uf);
            _updateSelection();
          },
        ),
        
        const SizedBox(height: 28),

        // CITY SELECTION
        _buildSearchableField(
          label: 'CIDADE',
          hint: _selectedUF == null ? 'Selecione o estado primeiro' : 'Digite o nome da cidade...',
          icon: Icons.location_city_rounded,
          controller: _cityController,
          options: _cities,
          isEnabled: _selectedUF != null && !_isLoadingCities,
          isLoading: _isLoadingCities,
          onSelected: (city) {
            HapticFeedback.lightImpact();
            setState(() {
              _selectedCity = city;
              _cityController.text = city;
            });
            _updateSelection();
          },
        ),
      ],
    );
  }

  Widget _buildSearchableField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    required List<String> options,
    required Function(String) onSelected,
    bool isEnabled = true,
    bool isLoading = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.textDisabled,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text == '') {
              return const Iterable<String>.empty();
            }
            return options.where((String option) {
              return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
            });
          },
          onSelected: onSelected,
          fieldViewBuilder: (context, fieldTextEditingController, focusNode, onFieldSubmitted) {
            // Sync internal controller with parent controller
            if (controller.text != fieldTextEditingController.text) {
               WidgetsBinding.instance.addPostFrameCallback((_) {
                 if (mounted && controller.text != fieldTextEditingController.text) {
                    fieldTextEditingController.text = controller.text;
                 }
               });
            }

            final isSelected = options.contains(fieldTextEditingController.text.trim());

            return Container(
              decoration: BoxDecoration(
                color: isEnabled ? Colors.white : AppColors.background,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.secondary : (isEnabled ? AppColors.border : AppColors.background),
                  width: 2.5,
                ),
                boxShadow: isEnabled ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    offset: const Offset(0, 4),
                    blurRadius: 0,
                  )
                ] : [],
              ),
              child: TextField(
                controller: fieldTextEditingController,
                focusNode: focusNode,
                enabled: isEnabled,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                onChanged: (val) {
                  // If manual type matches exactly, trigger selection logic
                  if (options.contains(val.trim())) {
                    onSelected(val.trim());
                  }
                },
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: AppColors.textDisabled, fontWeight: FontWeight.normal),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(icon, color: isEnabled ? AppColors.secondary : AppColors.textDisabled, size: 24),
                  ),
                  suffixIcon: isLoading 
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.secondary)),
                      )
                    : (isSelected 
                        ? IconButton(
                            icon: const Icon(Icons.check_circle_rounded, color: AppColors.success),
                            onPressed: () {
                              // Optional: Allow clearing?
                            },
                          )
                        : Icon(Icons.search_rounded, color: isEnabled ? AppColors.borderStrong : Colors.transparent, size: 22)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: MediaQuery.of(context).size.width - 64, // Adjust for padding
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border, width: 2),
                  ),
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.background),
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          child: Row(
                            children: [
                              Icon(
                                label == 'ESTADO' ? Icons.map_outlined : Icons.location_on_outlined, 
                                size: 18, 
                                color: AppColors.textTertiary
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  option,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              const Icon(Icons.add_rounded, size: 18, color: AppColors.secondary),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
