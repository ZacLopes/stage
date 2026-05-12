import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../resume_viewmodel.dart';

class ResumeTemplateSelector extends StatelessWidget {
  const ResumeTemplateSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ResumeViewModel>();
    
    final templates = [
      {
        'id': 'harvard_ats',
        'name': 'Harvard ATS Brasil',
        'description': 'Modelo limpo, tradicional e altamente compatível com plataformas de candidatura. Ideal para processos seletivos, vagas corporativas, tecnologia, estágio, consultoria, financeiro, administrativo e áreas profissionais em geral.',
        'ats': 'Alta',
        'style': 'Clássico, profissional e minimalista',
        'color': Colors.black,
      },
      {
        'id': 'jakes_resume',
        'name': 'Jake\'s Resume',
        'description': 'Padrão de tech e engenharia inspirado no clássico LaTeX. Layout em coluna única, fonte serifada, headers com underline. Aprovado em Big Techs, FAANG, fintechs e startups de alto crescimento.',
        'ats': 'Alta',
        'style': 'Serif clássico, denso e elegante',
        'color': const Color(0xFF1F2937),
      },
      {
        'id': 'forte_foundation',
        'name': 'Forte Foundation',
        'description': 'Padrão internacional para banking, consultoria e MBA admissions. Datas alinhadas à direita, GPA prominente, formato conservador. Ideal para Itaú BBA, BTG, Stone, McKinsey, BCG, Big Four.',
        'ats': 'Alta',
        'style': 'Times serif, conservador',
        'color': const Color(0xFF0B2A4A),
      },
      {
        'id': 'one_page_compact',
        'name': 'One-Page Compact',
        'description': 'Garantido em 1 página, sans-serif moderno. Otimizado para estudantes com 1-3 experiências. Visual leve, perfeito para programas trainee, estágios e primeiro emprego.',
        'ats': 'Alta',
        'style': 'Sans-serif moderno, compacto',
        'color': const Color(0xFF0F172A),
      },
    ];

    return Container(
      height: 420,
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
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF111827),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[100],
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
              itemCount: templates.length,
              separatorBuilder: (context, index) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final template = templates[index];
                final isSelected = viewModel.selectedTemplateId == template['id'];
                
                return GestureDetector(
                  onTap: () {
                    viewModel.setSelectedTemplateId(template['id'] as String);
                  },
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isSelected ? (template['color'] as Color).withOpacity(0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isSelected ? (template['color'] as Color) : Colors.grey[200]!,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: (template['color'] as Color).withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ] : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: template['color'] as Color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                template['name'] as String,
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          template['description'] as String,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey[600],
                            height: 1.4,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        _buildMetaRow('Compatibilidade ATS:', template['ats'] as String, isSelected),
                        const SizedBox(height: 4),
                        _buildMetaRow('Estilo:', template['style'] as String, isSelected),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              viewModel.setSelectedTemplateId(template['id'] as String);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSelected ? (template['color'] as Color) : Colors.grey[100],
                              foregroundColor: isSelected ? Colors.white : Colors.black87,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value, bool isSelected) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey[500],
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1F2937),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
