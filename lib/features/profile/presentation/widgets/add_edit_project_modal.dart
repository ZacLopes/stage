// AddEditProjectModal — bottom sheet pra criar/editar Project.
//
// Campos pensados pra dar conta da variedade de projetos (tech, acadêmico,
// voluntariado, side hustle, evento universitário, criativo):
// - Nome (req)
// - Sua função (role) — qual papel você teve
// - Contexto (context) — onde rolou (universidade, hackathon, pessoal, etc.)
// - Período + em andamento
// - Link (URL única — GitHub, site, vídeo, doc, deck)
// - Resultados e responsabilidades — bullets como em experiência
//
// Bullets são gerenciados em estado local e enviados como ProjectBullet list
// no entity Project; o repository faz delete + re-insert.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../gamification/widgets/month_year_picker_sheet.dart';
import '../../domain/entities/entities.dart';

const _kBorderColor = Color(0xFFE5E7EB);
const _kLabelColor = Color(0xFF6B7280);
const _kHintColor = Color(0xFF9CA3AF);
const _kTextColor = Color(0xFF111827);
const _kAccent = Color(0xFF00C27A);
const _kError = Color(0xFFEF4444);
const _kErrorBg = Color(0xFFFEE2E2);

class AddEditProjectModal extends StatefulWidget {
  final Project? initial;
  final void Function(Project) onSave;
  final void Function()? onDelete;

  const AddEditProjectModal({
    super.key,
    this.initial,
    required this.onSave,
    this.onDelete,
  });

  static Future<void> show({
    required BuildContext context,
    Project? initial,
    required void Function(Project) onSave,
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
      builder: (_) => AddEditProjectModal(
        initial: initial,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<AddEditProjectModal> createState() => _AddEditProjectModalState();
}

class _AddEditProjectModalState extends State<AddEditProjectModal> {
  late final TextEditingController _name;
  late final TextEditingController _role;
  late final TextEditingController _context;
  late final TextEditingController _website;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isCurrent = false;
  late List<String> _bullets;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.name ?? '');
    _role = TextEditingController(text: i?.role ?? '');
    _context = TextEditingController(text: i?.context ?? '');
    _website = TextEditingController(text: i?.website ?? '');
    _startDate = i?.startDate;
    _endDate = i?.endDate;
    _isCurrent = i?.isCurrent ?? false;
    _bullets = i?.bullets.map((b) => b.text).toList() ?? <String>[];
    // Compat: se tinha description legada, vira primeiro bullet automaticamente
    // quando o user abre pra editar.
    if (_bullets.isEmpty && (i?.description?.trim().isNotEmpty ?? false)) {
      _bullets = [i!.description!.trim()];
    }
    _name.addListener(() => setState(() {}));
    _role.addListener(() => setState(() {}));
    _context.addListener(() => setState(() {}));
    _website.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _context.dispose();
    _website.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  Future<void> _pickStart() async {
    FocusScope.of(context).unfocus();
    final r = await showMonthYearPickerSheet(context: context, initialDate: _startDate ?? DateTime.now());
    if (r != null) setState(() => _startDate = r);
  }

  Future<void> _pickEnd() async {
    if (_isCurrent) return;
    FocusScope.of(context).unfocus();
    final r = await showMonthYearPickerSheet(context: context, initialDate: _endDate ?? DateTime.now());
    if (r != null) setState(() => _endDate = r);
  }

  Future<void> _addBullet() async {
    final result = await _EditBulletSheet.show(context: context, initial: '');
    if (result != null && result.trim().isNotEmpty) {
      setState(() => _bullets.add(result.trim()));
    }
  }

  Future<void> _editBullet(int index) async {
    final result = await _EditBulletSheet.show(context: context, initial: _bullets[index]);
    if (result != null) {
      final v = result.trim();
      setState(() {
        if (v.isEmpty) {
          _bullets.removeAt(index);
        } else {
          _bullets[index] = v;
        }
      });
    }
  }

  void _removeBullet(int index) {
    setState(() => _bullets.removeAt(index));
  }

  void _handleSave() {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = widget.initial ?? Project(id: '', userId: userId, name: '');
    final bullets = _bullets
        .where((t) => t.trim().isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((e) => ProjectBullet(
              id: 'temp_${e.key}',
              projectId: base.id,
              text: e.value.trim(),
              orderIndex: e.key,
            ))
        .toList();
    final updated = base.copyWith(
      name: _name.text.trim(),
      role: _role.text.trim().isEmpty ? null : _role.text.trim(),
      context: _context.text.trim().isEmpty ? null : _context.text.trim(),
      website: _website.text.trim().isEmpty ? null : _website.text.trim(),
      // Quando o user migra bullets, zera o description legado.
      description: bullets.isNotEmpty ? null : (base.description),
      startDate: _startDate,
      endDate: _isCurrent ? null : _endDate,
      isCurrent: _isCurrent,
      bullets: bullets,
    );
    widget.onSave(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _UnderlineField(
                        controller: _name,
                        label: 'Nome do projeto',
                        required: true,
                        capitalize: true,
                        hintText: 'Ex: Aplicativo de doações, Festival universitário',
                      ),
                      const SizedBox(height: 20),
                      _UnderlineField(
                        controller: _role,
                        label: 'Sua função',
                        capitalize: true,
                        hintText: 'Ex: Fundador, Líder técnico, Voluntário',
                      ),
                      const SizedBox(height: 20),
                      _UnderlineField(
                        controller: _context,
                        label: 'Contexto',
                        capitalize: true,
                        hintText: 'Ex: Empresa Júnior, Hackathon, Pessoal',
                      ),
                      const SizedBox(height: 20),
                      _UnderlineField(
                        controller: _website,
                        label: 'Link',
                        hintText: 'GitHub, site, vídeo, deck...',
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _DateField(label: 'Início', value: _startDate, onTap: _pickStart)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Opacity(
                              opacity: _isCurrent ? 0.4 : 1,
                              child: _DateField(label: 'Fim', value: _endDate, onTap: _pickEnd),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _CheckboxRow(
                        value: _isCurrent,
                        label: 'Em andamento',
                        onChanged: (v) => setState(() {
                          _isCurrent = v;
                          if (_isCurrent) _endDate = null;
                        }),
                      ),
                      const SizedBox(height: 24),
                      const _FieldLabel(text: 'Resultados e responsabilidades'),
                      const SizedBox(height: 4),
                      const Text(
                        'O que você fez? Que impacto teve? Bullets concretos pesam mais.',
                        style: TextStyle(fontSize: 12, color: _kLabelColor),
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(_bullets.length, (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _BulletCard(
                              text: _bullets[i],
                              onRemove: () => _removeBullet(i),
                              onEdit: () => _editBullet(i),
                            ),
                          )),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addBullet,
                          icon: const Icon(Icons.add_rounded, color: _kAccent, size: 22),
                          label: const Text(
                            'Adicionar item',
                            style: TextStyle(color: _kAccent, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: const Text('Salvar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
              widget.initial == null ? 'Adicionar projeto' : 'Editar projeto',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kTextColor),
            ),
          ),
        ),
        if (widget.onDelete != null)
          _CircleIconButton(
            icon: Icons.delete_outline_rounded,
            color: _kError,
            onTap: () { widget.onDelete!(); Navigator.of(context).pop(); },
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

  const _CircleIconButton({required this.icon, required this.color, required this.onTap});

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
        style: const TextStyle(fontSize: 13, color: _kLabelColor, fontWeight: FontWeight.w500),
        children: [
          if (required)
            const TextSpan(text: ' *', style: TextStyle(color: _kError, fontWeight: FontWeight.w700)),
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
          textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _kTextColor),
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            hintStyle: const TextStyle(color: _kHintColor, fontWeight: FontWeight.w500, fontSize: 15),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: controller.text.isEmpty
                ? null
                : GestureDetector(
                    onTap: () => controller.clear(),
                    child: const Icon(Icons.cancel, color: _kHintColor, size: 20),
                  ),
            suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _kBorderColor)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _kAccent, width: 1.5)),
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

  const _DateField({required this.label, required this.value, required this.onTap});

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
                const Icon(Icons.calendar_today_outlined, color: _kHintColor, size: 18),
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
                const Icon(Icons.keyboard_arrow_down_rounded, color: _kHintColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }
}

class _CheckboxRow extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  const _CheckboxRow({required this.value, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: value ? _kAccent : Colors.white,
                border: Border.all(color: value ? _kAccent : _kBorderColor, width: 1.5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: value ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null,
            ),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 15, color: _kTextColor)),
          ],
        ),
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  final String text;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  const _BulletCard({required this.text, required this.onRemove, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onRemove,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 28, height: 28,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: _kErrorBg),
            child: const Icon(Icons.close_rounded, color: _kError, size: 18),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                border: Border.all(color: _kBorderColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, color: _kTextColor, height: 1.4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_outlined, color: _kLabelColor, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditBulletSheet extends StatefulWidget {
  final String initial;
  final bool isNew;

  const _EditBulletSheet({required this.initial, required this.isNew});

  static Future<String?> show({
    required BuildContext context,
    required String initial,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditBulletSheet(initial: initial, isNew: initial.isEmpty),
    );
  }

  @override
  State<_EditBulletSheet> createState() => _EditBulletSheetState();
}

class _EditBulletSheetState extends State<_EditBulletSheet> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSave => _controller.text.trim().isNotEmpty;

  void _done() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _CircleIconButton(
                    icon: Icons.close_rounded,
                    color: _kTextColor,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.isNew ? 'Adicionar item' : 'Editar item',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kTextColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 24),
              const _FieldLabel(text: 'Descrição'),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                focusNode: _focus,
                maxLines: 8,
                minLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 15, color: _kTextColor, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'Ex: Liderei equipe de 4 pessoas para entregar MVP em 3 meses, captando 500 usuários no primeiro mês',
                  hintStyle: const TextStyle(color: _kHintColor),
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kAccent, width: 1.5),
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _canSave ? _done : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _kAccent.withValues(alpha: 0.4),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: const Text('Concluir', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
