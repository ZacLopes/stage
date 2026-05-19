import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../core/constants/stage_colors.dart';
import '../../services/analytics_service.dart';
import 'user_viewmodel.dart';
import '../../core/widgets/pii_mask.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'onboarding_profile_setup';

  final PageController _pageController = PageController();
  int _currentStep = 0;
  
  // Step 1
  late TextEditingController _nameController;
  DateTime? _selectedDate;
  final _dobController = TextEditingController();
  String? _dobError;
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
    Analytics.shared.onboardingStepReached(step: 3, stepId: 'profile_setup');
    // Prefill name — mas trata "User" (sentinela legacy do bug antigo do Apple
    // sign-in) como vazio. User antigo via Apple tem name="User" no DB e
    // pré-preencher esse campo confunde — força o user a editar à mão.
    final vm = context.read<UserViewModel>();
    final rawName = (vm.user?.name ?? '').trim();
    final cleanName = rawName.toLowerCase() == 'user' ? '' : rawName;
    _nameController = TextEditingController(text: cleanName);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    _uniController.dispose();
    _courseController.dispose();
    super.dispose();
  }

  /// Valida e parseia a string `DD/MM/AAAA` em um DateTime.
  /// Regras:
  ///   - Vazio ou incompleto → date=null, sem erro (não polui UI antes da hora)
  ///   - Mês inválido (00/13+) → erro "Mês inválido"
  ///   - Dia inválido pro mês (ex: 31/02, 30/02) → erro "Dia inválido"
  ///   - Ano fora de 1950..hoje → erro "Ano inválido"
  ///   - Idade < 14 → erro "Idade mínima 14 anos"
  ///   - Idade > 100 → erro "Verifique a data"
  _ParsedDob _parseDob(String raw) {
    if (raw.isEmpty) return const _ParsedDob(null, null);
    // Aceita DD/MM/AAAA completo. Antes disso, ainda digitando → sem erro.
    if (raw.length < 10) return const _ParsedDob(null, null);

    final parts = raw.split('/');
    if (parts.length != 3) return const _ParsedDob(null, 'Data inválida');

    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) {
      return const _ParsedDob(null, 'Data inválida');
    }

    if (month < 1 || month > 12) {
      return const _ParsedDob(null, 'Mês inválido');
    }

    // DateTime.utc faz a checagem de dia: se digitar 31/02 ele retorna 02/03.
    // Verificamos que o roundtrip bate.
    final candidate = DateTime(year, month, day);
    if (candidate.day != day ||
        candidate.month != month ||
        candidate.year != year) {
      return const _ParsedDob(null, 'Dia inválido');
    }

    final now = DateTime.now();
    if (year < 1950 || candidate.isAfter(now)) {
      return const _ParsedDob(null, 'Ano inválido');
    }

    // Idade aproximada
    var age = now.year - year;
    if (now.month < month || (now.month == month && now.day < day)) {
      age--;
    }
    if (age < 14) {
      return const _ParsedDob(null, 'Idade mínima 14 anos');
    }
    if (age > 100) {
      return const _ParsedDob(null, 'Verifique a data');
    }

    return _ParsedDob(candidate, null);
  }

  Future<void> _confirmExitOnboarding() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair do cadastro?'),
        content: const Text(
          'Você vai precisar entrar de novo. Seu progresso desta tela será perdido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continuar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Sair', style: TextStyle(color: StageColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<UserViewModel>().logout();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao sair: $e'), backgroundColor: StageColors.error),
        );
      }
    }
  }

  bool get _isCurrentStepValid {
    if (_currentStep == 0) {
      // Step 1 pede: nome (pode vir pré-preenchido) + nascimento + celular.
      // Phone: mínimo 10 dígitos (fixos/móveis com DDD).
      final name = _nameController.text.trim();
      final phoneDigits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
      return name.length >= 2 &&
          name.toLowerCase() != 'user' &&
          _selectedDate != null &&
          phoneDigits.length >= 10;
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
          phone: _phoneController.text,
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

        // Não navegamos manualmente — quem chamou o ProfileSetup foi o
        // AuthGate (Consumer<UserViewModel>) ou o EmailSignup. Em ambos os
        // casos, a tela está sob um AuthGate ativo que reage à mudança de
        // `needsProfileSetup` e re-roteia automaticamente pra CompletionScreen.
        // Push manual aqui duplicava o AuthGate na árvore → GlobalKey
        // colisão (tutorial.jobsTab da BottomNav).
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: StageColors.error),
          );
        }
      }
    }
  }


  // --- Step 1 Build ---
  Widget _buildStep1() {
    return _StepContentLayout(
      headline: 'Conta mais\nsobre você',
      subtitle: 'Pra gente personalizar sua experiência.',
      children: [
        // Nome — pré-preenchido pelos providers (email signup, Google, Apple
        // com nome). Quando vazio (Apple sem nome / providers que não retornam
        // nome), user edita aqui. Sempre obrigatório no save final.
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('Nome completo', Icons.person_outline),
        ),
        const SizedBox(height: 20),

        // Data de Nascimento — input digitado com máscara DD/MM/AAAA.
        // Aceita só dígitos, insere as barras automaticamente, valida em
        // tempo real (mês 01-12, dia válido pro mês, ano entre 1950 e hoje).
        TextField(
          controller: _dobController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _DateInputFormatter(),
          ],
          onChanged: (raw) {
            final parsed = _parseDob(raw);
            setState(() {
              _selectedDate = parsed.date;
              _dobError = parsed.error;
            });
          },
          decoration: _inputDecoration(
            'Data de Nascimento',
            Icons.calendar_today,
            hint: 'DD/MM/AAAA',
          ).copyWith(errorText: _dobError),
        ),
        const SizedBox(height: 20),
        
        // Phone (Required) — máscara `(DD) NNNNN-NNNN` automática.
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _PhoneInputFormatter(),
          ],
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('Celular', Icons.phone_outlined, hint: '(11) 99999-9999'),
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

        // Semester — campo que abre bottom sheet com slide-up suave.
        // Visualmente igual aos outros TextFields, mas a interação é
        // mais fluida que o DropdownButtonFormField padrão (que pula
        // sem animação clara e estoura a tela com 11 items).
        _SemesterField(
          value: _selectedSemester,
          onChanged: (val) => setState(() => _selectedSemester = val),
          decoration: _inputDecoration('Semestre', Icons.timeline_rounded),
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
    return PiiMask(child: Scaffold(
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
                        // Step 0: ProfileSetup é root via AuthGate (não foi
                        // pushed). Navigator.pop() pop a única rota → tela
                        // preta. Solução: confirma logout, AuthGate auto-
                        // roteia pra AuthScreen quando user vira null.
                        _confirmExitOnboarding();
                      }
                    },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 24),
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
    ));
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

/// Resultado do parsing da data digitada.
class _ParsedDob {
  final DateTime? date;
  final String? error;
  const _ParsedDob(this.date, this.error);
}

/// `TextInputFormatter` que aceita só dígitos e insere automaticamente as
/// barras de DD/MM/AAAA. Suporta backspace corretamente — quando o user
/// apaga, as barras saem junto se necessário.
class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Extrai só os dígitos do que o user digitou (descarta barras digitadas)
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > 8 ? digits.substring(0, 8) : digits;

    // Reconstroi com barras: DD/MM/AAAA
    final buf = StringBuffer();
    for (var i = 0; i < truncated.length; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(truncated[i]);
    }
    final formatted = buf.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// `TextInputFormatter` pra celular BR no formato `(DD) NNNNN-NNNN`.
/// Cap em 11 dígitos. Sempre usa split 5-4 (mobile) — fixos de 10 dígitos
/// ficam como `(11) 99999-999` (sem o último), e o user precisa digitar
/// mais um dígito pra completar.
class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > 11 ? digits.substring(0, 11) : digits;

    final buf = StringBuffer();
    for (var i = 0; i < truncated.length; i++) {
      if (i == 0) buf.write('(');
      if (i == 2) buf.write(') ');
      if (i == 7) buf.write('-');
      buf.write(truncated[i]);
    }
    final formatted = buf.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Campo de seleção de semestre. Visualmente idêntico aos TextFields do form.
/// Tap abre um bottom sheet compacto com slide-up suave, em vez do dropdown
/// padrão do Flutter (que tem animação seca e estoura a tela com 11 items).
class _SemesterField extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onChanged;
  final InputDecoration decoration;

  const _SemesterField({
    required this.value,
    required this.onChanged,
    required this.decoration,
  });

  static String _labelFor(int n) => n > 10 ? '10+ semestre' : '${n}º semestre';

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // Animação custom mais suave (300ms ease-out-cubic) em vez do default.
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 320),
        reverseDuration: const Duration(milliseconds: 240),
      ),
      builder: (ctx) => _SemesterPickerSheet(selected: value),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPicker(context),
      child: AbsorbPointer(
        child: TextField(
          controller: TextEditingController(
            text: value == null ? '' : _labelFor(value!),
          ),
          decoration: decoration.copyWith(
            suffixIcon: const Icon(
              Icons.arrow_drop_down_rounded,
              color: StageColors.hintGray,
            ),
          ),
          style: GoogleFonts.inter(
            color: StageColors.darkText,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _SemesterPickerSheet extends StatelessWidget {
  final int? selected;
  const _SemesterPickerSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
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
            // Drag handle visual
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Semestre',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: StageColors.titleText,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: StageColors.hintGray,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Lista compacta — items pequenos pra caber bem
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: 11,
                itemBuilder: (_, i) {
                  final n = i + 1;
                  final isSelected = selected == n;
                  return InkWell(
                    onTap: () => Navigator.pop(context, n),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      color: isSelected
                          ? StageColors.brandCyan.withOpacity(0.08)
                          : Colors.transparent,
                      child: Row(
                        children: [
                          Text(
                            _SemesterField._labelFor(n),
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected
                                  ? StageColors.brandBlue
                                  : StageColors.darkText,
                            ),
                          ),
                          const Spacer(),
                          if (isSelected)
                            const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: StageColors.brandBlue,
                            ),
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
  }
}
