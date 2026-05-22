// ProfileEditorScreen — editor permanente do perfil estruturado.
//
// Acessado via botão "Editar Perfil" na aba Perfil atual. Não tem barra de
// progresso nem botão Continue — autosave contínuo via ProfileEditorViewModel.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../application/profile_editor_view_model.dart';
import 'widgets/personal_info_form.dart';
import 'widgets/profile_section_list.dart';

class ProfileEditorScreen extends StatefulWidget {
  const ProfileEditorScreen({super.key});

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  bool _personalExpanded = false;

  @override
  void initState() {
    super.initState();
    // Carrega ao abrir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProfileEditorViewModel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileEditorViewModel>();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Editar Perfil'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          _saveIndicator(vm.saveStatus),
          const SizedBox(width: 8),
        ],
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00C27A)))
          : RefreshIndicator(
              color: const Color(0xFF00C27A),
              onRefresh: () => vm.load(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _header(vm),
                  const SizedBox(height: 16),
                  _personalCard(vm),
                  const SizedBox(height: 12),
                  const ProfileSectionList(
                    showLowConfidenceBadges: false,
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _saveIndicator(SaveStatus status) {
    String label;
    Color color;
    IconData icon;
    switch (status) {
      case SaveStatus.saving:
        label = 'Salvando...';
        color = const Color(0xFF6B7280);
        icon = Icons.sync;
        break;
      case SaveStatus.saved:
        label = 'Salvo';
        color = const Color(0xFF10B981);
        icon = Icons.check_circle_outline;
        break;
      case SaveStatus.error:
        label = 'Erro';
        color = const Color(0xFFEF4444);
        icon = Icons.error_outline;
        break;
      case SaveStatus.idle:
        return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _header(ProfileEditorViewModel vm) {
    final p = vm.personal;
    final name = p?.fullName ?? '';
    final headline = p?.headline ?? '';
    final location = p?.formattedLocation ?? '';
    final score = vm.completenessScore;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF00C27A).withValues(alpha: 0.15),
                child: Text(
                  name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF00C27A),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Seu nome' : name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    if (headline.isNotEmpty || location.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [headline, location].where((s) => s.isNotEmpty).join(' • '),
                          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    backgroundColor: const Color(0xFFE5E7EB),
                    color: const Color(0xFF00C27A),
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$score% completo',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _personalCard(ProfileEditorViewModel vm) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _personalExpanded = !_personalExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: Color(0xFF6B7280)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Informações pessoais',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    _personalExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: const Color(0xFF6B7280),
                  ),
                ],
              ),
            ),
          ),
          if (_personalExpanded && vm.personal != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: PersonalInfoForm(
                initial: vm.personal,
                onChanged: (draft) => vm.updatePersonalDraft(draft),
              ),
            ),
        ],
      ),
    );
  }
}
