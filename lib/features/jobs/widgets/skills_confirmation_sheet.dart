import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../auth/user_viewmodel.dart';
import '../../../services/ai_service.dart';
import '../../../services/analytics_service.dart';
import '../models/job.dart';
import '../models/job_skills_extraction.dart';
import '../../../core/theme/theme.dart';

/// Bottom sheet que aparece ANTES da adaptação de CV.
///
/// Lista skills extraídas da vaga e permite que o user confirme habilidades
/// que tem na vida real mas esqueceu de colocar no CV. Skills confirmadas
/// vão para `extra_skills` em `adapt-resume-to-job` — a IA inclui no CV
/// adaptado sem ser rejeitada pelo validator anti-invenção.
///
/// Retorna via `Navigator.pop`:
/// - `List<String>` com as skills confirmadas (pode ser vazio se user pulou)
/// - `null` se user fechou o sheet sem decidir (drag down) → caller deve abortar
///
/// Estados internos:
/// - `loading`: chamando `extract-job-skills`
/// - `error`/`empty`: pop automático com lista vazia (skip silencioso)
/// - `ready`: render normal com chips
class SkillsConfirmationSheet extends StatefulWidget {
  final Job job;

  const SkillsConfirmationSheet({super.key, required this.job});

  @override
  State<SkillsConfirmationSheet> createState() =>
      _SkillsConfirmationSheetState();
}

class _SkillsConfirmationSheetState extends State<SkillsConfirmationSheet> {
  // ── Paleta (espelha a do resume_adaptation_sheet) ────────────────────
  static const _indigo = AppColors.primary;
  static const _purple = AppColors.primary;
  static const _emerald = AppColors.success;
  static const _textPrimary = AppColors.textPrimary;
  static const _textSecondary = AppColors.textSecondary;
  static const _textMuted = AppColors.textTertiary;
  static const _border = AppColors.border;
  static const _surfaceSoft = AppColors.surfaceMuted;
  static const _surfaceGreen = AppColors.successSoft;

  final AIService _ai = AIService();

  JobSkillsExtraction? _extraction;
  bool _loading = true;
  Object? _error;

  /// Set normalizado (lowercase) das skills marcadas. Usa o `name` original
  /// como source-of-truth — preservamos capitalização ao enviar.
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _ai.extractJobSkills(widget.job.id);
      if (!mounted) return;

      // O flag `in_cv` vem de `extract-job-skills`, que só cruza as fontes
      // LEGADAS — skills gravadas em `profile_skills` não contam. Efeito na
      // tela: alguém cadastrava Excel, Power BI e Python e, cinco minutos
      // depois, a folha perguntava "marque o que você tem mas não escreveu no
      // CV" oferecendo Excel, Power BI e Python.
      // Revisão UX 28/07, achado P2-19 (D2 no backlog).
      //
      // Aqui reforçamos no cliente com o que o app JÁ sabe do perfil. A
      // causa-raiz continua no servidor; isto tira o absurdo da frente da
      // pessoa sem esperar aquele deploy.
      final result = raw.markingAsInCv(
        context.read<UserViewModel>().profileSkillNames,
      );

      Analytics.shared.skillsConfirmationOpened(
        jobId: widget.job.id,
        totalSkills: result.total,
        missingFromCv: result.missingSkills.length,
      );

      // Auto-skip: sem skills extraídas OU todas já no CV.
      if (result.shouldSkip) {
        Analytics.shared.skillsConfirmationAutoSkipped(
          jobId: widget.job.id,
          reason: result.skills.isEmpty ? 'no_requirements' : 'all_in_cv',
        );
        if (mounted) Navigator.pop(context, <String>[]);
        return;
      }

      // Pre-seleção: skills missing que já vieram confirmadas antes.
      for (final s in result.preConfirmedMissing) {
        _selected.add(s.name);
      }

      setState(() {
        _extraction = result;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // Erro = skip silencioso. Sheet de adaptação assume o controle e tudo
      // funciona como antes da feature existir (sem confirmação prévia).
      Analytics.shared.skillsConfirmationAutoSkipped(
        jobId: widget.job.id,
        reason: 'extraction_failed',
      );
      Navigator.pop(context, <String>[]);
    }
  }

  void _toggle(String name) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(name)) {
        _selected.remove(name);
      } else {
        _selected.add(name);
      }
    });
  }

  void _onSkip() {
    HapticFeedback.lightImpact();
    Analytics.shared.skillsConfirmationCompleted(
      jobId: widget.job.id,
      confirmed: 0,
      skipped: true,
    );
    Navigator.pop(context, <String>[]);
  }

  void _onConfirm() {
    HapticFeedback.mediumImpact();
    final list = _selected.toList(growable: false);
    Analytics.shared.skillsConfirmationCompleted(
      jobId: widget.job.id,
      confirmed: list.length,
      skipped: false,
    );
    Navigator.pop(context, list);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHandle(),
                _buildHeader(),
                Expanded(child: _buildBody(scrollController)),
                if (!_loading && _extraction != null) _buildFooter(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.borderStrong,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Algo que esqueceu de mencionar?',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'A IA não inventa. Diga o que sabe mas ficou de fora do CV — '
                  'eu incluo na versão adaptada.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: _textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 22),
            color: _textMuted,
            onPressed: () => Navigator.pop(context, null),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController controller) {
    if (_loading) return _buildLoading();
    if (_error != null) return const SizedBox.shrink();

    final ext = _extraction!;
    final inCv = ext.inCvSkills;
    final missing = ext.missingSkills;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      children: [
        if (inCv.isNotEmpty) ...[
          _buildSectionLabel(
            'Já no seu CV',
            'Estas a vaga pede e você já tem.',
            Icons.check_circle_rounded,
            _emerald,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: inCv.map((s) => _InCvChip(label: s.name)).toList(),
          ),
          const SizedBox(height: 22),
        ],
        if (missing.isNotEmpty) ...[
          _buildSectionLabel(
            'A vaga também pede',
            'Marque o que você tem mas não escreveu no CV.',
            Icons.add_circle_outline_rounded,
            _indigo,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: missing.map((s) {
              final selected = _selected.contains(s.name);
              return _SelectableSkillChip(
                label: s.name,
                selected: selected,
                preConfirmed: s.preConfirmed,
                onTap: () => _toggle(s.name),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          if (missing.any((s) => s.preConfirmed))
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Skills com ✓ você já confirmou em outras vagas — desmarque '
                'se preferir não incluir desta vez.',
                style: TextStyle(
                  fontSize: 12,
                  color: _textMuted,
                  height: 1.35,
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _indigo,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Lendo a vaga…',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(6, (_) => const _SkeletonChip()),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(
    String title,
    String hint,
    IconData icon,
    Color iconColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: _textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final n = _selected.length;
    final hasSelection = n > 0;
    final ctaLabel = !hasSelection
        ? 'Adaptar como está'
        : (n == 1 ? 'Adaptar com 1 habilidade' : 'Adaptar com $n habilidades');

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border, width: 1)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _onSkip,
            style: TextButton.styleFrom(
              foregroundColor: _textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Pular'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_indigo, _purple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _indigo.withOpacity(hasSelection ? 0.38 : 0.22),
                    blurRadius: hasSelection ? 14 : 8,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _onConfirm,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            ctaLabel,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ),
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

// ────────────────────────────────────────────────────────────────────────────
// Chips
// ────────────────────────────────────────────────────────────────────────────

/// Chip read-only verde — skill que já está no CV.
class _InCvChip extends StatelessWidget {
  final String label;
  const _InCvChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _SkillsConfirmationSheetState._surfaceGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _SkillsConfirmationSheetState._emerald.withOpacity(0.3),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_rounded,
            size: 14,
            color: _SkillsConfirmationSheetState._emerald,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _SkillsConfirmationSheetState._emerald,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip selecionável (skill que NÃO está no CV). User tap = "eu tenho isso".
class _SelectableSkillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool preConfirmed;
  final VoidCallback onTap;

  const _SelectableSkillChip({
    required this.label,
    required this.selected,
    required this.preConfirmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [
                    _SkillsConfirmationSheetState._indigo,
                    _SkillsConfirmationSheetState._purple,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : _SkillsConfirmationSheetState._surfaceSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : _SkillsConfirmationSheetState._border,
            width: 1.2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _SkillsConfirmationSheetState._indigo
                        .withOpacity(0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (preConfirmed && !selected) ...[
              const Icon(
                Icons.history_rounded,
                size: 13,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? Colors.white
                    : AppColors.textPrimary,
                letterSpacing: -0.1,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_rounded, size: 15, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}

/// Skeleton chip cinza pra loading state.
class _SkeletonChip extends StatelessWidget {
  const _SkeletonChip();

  @override
  Widget build(BuildContext context) {
    // Largura variável pra parecer real
    final widths = [70.0, 90.0, 56.0, 110.0, 78.0, 64.0];
    final w = widths[(hashCode % widths.length).abs()];
    return Container(
      width: w,
      height: 34,
      decoration: BoxDecoration(
        color: _SkillsConfirmationSheetState._surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _SkillsConfirmationSheetState._border,
          width: 1.2,
        ),
      ),
    );
  }
}
