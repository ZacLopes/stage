import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/stage_colors.dart';

/// Widget de edição inline para um campo do CV adaptado. Usado dentro de
/// [AdaptedResumePreviewScreen] (F1 da reformulação).
///
/// Comportamento:
/// - Estado padrão: mostra `value` como texto (Outfit/Inter conforme tipo).
///   Tap em qualquer parte coloca em modo edição.
/// - Modo edição: TextField inline. Tap fora ou Enter (single-line) confirma.
/// - Se valor atual != original: mostra chip "Mudou" + tap nele exibe
///   diff e botão "Voltar ao original".
/// - Notifica caller via `onChanged` apenas quando o valor efetivamente muda.
///
/// Reutilizável para: summary, location, phone, role, company, period,
/// description (bullets), etc. Para listas (skills, achievements, interests)
/// use [ResumeListEditor] abaixo.
class ResumeBlockEditor extends StatefulWidget {
  /// Valor atual (pode ser igual ou diferente do original).
  final String value;

  /// Valor que veio da IA antes de qualquer edição do usuário. Usado para
  /// detectar "modificado" e oferecer "voltar ao original".
  final String original;

  /// Label opcional acima do campo (ex: "Resumo profissional").
  final String? label;

  /// Estilo do texto quando NÃO está editando.
  final TextStyle? textStyle;

  /// Hint pro modo edição.
  final String? hint;

  /// Aceita múltiplas linhas (descrições, bullets).
  final bool multiline;

  /// Texto disabled (não editável). Usado pra campos imutáveis no preview.
  final bool readOnly;

  /// Limite máximo de caracteres (apenas guardrail visual).
  final int? maxLength;

  /// Disparado quando o valor muda (com debounce de fim de edição).
  final ValueChanged<String> onChanged;

  /// Disparado quando o user clica em "Voltar ao original". Recebe o valor
  /// original — caller deve atualizar o state externo.
  final VoidCallback? onRestoreOriginal;

  const ResumeBlockEditor({
    super.key,
    required this.value,
    required this.original,
    required this.onChanged,
    this.label,
    this.textStyle,
    this.hint,
    this.multiline = false,
    this.readOnly = false,
    this.maxLength,
    this.onRestoreOriginal,
  });

  @override
  State<ResumeBlockEditor> createState() => _ResumeBlockEditorState();
}

class _ResumeBlockEditorState extends State<ResumeBlockEditor> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _editing = false;
  bool _diffExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant ResumeBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Caller pode forçar update externo (ex: restore original).
    if (!_editing && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _editing) {
      _commit();
    }
  }

  void _commit() {
    final newValue = _controller.text.trim();
    setState(() => _editing = false);
    if (newValue != widget.value) {
      widget.onChanged(newValue);
    }
  }

  void _startEditing() {
    if (widget.readOnly) return;
    HapticFeedback.selectionClick();
    setState(() => _editing = true);
    // Aguarda 1 frame para o TextField ser construído antes de pedir foco.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  bool get _isModified => widget.value != widget.original;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Row(
            children: [
              Text(
                widget.label!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: Color(0xFF6B7280),
                ),
              ),
              if (_isModified) ...[
                const SizedBox(width: 8),
                _ModifiedChip(
                  expanded: _diffExpanded,
                  onTap: () => setState(() => _diffExpanded = !_diffExpanded),
                  onRestore: widget.onRestoreOriginal,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
        ],
        if (_isModified && _diffExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _DiffViewer(before: widget.original, after: widget.value),
          ),
        _editing ? _buildEditor() : _buildDisplay(),
      ],
    );
  }

  Widget _buildDisplay() {
    final display = widget.value.isEmpty
        ? (widget.hint ?? 'Tocar para adicionar')
        : widget.value;
    final isEmpty = widget.value.isEmpty;
    return GestureDetector(
      onTap: _startEditing,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: widget.readOnly ? Colors.transparent : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
        ),
        child: Text(
          display,
          style: (widget.textStyle ??
                  const TextStyle(fontSize: 14, height: 1.4))
              .copyWith(
            color: isEmpty
                ? const Color(0xFF9CA3AF)
                : (widget.textStyle?.color ?? const Color(0xFF111827)),
            fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: widget.multiline ? null : 1,
      maxLength: widget.maxLength,
      textInputAction:
          widget.multiline ? TextInputAction.newline : TextInputAction.done,
      style: widget.textStyle ?? const TextStyle(fontSize: 14, height: 1.4),
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: widget.hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: StageColors.brandCyan, width: 1.5),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: StageColors.brandCyan, width: 2),
        ),
      ),
    );
  }
}

class _ModifiedChip extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onRestore;

  const _ModifiedChip({
    required this.expanded,
    required this.onTap,
    this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: StageColors.brandCyan.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: StageColors.brandCyan.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                expanded ? Icons.expand_less_rounded : Icons.edit_rounded,
                size: 11,
                color: StageColors.brandCyan,
              ),
              const SizedBox(width: 3),
              const Text(
                'Mudou',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: StageColors.brandCyan,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiffViewer extends StatelessWidget {
  final String before;
  final String after;

  const _DiffViewer({required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.remove_rounded, size: 12, color: Color(0xFFEF4444)),
              SizedBox(width: 4),
              Text(
                'Original',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFEF4444),
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            before.isEmpty ? '(vazio)' : before,
            style: TextStyle(
              fontSize: 12,
              color: const Color(0xFF6B7280),
              decoration: TextDecoration.lineThrough,
              fontStyle: before.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.add_rounded, size: 12, color: StageColors.brandCyan),
              SizedBox(width: 4),
              Text(
                'Atual',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: StageColors.brandCyan,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            after.isEmpty ? '(vazio)' : after,
            style: TextStyle(
              fontSize: 12,
              color: const Color(0xFF111827),
              fontStyle: after.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Editor de lista de strings (skills, achievements, interests). Mostra como
/// chips; tap em chip → editar inline; chip "+" no fim → adicionar novo.
class ResumeListEditor extends StatefulWidget {
  final List<String> value;
  final List<String> original;
  final String label;
  final String addHint;
  final ValueChanged<List<String>> onChanged;
  final VoidCallback? onRestoreOriginal;

  const ResumeListEditor({
    super.key,
    required this.value,
    required this.original,
    required this.label,
    required this.onChanged,
    this.addHint = 'Adicionar',
    this.onRestoreOriginal,
  });

  @override
  State<ResumeListEditor> createState() => _ResumeListEditorState();
}

class _ResumeListEditorState extends State<ResumeListEditor> {
  bool _diffExpanded = false;
  // Convenção:
  //   -1  = idle (nada editando — estado inicial)
  //   null = adicionando novo item (mostra TextField com autofocus)
  //   >= 0 = editando item existente nessa posição
  // Estado inicial DEVE ser -1, NÃO null. Antes o default do Dart era null,
  // que casava com "adicionando novo" e abria o teclado automaticamente ao
  // entrar na preview screen.
  int? _editingIndex = -1;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isModified {
    if (widget.value.length != widget.original.length) return true;
    for (var i = 0; i < widget.value.length; i++) {
      if (widget.value[i] != widget.original[i]) return true;
    }
    return false;
  }

  void _startEdit(int? index) {
    HapticFeedback.selectionClick();
    setState(() {
      _editingIndex = index;
      _controller.text = index != null ? widget.value[index] : '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _commit() {
    // Guard: estado idle (-1) não tem item nem add em curso. Esse caller
    // chega quando o TextField perde foco sem o user ter aberto edição
    // de fato (ex: tap fora). Sem o guard, removeAt(-1) crashava com
    // RangeError.
    if (_editingIndex == -1) return;
    final newText = _controller.text.trim();
    final next = List<String>.from(widget.value);
    if (_editingIndex == null) {
      if (newText.isNotEmpty) next.add(newText);
    } else {
      final idx = _editingIndex!;
      if (idx < 0 || idx >= next.length) {
        // Index inválido (estado inconsistente) — só sai do modo edição
        // sem mutar a lista. Defensivo.
        setState(() => _editingIndex = -1);
        return;
      }
      if (newText.isEmpty) {
        next.removeAt(idx);
      } else {
        next[idx] = newText;
      }
    }
    setState(() => _editingIndex = -1);
    widget.onChanged(next);
  }

  void _remove(int index) {
    HapticFeedback.lightImpact();
    final next = List<String>.from(widget.value)..removeAt(index);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final editing = _editingIndex != null && _editingIndex != -1;
    final adding = _editingIndex == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Color(0xFF6B7280),
              ),
            ),
            if (_isModified) ...[
              const SizedBox(width: 8),
              _ModifiedChip(
                expanded: _diffExpanded,
                onTap: () => setState(() => _diffExpanded = !_diffExpanded),
                onRestore: widget.onRestoreOriginal,
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (_isModified && _diffExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _DiffViewer(
              before: widget.original.join(' · '),
              after: widget.value.join(' · '),
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...List.generate(widget.value.length, (i) {
              if (editing && _editingIndex == i) {
                return _buildInlineField();
              }
              return _Chip(
                label: widget.value[i],
                onTap: () => _startEdit(i),
                onRemove: () => _remove(i),
              );
            }),
            if (adding) _buildInlineField() else _AddChip(onTap: () => _startEdit(null)),
          ],
        ),
        if (_isModified && widget.onRestoreOriginal != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onRestoreOriginal,
              icon: const Icon(Icons.undo_rounded, size: 14),
              label: const Text(
                'Voltar ao original',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: StageColors.brandCyan,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 28),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInlineField() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 240),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        textInputAction: TextInputAction.done,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.addHint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: StageColors.brandCyan, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: StageColors.brandCyan, width: 2),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _Chip({required this.label, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: ConstrainedBox(
          // Skills/conquistas/interesses podem ser textos longos ("Domínio
          // do Pacote Office (Excel avançado, PowerPoint, Word)"). Cap em
          // 280px e trunca com ellipsis pra evitar overflow do Wrap parent.
          constraints: const BoxConstraints(maxWidth: 280),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 14, color: Color(0xFF6B7280)),
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

class _AddChip extends StatelessWidget {
  final VoidCallback onTap;

  const _AddChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: StageColors.brandCyan.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: StageColors.brandCyan.withOpacity(0.3),
              style: BorderStyle.solid,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 14, color: StageColors.brandCyan),
              SizedBox(width: 3),
              Text(
                'Adicionar',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: StageColors.brandCyan,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
