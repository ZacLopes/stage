import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/analytics/screen_tracking.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';
import '../../services/ai_service.dart';
import '../gamification/bullet_review_screen.dart';
import '../gamification/widgets/experience_detail_form_widget.dart';
import 'resume_viewmodel.dart';
import '../../core/widgets/pii_mask.dart';
import '../../core/theme/theme.dart';

/// Edit screen for an existing experience: lets the user update the D1
/// fields (org, role, dates, city) and manage the list of approved bullets
/// (edit text, regenerate via AI, remove, add manual).
class EditExperienceScreen extends StatefulWidget {
  /// e.g. 'm3.lead.0' — also used as `experience_phase_id` in approved_bullets.
  final String experiencePhaseId;
  final String campaignId;

  const EditExperienceScreen({
    super.key,
    required this.experiencePhaseId,
    required this.campaignId,
  });

  @override
  State<EditExperienceScreen> createState() => _EditExperienceScreenState();
}

class _EditExperienceScreenState extends State<EditExperienceScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'resume_experience_edit';

  @override
  Map<String, Object>? get screenProperties =>
      {'experience_phase_id': widget.experiencePhaseId};

  final _repo = SupabaseRepository();
  final _aiService = AIService();

  bool _loading = true;
  String _d1Json = '';
  String _initialD1Json = '';
  List<ApprovedBullet> _bullets = [];

  String get _cat {
    final parts = widget.experiencePhaseId.split('.');
    return parts.length >= 2 ? parts[1] : '';
  }

  int get _idx {
    final parts = widget.experiencePhaseId.split('.');
    return parts.length >= 3 ? int.tryParse(parts[2]) ?? 0 : 0;
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final answers = await _repo.getUserAnswers();
    final qid = 'M3_D1_${_cat}_$_idx';
    for (final a in answers) {
      if (a['question_id'] == qid) {
        _initialD1Json = (a['answer'] ?? '') as String;
        _d1Json = _initialD1Json;
        break;
      }
    }
    final all = await _repo.getApprovedBullets(widget.campaignId);
    _bullets = all
        .where((b) => b.experiencePhaseId == widget.experiencePhaseId)
        .toList();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveD1() async {
    if (_d1Json.isEmpty || _d1Json == _initialD1Json) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma alteração para salvar.'),
            duration: Duration(milliseconds: 1200),
          ),
        );
      }
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final qid = 'M3_D1_${_cat}_$_idx';
    final phaseId = '${widget.experiencePhaseId}.d1';
    await _repo.replaceAnswer(qid, _d1Json);
    await _repo.replaceRawResponse(
      phaseId: phaseId,
      question: 'Detalhes da experiência',
      answer: _d1Json,
      answerType: 'experienceDetailForm',
      questionOrder: 1,
    );
    _initialD1Json = _d1Json;
    if (mounted) {
      // Flag the resume as needing regeneration so the parent screen shows
      // the "Regerar com IA" prompt.
      context.read<ResumeViewModel>().markStale();
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Detalhes salvos · clique em Regerar para refletir no CV'),
            ],
          ),
          backgroundColor: const Color(0xFF059669),
          duration: const Duration(milliseconds: 2200),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _editBulletText(ApprovedBullet b) async {
    final ctrl = TextEditingController(text: b.finalText);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar bullet'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newText = ctrl.text.trim();
    if (newText.isEmpty) return;
    await _repo.updateApprovedBulletText(b.id, newText);
    if (mounted) {
      context.read<ResumeViewModel>().regenerateAfterEdits();
      _loadAll();
    }
  }

  Future<void> _removeBullet(ApprovedBullet b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover bullet?'),
        content: const Text('Essa ação remove o bullet do CV. Você ainda pode regerar com IA depois.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.softDeleteApprovedBullet(b.id);
    if (mounted) {
      context.read<ResumeViewModel>().regenerateAfterEdits();
      _loadAll();
    }
  }

  Future<void> _regenerateAllBullets() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refazer bullets com IA'),
        content: const Text(
          'Isso vai gerar 3 novas opções de bullets baseadas nas suas respostas D1-D6. Os bullets atuais ficarão inativos. Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Refazer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      // Soft-delete current bullets so the new approval becomes the active one
      await _repo.softDeleteAllBulletsForPhase(
          widget.campaignId, widget.experiencePhaseId);
      // Trigger generation
      await _aiService.generateBullets(
        experiencePhaseId: widget.experiencePhaseId,
        campaignId: widget.campaignId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BulletReviewScreen(
            experiencePhaseId: widget.experiencePhaseId,
            campaignId: widget.campaignId,
          ),
        ),
      );
      if (!mounted) return;
      context.read<ResumeViewModel>().regenerateAfterEdits();
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao refazer bullets: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _addManualBullet() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar bullet'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Comece com um verbo de ação no passado…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    await _repo.approveBullet(
      campaignId: widget.campaignId,
      finalText: text,
      source: 'user_written',
      experiencePhaseId: widget.experiencePhaseId,
      displayOrder: _bullets.length,
    );
    if (mounted) {
      context.read<ResumeViewModel>().regenerateAfterEdits();
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PiiMask(child: Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(
        title: const Text('Editar experiência'),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(fontFamily: 'Inter', 
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildD1Card(),
                  const SizedBox(height: 16),
                  _buildBulletsCard(),
                ],
              ),
            ),
    ));
  }

  Widget _buildD1Card() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit_note,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dados básicos',
                      style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Edite organização, cargo, datas e local',
                      style: TextStyle(fontFamily: 'Inter', 
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ExperienceDetailFormWidget(
            categoryCode: _cat,
            initialValue: _initialD1Json,
            onSelect: (val) => _d1Json = val,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _saveD1,
            icon: const Icon(Icons.save),
            label: const Text('Salvar detalhes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.format_list_bulleted,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Bullets aprovados',
                  style: TextStyle(fontFamily: 'Inter', 
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_bullets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhum bullet aprovado para esta experiência. Adicione manual ou gere com IA.',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
            )
          else
            ..._bullets.map(_buildBulletTile),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _regenerateAllBullets,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Refazer com IA'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _addManualBullet,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Adicionar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBulletTile(ApprovedBullet b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '•',
              style: TextStyle(fontFamily: 'Inter', 
                  fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              b.finalText,
              style: TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.4),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18, color: Colors.blueGrey),
            onPressed: () => _editBulletText(b),
            tooltip: 'Editar texto',
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
            onPressed: () => _removeBullet(b),
            tooltip: 'Remover',
          ),
        ],
      ),
    );
  }
}
