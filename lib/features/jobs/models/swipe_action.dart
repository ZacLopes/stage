class SwipeAction {
  final String id;
  final String userId;
  final String jobId;
  final String action; // 'liked' or 'rejected'
  final DateTime createdAt;
  final bool applied;
  final DateTime? appliedAt;

  SwipeAction({
    required this.id,
    required this.userId,
    required this.jobId,
    required this.action,
    required this.createdAt,
    this.applied = false,
    this.appliedAt,
  });

  factory SwipeAction.fromJson(Map<String, dynamic> json) {
    return SwipeAction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      jobId: json['job_id'] as String,
      action: json['action'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      applied: json['applied'] == true,
      appliedAt: json['applied_at'] != null
          ? DateTime.tryParse(json['applied_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'job_id': jobId,
      'action': action,
      'created_at': createdAt.toIso8601String(),
      'applied': applied,
      'applied_at': appliedAt?.toIso8601String(),
    };
  }
}
