import 'package:flutter/material.dart';
import '../../core/analytics/screen_tracking.dart';
import '../../data/models/models.dart';
import '../../core/widgets/pii_mask.dart';

class ProfileEditScreen extends StatefulWidget {
  final ProfileContent initialContent;
  final Function(ProfileContent) onSave;

  const ProfileEditScreen({
    super.key,
    required this.initialContent,
    required this.onSave,
  });

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'profile_edit';

  late TextEditingController _aboutMeController;
  late TextEditingController _experiencesController;
  late TextEditingController _skillsController;
  late TextEditingController _interestsController;

  @override
  void initState() {
    super.initState();
    _aboutMeController = TextEditingController(text: widget.initialContent.aboutMe);
    _experiencesController = TextEditingController(text: widget.initialContent.experiences);
    _skillsController = TextEditingController(text: widget.initialContent.skills);
    _interestsController = TextEditingController(text: widget.initialContent.interests);
  }

  @override
  void dispose() {
    _aboutMeController.dispose();
    _experiencesController.dispose();
    _skillsController.dispose();
    _interestsController.dispose();
    super.dispose();
  }

  void _save() {
    final newContent = ProfileContent(
      aboutMe: _aboutMeController.text,
      experiences: _experiencesController.text,
      skills: _skillsController.text,
      interests: _interestsController.text,
    );
    widget.onSave(newContent);
    Navigator.pop(context);
  }

  bool _isEditable(String text) {
    if (text.isEmpty) return false;
    if (text.contains('Continue a trilha')) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PiiMask(child: Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
            tooltip: 'Salvar',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildField('Sobre Mim', _aboutMeController, maxLines: 5),
            const SizedBox(height: 16),
            _buildField('Experiências', _experiencesController, maxLines: 5, hint: 'Descreva suas experiências'),
            const SizedBox(height: 16),
            _buildField('Habilidades', _skillsController, maxLines: 5, hint: 'Liste suas habilidades'),
            const SizedBox(height: 16),
            _buildField('Interesses', _interestsController, maxLines: 3, hint: 'Liste seus interesses'),
          ],
        ),
      ),
    ));
  }

  Widget _buildField(String label, TextEditingController controller, {int maxLines = 1, String? hint}) {
    final isEditable = _isEditable(controller.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF111827))),
            if (!isEditable) ...[
              const SizedBox(width: 8),
              const Icon(Icons.lock, size: 16, color: Colors.grey),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          readOnly: !isEditable,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            hintText: isEditable ? hint : 'Complete a trilha para desbloquear esta seção.',
            filled: true,
            fillColor: isEditable ? Colors.white : Colors.grey[200],
          ),
        ),
      ],
    );
  }
}
