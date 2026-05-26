import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';
import '../../services/ai_service.dart';
import '../gamification/bullet_review_screen.dart';
import '../gamification/widgets/experience_detail_form_widget.dart';
import 'resume_viewmodel.dart';
import '../../core/widgets/pii_mask.dart';

/// Reproduces the gamification trail's D1-D6 flow as a self-contained wizard
/// the user can launch from the resume edit screen to add a brand-new
/// experience. After D6 it calls `generate-bullets` and pushes the existing
/// `BulletReviewScreen`. On approval, the new experience is fully integrated
/// into the CV via the standard frontend overrides.
class AddExperienceWizardScreen extends StatefulWidget {
  /// One of: 'emp', 'free', 'lead', 'vol', 'proj', 'res', 'spo'.
  final String category;

  const AddExperienceWizardScreen({super.key, required this.category});

  @override
  State<AddExperienceWizardScreen> createState() =>
      _AddExperienceWizardScreenState();
}

class _AddExperienceWizardScreenState extends State<AddExperienceWizardScreen> {
  final _repo = SupabaseRepository();
  final _aiService = AIService();
  final _pageController = PageController();

  // Step 0: D1 form payload (JSON from ExperienceDetailFormWidget)
  String _d1Json = '';

  // Steps 1..5: D2-D6 text answers
  final _d2Ctrl = TextEditingController();
  final _d3Ctrl = TextEditingController();
  final _d4Ctrl = TextEditingController();
  final _d5Ctrl = TextEditingController();
  final _d6Ctrl = TextEditingController();

  int _step = 0;
  bool _saving = false;

  // Computed at init: the new index (0-based) for this experience in its
  // category, derived from existing M3_D1_${cat}_* answers.
  int _idx = 0;

  // Used to label the D1 step title.
  late final String _categoryLabel;

  @override
  void initState() {
    super.initState();
    _categoryLabel = _labelFor(widget.category);
    _computeNextIndex();
  }

  Future<void> _computeNextIndex() async {
    final answers = await _repo.getUserAnswers();
    final re = RegExp('^M3_D1_${widget.category}_(\\d+)\$');
    int max = -1;
    for (final a in answers) {
      final qid = (a['question_id'] ?? '') as String;
      final m = re.firstMatch(qid);
      if (m != null) {
        final n = int.tryParse(m.group(1) ?? '');
        if (n != null && n > max) max = n;
      }
    }
    _idx = max + 1;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    _d2Ctrl.dispose();
    _d3Ctrl.dispose();
    _d4Ctrl.dispose();
    _d5Ctrl.dispose();
    _d6Ctrl.dispose();
    super.dispose();
  }

  static String _labelFor(String cat) => switch (cat) {
        'emp' => 'Estágio ou Emprego',
        'stage' => 'Estágio',
        'free' => 'Trabalho Freelance',
        'lead' => 'Liderança Estudantil',
        'vol' => 'Voluntariado',
        'proj' => 'Projeto Pessoal',
        'res' => 'Pesquisa Acadêmica',
        'spo' => 'Esporte',
        _ => 'Experiência',
      };

  static const _d2 = {
    'stage': ('Em poucas palavras, o que essa empresa faz?',
        'Recrutador pode não conhecer. Em 1-2 frases, ajude ele a entender.'),
    'emp': ('Em poucas palavras, o que essa empresa faz?',
        'Recrutador pode não conhecer. Em 1-2 frases, ajude ele a entender.'),
    'free': ('Em poucas palavras, qual era o projeto ou cliente?',
        'Tipo de cliente, nicho ou produto que você entregou.'),
    'proj': ('Em poucas palavras, qual era o projeto e para quem?',
        'A ideia e o público: quem usaria ou se beneficiaria disso.'),
    'lead': ('Em poucas palavras, o que essa entidade faz?',
        'Recrutador pode não conhecer. Em 1-2 frases, ajude ele a entender.'),
    'vol': ('Em poucas palavras, qual é a missão dessa organização?',
        'Em 1-2 frases, descreva o que ela faz.'),
    'res': ('Em poucas palavras, qual era o tema da pesquisa?',
        'O problema estudado e o contexto acadêmico.'),
    'spo': ('Em poucas palavras, qual era o contexto do esporte?',
        'Nível, equipe ou competição em que você participava.'),
  };

  static const _d3 = {
    'stage': ('Como você entrou nesse estágio e o que esperavam de você?',
        'O processo seletivo, por que te escolheram, expectativas iniciais.'),
    'emp': ('Como você foi contratado e qual era sua missão no cargo?',
        'O contexto e o problema que você foi resolver.'),
    'free': ('Por que o cliente te contratou ou como surgiu esse projeto?',
        'O problema que ele queria resolver e por que escolheu você.'),
    'proj': ('Por que você criou isso? Qual problema queria resolver?',
        'A motivação e o que te fez começar.'),
    'lead': ('Como você entrou nessa liderança e qual era o desafio inicial?',
        'Processo de seleção ou fundação e o que precisava ser feito.'),
    'vol': ('Por que você escolheu esse voluntariado e qual era sua função?',
        'A motivação pessoal e o papel que assumiu.'),
    'res': ('Como surgiu esse projeto de pesquisa e qual era a hipótese?',
        'O orientador, o problema científico, a pergunta que respondiam.'),
    'spo': ('Como você chegou nesse nível e o que te motivava a continuar?',
        'O início da trajetória e a dedicação por trás dos resultados.'),
  };

  static const _d4 = {
    'stage': ('Me conta 2-3 coisas concretas que você fez no estágio.',
        'Tarefas, entregas, projetos. Pode ser desorganizado, eu organizo depois.'),
    'emp': ('Me conta 2-3 coisas concretas que você fez nesse trabalho.',
        'Responsabilidades, entregas, processos que tocou ou criou.'),
    'free': ('Me conta o que você entregou nesse projeto.',
        'O que foi criado, em quanto tempo, quais ferramentas usou.'),
    'proj': ('Me conta o que você desenvolveu ou construiu nesse projeto.',
        'Funcionalidades, versões, o que criou do zero ou melhorou.'),
    'lead': ('Me conta 2-3 coisas concretas que você liderou ou organizou.',
        'Eventos, projetos, decisões, membros gerenciados.'),
    'vol': ('Me conta 2-3 coisas concretas que você fez no voluntariado.',
        'Atividades, pessoas impactadas, projetos que tocou.'),
    'res': ('Me conta 2-3 coisas concretas que você fez na pesquisa.',
        'Coleta de dados, análises, artigos, apresentações.'),
    'spo': ('Me conta 2-3 conquistas ou atividades concretas do esporte.',
        'Campeonatos, treinos, liderança em equipe, resultados.'),
  };

  static const _d5 = {
    'stage': ('Qual foi o resultado mais concreto que você gerou nesse estágio?',
        'Pode ser número, processo criado, problema resolvido, feedback recebido.'),
    'emp': ('Qual foi o impacto mais concreto do seu trabalho nessa empresa?',
        'Número, meta batida, processo melhorado, equipe desenvolvida.'),
    'free': ('O cliente ficou satisfeito? O que mudou depois da sua entrega?',
        'Feedback, repetição, indicação, resultado relatado.'),
    'proj': ('O que o projeto gerou de concreto — uso, aprendizado ou impacto?',
        'Downloads, usuários, aprendizados técnicos, feedbacks.'),
    'lead': ('O que mudou na entidade ou no grupo depois da sua liderança?',
        'Crescimento, novos projetos, cultura, reconhecimento externo.'),
    'vol': ('Qual foi o impacto mais concreto do seu voluntariado?',
        'Pessoas impactadas, projetos entregues, mudança que ficou.'),
    'res': ('Quais foram os resultados ou conclusões da pesquisa?',
        'Publicações, apresentações, descobertas, continuidade do projeto.'),
    'spo': ('Qual foi o maior resultado ou aprendizado do percurso esportivo?',
        'Títulos, classificações, habilidades desenvolvidas, disciplina.'),
  };

  // ════════════════════════════════════════════════════════════════════
  // Step navigation
  // ════════════════════════════════════════════════════════════════════

  bool _canGoNext() {
    switch (_step) {
      case 0:
        // D1 must contain at least org + role + start
        try {
          final j = jsonDecode(_d1Json);
          return (j['org'] ?? '').toString().trim().isNotEmpty &&
              (j['role'] ?? '').toString().trim().isNotEmpty;
        } catch (_) {
          return false;
        }
      case 1:
        return _d2Ctrl.text.trim().length >= 5;
      case 2:
        return _d3Ctrl.text.trim().length >= 5;
      case 3:
        return _d4Ctrl.text.trim().length >= 5;
      case 4:
        return _d5Ctrl.text.trim().length >= 5;
      case 5:
        return true; // D6 is optional
      default:
        return false;
    }
  }

  void _nextStep() {
    if (_step < 5) {
      setState(() => _step++);
      _pageController.animateToPage(
        _step,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      _finishWizard();
    }
  }

  void _prevStep() {
    if (_step > 0) {
      setState(() => _step--);
      _pageController.animateToPage(
        _step,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Persistence: save D1-D6 + bump inventory + invoke generate-bullets
  // ════════════════════════════════════════════════════════════════════

  Future<void> _finishWizard() async {
    setState(() => _saving = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw 'Usuário não autenticado';

      final cat = widget.category;
      final n = _idx;

      // 1. Save user_answers (canonical) + raw_responses (for generate-bullets)
      // IMPORTANT: dynamic D-questions don't exist in the `questions` table by
      // default — we must `ensureQuestionExists` first to satisfy the FK.
      Future<void> saveBoth(int d, String questionText, String answer) async {
        final qid = 'M3_D${d}_${cat}_$n';
        final phaseId = 'm3.$cat.$n.d${d}';
        // Upsert the dynamic question row first
        final qType = d == 1
            ? QuestionType.experienceDetailForm
            : QuestionType.text;
        final options = d == 1
            ? <String>[cat]
            : <String>['', ''];
        await _repo.ensureQuestionExists(Question(
          id: qid,
          phaseId: 't3_p1',
          type: qType,
          content: questionText,
          options: options,
        ));
        await _repo.replaceAnswer(qid, answer);
        await _repo.replaceRawResponse(
          phaseId: phaseId,
          question: questionText,
          answer: answer,
          answerType: d == 1 ? 'experienceDetailForm' : 'text',
          questionOrder: d,
        );
      }

      await saveBoth(1, 'Me conta os detalhes do seu $_categoryLabel:', _d1Json);
      await saveBoth(2, _d2[cat]?.$1 ?? '', _d2Ctrl.text.trim());
      await saveBoth(3, _d3[cat]?.$1 ?? '', _d3Ctrl.text.trim());
      await saveBoth(4, _d4[cat]?.$1 ?? '', _d4Ctrl.text.trim());
      await saveBoth(5, _d5[cat]?.$1 ?? '', _d5Ctrl.text.trim());
      if (_d6Ctrl.text.trim().isNotEmpty) {
        await saveBoth(6, 'Tem números concretos pra incluir?', _d6Ctrl.text.trim());
      }

      // 2. Update M3 inventory + count so the generation flow sees the new exp
      await _bumpInventoryAndCount(cat);

      // 3. Get active campaign for bullet generation
      final campaign = await _repo.getLatestCampaign(userId);
      if (campaign == null) {
        throw 'Crie uma vaga-alvo antes de adicionar experiências.';
      }

      // 4. Trigger bullet generation
      await _aiService.generateBullets(
        experiencePhaseId: 'm3.$cat.$n',
        campaignId: campaign.id,
      );

      if (!mounted) return;

      // 5. Push BulletReviewScreen — user picks/edits/approves a bullet
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BulletReviewScreen(
            experiencePhaseId: 'm3.$cat.$n',
            campaignId: campaign.id,
          ),
        ),
      );

      if (!mounted) return;
      // 6. Mark resume stale and pop wizard with success
      context.read<ResumeViewModel>().regenerateAfterEdits();
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao adicionar experiência: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  /// Adds the category to M3_1_1_Q1 (inventory) if absent, and increments
  /// the count in M3_1_1_QCount.
  Future<void> _bumpInventoryAndCount(String cat) async {
    final answers = await _repo.getUserAnswers();
    String? findA(String qid) {
      for (final a in answers) {
        if (a['question_id'] == qid) return a['answer'] as String?;
      }
      return null;
    }

    // Inventory list
    final invRaw = findA('M3_1_1_Q1');
    final inv = <String>{};
    if (invRaw != null && invRaw.trim().isNotEmpty) {
      try {
        final v = jsonDecode(invRaw);
        if (v is List) inv.addAll(v.map((e) => e.toString()));
      } catch (_) {}
    }
    inv.add(cat);
    await _repo.replaceAnswer('M3_1_1_Q1', jsonEncode(inv.toList()));

    // Count map
    final countRaw = findA('M3_1_1_QCount');
    final counts = <String, int>{};
    if (countRaw != null && countRaw.trim().isNotEmpty) {
      try {
        final v = jsonDecode(countRaw);
        if (v is Map) {
          v.forEach((k, val) {
            counts[k.toString()] = (val is int)
                ? val
                : int.tryParse(val.toString()) ?? 0;
          });
        }
      } catch (_) {}
    }
    counts[cat] = (counts[cat] ?? 0) + 1;
    await _repo.replaceAnswer('M3_1_1_QCount', jsonEncode(counts));
  }

  // ════════════════════════════════════════════════════════════════════
  // Build
  // ════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PiiMask(child: Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text('Adicionar $_categoryLabel'),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
        titleTextStyle: TextStyle(fontFamily: 'Inter', 
          color: const Color(0xFF111827),
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      body: Column(
        children: [
          // Progress indicator (6 dots)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              children: List.generate(6, (i) {
                final active = i <= _step;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 5 ? 6 : 0),
                    height: 4,
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF4F46E5) : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStepD1(),
                _buildStepText(
                    title: _d2[widget.category]?.$1 ?? 'Sobre a organização',
                    hint: _d2[widget.category]?.$2 ?? '',
                    controller: _d2Ctrl),
                _buildStepText(
                    title: _d3[widget.category]?.$1 ?? 'Como começou',
                    hint: _d3[widget.category]?.$2 ?? '',
                    controller: _d3Ctrl),
                _buildStepText(
                    title: _d4[widget.category]?.$1 ?? 'O que você fez',
                    hint: _d4[widget.category]?.$2 ?? '',
                    controller: _d4Ctrl),
                _buildStepText(
                    title: _d5[widget.category]?.$1 ?? 'O que mudou / impacto',
                    hint: _d5[widget.category]?.$2 ?? '',
                    controller: _d5Ctrl),
                _buildStepD6(),
              ],
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    ));
  }

  Widget _buildStepD1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(
            'Detalhes do seu $_categoryLabel',
            'Organização, cargo, datas e local. Tudo aqui aparece na linha de cima do CV.',
          ),
          const SizedBox(height: 16),
          ExperienceDetailFormWidget(
            categoryCode: widget.category,
            onSelect: (val) {
              _d1Json = val;
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStepText({
    required String title,
    required String hint,
    required TextEditingController controller,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(title, hint),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Sua resposta…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepD6() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(
            'Tem números concretos pra incluir?',
            'Quantas pessoas envolvidas, quanto cresceu, ranking, downloads, prazo, ROI? Pode pular se não tiver — vai forçar a IA a destacar números reais nos bullets.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _d6Ctrl,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Ex: liderei 8 trainees; 1000 downloads; +30% engajamento…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb, size: 16, color: Color(0xFF4F46E5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quando você concluir, a IA vai gerar 3 bullets diferentes pra você escolher o que mais te representa.',
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: 12,
                      color: const Color(0xFF312E81),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Passo ${_step + 1} de 6',
          style: TextStyle(fontFamily: 'Inter', 
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF6B7280),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: TextStyle(fontFamily: 'Inter', 
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF111827),
            height: 1.3,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontFamily: 'Inter', 
              fontSize: 13,
              color: const Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            if (_step > 0)
              OutlinedButton(
                onPressed: _saving ? null : _prevStep,
                child: const Text('Voltar'),
              ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: (_canGoNext() && !_saving) ? _nextStep : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(_step == 5 ? Icons.auto_awesome : Icons.arrow_forward, size: 18),
              label: Text(
                _saving
                    ? 'Gerando bullets…'
                    : (_step == 5 ? 'Gerar bullets com IA' : 'Próximo'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
