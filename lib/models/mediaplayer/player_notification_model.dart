/// PlayerNotification — Social notification for comments, likes, reposts,
/// subscriptions, and supporter badges. Stored locally and synced to Supabase.
class PlayerNotification {
  final String notificationId;
  final String recipientUid;     // The user receiving the notification
  final String actorUid;         // The user who triggered the notification
  final String actorName;
  final String notificationType; // 'comment', 'like', 'repost', 'subscribe', 'badge', 'mention'
  final String? videoId;
  final String? videoTitle;
  final String? commentText;
  final String? badgeType;       // e.g. 'supporter', 'top_fan', 'milestone'
  final String createdAt;
  final bool isRead;

  PlayerNotification({
    required this.notificationId,
    required this.recipientUid,
    required this.actorUid,
    this.actorName = '',
    required this.notificationType,
    this.videoId,
    this.videoTitle,
    this.commentText,
    this.badgeType,
    required this.createdAt,
    this.isRead = false,
  });

  factory PlayerNotification.fromJson(Map<String, dynamic> json) {
    return PlayerNotification(
      notificationId: json['id']?.toString() ??
          json['notification_id']?.toString() ??
          '',
      recipientUid: json['recipient_uid']?.toString() ??
          json['user_id']?.toString() ??
          '',
      actorUid: json['actor_uid']?.toString() ?? '',
      actorName: json['actor_name']?.toString() ??
          json['channel_name']?.toString() ??
          '',
      notificationType: json['notification_type']?.toString() ??
          json['type']?.toString() ??
          'comment',
      videoId: json['video_id']?.toString(),
      videoTitle: json['video_title']?.toString(),
      commentText: json['comment_text']?.toString(),
      badgeType: json['badge_type']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      isRead: json['is_read'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': notificationId,
      'recipient_uid': recipientUid,
      'actor_uid': actorUid,
      'actor_name': actorName,
      'notification_type': notificationType,
      'video_id': videoId,
      'video_title': videoTitle,
      'comment_text': commentText,
      'badge_type': badgeType,
      'created_at': createdAt,
      'is_read': isRead,
    };
  }

  /// Human-readable message for the notification tile
  String get displayMessage {
    switch (notificationType) {
      case 'comment':
        return '$actorName commented on "${videoTitle ?? 'your video'}"';
      case 'like':
        return '$actorName liked your video "${videoTitle ?? ''}"';
      case 'repost':
        return '$actorName reposted your video "${videoTitle ?? ''}"';
      case 'subscribe':
        return '$actorName subscribed to your channel';
      case 'badge':
        return 'You earned the "$badgeType" badge!';
      case 'mention':
        return '$actorName mentioned you in a comment';
      default:
        return '$actorName interacted with your content';
    }
  }

  /// Icon name matching the notification type for UI rendering
  String get iconKey {
    switch (notificationType) {
      case 'comment':
        return 'comment';
      case 'like':
        return 'thumb_up';
      case 'repost':
        return 'repeat';
      case 'subscribe':
        return 'subscriptions';
      case 'badge':
        return 'verified';
      case 'mention':
        return 'alternate_email';
      default:
        return 'notifications';
    }
  }
}

/// CreatorBadge — Represents supporter/top fan badges awarded to viewers.
class CreatorBadge {
  final String badgeId;
  final String channelId;
  final String supporterUid;
  final String supporterName;
  final String badgeType;    // 'supporter', 'top_fan', 'milestone'
  final String? milestone;   // e.g. '100_subs', '1000_views'
  final String awardedAt;

  CreatorBadge({
    required this.badgeId,
    required this.channelId,
    required this.supporterUid,
    this.supporterName = '',
    required this.badgeType,
    this.milestone,
    required this.awardedAt,
  });

  factory CreatorBadge.fromJson(Map<String, dynamic> json) {
    return CreatorBadge(
      badgeId: json['id']?.toString() ?? json['badge_id']?.toString() ?? '',
      channelId: json['channel_id']?.toString() ?? '',
      supporterUid: json['supporter_uid']?.toString() ?? '',
      supporterName: json['supporter_name']?.toString() ?? '',
      badgeType: json['badge_type']?.toString() ?? 'supporter',
      milestone: json['milestone']?.toString(),
      awardedAt: json['awarded_at']?.toString() ??
          json['created_at']?.toString() ??
          '',
    );
  }
}