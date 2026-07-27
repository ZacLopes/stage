import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/analytics_service.dart';
import '../resume_viewmodel.dart';
import '../../../core/theme/theme.dart';

class ResumeTemplateSelector extends StatefulWidget {
  const ResumeTemplateSelector({super.key});

  /// Nome de exibição de um template por id (fonte única = o catálogo abaixo).
  /// Usado por superfícies fora do seletor (ex.: chip de modelo do Currículo
  /// geral). Fallback pro primeiro template pra id desconhecido.
  static String displayName(String id) {
    final meta = _ResumeTemplateSelectorState._templates.firstWhere(
      (t) => t.id == id,
      orElse: () => _ResumeTemplateSelectorState._templates.first,
    );
    return meta.name;
  }

  @override
  State<ResumeTemplateSelector> createState() => _ResumeTemplateSelectorState();
}

class _ResumeTemplateSelectorState extends State<ResumeTemplateSelector> {
  // Metadata estática dos 4 templates. Pra adicionar/remover template:
  //  1. Edita esta lista
  //  2. Atualiza o switch em `PdfService.generateResumeBytes`
  //  3. Roda Settings → "[DEV] Gerar thumbnails dos templates" e copia o PNG
  //     novo pra `assets/images/templates/`
  static const List<_TemplateMeta> _templates = [
    _TemplateMeta(
      id: 'harvard_ats',
      name: 'Harvard ATS Brasil',
      thumbnail: 'assets/images/templates/harvard_ats.png',
      description:
          'Modelo limpo, tradicional e altamente compatível com plataformas de candidatura. Ideal para vagas corporativas e estágio.',
      ats: 'Alta',
      style: 'Clássico, profissional, minimalista',
      color: Colors.black,
    ),
    _TemplateMeta(
      id: 'jakes_resume',
      name: "Jake's Resume",
      thumbnail: 'assets/images/templates/jakes_resume.png',
      description:
          'Padrão de tech e engenharia inspirado no clássico LaTeX. Aprovado em Big Techs, FAANG e startups.',
      ats: 'Alta',
      style: 'Serif clássico, denso e elegante',
      color: AppColors.textPrimary,
    ),
    _TemplateMeta(
      id: 'forte_foundation',
      name: 'Forte Foundation',
      thumbnail: 'assets/images/templates/forte_foundation.png',
      description:
          'Padrão internacional para banking, consultoria e MBA. Datas alinhadas à direita, GPA prominente.',
      ats: 'Alta',
      style: 'Times serif, conservador',
      color: Color(0xFF0B2A4A),
    ),
    _TemplateMeta(
      id: 'one_page_compact',
      name: 'One-Page Compact',
      thumbnail: 'assets/images/templates/one_page_compact.png',
      description:
          'Garantido em 1 página, sans-serif moderno. Otimizado para estudantes com 1-3 experiências.',
      ats: 'Alta',
      style: 'Sans-serif moderno, compacto',
      color: AppColors.textPrimary,
    ),
    _TemplateMeta(
      id: 'cobalt_modern',
      name: 'Cobalt Modern',
      thumbnail: 'assets/images/templates/cobalt_modern.png',
      description:
          'Layout 2 colunas com sidebar de contato/skills, cor de destaque azul cobalt. Ideal pra design, marketing, tech e candidatos que querem se diferenciar visualmente.',
      ats: 'Média-Alta',
      style: 'Sans-serif moderno (Inter), 2 colunas, accent azul',
      color: AppColors.primary,
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Captura o currentTemplateId no frame seguinte pra ler do Provider
    // sem cair em "didChangeDependencies before initState" issues.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final viewModel = context.read<ResumeViewModel>();
      Analytics.shared.cvTemplateSelectorOpened(
        currentTemplateId: viewModel.selectedTemplateId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ResumeViewModel>();

    return Container(
      height: 560,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Escolha seu Modelo',
                  style: TextStyle(fontFamily: 'Outfit', 
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.divider,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: _templates.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final template = _templates[index];
                final isSelected = viewModel.selectedTemplateId == template.id;
                return _TemplateCard(
                  template: template,
                  isSelected: isSelected,
                  onTap: () {
                    viewModel.setSelectedTemplateId(template.id);
                    Analytics.shared.cvTemplateChanged(templateId: template.id);
                  },
                  onUseTap: () {
                    viewModel.setSelectedTemplateId(template.id);
                    Analytics.shared.cvTemplateChanged(templateId: template.id);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final _TemplateMeta template;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onUseTap;

  const _TemplateCard({
    required this.template,
    required this.isSelected,
    required this.onTap,
    required this.onUseTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? template.color.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? template.color : AppColors.border!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: template.color.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail (A4 ratio 1:1.414)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1 / 1.414,
                child: Image.asset(
                  template.thumbnail,
                  fit: BoxFit.cover,
                  cacheWidth: 600, // ~2x retina pra cards de ~268px
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.divider,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image_outlined,
                                size: 32, color: AppColors.textDisabled),
                            const SizedBox(height: 8),
                            Text(
                              'Preview indisponível',
                              style: TextStyle(fontFamily: 'Inter', 
                                fontSize: 11,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Nome + check
            Row(
              children: [
                Expanded(
                  child: Text(
                    template.name,
                    style: TextStyle(fontFamily: 'Outfit', 
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle,
                      color: Colors.green, size: 20),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              template.description,
              style: TextStyle(fontFamily: 'Inter', 
                fontSize: 12,
                color: AppColors.textTertiary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onUseTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isSelected ? template.color : AppColors.divider,
                  foregroundColor:
                      isSelected ? Colors.white : Colors.black87,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: Text(
                  isSelected ? 'Selecionado' : 'Usar este Modelo',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateMeta {
  final String id;
  final String name;
  final String thumbnail;
  final String description;
  final String ats;
  final String style;
  final Color color;

  const _TemplateMeta({
    required this.id,
    required this.name,
    required this.thumbnail,
    required this.description,
    required this.ats,
    required this.style,
    required this.color,
  });
}
