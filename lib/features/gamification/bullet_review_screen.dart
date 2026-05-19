import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';
import '../auth/user_viewmodel.dart';
import 'gamification_viewmodel.dart';
import '../../services/ai_service.dart';

class BulletReviewScreen extends StatefulWidget {
  final String experiencePhaseId; // e.g. 'm3.stage.0'
  final String campaignId;

  const BulletReviewScreen({
    super.key,
    required this.experiencePhaseId,
    required this.campaignId,
  });

  @override
  State<BulletReviewScreen> createState() => _BulletReviewScreenState();
}

class _BulletReviewScreenState extends State<BulletReviewScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'bullet_review';

  @override
  Map<String, Object>? get screenProperties =>
      {'experience_phase_id': widget.experiencePhaseId};

  final _aiService = AIService();
  final _repo = SupabaseRepository();

  BulletGenerationResult? _result;
  bool _isLoading = true;
  String? _error;

  // clarification flow
  bool _showClarification = false;
  final _clarificationController = TextEditingController();

  // editor flow
  bool _showEditor = false;
  final _editorController = TextEditingController();
  String _editorSource = 'ai_edited'; // 'ai_edited' or 'user_written'
  String? _selectedVersionId;

  // "want another bullet?" flow
  bool _showAddMore = false;
  String? _approvedBulletText;

  int _approvedCount = 0; // bullets saved for this experience so far

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _clarificationController.dispose();
    _editorController.dispose();
    super.dispose();
  }

  Future<void> _generate({String? clarificationAnswer}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _showClarification = false;
      _showEditor = false;
    });
    try {
      final result = await _aiService.generateBullets(
        experiencePhaseId: widget.experiencePhaseId,
        campaignId: widget.campaignId,
        clarificationAnswer: clarificationAnswer,
      );
      setState(() {
        _result = result;
        _isLoading = false;
        if (result.needsClarification != null) {
          _showClarification = true;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Não foi possível gerar os bullets. Tente novamente.';
      });
    }
  }

  Future<void> _approveBullet({
    required String finalText,
    required String source,
    String? versionId,
  }) async {
    final existingBullets = await _repo.getApprovedBullets(widget.campaignId);
    final displayOrder = existingBullets.length;

    await _repo.approveBullet(
      campaignId: widget.campaignId,
      finalText: finalText,
      source: source,
      experiencePhaseId: widget.experiencePhaseId,
      bulletVersionId: versionId,
      displayOrder: displayOrder,
    );

    HapticFeedback.mediumImpact();
    setState(() {
      _approvedCount++;
      _approvedBulletText = finalText;
      _showAddMore = true;
      _showEditor = false;
    });
  }

  void _openEditor(String prefilledText, {String? versionId, bool fromScratch = false}) {
    setState(() {
      _showEditor = true;
      _showAddMore = false;
      _editorController.text = fromScratch ? '' : prefilledText;
      _editorSource = fromScratch ? 'user_written' : 'ai_edited';
      _selectedVersionId = fromScratch ? null : versionId;
    });
  }

  void _exitToPhase() {
    context.read<GamificationViewModel>().resumeAfterBullet();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // must approve or skip
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Seus bullets',
            style: TextStyle(
              color: Color(0xFF1F2937),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _exitToPhase,
              child: const Text(
                'Pular',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
              ),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoading();
    if (_error != null) return _buildError();
    if (_showEditor) return _buildEditor();
    if (_showAddMore) return _buildAddMore();
    if (_showClarification && _result?.needsClarification != null) {
      return _buildClarification(_result!.needsClarification!);
    }
    if (_result != null) return _buildBulletCards(_result!);
    return const SizedBox.shrink();
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: Color(0xFF00C27A),
            strokeWidth: 3,
          ),
          SizedBox(height: 20),
          Text(
            'Trabalhando nos seus bullets...',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_outlined, size: 48, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF4B5563), fontSize: 15),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _generate,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C27A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              child: const Text('Tentar novamente', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _exitToPhase, child: const Text('Pular esta etapa')),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletCards(BulletGenerationResult result) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Escolha o ângulo que melhor te representa:',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
          ),
          if (result.needsClarification != null) ...[
            const SizedBox(height: 12),
            _buildClarificationHint(result.needsClarification!),
          ],
          const SizedBox(height: 16),
          ...result.bullets.map((bullet) => _buildBulletCard(bullet)),
          const SizedBox(height: 8),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openEditor(
                    result.bullets.first.content,
                    versionId: result.bullets.first.id,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Misturar / editar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4B5563),
                    side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openEditor('', fromScratch: true),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Escrever do zero'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4B5563),
                    side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBulletCard(BulletVersion bullet) {
    final meta = _angleMeta(bullet.angle);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0xFFF3F4F6), offset: Offset(0, 3), blurRadius: 0)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: meta.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(meta.icon, size: 14, color: meta.color),
                      const SizedBox(width: 5),
                      Text(
                        meta.label,
                        style: TextStyle(
                          color: meta.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Text(
              bullet.content,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF1F2937),
                height: 1.5,
              ),
            ),
          ),
          // Strength feedback (Harvard MCS heuristics)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _BulletStrengthBadge(text: bullet.content),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _approveBullet(
                  finalText: bullet.content,
                  source: 'ai_chosen',
                  versionId: bullet.id.isNotEmpty ? bullet.id : null,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C27A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Usar este', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClarificationHint(BulletClarification clarification) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9C4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFBC02D), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dica para melhorar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
                ),
                const SizedBox(height: 4),
                Text(
                  clarification.question,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF78350F), height: 1.4),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => setState(() => _showClarification = true),
                  child: const Text(
                    'Responder e gerar novos bullets →',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
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

  Widget _buildClarification(BulletClarification clarification) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Uma pergunta antes de gerar novos bullets:',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
          ),
          const SizedBox(height: 16),
          Text(
            clarification.question,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            clarification.reason,
            style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF), height: 1.4),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _clarificationController,
            maxLines: 4,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Sua resposta aqui...',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF00C27A), width: 2),
              ),
            ),
            style: const TextStyle(fontSize: 15, color: Color(0xFF1F2937)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                final ans = _clarificationController.text.trim();
                if (ans.isEmpty) return;
                _generate(clarificationAnswer: ans);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C27A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Gerar novos bullets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                _showClarification = false;
              }),
              child: const Text('Voltar para os bullets atuais', style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editorSource == 'user_written' ? 'Escreva seu bullet:' : 'Edite o bullet:',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Comece com um verbo de ação forte: Liderei, Cresci, Estruturei...',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _editorController,
            maxLines: 5,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Ex: Liderei a reestruturação do processo de onboarding...',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF00C27A), width: 2),
              ),
            ),
            style: const TextStyle(fontSize: 15, color: Color(0xFF1F2937), height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                final text = _editorController.text.trim();
                if (text.isEmpty) return;
                _approveBullet(
                  finalText: text,
                  source: _editorSource,
                  versionId: _selectedVersionId,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C27A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Salvar bullet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showEditor = false),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMore() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF00C27A).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, color: Color(0xFF00C27A), size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            'Bullet salvo!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Quer adicionar mais um bullet desta experiência?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Color(0xFF6B7280), height: 1.5),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _generate(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C27A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Sim, gerar mais um', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: _exitToPhase,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4B5563),
                side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Não, próxima experiência', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  _AngleMeta _angleMeta(String angle) {
    switch (angle) {
      case 'processo':
        return _AngleMeta(Icons.settings_outlined, const Color(0xFF6366F1), 'PROCESSO');
      case 'habilidade':
        return _AngleMeta(Icons.psychology_outlined, const Color(0xFFF59E0B), 'HABILIDADE');
      case 'resultado':
      default:
        return _AngleMeta(Icons.trending_up, const Color(0xFF00C27A), 'RESULTADO');
    }
  }
}

class _AngleMeta {
  final IconData icon;
  final Color color;
  final String label;
  const _AngleMeta(this.icon, this.color, this.label);
}

// ════════════════════════════════════════════════════════════════════
// Bullet strength heuristics (Harvard MCS guidelines)
// ════════════════════════════════════════════════════════════════════

enum _BulletStrength { strong, medium, weak }

class _BulletAnalysis {
  final _BulletStrength strength;
  final String message;
  const _BulletAnalysis(this.strength, this.message);
}

const _bannedVerbs = [
  'ajudei', 'auxiliei', 'trabalhei em', 'fui responsável', 'foi responsável',
  'tive a oportunidade', 'estive envolvido', 'fiz parte de', 'participei de',
];

const _cliches = [
  'proativo', 'proativa', 'dinâmico', 'dinâmica', 'líder nato', 'líder nata',
  'foco em resultados', 'perfil empreendedor', 'team player', 'hands-on',
  'apaixonado por', 'apaixonada por', 'comunicativo', 'comunicativa',
  'automotivado', 'habilidoso em',
];

const _harvardActionVerbs = [
  // Liderança
  'liderei', 'coordenei', 'dirigi', 'geri', 'supervisionei', 'orquestrei',
  'encabecei', 'presidi', 'conduzi', 'estabeleci', 'priorizei', 'deleguei',
  'recomendei', 'avaliei',
  // Comunicação
  'apresentei', 'negociei', 'mediei', 'redigi', 'editei', 'traduzi',
  'persuadi', 'promovi', 'recrutei', 'convenci', 'articulei',
  // Pesquisa
  'investiguei', 'analisei', 'identifiquei', 'diagnostiquei', 'mapeei',
  'examinei', 'sintetizei', 'modelei', 'validei',
  // Técnico
  'construí', 'projetei', 'implementei', 'otimizei', 'padronizei',
  'programei', 'automatizei', 'engenhei', 'reformulei', 'atualizei',
  // Quantitativo
  'calculei', 'orçamentei', 'maximizei', 'minimizei', 'auditei',
  'quantifiquei', 'reduzi', 'cresci', 'aumentei', 'diminuí',
  // Criativo
  'criei', 'concebi', 'fundei', 'desenvolvi', 'lancei', 'originei',
  'visualizei', 'estruturei',
  // Organizacional
  'organizei', 'sistematizei', 'centralizei', 'categorizei', 'compilei',
  'processei', 'coletei',
];

final _metricRegex = RegExp(
  r'\d+(?:[.,]\d+)?\s*%'
  r'|\d+(?:[.,]\d+)*\+'
  r'|R\$\s*\d+'
  r'|\d+(?:[.,]\d+)*\s+(?:usuários|usuarios|downloads|membros|pessoas|clientes|alunos|atendentes|alvos|empresas|projetos|acessos|seguidores|leads|trainees|participantes|vendas|países|paises|horas|meses|anos)',
  caseSensitive: false,
);

_BulletAnalysis _analyzeBullet(String text) {
  final stripped = text.replaceAll('•', '').trim();
  final lower = stripped.toLowerCase();

  // 1) Banned verbs / clichés → weak
  for (final b in _bannedVerbs) {
    if (lower.startsWith(b) || lower.contains(' $b ')) {
      return _BulletAnalysis(_BulletStrength.weak, 'Substitua "$b" por verbo de ação no passado');
    }
  }
  for (final c in _cliches) {
    if (lower.contains(c)) {
      return _BulletAnalysis(_BulletStrength.weak, 'Evite o clichê "$c" — Harvard pede fatos, não adjetivos');
    }
  }

  // 2) Strong action verb at start?
  final startsWithStrongVerb = _harvardActionVerbs.any((v) => lower.startsWith('$v '));
  final hasMetric = _metricRegex.hasMatch(stripped);

  if (startsWithStrongVerb && hasMetric) {
    return const _BulletAnalysis(_BulletStrength.strong, 'Verbo de ação forte + métrica concreta');
  }
  if (startsWithStrongVerb) {
    return const _BulletAnalysis(_BulletStrength.medium, 'Forte. Adicione números (quantos, quanto cresceu, ranking) para ficar Harvard.');
  }
  if (hasMetric) {
    return const _BulletAnalysis(_BulletStrength.medium, 'Tem métrica. Considere começar com verbo de ação no passado.');
  }
  return const _BulletAnalysis(_BulletStrength.medium, 'Considere começar com verbo de ação no passado e adicionar números.');
}

class _BulletStrengthBadge extends StatelessWidget {
  final String text;
  const _BulletStrengthBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final analysis = _analyzeBullet(text);
    final (bg, fg, icon, label) = switch (analysis.strength) {
      _BulletStrength.strong => (
          const Color(0xFFD1FAE5),
          const Color(0xFF065F46),
          Icons.check_circle,
          'Forte',
        ),
      _BulletStrength.medium => (
          const Color(0xFFFEF3C7),
          const Color(0xFF92400E),
          Icons.bolt,
          'Pode melhorar',
        ),
      _BulletStrength.weak => (
          const Color(0xFFFEE2E2),
          const Color(0xFF991B1B),
          Icons.warning_amber,
          'Fraco',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  analysis.message,
                  style: TextStyle(
                    color: fg,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
