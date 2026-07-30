import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../models/application.dart';

/// Entrada da adição manual (FASE 3 T3.3): empresa + título + link opcional +
/// status inicial. Meta UX ≤10s.
class ManualApplicationInput {
  final String company;
  final String title;
  final String? url;
  final ApplicationStatus status;
  const ManualApplicationInput({
    required this.company,
    required this.title,
    this.url,
    required this.status,
  });
}

/// Abre o sheet de adição manual. Retorna o input, ou null se cancelado.
Future<ManualApplicationInput?> showManualApplicationSheet(BuildContext context) {
  return showModalBottomSheet<ManualApplicationInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ManualApplicationSheet(),
  );
}


class _ManualApplicationSheet extends StatefulWidget {
  const _ManualApplicationSheet();

  @override
  State<_ManualApplicationSheet> createState() =>
      _ManualApplicationSheetState();
}

class _ManualApplicationSheetState extends State<_ManualApplicationSheet> {
  final _company = TextEditingController();
  final _title = TextEditingController();
  final _url = TextEditingController();
  ApplicationStatus _status = ApplicationStatus.submitted;
  bool _attempted = false;

  @override
  void dispose() {
    _company.dispose();
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _attempted = true);
    final company = _company.text.trim();
    final title = _title.text.trim();
    if (company.isEmpty || title.isEmpty) return;
    final url = _url.text.trim();
    Navigator.of(context).pop(ManualApplicationInput(
      company: company,
      title: title,
      url: url.isEmpty ? null : url,
      status: _status,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      // Rolável: com 7 status (antes 4) o conteúdo passa a altura disponível
      // em tela pequena / teclado aberto — e um `Column` fixo estourava
      // (`RenderFlex overflowed by 7.0 pixels`, pego pelo widget test ao
      // ampliar a lista). `mainAxisSize.min` mantém o sheet do tamanho do
      // conteúdo quando ele cabe.
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Adicionar candidatura',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pra acompanhar o que aconteceu fora do Stage.',
            style: TextStyle(
                fontFamily: 'Inter', fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          _field(_company, 'Empresa *',
              error: _attempted && _company.text.trim().isEmpty
                  ? 'Informe a empresa'
                  : null),
          const SizedBox(height: 12),
          _field(_title, 'Vaga / cargo *',
              error: _attempted && _title.text.trim().isEmpty
                  ? 'Informe a vaga'
                  : null),
          const SizedBox(height: 12),
          _field(_url, 'Link da vaga (opcional)',
              keyboardType: TextInputType.url),
          const SizedBox(height: 16),
          Text('Status',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in ApplicationStatus.initialOptions)
                ChoiceChip(
                  label: Text(s.label),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
            ],
          ),
          // "Aprovada" é FINAL no banco: `hired` não transiciona para nada
          // (verificado em `_application_transition_allowed`). Sem este aviso,
          // um toque errado congelava o card — o chip ficava vazio e não havia
          // como corrigir. Achado P2-20, parte que a correção anterior criou.
          if (_status.isTerminal) ...[
            const SizedBox(height: 8),
            Text(
              '"${_status.label}" encerra o acompanhamento — depois não dá pra '
              'mudar o status desta candidatura.',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _submit,
              child: const Text('Adicionar',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? error, TextInputType? keyboardType}) {
    return TextField(
      controller: c,
      keyboardType: keyboardType,
      onChanged: (_) {
        if (_attempted) setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
    );
  }
}
