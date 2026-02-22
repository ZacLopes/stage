import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/models.dart';

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

class _ResumeEditScreenState extends State<ResumeEditScreen> {
  // Text Controllers
  late TextEditingController _summaryController;
  late TextEditingController _skillsController;
  late TextEditingController _interestsController;

  // Lists
  late List<ResumeExperience> _experiences;
  late List<ResumeEducation> _education;
  late List<ResumeProject> _projects;
  late List<ResumeCourse> _courses;
  late List<ResumeLanguage> _languages;
  late List<ResumeAward> _awards;

  @override
  void initState() {
    super.initState();
    _summaryController = TextEditingController(text: widget.initialContent.summary);
    _skillsController = TextEditingController(text: widget.initialContent.skills);
    _interestsController = TextEditingController(text: widget.initialContent.interests);

    _experiences = List.from(widget.initialContent.experiences);
    _education = List.from(widget.initialContent.education);
    _projects = List.from(widget.initialContent.academicProjects);
    _courses = List.from(widget.initialContent.courses);
    _languages = List.from(widget.initialContent.languages);
    _awards = List.from(widget.initialContent.awards);
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _skillsController.dispose();
    _interestsController.dispose();
    super.dispose();
  }

  void _save() {
    final newContent = ResumeContent(
      summary: _summaryController.text,
      skills: _skillsController.text,
      interests: _interestsController.text,
      experiences: _experiences,
      education: _education,
      academicProjects: _projects,
      courses: _courses,
      languages: _languages,
      awards: _awards,
      achievements: '', // Deprecated placeholder
      leadership: [], // Forced empty as per user request
    );
    widget.onSave(newContent);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text('Editar Currículo', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_circle, color: Color(0xFF10B981)),
            label: Text('Salvar', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildSectionCard(
              title: 'Resumo Profissional',
              icon: Icons.person,
              child: _buildTextField(_summaryController, hint: 'Escreva um breve resumo sobre você...', maxLines: 5),
            ),
            const SizedBox(height: 16),
            
            _buildEducationSection(),
            const SizedBox(height: 16),
            
            _buildExperienceSection(),
            const SizedBox(height: 16),

            _buildProjectsSection(),
            const SizedBox(height: 16),

            _buildSectionCard(
              title: 'Habilidades',
              icon: Icons.psychology,
              child: _buildTextField(_skillsController, hint: 'Separe suas habilidades por linhas ou vírgulas.', maxLines: 4),
            ),
            const SizedBox(height: 16),

            _buildCoursesSection(),
            const SizedBox(height: 16),

            _buildLanguagesSection(),
            const SizedBox(height: 16),

            _buildAwardsSection(),
            const SizedBox(height: 16),

            _buildSectionCard(
              title: 'Interesses',
              icon: Icons.interests,
              child: _buildTextField(_interestsController, hint: 'Seus interesses pessoais (ex: Tecnologia, Esportes...)', maxLines: 3),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Builders ---

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child, Widget? trailingAction}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: const Color(0xFF4F46E5), size: 20),
          ),
          title: Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
          trailing: trailingAction,
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [child],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, {String? hint, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.all(16),
      ),
      style: GoogleFonts.inter(fontSize: 14, height: 1.5),
    );
  }

  // --- Specialized List Builders ---

  Widget _buildExperienceSection() {
    return _buildSectionCard(
      title: 'Experiência Profissional',
      icon: Icons.work,
      child: Column(
        children: [
          ..._experiences.asMap().entries.map((entry) => _buildListItemCard(
            title: entry.value.role,
            subtitle: '${entry.value.company} • ${entry.value.period}',
            onEdit: () => _editExperience(entry.key),
            onDelete: () => setState(() => _experiences.removeAt(entry.key)),
          )),
          _buildAddButton('Adicionar Experiência', () => _editExperience(null)),
        ],
      ),
    );
  }

  Widget _buildEducationSection() {
    return _buildSectionCard(
      title: 'Formação Acadêmica',
      icon: Icons.school,
      child: Column(
        children: [
          ..._education.asMap().entries.map((entry) => _buildListItemCard(
            title: entry.value.course, // Using 'course' as the degree/major field
            // ResumeEducation has: institution, course, period, details. 
            // Often 'course' is the degree/major.
            // Let's check model. ResumeEducation has (institution, course, period, details). 
            // Where 'degree' acts usually as course name. 
            // In PDF we use `edu.degree`. Wait, model says `course`.
            // Ah, I need to check `ResumeEducation` model again.
            // Model: institution, course, period, details.
            // PDF: `edu.degree`.
            // Wait, does ResumeEducation have `degree`? 
            // Let's access via `course` which maps to degree usually.
            // Actually, in ResumeTemplate: `edu.degree`.
            // ResumeEducation in models.dart (line 359) has attributes: institution, course, period, details.
            // But Template uses `.degree`. Is it an extension/getter? 
            // Or did I misread model?
            // Line 361: final String course;
            // Line 366: required this.course,
            // I will assume `edu.course` is what we want.
            // Checking previous `resume_templates.dart`: `Text(edu.degree, ...)`
            // This implies `ResumeEducation` HAS a getter `degree`.
            // Or `course` IS accessible as `degree`?
            // I will use `entry.value.course` safely.
            subtitle: '${entry.value.institution} • ${entry.value.period}',
            onEdit: () => _editEducation(entry.key),
            onDelete: () => setState(() => _education.removeAt(entry.key)),
          )),
          _buildAddButton('Adicionar Formação', () => _editEducation(null)),
        ],
      ),
    );
  }

  Widget _buildProjectsSection() {
    return _buildSectionCard(
      title: 'Projetos',
      icon: Icons.folder,
      child: Column(
        children: [
          ..._projects.asMap().entries.map((entry) => _buildListItemCard(
            title: entry.value.title,
            subtitle: entry.value.role,
            onEdit: () => _editProject(entry.key),
            onDelete: () => setState(() => _projects.removeAt(entry.key)),
          )),
          _buildAddButton('Adicionar Projeto', () => _editProject(null)),
        ],
      ),
    );
  }

  Widget _buildCoursesSection() {
    return _buildSectionCard(
      title: 'Cursos e Certificações',
      icon: Icons.card_membership,
      child: Column(
        children: [
          ..._courses.asMap().entries.map((entry) => _buildListItemCard(
            title: entry.value.title,
            subtitle: entry.value.institution,
            onEdit: () => _editCourse(entry.key),
            onDelete: () => setState(() => _courses.removeAt(entry.key)),
          )),
          _buildAddButton('Adicionar Curso', () => _editCourse(null)),
        ],
      ),
    );
  }

  Widget _buildLanguagesSection() {
    return _buildSectionCard(
      title: 'Idiomas',
      icon: Icons.language,
      child: Column(
        children: [
          ..._languages.asMap().entries.map((entry) => _buildListItemCard(
            title: entry.value.language,
            subtitle: entry.value.level,
            onEdit: () => _editLanguage(entry.key),
            onDelete: () => setState(() => _languages.removeAt(entry.key)),
          )),
          _buildAddButton('Adicionar Idioma', () => _editLanguage(null)),
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
          ..._awards.asMap().entries.map((entry) => _buildListItemCard(
            title: entry.value.title,
            subtitle: entry.value.institution,
            onEdit: () => _editAward(entry.key),
            onDelete: () => setState(() => _awards.removeAt(entry.key)),
          )),
          _buildAddButton('Adicionar Premiação', () => _editAward(null)),
        ],
      ),
    );
  }

  // --- Generic UI Components ---

  Widget _buildListItemCard({required String title, required String subtitle, required VoidCallback onEdit, required VoidCallback onDelete}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFFF9FAFB),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style:GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.blueGrey), onPressed: onEdit),
            IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent), onPressed: onDelete),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF4F46E5), style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 16, color: Color(0xFF4F46E5)),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.inter(color: const Color(0xFF4F46E5), fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // --- Dialogs ---

  Future<void> _showFormDialog({
    required String title,
    required List<Widget> children,
    required VoidCallback onSave,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental close
      builder: (context) => AlertDialog(
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
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
      title: index == null ? 'Nova Experiência' : 'Editar Experiência',
      children: [
        _buildTextField(roleCtrl, hint: 'Cargo'),
        const SizedBox(height: 8),
        _buildTextField(compCtrl, hint: 'Empresa'),
        const SizedBox(height: 8),
        _buildTextField(dateCtrl, hint: 'Período (ex: Jan 2023 - Atual)'),
        const SizedBox(height: 8),
        _buildTextField(descCtrl, hint: 'Descrição das atividades', maxLines: 4),
      ],
      onSave: () {
        final newExp = ResumeExperience(
          role: roleCtrl.text,
          company: compCtrl.text,
          period: dateCtrl.text,
          description: descCtrl.text,
        );
        setState(() {
          if (index != null) {
            _experiences[index] = newExp;
          } else {
            _experiences.add(newExp);
          }
        });
      },
    );
  }

  void _editEducation(int? index) {
    final edu = index != null ? _education[index] : null;
    final courseCtrl = TextEditingController(text: edu?.course);
    final instCtrl = TextEditingController(text: edu?.institution);
    final dateCtrl = TextEditingController(text: edu?.period);
    final detailsCtrl = TextEditingController(text: edu?.details);

    _showFormDialog(
      title: index == null ? 'Nova Formação' : 'Editar Formação',
      children: [
        _buildTextField(courseCtrl, hint: 'Curso / Grau'),
        const SizedBox(height: 8),
        _buildTextField(instCtrl, hint: 'Instituição'),
        const SizedBox(height: 8),
        _buildTextField(dateCtrl, hint: 'Período'),
        const SizedBox(height: 8),
        _buildTextField(detailsCtrl, hint: 'Detalhes (opcional)'),
      ],
      onSave: () {
        final newEdu = ResumeEducation(
          course: courseCtrl.text,
          institution: instCtrl.text,
          period: dateCtrl.text,
          details: detailsCtrl.text,
        );
        setState(() {
          if (index != null) {
            _education[index] = newEdu;
          } else {
            _education.add(newEdu);
          }
        });
      },
    );
  }

  void _editProject(int? index) {
    final proj = index != null ? _projects[index] : null;
    final titleCtrl = TextEditingController(text: proj?.title);
    final roleCtrl = TextEditingController(text: proj?.role);
    final descCtrl = TextEditingController(text: proj?.description);

    _showFormDialog(
      title: index == null ? 'Novo Projeto' : 'Editar Projeto',
      children: [
        _buildTextField(titleCtrl, hint: 'Título do Projeto'),
        const SizedBox(height: 8),
        _buildTextField(roleCtrl, hint: 'Seu Papel / Tecnologias'),
        const SizedBox(height: 8),
        _buildTextField(descCtrl, hint: 'Descrição', maxLines: 3),
      ],
      onSave: () {
        final newProj = ResumeProject(
          title: titleCtrl.text,
          role: roleCtrl.text,
          period: '', // Not used actively in UI currently
          description: descCtrl.text,
        );
        setState(() {
          if (index != null) {
            _projects[index] = newProj;
          } else {
            _projects.add(newProj);
          }
        });
      },
    );
  }

  void _editCourse(int? index) {
    final course = index != null ? _courses[index] : null;
    final titleCtrl = TextEditingController(text: course?.title);
    final instCtrl = TextEditingController(text: course?.institution);
    final dateCtrl = TextEditingController(text: course?.period);

    _showFormDialog(
      title: index == null ? 'Novo Curso' : 'Editar Curso',
      children: [
        _buildTextField(titleCtrl, hint: 'Nome do Curso'),
        const SizedBox(height: 8),
        _buildTextField(instCtrl, hint: 'Instituição / Plataforma'),
        const SizedBox(height: 8),
        _buildTextField(dateCtrl, hint: 'Data / Carga Horária'),
      ],
      onSave: () {
        final newCourse = ResumeCourse(
          title: titleCtrl.text,
          institution: instCtrl.text,
          period: dateCtrl.text,
        );
        setState(() {
          if (index != null) {
            _courses[index] = newCourse;
          } else {
            _courses.add(newCourse);
          }
        });
      },
    );
  }

  void _editLanguage(int? index) {
    final lang = index != null ? _languages[index] : null;
    final nameCtrl = TextEditingController(text: lang?.language);
    final levelCtrl = TextEditingController(text: lang?.level);

    _showFormDialog(
      title: index == null ? 'Novo Idioma' : 'Editar Idioma',
      children: [
        _buildTextField(nameCtrl, hint: 'Idioma (ex: Inglês)'),
        const SizedBox(height: 8),
        _buildTextField(levelCtrl, hint: 'Nível (ex: Avançado, B2)'),
      ],
      onSave: () {
        final newLang = ResumeLanguage(
          language: nameCtrl.text,
          level: levelCtrl.text,
        );
        setState(() {
          if (index != null) {
            _languages[index] = newLang;
          } else {
            _languages.add(newLang);
          }
        });
      },
    );
  }

    void _editAward(int? index) {
    final award = index != null ? _awards[index] : null;
    final titleCtrl = TextEditingController(text: award?.title);
    final instCtrl = TextEditingController(text: award?.institution);
    final dateCtrl = TextEditingController(text: award?.date);

    _showFormDialog(
      title: index == null ? 'Nova Premiação' : 'Editar Premiação',
      children: [
        _buildTextField(titleCtrl, hint: 'Título do Prêmio'),
        const SizedBox(height: 8),
        _buildTextField(instCtrl, hint: 'Emissor / Instituição'),
        const SizedBox(height: 8),
        _buildTextField(dateCtrl, hint: 'Data'),
      ],
      onSave: () {
        final newAward = ResumeAward(
          title: titleCtrl.text,
          institution: instCtrl.text,
          date: dateCtrl.text,
          description: '', // Optional field
        );
        setState(() {
          if (index != null) {
            _awards[index] = newAward;
          } else {
            _awards.add(newAward);
          }
        });
      },
    );
  }
}
