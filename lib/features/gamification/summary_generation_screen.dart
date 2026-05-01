import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/supabase_repository.dart';
import '../../services/ai_service.dart';
import 'gamification_viewmodel.dart';

enum _SummaryState { initial, loading, result, editing }

class SummaryGenerationScreen extends StatefulWidget {
  final String campaignId;

  const SummaryGenerationScreen({super.key, required this.campaignId});

  @override
  State<SummaryGenerationScreen> createState() => _SummaryGenerationScreenState();
}

class _SummaryGenerationScreenState extends State<SummaryGenerationScreen> {
  final _aiService = AIService();
  final _repo = SupabaseRepository();

  _SummaryState _state = _SummaryState.initial;
  String? _summaryText;
  String? _versionId;
  String? _error;
  int _versionCount = 0;

  final _editController = TextEditingController();

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _state = _SummaryState.loading;
      _error = null;
    });
    try {
      final data = await _aiService.generateSummary(widget.campaignId);
      setState(() {
        _summaryText = data['summary'] as String?;
        _versionId = data['version_id'] as String?;
        _versionCount++;
        _editController.text = _summaryText ?? '';
        _state = _SummaryState.result;
      });
    } catch (e) {
      setState(() {
        _error = 'Não foi possível gerar o resumo. Tente novamente.';
        _state = _SummaryState.initial;
      });
    }
  }

  Future<void> _approve({bool wasEdited = false, String? editedContent}) async {
    setState(() => _state = _SummaryState.loading);
    try {
      await _repo.saveSectionVersion(
        campaignId: widget.campaignId,
        content: _summaryText ?? '',
        versionNumber: _versionCount,
        versionId: _versionId,
        wasEdited: wasEdited,
        editedContent: editedContent,
      );
    } catch (e) {
      print('Error saving summary: $e');
    }
    if (mounted) {
      await context.read<GamificationViewModel>().completePhaseAfterSummary();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _saveUserWritten(String text) async {
    if (text.trim().isEmpty) return;
    setState(() => _state = _SummaryState.loading);
    try {
      await _repo.saveSectionVersion(
        campaignId: widget.campaignId,
        content: text.trim(),
        versionNumber: 1,
        wasEdited: true,
        editedContent: text.trim(),
      );
    } catch (e) {
      print('Error saving user-written summary: $e');
    }
    if (mounted) {
      await context.read<GamificationViewModel>().completePhaseAfterSummary();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _skip() async {
    await context.read<GamificationViewModel>().completePhaseAfterSummary();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: _state == _SummaryState.loading ? null : _skip,
              child: const Text(
                'Pular',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _SummaryState.loading:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF58CC02)),
              SizedBox(height: 16),
              Text(
                'Gerando seu resumo profissional...',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 15),
              ),
            ],
          ),
        );

      case _SummaryState.result:
        return _buildResult();

      case _SummaryState.editing:
        return _buildEditor();

      case _SummaryState.initial:
        return _buildInitial();
    }
  }

  Widget _buildInitial() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.auto_awesome, color: Color(0xFF00C27A), size: 32),
          ),
          const SizedBox(height: 24),
          const Text(
            'Resumo profissional',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'A IA vai criar um parágrafo curto (3-4 linhas) destacando suas experiências, habilidades e o que você busca — pronto para o topo do seu currículo.',
            style: TextStyle(fontSize: 15, color: Color(0xFF6B7280), height: 1.5),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _generate,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF58CC02),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                'Gerar resumo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: () {
                _editController.clear();
                setState(() => _state = _SummaryState.editing);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                side: const BorderSide(color: Color(0xFFE5E7EB), width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Escrever do zero', style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildResult() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Resumo gerado',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Versão $_versionCount',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(
                    _summaryText ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF374151),
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        _buildResultActions(),
      ],
    );
  }

  Widget _buildResultActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => _approve(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF58CC02),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Usar este',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _generate,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFE5E7EB), width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Gerar outro', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {
                        _editController.text = _summaryText ?? '';
                        setState(() => _state = _SummaryState.editing);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFE5E7EB), width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Editar', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    final isFromAI = _summaryText != null;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFromAI ? 'Editar resumo' : 'Escrever resumo',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '3 a 4 linhas destacando sua experiência e objetivos.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TextField(
                    controller: _editController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF374151), height: 1.6),
                    decoration: InputDecoration(
                      hintText: 'Ex: Estudante de Administração com experiência em estágios corporativos...',
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF58CC02), width: 2),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                if (isFromAI) ...[
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => setState(() => _state = _SummaryState.result),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        side: const BorderSide(color: Color(0xFFE5E7EB), width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Icon(Icons.arrow_back, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        final text = _editController.text.trim();
                        if (text.isEmpty) return;
                        if (isFromAI) {
                          _approve(wasEdited: true, editedContent: text);
                        } else {
                          _saveUserWritten(text);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF58CC02),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Salvar resumo',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
