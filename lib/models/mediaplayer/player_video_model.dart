class PlayerVideo {
  final String videoId;
  final String creatorUid;
  final String title;
  final String description;
  final String filePath; 
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final String createdAt;
  final String creatorUrl;
  final String channelName;
  final List<String> stickers;
  final bool isReel;
  final String visibility;

  // 🚀 NEW: Extended fields for enhanced features
  final String category;
  final List<String> tags;
  final bool isMonetized;
  final int saveCount;
  final int repostCount;
  final int shareCount;
  final int reactionHeartCount;
  final int reactionFireCount;
  final int reactionThumbsUpCount;
  final int reactionClapCount;
  final int reactionLaughCount;
  final int reactionSurprisedCount;
  final int reactionSadCount;
  final double averageWatchPercentage;
  final int uniqueViewers;
  final String? thumbnailUrl;

  PlayerVideo({
    required this.videoId,
    required this.creatorUid,
    required this.title,
    required this.description,
    required this.filePath,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.createdAt,
    required this.creatorUrl,
    required this.channelName,
    this.stickers = const [],
    required this.isReel,
    required this.visibility,
    this.category = '',
    this.tags = const [],
    this.isMonetized = false,
    this.saveCount = 0,
    this.repostCount = 0,
    this.shareCount = 0,
    this.reactionHeartCount = 0,
    this.reactionFireCount = 0,
    this.reactionThumbsUpCount = 0,
    this.reactionClapCount = 0,
    this.reactionLaughCount = 0,
    this.reactionSurprisedCount = 0,
    this.reactionSadCount = 0,
    this.averageWatchPercentage = 0.0,
    this.uniqueViewers = 0,
    this.thumbnailUrl,
  });

  /// Total reactions across all types
  int get totalReactions =>
      reactionHeartCount +
      reactionFireCount +
      reactionThumbsUpCount +
      reactionClapCount +
      reactionLaughCount +
      reactionSurprisedCount +
      reactionSadCount;

  /// Engagement rate (likes + comments + saves + reposts) / views * 100
  double get engagementRate =>
      viewCount > 0 ? ((likeCount + commentCount + saveCount + repostCount) / viewCount) * 100 : 0.0;

  factory PlayerVideo.fromJson(Map<String, dynamic> json, String gateway) {
    // Parse tags from various possible formats
    List<String> parseTags(dynamic rawTags) {
      if (rawTags == null) return [];
      if (rawTags is List) return rawTags.map((e) => e.toString()).toList();
      if (rawTags is String && rawTags.isNotEmpty) {
        return rawTags.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      return [];
    }

    return PlayerVideo(
      videoId: json['video_id'] ?? json['id'] ?? '',
      creatorUid: json['creator_uid'] ?? '',
      title: json['title'] ?? 'Untitled Broadcast',
      description: json['description'] ?? '',
      filePath: json['file_path'] ?? '',
      viewCount: json['view_count_local'] ?? json['view_count'] ?? 0,
      likeCount: json['like_count_local'] ?? json['like_count'] ?? 0,
      commentCount: json['comment_count_local'] ?? json['comment_count'] ?? 0,
      createdAt: json['published_at'] ?? json['created_at'] ?? json['upload_timestamp'] ?? '',
      creatorUrl: gateway,
      channelName: json['channel_name'] ?? 'Unknown Creator', 
      isReel: json['is_reel'] ?? false,
      visibility: json['visibility'] ?? 'public',
      // 🚀 NEW: Extended fields
      category: json['category']?.toString() ?? '',
      tags: parseTags(json['tags']),
      isMonetized: json['is_monetized'] ?? json['monetization_enabled'] ?? false,
      saveCount: json['save_count_local'] ?? json['save_count'] ?? 0,
      repostCount: json['repost_count_local'] ?? json['repost_count'] ?? 0,
      shareCount: json['share_count_local'] ?? json['share_count'] ?? 0,
      reactionHeartCount: json['reaction_heart_count'] ?? 0,
      reactionFireCount: json['reaction_fire_count'] ?? 0,
      reactionThumbsUpCount: json['reaction_thumbs_up_count'] ?? 0,
      reactionClapCount: json['reaction_clap_count'] ?? 0,
      reactionLaughCount: json['reaction_laugh_count'] ?? 0,
      reactionSurprisedCount: json['reaction_surprised_count'] ?? 0,
      reactionSadCount: json['reaction_sad_count'] ?? 0,
      averageWatchPercentage: (json['average_watch_percentage'] ?? 0).toDouble(),
      uniqueViewers: json['unique_viewers_local'] ?? json['unique_viewers'] ?? 0,
      thumbnailUrl: json['thumbnail_url']?.toString(),
    );
  }
}