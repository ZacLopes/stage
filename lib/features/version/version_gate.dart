import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/theme.dart';
import '../../services/version_service.dart';

/// Envolve o app e bloqueia o uso quando a versão instalada é menor que a
/// `min_supported_version` definida no Supabase (`app_config`). Sem conexão
/// ou se a tabela retornar erro, libera (fail-open) — gate é best-effort.
class VersionGate extends StatefulWidget {
  final Widget child;
  const VersionGate({super.key, required this.child});

  @override
  State<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<VersionGate> {
  late Future<VersionCheckResult> _future;

  @override
  void initState() {
    super.initState();
    _future = VersionService().check();
  }

  void _retry() {
    setState(() {
      _future = VersionService().check();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VersionCheckResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.child;
        }
        final result = snapshot.data;
        if (result != null && result.updateRequired && result.config != null) {
          return _ForceUpdateScreen(
            config: result.config!,
            currentVersion: result.currentVersion,
            onRetry: _retry,
          );
        }
        return widget.child;
      },
    );
  }
}

class _ForceUpdateScreen extends StatelessWidget {
  final AppVersionConfig config;
  final String currentVersion;
  final VoidCallback onRetry;

  const _ForceUpdateScreen({
    required this.config,
    required this.currentVersion,
    required this.onRetry,
  });

  Future<void> _openStore(BuildContext context) async {
    final url = config.storeUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppGradients.brand),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Atualização necessária',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Outfit', 
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    config.updateMessage?.trim().isNotEmpty == true
                        ? config.updateMessage!
                        : 'Uma nova versão do Stage está disponível com melhorias e correções importantes. Atualize para continuar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: 15,
                      height: 1.5,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sua versão: $currentVersion · Mínima: ${config.minSupportedVersion}',
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.65),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () => _openStore(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.brandBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Atualizar agora',
                        style: TextStyle(fontFamily: 'Outfit', 
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onRetry,
                    child: Text(
                      'Já atualizei',
                      style: TextStyle(fontFamily: 'Inter', 
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.85),
                      ),
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
}
