import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/analytics/screen_tracking.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';
import '../auth/user_viewmodel.dart';
import '../gamification/widgets/academic_highlights_form_widget.dart';
import '../gamification/widgets/contact_form_widget.dart';
import '../gamification/summary_generation_screen.dart';
import 'add_experience_wizard.dart';
import 'edit_experience_screen.dart';
import 'resume_viewmodel.dart';
import '../../core/widgets/pii_mask.dart';

/// Edit mode for the user's CV. Each card persists changes directly to the
/// source-of-truth (user_answers / target_jobs / section_versions) so that
/// the next AI regeneration respects manual edits.
class ResumeEditScreen extends StatefulWidget {
  final ResumeContent initialContent;
  final Function(ResumeContent) onSave;

  const ResumeEditScreen({
    super.key,
    required this.initialContent,
    required this.onSave,
  });

  @override
  State<ResumeEditScreen> createState() => _ResumeEditScreenState();
}

class _ResumeEditScreenState extends State<ResumeEditScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'resume_edit';

  final _repo = SupabaseRepository();

  // Free-text controllers (legacy ResumeContent fields kept for compat)
  late TextEditingController _summaryController;
  late TextEditingController _skillsController; // kept for compat with _save()
  late TextEditingController _interestsController;
  // Chips-backed skill list — single source of truth for the new UX. Saved
  // back into _skillsController.text on every mutation so existing _save()
  // logic keeps working.
  List<String> _skillsList = [];
  final TextEditingController _newSkillCtrl = TextEditingController();

  // Lists held in memory and saved on "Salvar" via legacy onSave callback
  late List<ResumeExperience> _experiences;
  late List<ResumeEducation> _education;
  late List<ResumeProject> _projects;
  late List<ResumeLeadership> _leadership;
  late List<ResumeAward> _awards;

  // Source-of-truth fields loaded asynchronously
  Map<String, String> _academicHighlights = const {};
  Map<String, String> _contact = const {};
  List<ToolWithLevel> _tools = const [];
  List<({String title, String institution, String year})> _certs = const [];
  List<({String language, String level})> _languages = const [];
  TargetJob? _targetJob;
  String? _campaignId;
  // Maps a normalized "org|role" key → (cat, idx) for D1-backed entries.
  // Used by edit/delete actions to route into the rich EditExperienceScreen
  // and to call deleteExperience() instead of just dropping a list item.
  Map<String, ({String cat, int idx})> _d1KeyToCatIdx = const {};

  // First-time onboarding banner
  bool _showOnboarding = false;
  static const _onboardingFlagKey = 'resume_edit_seen_onboarding_v1';

  bool _loading = true;

  static const _harvardLanguageLevels = [
    'Nativo',
    'Fluente',
    'Avançado',
    'Intermediário',
    'Básico',
  ];

  static const _toolLevels = ['Avançado', 'Intermediário', 'Básico'];

  @override
  void initState() {
    super.initState();
    _summaryController = TextEditingController(text: widget.initialContent.summary);
    _skillsController = TextEditingController(text: widget.initialContent.skills);
    _skillsList = _parseSkillsString(widget.initialContent.skills);
    _interestsController = TextEditingController(text: widget.initialContent.interests);
    _experiences = List.from(widget.initialContent.experiences);
    _education = List.from(widget.initialContent.education);
    _projects = List.from(widget.initialContent.academicProjects);
    _leadership = List.from(widget.initialContent.leadership);
    _awards = List.from(widget.initialContent.awards);
    _loadSourceOfTruth();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_onboardingFlagKey) ?? false;
    if (!seen && mounted) {
      setState(() => _showOnboarding = true);
    }
  }

  Future<void> _dismissOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingFlagKey, true);
    if (mounted) setState(() => _showOnboarding = false);
  }

  /// Splits the legacy free-text skills field into a clean list. Handles all
  /// historical formats: newline-separated, comma-separated, "•"-prefixed.
  List<String> _parseSkillsString(String raw) {
    if (raw.trim().isEmpty) return [];
    final parts = raw
        .split(RegExp(r'[\n,;]'))
        .map((s) => s.replaceAll('•', '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    // Dedup while preserving order
    final seen = <String>{};
    return parts.where((s) => seen.add(s.toLowerCase())).toList();
  }

  /// Joins the chip list back to the legacy string format expected by
  /// `_save()` / `processList()` in resume_viewmodel.dart.
  void _persistSkillsList() {
    _skillsController.text = _skillsList.join('\n');
    _save();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _skillsController.dispose();
    _interestsController.dispose();
    _newSkillCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSourceOfTruth() async {
    final answers = await _repo.getUserAnswers();
    String? findAnswer(String qid) {
      for (final a in answers) {
        if (a['question_id'] == qid) return a['answer'] as String?;
      }
      return null;
    }

    // Academic highlights — M2_1_1_Q5
    final highlightsRaw = findAnswer('M2_1_1_Q5');
    if (highlightsRaw != null && highlightsRaw.isNotEmpty) {
      try {
        final j = jsonDecode(highlightsRaw);
        if (j is Map) {
          _academicHighlights = {
            'gpa': (j['gpa'] ?? '').toString(),
            'honors': (j['honors'] ?? '').toString(),
            'rep_role': (j['rep_role'] ?? '').toString(),
            'coursework': (j['coursework'] ?? '').toString(),
          };
        }
      } catch (_) {}
    }

    // Contact — M5_1_1_Q1
    final contactRaw = findAnswer('M5_1_1_Q1');
    if (contactRaw != null && contactRaw.isNotEmpty) {
      try {
        final j = jsonDecode(contactRaw);
        if (j is Map) {
          _contact = {
            'linkedin': (j['linkedin'] ?? '').toString(),
            'email': (j['email'] ?? '').toString(),
            'phone': (j['phone'] ?? '').toString(),
            'address': (j['address'] ?? '').toString(),
          };
        }
      } catch (_) {}
    }

    // Tools — M4_1_1_Q1
    final toolsRaw = findAnswer('M4_1_1_Q1');
    if (toolsRaw != null && toolsRaw.isNotEmpty) {
      try {
        final v = jsonDecode(toolsRaw);
        if (v is List) {
          _tools = v.where((e) => e is Map).map((e) {
            final m = e as Map;
            return ToolWithLevel(
              (m['category'] ?? m['tool'] ?? '').toString(),
              (m['level'] ?? '').toString(),
            );
          }).where((t) => t.name.isNotEmpty).toList();
        }
      } catch (_) {}
    }

    // Certifications — M3_2_1_Q2 (learningVault format)
    final certsRaw = findAnswer('M3_2_1_Q2');
    if (certsRaw != null && certsRaw.isNotEmpty) {
      try {
        final v = jsonDecode(certsRaw);
        if (v is List) {
          _certs = v.where((e) => e is Map).map((e) {
            final m = e as Map;
            return (
              title: (m['title'] ?? m['nome'] ?? '').toString(),
              institution: (m['institution'] ?? m['instituicao'] ?? '').toString(),
              year: (m['year'] ?? m['ano'] ?? '').toString(),
            );
          }).where((c) => c.title.isNotEmpty).toList();
        }
      } catch (_) {}
    }

    // Languages — prefer the structured override M4_2_1_Q3 if present,
    // else fall back to the AI-generated list from ResumeContent.
    final langsRaw = findAnswer('M4_2_1_Q3');
    if (langsRaw != null && langsRaw.trim().isNotEmpty) {
      try {
        final v = jsonDecode(langsRaw);
        if (v is List) {
          _languages = v.where((e) => e is Map).map((e) {
            final m = e as Map;
            return (
              language: (m['idioma'] ?? m['language'] ?? '').toString(),
              level: (m['nivel'] ?? m['level'] ?? '').toString(),
            );
          }).where((l) => l.language.isNotEmpty).toList();
        }
      } catch (_) {}
    }
    if (_languages.isEmpty) {
      _languages = widget.initialContent.languages
          .map((l) => (language: l.language, level: l.level))
          .toList();
    }

    // Target job from active campaign
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      final campaign = await _repo.getLatestCampaign(userId);
      _campaignId = campaign?.id;
      final targetJobId = campaign?.targetJobId;
      if (targetJobId != null) {
        _targetJob = await _repo.getTargetJob(targetJobId);
      }
    }

    // Build D1 key map (org|role lower → cat/idx) so item-level edit/delete
    // actions can route into the rich D1-backed flows.
    final d1Re = RegExp(r'^M3_D1_([a-z]+)_(\d+)$');
    final d1Map = <String, ({String cat, int idx})>{};
    for (final a in answers) {
      final qid = (a['question_id'] ?? '') as String;
      final m = d1Re.firstMatch(qid);
      if (m == null) continue;
      final raw = a['answer'];
      if (raw is! String) continue;
      try {
        final j = jsonDecode(raw);
        if (j is! Map) continue;
        final org = (j['org'] ?? '').toString().trim().toLowerCase();
        final role = (j['role'] ?? '').toString().trim().toLowerCase();
        if (org.isEmpty && role.isEmpty) continue;
        d1Map['$org|$role'] = (cat: m.group(1)!, idx: int.parse(m.group(2)!));
      } catch (_) {}
    }
    _d1KeyToCatIdx = d1Map;

    if (mounted) setState(() => _loading = false);
  }

  /// Parses an `experience_phase_id` like 'm3.lead.0' into a (cat, idx) pair.
  /// Returns null if the string isn't in the expected format.
  ({String cat, int idx})? _parsePhaseId(String phaseId) {
    final parts = phaseId.split('.');
    if (parts.length < 3 || parts[0] != 'm3') return null;
    final idx = int.tryParse(parts[2]);
    if (idx == null) return null;
    return (cat: parts[1], idx: idx);
  }

  /// Returns (cat, idx) when the given (org, role) maps to a D1 entry.
  /// Multi-strategy lookup tolerates PT/EN translation drift between the
  /// displayed CV and the raw D1 data (which is always in PT):
  ///   1. Exact match on (org+role)
  ///   2. Same-org match if unique within D1 (handles same org but role
  ///      translated, e.g. "Analista" → "Analyst")
  ///   3. Same-org match disambiguated by 3-char prefix on role
  ///      (handles "Pre…" matching "Presidente"/"President")
  ({String cat, int idx})? _findD1ForOrgRole(String org, String role) {
    final orgLower = org.trim().toLowerCase();
    final roleLower = role.trim().toLowerCase();

    // 1. Exact match
    final exact = _d1KeyToCatIdx['$orgLower|$roleLower'];
    if (exact != null) return exact;

    // 2 & 3. Find all D1 entries for this org
    final orgMatches = _d1KeyToCatIdx.entries
        .where((e) => e.key.split('|').first == orgLower)
        .toList();

    if (orgMatches.isEmpty) return null;
    if (orgMatches.length == 1) return orgMatches.first.value;

    // Multiple D1 entries for same org → disambiguate by role 3-char prefix
    if (roleLower.length >= 3) {
      for (final m in orgMatches) {
        final keyRole = m.key.split('|').last;
        if (keyRole.length < 3) continue;
        final pa = roleLower.substring(0, 3);
        final pb = keyRole.substring(0, 3);
        if (pa == pb || keyRole.startsWith(pa) || roleLower.startsWith(pb)) {
          return m.value;
        }
      }
    }

    return null;
  }

  /// Routes the [✏️] button: opens the rich EditExperienceScreen if the item
  /// is D1-backed, else falls back to the legacy free-text dialog.
  /// Prefers the embedded `phaseId` when available — this is unambiguous and
  /// survives PT/EN role translation. Falls back to text-matching otherwise.
  Future<bool> _maybeOpenRichEditor(String org, String role, {String? phaseId}) async {
    ({String cat, int idx})? match;
    if (phaseId != null && phaseId.isNotEmpty) {
      match = _parsePhaseId(phaseId);
    }
    match ??= _findD1ForOrgRole(org, role);
    if (match == null || _campaignId == null) return false;
    final cat = match.cat;
    final idx = match.idx;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditExperienceScreen(
          experiencePhaseId: 'm3.$cat.$idx',
          campaignId: _campaignId!,
        ),
      ),
    );
    // After return, refresh local state to reflect bullet/D1 edits
    await _loadSourceOfTruth();
    return true;
  }

  /// Confirms removal of an experience and, when the item is D1-backed,
  /// soft-deletes the bullets + hard-deletes raw_responses + user_answers.
  /// Pass `phaseId` (e.g. 'm3.lead.0') when the item carries an embedded
  /// reference — this is preferred over text-matching since it survives
  /// PT/EN translation and is fully deterministic.
  /// Returns:
  ///   - `null` when the user cancels (caller does nothing)
  ///   - `true` when removal was confirmed (caller should also drop the
  ///     item from its local list — both for D1-backed and free-text items)
  Future<bool?> _confirmAndDelete(
      ResumeViewModel vm, String org, String role, {String? phaseId}) async {
    ({String cat, int idx})? match;
    if (phaseId != null && phaseId.isNotEmpty) {
      match = _parsePhaseId(phaseId);
    }
    match ??= _findD1ForOrgRole(org, role);
    final isRich = match != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover esta entrada?'),
        content: Text(
          isRich
              ? 'Isso remove os bullets aprovados e todas as respostas D1-D6 desta experiência. Essa ação não pode ser desfeita.'
              : 'Isso remove a entrada do CV. Você pode adicionar novamente depois.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    if (isRich) {
      await vm.deleteExperience(cat: match.cat, idx: match.idx);
      await _loadSourceOfTruth();
    }
    return true;
  }

  /// Saves the legacy free-text edits (summary/skills/interests/lists) back
  /// to the local resume content. Source-of-truth fields are NOT touched —
  /// those are persisted directly when each card is edited.
  void _save() {
    final newContent = ResumeContent(
      summary: _summaryController.text,
      skills: _skillsController.text,
      interests: _interestsController.text,
      experiences: _experiences,
      education: _education,
      academicProjects: _projects,
      leadership: _leadership,
      courses: widget.initialContent.courses,
      languages: widget.initialContent.languages,
      awards: _awards,
      achievements: '',
    );
    widget.onSave(newContent);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ResumeViewModel>();
    return PiiMask(child: Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text(
          'Editar Currículo',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF111827),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
        actions: [
          TextButton.icon(
            onPressed: () {
              _save();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check_circle, color: Color(0xFF10B981)),
            label: Text(
              'Concluir',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF10B981),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Column(
                children: [
                  _buildLanguageBanner(vm),
                  const SizedBox(height: 12),
                  if (_showOnboarding) _buildOnboardingBanner(),
                  if (_showOnboarding) const SizedBox(height: 16),

                  // ─── Cabeçalho do CV ───
                  _buildBlockHeader('Cabeçalho do CV'),
                  _buildContactCard(vm),
                  const SizedBox(height: 12),
                  _buildTargetJobCard(vm),
                  const SizedBox(height: 12),
                  _buildSummaryCard(vm),
                  const SizedBox(height: 24),

                  // ─── Corpo principal ───
                  _buildBlockHeader('Corpo principal'),
                  _buildExperienceSection(),
                  const SizedBox(height: 12),
                  _buildEducationSection(),
                  const SizedBox(height: 12),
                  _buildAcademicHighlightsCard(vm),
                  const SizedBox(height: 12),
                  _buildLeadershipSection(),
                  const SizedBox(height: 12),
                  _buildProjectsSection(),
                  const SizedBox(height: 24),

                  // ─── Habilidades & Complementos ───
                  _buildBlockHeader('Habilidades & Complementos'),
                  _buildSkillsCard(),
                  const SizedBox(height: 12),
                  _buildToolsCard(vm),
                  const SizedBox(height: 12),
                  _buildLanguagesCard(),
                  const SizedBox(height: 12),
                  _buildCertificationsCard(vm),
                  const SizedBox(height: 12),
                  _buildAwardsSection(),
                  const SizedBox(height: 12),
                  _buildInterestsCard(),
                ],
              ),
            ),
      bottomNavigationBar: _buildRegenerateBar(vm),
    ));
  }

  /// Section group label rendered above each logical block of cards.
  Widget _buildBlockHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF00C27A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact banner indicating which language the displayed CV uses, plus a
  /// note that edits made in this screen are always against the PT source of
  /// truth. Tapping switches the CV language (delegated to the resume tab).
  Widget _buildLanguageBanner(ResumeViewModel vm) {
    final isEn = vm.language == 'en';
    final flag = isEn ? '🇺🇸' : '🇧🇷';
    final cvLang = isEn ? 'Inglês' : 'Português';
    final hint = isEn
        ? 'Edições em Português · clique em Regerar para aplicar na versão em Inglês'
        : 'Suas edições aqui aparecem direto no CV';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isEn ? const Color(0xFFFFF7ED) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEn ? const Color(0xFFFED7AA) : const Color(0xFFDBEAFE),
        ),
      ),
      child: Row(
        children: [
          Text(flag, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CV em $cvLang',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bem-vindo ao Modo Edição',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: _dismissOnboarding,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _onboardingTip(
            Icons.auto_awesome,
            'Adicionar com IA',
            'Adicione novas experiências passo-a-passo e a IA gera 3 bullets de qualidade Harvard pra você escolher.',
          ),
          const SizedBox(height: 8),
          _onboardingTip(
            Icons.edit,
            'Editar tudo',
            'Toque no ícone de lápis em qualquer entrada pra editar D1, refazer bullets ou ajustar texto manualmente.',
          ),
          const SizedBox(height: 8),
          _onboardingTip(
            Icons.refresh,
            'Regerar quando terminar',
            'Toque em "Regerar meu CV" no rodapé pra aplicar todas as mudanças no CV final.',
          ),
        ],
      ),
    );
  }

  Widget _onboardingTip(IconData icon, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.9), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withOpacity(0.95),
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: '$title — ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Footer "Regerar meu CV" — visible whenever there are pending edits
  // ════════════════════════════════════════════════════════════════════

  Widget _buildRegenerateBar(ResumeViewModel vm) {
    if (_loading) return const SizedBox.shrink();
    final hasEdits = vm.hasPendingEdits;
    if (!hasEdits && !vm.isGeneratingResume) return const SizedBox.shrink();

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    vm.isGeneratingResume
                        ? 'Aplicando mudanças…'
                        : 'Mudanças não aplicadas',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  Text(
                    vm.isGeneratingResume
                        ? 'Regerando seu currículo com a IA'
                        : 'Toque em Regerar para atualizar o CV.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: vm.isGeneratingResume
                  ? null
                  : () async {
                      _save();
                      await vm.regenerateAfterEdits();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('CV regerado com sucesso!'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      }
                    },
              icon: vm.isGeneratingResume
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                vm.isGeneratingResume ? 'Regerando' : 'Regerar meu CV',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // T2 — Vaga-Alvo
  // ════════════════════════════════════════════════════════════════════

  Widget _buildTargetJobCard(ResumeViewModel vm) {
    final title = _targetJob?.title?.trim();
    final desc = _targetJob?.descriptionText?.trim();
    return _buildSectionCard(
      title: 'Vaga-Alvo',
      icon: Icons.flag,
      collapsible: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (title == null || title.isEmpty)
                ? 'Nenhuma vaga-alvo definida'
                : title,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: (title == null || title.isEmpty)
                  ? Colors.grey
                  : const Color(0xFF111827),
            ),
          ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _editTargetJob(vm),
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Editar vaga-alvo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4F46E5),
              side: const BorderSide(color: Color(0xFF4F46E5)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTargetJob(ResumeViewModel vm) async {
    final titleCtrl = TextEditingController(text: _targetJob?.title ?? '');
    final descCtrl = TextEditingController(text: _targetJob?.descriptionText ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar vaga-alvo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Defina o tipo de vaga ou cargo que você quer aplicar. Isso ajuda a IA a focar o tom e os bullets do CV.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Vaga / cargo',
                  hintText: 'Ex: Estágio em Investment Banking',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descrição da vaga (opcional)',
                  hintText: 'Cole o texto da JD aqui se tiver',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    await vm.updateTargetJob(
      title: title,
      descriptionText: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
    );
    // Refresh local copy
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      final campaign = await _repo.getLatestCampaign(userId);
      if (campaign?.targetJobId != null) {
        _targetJob = await _repo.getTargetJob(campaign!.targetJobId!);
      }
    }
    if (mounted) {
      setState(() {});
      _showSavedFeedback();
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Summary card with "Refazer com IA" + manual edit
  // ════════════════════════════════════════════════════════════════════

  Widget _buildSummaryCard(ResumeViewModel vm) {
    return _buildSectionCard(
      title: 'Resumo Profissional',
      icon: Icons.person,
      collapsible: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(
            _summaryController,
            hint: 'Escreva um breve resumo sobre você…',
            maxLines: 5,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _refazerSummaryComIA(vm),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Refazer com IA'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4F46E5),
                    side: const BorderSide(color: Color(0xFF4F46E5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _salvarSummaryManual(vm),
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('Salvar texto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showSummaryHistory(vm),
              icon: const Icon(Icons.history, size: 16),
              label: const Text('Versões anteriores'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          Text(
            'Salvar texto persiste o resumo. Refazer com IA gera uma nova versão e abre a tela de aprovação.',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Future<void> _showSummaryHistory(ResumeViewModel vm) async {
    if (_campaignId == null) {
      _showSnack('Crie uma vaga-alvo antes de ver o histórico.');
      return;
    }
    final versions = await _repo.getAllSummaryVersions(_campaignId!);
    if (versions.isEmpty) {
      _showSnack('Nenhuma versão anterior encontrada.');
      return;
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<SectionVersion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Versões anteriores do resumo',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollCtl,
                padding: const EdgeInsets.all(12),
                itemCount: versions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final v = versions[i];
                  final txt = (v.editedContent != null && v.editedContent!.isNotEmpty)
                      ? v.editedContent!
                      : v.content;
                  final preview = txt.length > 200 ? '${txt.substring(0, 200)}…' : txt;
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, v),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: v.wasChosen
                            ? const Color(0xFFEEF2FF)
                            : const Color(0xFFF9FAFB),
                        border: Border.all(
                          color: v.wasChosen
                              ? const Color(0xFF4F46E5)
                              : Colors.grey[300]!,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Versão ${v.versionNumber}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (v.wasChosen)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4F46E5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'EM USO',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              Text(
                                _formatTimestamp(v.createdAt),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            preview,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF374151),
                              height: 1.4,
                            ),
                          ),
                          if (v.wasEdited) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Editado manualmente',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.grey[500],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    if (selected.wasChosen) {
      _showSnack('Esta já é a versão atual.');
      return;
    }
    await vm.restoreSummaryVersion(selected.id);
    final txt = (selected.editedContent != null && selected.editedContent!.isNotEmpty)
        ? selected.editedContent!
        : selected.content;
    _summaryController.text = txt;
    if (mounted) {
      setState(() {});
      _showSnack('Versão restaurada. Toque em Regerar para aplicar ao CV.');
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inHours < 1) return '${diff.inMinutes} min';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  Future<void> _refazerSummaryComIA(ResumeViewModel vm) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final campaign = context.read<UserViewModel>().currentCampaign
        ?? await _repo.getLatestCampaign(userId);
    if (campaign == null) {
      _showSnack('Crie uma vaga-alvo primeiro para refazer o resumo.');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SummaryGenerationScreen(campaignId: campaign.id),
      ),
    );
    // After approval, sync local controller from the new chosen version
    final approved = await _repo.getApprovedSummary(campaign.id);
    if (approved != null) {
      final txt = (approved.editedContent != null && approved.editedContent!.isNotEmpty)
          ? approved.editedContent!
          : approved.content;
      _summaryController.text = txt;
      // Mark stale so the "Regerar meu CV" button shows
      vm.updateSummaryManually(txt); // no-op write that flags stale
    }
    if (mounted) setState(() {});
  }

  Future<void> _salvarSummaryManual(ResumeViewModel vm) async {
    final txt = _summaryController.text.trim();
    if (txt.isEmpty) {
      _showSnack('Digite algo no resumo antes de salvar.');
      return;
    }
    await vm.updateSummaryManually(txt);
    _showSavedFeedback();
  }

  // ════════════════════════════════════════════════════════════════════
  // T3 — Contato
  // ════════════════════════════════════════════════════════════════════

  Widget _buildContactCard(ResumeViewModel vm) {
    final linkedin = _contact['linkedin'] ?? '';
    final email = _contact['email'] ?? '';
    final phone = _contact['phone'] ?? '';
    final address = _contact['address'] ?? '';
    final empty = linkedin.isEmpty && email.isEmpty && phone.isEmpty && address.isEmpty;
    return _buildSectionCard(
      title: 'Contato',
      icon: Icons.contact_mail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (empty)
            const Text(
              'Nenhum dado de contato. Toque em Editar para preencher.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            )
          else ...[
            if (email.isNotEmpty) _kv('E-mail', email),
            if (phone.isNotEmpty) _kv('Telefone', phone),
            if (linkedin.isNotEmpty) _kv('LinkedIn', linkedin),
            if (address.isNotEmpty) _kv('Endereço', address),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _editContact(vm),
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Editar contato'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4F46E5),
              side: const BorderSide(color: Color(0xFF4F46E5)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editContact(ResumeViewModel vm) async {
    String emittedJson = '';
    final initialJson = jsonEncode(_contact);
    final formKey = GlobalKey<ContactFormWidgetState>();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            // Force-flush so emittedJson reflects current state
            formKey.currentState?.flushEmit();
            final dirty = emittedJson.isNotEmpty && emittedJson != initialJson;
            if (!dirty) {
              if (ctx.mounted) Navigator.pop(ctx);
              return;
            }
            final discard = await _confirmDiscardChanges(ctx);
            if (discard && ctx.mounted) Navigator.pop(ctx);
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('Editar contato')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ContactFormWidget(
                key: formKey,
                initialValue: initialJson,
                onSelect: (val) => emittedJson = val,
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  // Force-flush the form state synchronously so `emittedJson`
                  // reflects the LAST keystroke even if the 500ms debounce
                  // window hasn't fired yet — eliminates the truncated-phone
                  // race condition. If the form is invalid, surface a clear
                  // error snackbar instead of silently doing nothing.
                  onPressed: () {
                    final ok = formKey.currentState?.flushEmit() ?? false;
                    if (!ok) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Preencha email válido e telefone com no mínimo 10 dígitos.'),
                          backgroundColor: Color(0xFFEF4444),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Salvar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (saved != true || emittedJson.isEmpty) return;
    try {
      final m = jsonDecode(emittedJson) as Map;
      final newContact = {
        'linkedin': (m['linkedin'] ?? '').toString(),
        'email': (m['email'] ?? '').toString(),
        'phone': (m['phone'] ?? '').toString(),
        'address': (m['address'] ?? '').toString(),
      };
      await vm.updateContact(
        linkedin: newContact['linkedin']!,
        email: newContact['email']!,
        phone: newContact['phone']!,
        address: newContact['address']!,
      );
      // Apply contact directly to the live ResumeData so the preview/header
      // update immediately — without waiting for the user to "Regerar com IA".
      vm.applyContactToHeader(newContact);
      _contact = newContact;
      if (mounted) {
        setState(() {});
        _showSavedFeedback();
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════
  // T4 — Destaques Acadêmicos
  // ════════════════════════════════════════════════════════════════════

  Widget _buildAcademicHighlightsCard(ResumeViewModel vm) {
    final gpa = _academicHighlights['gpa'] ?? '';
    final honors = _academicHighlights['honors'] ?? '';
    final repRole = _academicHighlights['rep_role'] ?? '';
    final coursework = _academicHighlights['coursework'] ?? '';
    final empty = gpa.isEmpty && honors.isEmpty && repRole.isEmpty && coursework.isEmpty;
    return _buildSectionCard(
      title: 'Destaques Acadêmicos',
      icon: Icons.emoji_events_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (empty)
            const Text(
              'Nenhum destaque informado. Toque em Editar para incluir GPA, distinções, cargos e disciplinas.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            )
          else ...[
            if (gpa.isNotEmpty) _kv('CR / GPA', gpa),
            if (honors.isNotEmpty) _kv('Distinções', honors),
            if (repRole.isNotEmpty) _kv('Cargo representativo', repRole),
            if (coursework.isNotEmpty) _kv('Disciplinas relevantes', coursework),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _editAcademicHighlights(vm),
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Editar destaques'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4F46E5),
              side: const BorderSide(color: Color(0xFF4F46E5)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editAcademicHighlights(ResumeViewModel vm) async {
    String emitted = '';
    final initialJson = jsonEncode(_academicHighlights);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final dirty = emitted.isNotEmpty && emitted != initialJson;
            if (!dirty) {
              if (ctx.mounted) Navigator.pop(ctx);
              return;
            }
            final discard = await _confirmDiscardChanges(ctx);
            if (discard && ctx.mounted) Navigator.pop(ctx);
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('Destaques acadêmicos')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: AcademicHighlightsFormWidget(
                initialValue: initialJson,
                onSelect: (val) => emitted = val,
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Future.delayed(const Duration(milliseconds: 600));
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Salvar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (saved != true || emitted.isEmpty) return;
    try {
      final m = jsonDecode(emitted) as Map;
      await vm.updateAcademicHighlights(
        gpa: (m['gpa'] ?? '').toString(),
        honors: (m['honors'] ?? '').toString(),
        repRole: (m['rep_role'] ?? '').toString(),
        coursework: (m['coursework'] ?? '').toString(),
      );
      _academicHighlights = {
        'gpa': (m['gpa'] ?? '').toString(),
        'honors': (m['honors'] ?? '').toString(),
        'rep_role': (m['rep_role'] ?? '').toString(),
        'coursework': (m['coursework'] ?? '').toString(),
      };
      if (mounted) {
        setState(() {});
        _showSavedFeedback();
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════
  // T5 — Habilidades Técnicas (texto livre, conceitos)
  // ════════════════════════════════════════════════════════════════════

  Widget _buildSkillsCard() {
    return _buildSectionCard(
      title: 'Habilidades Técnicas',
      icon: Icons.psychology,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Conceitos / áreas de domínio (NÃO inclua softwares aqui — esses vão em Ferramentas).',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (_skillsList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Nenhuma habilidade adicionada.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _skillsList.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return Chip(
                  label: Text(s, style: const TextStyle(fontSize: 13)),
                  backgroundColor: const Color(0xFFEEF2FF),
                  side: const BorderSide(color: Color(0xFFC7D2FE)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() => _skillsList.removeAt(i));
                    _persistSkillsList();
                    _showSavedFeedback();
                  },
                );
              }).toList(),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newSkillCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Adicionar habilidade…',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (_) => _addSkillFromInput(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addSkillFromInput,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: const Text('Adicionar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addSkillFromInput() {
    final txt = _newSkillCtrl.text.trim();
    if (txt.isEmpty) return;
    // Avoid duplicates (case-insensitive)
    final exists = _skillsList.any((s) => s.toLowerCase() == txt.toLowerCase());
    if (exists) {
      _newSkillCtrl.clear();
      _showSnack('Habilidade já adicionada.');
      return;
    }
    setState(() {
      _skillsList.add(txt);
      _newSkillCtrl.clear();
    });
    _persistSkillsList();
    _showSavedFeedback();
  }

  // ════════════════════════════════════════════════════════════════════
  // T5 — Ferramentas (estruturado: nome + nível)
  // ════════════════════════════════════════════════════════════════════

  Widget _buildToolsCard(ResumeViewModel vm) {
    return _buildSectionCard(
      title: 'Ferramentas',
      icon: Icons.build,
      child: Column(
        children: [
          if (_tools.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhuma ferramenta adicionada.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _tools.length,
              onReorder: (oldIndex, newIndex) async {
                final list = List<ToolWithLevel>.from(_tools);
                _reorderInPlace(list, oldIndex, newIndex);
                await vm.updateTools(list);
                setState(() => _tools = list);
              },
              itemBuilder: (ctx, i) {
                final t = _tools[i];
                return KeyedSubtree(
                  key: ValueKey('tool-$i-${t.name}'),
                  child: _buildListItemCard(
                    title: t.name,
                    subtitle: t.level.isNotEmpty ? 'Nível: ${t.level}' : 'Sem nível',
                    onEdit: () => _editTool(vm, i),
                    onDelete: () async {
                      final list = List<ToolWithLevel>.from(_tools)..removeAt(i);
                      await vm.updateTools(list);
                      setState(() => _tools = list);
                      _showSavedFeedback();
                    },
                    dragIndex: i,
                  ),
                );
              },
            ),
          _buildAddButton('Adicionar ferramenta', () => _editTool(vm, null)),
        ],
      ),
    );
  }

  Future<void> _editTool(ResumeViewModel vm, int? index) async {
    final existing = index != null ? _tools[index] : null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String level = existing?.level.isNotEmpty == true
        ? existing!.level
        : 'Intermediário';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(index == null ? 'Adicionar ferramenta' : 'Editar ferramenta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome (Ex: Excel, Figma, Python)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: _toolLevels.map((lv) {
                  final selected = lv == level;
                  return ChoiceChip(
                    label: Text(lv),
                    selected: selected,
                    onSelected: (_) => setLocal(() => level = lv),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final list = List<ToolWithLevel>.from(_tools);
    final newTool = ToolWithLevel(name, level);
    if (index == null) {
      list.add(newTool);
    } else {
      list[index] = newTool;
    }
    await vm.updateTools(list);
    setState(() => _tools = list);
    _showSavedFeedback();
  }

  // ════════════════════════════════════════════════════════════════════
  // T6 — Idiomas (estruturado com nível Harvard)
  // ════════════════════════════════════════════════════════════════════

  Widget _buildLanguagesCard() {
    final vm = context.read<ResumeViewModel>();
    return _buildSectionCard(
      title: 'Idiomas',
      icon: Icons.language,
      child: Column(
        children: [
          if (_languages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhum idioma adicionado.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _languages.length,
              onReorder: (oldIndex, newIndex) async {
                final list = List<({String language, String level})>.from(_languages);
                _reorderInPlace(list, oldIndex, newIndex);
                await vm.updateLanguagesStructured(list);
                setState(() => _languages = list);
              },
              itemBuilder: (ctx, i) {
                final l = _languages[i];
                return KeyedSubtree(
                  key: ValueKey('lang-$i-${l.language}'),
                  child: _buildListItemCard(
                    title: l.language,
                    subtitle: l.level.isEmpty ? 'Sem nível' : l.level,
                    onEdit: () => _editLanguage(vm, i),
                    onDelete: () async {
                      final list = List<({String language, String level})>.from(_languages)
                        ..removeAt(i);
                      await vm.updateLanguagesStructured(list);
                      setState(() => _languages = list);
                      _showSavedFeedback();
                    },
                    dragIndex: i,
                  ),
                );
              },
            ),
          _buildAddButton('Adicionar idioma', () => _editLanguage(vm, null)),
        ],
      ),
    );
  }

  Future<void> _editLanguage(ResumeViewModel vm, int? index) async {
    final existing = index != null ? _languages[index] : null;
    final nameCtrl = TextEditingController(text: existing?.language ?? '');
    String level = existing?.level.isNotEmpty == true
        ? existing!.level
        : 'Intermediário';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(index == null ? 'Adicionar idioma' : 'Editar idioma'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Idioma (Ex: Inglês, Espanhol)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _harvardLanguageLevels.map((lv) {
                  final selected = lv == level;
                  return ChoiceChip(
                    label: Text(lv),
                    selected: selected,
                    onSelected: (_) => setLocal(() => level = lv),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final list = List<({String language, String level})>.from(_languages);
    if (index == null) {
      list.add((language: name, level: level));
    } else {
      list[index] = (language: name, level: level);
    }
    await vm.updateLanguagesStructured(list);
    setState(() => _languages = list);
    _showSavedFeedback();
  }

  // ════════════════════════════════════════════════════════════════════
  // T7 — Certificações (estruturado)
  // ════════════════════════════════════════════════════════════════════

  Widget _buildCertificationsCard(ResumeViewModel vm) {
    return _buildSectionCard(
      title: 'Certificações & Programas',
      icon: Icons.verified,
      child: Column(
        children: [
          if (_certs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhuma certificação adicionada.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _certs.length,
              onReorder: (oldIndex, newIndex) async {
                final list = List<({String title, String institution, String year})>.from(_certs);
                _reorderInPlace(list, oldIndex, newIndex);
                await vm.updateCertifications(list);
                setState(() => _certs = list);
              },
              itemBuilder: (ctx, i) {
                final c = _certs[i];
                final subtitle = [
                  if (c.institution.isNotEmpty) c.institution,
                  if (c.year.isNotEmpty) c.year,
                ].join(' • ');
                return KeyedSubtree(
                  key: ValueKey('cert-$i-${c.title}'),
                  child: _buildListItemCard(
                    title: c.title,
                    subtitle: subtitle,
                    onEdit: () => _editCert(vm, i),
                    onDelete: () async {
                      final list = List<({String title, String institution, String year})>.from(_certs)
                        ..removeAt(i);
                      await vm.updateCertifications(list);
                      setState(() => _certs = list);
                      _showSavedFeedback();
                    },
                    dragIndex: i,
                  ),
                );
              },
            ),
          _buildAddButton('Adicionar certificação', () => _editCert(vm, null)),
        ],
      ),
    );
  }

  Future<void> _editCert(ResumeViewModel vm, int? index) async {
    final existing = index != null ? _certs[index] : null;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final instCtrl = TextEditingController(text: existing?.institution ?? '');
    final yearCtrl = TextEditingController(text: existing?.year ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'Adicionar certificação' : 'Editar certificação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome do curso',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: instCtrl,
              decoration: const InputDecoration(
                labelText: 'Instituição',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: yearCtrl,
              decoration: const InputDecoration(
                labelText: 'Ano',
                hintText: 'Ex: 2026',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    final list = List<({String title, String institution, String year})>.from(_certs);
    final newCert = (
      title: title,
      institution: instCtrl.text.trim(),
      year: yearCtrl.text.trim(),
    );
    if (index == null) {
      list.add(newCert);
    } else {
      list[index] = newCert;
    }
    await vm.updateCertifications(list);
    setState(() => _certs = list);
    _showSavedFeedback();
  }

  // ════════════════════════════════════════════════════════════════════
  // Education / Experience / Leadership / Projects / Awards (manual lists)
  // ════════════════════════════════════════════════════════════════════

  Widget _buildEducationSection() {
    return _buildSectionCard(
      title: 'Formação Acadêmica',
      icon: Icons.school,
      child: Column(
        children: [
          if (_education.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _education.length,
              onReorder: (oldIndex, newIndex) {
                setState(() => _reorderInPlace(_education, oldIndex, newIndex));
                _save();
              },
              itemBuilder: (ctx, i) {
                final e = _education[i];
                return KeyedSubtree(
                  key: ValueKey('edu-$i-${e.institution}-${e.course}'),
                  child: _buildListItemCard(
                    title: e.course,
                    subtitle: '${e.institution} • ${e.period}',
                    onEdit: () => _editEducation(i),
                    onDelete: () {
                      setState(() => _education.removeAt(i));
                      _save();
                    },
                    dragIndex: i,
                  ),
                );
              },
            ),
          _buildAddButton('Adicionar formação', () => _editEducation(null)),
        ],
      ),
    );
  }

  Widget _buildExperienceSection() {
    final vm = context.read<ResumeViewModel>();
    return _buildSectionCard(
      title: 'Experiência Profissional',
      icon: Icons.work,
      child: Column(
        children: [
          if (_experiences.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _experiences.length,
              onReorder: (oldIndex, newIndex) {
                setState(() => _reorderInPlace(_experiences, oldIndex, newIndex));
                _save();
              },
              itemBuilder: (ctx, i) {
                final exp = _experiences[i];
                return KeyedSubtree(
                  key: ValueKey('exp-$i-${exp.company}-${exp.role}'),
                  child: _buildListItemCard(
                    title: exp.role,
                    subtitle: '${exp.company} • ${exp.period}',
                    onEdit: () async {
                      final handled = await _maybeOpenRichEditor(
                        exp.company,
                        exp.role,
                        phaseId: exp.experiencePhaseId,
                      );
                      if (!handled) _editExperience(i);
                    },
                    onDelete: () async {
                      final ok = await _confirmAndDelete(
                        vm,
                        exp.company,
                        exp.role,
                        phaseId: exp.experiencePhaseId,
                      );
                      if (ok == true) {
                        setState(() => _experiences.removeAt(i));
                        _save();
                      }
                    },
                    dragIndex: i,
                  ),
                );
              },
            ),
          _buildAddWithWizardButton(
            'Adicionar experiência (com IA)',
            ['emp', 'free'],
          ),
          const SizedBox(height: 6),
          _buildAddButton('Adicionar manualmente', () => _editExperience(null)),
        ],
      ),
    );
  }

  // T8 — Liderança & Atividades
  Widget _buildLeadershipSection() {
    final vm = context.read<ResumeViewModel>();
    return _buildSectionCard(
      title: 'Liderança & Atividades',
      icon: Icons.handshake,
      child: Column(
        children: [
          if (_leadership.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _leadership.length,
              onReorder: (oldIndex, newIndex) {
                setState(() => _reorderInPlace(_leadership, oldIndex, newIndex));
                _save();
              },
              itemBuilder: (ctx, i) {
                final l = _leadership[i];
                return KeyedSubtree(
                  key: ValueKey('lead-$i-${l.organization}-${l.role}'),
                  child: _buildListItemCard(
                    title: l.role.isNotEmpty ? l.role : l.organization,
                    subtitle: '${l.organization} • ${l.period}',
                    onEdit: () async {
                      final handled = await _maybeOpenRichEditor(
                        l.organization,
                        l.role,
                        phaseId: l.experiencePhaseId,
                      );
                      if (!handled) _editLeadership(i);
                    },
                    onDelete: () async {
                      final ok = await _confirmAndDelete(
                        vm,
                        l.organization,
                        l.role,
                        phaseId: l.experiencePhaseId,
                      );
                      if (ok == true) {
                        setState(() => _leadership.removeAt(i));
                        _save();
                      }
                    },
                    dragIndex: i,
                  ),
                );
              },
            ),
          _buildAddWithWizardButton(
            'Adicionar atividade (com IA)',
            ['lead', 'vol'],
          ),
          const SizedBox(height: 6),
          _buildAddButton('Adicionar manualmente', () => _editLeadership(null)),
        ],
      ),
    );
  }

  Widget _buildProjectsSection() {
    final vm = context.read<ResumeViewModel>();
    return _buildSectionCard(
      title: 'Projetos',
      icon: Icons.folder,
      child: Column(
        children: [
          if (_projects.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _projects.length,
              onReorder: (oldIndex, newIndex) {
                setState(() => _reorderInPlace(_projects, oldIndex, newIndex));
                _save();
              },
              itemBuilder: (ctx, i) {
                final p = _projects[i];
                return KeyedSubtree(
                  key: ValueKey('proj-$i-${p.title}-${p.role}'),
                  child: _buildListItemCard(
                    title: p.title,
                    subtitle: p.role,
                    onEdit: () async {
                      final handled = await _maybeOpenRichEditor(
                        p.title,
                        p.role,
                        phaseId: p.experiencePhaseId,
                      );
                      if (!handled) _editProject(i);
                    },
                    onDelete: () async {
                      final ok = await _confirmAndDelete(
                        vm,
                        p.title,
                        p.role,
                        phaseId: p.experiencePhaseId,
                      );
                      if (ok == true) {
                        setState(() => _projects.removeAt(i));
                        _save();
                      }
                    },
                    dragIndex: i,
                  ),
                );
              },
            ),
          _buildAddWithWizardButton(
            'Adicionar projeto (com IA)',
            ['proj', 'res'],
          ),
          const SizedBox(height: 6),
          _buildAddButton('Adicionar manualmente', () => _editProject(null)),
        ],
      ),
    );
  }

  Widget _buildAwardsSection() {
    return _buildSectionCard(
      title: 'Premiações',
      icon: Icons.emoji_events,
      child: Column(
        children: [
          if (_awards.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _awards.length,
              onReorder: (oldIndex, newIndex) {
                setState(() => _reorderInPlace(_awards, oldIndex, newIndex));
                _save();
              },
              itemBuilder: (ctx, i) {
                final a = _awards[i];
                return KeyedSubtree(
                  key: ValueKey('award-$i-${a.title}-${a.institution}'),
                  child: _buildListItemCard(
                    title: a.title,
                    subtitle: a.institution,
                    onEdit: () => _editAward(i),
                    onDelete: () {
                      setState(() => _awards.removeAt(i));
                      _save();
                    },
                    dragIndex: i,
                  ),
                );
              },
            ),
          _buildAddButton('Adicionar premiação', () => _editAward(null)),
        ],
      ),
    );
  }

  Widget _buildInterestsCard() {
    return _buildSectionCard(
      title: 'Interesses',
      icon: Icons.interests,
      child: _buildTextField(
        _interestsController,
        hint: 'Seus interesses pessoais (ex: Tecnologia, Esportes…)',
        maxLines: 3,
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Generic UI helpers
  // ════════════════════════════════════════════════════════════════════

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    bool collapsible = true,
    Widget? trailingAction,
  }) {
    final card = Container(
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
      child: collapsible
          ? Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: const Color(0xFF4F46E5), size: 20),
                ),
                title: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF111827),
                  ),
                ),
                trailing: trailingAction,
                childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [child],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: const Color(0xFF4F46E5), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF111827),
                          ),
                        ),
                      ),
                      if (trailingAction != null) trailingAction,
                    ],
                  ),
                  const SizedBox(height: 16),
                  child,
                ],
              ),
            ),
    );
    return card;
  }

  Widget _buildTextField(
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      style: GoogleFonts.inter(fontSize: 14, height: 1.5),
    );
  }

  Widget _buildListItemCard({
    required String title,
    required String subtitle,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    int? dragIndex, // when non-null, renders a drag handle wired via ReorderableDragStartListener
  }) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFFF9FAFB),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        leading: dragIndex != null
            ? ReorderableDragStartListener(
                index: dragIndex,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              )
            : null,
        title: Text(
          title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 18, color: Colors.blueGrey),
              onPressed: onEdit,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(8),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
              onPressed: onDelete,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(8),
            ),
          ],
        ),
      ),
    );
    return card;
  }

  /// Helper that mutates a list using the (oldIndex, newIndex) pattern from
  /// ReorderableListView. Handles the standard "remove then insert" shift.
  void _reorderInPlace<T>(List<T> list, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
  }


  /// "Adicionar com IA" button — opens a category picker (when more than one
  /// option is available) and pushes the AddExperienceWizardScreen, which
  /// runs the D1-D6 flow + bullet generation.
  Widget _buildAddWithWizardButton(String label, List<String> categories) {
    return InkWell(
      onTap: () => _launchAddWizard(categories),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchAddWizard(List<String> categories) async {
    String? cat;
    if (categories.length == 1) {
      cat = categories.first;
    } else {
      cat = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Que tipo de experiência?',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...categories.map(_buildCategoryChoice),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    }
    if (cat == null) return;
    if (!mounted) return;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddExperienceWizardScreen(category: cat!)),
    );
    if (added == true && mounted) {
      // The wizard already triggered regenerateAfterEdits; just refresh
      // local state so newly-added items show up.
      _showSnack('Experiência adicionada! CV atualizado.');
    }
  }

  Widget _buildCategoryChoice(String cat) {
    final (label, hint, icon) = _categoryDescriptors(cat);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF4F46E5), size: 20),
      ),
      title: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      subtitle: Text(hint, style: GoogleFonts.inter(fontSize: 12)),
      onTap: () => Navigator.pop(context, cat),
    );
  }

  static (String, String, IconData) _categoryDescriptors(String cat) =>
      switch (cat) {
        'emp' => ('Estágio ou Emprego', 'CLT, estágio formal, trabalho registrado', Icons.work),
        'free' => ('Freelance', 'Trabalho autônomo ou projeto pago', Icons.description),
        'lead' => ('Liderança Estudantil', 'Liga, atlética, DA/CA, empresa júnior', Icons.handshake),
        'vol' => ('Voluntariado', 'ONG, projeto social', Icons.volunteer_activism),
        'proj' => ('Projeto Pessoal', 'Startup, app, projeto independente', Icons.lightbulb),
        'res' => ('Pesquisa Acadêmica', 'Iniciação científica, lab, TCC', Icons.science),
        'spo' => ('Esporte', 'Atleta, time da faculdade', Icons.sports),
        _ => ('Experiência', '', Icons.star),
      };

  Widget _buildAddButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF4F46E5),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 16, color: Color(0xFF4F46E5)),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: const Color(0xFF4F46E5),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF374151)),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Brief green check snackbar shown after a successful local save. Indicates
  /// the data was persisted but the rendered CV won't reflect it until the
  /// user clicks "Regerar com IA".
  void _showSavedFeedback([String label = 'Salvo localmente']) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
        backgroundColor: const Color(0xFF059669),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Shows a "Descartar alterações?" confirmation dialog. Returns true when
  /// the user wants to discard, false when they want to keep editing.
  Future<bool> _confirmDiscardChanges(BuildContext ctx) async {
    final result = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text(
          'Você tem edições não salvas. Se sair agora, elas serão perdidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ════════════════════════════════════════════════════════════════════
  // Dialogs for legacy free-text edit (Education, Experience, etc.)
  // ════════════════════════════════════════════════════════════════════

  Future<void> _showFormDialog({
    required String title,
    required List<Widget> children,
    required VoidCallback onSave,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              onSave();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _editExperience(int? index) {
    final exp = index != null ? _experiences[index] : null;
    final roleCtrl = TextEditingController(text: exp?.role);
    final compCtrl = TextEditingController(text: exp?.company);
    final dateCtrl = TextEditingController(text: exp?.period);
    final descCtrl = TextEditingController(text: exp?.description);

    _showFormDialog(
      title: index == null ? 'Nova experiência' : 'Editar experiência',
      children: [
        _dialogField(roleCtrl, 'Cargo'),
        _dialogField(compCtrl, 'Empresa'),
        _dialogField(dateCtrl, 'Período (Ex: Jan 2024 - Atual)'),
        _dialogField(descCtrl, 'Descrição (uma linha por bullet)', maxLines: 5),
      ],
      onSave: () {
        final newItem = ResumeExperience(
          role: roleCtrl.text.trim(),
          company: compCtrl.text.trim(),
          period: dateCtrl.text.trim(),
          description: descCtrl.text.trim(),
        );
        setState(() {
          if (index == null) {
            _experiences.add(newItem);
          } else {
            _experiences[index] = newItem;
          }
        });
      },
    );
  }

  void _editEducation(int? index) {
    final edu = index != null ? _education[index] : null;
    final instCtrl = TextEditingController(text: edu?.institution);
    final courseCtrl = TextEditingController(text: edu?.course);
    final periodCtrl = TextEditingController(text: edu?.period);
    final detailsCtrl = TextEditingController(text: edu?.details);

    _showFormDialog(
      title: index == null ? 'Nova formação' : 'Editar formação',
      children: [
        _dialogField(instCtrl, 'Instituição'),
        _dialogField(courseCtrl, 'Curso'),
        _dialogField(periodCtrl, 'Período (Ex: 2020 - 2024)'),
        _dialogField(detailsCtrl, 'Detalhes', maxLines: 3),
      ],
      onSave: () {
        final newItem = ResumeEducation(
          institution: instCtrl.text.trim(),
          course: courseCtrl.text.trim(),
          period: periodCtrl.text.trim(),
          details: detailsCtrl.text.trim(),
        );
        setState(() {
          if (index == null) {
            _education.add(newItem);
          } else {
            _education[index] = newItem;
          }
        });
      },
    );
  }

  void _editLeadership(int? index) {
    final l = index != null ? _leadership[index] : null;
    final roleCtrl = TextEditingController(text: l?.role);
    final orgCtrl = TextEditingController(text: l?.organization);
    final periodCtrl = TextEditingController(text: l?.period);
    final locCtrl = TextEditingController(text: l?.location);
    final descCtrl = TextEditingController(text: l?.description);

    _showFormDialog(
      title: index == null ? 'Nova atividade' : 'Editar atividade',
      children: [
        _dialogField(roleCtrl, 'Cargo / papel'),
        _dialogField(orgCtrl, 'Organização'),
        _dialogField(periodCtrl, 'Período'),
        _dialogField(locCtrl, 'Local'),
        _dialogField(descCtrl, 'Descrição (uma linha por bullet)', maxLines: 5),
      ],
      onSave: () {
        final newItem = ResumeLeadership(
          role: roleCtrl.text.trim(),
          organization: orgCtrl.text.trim(),
          period: periodCtrl.text.trim(),
          location: locCtrl.text.trim(),
          description: descCtrl.text.trim(),
        );
        setState(() {
          if (index == null) {
            _leadership.add(newItem);
          } else {
            _leadership[index] = newItem;
          }
        });
      },
    );
  }

  void _editProject(int? index) {
    final p = index != null ? _projects[index] : null;
    final titleCtrl = TextEditingController(text: p?.title);
    final roleCtrl = TextEditingController(text: p?.role);
    final periodCtrl = TextEditingController(text: p?.period);
    final descCtrl = TextEditingController(text: p?.description);

    _showFormDialog(
      title: index == null ? 'Novo projeto' : 'Editar projeto',
      children: [
        _dialogField(titleCtrl, 'Título'),
        _dialogField(roleCtrl, 'Papel'),
        _dialogField(periodCtrl, 'Período'),
        _dialogField(descCtrl, 'Descrição', maxLines: 4),
      ],
      onSave: () {
        final newItem = ResumeProject(
          title: titleCtrl.text.trim(),
          role: roleCtrl.text.trim(),
          period: periodCtrl.text.trim(),
          description: descCtrl.text.trim(),
        );
        setState(() {
          if (index == null) {
            _projects.add(newItem);
          } else {
            _projects[index] = newItem;
          }
        });
      },
    );
  }

  void _editAward(int? index) {
    final a = index != null ? _awards[index] : null;
    final titleCtrl = TextEditingController(text: a?.title);
    final instCtrl = TextEditingController(text: a?.institution);
    final dateCtrl = TextEditingController(text: a?.date);
    final descCtrl = TextEditingController(text: a?.description);

    _showFormDialog(
      title: index == null ? 'Nova premiação' : 'Editar premiação',
      children: [
        _dialogField(titleCtrl, 'Título'),
        _dialogField(instCtrl, 'Instituição'),
        _dialogField(dateCtrl, 'Data'),
        _dialogField(descCtrl, 'Descrição', maxLines: 3),
      ],
      onSave: () {
        final newItem = ResumeAward(
          title: titleCtrl.text.trim(),
          institution: instCtrl.text.trim(),
          date: dateCtrl.text.trim(),
          description: descCtrl.text.trim(),
        );
        setState(() {
          if (index == null) {
            _awards.add(newItem);
          } else {
            _awards[index] = newItem;
          }
        });
      },
    );
  }

  Widget _dialogField(TextEditingController c, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}
