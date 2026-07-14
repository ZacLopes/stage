// PendingUploadBanner — banner não-bloqueante exibido no topo da HomeScreen
// quando o user tem um PDF que falhou de subir pro Storage durante o
// onboarding (ver PendingResumeUploadService).
//
// Comportamento:
//   - Polla o service quando monta E quando o user muda (UserViewModel).
//   - Se há pending: mostra banner com "Tentar agora" + "Dispensar".
//   - "Tentar agora" → lê bytes locais + chama saveResume. Sucesso = banner
//     some pra sempre. Falha = snackbar vermelho + banner continua.
//   - "Dispensar" → esconde só nesta sessão (flag em memória). Próxima
//     abertura volta a mostrar, pois o pending ainda existe.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart' show SavedResumeSource;
import '../../../services/pending_resume_upload_service.dart';
import '../../auth/user_viewmodel.dart';
import '../../profile/profile_viewmodel.dart';

class PendingUploadBanner extends StatefulWidget {
  const PendingUploadBanner({super.key});

  @override
  State<PendingUploadBanner> createState() => _PendingUploadBannerState();
}

class _PendingUploadBannerState extends State<PendingUploadBanner> {
  PendingUploadInfo? _info;
  bool _checking = true;
  bool _retrying = false;
  bool _dismissedThisSession = false;
  String? _watchedUserId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    _watchedUserId = userId;
    if (userId == null) {
      setState(() {
        _info = null;
        _checking = false;
      });
      return;
    }
    final info = await PendingResumeUploadService.shared.getPendingInfo(userId);
    if (!mounted) return;
    setState(() {
      _info = info;
      _checking = false;
    });
  }

  Future<void> _retry() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    // Captura o ViewModel ANTES dos awaits — context pode invalidar.
    final profileVm = context.read<ProfileViewModel>();
    setState(() => _retrying = true);
    HapticFeedback.lightImpact();

    final svc = PendingResumeUploadService.shared;
    final bytes = await svc.loadPendingBytes(userId);
    if (bytes == null) {
      // Arquivo sumiu — banner não tem o que oferecer. Limpa estado.
      if (mounted) {
        setState(() {
          _info = null;
          _retrying = false;
        });
      }
      return;
    }

    try {
      final title = await profileVm.resolveUniqueTitle('Meu Currículo');
      await profileVm.saveResume(
        title,
        bytes,
        source: SavedResumeSource.imported,
      );
      await svc.clear(userId);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      AppSnackBar.success(context, 'Arquivo importado salvo!');
      setState(() {
        _info = null;
        _retrying = false;
      });
    } catch (e) {
      await svc.recordFailure(userId: userId, error: e.toString());
      if (!mounted) return;
      AppSnackBar.error(
        context,
        'Não consegui salvar. Tenta de novo daqui a pouco.',
      );
      _refresh(); // recarrega contador de tentativas
      setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-checa quando o user muda (login/logout/troca de conta).
    final user = context.watch<UserViewModel>().user;
    if (user?.id != _watchedUserId) {
      _watchedUserId = user?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }

    if (_checking || _info == null || _dismissedThisSession) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.md,
        AppSpacing.base,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Não conseguimos salvar seu arquivo',
                      style: AppTextStyles.labelLg.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A análise foi feita, mas o arquivo original ainda não foi salvo como fonte do seu perfil.',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _retrying
                    ? null
                    : () => setState(() => _dismissedThisSession = true),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                tooltip: 'Dispensar',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton(
                onPressed: _retrying ? null : _retry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: AppColors.textOnDark,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base + 2,
                    vertical: AppSpacing.sm + 2,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.brPill,
                  ),
                ),
                child: _retrying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textOnDark,
                        ),
                      )
                    : Text(
                        'Tentar agora',
                        style: AppTextStyles.labelMd.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textOnDark,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
