import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme.dart';
import '../jobs_viewmodel.dart';

/// FASE 2 (T2.3): sheet "Pedir uma empresa" — aparece nos estados de
/// exaustão do feed (fim das relevantes). Insere em `company_requests`
/// (own-insert via RLS) e emite `company_requested` (R7). O pedido vai
/// pro admin dashboard (aba Pedidos) e alimenta a prospecção B2B.
class CompanyRequestSheet extends StatefulWidget {
  const CompanyRequestSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ChangeNotifierProvider.value(
        // O sheet roda em outra rota — repassa o VM da aba Vagas.
        value: context.read<JobsViewModel>(),
        child: const CompanyRequestSheet(),
      ),
    );
  }

  @override
  State<CompanyRequestSheet> createState() => _CompanyRequestSheetState();
}

class _CompanyRequestSheetState extends State<CompanyRequestSheet> {
  final TextEditingController _company = TextEditingController();
  final TextEditingController _note = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _company.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _company.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Conta pra gente qual empresa você quer ver aqui.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final ok = await context
        .read<JobsViewModel>()
        .submitCompanyRequest(name, _note.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido enviado! Vamos atrás dessa empresa. 💙'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() {
        _sending = false;
        _error = 'Não deu pra enviar agora. Tenta de novo?';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Pedir uma empresa',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Qual empresa você queria ver contratando por aqui? '
            'A gente usa os pedidos pra priorizar quem trazer.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _company,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Empresa',
              hintText: 'Ex.: Nubank, Embraer, iFood…',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            maxLength: 280,
            decoration: const InputDecoration(
              labelText: 'Por quê? (opcional)',
              hintText: 'Área, vaga dos sonhos, alguma referência…',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Enviar pedido',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
