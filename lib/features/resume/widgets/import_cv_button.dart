import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/cv_import_service.dart';

/// Botão "Importar CV em PDF" reutilizável. Usa o [CvImportService] e mostra
/// feedback via SnackBar. Em sucesso, chama [onImported] (caller decide se
/// quer recarregar lista, navegar, fechar sheet, etc).
///
/// 3 estilos:
/// - [variant: ImportCvVariant.primary] — botão grande gradient (CTA principal)
/// - [variant: ImportCvVariant.secondary] — outlined, mais discreto
/// - [variant: ImportCvVariant.compact] — tile pequeno pra usar em listas
class ImportCvButton extends StatefulWidget {
  final VoidCallback? onImported;
  final ImportCvVariant variant;
  final String label;

  const ImportCvButton({
    super.key,
    this.onImported,
    this.variant = ImportCvVariant.primary,
    this.label = 'Importar CV em PDF',
  });

  @override
  State<ImportCvButton> createState() => _ImportCvButtonState();
}

enum ImportCvVariant { primary, secondary, compact }

class _ImportCvButtonState extends State<ImportCvButton> {
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);

    final result = await CvImportService.pickAndImport(context);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.success) {
      _showSnack(
        result.textWasUsable
            ? '✓ Currículo importado e texto extraído (${result.extractedTextLength} chars).'
            : '✓ Currículo salvo, mas não consegui ler o texto. Match score pode ficar limitado.',
        success: true,
      );
      widget.onImported?.call();
    } else if (result.errorMessage != null) {
      _showSnack(result.errorMessage!, success: false);
    }
    // Cancelado: nenhuma mensagem (user só fechou o picker).
  }

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? const Color(0xFF10B981) : Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.variant) {
      case ImportCvVariant.primary:
        return _buildPrimary();
      case ImportCvVariant.secondary:
        return _buildSecondary();
      case ImportCvVariant.compact:
        return _buildCompact();
    }
  }

  // ── Variants ─────────────────────────────────────────────────────────────

  Widget _buildPrimary() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: _busy
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: _busy ? const Color(0xFF94A3B8) : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: _busy
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _busy ? null : _onTap,
            child: Center(
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.upload_file_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondary() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _onTap,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF4F46E5),
                ),
              )
            : const Icon(Icons.upload_file_rounded, size: 20),
        label: Text(widget.label),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF4F46E5),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }

  Widget _buildCompact() {
    return InkWell(
      onTap: _busy ? null : _onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_rounded, size: 16, color: Color(0xFF4F46E5)),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
