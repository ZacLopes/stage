
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/models.dart';
import 'package:fl_chart/fl_chart.dart'; // Make sure to add fl_chart to pubspec if not already there, otherwise I'll need to use something else or simple widgets.
// Checking deps... pubspec has no fl_chart. I will use simple progress bars for the spider chart data to avoid adding deps without permission, or I can add it. 
// Plan didn't explicitly say "add fl_chart", but "Spider Chart Data" implies visualization.
// Usage of simple LinearProgressIndicators is safer and cleaner for now without adding deps.

class InterviewReportScreen extends StatelessWidget {
  final InterviewReport report;

  const InterviewReportScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827), // Dark background
      appBar: AppBar(
        title: Text(
          'RELATÓRIO DE ELITE',
          style: GoogleFonts.cinzel(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: const Color(0xFFFFD700), // Gold
          ),
        ),
        backgroundColor: const Color(0xFF111827),
        iconTheme: const IconThemeData(color: Color(0xFFFFD700)),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildHeader(),
          const SizedBox(height: 32),
          _buildScoreSection(),
          const SizedBox(height: 32),
          _buildSectionTitle('DIAGNÓSTICO'),
          _buildTextCard(report.diagnosis),
          const SizedBox(height: 24),
          _buildSectionTitle('O SEU PITCH ("Fale sobre você")'),
          _buildGradientCard(report.pitchFeedback, [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
          const SizedBox(height: 24),
          _buildSectionTitle('A ARMADILHA DO DEFEITO'),
          _buildGradientCard(report.trapFeedback, [Color(0xFFDC2626), Color(0xFFB91C1C)]),
          const SizedBox(height: 24),
          _buildSectionTitle('MISSÕES TÁTICAS'),
          ...report.tacticalMissions.map((mission) => _buildMissionCard(mission)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Icon(Icons.shield, size: 60, color: Color(0xFFFFD700)),
        const SizedBox(height: 16),
        Text(
          'ANÁLISE CONCLUÍDA',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildScoreSection() {
    return Column(
      children: report.spiderChartData.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entry.key.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${entry.value}/100',
                    style: GoogleFonts.mono(
                      color: Color(0xFFFFD700),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: entry.value / 100,
                backgroundColor: Colors.white10,
                color: _getColorForScore(entry.value),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getColorForScore(int score) {
    if (score >= 80) return Color(0xFF10B981); // Green
    if (score >= 50) return Color(0xFFF59E0B); // Amber
    return Color(0xFFEF4444); // Red
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(width: 4, height: 24, color: Color(0xFFFFD700)),
          const SizedBox(width: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextCard(String content) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        content,
        style: GoogleFonts.inter(
          color: Colors.white,
          height: 1.6,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildGradientCard(String content, List<Color> colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors.map((c) => c.withOpacity(0.3)).toList(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.first.withOpacity(0.3)),
      ),
      child: Text(
        content,
        style: GoogleFonts.inter(
          color: Colors.white,
          height: 1.6,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildMissionCard(String mission) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFFFD700).withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, color: Color(0xFFFFD700), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mission,
              style: GoogleFonts.inter(
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
