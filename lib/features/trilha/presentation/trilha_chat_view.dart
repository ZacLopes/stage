// View do chat da trilha v2 (PLANO chat v2 — F2 + F3).
//
// Renderiza o FIO (bolhas da IA + cards de resposta editáveis + o widget inline
// do passo atual + o gate de import + bolha de arquivo + card-resumo) e a BARRA
// inferior fixa (texto + 📎 anexar + ▶ enviar). Observa o [TrilhaChatController].
// Sem doca que sobe: os widgets vivem no fio; o teclado só na barra (texto livre).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../services/cv_import_service.dart';
import '../application/trilha_hub_status.dart';
import '../application/trilha_section.dart';
import 'trilha_chat_controller.dart';
import 'widgets/chat_bubbles.dart';
import 'widgets/import_conflict_card.dart';
import 'widgets/languages_editor_card.dart';
import 'widgets/list_editor_card.dart';
import 'widgets/inline/inline_step_input.dart';
import 'widgets/inline/trilha_answer_card.dart';

class TrilhaChatView extends StatefulWidget {
  const TrilhaChatView({
    super.key,
    required this.controller,
    this.onVerifySection,
    this.hubStatus,
  });

  final TrilhaChatController controller;

  /// Toque num tile do resumo do import → abre o sheet de verificação daquela
  /// seção (null = tiles não-tocáveis).
  final void Function(TrilhaSection section)? onVerifySection;

  /// Força honesta do perfil pro card de conclusão (força real + próximo ganho,
  /// nunca "forte" com lacuna aberta). Null ⇒ cai no texto genérico.
  final TrilhaHubStatus? hubStatus;

  @override
  State<TrilhaChatView> createState() => _TrilhaChatViewState();
}

class _TrilhaChatViewState extends State<TrilhaChatView>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _text = TextEditingController();

  /// FocusNode ESTÁVEL da barra de digitar. Sem ele, o TextField usa um node
  /// interno que, nesta subárvore muito re-buildada (watch do VM + 2
  /// AnimatedBuilder + reflow do teclado), pode ficar destacado no frame do
  /// toque — aí o guard global de "tocar fora fecha o teclado" (main.dart) lê
  /// "nenhum campo focado" e FECHA o teclado ao tocar na própria barra (ex.:
  /// pra colar). Um node próprio do State persiste e mantém o foco estável.
  final FocusNode _inputFocus = FocusNode();

  /// Âncora do card em edição — pra rolar ATÉ ele (e não pro fim do fio) quando
  /// o usuário toca no lápis de uma resposta lá em cima.
  final GlobalKey _editAnchorKey = GlobalKey();

  /// Âncora do card de conflito de import MAIS RECENTE — pra trazer o TOPO dele
  /// à vista quando aparece (senão o auto-scroll pro fim deixava o user no
  /// botão "Aplicar" e ele tinha que rolar pra cima pra ver os pontos).
  final GlobalKey _newConflictKey = GlobalKey();

  /// Tamanho do fio no último sync — pra distinguir "mensagem nova" (rola) de
  /// "interação num card existente" (NÃO arranca o user pro fim).
  int _lastThreadLen = 0;

  /// Coach-mark de 1ª vez apontando o ✦ ("toca aqui pra ver tudo que eu faço").
  /// O usuário pode não notar o botão — este balão ensina, uma vez só.
  static const String _coachSeenKey = 'trilha_assist_coach_v1';
  bool _showCoach = false;

  TrilhaChatController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_onTick);
    // ignore: unawaited_futures
    _loadCoach();
  }

  Future<void> _loadCoach() async {
    if (!_c.assistEnabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_coachSeenKey) ?? false) return;
    } catch (_) {
      return; // sem prefs → não arrisca mostrar sempre
    }
    if (mounted) setState(() => _showCoach = true);
  }

  void _dismissCoach() {
    if (!_showCoach) return;
    setState(() => _showCoach = false);
    // ignore: unawaited_futures
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_coachSeenKey, true))
        .catchError((_) => false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onTick);
    _scroll.dispose();
    _text.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onTick() => _syncScroll();

  @override
  void didChangeMetrics() {
    if (mounted) _syncScroll();
  }

  // Editando um card lá em cima? Traz ELE pra vista (perto do topo) e o mantém
  // visível quando o teclado sobe — em vez de colar no fim do fio. Fora de
  // edição: acompanha sempre a última bolha.
  void _syncScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_c.isEditing) {
        final ctx = _editAnchorKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            // Encosta o card perto do topo, deixando a pergunta logo acima à
            // mostra e o widget inteiro acima do teclado.
            alignment: 0.15,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
        _lastThreadLen = _c.thread.length;
        return;
      }
      final grew = _c.thread.length > _lastThreadLen;
      _lastThreadLen = _c.thread.length;

      // Card de conflito recém-adicionado (é o último do fio) → traz o TOPO dele
      // à vista, não o fim (senão o user cai no "Aplicar" e não vê os pontos).
      if (grew && _c.thread.isNotEmpty && _c.thread.last is ImportConflictItem) {
        final ctx = _newConflictKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              alignment: 0.02,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic);
          return;
        }
      }

      // Interação IN-PLACE num card de conflito (marcar/editar linha) NÃO pode
      // puxar pro fim — nem quando o card está a <160px do fim (o de várias
      // linhas cabe na tolerância e o guard de distância abaixo não pegaria).
      if (!grew &&
          _c.thread.isNotEmpty &&
          _c.thread.last is ImportConflictItem) {
        return;
      }
      final target = _scroll.position.maxScrollExtent;
      final distance = target - _scroll.offset;
      // Só puxa pro fim quando CHEGOU mensagem nova, OU o user já está colado no
      // fim. Se ele rolou pra cima (mexendo num card), NÃO arranca ele de lá.
      if (!grew && distance > 160) return;
      if (distance.abs() < 1) return;
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    });
  }

  void _sendText() {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    _text.clear();
    // ignore: unawaited_futures
    _c.submitFreeText(t);
  }

  /// Anexar/importar CV — reaproveita o pipeline existente; UI nova.
  Future<void> _import() async {
    final result = await CvImportService.pickAndImport(context);
    if (!mounted) return;
    if (result.success) {
      // Mesmo sem texto usável (PDF salvo, extração não roda): segue o fluxo —
      // o controller cai na conversa (extractionExpected=false pula o poll).
      // Sem isso, o gate ficaria preso num no-op silencioso.
      // Bolha mostra o NOME REAL do arquivo (não o título da biblioteca).
      // ignore: unawaited_futures
      _c.onCvUploaded(result.fileName ?? result.title ?? 'currículo.pdf',
          extractionExpected: result.textWasUsable);
    } else if (result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.errorMessage!),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Column(
          children: [
            Expanded(child: _thread()),
            if (_showCoach && _c.assistEnabled) _coachMark(),
            _bottomBar(),
          ],
        );
      },
    );
  }

  Widget _thread() {
    final c = _c;
    final children = <Widget>[];

    for (var i = 0; i < c.thread.length; i++) {
      final item = c.thread[i];
      if (item is AiMsgItem) {
        final prevIsAi = i > 0 && c.thread[i - 1] is AiMsgItem;
        children.add(Padding(
          key: ValueKey('ai-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AiBubble(text: item.text, showAvatar: !prevIsAi),
        ));
      } else if (item is UserMsgItem) {
        children.add(Padding(
          key: ValueKey('user-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _userBubble(item.text),
        ));
      } else if (item is FileBubbleItem) {
        children.add(Padding(
          key: ValueKey('file-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _fileBubble(item.name),
        ));
      } else if (item is ImportSummaryItem) {
        children.add(Padding(
          key: ValueKey('summary-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _importSummary(item.summary),
        ));
      } else if (item is AssistEditItem) {
        children.add(Padding(
          key: ValueKey('edit-item-${item.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _assistEditCard(item),
        ));
      } else if (item is AssistExtractItem) {
        children.add(Padding(
          key: ValueKey('extract-${item.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _assistExtractCard(item),
        ));
      } else if (item is ListEditorItem) {
        children.add(Padding(
          key: ValueKey('list-editor-${item.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: ListEditorCard(
            item: item,
            onApply: (added, removed) =>
                _c.applyListEditor(item.id, added: added, removed: removed),
            onCancel: () => _c.cancelListEditor(item.id),
            onUndo: () => _c.undoListEditor(item.id),
          ),
        ));
      } else if (item is LanguagesEditorItem) {
        children.add(Padding(
          key: ValueKey('lang-editor-${item.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: LanguagesEditorCard(
            item: item,
            onApply: (added, removed, changed) => _c.applyLanguagesEditor(
                item.id, added: added, removed: removed, changed: changed),
            onCancel: () => _c.cancelLanguagesEditor(item.id),
            onUndo: () => _c.undoLanguagesEditor(item.id),
          ),
        ));
      } else if (item is JobsCardItem) {
        children.add(Padding(
          key: ValueKey('jobs-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _jobsCard(item),
        ));
      } else if (item is GapsCardItem) {
        children.add(Padding(
          key: ValueKey('gaps-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _gapsCard(item),
        ));
      } else if (item is ImportConflictItem) {
        children.add(Padding(
          key: ValueKey('conflict-${item.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: ImportConflictCard(
            // Só o conflito MAIS RECENTE (último do fio) ganha a âncora — o
            // _syncScroll traz o topo dele à vista. GlobalKey tem que ser único.
            key: i == c.thread.length - 1 ? _newConflictKey : null,
            item: item,
            onToggle: (rowId, accepted) =>
                _c.toggleConflictRow(item.id, rowId, accepted),
            onEdit: (rowId, value) => _c.editConflictRow(item.id, rowId, value),
            onApply: () {
              // ignore: unawaited_futures
              _c.applyConflicts(item.id);
            },
            onCancel: () => _c.cancelConflicts(item.id),
            onUndo: () {
              // ignore: unawaited_futures
              _c.undoConflicts(item.id);
            },
          ),
        ));
      } else if (item is AssistActionCardItem) {
        children.add(Padding(
          key: ValueKey('action-${item.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _actionCard(item),
        ));
      } else if (item is StarterChipsItem) {
        children.add(Padding(
          key: ValueKey('starter-$i'),
          // Alinha com o texto das bolhas da IA (avatar 34 + gap).
          padding: const EdgeInsets.only(
              left: 34 + AppSpacing.sm, bottom: AppSpacing.md),
          child: _starterChips(item),
        ));
      } else if (item is AnsweredItem) {
        if (c.editingIndex == i && c.activeStep != null) {
          children.add(Padding(
            key: ValueKey('edit-$i'),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _EditFrame(
              key: _editAnchorKey,
              onCancel: c.cancelEdit,
              // initialAnswer → o widget reabre com o que já estava escrito.
              child: InlineStepInput(
                step: c.activeStep!,
                initialAnswer: item.exchange.answer,
                onSubmit: c.submit,
              ),
            ),
          ));
        } else {
          children.add(KeyedSubtree(
            key: ValueKey('ans-$i'),
            child: TrilhaAnswerCard(
              exchange: item.exchange,
              onEdit: item.exchange.step.reversible
                  ? () => c.beginEdit(item)
                  : null,
            ),
          ));
        }
      }
    }

    // Gate de import (abertura).
    if (c.phase == ChatPhase.gate) {
      children.add(Padding(
        key: const ValueKey('gate'),
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _gateChoice(),
      ));
    }

    // Passo atual (conversa): widget inline no fim do fio.
    if (c.phase == ChatPhase.converse &&
        c.inputVisible &&
        !c.isEditing &&
        c.activeStep != null) {
      children.add(Padding(
        key: ValueKey('current-${c.activeStep!.id}'),
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: InlineStepInput(step: c.activeStep!, onSubmit: c.submit),
      ));
    }

    if (c.typing) {
      children.add(const Padding(
        key: ValueKey('typing'),
        padding: EdgeInsets.only(bottom: AppSpacing.md),
        child: TypingBubble(),
      ));
    }

    if (c.finished) children.add(_completionCard(c));

    return ListView(
      controller: _scroll,
      padding: AppSpacing.allBase,
      children: children,
    );
  }

  // ── Gate de import ──────────────────────────────────────────────────────────

  Widget _gateChoice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: 'Preencher meu perfil',
          icon: Icons.add_rounded,
          onPressed: () {
            // ignore: unawaited_futures
            _c.chooseZero();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          label: 'Já tenho um currículo',
          icon: Icons.upload_rounded,
          onPressed: _import,
        ),
      ],
    );
  }

  // ── Bolha de arquivo ────────────────────────────────────────────────────────

  Widget _userBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: 11),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(text,
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.onPrimary)),
      ),
    );
  }

  Widget _fileBubble(String name) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: AppSpacing.allSm,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.onPrimary.withValues(alpha: 0.18),
                borderRadius: AppRadius.brSm,
              ),
              child: const Icon(Icons.description_rounded,
                  size: 18, color: AppColors.onPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMd
                      .copyWith(color: AppColors.onPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card-resumo da extração ─────────────────────────────────────────────────

  // ── Card de vagas reais (Grande: consulta ao feed) ────────────────────────

  Widget _jobsCard(JobsCardItem item) {
    final outOfProfile = item.outOfProfileArea.isNotEmpty;
    final sub = outOfProfile
        ? 'Fora das suas áreas — toca numa pra ver, ou salva 👇'
        : (item.hasResume
            ? 'Toca numa vaga pra ver ou salvar 👇'
            : 'Complete seu perfil pra eu calcular o match 👇');
    return Container(
      // Alinha com o texto das bolhas da IA: avatar (34) + gap (AppSpacing.sm).
      margin: const EdgeInsets.only(left: 34 + AppSpacing.sm),
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(outOfProfile ? 'Vagas de ${item.outOfProfileArea}' : 'Vagas pra você',
              style: AppTextStyles.overline),
          const SizedBox(height: 2),
          Text(sub,
              style:
                  AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpacing.sm),
          for (final j in item.jobs) _jobRow(item, j),
          if (outOfProfile) ...[
            const SizedBox(height: AppSpacing.xs),
            SecondaryButton(
              // Toggle: adiciona a área OU remove (se adicionou por engano). O
              // label é curto de propósito — a área já está no header ("Vagas de
              // X") e o completo estourava a borda no device-test.
              label: item.areaAdded
                  ? 'Remover das minhas áreas'
                  : 'Adicionar às minhas áreas',
              icon: item.areaAdded
                  ? Icons.close_rounded
                  : Icons.add_rounded,
              onPressed: () {
                // ignore: unawaited_futures
                _c.addAreaFromCard(item.id, item.outOfProfileArea);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _jobRow(JobsCardItem item, AssistJobRow j) {
    final sub = [j.company, if (j.area.isNotEmpty) j.area].join(' · ');
    final saved = item.savedIds.contains(j.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: () {
          // ignore: unawaited_futures
          _c.openJobFromCard(j.id);
        },
        borderRadius: AppRadius.brMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(j.title,
                        style: AppTextStyles.bodyMd
                            .copyWith(fontWeight: FontWeight.w600)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          style: AppTextStyles.bodySm
                              .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              if (j.hasScore) ...[
                const SizedBox(width: AppSpacing.sm),
                _matchBadge(j.score),
              ],
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  size: 20,
                  color: saved ? AppColors.primary : AppColors.textTertiary,
                ),
                tooltip: saved ? 'Tirar das salvas' : 'Salvar',
                onPressed: () {
                  // Toggle: salva se não estava, des-salva se já estava.
                  // ignore: unawaited_futures
                  _c.saveJobFromCard(item.id, j.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Card de ação (exportar/importar): botão que dispara a ação nativa ──────

  Widget _actionCard(AssistActionCardItem item) {
    const margin = EdgeInsets.only(left: 34 + AppSpacing.sm);
    final isExport = item.kind == 'export';
    if (item.status == AssistEditStatus.cancelled) {
      return Container(
        margin: margin,
        child: Text('Beleza, deixa pra depois.',
            style:
                AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary)),
      );
    }
    if (item.status == AssistEditStatus.applied) {
      return Container(
        margin: margin,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.check_circle_rounded,
                  size: 16, color: AppColors.success),
              const SizedBox(width: 6),
              Flexible(
                  child:
                      Text(item.resultMessage, style: AppTextStyles.bodyMd)),
            ]),
            // Import salvou o PDF na biblioteca (aba Perfil) → atalho pra ver.
            if (item.showCvLibraryLink) ...[
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Ver arquivo importado',
                icon: Icons.folder_open_rounded,
                expand: false,
                onPressed: () {
                  // ignore: unawaited_futures
                  _c.openCvLibraryFromCard();
                },
              ),
            ],
          ],
        ),
      );
    }
    // pending (com botão)
    return Container(
      margin: margin,
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isExport
                ? 'É só tocar pra gerar o PDF do seu currículo:'
                : 'É só tocar pra escolher o PDF do seu CV:',
            style: AppTextStyles.bodyMd,
          ),
          if (item.resultMessage.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(item.resultMessage,
                style: AppTextStyles.bodySm.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: isExport ? 'Exportar PDF' : 'Importar CV',
            icon: isExport
                ? Icons.upload_rounded
                : Icons.file_upload_outlined,
            isLoading: item.running,
            onPressed: item.running
                ? null
                : () {
                    // ignore: unawaited_futures
                    _c.runActionCard(item.id);
                  },
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: TextButton(
              // Trava o cancelar enquanto a ação roda (senão o cancel corria com
              // o resultado em voo e um sobrescrevia o outro).
              onPressed:
                  item.running ? null : () => _c.cancelActionCard(item.id),
              child: Text('Agora não',
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textTertiary)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Chips de partida (descoberta de capacidades) ──────────────────────────

  IconData _starterChipIcon(String id) {
    switch (id) {
      case 'import':
        return Icons.file_upload_outlined;
      case 'zero':
        return Icons.add_rounded;
      case 'jobs':
        return Icons.search_rounded;
      case 'gaps':
        return Icons.checklist_rounded;
      case 'summary':
        return Icons.auto_awesome_rounded;
      case 'exp':
        return Icons.work_outline_rounded;
      case 'capabilities':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.chevron_right_rounded;
    }
  }

  Widget _starterChips(StarterChipsItem item) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final chip in item.chips) _starterChip(chip)],
    );
  }

  Widget _starterChip(StarterChip chip) {
    final icon = _starterChipIcon(chip.id);
    // "Tudo que eu faço" abre a vitrine PERMANENTE (não some os chips).
    if (chip.id == 'capabilities') {
      return AppChip(label: chip.label, icon: icon, onTap: _openCapabilitiesSheet);
    }
    if (!chip.hero) {
      return AppChip(
        label: chip.label,
        icon: icon,
        onTap: () {
          // ignore: unawaited_futures
          _c.onStarterChip(chip);
        },
      );
    }
    // Herói (melhor próxima ação): pílula no gradiente da marca.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        // ignore: unawaited_futures
        _c.onStarterChip(chip);
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.brand,
          borderRadius: AppRadius.brPill,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.onPrimary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              chip.label,
              style: AppTextStyles.labelMd.copyWith(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _matchBadge(int score) {
    // Baldes iguais aos do detalhe da vaga: ≥70 forte, ≥40 médio, senão fraco.
    final strong = score >= 70;
    final mid = score >= 40;
    final color = strong
        ? AppColors.success
        : (mid ? AppColors.primary : AppColors.textTertiary);
    final bg = strong
        ? AppColors.successSoft
        : (mid ? AppColors.primarySoft : AppColors.surfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brSm),
      child: Text('$score%',
          style: AppTextStyles.labelSm.copyWith(color: color)),
    );
  }

  // ── Card de lacunas/resumo (Grande: render estruturado) ───────────────────

  Widget _gapsCard(GapsCardItem item) {
    final pct = item.completionPercent.clamp(0, 100);
    return Container(
      margin: const EdgeInsets.only(left: 34 + AppSpacing.sm),
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Seu perfil', style: AppTextStyles.overline),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.brSm,
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 8,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('$pct%',
                  style:
                      AppTextStyles.labelSm.copyWith(color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (item.rows.isEmpty)
            Text('Tá completo! 🎉 Seu perfil já cobre o essencial.',
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textTertiary))
          else ...[
            Text('Toca no que você quer preencher agora 👇',
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: AppSpacing.sm),
            // Cap pra não virar um card gigante quando o perfil está bem vazio.
            for (final r in item.rows.take(6)) _gapRow(r),
            if (item.rows.length > 6)
              Text('+ ${item.rows.length - 6} pra reforçar',
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textTertiary)),
          ],
        ],
      ),
    );
  }

  Widget _gapRow(GapRow r) {
    final color = switch (r.tier) {
      'tier1' => AppColors.primary,
      'tier2' => AppColors.textSecondary,
      _ => AppColors.textTertiary,
    };
    // Conduzível (tem section) ⇒ vira botão que começa a preencher a seção.
    final tappable = r.section.isNotEmpty;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(_gapIcon(r.key), size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(r.label, style: AppTextStyles.bodyMd)),
          if (tappable)
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.primary),
        ],
      ),
    );
    if (!tappable) return row;
    return InkWell(
      onTap: () {
        // ignore: unawaited_futures
        _c.fillGapFromCard(r.section);
      },
      borderRadius: AppRadius.brMd,
      child: row,
    );
  }

  IconData _gapIcon(String key) => switch (key) {
        'area' => Icons.category_outlined,
        'desiredPosition' => Icons.badge_outlined,
        'workMode' => Icons.laptop_outlined,
        'jobType' => Icons.schedule_outlined,
        'city' => Icons.place_outlined,
        'educationStatus' => Icons.school_outlined,
        'skills' => Icons.bolt_outlined,
        'experience' => Icons.work_outline,
        'languages' => Icons.translate_outlined,
        'summary' => Icons.notes_outlined,
        'linkedin' => Icons.link_outlined,
        'certifications' => Icons.verified_outlined,
        'awards' => Icons.emoji_events_outlined,
        'projects' => Icons.folder_outlined,
        'availability' => Icons.event_available_outlined,
        'interests' => Icons.favorite_outline,
        'companyStage' => Icons.business_outlined,
        'workEnvironment' => Icons.groups_outlined,
        'workStyle' => Icons.tune_outlined,
        _ => Icons.circle_outlined,
      };

  Widget _importSummary(ImportSummary s) {
    final cells = <(int, String, TrilhaSection)>[
      (s.experiences, 'experiências', TrilhaSection.experiencia),
      (s.skills, 'habilidades', TrilhaSection.skills),
      (s.languages, 'idiomas', TrilhaSection.idiomas),
      (s.education, 'formação', TrilhaSection.formacao),
    ].where((c) => c.$1 > 0).toList();

    return Container(
      // Alinha com o texto das bolhas da IA: avatar (34) + gap (AppSpacing.sm).
      margin: const EdgeInsets.only(left: 34 + AppSpacing.sm),
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('O que encontrei', style: AppTextStyles.overline),
          const SizedBox(height: 2),
          Text('Toque pra conferir cada um 👇',
              style: AppTextStyles.bodySm
                  .copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [for (final c in cells) _summaryTile(c.$1, c.$2, c.$3)],
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Revisar e confirmar',
            onPressed: () {
              // ignore: unawaited_futures
              _c.confirmImport();
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(int count, String label, TrilhaSection section) {
    final onVerify = widget.onVerifySection;
    return InkWell(
      onTap: onVerify == null ? null : () => onVerify(section),
      borderRadius: AppRadius.brMd,
      child: Container(
        width: 132,
        padding: AppSpacing.allMd,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$count',
                    style: AppTextStyles.headlineMd
                        .copyWith(color: AppColors.primary)),
                const Spacer(),
                if (onVerify != null)
                  Icon(Icons.visibility_outlined,
                      size: 15,
                      color: AppColors.primary.withValues(alpha: 0.7)),
              ],
            ),
            Text(label,
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  // ── Card de alteração do assistente (Fase B): confirmar → aplicado → desfazer

  Widget _assistEditCard(AssistEditItem item) {
    // Alinha com o texto das bolhas da IA (avatar 34 + gap).
    const margin = EdgeInsets.only(left: 34 + AppSpacing.sm);
    final isRemove = item.op == AssistEditOp.remove;
    final isAdd = item.op == AssistEditOp.add;

    if (item.status == AssistEditStatus.cancelled) {
      return Container(
        margin: margin,
        child: Text('Cancelado.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary)),
      );
    }
    if (item.status == AssistEditStatus.undone) {
      final txt = switch (item.op) {
        AssistEditOp.update =>
          '${item.fieldLabel} voltou pra ${item.beforeText.isEmpty ? '—' : item.beforeText}.',
        AssistEditOp.add => '${item.afterText} removido de novo.',
        AssistEditOp.remove => '${item.afterText} voltou pra ${item.fieldLabel}.',
        AssistEditOp.bullet => 'Bullet (${item.fieldLabel}) voltou ao original.',
      };
      return Container(
        margin: margin,
        child: Row(children: [
          const Icon(Icons.undo_rounded, size: 15, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Flexible(
              child: Text(txt,
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textTertiary))),
        ]),
      );
    }

    final applied = item.status == AssistEditStatus.applied;
    // Cor de acento: destrutivo (remove) usa warning; resto usa primary.
    final accent = isRemove ? AppColors.warning : AppColors.primary;
    final headerTitle = applied
        ? (isRemove ? 'Removi' : isAdd ? 'Adicionei' : 'Alterei no seu perfil')
        : (isRemove ? 'Confirmar remoção' : 'Confirmar alteração');
    final headerIcon = applied
        ? Icons.check_circle_rounded
        : (isRemove ? Icons.delete_outline_rounded : Icons.edit_rounded);

    return Container(
      margin: margin,
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: applied
            ? AppColors.surface
            : accent.withValues(alpha: isRemove ? 0.10 : 0.14),
        borderRadius: AppRadius.brLg,
        border: Border.all(
            color: applied ? AppColors.border : accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(headerIcon,
                  size: 15, color: applied ? AppColors.success : accent),
              const SizedBox(width: 6),
              Text(headerTitle,
                  style: AppTextStyles.overline
                      .copyWith(color: applied ? AppColors.success : accent)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            switch (item.op) {
              AssistEditOp.bullet => 'Bullet · ${item.fieldLabel}',
              AssistEditOp.remove => 'Remover de ${item.fieldLabel}',
              AssistEditOp.add => 'Adicionar em ${item.fieldLabel}',
              AssistEditOp.update => item.fieldLabel,
            },
            style: AppTextStyles.labelSm.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 4),
          // Texto longo (resumo/bullet) → antes/depois EMPILHADO; curto → inline.
          if ((item.op == AssistEditOp.update || item.op == AssistEditOp.bullet) &&
              (item.field == 'summary' ||
                  item.op == AssistEditOp.bullet ||
                  item.afterText.length > 60 ||
                  item.beforeText.length > 60)) ...[
            if (item.beforeText.isNotEmpty && item.beforeText != '—') ...[
              _summaryBlock('Antes', item.beforeText, muted: true),
              const SizedBox(height: AppSpacing.sm),
            ],
            _summaryBlock('Depois', item.afterText, muted: false),
          ] else
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                if (item.op == AssistEditOp.update &&
                    item.beforeText.isNotEmpty &&
                    item.beforeText != '—') ...[
                  Text(item.beforeText,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textTertiary,
                        decoration: TextDecoration.lineThrough,
                      )),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 15, color: AppColors.textTertiary),
                ],
                Text(item.afterText,
                    style: AppTextStyles.titleSm.copyWith(
                      color: AppColors.textPrimary,
                      decoration: (applied && isRemove)
                          ? TextDecoration.lineThrough
                          : null,
                    )),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          if (applied)
            Align(
              alignment: Alignment.centerLeft,
              child: _editPill(
                icon: Icons.undo_rounded,
                label: 'Desfazer',
                onTap: () => _c.undoAssistEdit(item.id),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _confirmButton(
                    label: isRemove ? 'Remover' : 'Aplicar',
                    color: isRemove ? AppColors.error : AppColors.primary,
                    onTap: () => _c.confirmAssistEdit(item.id),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _editPill(
                  label: 'Cancelar',
                  onTap: () => _c.cancelAssistEdit(item.id),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // Card "Peguei isto 👇": vários campos simples extraídos de um textão colado,
  // confirmados de uma vez; espelha o ImportSummaryItem (lista + aplicar/desfazer).
  Widget _assistExtractCard(AssistExtractItem item) {
    const margin = EdgeInsets.only(left: 34 + AppSpacing.sm);

    if (item.status == AssistEditStatus.cancelled) {
      return Container(
        margin: margin,
        child: Text('Cancelado.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary)),
      );
    }
    if (item.status == AssistEditStatus.undone) {
      return Container(
        margin: margin,
        child: Row(children: [
          const Icon(Icons.undo_rounded, size: 15, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Flexible(
              child: Text('Desfeito — não adicionei nada.',
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textTertiary))),
        ]),
      );
    }

    final applied = item.status == AssistEditStatus.applied;
    final accent = AppColors.primary;

    return Container(
      margin: margin,
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: applied ? AppColors.surface : accent.withValues(alpha: 0.14),
        borderRadius: AppRadius.brLg,
        border: Border.all(
            color: applied ? AppColors.border : accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(applied ? Icons.check_circle_rounded : Icons.auto_awesome_rounded,
                  size: 15, color: applied ? AppColors.success : accent),
              const SizedBox(width: 6),
              Text(applied ? 'Adicionei ao seu perfil' : 'Peguei isto 👇',
                  style: AppTextStyles.overline
                      .copyWith(color: applied ? AppColors.success : accent)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final e in item.entries) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_extractIcon(e.kind),
                    size: 15, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(e.label,
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: AppSpacing.xs),
          if (applied)
            Align(
              alignment: Alignment.centerLeft,
              child: _editPill(
                icon: Icons.undo_rounded,
                label: 'Desfazer',
                onTap: () => _c.undoExtract(item.id),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _confirmButton(
                    label: 'Aplicar tudo',
                    color: AppColors.primary,
                    onTap: () => _c.confirmExtract(item.id),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _editPill(
                  label: 'Cancelar',
                  onTap: () => _c.cancelExtract(item.id),
                ),
              ],
            ),
        ],
      ),
    );
  }

  IconData _extractIcon(String kind) {
    switch (kind) {
      case 'skill':
        return Icons.bolt_rounded;
      case 'language':
        return Icons.translate_rounded;
      case 'desired_position':
        return Icons.work_outline_rounded;
      default:
        return Icons.check_rounded;
    }
  }

  Widget _summaryBlock(String label, String text, {required bool muted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.overline.copyWith(
                color: muted ? AppColors.textTertiary : AppColors.primary)),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: AppSpacing.allSm,
          decoration: BoxDecoration(
            color: muted ? AppColors.surfaceVariant : AppColors.surface,
            borderRadius: AppRadius.brMd,
            border: Border.all(
                color: muted
                    ? AppColors.border
                    : AppColors.primary.withValues(alpha: 0.25)),
          ),
          child: Text(text,
              style: AppTextStyles.bodySm.copyWith(
                  color: muted ? AppColors.textTertiary : AppColors.textPrimary,
                  decoration:
                      muted ? TextDecoration.lineThrough : null)),
        ),
      ],
    );
  }

  Widget _confirmButton(
      {required String label,
      required Color color,
      required VoidCallback onTap}) {
    return Material(
      color: color,
      borderRadius: AppRadius.brMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brMd,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          child: Text(label,
              style:
                  AppTextStyles.labelLg.copyWith(color: AppColors.onPrimary)),
        ),
      ),
    );
  }

  Widget _editPill({IconData? icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.brPill,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brPill,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: AppRadius.brPill,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: AppTextStyles.labelMd
                      .copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Card de conclusão ───────────────────────────────────────────────────────

  Widget _completionCard(TrilhaChatController c) {
    return Padding(
      key: const ValueKey('done-card'),
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: AppCard(
        variant: AppCardVariant.gradient,
        child: c.finalizing
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const TypingDots(color: AppColors.onPrimary),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: Text('Montando seu resumo com a IA…',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMd
                            .copyWith(color: AppColors.onPrimary)),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                      widget.hubStatus?.level == HubLevel.building
                          ? Icons.trending_up_rounded
                          : Icons.celebration_rounded,
                      color: AppColors.onPrimary,
                      size: 36),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                        widget.hubStatus?.title ?? 'Perfil mais forte! 🎉',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleMd
                            .copyWith(color: AppColors.onPrimary)),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    // Honesto: o próximo ganho (força real) — não "está tudo forte".
                    // O resumo que a IA gera sobre o usuário NÃO aparece mais aqui
                    // no chat (decisão do fundador): ele vive no preview do
                    // Currículo/Perfil, não numa bolha da conversa.
                    widget.hubStatus?.message ??
                        'Quanto mais completo, mais empresas conseguem te achar.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMd
                        .copyWith(color: AppColors.onPrimary),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Barra inferior ──────────────────────────────────────────────────────────

  Widget _bottomBar() {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md,
          AppSpacing.sm + bottomSafe),
      child: Row(
        children: [
          // 📎 só no GATE: importar é ação de abertura. Depois, re-importar
          // reconstruiria a sessão e perderia o progresso (ver onCvUploaded).
          if (_c.phase == ChatPhase.gate) ...[
            _circleButton(
              icon: Icons.attach_file_rounded,
              filled: false,
              onTap: _import,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          // ✦ acesso PERMANENTE à descoberta ("No que eu te ajudo") — os chips
          // de partida são uso único; este ✦ deixa o usuário reabrir e ver tudo
          // que o copiloto faz a qualquer momento.
          if (_c.assistEnabled) ...[
            _SparkleButton(onTap: _openCapabilitiesSheet),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: AppRadius.brPill,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.textPrimary),
                      // Sem o fill/borda do tema global (que desenhava um
                      // "retângulo dentro" da pílula) — só o texto.
                      decoration: InputDecoration(
                        hintText: 'Escreva uma mensagem…',
                        hintStyle: AppTextStyles.bodyMd
                            .copyWith(color: AppColors.textTertiary),
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _circleButton(
            icon: Icons.send_rounded,
            filled: true,
            onTap: _sendText,
          ),
        ],
      ),
    );
  }

  Widget _circleButton(
      {required IconData icon,
      required bool filled,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : AppColors.surface,
          shape: BoxShape.circle,
          border: filled ? null : Border.all(color: AppColors.border),
        ),
        child: Icon(icon,
            size: 20,
            color: filled ? AppColors.onPrimary : AppColors.textTertiary),
      ),
    );
  }

  Widget _coachMark() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissCoach,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: AppRadius.brMd,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.30),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.onPrimary, size: 15),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Toca no ✦ pra ver tudo que eu faço',
                      style: AppTextStyles.labelMd.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.close_rounded,
                    color: AppColors.onPrimary, size: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCapabilitiesSheet() {
    _dismissCoach(); // já descobriu → não precisa mais do coach
    _c.trackCapabilitiesOpened();
    HapticFeedback.selectionClick();
    // ignore: unawaited_futures
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CapabilitiesSheet(
        onPick: (message) {
          Navigator.of(context).pop();
          // ignore: unawaited_futures
          _c.submitFreeText(message);
        },
      ),
    );
  }
}

/// Vitrine "No que eu te ajudo" — acesso PERMANENTE à descoberta do copiloto
/// (os chips de partida são uso único). 3 categorias: Currículo · Vagas ·
/// Carreira — a de Carreira (conselho, não captura de dado) é a prova de que é
/// copiloto, não preenchedor. Tocar num exemplo fecha a folha e manda pro chat.

/// Vitrine "No que eu te ajudo" — acesso PERMANENTE à descoberta do copiloto
/// (os chips de partida são uso único). Header no gradiente da marca + 3
/// categorias (Currículo · Vagas · Carreira, cada uma com cor própria) que
/// entram escalonadas. A de Carreira (conselho, não captura de dado) é a prova
/// de que é copiloto, não preenchedor. Tocar num exemplo fecha e manda pro chat.
class _CapabilitiesSheet extends StatefulWidget {
  const _CapabilitiesSheet({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  State<_CapabilitiesSheet> createState() => _CapabilitiesSheetState();
}

class _CapabilitiesSheetState extends State<_CapabilitiesSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in;

  static const List<_CapCategory> _categories = [
    _CapCategory(
      icon: Icons.description_rounded,
      accent: AppColors.primary,
      title: 'Perfil e currículo',
      desc: 'Completo seu perfil e preparo seu currículo',
      examples: [
        'Importa meu CV (PDF)',
        'Melhora meu resumo',
        'Adiciona Python nas skills',
        'Exporta em PDF',
      ],
    ),
    _CapCategory(
      icon: Icons.work_outline_rounded,
      accent: AppColors.brandCyan,
      title: 'Suas vagas',
      desc: 'Acho e comparo vagas com a sua cara',
      examples: [
        'Tem vaga de marketing?',
        'Quais combinam comigo?',
        'Estágios remotos',
      ],
    ),
    _CapCategory(
      icon: Icons.trending_up_rounded,
      accent: AppColors.warning,
      title: 'Sua carreira',
      desc: 'Tiro suas dúvidas e te oriento',
      examples: [
        'O que falta no meu perfil?',
        'Currículo sem experiência, e agora?',
        'Como funciona a candidatura?',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 950))
      ..forward();
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  double _seg(double a, double b) =>
      Curves.easeOut.transform(((_in.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.74,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.zero,
          children: [
            _header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
              child: Column(
                children: [
                  for (var i = 0; i < _categories.length; i++) ...[
                    AnimatedBuilder(
                      animation: _in,
                      builder: (context, child) {
                        final v = _seg(0.12 + i * 0.16, 0.55 + i * 0.16);
                        return Opacity(
                          opacity: v,
                          child: Transform.translate(
                            offset: Offset(0, 18 * (1 - v)),
                            child: child,
                          ),
                        );
                      },
                      child: _category(_categories[i]),
                    ),
                    const SizedBox(height: 22),
                  ],
                  _footer(),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(gradient: AppGradients.brand),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.25),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          Text('No que eu te ajudo',
              style: AppTextStyles.titleMd.copyWith(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              )),
          const SizedBox(height: 4),
          Text('Sou seu copiloto de carreira — toca no que precisar',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd
                  .copyWith(color: Colors.white.withValues(alpha: 0.92))),
        ],
      ),
    );
  }

  Widget _category(_CapCategory cat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cat.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(cat.icon, color: cat.accent, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cat.title,
                      style: AppTextStyles.bodyLg.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 1),
                  Text(cat.desc,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final ex in cat.examples) _pill(ex, cat.accent)],
        ),
      ],
    );
  }

  Widget _pill(String label, Color accent) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onPick(label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: AppRadius.brPill,
          border: Border.all(color: accent.withValues(alpha: 0.20)),
        ),
        child: Text(label,
            style: AppTextStyles.labelMd
                .copyWith(color: accent, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'É só me pedir em português. Tudo que eu mudar, você confirma '
              'antes e dá pra desfazer.',
              style: AppTextStyles.bodySm
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapCategory {
  final IconData icon;
  final Color accent;
  final String title;
  final String desc;
  final List<String> examples;
  const _CapCategory({
    required this.icon,
    required this.accent,
    required this.title,
    required this.desc,
    required this.examples,
  });
}

class _EditFrame extends StatelessWidget {
  const _EditFrame({super.key, required this.child, required this.onCancel});

  final Widget child;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.allSm,
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withValues(alpha: 0.5),
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs, 2, AppSpacing.xs, AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.edit_rounded,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text('Editando',
                    style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.w700)),
                const Spacer(),
                // "Cancelar" = sair da edição e manter a resposta anterior.
                InkWell(
                  onTap: onCancel,
                  borderRadius: AppRadius.brPill,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.close_rounded,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('Cancelar',
                            style: AppTextStyles.labelSm.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// ✦ da barra "Escreva uma mensagem…": pulsa (brilho respirando) pra o usuário
/// notar que existe — é o acesso permanente à vitrine de capacidades.
class _SparkleButton extends StatefulWidget {
  const _SparkleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SparkleButton> createState() => _SparkleButtonState();
}

class _SparkleButtonState extends State<_SparkleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_pulse.value);
          return Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppGradients.brand,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandCyan.withValues(alpha: 0.22 + 0.34 * t),
                  blurRadius: 8 + 9 * t,
                  spreadRadius: 0.5 + 1.2 * t,
                ),
              ],
            ),
            child: child,
          );
        },
        child: const Icon(Icons.auto_awesome_rounded,
            size: 20, color: AppColors.onPrimary),
      ),
    );
  }
}
