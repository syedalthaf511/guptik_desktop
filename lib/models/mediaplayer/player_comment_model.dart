import 'dart:convert';

/// PlayerComment — Advanced Comment System Model
/// Supports nested replies, reactions (like/heart/clap/etc.),
/// editing, deletion (soft), and reporting/moderation.
class PlayerComment {
  final String commentId;
  final String videoId;
  final String creatorUid;      // The user who wrote the comment
  final String creatorName;     // Display name of commenter
  final String commentText;
  final String createdAt;
  final String? editedAt;
  final String? parentCommentId; // null for top-level comments
  final int likesCount;
  final int heartCount;
  final int clapCount;
  final int laughCount;
  final int disagreeCount;
  final bool isDeleted;
  final bool isEdited;
  final bool isReported;
  final String? reportReason;
  final bool isIncognito;
  final String? viewerReaction; // The current viewer's reaction type (null if none)

  // Nested replies are populated when fetching a top-level comment
  final List<PlayerComment> replies;

  PlayerComment({
    required this.commentId,
    required this.videoId,
    required this.creatorUid,
    required this.creatorName,
    required this.commentText,
    required this.createdAt,
    this.editedAt,
    this.parentCommentId,
    this.likesCount = 0,
    this.heartCount = 0,
    this.clapCount = 0,
    this.laughCount = 0,
    this.disagreeCount = 0,
    this.isDeleted = false,
    this.isEdited = false,
    this.isReported = false,
    this.reportReason,
    this.isIncognito = false,
    this.viewerReaction,
    this.replies = const [],
  });

  /// Total reaction count for convenience
  int get totalReactions =>
      likesCount + heartCount + clapCount + laughCount + disagreeCount;

  factory PlayerComment.fromJson(Map<String, dynamic> json) {
    final rawReplies = json['replies'];
    List<PlayerComment> parsedReplies = [];
    if (rawReplies is List) {
      parsedReplies = rawReplies
          .map((r) => PlayerComment.fromJson(r as Map<String, dynamic>))
          .toList();
    } else if (rawReplies is String && rawReplies.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawReplies);
        if (decoded is List) {
          parsedReplies = decoded
              .map((r) => PlayerComment.fromJson(r as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }

    return PlayerComment(
      commentId: json['comment_id']?.toString() ?? json['id']?.toString() ?? '',
      videoId: json['video_id']?.toString() ?? '',
      creatorUid: json['creator_uid']?.toString() ?? json['user_id']?.toString() ?? '',
      creatorName: json['creator_name']?.toString() ??
          json['channel_name']?.toString() ??
          json['username']?.toString() ??
          'Anonymous',
      commentText: json['comment_text']?.toString() ?? json['content']?.toString() ?? '',
      createdAt: json['comment_timestamp']?.toString() ??
          json['created_at']?.toString() ??
          '',
      editedAt: json['edited_at']?.toString(),
      parentCommentId: json['parent_comment_id']?.toString(),
      likesCount: json['likes_on_comment_local'] ?? json['likes_count'] ?? 0,
      heartCount: json['reaction_heart'] ?? json['heart_count'] ?? 0,
      clapCount: json['reaction_clap'] ?? json['clap_count'] ?? 0,
      laughCount: json['reaction_laugh'] ?? json['laugh_count'] ?? 0,
      disagreeCount: json['reaction_disagree'] ?? json['disagree_count'] ?? 0,
      isDeleted: json['is_deleted'] ?? false,
      isEdited: json['is_edited'] ?? (json['edited_at'] != null),
      isReported: json['is_reported'] ?? false,
      reportReason: json['report_reason']?.toString(),
      isIncognito: json['is_incognito'] ?? false,
      viewerReaction: json['viewer_reaction']?.toString(),
      replies: parsedReplies,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'comment_id': commentId,
      'video_id': videoId,
      'creator_uid': creatorUid,
      'creator_name': creatorName,
      'comment_text': commentText,
      'comment_timestamp': createdAt,
      'edited_at': editedAt,
      'parent_comment_id': parentCommentId,
      'likes_on_comment_local': likesCount,
      'reaction_heart': heartCount,
      'reaction_clap': clapCount,
      'reaction_laugh': laughCount,
      'reaction_disagree': disagreeCount,
      'is_deleted': isDeleted,
      'is_edited': isEdited,
      'is_reported': isReported,
      'report_reason': reportReason,
      'is_incognito': isIncognito,
      'viewer_reaction': viewerReaction,
    };
  }

  /// Creates a copy of the comment with optionally updated fields.
  /// Useful for immutable state updates in the UI.
  PlayerComment copyWith({
    String? commentText,
    String? editedAt,
    int? likesCount,
    int? heartCount,
    int? clapCount,
    int? laughCount,
    int? disagreeCount,
    bool? isDeleted,
    bool? isEdited,
    bool? isReported,
    String? reportReason,
    String? viewerReaction,
    List<PlayerComment>? replies,
  }) {
    return PlayerComment(
      commentId: commentId,
      videoId: videoId,
      creatorUid: creatorUid,
      creatorName: creatorName,
      commentText: commentText ?? this.commentText,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      parentCommentId: parentCommentId,
      likesCount: likesCount ?? this.likesCount,
      heartCount: heartCount ?? this.heartCount,
      clapCount: clapCount ?? this.clapCount,
      laughCount: laughCount ?? this.laughCount,
      disagreeCount: disagreeCount ?? this.disagreeCount,
      isDeleted: isDeleted ?? this.isDeleted,
      isEdited: isEdited ?? this.isEdited,
      isReported: isReported ?? this.isReported,
      reportReason: reportReason ?? this.reportReason,
      isIncognito: isIncognito,
      viewerReaction: viewerReaction ?? this.viewerReaction,
      replies: replies ?? this.replies,
    );
  }
}