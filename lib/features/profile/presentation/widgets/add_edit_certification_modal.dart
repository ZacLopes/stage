// AddEditCertificationModal — bottom sheet pra criar/editar Certification.
//
// Por que este arquivo existe (auditoria de 27/07):
// A seção "Certificações" era a única lista do editor SEM modal próprio. Ela
// usava o `EditListModal` genérico, que só sabe lidar com texto solto: mostrava
// "Nome - Instituição - Ano" numa linha e, ao salvar, apagava TODAS as
// certificações e regravava cada linha inteira no campo `name`, com `issuer` e
// `date` nulos. Ou seja, abrir e salvar sem mudar nada já destruía a estrutura —
// e o nome ficava poluído com a concatenação.
//
// Medido em produção no dia da correção: 392 certificações de 126 pessoas
// tinham instituição ou data a perder, e 19 linhas de 13 pessoas já estavam com
// o nome concatenado e os dois campos vazios.
//
// Campos, deliberadamente poucos (é o que a entidade guarda):
// - Nome (obrigatório)
// - Instituição (opcional)
// - Data (opcional, mês/ano, com "Limpar")

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../../auth/auth_session.dart';
import '../../../gamification/widgets/month_year_picker_sheet.dart';
import '../../domain/entities/entities.dart';
import '../../domain/profile_title.dart';

const _kBorderColor = AppColors.border;
const _kLabelColor = AppColors.textTertiary;
const _kHintColor = AppColors.textDisabled;
const _kTextColor = AppColors.textPrimary;
const _kAccent = AppColors.primary;
const _kError = AppColors.error;

class AddEditCertificationModal extends StatefulWidget {
  final Certification? initial;
  final void Function(Certification) onSave;
  final void Function()? onDelete;

  const AddEditCertificationModal({
    super.key,
    this.initial,
    required this.onSave,
    this.onDelete,
  });

  static Future<void> show({
    required BuildContext context,
    Certification? initial,
    required void Function(Certification) onSave,
    void Function()? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddEditCertificationModal(
        initial: initial,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<AddEditCertificationModal> createState() =>
      _AddEditCertificationModalState();
}

class _AddEditCertificationModalState extends State<AddEditCertificationModal> {
  late final TextEditingController _name;
  late final TextEditingController _issuer;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.name ?? '');
    _issuer = TextEditingController(text: i?.issuer ?? '');
    _date = i?.date;
    _name.addListener(() => setState(() {}));
    _issuer.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _issuer.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final r = await showMonthYearPickerSheet(
      context: context,
      initialDate: _date ?? DateTime.now(),
    );
    if (r != null) setState(() => _date = r);
  }

  void _handleSave() {
    final base = widget.initial;
    // EDITANDO: o dono já vem na própria linha. Ler a sessão aqui não
    // acrescenta garantia nenhuma — quem decide é a RLS no servidor — e só
    // criaria um caminho de falha a mais numa tela cujo bug era justamente
    // perder dado. CRIANDO: aí sim é preciso saber de quem é a certificação.
    final String userId;
    if (base != null) {
      userId = base.userId;
    } else {
      final atual = currentUserIdOrNull();
      if (atual == null) {
        // ignore: unawaited_futures
        handleSessionLost(context);
        return;
      }
      userId = atual;
    }
    final issuer = _issuer.text.trim();
    // Construção DIRETA, não `copyWith`: o `copyWith` da entidade usa `??`, então
    // passar null nele MANTÉM o valor anterior — apagar a instituição ou a data
    // seria silenciosamente ignorado.
    final saved = Certification(
      id: base?.id ?? '',
      userId: userId,
      name: normalizeProfileTitle(_name.text),
      issuer: issuer.isEmpty ? null : issuer,
      date: _date,
      orderIndex: base?.orderIndex ?? 0,
    );
    widget.onSave(saved);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.92,
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _UnderlineField(
                          controller: _name,
                          label: 'Nome do certificado',
                          required: true,
                          capitalize: true,
                          hintText: 'Ex: Excel Avançado, AWS Cloud Practitioner',
                        ),
                        const SizedBox(height: 20),
                        _UnderlineField(
                          controller: _issuer,
                          label: 'Instituição',
                          capitalize: true,
                          hintText: 'Quem emitiu — Ex: FGV, Alura, Google',
                        ),
                        const SizedBox(height: 24),
                        _DateField(
                          label: 'Data de conclusão',
                          value: _date,
                          onTap: _pickDate,
                          onClear:
                              _date == null ? null : () => setState(() => _date = null),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _canSave ? _handleSave : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kAccent.withValues(alpha: 0.4),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      'Salvar',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        _CircleIconButton(
          icon: Icons.close_rounded,
          color: _kTextColor,
          onTap: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Center(
            child: Text(
              widget.initial == null
                  ? 'Adicionar certificação'
                  : 'Editar certificação',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _kTextColor,
              ),
            ),
          ),
        ),
        if (widget.onDelete != null)
          _CircleIconButton(
            icon: Icons.delete_outline_rounded,
            color: _kError,
            onTap: () {
              widget.onDelete!();
              Navigator.of(context).pop();
            },
          )
        else
          const SizedBox(width: 40),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CircleIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _kBorderColor),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _FieldLabel({required this.text, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 13,
          color: _kLabelColor,
          fontWeight: FontWeight.w500,
        ),
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: _kError, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}

class _UnderlineField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final bool capitalize;
  final String? hintText;

  const _UnderlineField({
    required this.controller,
    required this.label,
    this.required = false,
    this.capitalize = false,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label, required: required),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          textCapitalization:
              capitalize ? TextCapitalization.words : TextCapitalization.none,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _kTextColor,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            hintStyle: const TextStyle(
              color: _kHintColor,
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: controller.text.isEmpty
                ? null
                : GestureDetector(
                    onTap: () => controller.clear(),
                    child: const Icon(Icons.cancel,
                        color: _kHintColor, size: 20),
                  ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 24, minHeight: 24),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _kBorderColor),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _kAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  /// Null quando não há data — sem isso, uma data posta por engano (ou vinda de
  /// uma importação errada) ficaria impossível de remover pela UI.
  final VoidCallback? onClear;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorderColor)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    color: _kHintColor, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value == null ? '--/--' : _fmt(value!),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: value == null ? _kHintColor : _kTextColor,
                    ),
                  ),
                ),
                if (onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Limpar',
                        style: TextStyle(
                          fontSize: 13,
                          color: _kAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: _kHintColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    return '$mm/${d.year}';
  }
}
