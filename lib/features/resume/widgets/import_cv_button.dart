import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/cv_import_service.dart';
import '../../../core/theme/theme.dart';

/// Mensagem de sucesso da importação.
///
/// Contrato de linguagem (§2 do handoff): "Currículo" é o documento GERADO
/// pelo Stage — versionável e exportável. O arquivo que a pessoa envia é uma
/// "fonte importada", usada para propor/preencher/validar o perfil. Dizer
/// "Currículo importado!" trocava os dois papéis logo no primeiro contato com
/// o conceito.
///
/// "CV" continua permitido: é como a pessoa chama o arquivo dela, e o contrato
/// não reserva esse termo. Quem muda é o predicado — o arquivo é fonte, não
/// currículo.
String importCvSuccessMessage({required bool textWasUsable}) => textWasUsable
    ? '✓ CV importado como fonte do seu perfil'
    : '✓ CV salvo como fonte, mas não consegui ler o texto. Match score pode ficar limitado.';

/// Botão "Importar CV em PDF" reutilizável. Usa o [CvImportService] e mostra
/// feedback via SnackBar. Em sucesso, chama [onImported] (caller decide se
/// quer recarregar lista, navegar, fechar sheet, etc).
///
/// 3 estilos:
/// - [variant: ImportCvVariant.primary] — botão grande gradient (CTA principal)
/// - [variant: ImportCvVariant.secondary] — outlined, mais discreto
/// - [variant: ImportCvVariant.compact] — tile pequeno pra usar em listas
class ImportCvButton extends StatefulWidget {
  /// Called after a successful import. Receives the new SavedResume id
  /// (when available) so callers can highlight or navigate to it.
  final void Function(String? newResumeId)? onImported;
  final ImportCvVariant variant;
  final String label;

  /// Qual PORTA do app disparou o import ('profile_resumes', 'adapt_sheet'…).
  /// Vai como prop do evento de telemetria. Opcional — sem ele o evento sai
  /// como sempre saiu.
  final String? analyticsSource;

  const ImportCvButton({
    super.key,
    this.onImported,
    this.variant = ImportCvVariant.primary,
    this.label = 'Importar CV em PDF',
    this.analyticsSource,
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

    final result = await CvImportService.pickAndImport(
      context,
      analyticsSource: widget.analyticsSource,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.success) {
      _showSnack(
        importCvSuccessMessage(textWasUsable: result.textWasUsable),
        success: true,
      );
      widget.onImported?.call(result.savedResumeId);
    } else if (result.errorMessage != null) {
      _showSnack(result.errorMessage!, success: false);
    }
    // Cancelado: nenhuma mensagem (user só fechou o picker).
  }

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? AppColors.success : AppColors.error,
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
                  colors: [AppColors.primary, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: _busy ? AppColors.textTertiary : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: _busy
              ? null
              : [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
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
                  color: AppColors.primary,
                ),
              )
            : const Icon(Icons.upload_file_rounded, size: 20),
        label: Text(widget.label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border, width: 1.5),
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
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
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
                : const Icon(Icons.upload_file_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
