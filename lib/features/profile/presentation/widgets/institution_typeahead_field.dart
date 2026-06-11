import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/theme.dart';

/// Sugestão do catálogo `institutions` (Fase 1 T1.6).
class InstitutionSuggestion {
  final String id;
  final String name;
  const InstitutionSuggestion({required this.id, required this.name});
}

/// Campo de instituição com typeahead contra o catálogo `institutions`
/// (Fase 1 T1.6 — resolve a fragmentação do texto livre, auditoria G7).
///
/// Comportamento:
///  - digitou ≥2 chars → consulta o catálogo (debounce 250ms) e mostra até
///    6 sugestões INLINE abaixo do campo (sem overlay — funciona igual no
///    onboarding e no modal do perfil);
///  - tocar numa sugestão preenche o texto com o nome canônico e fixa o
///    `institution_id` (via [onInstitutionSelected]);
///  - continuar digitando depois de selecionar LIMPA o id ("outra" =
///    texto livre, institution_id null — o raw text permanece a verdade).
///
/// O dono do [controller] e do estado do id é o caller — este widget só
/// notifica. [decoration] permite casar com o estilo da tela hospedeira.
class InstitutionTypeaheadField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<InstitutionSuggestion?> onInstitutionSelected;
  final InputDecoration decoration;
  final TextStyle? style;

  const InstitutionTypeaheadField({
    super.key,
    required this.controller,
    required this.onInstitutionSelected,
    required this.decoration,
    this.style,
  });

  @override
  State<InstitutionTypeaheadField> createState() =>
      _InstitutionTypeaheadFieldState();
}

class _InstitutionTypeaheadFieldState extends State<InstitutionTypeaheadField> {
  Timer? _debounce;
  List<InstitutionSuggestion> _suggestions = const [];
  String _lastSelectedName = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    // Editar depois de selecionar invalida o vínculo com o catálogo.
    if (value != _lastSelectedName) {
      widget.onInstitutionSelected(null);
    }
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(query));
  }

  Future<void> _search(String query) async {
    try {
      final sanitized = query.replaceAll('%', '').replaceAll(',', ' ');
      final rows = await Supabase.instance.client
          .from('institutions')
          .select('id, name')
          .or('name.ilike.%$sanitized%,normalized_name.ilike.%$sanitized%')
          .limit(6);
      if (!mounted) return;
      setState(() {
        _suggestions = (rows as List)
            .map((r) => InstitutionSuggestion(
                  id: r['id'] as String,
                  name: r['name'] as String,
                ))
            .toList();
      });
    } catch (_) {
      // Catálogo indisponível = campo segue como texto livre. Silencioso.
      if (mounted) setState(() => _suggestions = const []);
    }
  }

  void _select(InstitutionSuggestion s) {
    _lastSelectedName = s.name;
    widget.controller.text = s.name;
    widget.controller.selection =
        TextSelection.collapsed(offset: s.name.length);
    widget.onInstitutionSelected(s);
    setState(() => _suggestions = const []);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: _onChanged,
          style: widget.style,
          decoration: widget.decoration,
          textCapitalization: TextCapitalization.words,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in _suggestions)
                  InkWell(
                    onTap: () => _select(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.school_outlined,
                              size: 16, color: AppColors.textTertiary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
