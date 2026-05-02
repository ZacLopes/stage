import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/models.dart';
import 'resume_viewmodel.dart';

// --- Base Widget for Templates ---
abstract class ResumeTemplate extends StatelessWidget {
  final UserProfile? user;
  final ResumeData? resume;

  const ResumeTemplate({super.key, required this.user, required this.resume});
}

// --- 1. Basic Template (Original) ---
class BasicResumeTemplate extends ResumeTemplate {
  const BasicResumeTemplate({super.key, required super.user, required super.resume});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user?.name.toUpperCase() ?? 'SEU NOME',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF111827),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Estudante em ${user?.course ?? "Curso"}',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: const Color(0xFF10B981),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.email_outlined, size: 16, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              Text(
                user?.email ?? 'email@exemplo.com',
                style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF6B7280)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('SUMÁRIO'),
          _buildSectionContent(
            (resume?.summary ?? '').isEmpty
                ? 'Complete os mundos "Direção" e "Síntese" para gerar seu resumo profissional.'
                : resume!.summary,
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('HABILIDADES'),
          (resume?.skills ?? []).isEmpty
              ? _buildSectionContent('Complete o mundo "Minhas Experiências" para listar suas habilidades.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: resume!.skills.map((skill) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                        Expanded(
                          child: Text(
                            skill,
                            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF374151)),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
          const SizedBox(height: 20),
          _buildSectionTitle('EXPERIÊNCIA'),
          (resume?.experiences ?? []).isEmpty
              ? _buildSectionContent('Complete o mundo "O que eu já fiz" para adicionar suas experiências.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: resume!.experiences.map((exp) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exp.role,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          exp.company,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: const Color(0xFF10B981),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (exp.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            exp.description,
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280)),
                          ),
                        ],
                      ],
                    ),
                  )).toList(),
                ),
          const SizedBox(height: 20),
          _buildSectionTitle('FORMAÇÃO'),
          if ((resume?.education ?? []).isEmpty)
             _buildSectionContent('Complete os dados acadêmicos para preencher esta seção.')
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: resume!.education.map((edu) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        edu.degree,
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF111827)),
                      ),
                      Text(
                        edu.institution,
                        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF10B981), fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${edu.period}${edu.details.isNotEmpty ? ' • ${edu.details}' : ''}',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
          if ((resume?.interests ?? []).isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildSectionTitle('INTERESSES'),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: (resume?.interests ?? []).map((interest) => Chip(
                  label: Text(interest, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF374151))),
                  backgroundColor: const Color(0xFFF3F4F6),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF111827), width: 2)),
      ),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF111827),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSectionContent(String content) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        content,
        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF6B7280), height: 1.5),
      ),
    );
  }
}

// --- 2. Clean Template (O Básico Eficiente) ---
class CleanResumeTemplate extends ResumeTemplate {
  const CleanResumeTemplate({super.key, required super.user, required super.resume});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Nome Centralizado
          Text(
            user?.name.toUpperCase() ?? 'SEU NOME',
            style: GoogleFonts.arimo( // Arial alternative
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              letterSpacing: 1.0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Contato
          Text(
            '${user?.email ?? ""} | ${user?.course ?? ""}',
            style: GoogleFonts.arimo(
              fontSize: 12,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          // Resumo
          _buildSection('SUMÁRIO', resume?.summary),
          
          // Educação (Formação)
          _buildSection('EDUCAÇÃO', null, 
            customContent: Column(
              children: (resume?.education ?? []).map((edu) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Text(
                      edu.degree,
                      style: GoogleFonts.arimo(fontSize: 14, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      edu.institution,
                      style: GoogleFonts.arimo(fontSize: 13, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${edu.period}${edu.details.isNotEmpty ? ' • ${edu.details}' : ''}',
                      style: GoogleFonts.arimo(fontSize: 12, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )).toList(),
            )
          ),

          // Experiência
          _buildSection('EXPERIÊNCIA', null, 
            customContent: Column(
              children: (resume?.experiences ?? []).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    Text(
                      e.role,
                      style: GoogleFonts.arimo(fontSize: 14, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      e.company,
                      style: GoogleFonts.arimo(fontSize: 13, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      e.description,
                      style: GoogleFonts.arimo(fontSize: 12, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )).toList(),
            )
          ),

          // Habilidades
          _buildSection('HABILIDADES', null, 
            customContent: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: (resume?.skills ?? []).map((s) => Text(
                '• $s',
                style: GoogleFonts.arimo(fontSize: 12),
              )).toList(),
            )
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String? content, {Widget? customContent}) {
    if ((content == null || content.isEmpty) && customContent == null) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        children: [
          Text(
            title,
            style: GoogleFonts.arimo(
              fontSize: 14, 
              fontWeight: FontWeight.bold, 
              letterSpacing: 1.5,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          if (content != null)
            Text(
              content, 
              textAlign: TextAlign.center, 
              style: GoogleFonts.arimo(fontSize: 12, height: 1.6, color: Colors.black87)
            ),
          if (customContent != null) customContent,
        ],
      ),
    );
  }
}

// --- 3. Modern Template (O Favorito das Startups) ---
class ModernResumeTemplate extends ResumeTemplate {
  const ModernResumeTemplate({super.key, required super.user, required super.resume});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Esquerda (Coluna menor - 30%)
            Expanded(
              flex: 3,
              child: Container(
                color: const Color(0xFFF3F4F6), // Light grey background for sidebar
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Foto (Placeholder icon)
                    Center(
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: const Color(0xFF1F2937),
                        child: Text(
                          user?.name.substring(0, 1).toUpperCase() ?? 'U',
                          style: const TextStyle(color: Colors.white, fontSize: 24),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    // Contato
                    _buildSidebarTitle('CONTATO'),
                    _buildContactItem(Icons.email, user?.email ?? ''),
                    _buildContactItem(Icons.school, user?.course ?? ''),
                    
                    const SizedBox(height: 30),
                    
                    // Habilidades
                    _buildSidebarTitle('HABILIDADES'),
                    ...(resume?.skills ?? []).map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        s, 
                        style: GoogleFonts.lato(color: const Color(0xFF374151), fontSize: 12)
                      ),
                    )),

                    const SizedBox(height: 30),

                    // Idiomas (Simulado com Interesses por enquanto)
                    if ((resume?.interests ?? []).isNotEmpty) ...[
                      _buildSidebarTitle('INTERESSES'),
                      ...(resume?.interests ?? []).map((i) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          i, 
                          style: GoogleFonts.lato(color: const Color(0xFF374151), fontSize: 12)
                        ),
                      )),
                    ]
                  ],
                ),
              ),
            ),
            
            // Direita (Coluna maior - 70%)
            Expanded(
              flex: 7,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name.toUpperCase() ?? 'NOME',
                      style: GoogleFonts.lato(
                        fontSize: 28, 
                        fontWeight: FontWeight.w900, 
                        color: const Color(0xFF111827) // Dark/Navy
                      ),
                    ),
                    Text(
                      user?.course ?? 'Curso',
                      style: GoogleFonts.lato(
                        fontSize: 16, 
                        color: const Color(0xFF0F766E), // Teal/Petrol Green
                        fontWeight: FontWeight.bold
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    _buildMainSection('SUMÁRIO', resume?.summary),
                    
                    _buildMainSection('FORMAÇÃO', null,
                      customContent: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: (resume?.education ?? []).map((edu) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                edu.degree, 
                                style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF111827))
                              ),
                              Text(
                                edu.institution, 
                                style: GoogleFonts.lato(color: const Color(0xFF0F766E), fontSize: 13, fontWeight: FontWeight.w600)
                              ),
                              Text(
                                '${edu.period}${edu.details.isNotEmpty ? ' • ${edu.details}' : ''}', 
                                style: GoogleFonts.lato(fontSize: 12, color: const Color(0xFF4B5563))
                              ),
                            ],
                          ),
                        )).toList(),
                      )
                    ),
                    
                    _buildMainSection('EXPERIÊNCIA', null, 
                      customContent: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: (resume?.experiences ?? []).map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.role, 
                                style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF111827))
                              ),
                              Text(
                                e.company, 
                                style: GoogleFonts.lato(color: const Color(0xFF0F766E), fontSize: 13, fontWeight: FontWeight.w600)
                              ),
                              const SizedBox(height: 4),
                              Text(
                                e.description, 
                                style: GoogleFonts.lato(fontSize: 13, color: const Color(0xFF4B5563), height: 1.4)
                              ),
                            ],
                          ),
                        )).toList(),
                      )
                    ),

                    _buildMainSection('PROJETOS', null,
                      customContent: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: (resume?.achievements ?? []).map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.arrow_right, color: Color(0xFF0F766E), size: 16),
                              Expanded(
                                child: Text(
                                  a,
                                  style: GoogleFonts.lato(fontSize: 13, color: const Color(0xFF4B5563)),
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      )
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.lato(
          color: const Color(0xFF111827), 
          fontSize: 12, 
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0
        ),
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF0F766E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text, 
              style: GoogleFonts.lato(fontSize: 11, color: const Color(0xFF374151))
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainSection(String title, String? content, {Widget? customContent}) {
    if ((content == null || content.isEmpty) && customContent == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title, 
            style: GoogleFonts.lato(
              fontSize: 14, 
              fontWeight: FontWeight.bold, 
              color: const Color(0xFF111827),
              letterSpacing: 0.5
            )
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            height: 2,
            width: 40,
            color: const Color(0xFF0F766E),
          ),
          if (content != null) 
            Text(
              content, 
              style: GoogleFonts.lato(fontSize: 13, color: const Color(0xFF4B5563), height: 1.5)
            ),
          if (customContent != null) customContent,
        ],
      ),
    );
  }
}

// --- 4. Creative Template (O Visual Impactante) ---
class CreativeResumeTemplate extends ResumeTemplate {
  const CreativeResumeTemplate({super.key, required super.user, required super.resume});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Column(
        children: [
          // Cabeçalho Grande e Colorido
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            decoration: const BoxDecoration(
              color: Color(0xFF6366F1), // Vivid Indigo
              borderRadius: BorderRadius.only(bottomRight: Radius.circular(80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.name ?? 'Nome',
                  style: GoogleFonts.poppins(
                    fontSize: 36, 
                    fontWeight: FontWeight.w900, 
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                Text(
                  user?.course ?? 'Curso',
                  style: GoogleFonts.poppins(
                    fontSize: 18, 
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Projetos / Portfólio (Destaque)
                if ((resume?.achievements ?? []).isNotEmpty) ...[
                  _buildSection('PROJETOS DESTAQUE', null, 
                    color: const Color(0xFF6366F1),
                    customContent: Column(
                      children: (resume?.achievements ?? []).map((a) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFC7D2FE)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.rocket_launch, color: Color(0xFF6366F1), size: 20),
                            const SizedBox(width: 12),
                            Expanded(child: Text(a, style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF4338CA)))),
                          ],
                        ),
                      )).toList(),
                    )
                  ),
                  const SizedBox(height: 24),
                ],

                // Barras de Skill (Visual Impactante)
                _buildSection('COMPETÊNCIAS', null, 
                  color: const Color(0xFFEC4899), // Pink for contrast
                  customContent: Column(
                    children: (resume?.skills ?? []).map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(s, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          Expanded(
                            flex: 4,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: 0.85, // Mocked high proficiency
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEC4899),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )).toList(),
                  )
                ),
                const SizedBox(height: 24),

                // Experiência
                _buildSection('EXPERIÊNCIA', null, 
                  color: const Color(0xFF6366F1),
                  customContent: Column(
                    children: (resume?.experiences ?? []).map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6366F1),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.role, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text(e.company, style: GoogleFonts.poppins(color: const Color(0xFF6366F1), fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(e.description, style: GoogleFonts.poppins(color: Colors.grey[700], fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )).toList(),
                  )
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String? content, {required Color color, Widget? customContent}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title, 
          style: GoogleFonts.poppins(
            fontSize: 20, 
            fontWeight: FontWeight.w900, 
            color: color,
            letterSpacing: -0.5,
          )
        ),
        const SizedBox(height: 12),
        if (content != null) 
          Text(content, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800])),
        if (customContent != null) customContent,
      ],
    );
  }
}

// --- 5. Executive Template (Estilo Harvard/Consultoria) ---
class ExecutiveResumeTemplate extends ResumeTemplate {
  const ExecutiveResumeTemplate({super.key, required super.user, required super.resume});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48), // Margens generosas
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho Sóbrio
          Center(
            child: Column(
              children: [
                Text(
                  user?.name.toUpperCase() ?? 'NOME',
                  style: GoogleFonts.merriweather( // Serif
                    fontSize: 24, 
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${user?.email ?? ""} • ${user?.course ?? ""}',
                  style: GoogleFonts.merriweather(
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(thickness: 1, color: Colors.black),
          const SizedBox(height: 24),

          // Resumo (Bullet Points de Resultados)
          _buildSection('SUMÁRIO', resume?.summary),

          // Experiência
          _buildSection('EXPERIÊNCIA PROFISSIONAL', null, 
            customContent: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: (resume?.experiences ?? []).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          e.role, 
                          style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 14)
                        ),
                        Text(
                          e.period, 
                          style: GoogleFonts.merriweather(fontStyle: FontStyle.italic, fontSize: 12)
                        ),
                      ],
                    ),
                    Text(
                      e.company, 
                      style: GoogleFonts.merriweather(fontSize: 13)
                    ),
                    const SizedBox(height: 4),
                    // Transformar descrição em bullet point se possível, ou apenas justificar
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontSize: 14)),
                        Expanded(
                          child: Text(
                            e.description, 
                            style: GoogleFonts.merriweather(fontSize: 12, height: 1.4),
                            textAlign: TextAlign.justify,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )).toList(),
            )
          ),

          // Formação
          _buildSection('FORMAÇÃO ACADÊMICA', null, 
            customContent: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: (resume?.education ?? []).map((edu) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      edu.degree.toUpperCase(),
                      style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Text(
                      edu.institution,
                      style: GoogleFonts.merriweather(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                    Text(
                      '${edu.period}${edu.details.isNotEmpty ? ' • ${edu.details}' : ''}',
                      style: GoogleFonts.merriweather(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              )).toList(),
            )
          ),

          // Habilidades e Interesses (Compacto)
          _buildSection('HABILIDADES & INTERESSES', null,
            customContent: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((resume?.skills ?? []).isNotEmpty)
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.merriweather(fontSize: 12, color: Colors.black, height: 1.4),
                      children: [
                        const TextSpan(text: 'Habilidades: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: (resume?.skills ?? []).join(', ') + '.'),
                      ],
                    ),
                  ),
                if ((resume?.interests ?? []).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.merriweather(fontSize: 12, color: Colors.black, height: 1.4),
                        children: [
                          const TextSpan(text: 'Interesses: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(text: (resume?.interests ?? []).join(', ') + '.'),
                        ],
                      ),
                    ),
                  ),
              ],
            )
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String? content, {Widget? customContent}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(), 
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.bold, 
              fontSize: 13, 
              decoration: TextDecoration.underline
            )
          ),
          const SizedBox(height: 8),
          if (content != null) 
            Text(
              content, 
              style: GoogleFonts.merriweather(fontSize: 12, height: 1.4),
              textAlign: TextAlign.justify,
            ),
          if (customContent != null) customContent,
        ],
      ),
    );
  }
}

// --- 6. Quick CV Template (Maya Davis Style) ---
// --- 6. Quick CV Template (Matching PDF Layout) ---
class QuickCvResumeTemplate extends ResumeTemplate {
  const QuickCvResumeTemplate({super.key, required super.user, required super.resume});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF355C7D);
    const accentColor = Color(0xFFDCE4E8);
    const subTextColor = Color(0xFF7A7E83);

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(32),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header
          Text(
            user?.name ?? 'Seu Nome',
            style: GoogleFonts.lato(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.course ?? 'Curso',
            style: GoogleFonts.lato(
              fontSize: 18,
              fontStyle: FontStyle.italic,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _buildContactItem(Icons.email, user?.email ?? 'email@exemplo.com'),
              _buildContactItem(Icons.phone, resume?.phone ?? '(99) 99999-9999'),
              _buildContactItem(Icons.link, resume?.linkedin.replaceAll('https://', '') ?? 'linkedin.com/in/usuario'),
              _buildContactItem(Icons.location_on, resume?.location ?? 'Cidade - UF'),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: primaryColor, thickness: 2),
          const SizedBox(height: 20),

          // Two Column Layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column (Main Content)
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary
                      if ((resume?.summary ?? '').isNotEmpty) ...[
                        _buildSectionHeader(Icons.person, 'SUMÁRIO'),
                        const SizedBox(height: 8),
                        Text(
                          resume?.summary ?? '',
                          style: GoogleFonts.lato(fontSize: 13, color: const Color(0xFF343B41), height: 1.4),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Education (From Left)
                      if ((resume?.education ?? []).isNotEmpty) ...[
                         _buildSectionHeader(Icons.school, 'FORMAÇÃO'),
                         ...(resume?.education ?? []).map((edu) => Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(edu.degree, style: _headerStyle()),
                              Text(edu.institution, style: _subHeaderStyle()),
                              Text(edu.period, style: _dateStyle()),
                              if (edu.details.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(edu.details, style: _bodyStyle()),
                              ]
                            ],
                          ),
                        )),
                        const SizedBox(height: 24),
                      ],

                      // Experience
                      if ((resume?.experiences ?? []).isNotEmpty) ...[
                         _buildSectionHeader(Icons.work, 'EXPERIÊNCIA PROFISSIONAL'),
                         ...(resume?.experiences ?? []).map((exp) => Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(exp.role, style: _headerStyle()),
                              Text(exp.company, style: _subHeaderStyle()),
                              Text(exp.period, style: _dateStyle()),
                              if (exp.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(exp.description, style: _bodyStyle()),
                              ]
                            ],
                          ),
                        )),
                        const SizedBox(height: 24),
                      ],

                      // Academic Projects
                      if ((resume?.academicProjects ?? []).isNotEmpty) ...[
                        _buildSectionHeader(Icons.folder_open, 'PROJETOS'),
                        ...(resume?.academicProjects ?? []).map((proj) => Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(proj.title, style: _headerStyle()),
                              Text(proj.role, style: _subHeaderStyle()),
                              Text(proj.description, style: _bodyStyle()),
                            ],
                          ),
                        )),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
              ),

              // Right Column (Skills & Extra)
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.only(left: 24),
                  decoration: const BoxDecoration(
                     border: Border(left: BorderSide(color: Color(0xFFE5E7EB), width: 1))
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Skills
                      if ((resume?.skills ?? []).isNotEmpty) ...[
                        _buildSectionHeader(Icons.psychology, 'HABILIDADES'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: (resume?.skills ?? []).map((skill) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: accentColor, // Light blue-grey
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              skill,
                              style: GoogleFonts.lato(fontSize: 11, color: const Color(0xFF343B41), fontWeight: FontWeight.w600),
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 32),
                      ],

                      // Courses
                      if ((resume?.courses ?? []).isNotEmpty) ...[
                        _buildSectionHeader(Icons.library_books, 'CURSOS E CERTIFICAÇÕES'),
                        const SizedBox(height: 8),
                        ...(resume?.courses ?? []).map((course) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(course.title, style: _headerStyle(fontSize: 12)),
                              Text(course.institution, style: _subHeaderStyle(fontSize: 12)),
                              Text(course.period, style: _dateStyle(fontSize: 11)),
                            ],
                          ),
                        )),
                        const SizedBox(height: 32),
                      ],

                       // Languages
                      if ((resume?.languages ?? []).isNotEmpty) ...[
                        _buildSectionHeader(Icons.language, 'IDIOMAS'),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: (resume?.languages ?? []).map((lang) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('${lang.language} - ${lang.level}', style: GoogleFonts.lato(fontSize: 12, color: const Color(0xFF343B41))),
                          )).toList(),
                        ),
                        const SizedBox(height: 32),
                      ],

                      // Awards
                      if ((resume?.awards ?? []).isNotEmpty) ...[
                        _buildSectionHeader(Icons.emoji_events, 'PREMIAÇÕES'),
                        const SizedBox(height: 8),
                        ...(resume?.awards ?? []).map((award) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(award.title, style: GoogleFonts.lato(fontSize: 12, color: const Color(0xFF343B41))),
                        )),
                      ],

                      // Interests
                      if ((resume?.interests ?? []).isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildSectionHeader(Icons.interests, 'INTERESSES'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: (resume?.interests ?? []).map((interest) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0E0E0),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                interest,
                                style: _bodyStyle().copyWith(fontSize: 10),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
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

  Widget _buildContactItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF355C7D)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: GoogleFonts.lato(fontSize: 12, color: const Color(0xFF13191D)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.grey[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.lato(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF355C7D),
                  letterSpacing: 0.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(width: double.infinity, height: 1.5, color: const Color(0xFF355C7D)),
      ],
    );
  }

  TextStyle _headerStyle({double fontSize = 14}) {
    return GoogleFonts.lato(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      color: const Color(0xFF343B41),
    );
  }

  TextStyle _subHeaderStyle({double fontSize = 13}) {
    return GoogleFonts.lato(
      fontSize: fontSize,
      fontStyle: FontStyle.italic,
      color: const Color(0xFF7A7E83),
    );
  }

  TextStyle _dateStyle({double fontSize = 12}) {
    return GoogleFonts.lato(
      fontSize: fontSize,
      fontStyle: FontStyle.italic,
      color: const Color(0xFF7A7E83),
    );
  }

  TextStyle _bodyStyle() {
    return GoogleFonts.lato(
      fontSize: 12,
      color: const Color(0xFF343B41),
      height: 1.4,
    );
  }
}

// --- 7. Harvard ATS Brasil Template (MCS Style) ---
class HarvardAtsBrasilTemplate extends ResumeTemplate {
  const HarvardAtsBrasilTemplate({super.key, required super.user, required super.resume});

  String get _lang => resume?.language ?? 'pt';

  static const _ptLabels = {
    'summary': 'Sumário',
    'education': 'Educação',
    'experience': 'Experiência Profissional',
    'leadership': 'Atividades Extracurriculares',
    'skills_section': 'Habilidades, Certificações & Programas',
    'technical_skills': 'Habilidades Técnicas',
    'languages': 'Idiomas',
    'tools': 'Ferramentas',
    'certifications': 'Certificações & Programas',
    'interests': 'Interesses',
    'mobile': 'Mobile',
    'edu_coursework': 'Disciplinas relevantes',
    'edu_gpa': 'CR',
    'edu_honors': 'Honras & Distinção Acadêmica',
    'edu_rep_role': 'Cargo representativo',
    'relevant_work': 'Trabalho Relevante',
  };
  static const _enLabels = {
    'summary': 'Summary',
    'education': 'Education',
    'experience': 'Professional Experience',
    'leadership': 'Extracurricular Activities',
    'skills_section': 'Skills, Certifications & Programs',
    'technical_skills': 'Technical Skills',
    'languages': 'Languages',
    'tools': 'Tools',
    'certifications': 'Certifications & Programs',
    'interests': 'Interests',
    'mobile': 'Mobile',
    'edu_coursework': 'Relevant Coursework',
    'edu_gpa': 'GPA',
    'edu_honors': 'Honors & Academic Distinction',
    'edu_rep_role': 'Representative Role',
    'relevant_work': 'Relevant Work',
  };

  String _t(String key) => (_lang == 'en' ? _enLabels[key] : _ptLabels[key]) ?? key;

  @override
  Widget build(BuildContext context) {
    if (resume == null) return const SizedBox.shrink();

    // Font style — Times New Roman to match the PDF Harvard ATS template
    final textStyle = GoogleFonts.tinos(color: Colors.black);
    final addressLine = resume!.address.trim();

    // The preview is rendered inside a 794×1123 container (A4 @ 96 DPI) with
    // an outer 32px wrapper applied by resume_tab.dart. We compensate so the
    // total margins match the PDF's `@page { margin: 0.4in 0.45in }`:
    //   horizontal: 32 (wrapper) + 11 (here) = 43px ≈ 0.45in
    //   vertical:   32 (wrapper) +  6 (here) = 38px ≈ 0.40in
    // Font sizes are scaled ~1.33× from PDF pt values so 11pt → 15 logical
    // pixels, visually matching the rendered PDF at this preview scale.
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — Harvard MCS style: name in CAPS, optional address line,
          // contact line with pipes and "Mobile:" prefix.
          Center(
            child: Column(
              children: [
                Text(
                  (user?.name ?? 'Seu Nome').toUpperCase(),
                  style: textStyle.copyWith(
                    fontSize: 23, // 17pt × 1.333
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                if (addressLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      addressLine,
                      if (resume!.location.trim().isNotEmpty) resume!.location.trim(),
                    ].join(' – '),
                    style: textStyle.copyWith(fontSize: 13), // 9.5pt × 1.333
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 1),
                Text(
                  _buildContactString(),
                  style: textStyle.copyWith(fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4), // .header margin-bottom 3pt × 1.333 ≈ 4

          // Sumário
          if (resume!.summary.trim().isNotEmpty) ...[
            _buildCenteredTitle(_t('summary'), textStyle),
            Text(
              resume!.summary.trim(),
              style: textStyle.copyWith(fontSize: 15, height: 1.15), // 11pt × 1.333
            ),
            const SizedBox(height: 5), // .entry margin-bottom 4pt × 1.333
          ],

          // Experiência Profissional
          if (resume!.experiences.isNotEmpty) ...[
            _buildCenteredTitle(_t('experience'), textStyle),
            ...resume!.experiences.map((exp) => _buildExperienceItem(exp, textStyle)),
          ],

          // Educação
          if (resume!.education.isNotEmpty) ...[
            _buildCenteredTitle(_t('education'), textStyle),
            ...resume!.education.map((edu) => _buildEducationItem(edu, textStyle)),
          ],

          // Atividades Extracurriculares
          if (resume!.academicProjects.isNotEmpty || resume!.leadership.isNotEmpty) ...[
            _buildCenteredTitle(_t('leadership'), textStyle),
            ...resume!.academicProjects.map((p) => _buildProjectItem(p, textStyle)),
            ...resume!.leadership.map((l) => _buildLeadershipItem(l, textStyle)),
          ],

          // Habilidades, Certificações & Programas
          _buildCenteredTitle(_t('skills_section'), textStyle),
          _buildSkillsSection(textStyle),

          // Interesses (seção separada no fim)
          if (resume!.interests.isNotEmpty) ...[
            _buildCenteredTitle(_t('interests'), textStyle),
            RichText(
              text: TextSpan(
                style: textStyle.copyWith(fontSize: 15, height: 1.15),
                children: [
                  TextSpan(
                    text: '${_t('interests')}: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: resume!.interests.join(', ')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCenteredTitle(String title, TextStyle style) {
    // PDF: .sec { margin: 5pt 0 0; padding-bottom: 1pt; border-bottom: 0.5pt; font-size: 11pt }
    //      .sec + * { margin-top: 2pt }
    // × 1.333 → top: 7, between text and line: 1, after line: 3
    return Padding(
      padding: const EdgeInsets.only(top: 7, bottom: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: style.copyWith(
              fontSize: 15, // 11pt × 1.333
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 1),
          const Divider(height: 0.5, thickness: 0.5, color: Colors.black),
        ],
      ),
    );
  }

  String _buildContactString() {
    final parts = <String>[];
    // If a full address line is shown above, the city is already there —
    // skip it from the contact line to avoid duplication.
    final hasAddressLine = resume?.address.trim().isNotEmpty == true;
    if (!hasAddressLine && resume?.location.isNotEmpty == true) {
      parts.add(resume!.location);
    }
    if (resume?.phone.isNotEmpty == true) parts.add('${_t('mobile')}: ${resume!.phone}');
    if (resume?.email.isNotEmpty == true) parts.add(resume!.email);
    if (resume?.linkedin.isNotEmpty == true) {
      parts.add(resume!.linkedin
          .replaceAll('https://', '')
          .replaceAll('http://', '')
          .replaceAll('www.', ''));
    }
    return parts.join(' | ');
  }

  Widget _buildEducationItem(EducationItem edu, TextStyle style) {
    final location = edu.location.isNotEmpty ? edu.location : (resume?.location ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 5), // .entry margin-bottom 4pt × 1.333
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                edu.institution,
                style: style.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                location,
                style: style.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                edu.degree,
                style: style.copyWith(fontSize: 15, fontStyle: FontStyle.italic),
              ),
              Text(
                edu.period,
                style: style.copyWith(fontSize: 15),
              ),
            ],
          ),
          if (edu.details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                edu.details,
                style: style.copyWith(fontSize: 13), // 9.5pt × 1.333
              ),
            ),
          // Harvard enrichments — render as labelled bullet rows
          if (edu.coursework.isNotEmpty)
            _buildEducationHighlightRow(_t('edu_coursework'), edu.coursework, style),
          if (edu.gpa.isNotEmpty)
            _buildEducationHighlightRow(_t('edu_gpa'), edu.gpa, style),
          if (edu.honors.isNotEmpty)
            _buildEducationHighlightRow(_t('edu_honors'), edu.honors, style),
          if (edu.repRole.isNotEmpty)
            _buildEducationHighlightRow(_t('edu_rep_role'), edu.repRole, style),
        ],
      ),
    );
  }

  Widget _buildEducationHighlightRow(String label, String value, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: RichText(
        text: TextSpan(
          style: style.copyWith(fontSize: 15, color: Colors.black),
          children: [
            const TextSpan(text: '• '),
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildExperienceItem(ExperienceItem exp, TextStyle style) {
    final location = exp.location.isNotEmpty ? exp.location : (resume?.location ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                exp.company,
                style: style.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                location,
                style: style.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                exp.role,
                style: style.copyWith(fontSize: 15, fontStyle: FontStyle.italic),
              ),
              Text(
                exp.period,
                style: style.copyWith(fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildBulletsFromDescription(exp.description, style),
        ],
      ),
    );
  }

  Widget _buildProjectItem(ResumeProject proj, TextStyle style) {
    final location = proj.location.isNotEmpty ? proj.location : (resume?.location ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Title (bold) + Location (right)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                proj.title,
                style: style.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                location,
                style: style.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          // Bottom row: Role (italic) + Period (regular)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                proj.role,
                style: style.copyWith(fontSize: 15, fontStyle: FontStyle.italic),
              ),
              Text(
                proj.period,
                style: style.copyWith(fontSize: 15),
              ),
            ],
          ),
          if (proj.relevantWork.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 1),
              child: RichText(
                text: TextSpan(
                  style: style.copyWith(fontSize: 15),
                  children: [
                    TextSpan(
                      text: '${_t('relevant_work')}: ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: proj.relevantWork.trim()),
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: 2),
          _buildBulletsFromDescription(proj.description, style),
        ],
      ),
    );
  }

  Widget _buildLeadershipItem(ResumeLeadership lead, TextStyle style) {
    final location = lead.location.isNotEmpty ? lead.location : (resume?.location ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Organization (bold) + Location (right)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                lead.organization,
                style: style.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                location,
                style: style.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          // Bottom row: Role (italic) + Period (regular)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                lead.role,
                style: style.copyWith(fontSize: 15, fontStyle: FontStyle.italic),
              ),
              Text(
                lead.period,
                style: style.copyWith(fontSize: 15),
              ),
            ],
          ),
          if (lead.relevantWork.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 1),
              child: RichText(
                text: TextSpan(
                  style: style.copyWith(fontSize: 15),
                  children: [
                    TextSpan(
                      text: '${_t('relevant_work')}: ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: lead.relevantWork.trim()),
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: 2),
          _buildBulletsFromDescription(lead.description, style),
        ],
      ),
    );
  }

  Widget _buildSkillsSection(TextStyle style) {
    // Group languages and tools by level (Harvard-style sentences)
    final isEn = _lang == 'en';
    String joinList(List<String> items) {
      final conj = isEn ? 'and' : 'e';
      if (items.isEmpty) return '';
      if (items.length == 1) return items[0];
      if (items.length == 2) return '${items[0]} $conj ${items[1]}';
      return '${items.sublist(0, items.length - 1).join(', ')} $conj ${items.last}';
    }

    String groupLanguages(List<ResumeLanguage> langs) {
      const order = ['Nativo', 'Fluente', 'Avançado', 'Intermediário', 'Básico'];
      const enLabels = {
        'Nativo': 'Native',
        'Fluente': 'Fluent',
        'Avançado': 'Advanced',
        'Intermediário': 'Intermediate',
        'Básico': 'Basic',
      };
      final preposition = isEn ? 'in' : 'em';
      final byLevel = <String, List<String>>{};
      for (final l in langs) {
        final level = l.level.trim().isEmpty ? 'Outro' : l.level.trim();
        byLevel.putIfAbsent(level, () => []).add(l.language);
      }
      final parts = <String>[];
      for (final level in order) {
        final list = byLevel.remove(level);
        if (list != null && list.isNotEmpty) {
          final label = isEn ? (enLabels[level] ?? level) : level;
          parts.add('$label $preposition ${joinList(list)}');
        }
      }
      byLevel.forEach((level, list) {
        parts.add('$level $preposition ${joinList(list)}');
      });
      return parts.join('; ');
    }

    String groupTools(List<ToolWithLevel> tools) {
      const order = ['Avançado', 'Intermediário', 'Básico'];
      final byLevel = <String, List<String>>{};
      for (final t in tools) {
        final level = t.level.trim().isEmpty ? '' : t.level.trim();
        byLevel.putIfAbsent(level, () => []).add(t.name);
      }
      final parts = <String>[];
      for (final level in order) {
        final list = byLevel.remove(level);
        if (list != null && list.isNotEmpty) parts.add('$level: ${list.join(', ')}');
      }
      final un = byLevel.remove('');
      if (un != null && un.isNotEmpty) parts.add(un.join(', '));
      byLevel.forEach((level, list) => parts.add('$level: ${list.join(', ')}'));
      return parts.join('; ');
    }

    List<String> certificationItems(List<ResumeCourse> courses) =>
        courses.map((c) {
          final parts = <String>[c.title];
          if (c.institution.isNotEmpty) parts.add(c.institution);
          var s = parts.join(' - ');
          if (c.period.isNotEmpty) s = '$s (${c.period})';
          if (!s.trimRight().endsWith('.')) s = '$s.';
          return s;
        }).toList();

    String withDot(String s) => s.trimRight().endsWith('.') ? s : '$s.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (resume!.skills.isNotEmpty)
          _buildSkillCategory(_t('technical_skills'), withDot(resume!.skills.join(', ')), style),
        if (resume!.languages.isNotEmpty)
          _buildSkillCategory(_t('languages'), withDot(groupLanguages(resume!.languages)), style),
        if (resume!.toolsText.trim().isNotEmpty)
          _buildSkillCategory(_t('tools'), withDot(resume!.toolsText.trim()), style)
        else if (resume!.tools.isNotEmpty)
          _buildSkillCategory(_t('tools'), withDot(groupTools(resume!.tools)), style),
        if (resume!.courses.isNotEmpty)
          _buildSkillBulletList(_t('certifications'), certificationItems(resume!.courses), style),
      ],
    );
  }

  Widget _buildSkillBulletList(String label, List<String> items, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label:',
            style: style.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(top: 1),
                child: RichText(
                  text: TextSpan(
                    style: style.copyWith(fontSize: 15),
                    children: [
                      const TextSpan(text: '• '),
                      TextSpan(text: item),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  static String _joinPt(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items[0];
    if (items.length == 2) return '${items[0]} e ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')} e ${items.last}';
  }

  Widget _buildSkillCategory(String label, String content, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: style.copyWith(fontSize: 15, color: Colors.black),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: content),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletsFromDescription(String description, TextStyle style) {
    final lines = description.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return Column(
      children: lines.map((line) {
        final cleanLine = line.replaceAll('•', '').trim();
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: RichText(
            text: TextSpan(
              style: style.copyWith(fontSize: 15),
              children: [
                const TextSpan(text: '• '),
                TextSpan(text: cleanLine),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
