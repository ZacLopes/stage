import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/stage_colors.dart';
import '../../services/analytics_service.dart';
import 'user_viewmodel.dart';
import 'completion_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  
  // Step 1
  late TextEditingController _nameController;
  DateTime? _selectedDate;
  final _phoneController = TextEditingController();

  // Step 2
  final _uniController = TextEditingController();
  final _courseController = TextEditingController();
  int? _selectedSemester;
  
  final List<String> _uniSuggestions = ['USP', 'UNICAMP', 'PUC-SP', 'FGV', 'Insper', 'Mackenzie', 'UFRJ', 'UFMG'];
  final List<String> _courseSuggestions = ['Administração', 'Engenharia', 'Direito', 'Marketing', 'Ciência da Computação', 'Economia'];

  // Step 3
  final Set<String> _selectedJobTypes = {};
  final Set<String> _selectedAreas = {};
  String? _selectedWorkModel;

  final List<String> _jobTypes = ['Estágio', 'Trainee', 'CLT Júnior'];
  final List<String> _workModels = ['Remoto', 'Híbrido', 'Presencial', 'Tanto faz'];
  final List<String> _areas = [
    'Marketing', 'Finanças', 'Tecnologia', 'Design', 
    'Engenharia', 'Administração', 'Jurídico', 
    'Recursos Humanos', 'Comunicação', 'Vendas'
  ];

  @override
  void initState() {
    super.initState();
    Analytics.shared.onboardingStepReached(step: 3);
    // Prefill name if available
    final vm = context.read<UserViewModel>();
    _nameController = TextEditingController(text: vm.user?.name ?? '');
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _uniController.dispose();
    _courseController.dispose();
    super.dispose();
  }

  bool get _isCurrentStepValid {
    if (_currentStep == 0) {
      return _nameController.text.trim().isNotEmpty && _selectedDate != null;
    } else if (_currentStep == 1) {
      return _uniController.text.trim().isNotEmpty && 
             _courseController.text.trim().isNotEmpty &&
             _selectedSemester != null;
    } else {
      return _selectedJobTypes.isNotEmpty && 
             _selectedAreas.isNotEmpty && 
             _selectedWorkModel != null;
    }
  }

  Future<void> _nextStep() async {
    if (!_isCurrentStepValid) return;

    if (_currentStep < 2) {
      FocusScope.of(context).unfocus();
      _pageController.animateToPage(
        _currentStep + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Final Step: Save profile (não as preferências de vagas)
      final userVm = context.read<UserViewModel>();

      // Calculate approximate age
      final today = DateTime.now();
      int age = today.year - _selectedDate!.year;
      if (today.month < _selectedDate!.month ||
          (today.month == _selectedDate!.month && today.day < _selectedDate!.day)) {
        age--;
      }

      try {
        await userVm.updateProfile(
          name: _nameController.text.trim(),
          age: age,
          course: _courseController.text.trim(),
          semester: _selectedSemester.toString(),
          university: _uniController.text.trim(),
        );

        // ⚠️ NÃO salvar UserJobPreferences a partir do onboarding.
        //
        // O usuário relatou que após criar conta, abrir Vagas e ver feed vazio
        // é confuso — os filtros vinham auto-aplicados das escolhas do step 3
        // (áreas, tipo, modelo) e excluíam a maioria das vagas no banco.
        //
        // Comportamento agora: o feed começa SEM filtros. As escolhas do step 3
        // são coletadas pra UX (formulário se sente intencional), mas só viram
        // filtros se o usuário entrar em Vagas > Filtros e salvar manualmente.
        //
        // Se no futuro quisermos "pré-preencher" o picker de filtros com o que
        // foi respondido aqui, fazer isso na tela de filtros (campo "sugestão"
        // ou similar) — não auto-salvar.

        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, anim, secAnim) => const CompletionScreen(),
              transitionsBuilder: (context, anim, secAnim, child) {
                return FadeTransition(opacity: anim, child: child);
              },
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: StageColors.error),
          );
        }
      }
    }
  }

  void _skipOptional() {
    setState(() {
      if (_currentStep == 0) {
        // Just fill defaults to pass validation if skipped
        _selectedDate ??= DateTime(2000, 1, 1);
        if (_nameController.text.isEmpty) _nameController.text = 'Usuário';
      } else if (_currentStep == 1) {
        if (_uniController.text.isEmpty) _uniController.text = 'Não informado';
        if (_courseController.text.isEmpty) _courseController.text = 'Não informado';
        _selectedSemester ??= 1;
      } else if (_currentStep == 2) {
        if (_selectedJobTypes.isEmpty) _selectedJobTypes.add('Estágio');
        if (_selectedAreas.isEmpty) _selectedAreas.add('Administração');
        _selectedWorkModel ??= 'Tanto faz';
      }
    });
    _nextStep();
  }

  // --- Step 1 Build ---
  Widget _buildStep1() {
    return _StepContentLayout(
      headline: 'Conta mais\nsobre você',
      subtitle: 'Pra gente personalizar sua experiência.',
      children: [
        // Name
        TextField(
          controller: _nameController,
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('Nome Completo', Icons.person_outline),
        ),
        const SizedBox(height: 20),
        
        // Date
        GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.now().subtract(const Duration(days: 365 * 20)),
              firstDate: DateTime(1950),
              lastDate: DateTime.now(),
              builder: (context, child) => Theme(
                data: ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(primary: StageColors.brandBlue),
                ),
                child: child!,
              ),
            );
            if (date != null) {
              setState(() => _selectedDate = date);
            }
          },
          child: AbsorbPointer(
            child: TextField(
              controller: TextEditingController(
                text: _selectedDate == null 
                  ? '' 
                  : '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}',
              ),
              decoration: _inputDecoration('Data de Nascimento', Icons.calendar_today),
            ),
          ),
        ),
        const SizedBox(height: 20),
        
        // Phone (Optional)
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: _inputDecoration('Celular (Opcional)', Icons.phone_outlined, hint: '(11) 99999-9999'),
        ),
      ],
    );
  }

  // --- Step 2 Build ---
  Widget _buildStep2() {
    return _StepContentLayout(
      headline: 'Onde você estuda?',
      subtitle: 'Isso nos ajuda a encontrar vagas perfeitas.',
      children: [
        // University Autocomplete using tags for simplicty
        TextField(
          controller: _uniController,
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('Universidade', Icons.account_balance),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _uniSuggestions.map((u) => ActionChip(
            label: Text(u, style: GoogleFonts.inter(fontSize: 12)),
            backgroundColor: StageColors.chipUnselectedBg,
            side: BorderSide.none,
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() => _uniController.text = u);
            },
          )).toList(),
        ),
        const SizedBox(height: 24),
        
        // Course Autocomplete
        TextField(
          controller: _courseController,
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('Curso', Icons.school_outlined),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _courseSuggestions.map((c) => ActionChip(
            label: Text(c, style: GoogleFonts.inter(fontSize: 12)),
            backgroundColor: StageColors.chipUnselectedBg,
            side: BorderSide.none,
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() => _courseController.text = c);
            },
          )).toList(),
        ),
        const SizedBox(height: 32),

        // Semester
        Text('Semestre Sugerido', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(11, (index) {
              final number = index + 1;
              final isSelected = _selectedSemester == number;
              final label = number > 10 ? '10+' : number.toString();
              
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label, style: GoogleFonts.inter(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                  selected: isSelected,
                  selectedColor: StageColors.brandCyan.withOpacity(0.15),
                  backgroundColor: StageColors.chipUnselectedBg,
                  side: isSelected ? const BorderSide(color: StageColors.brandCyan) : BorderSide.none,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onSelected: (val) {
                    if (val) setState(() => _selectedSemester = number);
                  },
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // --- Step 3 Build ---
  Widget _buildStep3() {
    final maxAreasReached = _selectedAreas.length >= 5;

    return _StepContentLayout(
      headline: 'O que você\nbusca?',
      subtitle: 'Selecione tudo que te interessa.',
      children: [
        Text('Tipo de Vaga', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: _jobTypes.map((type) {
            final isSelected = _selectedJobTypes.contains(type);
            return FilterChip(
              label: Text(type),
              selected: isSelected,
              onSelected: (val) {
                setState(() {
                  val ? _selectedJobTypes.add(type) : _selectedJobTypes.remove(type);
                });
              },
              selectedColor: StageColors.brandCyan.withOpacity(0.15),
              backgroundColor: StageColors.chipUnselectedBg,
              side: isSelected ? const BorderSide(color: StageColors.brandCyan) : BorderSide(color: Colors.grey[300]!),
              labelStyle: GoogleFonts.inter(
                color: isSelected ? StageColors.brandBlue : StageColors.chipUnselectedText,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              checkmarkColor: StageColors.brandBlue,
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Áreas de Interesse', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('${_selectedAreas.length}/5 selecionados', 
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: StageColors.brandBlue, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _areas.map((area) {
            final isSelected = _selectedAreas.contains(area);
            final disabled = !isSelected && maxAreasReached;
            
            return Opacity(
              opacity: disabled ? 0.4 : 1.0,
              child: FilterChip(
                label: Text(area),
                selected: isSelected,
                onSelected: disabled ? null : (val) {
                  setState(() {
                    val ? _selectedAreas.add(area) : _selectedAreas.remove(area);
                  });
                },
                selectedColor: StageColors.brandCyan.withOpacity(0.15),
                backgroundColor: StageColors.chipUnselectedBg,
                side: isSelected ? const BorderSide(color: StageColors.brandCyan) : BorderSide.none,
                labelStyle: GoogleFonts.inter(
                  color: isSelected ? StageColors.brandBlue : StageColors.chipUnselectedText,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                checkmarkColor: StageColors.brandBlue,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        Text('Modelo de Trabalho', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _workModels.map((model) {
              final isSelected = _selectedWorkModel == model;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(model),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) setState(() => _selectedWorkModel = model);
                  },
                  selectedColor: StageColors.brandCyan.withOpacity(0.15),
                  backgroundColor: StageColors.chipUnselectedBg,
                  side: isSelected ? const BorderSide(color: StageColors.brandCyan) : BorderSide(color: Colors.grey[300]!),
                  labelStyle: GoogleFonts.inter(
                    color: isSelected ? StageColors.brandBlue : StageColors.chipUnselectedText,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // --- Main Build ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StageColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            // Top Nav
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () {
                      if (_currentStep > 0) {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                        );
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (_currentStep + 1) / 3,
                          minHeight: 8,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(StageColors.brandCyan),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _skipOptional,
                    child: Text('Pular', style: GoogleFonts.inter(color: StageColors.subtitleGray, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            
            // Step indication
            Text('Passo ${_currentStep + 1} de 3', style: GoogleFonts.inter(color: StageColors.subtitleGray, fontWeight: FontWeight.bold)),

            // View Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Only code-driven navigation
                onPageChanged: (i) => setState(() => _currentStep = i),
                children: [
                   _buildStep1(),
                   _buildStep2(),
                   _buildStep3(),
                ],
              ),
            ),

            // Bottom CTA
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isCurrentStepValid ? _nextStep : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StageColors.ctaGreen,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    'Continuar',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isCurrentStepValid ? Colors.white : Colors.grey[500],
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

  InputDecoration _inputDecoration(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: StageColors.hintGray),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: StageColors.brandCyan, width: 2)),
      labelStyle: GoogleFonts.inter(color: StageColors.subtitleGray),
    );
  }
}

class _StepContentLayout extends StatelessWidget {
  final String headline;
  final String subtitle;
  final List<Widget> children;

  const _StepContentLayout({
    required this.headline,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline, style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: StageColors.titleText, height: 1.2)),
          const SizedBox(height: 8),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 16, color: StageColors.subtitleGray)),
          const SizedBox(height: 32),
          ...children,
        ],
      ),
    );
  }
}
