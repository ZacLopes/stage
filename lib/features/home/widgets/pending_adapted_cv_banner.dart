import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../jobs/pending_adapted_cv_tracker.dart';

/// Banner persistente no topo do Home avisando que o user tem um CV
/// adaptado pra uma vaga específica mas ainda não exportou. Captura o
/// momento mais crítico do funil (F2.5 do plano): 14 usuários adaptaram
/// com sucesso na janela analisada, ~7 não exportaram nada — pura perda.
///
/// Reativo via `context.watch<PendingAdaptedCvTracker>()` — quando o
/// adaptation sheet chama `tracker.markAdapted(...)`, este banner
/// re-renderiza no próximo frame (sem precisar restart do app).
///
/// Tap dispara [onOpen] com o pending. O caller (Home) navega pra aba
/// Vagas e abre a sheet de adaptação pra esse job (já cacheada no
/// servidor → sem custo de IA adicional).
class PendingAdaptedCvBanner extends StatelessWidget {
  final void Function(PendingAdaptedCv pending) onOpen;
  final VoidCallback? onDismiss;

  const PendingAdaptedCvBanner({
    super.key,
    required this.onOpen,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<PendingAdaptedCvTracker>();
    final p = tracker.current;
    if (p == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf_rounded,
              color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seu CV pra ${p.jobTitle} tá pronto',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Inter', 
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.company != null && p.company!.isNotEmpty
                      ? 'Toque pra baixar agora · ${p.company}'
                      : 'Toque pra baixar agora',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Inter', 
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onOpen(p),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Abrir',
                  style: TextStyle(fontFamily: 'Inter', 
                    color: const Color(0xFF4F46E5),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dispensar',
            iconSize: 20,
            padding: const EdgeInsets.only(left: 4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () async {
              await PendingAdaptedCvTracker.shared.clear();
              onDismiss?.call();
            },
          ),
        ],
      ),
    );
  }
}
