/// PlayerPlaylist — Video playlist creation and management model.
/// Maps to the local Postgres `mp_playlists` / `mp_playlist_videos` tables.
class PlayerPlaylist {
  final String playlistId;
  final String channelId;
  final String name;
  final String description;
  final bool isPublic;
  final String? coverImagePath;
  final int videoCount;
  final int totalDurationSeconds;
  final String createdAt;
  final String updatedAt;

  PlayerPlaylist({
    required this.playlistId,
    required this.channelId,
    required this.name,
    this.description = '',
    this.isPublic = true,
    this.coverImagePath,
    this.videoCount = 0,
    this.totalDurationSeconds = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PlayerPlaylist.fromJson(Map<String, dynamic> json) {
    return PlayerPlaylist(
      playlistId: json['id']?.toString() ?? json['playlist_id']?.toString() ?? '',
      channelId: json['channel_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Playlist',
      description: json['description']?.toString() ?? '',
      isPublic: json['is_public'] ?? true,
      coverImagePath: json['cover_image_path']?.toString(),
      videoCount: json['video_count'] ?? 0,
      totalDurationSeconds: json['total_duration_seconds'] ?? 0,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': playlistId,
      'channel_id': channelId,
      'name': name,
      'description': description,
      'is_public': isPublic,
      'cover_image_path': coverImagePath,
      'video_count': videoCount,
      'total_duration_seconds': totalDurationSeconds,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// Formatted total duration (e.g. "1h 23m")
  String get formattedDuration {
    if (totalDurationSeconds <= 0) return '0m';
    final h = totalDurationSeconds ~/ 3600;
    final m = (totalDurationSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

/// PlayerPlaylistVideo — A single video entry within a playlist, including
/// its ordered position so the playlist can be rearranged by the user.
class PlayerPlaylistVideo {
  final String playlistId;
  final String videoId;
  final int position;
  final String addedAt;

  PlayerPlaylistVideo({
    required this.playlistId,
    required this.videoId,
    required this.position,
    required this.addedAt,
  });

  factory PlayerPlaylistVideo.fromJson(Map<String, dynamic> json) {
    return PlayerPlaylistVideo(
      playlistId: json['playlist_id']?.toString() ?? '',
      videoId: json['video_id']?.toString() ?? '',
      position: json['position'] ?? 0,
      addedAt: json['added_at']?.toString() ?? '',
    );
  }
}