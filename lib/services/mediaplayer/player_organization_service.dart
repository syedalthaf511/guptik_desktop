import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import '../../models/mediaplayer/player_playlist_model.dart';
import '../../models/mediaplayer/player_repost_model.dart';

/// PlayerOrganizationService — Video organization features.
/// Manages Watch Later, Reposts, Drafts, My Videos dashboard, and Playlists
/// by talking directly to the local Docker Postgres node (matching the
/// existing `DesktopSystemFolderScreen` connection pattern).
class PlayerOrganizationService {
  final String _localDbHost = '127.0.0.1';
  final int _localDbPort = 55432;
  final String _dbName = 'postgres';
  final String _dbUser = 'postgres';
  final String _dbPass = 'GuptikSystemPassword2026';

  Future<Connection> _connect() async {
    return Connection.open(
      Endpoint(
        host: _localDbHost,
        port: _localDbPort,
        database: _dbName,
        username: _dbUser,
        password: _dbPass,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
  }

  // =========================================================================
  // WATCH LATER (mp_saved_videos)
  // =========================================================================

  /// Adds a video to the Watch Later list (`mp_saved_videos` table).
  Future<bool> addToWatchLater({
    required String videoId,
    required String creatorUid,
    String folderName = 'Watch Later',
    bool isIncognito = false,
  }) async {
    try {
      final conn = await _connect();
      await conn.execute(
        Sql.named('''
          INSERT INTO mp_saved_videos (video_id, creator_uid, folder_name, is_incognito)
          VALUES (@vid, @cuid, @folder, @incog)
          ON CONFLICT DO NOTHING
        '''),
        parameters: {
          'vid': videoId,
          'cuid': creatorUid,
          'folder': folderName,
          'incog': isIncognito,
        },
      );
      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Add to Watch Later Error: $e');
      return false;
    }
  }

  /// Removes a video from the Watch Later list.
  Future<bool> removeFromWatchLater(String videoId) async {
    try {
      final conn = await _connect();
      await conn.execute(
        Sql.named('DELETE FROM mp_saved_videos WHERE video_id = @vid'),
        parameters: {'vid': videoId},
      );
      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Remove from Watch Later Error: $e');
      return false;
    }
  }

  /// Checks whether a video is already in the user's Watch Later list.
  Future<bool> isInWatchLater(String videoId) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('SELECT 1 FROM mp_saved_videos WHERE video_id = @vid LIMIT 1'),
        parameters: {'vid': videoId},
      );
      await conn.close();
      return result.isNotEmpty;
    } catch (e) {
      debugPrint('Check Watch Later Error: $e');
      return false;
    }
  }

  // =========================================================================
  // REPOSTS
  // =========================================================================

  /// Creates a repost, preserving original creator attribution.
  Future<bool> repostVideo({
    required String originalVideoId,
    required String originalCreatorUid,
    String? originalCreatorName,
    String? originalChannelName,
    required String reposterUid,
    String? reposterChannelName,
    String? repostComment,
  }) async {
    try {
      final conn = await _connect();

      // Ensure the repost table exists (safe to call repeatedly)
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mp_repost_videos (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          original_video_id TEXT NOT NULL,
          original_creator_uid TEXT NOT NULL,
          original_creator_name TEXT DEFAULT '',
          original_channel_name TEXT DEFAULT '',
          reposter_uid TEXT NOT NULL,
          reposter_channel_name TEXT DEFAULT '',
          repost_comment TEXT,
          reposted_at TIMESTAMPTZ DEFAULT NOW(),
          repost_likes INTEGER DEFAULT 0,
          repost_comments INTEGER DEFAULT 0
        )
      ''');

      await conn.execute(
        Sql.named('''
          INSERT INTO mp_repost_videos
            (original_video_id, original_creator_uid, original_creator_name,
             original_channel_name, reposter_uid, reposter_channel_name,
             repost_comment)
          VALUES (@ovid, @ocuid, @ocname, @ochname, @ruid, @rchname, @comment)
        '''),
        parameters: {
          'ovid': originalVideoId,
          'ocuid': originalCreatorUid,
          'ocname': originalCreatorName ?? '',
          'ochname': originalChannelName ?? '',
          'ruid': reposterUid,
          'rchname': reposterChannelName ?? '',
          'comment': repostComment,
        },
      );

      // Increment the original video's repost count
      await conn.execute(
        Sql.named('''
          UPDATE mp_videos
          SET repost_count_local = repost_count_local + 1
          WHERE id::text = @ovid
        '''),
        parameters: {'ovid': originalVideoId},
      );

      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Repost Video Error: $e');
      return false;
    }
  }

  /// Fetches all reposts made by a specific user.
  /// Uses index-based column access matching the existing pattern.
  Future<List<PlayerRepost>> fetchUserReposts(String reposterUid) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('''
          SELECT id, original_video_id, original_creator_uid,
                 original_creator_name, original_channel_name,
                 reposter_uid, reposter_channel_name, repost_comment,
                 reposted_at, repost_likes, repost_comments
          FROM mp_repost_videos
          WHERE reposter_uid = @ruid
          ORDER BY reposted_at DESC
        '''),
        parameters: {'ruid': reposterUid},
      );
      await conn.close();

      final List<PlayerRepost> reposts = [];
      for (final row in result) {
        reposts.add(PlayerRepost.fromJson({
          'id': row[0]?.toString() ?? '',
          'original_video_id': row[1]?.toString() ?? '',
          'original_creator_uid': row[2]?.toString() ?? '',
          'original_creator_name': row[3]?.toString() ?? '',
          'original_channel_name': row[4]?.toString() ?? '',
          'reposter_uid': row[5]?.toString() ?? '',
          'reposter_channel_name': row[6]?.toString() ?? '',
          'repost_comment': row[7]?.toString(),
          'reposted_at': row[8]?.toString() ?? '',
          'repost_likes': row[9] ?? 0,
          'repost_comments': row[10] ?? 0,
        }));
      }
      return reposts;
    } catch (e) {
      debugPrint('Fetch User Reposts Error: $e');
      return [];
    }
  }

  // =========================================================================
  // DRAFTS (mp_draft_videos)
  // =========================================================================

  /// Fetches all draft videos for a channel.
  Future<List<DraftVideo>> fetchDrafts(String channelId) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('''
          SELECT id, channel_id, title, description, tags,
                 file_path_temp, thumbnail_temp_path, last_edited_at,
                 schedule_publish_at, cross_post_platforms, created_at
          FROM mp_draft_videos
          WHERE channel_id = @cid
          ORDER BY last_edited_at DESC
        '''),
        parameters: {'cid': channelId},
      );
      await conn.close();

      final List<DraftVideo> drafts = [];
      for (final row in result) {
        drafts.add(DraftVideo.fromJson({
          'id': row[0]?.toString() ?? '',
          'channel_id': row[1]?.toString() ?? '',
          'title': row[2]?.toString() ?? '',
          'description': row[3]?.toString() ?? '',
          'tags': row[4] ?? [],
          'file_path_temp': row[5]?.toString(),
          'thumbnail_temp_path': row[6]?.toString(),
          'last_edited_at': row[7]?.toString() ?? '',
          'schedule_publish_at': row[8]?.toString(),
          'cross_post_platforms': row[9] ?? [],
          'created_at': row[10]?.toString() ?? '',
        }));
      }
      return drafts;
    } catch (e) {
      debugPrint('Fetch Drafts Error: $e');
      return [];
    }
  }

  /// Saves or updates a draft. Returns the draft ID.
  Future<String?> saveDraft({
    String? draftId,
    required String channelId,
    String title = '',
    String description = '',
    List<String> tags = const [],
    String? filePathTemp,
    String? thumbnailTempPath,
    DateTime? schedulePublishAt,
    List<String> crossPostPlatforms = const [],
  }) async {
    try {
      final conn = await _connect();
      final id = draftId ?? '';

      if (id.isEmpty) {
        await conn.execute(
          Sql.named('''
            INSERT INTO mp_draft_videos
              (channel_id, title, description, tags, file_path_temp,
               thumbnail_temp_path, last_edited_at, schedule_publish_at,
               cross_post_platforms)
            VALUES (@cid, @title, @desc, @tags, @fpath, @tpath, NOW(),
                    @schedule, @cross)
          '''),
          parameters: {
            'cid': channelId,
            'title': title,
            'desc': description,
            'tags': tags,
            'fpath': filePathTemp,
            'tpath': thumbnailTempPath,
            'schedule': schedulePublishAt,
            'cross': crossPostPlatforms,
          },
        );
      } else {
        await conn.execute(
          Sql.named('''
            UPDATE mp_draft_videos SET
              title = @title, description = @desc, tags = @tags,
              file_path_temp = @fpath, thumbnail_temp_path = @tpath,
              last_edited_at = NOW(), schedule_publish_at = @schedule,
              cross_post_platforms = @cross
            WHERE id = @did
          '''),
          parameters: {
            'did': draftId,
            'title': title,
            'desc': description,
            'tags': tags,
            'fpath': filePathTemp,
            'tpath': thumbnailTempPath,
            'schedule': schedulePublishAt,
            'cross': crossPostPlatforms,
          },
        );
      }

      await conn.close();
      return id.isEmpty ? 'new_draft' : id;
    } catch (e) {
      debugPrint('Save Draft Error: $e');
      return null;
    }
  }

  /// Deletes a draft permanently.
  Future<bool> deleteDraft(String draftId) async {
    try {
      final conn = await _connect();
      await conn.execute(
        Sql.named('DELETE FROM mp_draft_videos WHERE id = @did'),
        parameters: {'did': draftId},
      );
      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Delete Draft Error: $e');
      return false;
    }
  }

  // =========================================================================
  // PLAYLISTS (mp_playlists / mp_playlist_videos)
  // =========================================================================

  /// Fetches all playlists for a channel.
  Future<List<PlayerPlaylist>> fetchPlaylists(String channelId) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('''
          SELECT id, channel_id, name, description, is_public,
                 cover_image_path, video_count, total_duration_seconds,
                 created_at, updated_at
          FROM mp_playlists
          WHERE channel_id = @cid
          ORDER BY updated_at DESC
        '''),
        parameters: {'cid': channelId},
      );
      await conn.close();

      final List<PlayerPlaylist> playlists = [];
      for (final row in result) {
        playlists.add(PlayerPlaylist.fromJson({
          'id': row[0]?.toString() ?? '',
          'channel_id': row[1]?.toString() ?? '',
          'name': row[2]?.toString() ?? 'Untitled Playlist',
          'description': row[3]?.toString() ?? '',
          'is_public': row[4] ?? true,
          'cover_image_path': row[5]?.toString(),
          'video_count': row[6] ?? 0,
          'total_duration_seconds': row[7] ?? 0,
          'created_at': row[8]?.toString() ?? '',
          'updated_at': row[9]?.toString() ?? '',
        }));
      }
      return playlists;
    } catch (e) {
      debugPrint('Fetch Playlists Error: $e');
      return [];
    }
  }

  /// Creates a new playlist. Returns the playlist ID on success.
  Future<String?> createPlaylist({
    required String channelId,
    required String name,
    String description = '',
    bool isPublic = true,
  }) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('''
          INSERT INTO mp_playlists (channel_id, name, description, is_public)
          VALUES (@cid, @name, @desc, @pub)
          RETURNING id
        '''),
        parameters: {
          'cid': channelId,
          'name': name,
          'desc': description,
          'pub': isPublic,
        },
      );
      await conn.close();
      if (result.isNotEmpty) {
        return result.first.first?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('Create Playlist Error: $e');
      return null;
    }
  }

  /// Adds a video to a playlist at the specified position.
  Future<bool> addVideoToPlaylist({
    required String playlistId,
    required String videoId,
    int position = 0,
  }) async {
    try {
      final conn = await _connect();
      await conn.execute(
        Sql.named('''
          INSERT INTO mp_playlist_videos (playlist_id, video_id, position)
          VALUES (@pid, @vid, @pos)
          ON CONFLICT (playlist_id, video_id) DO UPDATE SET position = @pos
        '''),
        parameters: {
          'pid': playlistId,
          'vid': videoId,
          'pos': position,
        },
      );

      // Update the playlist's video count
      await conn.execute(
        Sql.named('''
          UPDATE mp_playlists
          SET video_count = (
            SELECT COUNT(*) FROM mp_playlist_videos WHERE playlist_id = @pid
          ), updated_at = NOW()
          WHERE id = @pid
        '''),
        parameters: {'pid': playlistId},
      );

      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Add Video to Playlist Error: $e');
      return false;
    }
  }

  /// Removes a video from a playlist.
  Future<bool> removeVideoFromPlaylist({
    required String playlistId,
    required String videoId,
  }) async {
    try {
      final conn = await _connect();
      await conn.execute(
        Sql.named('''
          DELETE FROM mp_playlist_videos
          WHERE playlist_id = @pid AND video_id = @vid
        '''),
        parameters: {'pid': playlistId, 'vid': videoId},
      );

      await conn.execute(
        Sql.named('''
          UPDATE mp_playlists
          SET video_count = (
            SELECT COUNT(*) FROM mp_playlist_videos WHERE playlist_id = @pid
          ), updated_at = NOW()
          WHERE id = @pid
        '''),
        parameters: {'pid': playlistId},
      );

      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Remove Video from Playlist Error: $e');
      return false;
    }
  }

  /// Deletes a playlist entirely.
  Future<bool> deletePlaylist(String playlistId) async {
    try {
      final conn = await _connect();
      await conn.execute(
        Sql.named('DELETE FROM mp_playlist_videos WHERE playlist_id = @pid'),
        parameters: {'pid': playlistId},
      );
      await conn.execute(
        Sql.named('DELETE FROM mp_playlists WHERE id = @pid'),
        parameters: {'pid': playlistId},
      );
      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Delete Playlist Error: $e');
      return false;
    }
  }
}