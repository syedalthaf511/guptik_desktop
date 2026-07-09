/// PlayerRepost — Repost functionality with original creator attribution.
/// Maps to local Postgres `mp_repost_videos` (when present) and Supabase feed.
class PlayerRepost {
  final String repostId;
  final String originalVideoId;
  final String originalCreatorUid;
  final String originalCreatorName;
  final String originalChannelName;
  final String reposterUid;
  final String reposterChannelName;
  final String? repostComment; // Optional caption added by reposter
  final String repostedAt;
  final int repostLikes;
  final int repostComments;

  PlayerRepost({
    required this.repostId,
    required this.originalVideoId,
    required this.originalCreatorUid,
    this.originalCreatorName = '',
    this.originalChannelName = '',
    required this.reposterUid,
    this.reposterChannelName = '',
    this.repostComment,
    required this.repostedAt,
    this.repostLikes = 0,
    this.repostComments = 0,
  });

  factory PlayerRepost.fromJson(Map<String, dynamic> json) {
    return PlayerRepost(
      repostId: json['repost_id']?.toString() ?? json['id']?.toString() ?? '',
      originalVideoId: json['original_video_id']?.toString() ??
          json['video_id']?.toString() ??
          '',
      originalCreatorUid: json['original_creator_uid']?.toString() ??
          json['creator_uid']?.toString() ??
          '',
      originalCreatorName: json['original_creator_name']?.toString() ?? '',
      originalChannelName: json['original_channel_name']?.toString() ??
          json['channel_name']?.toString() ??
          '',
      reposterUid: json['reposter_uid']?.toString() ??
          json['reposter_id']?.toString() ??
          '',
      reposterChannelName: json['reposter_channel_name']?.toString() ?? '',
      repostComment: json['repost_comment']?.toString(),
      repostedAt: json['reposted_at']?.toString() ??
          json['created_at']?.toString() ??
          '',
      repostLikes: json['repost_likes'] ?? json['like_count_local'] ?? 0,
      repostComments:
          json['repost_comments'] ?? json['comment_count_local'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'original_video_id': originalVideoId,
      'original_creator_uid': originalCreatorUid,
      'original_creator_name': originalCreatorName,
      'original_channel_name': originalChannelName,
      'reposter_uid': reposterUid,
      'reposter_channel_name': reposterChannelName,
      'repost_comment': repostComment,
      'reposted_at': repostedAt,
    };
  }
}

/// DraftVideo — Unpublished draft with optional scheduling and cross-post.
/// Maps to local Postgres `mp_draft_videos` table.
class DraftVideo {
  final String draftId;
  final String channelId;
  final String title;
  final String description;
  final List<String> tags;
  final String? filePathTemp;
  final String? thumbnailTempPath;
  final String lastEditedAt;
  final DateTime? schedulePublishAt;
  final List<String> crossPostPlatforms;
  final String createdAt;

  DraftVideo({
    required this.draftId,
    required this.channelId,
    this.title = '',
    this.description = '',
    this.tags = const [],
    this.filePathTemp,
    this.thumbnailTempPath,
    required this.lastEditedAt,
    this.schedulePublishAt,
    this.crossPostPlatforms = const [],
    required this.createdAt,
  });

  factory DraftVideo.fromJson(Map<String, dynamic> json) {
    return DraftVideo(
      draftId: json['id']?.toString() ?? json['draft_id']?.toString() ?? '',
      channelId: json['channel_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      filePathTemp: json['file_path_temp']?.toString(),
      thumbnailTempPath: json['thumbnail_temp_path']?.toString(),
      lastEditedAt: json['last_edited_at']?.toString() ?? '',
      schedulePublishAt: json['schedule_publish_at'] != null
          ? DateTime.tryParse(json['schedule_publish_at'].toString())
          : null,
      crossPostPlatforms: List<String>.from(json['cross_post_platforms'] ?? []),
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  bool get isScheduled =>
      schedulePublishAt != null &&
      schedulePublishAt!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() {
    return {
      'id': draftId,
      'channel_id': channelId,
      'title': title,
      'description': description,
      'tags': tags,
      'file_path_temp': filePathTemp,
      'thumbnail_temp_path': thumbnailTempPath,
      'last_edited_at': lastEditedAt,
      'schedule_publish_at': schedulePublishAt?.toIso8601String(),
      'cross_post_platforms': crossPostPlatforms,
      'created_at': createdAt,
    };
  }
}

/// VideoAnalytics — View/engagement tracking for the analytics dashboard.
/// Maps to local Postgres `video_analytics` and aggregated counts in
/// `mp_videos` / `watch_history`.
class VideoAnalytics {
  final String videoId;
  final int totalViews;
  final int uniqueViewers;
  final int likes;
  final int comments;
  final int saves;
  final int reposts;
  final int shares;
  final double averageWatchPercentage;
  final int totalWatchTimeSeconds;
  final int reactionHeart;
  final int reactionFire;
  final int reactionThumbsUp;
  final int reactionClap;
  final int reactionLaugh;
  final int reactionSurprised;
  final int reactionSad;
  final double estimatedEarnings;

  VideoAnalytics({
    required this.videoId,
    this.totalViews = 0,
    this.uniqueViewers = 0,
    this.likes = 0,
    this.comments = 0,
    this.saves = 0,
    this.reposts = 0,
    this.shares = 0,
    this.averageWatchPercentage = 0.0,
    this.totalWatchTimeSeconds = 0,
    this.reactionHeart = 0,
    this.reactionFire = 0,
    this.reactionThumbsUp = 0,
    this.reactionClap = 0,
    this.reactionLaugh = 0,
    this.reactionSurprised = 0,
    this.reactionSad = 0,
    this.estimatedEarnings = 0.0,
  });

  factory VideoAnalytics.fromJson(Map<String, dynamic> json) {
    return VideoAnalytics(
      videoId: json['video_id']?.toString() ?? json['id']?.toString() ?? '',
      totalViews: json['view_count_local'] ?? json['total_views'] ?? 0,
      uniqueViewers: json['unique_viewers_local'] ?? json['unique_viewers'] ?? 0,
      likes: json['like_count_local'] ?? json['likes'] ?? 0,
      comments: json['comment_count_local'] ?? json['comments'] ?? 0,
      saves: json['save_count_local'] ?? json['saves'] ?? 0,
      reposts: json['repost_count_local'] ?? json['reposts'] ?? 0,
      shares: json['share_count_local'] ?? json['shares'] ?? 0,
      averageWatchPercentage:
          (json['average_watch_percentage'] ?? 0).toDouble(),
      totalWatchTimeSeconds: json['total_watch_time_seconds'] ?? 0,
      reactionHeart: json['reaction_heart_count'] ?? 0,
      reactionFire: json['reaction_fire_count'] ?? 0,
      reactionThumbsUp: json['reaction_thumbs_up_count'] ?? 0,
      reactionClap: json['reaction_clap_count'] ?? 0,
      reactionLaugh: json['reaction_laugh_count'] ?? 0,
      reactionSurprised: json['reaction_surprised_count'] ?? 0,
      reactionSad: json['reaction_sad_count'] ?? 0,
      estimatedEarnings: (json['estimated_earnings'] ?? 0).toDouble(),
    );
  }

  int get totalReactions =>
      reactionHeart +
      reactionFire +
      reactionThumbsUp +
      reactionClap +
      reactionLaugh +
      reactionSurprised +
      reactionSad;

  double get engagementRate =>
      totalViews > 0 ? ((likes + comments + saves + reposts) / totalViews) * 100 : 0.0;
}