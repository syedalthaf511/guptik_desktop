import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/mediaplayer/player_repost_model.dart';
import '../../models/mediaplayer/player_notification_model.dart';

/// PlayerAnalyticsService — View/engagement tracking and notification system.
/// Fetches analytics from local Postgres `mp_videos` / `watch_history` and
/// manages social notifications for comments, likes, reposts, and badges.
class PlayerAnalyticsService {
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
  // VIDEO ANALYTICS
  // =========================================================================

  /// Fetches detailed analytics for a single video.
  Future<VideoAnalytics> fetchVideoAnalytics(String videoId) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('''
          SELECT id, view_count_local, unique_viewers_local, like_count_local,
                 comment_count_local, save_count_local, repost_count_local,
                 share_count_local, average_watch_percentage,
                 reaction_heart_count, reaction_fire_count,
                 reaction_thumbs_up_count, reaction_clap_count,
                 reaction_laugh_count, reaction_surprised_count,
                 reaction_sad_count
          FROM mp_videos
          WHERE id::text = @vid AND is_deleted = FALSE
        '''),
        parameters: {'vid': videoId},
      );
      await conn.close();

      if (result.isNotEmpty) {
        final row = result.first;
        return VideoAnalytics.fromJson({
          'video_id': row[0]?.toString() ?? '',
          'view_count_local': row[1] ?? 0,
          'unique_viewers_local': row[2] ?? 0,
          'like_count_local': row[3] ?? 0,
          'comment_count_local': row[4] ?? 0,
          'save_count_local': row[5] ?? 0,
          'repost_count_local': row[6] ?? 0,
          'share_count_local': row[7] ?? 0,
          'average_watch_percentage': row[8] ?? 0,
          'reaction_heart_count': row[9] ?? 0,
          'reaction_fire_count': row[10] ?? 0,
          'reaction_thumbs_up_count': row[11] ?? 0,
          'reaction_clap_count': row[12] ?? 0,
          'reaction_laugh_count': row[13] ?? 0,
          'reaction_surprised_count': row[14] ?? 0,
          'reaction_sad_count': row[15] ?? 0,
        });
      }
      return VideoAnalytics(videoId: videoId);
    } catch (e) {
      debugPrint('Fetch Video Analytics Error: $e');
      return VideoAnalytics(videoId: videoId);
    }
  }

  /// Fetches channel-level analytics — aggregated views, engagement, and
  /// total watch time across all videos.
  Future<Map<String, dynamic>> fetchChannelAnalytics(String channelId) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('''
          SELECT
            COUNT(*) as total_videos,
            COALESCE(SUM(view_count_local), 0) as total_views,
            COALESCE(SUM(unique_viewers_local), 0) as total_unique_viewers,
            COALESCE(SUM(like_count_local), 0) as total_likes,
            COALESCE(SUM(comment_count_local), 0) as total_comments,
            COALESCE(SUM(save_count_local), 0) as total_saves,
            COALESCE(SUM(repost_count_local), 0) as total_reposts,
            COALESCE(SUM(share_count_local), 0) as total_shares,
            COALESCE(SUM(reaction_heart_count + reaction_fire_count +
                         reaction_thumbs_up_count + reaction_clap_count +
                         reaction_laugh_count + reaction_surprised_count +
                         reaction_sad_count), 0) as total_reactions
          FROM mp_videos
          WHERE channel_id = @cid AND is_deleted = FALSE
        '''),
        parameters: {'cid': channelId},
      );

      // Top performing videos
      final topResult = await conn.execute(
        Sql.named('''
          SELECT id, title, view_count_local, like_count_local,
                 comment_count_local
          FROM mp_videos
          WHERE channel_id = @cid AND is_deleted = FALSE
          ORDER BY view_count_local DESC
          LIMIT 5
        '''),
        parameters: {'cid': channelId},
      );

      await conn.close();

      Map<String, dynamic> summary = {
        'total_videos': 0,
        'total_views': 0,
        'total_unique_viewers': 0,
        'total_likes': 0,
        'total_comments': 0,
        'total_saves': 0,
        'total_reposts': 0,
        'total_shares': 0,
        'total_reactions': 0,
      };

      if (result.isNotEmpty) {
        final row = result.first;
        summary = {
          'total_videos': row[0] ?? 0,
          'total_views': row[1] ?? 0,
          'total_unique_viewers': row[2] ?? 0,
          'total_likes': row[3] ?? 0,
          'total_comments': row[4] ?? 0,
          'total_saves': row[5] ?? 0,
          'total_reposts': row[6] ?? 0,
          'total_shares': row[7] ?? 0,
          'total_reactions': row[8] ?? 0,
        };
      }

      final List<Map<String, dynamic>> topVideos = [];
      for (final row in topResult) {
        topVideos.add({
          'video_id': row[0]?.toString() ?? '',
          'title': row[1]?.toString() ?? '',
          'views': row[2] ?? 0,
          'likes': row[3] ?? 0,
          'comments': row[4] ?? 0,
        });
      }

      return {
        ...summary,
        'top_videos': topVideos,
        'engagement_rate': (summary['total_views'] as int) > 0
            ? (((summary['total_likes'] as int) +
                    (summary['total_comments'] as int) +
                    (summary['total_saves'] as int) +
                    (summary['total_reposts'] as int)) /
                (summary['total_views'] as int)) *
                100
            : 0.0,
      };
    } catch (e) {
      debugPrint('Fetch Channel Analytics Error: $e');
      return {
        'total_videos': 0,
        'total_views': 0,
        'total_unique_viewers': 0,
        'total_likes': 0,
        'total_comments': 0,
        'total_saves': 0,
        'total_reposts': 0,
        'total_shares': 0,
        'total_reactions': 0,
        'top_videos': <Map<String, dynamic>>[],
        'engagement_rate': 0.0,
      };
    }
  }

  // =========================================================================
  // NOTIFICATIONS
  // =========================================================================

  /// Creates a notification entry in the local Postgres notifications table.
  Future<bool> createNotification({
    required String recipientUid,
    required String actorUid,
    String actorName = '',
    required String notificationType,
    String? videoId,
    String? videoTitle,
    String? commentText,
    String? badgeType,
  }) async {
    try {
      final conn = await _connect();

      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mp_player_notifications (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          recipient_uid TEXT NOT NULL,
          actor_uid TEXT NOT NULL,
          actor_name TEXT DEFAULT '',
          notification_type TEXT NOT NULL,
          video_id TEXT,
          video_title TEXT,
          comment_text TEXT,
          badge_type TEXT,
          is_read BOOLEAN DEFAULT FALSE,
          created_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');

      await conn.execute(
        Sql.named('''
          INSERT INTO mp_player_notifications
            (recipient_uid, actor_uid, actor_name, notification_type,
             video_id, video_title, comment_text, badge_type)
          VALUES (@ruid, @auid, @aname, @type, @vid, @vtitle, @ctext, @btype)
        '''),
        parameters: {
          'ruid': recipientUid,
          'auid': actorUid,
          'aname': actorName,
          'type': notificationType,
          'vid': videoId,
          'vtitle': videoTitle,
          'ctext': commentText,
          'btype': badgeType,
        },
      );

      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Create Notification Error: $e');
      return false;
    }
  }

  /// Fetches all notifications for a user, newest first.
  Future<List<PlayerNotification>> fetchNotifications(
      String recipientUid) async {
    try {
      final conn = await _connect();
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mp_player_notifications (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          recipient_uid TEXT NOT NULL,
          actor_uid TEXT NOT NULL,
          actor_name TEXT DEFAULT '',
          notification_type TEXT NOT NULL,
          video_id TEXT,
          video_title TEXT,
          comment_text TEXT,
          badge_type TEXT,
          is_read BOOLEAN DEFAULT FALSE,
          created_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');

      final result = await conn.execute(
        Sql.named('''
          SELECT id, recipient_uid, actor_uid, actor_name,
                 notification_type, video_id, video_title, comment_text,
                 badge_type, is_read, created_at
          FROM mp_player_notifications
          WHERE recipient_uid = @ruid
          ORDER BY created_at DESC
          LIMIT 50
        '''),
        parameters: {'ruid': recipientUid},
      );
      await conn.close();

      final List<PlayerNotification> notifications = [];
      for (final row in result) {
        notifications.add(PlayerNotification.fromJson({
          'id': row[0]?.toString() ?? '',
          'recipient_uid': row[1]?.toString() ?? '',
          'actor_uid': row[2]?.toString() ?? '',
          'actor_name': row[3]?.toString() ?? '',
          'notification_type': row[4]?.toString() ?? 'comment',
          'video_id': row[5]?.toString(),
          'video_title': row[6]?.toString(),
          'comment_text': row[7]?.toString(),
          'badge_type': row[8]?.toString(),
          'is_read': row[9] ?? false,
          'created_at': row[10]?.toString() ?? '',
        }));
      }
      return notifications;
    } catch (e) {
      debugPrint('Fetch Notifications Error: $e');
      return [];
    }
  }

  /// Fetches only unread notifications (for the badge count).
  Future<int> fetchUnreadNotificationCount(String recipientUid) async {
    try {
      final conn = await _connect();
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mp_player_notifications (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          recipient_uid TEXT NOT NULL,
          actor_uid TEXT NOT NULL,
          actor_name TEXT DEFAULT '',
          notification_type TEXT NOT NULL,
          video_id TEXT,
          video_title TEXT,
          comment_text TEXT,
          badge_type TEXT,
          is_read BOOLEAN DEFAULT FALSE,
          created_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');

      final result = await conn.execute(
        Sql.named('''
          SELECT COUNT(*) FROM mp_player_notifications
          WHERE recipient_uid = @ruid AND is_read = FALSE
        '''),
        parameters: {'ruid': recipientUid},
      );
      await conn.close();

      if (result.isNotEmpty) {
        return result.first.first as int? ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('Fetch Unread Count Error: $e');
      return 0;
    }
  }

  /// Marks a single notification as read.
  Future<bool> markNotificationRead(String notificationId) async {
    try {
      final conn = await _connect();
      await conn.execute(
        Sql.named('''
          UPDATE mp_player_notifications
          SET is_read = TRUE
          WHERE id = @nid
        '''),
        parameters: {'nid': notificationId},
      );
      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Mark Notification Read Error: $e');
      return false;
    }
  }

  /// Marks all notifications as read for a user.
  Future<bool> markAllNotificationsRead(String recipientUid) async {
    try {
      final conn = await _connect();
      await conn.execute(
        Sql.named('''
          UPDATE mp_player_notifications
          SET is_read = TRUE
          WHERE recipient_uid = @ruid AND is_read = FALSE
        '''),
        parameters: {'ruid': recipientUid},
      );
      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Mark All Notifications Read Error: $e');
      return false;
    }
  }

  // =========================================================================
  // CREATOR SUPPORTER BADGES
  // =========================================================================

  /// Awards a supporter badge to a viewer.
  Future<bool> awardBadge({
    required String channelId,
    required String supporterUid,
    String supporterName = '',
    required String badgeType,
    String? milestone,
  }) async {
    try {
      final conn = await _connect();
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mp_creator_badges (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          channel_id TEXT NOT NULL,
          supporter_uid TEXT NOT NULL,
          supporter_name TEXT DEFAULT '',
          badge_type TEXT NOT NULL,
          milestone TEXT,
          awarded_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');

      await conn.execute(
        Sql.named('''
          INSERT INTO mp_creator_badges
            (channel_id, supporter_uid, supporter_name, badge_type, milestone)
          VALUES (@cid, @suid, @sname, @btype, @milestone)
          ON CONFLICT DO NOTHING
        '''),
        parameters: {
          'cid': channelId,
          'suid': supporterUid,
          'sname': supporterName,
          'btype': badgeType,
          'milestone': milestone,
        },
      );

      // Also create a notification
      await createNotification(
        recipientUid: supporterUid,
        actorUid: channelId,
        actorName: 'Guptik',
        notificationType: 'badge',
        badgeType: badgeType,
      );

      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Award Badge Error: $e');
      return false;
    }
  }

  /// Fetches all badges awarded by a channel.
  Future<List<CreatorBadge>> fetchChannelBadges(String channelId) async {
    try {
      final conn = await _connect();
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mp_creator_badges (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          channel_id TEXT NOT NULL,
          supporter_uid TEXT NOT NULL,
          supporter_name TEXT DEFAULT '',
          badge_type TEXT NOT NULL,
          milestone TEXT,
          awarded_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');

      final result = await conn.execute(
        Sql.named('''
          SELECT id, channel_id, supporter_uid, supporter_name,
                 badge_type, milestone, awarded_at
          FROM mp_creator_badges
          WHERE channel_id = @cid
          ORDER BY awarded_at DESC
        '''),
        parameters: {'cid': channelId},
      );
      await conn.close();

      final List<CreatorBadge> badges = [];
      for (final row in result) {
        badges.add(CreatorBadge.fromJson({
          'id': row[0]?.toString() ?? '',
          'channel_id': row[1]?.toString() ?? '',
          'supporter_uid': row[2]?.toString() ?? '',
          'supporter_name': row[3]?.toString() ?? '',
          'badge_type': row[4]?.toString() ?? 'supporter',
          'milestone': row[5]?.toString(),
          'awarded_at': row[6]?.toString() ?? '',
        }));
      }
      return badges;
    } catch (e) {
      debugPrint('Fetch Channel Badges Error: $e');
      return [];
    }
  }

  // =========================================================================
  // SOCIAL FEED (FRIENDS ACTIVITY)
  // =========================================================================

  /// Fetches recent activity from subscribed channels via Supabase.
  /// Returns a list of recent video uploads from channels the user follows.
  Future<List<Map<String, dynamic>>> fetchSocialFeed(String userUid) async {
    try {
      final supabase = Supabase.instance.client;

      // Get channels the user subscribes to
      final subscriptions = await supabase
          .from('mp_subscriptions')
          .select('channel_id')
          .eq('subscriber_uid', userUid);

      if (subscriptions.isEmpty) return [];

      final channelIds = (subscriptions as List)
          .map((s) => s['channel_id'] as String)
          .toList();

      // Fetch recent videos from those channels
      final videos = await supabase
          .from('mp_videos')
          .select()
          .inFilter('creator_uid', channelIds)
          .order('published_at', ascending: false)
          .limit(20);

      return (videos as List)
          .map((v) => v as Map<String, dynamic>)
          .toList();
    } catch (e) {
      debugPrint('Fetch Social Feed Error: $e');
      return [];
    }
  }
}