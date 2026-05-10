import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/ai_service.dart';
import '../../auth/user_viewmodel.dart';
import '../../resume/pdf_service.dart';
import '../../resume/resume_viewmodel.dart';
import '../models/adapted_resume.dart';
import '../models/job.dart';

/// Bottom sheet que adapta o currículo do usuário pra uma vaga específica
/// usando IA. Mostra diff explicável + botão pra baixar PDF.
///
/// Princípios de UX:
/// - Loading 4-8s → mostra fases ("Lendo vaga...", "Adaptando bullets...")
///   pra latência não parecer travada.
/// - Toda mudança visível ANTES do botão baixar (diff before/after).
/// - Score upgrade animado (gancho emocional).
/// - Fallback gracioso: se IA falhar, oferece abrir CV original.
class ResumeAdaptationSheet extends StatefulWidget {
  final Job job;
  final int? matchScoreFromCard;

  const ResumeAdaptationSheet({
    super.key,
    required this.job,
    this.matchScoreFromCard,
  });

  @override
  State<ResumeAdaptationSheet> createState() => _ResumeAdaptationSheetState();
}

class _ResumeAdaptationSheetState extends State<ResumeAdaptationSheet>
    with TickerProviderStateMixin {
  // ── Cores (alinhadas com jobs_swipe_screen + job_preferences_screen) ─
  static const _indigo = Color(0xFF4F46E5);
  static const _purple = Color(0xFF7C3AED);
  static const _gradient = LinearGradient(
    colors: [_indigo, _purple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const _emerald = Color(0xFF10B981);
  static const _textPrimary = Color(0xFF0F172A);
  static const _textSecondary = Color(0xFF475569);
  static const _textMuted = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);
  static const _surface = Color(0xFFF8FAFC);

  // ── State ──────────────────────────────────────────────────────────
  // AIService instanciado direto aqui (sem Provider) — segue mesmo padrão
  // que `JobsSwipeScreen`. Se virar Provider no futuro, substituir por
  // `context.read<AIService>()`.
  final AIService _aiService = AIService();

  AdaptedResume? _adapted;
  Object? _error;
  bool _isLoading = true;
  bool _isExporting = false;
  bool _retrying = false;

  // Animações
  late final AnimationController _scoreController;
  late final Animation<int> _scoreAnimation;

  // Loading message rotation (pra latência não parecer travada)
  Timer? _loadingMessageTimer;
  int _loadingMessageIndex = 0;
  static const _loadingMessages = [
    'Lendo a descrição da vaga…',
    'Identificando palavras-chave…',
    'Reordenando suas habilidades…',
    'Reformulando bullets pro fit…',
    'Validando que nada foi inventado…',
    'Quase lá, finalizando…',
  ];

  @override
  void initState() {
    super.initState();
    _scoreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scoreAnimation = IntTween(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _scoreController, curve: Curves.easeOutCubic),
    );
    _startLoadingMessages();
    _adapt();
  }

  @override
  void dispose() {
    _loadingMessageTimer?.cancel();
    _scoreController.dispose();
    super.dispose();
  }

  void _startLoadingMessages() {
    _loadingMessageTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_isLoading) return;
      setState(() {
        _loadingMessageIndex =
            (_loadingMessageIndex + 1) % _loadingMessages.length;
      });
    });
  }

  Future<void> _adapt({bool force = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      if (force) _retrying = true;
    });
    try {
      final result = await _aiService.adaptResume(widget.job.id, force: force);
      if (!mounted) return;
      setState(() {
        _adapted = result;
        _isLoading = false;
        _retrying = false;
      });
      _animateScoreUpgrade(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
        _retrying = false;
      });
    }
  }

  void _animateScoreUpgrade(AdaptedResume r) {
    final from = r.matchScoreBefore ?? 0;
    final to = r.matchScoreAfter ?? from;
    if (to <= 0) return;
    _scoreAnimation = IntTween(begin: from, end: to).animate(
      CurvedAnimation(parent: _scoreController, curve: Curves.easeOutCubic),
    );
    _scoreController.forward(from: 0);
  }

  // ── Actions ────────────────────────────────────────────────────────
  Future<void> _downloadPdf() async {
    final adapted = _adapted;
    if (adapted == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _isExporting = true);
    try {
      final user = context.read<UserViewModel>().user;
      // Usa o template que o user já escolheu pro CV regular — currículo
      // adaptado tem mesma identidade visual que o original. Default
      // 'harvard_ats' (ATS-friendly, seguro pra qualquer recrutador).
      final templateId =
          context.read<ResumeViewModel>().selectedTemplateId;
      await PdfService.generateResume(user, adapted.resumeData, templateId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar PDF: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              _buildDragHandle(),
              _buildHeader(),
              Expanded(child: _buildBody(scrollController)),
              if (_adapted != null && _error == null) _buildFooter(mq),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: _border,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 24),
            color: _textSecondary,
            onPressed: () => Navigator.pop(context),
            splashRadius: 22,
          ),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (b) => _gradient.createShader(b),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ShaderMask(
                      shaderCallback: (b) => _gradient.createShader(b),
                      child: const Text(
                        'CV adaptado pela IA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Pra balancear o close button da esquerda
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── Body states ───────────────────────────────────────────────────
  Widget _buildBody(ScrollController scrollController) {
    if (_isLoading) return _buildLoading();
    if (_error != null) return _buildError(scrollController);
    return _buildSuccess(scrollController);
  }

  // ── Loading ────────────────────────────────────────────────────────
  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Job card peek
          _buildJobPeek(),
          const SizedBox(height: 32),
          // Pulsing IA orb
          _PulsingOrb(),
          const SizedBox(height: 28),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Text(
              _loadingMessages[_loadingMessageIndex],
              key: ValueKey(_loadingMessageIndex),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: _textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.4,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nada será inventado — só reorganizamos\no que você já nos contou.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: _textMuted,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobPeek() {
    final logo = widget.job.companyLogoUrl;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: logo.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: logo,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.business_rounded, color: _textMuted),
                  )
                : const Icon(Icons.business_rounded, color: _textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.job.companyName} • ${widget.job.location}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Error ──────────────────────────────────────────────────────────
  Widget _buildError(ScrollController scrollController) {
    final err = _error;
    final isProfileIncomplete = err is ResumeAdaptationException &&
        err.code == 'profile_incomplete';
    final isRateLimited = err is ResumeAdaptationException &&
        err.code == 'rate_limited';
    final canRetry = !isProfileIncomplete && !isRateLimited;

    final message = err is ResumeAdaptationException
        ? err.message
        : 'Não consegui adaptar seu currículo agora.';

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        _buildJobPeek(),
        const SizedBox(height: 28),
        Container(
          width: 80,
          height: 80,
          margin: const EdgeInsets.symmetric(horizontal: 100),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFECACA), width: 2),
          ),
          child: Icon(
            isProfileIncomplete
                ? Icons.person_outline_rounded
                : isRateLimited
                    ? Icons.timer_off_rounded
                    : Icons.error_outline_rounded,
            size: 36,
            color: const Color(0xFFEF4444),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          isProfileIncomplete
              ? 'Complete seu perfil primeiro'
              : isRateLimited
                  ? 'Limite diário atingido'
                  : 'Algo deu errado',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            color: _textPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: _textSecondary,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 24),
        if (canRetry)
          _buildPrimaryButton(
            label: _retrying ? 'Tentando novamente…' : 'Tentar de novo',
            icon: Icons.refresh_rounded,
            onTap: _retrying ? null : () => _adapt(force: true),
            loading: _retrying,
          ),
      ],
    );
  }

  // ── Success ────────────────────────────────────────────────────────
  Widget _buildSuccess(ScrollController scrollController) {
    final adapted = _adapted!;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _buildScoreUpgradeCard(adapted),
        const SizedBox(height: 16),
        if (adapted.changes.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, size: 16, color: _textSecondary),
                const SizedBox(width: 6),
                Text(
                  '${adapted.changes.length} ajuste${adapted.changes.length > 1 ? "s" : ""} aplicado${adapted.changes.length > 1 ? "s" : ""}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textSecondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          ...adapted.changes
              .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ChangeCard(change: c),
                  )),
        ] else
          _buildNoChangesCard(),
        const SizedBox(height: 8),
        _buildPrivacyNote(),
      ],
    );
  }

  Widget _buildScoreUpgradeCard(AdaptedResume adapted) {
    final upgrade = adapted.matchUpgrade;
    final hasUpgrade = upgrade != null && upgrade > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _indigo.withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasUpgrade ? Icons.trending_up_rounded : Icons.check_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasUpgrade ? 'Match melhorou' : 'Adaptado',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (adapted.cached)
                Tooltip(
                  message: 'Você já tinha gerado essa adaptação antes',
                  child: Icon(
                    Icons.bolt_rounded,
                    color: Colors.white.withOpacity(0.6),
                    size: 16,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasUpgrade)
            AnimatedBuilder(
              animation: _scoreAnimation,
              builder: (_, __) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${adapted.matchScoreBefore}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.white.withOpacity(0.45),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white70, size: 24),
                    const SizedBox(width: 10),
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [Color(0xFFA7F3D0), Color(0xFF6EE7B7)],
                      ).createShader(b),
                      child: Text(
                        '${_scoreAnimation.value}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.4,
                          height: 1,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 2),
                      child: Text(
                        '/100',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          else
            Center(
              child: Text(
                'Currículo otimizado pra esta vaga',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            hasUpgrade
                ? 'Match score com base nos requisitos da vaga'
                : 'Pronto pra baixar e enviar',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoChangesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _emerald.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_rounded, color: _emerald),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Seu currículo já está bem alinhado com essa vaga. Nenhum ajuste necessário.',
              style: TextStyle(
                fontSize: 13,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 13, color: _textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Nenhuma informação foi inventada. A IA só reorganizou e reformulou dados que você já cadastrou.',
              style: TextStyle(
                fontSize: 11.5,
                color: _textMuted.withOpacity(0.9),
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer (download button) ──────────────────────────────────────
  Widget _buildFooter(MediaQueryData mq) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + mq.padding.bottom),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            border: const Border(top: BorderSide(color: _border, width: 0.5)),
          ),
          child: _buildPrimaryButton(
            label: _isExporting ? 'Gerando PDF…' : 'Baixar currículo (PDF)',
            icon: _isExporting ? null : Icons.download_rounded,
            onTap: _isExporting ? null : _downloadPdf,
            loading: _isExporting,
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    IconData? icon,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: onTap == null ? null : _gradient,
          color: onTap == null ? _textMuted : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: onTap == null
              ? null
              : [
                  BoxShadow(
                    color: _indigo.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Center(
              child: loading
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
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
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
}

// ─────────────────────────────────────────────────────────────────────
//  Internal: pulsing orb (loading visual)
// ─────────────────────────────────────────────────────────────────────

class _PulsingOrb extends StatefulWidget {
  @override
  State<_PulsingOrb> createState() => _PulsingOrbState();
}

class _PulsingOrbState extends State<_PulsingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // outer pulse
              Opacity(
                opacity: (1 - t) * 0.5,
                child: Container(
                  width: 96 * (0.8 + 0.4 * t),
                  height: 96 * (0.8 + 0.4 * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4F46E5).withOpacity(0.12),
                  ),
                ),
              ),
              // core orb
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Internal: change card (diff before/after)
// ─────────────────────────────────────────────────────────────────────

class _ChangeCard extends StatefulWidget {
  final ResumeChange change;
  const _ChangeCard({required this.change});

  @override
  State<_ChangeCard> createState() => _ChangeCardState();
}

class _ChangeCardState extends State<_ChangeCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final c = widget.change;
    final cat = c.category;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildCategoryBadge(cat),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.label.isEmpty ? _categoryLabel(cat) : c.label,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (c.reason.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                c.reason,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        color: Color(0xFF94A3B8),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  crossFadeState: _expanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildDiff(c),
                  ),
                  secondChild: const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiff(ResumeChange c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.before.isNotEmpty)
          _buildDiffLine(
            tag: 'Antes',
            text: c.before,
            color: const Color(0xFF94A3B8),
            strikethrough: true,
            bgColor: const Color(0xFFF1F5F9),
          ),
        if (c.before.isNotEmpty && c.after.isNotEmpty)
          const SizedBox(height: 6),
        if (c.after.isNotEmpty)
          _buildDiffLine(
            tag: 'Depois',
            text: c.after,
            color: const Color(0xFF065F46),
            strikethrough: false,
            bgColor: const Color(0xFFECFDF5),
          ),
      ],
    );
  }

  Widget _buildDiffLine({
    required String tag,
    required String text,
    required Color color,
    required bool strikethrough,
    required Color bgColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tag.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              color: strikethrough ? color : const Color(0xFF0F172A),
              fontWeight: strikethrough ? FontWeight.w500 : FontWeight.w600,
              decoration: strikethrough
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              decorationColor: color,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBadge(ChangeCategory cat) {
    final (icon, color) = _categoryStyle(cat);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  static (IconData, Color) _categoryStyle(ChangeCategory cat) {
    switch (cat) {
      case ChangeCategory.summary:
        return (Icons.description_rounded, const Color(0xFF4F46E5));
      case ChangeCategory.skills:
        return (Icons.bolt_rounded, const Color(0xFF7C3AED));
      case ChangeCategory.experience:
        return (Icons.work_outline_rounded, const Color(0xFF0EA5E9));
      case ChangeCategory.education:
        return (Icons.school_outlined, const Color(0xFFF59E0B));
      case ChangeCategory.achievements:
        return (Icons.emoji_events_outlined, const Color(0xFFF59E0B));
      case ChangeCategory.other:
        return (Icons.tune_rounded, const Color(0xFF64748B));
    }
  }

  static String _categoryLabel(ChangeCategory cat) {
    switch (cat) {
      case ChangeCategory.summary:
        return 'Resumo profissional';
      case ChangeCategory.skills:
        return 'Habilidades';
      case ChangeCategory.experience:
        return 'Experiência';
      case ChangeCategory.education:
        return 'Formação';
      case ChangeCategory.achievements:
        return 'Conquistas';
      case ChangeCategory.other:
        return 'Ajuste';
    }
  }
}
