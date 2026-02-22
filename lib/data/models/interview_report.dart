
class InterviewReport {
  final Map<String, int> spiderChartData; // Confidence, Storytelling, Objectivity, Strategic Fit
  final String diagnosis;
  final String pitchFeedback;
  final String trapFeedback;
  final List<String> tacticalMissions;

  InterviewReport({
    required this.spiderChartData,
    required this.diagnosis,
    required this.pitchFeedback,
    required this.trapFeedback,
    required this.tacticalMissions,
  });

  factory InterviewReport.fromJson(Map<String, dynamic> json) {
    return InterviewReport(
      spiderChartData: Map<String, int>.from(json['spider_chart'] ?? {}),
      diagnosis: json['diagnostico'] ?? '',
      pitchFeedback: json['pitch_feedback'] ?? '',
      trapFeedback: json['trap_feedback'] ?? '',
      tacticalMissions: List<String>.from(json['missoes_ta ticas'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'spider_chart': spiderChartData,
      'diagnostico': diagnosis,
      'pitch_feedback': pitchFeedback,
      'trap_feedback': trapFeedback,
      'missoes_ta ticas': tacticalMissions,
    };
  }
}
