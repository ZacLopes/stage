import 'widgets/step_slider_widget.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../data/models/models.dart';
import '../auth/user_viewmodel.dart';
import '../home/home_viewmodel.dart';
import 'gamification_viewmodel.dart';
import 'widgets/character_select_widget.dart';
import 'widgets/interactive_story_widget.dart';
import 'widgets/balance_slider_widget.dart';
import 'widgets/drag_and_drop_widget.dart';
import 'widgets/vibe_select_widget.dart';
import 'widgets/quick_time_event_widget.dart';
import 'widgets/chat_interface_widget.dart';
import 'widgets/vision_cards_widget.dart';
import 'widgets/squad_select_widget.dart';
import 'widgets/level_up_ladder_widget.dart';
import 'widgets/id_card_builder_widget.dart';
import 'widgets/dual_date_picker_widget.dart';
import 'widgets/dynamic_list_input_widget.dart';
import 'widgets/step_slider_widget.dart';
import 'widgets/icon_select_widget.dart';
import 'widgets/reward_card_widget.dart';
import 'widgets/badge_multiselect_widget.dart';
import 'widgets/mini_text_box_widget.dart';
import 'widgets/yes_no_detail_widget.dart';
import 'widgets/link_input_widget.dart';
import 'widgets/platform_selector_widget.dart';
import 'widgets/phone_input_widget.dart';
import 'widgets/phone_input_widget.dart';
import 'widgets/license_selector_widget.dart';
import 'widgets/city_state_selection_widget.dart';
import 'widgets/phase_completion_widget.dart';
import 'widgets/binary_choice_widget.dart';
import 'widgets/retro_id_card_widget.dart';
import 'widgets/bridge_text_widget.dart';
import 'widgets/activities_grid_widget.dart';
import 'widgets/experience_type_select_widget.dart';
import 'widgets/experience_form_widget.dart';
import 'widgets/corporate_form_widget.dart';
import 'widgets/startup_form_widget.dart';
import 'widgets/freelance_form_widget.dart';
import 'widgets/social_form_widget.dart';
import 'widgets/learning_vault_widget.dart';

class QuestionScreen extends StatefulWidget {
  final Phase phase;

  const QuestionScreen({super.key, required this.phase});

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  final Set<String> _selectedOptions = {};
  bool _isAnswerChecked = false;
  bool _isSaving = false;
  bool _isReverseAnimation = false;
  String? _lastQuestionId;

  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        context.read<GamificationViewModel>().startPhase(widget.phase.id));
  }

  void _handleOptionSelect(dynamic answer, QuestionType type) {
    if (_isAnswerChecked) return;
    setState(() {
      if (type == QuestionType.singleChoice || 
          type == QuestionType.scale ||
          // Single selection types
          type == QuestionType.characterSelect ||
          type == QuestionType.interactiveStory ||
          type == QuestionType.balanceSlider || // Returns double, but handled as single
          type == QuestionType.vibeSelect ||
          type == QuestionType.quickTimeEvent ||
          type == QuestionType.chat ||
          type == QuestionType.visionCards ||
          type == QuestionType.levelUpLadder ||
          type == QuestionType.stepSlider || // Returns string
          type == QuestionType.iconSelect ||
          // type == QuestionType.rewardCardSelect // Moved to complex
          type == QuestionType.miniTextBox ||
          type == QuestionType.linkInput ||
          type == QuestionType.phoneInput ||
          type == QuestionType.linkInput ||
          type == QuestionType.phoneInput ||
          type == QuestionType.cityStateInput ||
          type == QuestionType.binaryChoice ||
          type == QuestionType.retroIdCard ||
          type == QuestionType.bridgeText
          ) {
        _selectedOptions.clear();
        _selectedOptions.add(answer.toString());
      } else if (type == QuestionType.idCardBuilder ||
                 type == QuestionType.dualWheelDate ||
                 type == QuestionType.yesNoWithDetail ||
                 type == QuestionType.rewardCardSelect ||
                 type == QuestionType.activitiesGrid ||
                 type == QuestionType.experienceForm) { // Treat as complex for detail input
         // Complex objects -> JSON
         _selectedOptions.clear();
         
         // Fix for validation: if answer is empty map, do not add it.
         if (answer is Map && answer.isEmpty) {
           return;
         }
         
         _selectedOptions.add(jsonEncode(answer));
      } else if (type == QuestionType.dragAndDrop) {
        // Drag and Drop returns a List<String>
        _selectedOptions.clear();
        _selectedOptions.addAll(answer as List<String>);
      } else if (type == QuestionType.squadSelect) {
         // Squad Select returns a List<String>
         _selectedOptions.clear();
         _selectedOptions.addAll(answer as List<String>);
      } else if (type == QuestionType.dynamicList) {
         // Dynamic List returns a List<String>
         _selectedOptions.clear();
         _selectedOptions.addAll(answer as List<String>);
      } else if (type == QuestionType.platformSelect) {
         // Platform returns List<String> of "Platform: Link"
         _selectedOptions.clear();
         _selectedOptions.addAll(answer as List<String>);
      } else if (type == QuestionType.badgeMultiSelect) {
         // Badge Select returns List<String>
         _selectedOptions.clear();
         try {
           _selectedOptions.addAll((answer as List).map((e) => e.toString()));
         } catch (_) {}
      } else if (type == QuestionType.learningVault) {
         _selectedOptions.clear();
         _selectedOptions.add(jsonEncode(answer));
      } else if (type == QuestionType.experienceTypeSelect) {
         // Experience Select returns List<String> but we want to allow duplicates (e.g. 2 Startups)
         // So we store it as a SINGLE JSON string in the set
         _selectedOptions.clear();
         _selectedOptions.add(jsonEncode(answer));
      } else {
        // Multiple Choice
        final option = answer.toString();
        if (_selectedOptions.contains(option)) {
          _selectedOptions.remove(option);
        } else {
          _selectedOptions.add(option);
        }
      }
    });
  }



  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Consumer<GamificationViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoadingQuestions) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (viewModel.isCurrentPhaseFinished) {
          return _buildCompletionScreen(context, viewModel);
        }

        final question = viewModel.currentQuestion;
        if (question == null) {
          return const Scaffold(
            body: Center(child: Text('No questions found.')),
          );
        }

        // --- STATE RESTORATION LOGIC ---
        // If the question changed (moved forward OR backward), reload the state
        if (_lastQuestionId != question.id) {
          _lastQuestionId = question.id;
          _selectedOptions.clear();
          _textController.clear();
          _isAnswerChecked = false;

          final savedAnswer = viewModel.getAnswer(question.id);
          if (savedAnswer != null) {
            // Restore state DIRECTLY (without setState) to avoid build error
            final type = question.type;
            
            if (type == QuestionType.singleChoice || 
                type == QuestionType.scale ||
                // Single selection types
                type == QuestionType.characterSelect ||
                type == QuestionType.interactiveStory ||
                type == QuestionType.balanceSlider || 
                type == QuestionType.vibeSelect ||
                type == QuestionType.quickTimeEvent ||
                type == QuestionType.chat ||
                type == QuestionType.visionCards ||
                type == QuestionType.levelUpLadder ||
                type == QuestionType.stepSlider || 
                type == QuestionType.iconSelect ||
                type == QuestionType.miniTextBox ||
                type == QuestionType.linkInput ||
                type == QuestionType.phoneInput ||
                type == QuestionType.cityStateInput ||
                type == QuestionType.binaryChoice ||
                type == QuestionType.retroIdCard ||
                type == QuestionType.bridgeText
                ) {
              _selectedOptions.add(savedAnswer.toString());
            } else if (type == QuestionType.idCardBuilder ||
                       type == QuestionType.dualWheelDate ||
                       type == QuestionType.yesNoWithDetail ||
                       type == QuestionType.rewardCardSelect) { 
               // Complex objects -> JSON
               _selectedOptions.add(jsonEncode(savedAnswer));
            } else if (type == QuestionType.dragAndDrop || 
                       type == QuestionType.squadSelect ||
                       type == QuestionType.dynamicList || 
                       type == QuestionType.platformSelect ||
                       type == QuestionType.badgeMultiSelect) {
               // List<String> types
               if (savedAnswer is List) {
                 _selectedOptions.addAll(savedAnswer.map((e) => e.toString()));
               }
            } else if (type == QuestionType.experienceTypeSelect) {
                // Stored as JSON string
                if (savedAnswer is String) {
                   _selectedOptions.add(savedAnswer);
                } else if (savedAnswer is List) {
                   // Fallback for old data or if repository returns list
                   _selectedOptions.add(jsonEncode(savedAnswer));
                }
            } else if (type == QuestionType.learningVault) {
                if (savedAnswer is String) {
                   _selectedOptions.add(savedAnswer);
                } else {
                   _selectedOptions.add(jsonEncode(savedAnswer));
                }
            } else {
              // Multiple Choice
              if (savedAnswer is List) {
                 _selectedOptions.addAll(savedAnswer.map((e) => e.toString()));
              } else if (savedAnswer is String) {
                 _selectedOptions.add(savedAnswer.toString());
              }
            }

            // Specifically handling text input restoration
            if (question.type == QuestionType.text && savedAnswer is String) {
               _textController.text = savedAnswer;
            }
          }
        }
        // -------------------------------

        // --- CONDITIONAL LOGIC FOR MODULE 2 (M2_1_1) ---
        if (question.id == 'M2_1_1_Q3' || question.id == 'M2_1_1_Q4') {
          final q2Answer = viewModel.getAnswer('M2_1_1_Q2');
          if (q2Answer == 'Não') {
            Future.microtask(() => viewModel.answerQuestion('SKIPPED'));
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
        }

        // --- CONDITIONAL LOGIC FOR MODULE 2 (M2_3_1_Q3) ---
        if (question.id == 'M2_3_1_Q3') {
           final q2Answer = viewModel.getAnswer('M2_3_1_Q2');
           bool shouldSkip = false;
           // Check if answer is empty list
           if (q2Answer != null) {
             if (q2Answer is List && q2Answer.isEmpty) shouldSkip = true;
             // If stored as string "[]" or empty string
             if (q2Answer is String && (q2Answer.isEmpty || q2Answer == '[]')) shouldSkip = true;
           } else {
             // If null (not answered?), safely assume skip or let user decide?
             // Usually it should be answered previously. If null, maybe we just started Q3 directly?
             // Let's assume skip to be safe if no badges selected.
             shouldSkip = true;
           }

           if (shouldSkip) {
             WidgetsBinding.instance.addPostFrameCallback((_) {
               viewModel.answerQuestion('skipped');
             });
             return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF58CC02))));
           }
        }
        


        // --- CONDITIONAL LOGIC FOR MODULE 3.2 (M3_2_1_Q2) ---
        if (question.id == 'M3_2_1_Q2') {
           final q1Answer = viewModel.getAnswer('M3_2_1_Q1');
           if (q1Answer != null && q1Answer.toString().startsWith('Não')) {
               WidgetsBinding.instance.addPostFrameCallback((_) {
                 viewModel.answerQuestion('skipped');
               });
               return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF58CC02))));
           }
        }

        // Dynamic Text Replacement logic
        String displayContent = question.content;
        if (question.id == 'M2_1_1_Q4') {
             final prevAnswer = viewModel.getAnswer('M2_1_1_Q3');
             if (prevAnswer != null && prevAnswer is String) {
                 try {
                     final Map<String, dynamic> data = jsonDecode(prevAnswer);
                     final String? course = data['course'];
                     if (course != null && course.isNotEmpty) {
                         displayContent = displayContent.replaceAll('[Curso Anterior]', course);
                     }
                 } catch (e) {
                     print('Error parsing previous answer for dynamic text: $e');
                 }
             }
        }

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Color(0xFFE5E7EB), size: 32),
              onPressed: () => Navigator.pop(context),
            ),
            title: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LinearProgressIndicator(
                value: viewModel.progress,
                minHeight: 16,
                backgroundColor: const Color(0xFFE5E7EB),
                color: const Color(0xFF58CC02), // Duolingo Green
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  switchInCurve: Curves.easeOutQuart,
                  switchOutCurve: Curves.easeInQuart,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    final isEntry = child.key == ValueKey(question.id);
                    
                    // Logic:
                    // If Going Forward (_isReverseAnimation = false):
                    //   - Entry comes from Right (1.0) -> Center (0.0)
                    //   - Exit goes to Left (-1.0)
                    // If Going Backward (_isReverseAnimation = true):
                    //   - Entry comes from Left (-1.0) -> Center (0.0)
                    //   - Exit goes to Right (1.0)

                    Offset beginOffset;
                    if (!_isReverseAnimation) {
                       // Forward
                       beginOffset = isEntry ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0);
                    } else {
                       // Backward (Inverse)
                       beginOffset = isEntry ? const Offset(-1.0, 0.0) : const Offset(1.0, 0.0);
                    }

                    final offsetAnimation = Tween<Offset>(begin: beginOffset, end: Offset.zero)
                        .chain(CurveTween(curve: Curves.easeOutQuart)) // Smooth curve
                        .animate(animation);

                    return SlideTransition(
                      position: offsetAnimation,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: SingleChildScrollView(
                    key: ValueKey(question.id),
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const SizedBox(height: 16),
                        Text(
                          displayContent,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF374151),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 48),
                        _buildQuestionContent(context, question, viewModel, displayContent),
                      ],
                    ),
                  ),
                ),
              ),
              _buildBottomBar(context, viewModel),
            ],
          ),
        );
      },
    ),
    );
  }

  Widget _buildQuestionContent(BuildContext context, Question question, GamificationViewModel viewModel, String displayContent) {
    switch (question.type) {
      case QuestionType.multipleChoice:
      case QuestionType.singleChoice:
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: question.options.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final option = question.options[index];
            final isSelected = _selectedOptions.contains(option);
            
            return GestureDetector(
              onTap: () => _handleOptionSelect(option, question.type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFDDF4FF) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF1CB0F6) : const Color(0xFFE5E7EB),
                    width: 2, // Thicker border
                  ),
                  boxShadow: [
                    if (!isSelected)
                      const BoxShadow(
                        color: Color(0xFFE5E7EB),
                        offset: Offset(0, 4),
                        blurRadius: 0,
                      ),
                    if (isSelected)
                      const BoxShadow(
                        color: Color(0xFF1899D6), // Darker blue for "pressed" look
                        offset: Offset(0, 0),
                        blurRadius: 0,
                      ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          fontSize: 18,
                          color: isSelected ? const Color(0xFF1899D6) : const Color(0xFF4B5563),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle, color: Color(0xFF1CB0F6)),
                  ],
                ),
              ),
            );
          },
        );
      case QuestionType.scale:
        // Simplified scale for MVP
        return Column(
          children: question.options.map((option) {
             final isSelected = _selectedOptions.contains(option);
             return Padding(
               padding: const EdgeInsets.only(bottom: 12),
               child: GestureDetector(
                onTap: () => _handleOptionSelect(option, question.type),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFDDF4FF) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF1CB0F6) : const Color(0xFFE5E7EB),
                      width: 2,
                    ),
                  ),
                  child: Center(child: Text(option, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                ),
               ),
             );
          }).toList(),
        );

      case QuestionType.email:
        return TextField(
            controller: _textController,
            onChanged: (value) {
              setState(() {
                _selectedOptions.clear();
                if (value.isNotEmpty) {
                  _selectedOptions.add(value);
                }
              });
            },
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              hintText: 'exemplo@email.com',
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF9CA3AF)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF58CC02), width: 2),
              ),
              // Simple validation feedback can be added here if needed
            ),
            style: const TextStyle(fontSize: 18),
        );
      case QuestionType.text:
        return TextField(
          controller: _textController,
          onChanged: (value) {
            setState(() {
              _selectedOptions.clear();
              if (value.isNotEmpty) {
                _selectedOptions.add(value);
              }
            });
          },
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Digite sua resposta aqui...',
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF58CC02), width: 2),
            ),
          ),
          style: const TextStyle(fontSize: 18),
        );
      case QuestionType.characterSelect:
        return CharacterSelectWidget(
          options: const {}, // In real app, pass question.options or parsed data
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.interactiveStory:
        return InteractiveStoryWidget(
          options: const {},
          onSelect: (val) => _handleOptionSelect(val, question.type),
        );
      case QuestionType.balanceSlider:
        return BalanceSliderWidget(
          options: const {},
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.dragAndDrop:
        List<String> options = [];
        if (question.id == 'M1_3_1_Q1') {
          options = [
            'Mestria — “Aprender muito e virar referência técnica”',
            'Impacto — “Sentir que meu trabalho muda a vida das pessoas”',
            'Ascensão — “Crescer rápido e assumir liderança”',
            'Estabilidade — “Segurança financeira e equilíbrio”',
            'Autonomia — “Liberdade para fazer do meu jeito”',
          ];
        }
        return DragAndDropWidget(
          options: options,
          onSelect: (val) => _handleOptionSelect(val, question.type),
        );
      case QuestionType.vibeSelect:
        return VibeSelectWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.quickTimeEvent:
        return QuickTimeEventWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.chat:
        // Config for Module 3.3 Q2
        final isM3Chat = question.id == 'M3_3_1_Q2';
        return ChatInterfaceWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          isInputMode: isM3Chat,
          recruiterMessage: isM3Chat
              ? 'Legal! E como você fazia isso na prática? Pode escrever do seu jeito, eu te ajudo a organizar.'
              : null,
          hintText: isM3Chat
              ? 'Ex: Eu atendia cerca de 20 clientes por dia e organizava as prateleiras da loja.'
              : null,
        );
      case QuestionType.visionCards:
        return VisionCardsWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.squadSelect:
        return SquadSelectWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.toList(),
        );

      // Module 2 Widgets
      case QuestionType.levelUpLadder:
        return LevelUpLadderWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );

      case QuestionType.idCardBuilder:
        // Customize based on Phase ID
        final isWork = question.phaseId.startsWith('t3');
        return IdCardBuilderWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          cardTitle: isWork ? 'CRACHÁ PROFISSIONAL' : 'CARTEIRINHA ESTUDANTIL',
          field1Label: isWork ? 'Empresa / Local' : 'Instituição de Ensino',
          field2Label: isWork ? 'Cargo / Função' : 'Nome do Curso',
          moduleTag: isWork ? 'Módulo 3' : 'Módulo 2',
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.dualWheelDate:
        DatePickerViewMode mode = DatePickerViewMode.dual;
        if (question.id == 'M3_2_1_Q1') mode = DatePickerViewMode.startOnly;

        return DualWheelDateWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          viewMode: mode,
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.stepSlider:
        return StepSliderWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          options: question.options,
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.iconSelect:
        return IconSelectWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          options: question.options,
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.rewardCardSelect:
        return RewardCardWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          options: question.options,
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.badgeMultiSelect:
        return BadgeMultiSelectWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          options: question.options,
          initialValue: _selectedOptions.toList(),
        );
      case QuestionType.miniTextBox:
        return MiniTextBoxWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.yesNoWithDetail:
         // Custom config for Module 4 certificates
         String? label;
         String? hint;
         if (question.id == 'M4_1_1_Q4') {
           label = 'Nome do Curso e Instituição';
           hint = 'Ex: Excel Avançado - Fundação Bradesco';
         } else if (question.id == 'M4_2_1_Q4') {
           label = 'Nome da Certificação';
           hint = 'Ex: TOEFL iBT - Score 105';
         }
        return YesNoDetailWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          simpleMode: question.id.startsWith('M3'), // Use simple mode for Module 3
          detailLabel: label,
          detailHint: hint,
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.dynamicList:
        return DynamicListInputWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          hintText: 'Digite ou selecione...',
          suggestions: question.options,
          maxSelections: question.id == 'M1_3_1_Q2' ? 2 : null,
          initialValue: _selectedOptions.toList(),
        );
      case QuestionType.linkInput:
        return LinkInputWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.platformSelect:
        return PlatformSelectorWidget(
          options: question.options,
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.toList(),
        );
      case QuestionType.phoneInput:
        return PhoneInputWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.licenseSelect:
        return LicenseSelectorWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.cityStateInput:
        return CityStateSelectionWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.binaryChoice:
        return BinaryChoiceWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          selectedOption: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
          options: question.options,
        );
      case QuestionType.activitiesGrid:
        return ActivitiesGridWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          options: question.options,
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.experienceTypeSelect:
        List<dynamic> options = [];
        try {
          options = question.options.map((e) {
            try {
              return jsonDecode(e);
            } catch (error) {
              print('Error parsing option: $e -> $error');
              return null;
            }
          }).where((e) => e != null).toList();
        } catch (_) {}
        
        return ExperienceTypeSelectWidget(
          onSelect: (val) => _handleOptionSelect(val, question.type),
          options: options,
        );

      case QuestionType.experienceForm:
        // Context is passed in options for dynamic questions
        String? contextType;
        if (question.options.isNotEmpty) {
           final raw = question.options.first.toString();
           try {
             if (raw.startsWith('{')) {
               final json = jsonDecode(raw);
               contextType = json['id'];
             } else {
               contextType = raw;
             }
           } catch (_) { contextType = raw; }
        }

        // Route to specialized widget
        switch (contextType) {
          case 'startup':
          case 'acceleration':
            return StartupFormWidget(
               onSave: (val) => _handleOptionSelect(val, question.type),
               initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
            );
          case 'freelance':
            return FreelanceFormWidget(
               onSave: (val) => _handleOptionSelect(val, question.type),
               initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
            );
          case 'social':
            return SocialFormWidget(
               onSave: (val) => _handleOptionSelect(val, question.type),
               initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
            );
          case 'corporate':
          default:
             return CorporateFormWidget(
               onSave: (val) => _handleOptionSelect(val, question.type),
               initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
             );
        }

      case QuestionType.learningVault:
        return LearningVaultWidget(
          onSave: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? jsonDecode(_selectedOptions.first) : null,
        );
      case QuestionType.retroIdCard:
        return RetroIdCardWidget(
          onSave: (val) => _handleOptionSelect(val, question.type),
          initialValue: _selectedOptions.isNotEmpty ? _selectedOptions.first : null,
        );
      case QuestionType.bridgeText:
        // Automatically check the box as it's a bridge/info screen
        if (!_isAnswerChecked) {
           WidgetsBinding.instance.addPostFrameCallback((_) {
             _handleOptionSelect('seen', question.type);
           });
        }
        return BridgeTextWidget(
          questionText: displayContent, 
          onSave: (text) { 
             _handleOptionSelect(text, question.type);
             _handleContinue(viewModel);
          },
        );

      default:
        return const Center(child: Text('Unknown Question Type')); // Placeholder
    }
  }

  // Helper to validate and continue
  void _handleContinue(GamificationViewModel viewModel) async {
    if (_isSaving) return; // Debounce

    setState(() => _isSaving = true);
    
    try {
      bool isEnabled = _selectedOptions.isNotEmpty; // Re-evaluate isEnabled for _handleContinue context

    // Optional Question: M5_2_1_Q3 (Observação final)
    if (viewModel.currentQuestion?.id == 'M5_2_1_Q3') {
      isEnabled = true;
    }

    // Validate mandatory detail for RewardCardSelect (Scholarships)
    if (isEnabled && viewModel.currentQuestion?.type == QuestionType.rewardCardSelect) {
      try {
        final selection = jsonDecode(_selectedOptions.first);
        final String? optionId = selection['selected'];
        final String? detail = selection['detail'];
        
        // If option implies "Sim" (full, partial or explicitly contains 'Sim'), require detail
        if (optionId != null && 
           (optionId == 'full' || optionId == 'partial' || optionId.toLowerCase().contains('sim'))) {
          if (detail == null || detail.trim().isEmpty) {
            isEnabled = false;
          }
        }
      } catch (e) {
        // In case of parsing error, disable to be safe
        isEnabled = false;
      }
    }

    // Validate mandatory detail for YesNoWithDetail (Awards, Certificates)
    if (isEnabled && viewModel.currentQuestion?.type == QuestionType.yesNoWithDetail) {
      try {
        final selection = jsonDecode(_selectedOptions.first);
        final bool hasDetail = selection['value'] == true;
        final String? text = selection['detail_text'];
        
        if (hasDetail) {
             // M3 questions use simple mode (no text box), so skip validation for M3
             bool isSimple = viewModel.currentQuestion!.id.startsWith('M3');
             
             if (!isSimple && (text == null || text.trim().isEmpty)) {
               isEnabled = false;
             }
        }
      } catch (e) {
        isEnabled = false;
      }
    }

    // Validate Link Input (Must not be empty if selected)
    if (isEnabled && viewModel.currentQuestion?.type == QuestionType.linkInput) {
       final link = _selectedOptions.firstOrNull;
       if (link == null || link.trim().isEmpty) {
         isEnabled = false;
       }
    }

    // Check if we need to skip questions based on answer
    // M2_1_1_Q2 (Faculdade/Curso type check) handled elsewhere?
    
    // NEW SKIP LOGIC for Submodule 2.3
    if (viewModel.currentQuestion?.id == 'M2_3_1_Q2') {
       if (_selectedOptions.isNotEmpty) {
         try {
           final data = jsonDecode(_selectedOptions.first);
           if (data['id'] == 'none') {
             // Skip Next Question (Q3)
             // We need to tell ViewModel to skip? Or manually increment index?
             // ViewModel has `answerQuestion` which increments by 1.
             // We can chain another increment? Or use a method `skipQuestion`.
             // But simplest hack for now: 
             // Call answerQuestion, wait for it, then if next is Q3, answer matches, skip it.
             // Better: ViewModel logic should handle simple logic or Screen calls 'skip'.
             
             // Let's implement a 'forceSkip' param in answerQuestion or call next twice?
             // Calling twice is risky.
             // We can check next question ID.
             // Actually, `answerQuestion` takes us to next. 
             // If we want to skip Q3, we should answer Q3 as well (with 'skipped' val) and move on.
             
             await viewModel.answerQuestion(_selectedOptions.first); // Answers Q2
             
             // Now current is Q3? Wait, `answerQuestion` is async.
             // After await, view model updates.
             // If next question is M2_3_1_Q3, we answer it automatically with empty/skipped.
             
             if (viewModel.currentQuestion?.id == 'M2_3_1_Q3') {
               await viewModel.answerQuestion('skipped');
             }
             return;
           }
         } catch (_) {}
       }
    }

    if (viewModel.currentQuestion?.type == QuestionType.bridgeText) {
       // already handled in widget? No, widget calls this.
       // proceed.
    }

    // --- MODULE 3.1: NO EXPERIENCE SKIP ---
    if (viewModel.currentQuestion?.id == 'M3_1_1_Q1' && _selectedOptions.isNotEmpty) {
       // Check for No Experience
       if (_selectedOptions.first == 'NO_EXPERIENCE') {
          await viewModel.answerQuestion('NO_EXPERIENCE');
          while (viewModel.currentQuestion != null && viewModel.currentQuestion!.id.startsWith('M3')) {
             await viewModel.answerQuestion('skipped');
          }
          return;
       }
       // Custom 'Other' experience is now handled in ViewModel by not generating next questions
    }

    // --- MODULE 3.1: FORM VALIDATION ---
    if (isEnabled && viewModel.currentQuestion?.type == QuestionType.experienceForm) {
       try {
         final data = jsonDecode(_selectedOptions.first);
         final type = data['type'] as String?;

         if (type == 'corporate') {
           // Corporate Validation: Company, Start, End, DayToDay, Results
           if ((data['company'] ?? '').toString().trim().isEmpty || 
               // (data['role'] ?? '').toString().trim().isEmpty || // Removed
               // (data['location'] ?? '').toString().trim().isEmpty || // Removed
               (data['start_date'] ?? '').toString().trim().isEmpty ||
               (data['end_date'] ?? '').toString().trim().isEmpty ||
               (data['description'] ?? '').toString().trim().isEmpty ||
               (data['results'] ?? '').toString().trim().isEmpty) {
             isEnabled = false;
           }
         } else if (type == 'startup') {
           // Startup Validation: Company, Role, Start, End, Problem, Milestones
           if ((data['company'] ?? '').toString().trim().isEmpty || 
               (data['role'] ?? '').toString().trim().isEmpty || 
               (data['start_date'] ?? '').toString().trim().isEmpty ||
               (data['end_date'] ?? '').toString().trim().isEmpty ||
               (data['problem_solved'] ?? '').toString().trim().isEmpty ||
               (data['milestones'] ?? '').toString().trim().isEmpty) {
             isEnabled = false;
           }
         } else if (type == 'freelance' || type == 'social') {
            // Freelance/Social: Role/Project, Description + dates usually
             if ((data['role'] ?? '').toString().trim().isEmpty || 
                 (data['description'] ?? '').toString().trim().isEmpty) {
               isEnabled = false;
             }
         } else {
           // Fallback for default
           if ((data['company'] ?? '').toString().trim().isEmpty || 
               (data['role'] ?? '').toString().trim().isEmpty) {
             isEnabled = false;
           }
         }
       } catch (_) { isEnabled = false; }
    }

    // Email Validation
    if (isEnabled && viewModel.currentQuestion?.type == QuestionType.email) {
       final email = _selectedOptions.firstOrNull ?? '';
       final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
       if (!emailRegex.hasMatch(email)) {
         isEnabled = false;
         // TODO: Show error feedback? For now, button stays disabled.
       }
    }

    // Standard flow
    // Need to handle list/set to dynamic answer format
    dynamic answer;
    if (_selectedOptions.length == 1) {
       answer = _selectedOptions.first;
    } else {
       answer = _selectedOptions.toList();
    }
    
    await viewModel.answerQuestion(answer);
    } catch (e) {
      print('Error in _handleContinue: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildBottomBar(BuildContext context, GamificationViewModel viewModel) {
    bool isEnabled = _selectedOptions.isNotEmpty;

    // Optional Question: M5_2_1_Q3 (Observação final)
    if (viewModel.currentQuestion?.id == 'M5_2_1_Q3') {
      isEnabled = true;
    }

    // Email Validation in Bottom Bar (to disable button visually)
    if (isEnabled && viewModel.currentQuestion?.type == QuestionType.email) {
       final email = _selectedOptions.firstOrNull ?? '';
       final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
       if (!emailRegex.hasMatch(email)) {
         isEnabled = false;
       }
    }

    // Validate Form (Experience Form)
    if (isEnabled && viewModel.currentQuestion?.type == QuestionType.experienceForm) {
       try {
         final data = jsonDecode(_selectedOptions.first);
         final type = data['type'] as String?;

         if (type == 'corporate') {
           // Corporate: All fields
           if ((data['company'] ?? '').toString().trim().isEmpty || 
               // (data['role'] ?? '').toString().trim().isEmpty || // Removed
               // (data['location'] ?? '').toString().trim().isEmpty || // Removed
               (data['start_date'] ?? '').toString().trim().isEmpty ||
               (data['end_date'] ?? '').toString().trim().isEmpty ||
               (data['description'] ?? '').toString().trim().isEmpty ||
               (data['results'] ?? '').toString().trim().isEmpty) {
             isEnabled = false;
           }
         } else if (type == 'startup') {
           // Startup: All fields
             if ((data['company'] ?? '').toString().trim().isEmpty || 
               (data['role'] ?? '').toString().trim().isEmpty || 
               (data['start_date'] ?? '').toString().trim().isEmpty ||
               (data['end_date'] ?? '').toString().trim().isEmpty ||
               (data['problem_solved'] ?? '').toString().trim().isEmpty ||
               (data['milestones'] ?? '').toString().trim().isEmpty) {
             isEnabled = false;
           }
         } else if (type == 'freelance' || type == 'social') {
             if ((data['role'] ?? '').toString().trim().isEmpty || 
                 (data['description'] ?? '').toString().trim().isEmpty) {
               isEnabled = false;
             }
         } else {
           if ((data['company'] ?? '').toString().trim().isEmpty || 
               (data['role'] ?? '').toString().trim().isEmpty) {
             isEnabled = false;
           }
         }
       } catch (_) { isEnabled = false; }
    }

    // Validate mandatory detail for RewardCardSelect (Scholarships)
    if (isEnabled && viewModel.currentQuestion?.type == QuestionType.rewardCardSelect) {
      try {
        final selection = jsonDecode(_selectedOptions.first);
        final String? optionId = selection['selected'];
        final String? detail = selection['detail'];
        
        // If option implies "Sim" (full, partial or explicitly contains 'Sim'), require detail
        if (optionId != null && 
           (optionId == 'full' || optionId == 'partial' || optionId.toLowerCase().contains('sim'))) {
          if (detail == null || detail.trim().isEmpty) {
            isEnabled = false;
          }
        }
      } catch (e) {
        // In case of parsing error, disable to be safe
        isEnabled = false;
      }
    }

    // Validate mandatory detail for YesNoWithDetail (Awards, Certificates)
    if (isEnabled && viewModel.currentQuestion?.type == QuestionType.yesNoWithDetail) {
      try {
        final selection = jsonDecode(_selectedOptions.first);
        final bool hasDetail = selection['value'] == true;
        final String? text = selection['detail_text'];
        
        if (hasDetail) {
             // M3 questions use simple mode (no text box), so skip validation for M3
             bool isSimple = viewModel.currentQuestion!.id.startsWith('M3');
             
             if (!isSimple && (text == null || text.trim().isEmpty)) {
               isEnabled = false;
             }
        }
      } catch (e) {
        isEnabled = false;
      }
    }

    // Validate Link Input (Must not be empty if selected)
    if (isEnabled && viewModel.currentQuestion?.type == QuestionType.linkInput) {
       final link = _selectedOptions.firstOrNull;
       if (link == null || link.trim().isEmpty) {
         isEnabled = false;
       }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 2)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // BACK BUTTON
            if (viewModel.currentQuestionIndex > 0)
              Container(
                margin: const EdgeInsets.only(right: 12),
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _isReverseAnimation = true);
                    viewModel.previousQuestion();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFE5E7EB), // Gray border/icon
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFFE5E7EB), width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    minimumSize: const Size(56, 56), // Square-ish
                  ),
                  child: const Icon(Icons.arrow_back, color: Color(0xFFAFAFAF), size: 24),
                ),
              ),

            Expanded(
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: (isEnabled && !_isSaving) ? () => _handleContinue(viewModel) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF58CC02), // Green
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE5E7EB),
                    disabledForegroundColor: const Color(0xFFAFAFAF),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSaving 
                      ? const SizedBox(
                          width: 24, 
                          height: 24, 
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        )
                      : const Text(
                          'CONTINUAR',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionScreen(BuildContext context, GamificationViewModel viewModel) {
    return PhaseCompletionWidget(phase: widget.phase, viewModel: viewModel);
  }
}
