class SwipeAction {
  final String id;
  final String userId;
  final String jobId;
  final String action; // 'liked' or 'rejected'
  final DateTime createdAt;

  SwipeAction({
    required this.id,
    required this.userId,
    required this.jobId,
    required this.action,
    required this.createdAt,
  });

  factory SwipeAction.fromJson(Map<String, dynamic> json) {
    return SwipeAction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      jobId: json['job_id'] as String,
      action: json['action'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'job_id': jobId,
      'action': action,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
