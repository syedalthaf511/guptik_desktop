import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/mediaplayer/video_sticker_model.dart';

/// PlayerMonetizationService — In-video sticker product placement editor,
/// earnings dashboard, ad integration, and subscription/membership tracking.
class PlayerMonetizationService {
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
  // IN-VIDEO STICKERS (mp_sticker_products_catalog / mp_sticker_services_catalog)
  // =========================================================================

  /// Fetches all product/service stickers for a given video.
  Future<List<VideoSticker>> fetchStickers(String videoId) async {
    try {
      final conn = await _connect();

      // Products
      final productResult = await conn.execute(
        Sql.named('''
          SELECT id, video_id, product_id, timestamp_in_video, clickable_zone,
                 product_name, price, currency, description, link_url,
                 image_path, stock_status, sales_count_local,
                 click_count_local, purchase_initiated_count,
                 purchase_completed_count, is_active, created_at, updated_at
          FROM mp_sticker_products_catalog
          WHERE video_id = @vid AND is_active = TRUE
          ORDER BY timestamp_in_video ASC
        '''),
        parameters: {'vid': videoId},
      );

      // Services
      final serviceResult = await conn.execute(
        Sql.named('''
          SELECT id, video_id, service_id, timestamp_in_video, clickable_zone,
                 service_name, price, currency, description,
                 booking_count_local, is_active, created_at
          FROM mp_sticker_services_catalog
          WHERE video_id = @vid AND is_active = TRUE
          ORDER BY timestamp_in_video ASC
        '''),
        parameters: {'vid': videoId},
      );

      await conn.close();

      final List<VideoSticker> stickers = [];

      for (final row in productResult) {
        stickers.add(VideoSticker.fromJson({
          'id': row[0]?.toString() ?? '',
          'video_id': row[1]?.toString() ?? '',
          'product_id': row[2]?.toString() ?? '',
          'timestamp_in_video': row[3] ?? 0,
          'clickable_zone': _parseJsonb(row[4]),
          'product_name': row[5]?.toString() ?? 'Untitled',
          'price': row[6],
          'currency': row[7]?.toString() ?? 'USD',
          'description': row[8]?.toString() ?? '',
          'link_url': row[9]?.toString(),
          'image_path': row[10]?.toString(),
          'stock_status': row[11]?.toString() ?? 'in_stock',
          'sales_count_local': row[12] ?? 0,
          'click_count_local': row[13] ?? 0,
          'purchase_initiated_count': row[14] ?? 0,
          'purchase_completed_count': row[15] ?? 0,
          'is_active': row[16] ?? true,
          'created_at': row[17]?.toString() ?? '',
          'updated_at': row[18]?.toString() ?? '',
        }));
      }

      for (final row in serviceResult) {
        stickers.add(VideoSticker.fromJson({
          'id': row[0]?.toString() ?? '',
          'video_id': row[1]?.toString() ?? '',
          'service_id': row[2]?.toString() ?? '',
          'timestamp_in_video': row[3] ?? 0,
          'clickable_zone': _parseJsonb(row[4]),
          'service_name': row[5]?.toString() ?? 'Untitled',
          'price': row[6],
          'currency': row[7]?.toString() ?? 'USD',
          'description': row[8]?.toString() ?? '',
          'click_count_local': row[9] ?? 0,
          'is_active': row[10] ?? true,
          'created_at': row[11]?.toString() ?? '',
        }));
      }

      // Sort by timestamp in video
      stickers.sort((a, b) =>
          a.timestampInVideo.compareTo(b.timestampInVideo));

      return stickers;
    } catch (e) {
      debugPrint('Fetch Stickers Error: $e');
      return [];
    }
  }

  /// Adds a product sticker to a video for in-video placement.
  Future<String?> addProductSticker({
    required String videoId,
    required String productName,
    required double timestampInVideo,
    double? price,
    String currency = 'USD',
    String description = '',
    String? linkUrl,
    String? imagePath,
    ClickableZone? clickableZone,
  }) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('''
          INSERT INTO mp_sticker_products_catalog
            (video_id, product_id, timestamp_in_video, clickable_zone,
             product_name, price, currency, description, link_url,
             image_path, stock_status, is_active)
          VALUES (@vid, gen_random_uuid()::text, @ts, @zone, @name, @price,
                  @cur, @desc, @link, @img, 'in_stock', TRUE)
          RETURNING product_id
        '''),
        parameters: {
          'vid': videoId,
          'ts': timestampInVideo,
          'zone': clickableZone != null
              ? jsonEncode(clickableZone.toJson())
              : null,
          'name': productName,
          'price': price,
          'cur': currency,
          'desc': description,
          'link': linkUrl,
          'img': imagePath,
        },
      );
      await conn.close();
      if (result.isNotEmpty) {
        return result.first.first?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('Add Product Sticker Error: $e');
      return null;
    }
  }

  /// Adds a service sticker (e.g. booking/consultation) to a video.
  Future<String?> addServiceSticker({
    required String videoId,
    required String serviceName,
    required double timestampInVideo,
    double? price,
    String currency = 'USD',
    String description = '',
    ClickableZone? clickableZone,
  }) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('''
          INSERT INTO mp_sticker_services_catalog
            (video_id, service_id, timestamp_in_video, clickable_zone,
             service_name, price, currency, description, is_active)
          VALUES (@vid, gen_random_uuid()::text, @ts, @zone, @name, @price,
                  @cur, @desc, TRUE)
          RETURNING service_id
        '''),
        parameters: {
          'vid': videoId,
          'ts': timestampInVideo,
          'zone': clickableZone != null
              ? jsonEncode(clickableZone.toJson())
              : null,
          'name': serviceName,
          'price': price,
          'cur': currency,
          'desc': description,
        },
      );
      await conn.close();
      if (result.isNotEmpty) {
        return result.first.first?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('Add Service Sticker Error: $e');
      return null;
    }
  }

  /// Removes (deactivates) a sticker.
  Future<bool> removeSticker(String stickerId, String stickerType) async {
    try {
      final conn = await _connect();
      if (stickerType == 'product') {
        await conn.execute(
          Sql.named('''
            UPDATE mp_sticker_products_catalog
            SET is_active = FALSE
            WHERE product_id = @sid
          '''),
          parameters: {'sid': stickerId},
        );
      } else {
        await conn.execute(
          Sql.named('''
            UPDATE mp_sticker_services_catalog
            SET is_active = FALSE
            WHERE service_id = @sid
          '''),
          parameters: {'sid': stickerId},
        );
      }
      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Remove Sticker Error: $e');
      return false;
    }
  }

  /// Logs a click on a sticker for analytics tracking.
  Future<bool> logStickerClick(String stickerId, String stickerType) async {
    try {
      final conn = await _connect();
      if (stickerType == 'product') {
        await conn.execute(
          Sql.named('''
            UPDATE mp_sticker_products_catalog
            SET click_count_local = click_count_local + 1
            WHERE product_id = @sid
          '''),
          parameters: {'sid': stickerId},
        );
      } else {
        await conn.execute(
          Sql.named('''
            UPDATE mp_sticker_services_catalog
            SET booking_count_local = booking_count_local + 1
            WHERE service_id = @sid
          '''),
          parameters: {'sid': stickerId},
        );
      }
      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Log Sticker Click Error: $e');
      return false;
    }
  }

  // =========================================================================
  // EARNINGS DASHBOARD
  // =========================================================================

  /// Fetches monetization summary for a channel — total earnings, sales,
  /// clicks, and per-video breakdown.
  Future<Map<String, dynamic>> fetchChannelEarnings(String channelId) async {
    try {
      final conn = await _connect();

      // Aggregate product stats
      final productResult = await conn.execute(
        Sql.named('''
          SELECT
            COUNT(*) as total_stickers,
            COALESCE(SUM(click_count_local), 0) as total_clicks,
            COALESCE(SUM(purchase_initiated_count), 0) as total_initiated,
            COALESCE(SUM(purchase_completed_count), 0) as total_completed,
            COALESCE(SUM(price * purchase_completed_count), 0) as gross_revenue
          FROM mp_sticker_products_catalog spc
          JOIN mp_videos uv ON spc.video_id = uv.id::text
          WHERE uv.channel_id = @cid AND spc.is_active = TRUE
        '''),
        parameters: {'cid': channelId},
      );

      // Channel-level earnings
      final channelResult = await conn.execute(
        Sql.named('''
          SELECT total_earnings_local, monetization_enabled
          FROM mp_channels
          WHERE channel_id = @cid
        '''),
        parameters: {'cid': channelId},
      );

      await conn.close();

      double grossRevenue = 0;
      int totalClicks = 0;
      int totalCompleted = 0;
      int totalStickers = 0;
      double channelEarnings = 0;
      bool monetizationEnabled = false;

      if (productResult.isNotEmpty) {
        final row = productResult.first;
        totalStickers = (row[0] as int?) ?? 0;
        totalClicks = (row[1] as int?) ?? 0;
        totalCompleted = (row[3] as int?) ?? 0;
        grossRevenue = (row[4] as num?)?.toDouble() ?? 0.0;
      }

      if (channelResult.isNotEmpty) {
        final chRow = channelResult.first;
        channelEarnings = (chRow[0] as num?)?.toDouble() ?? 0.0;
        monetizationEnabled = (chRow[1] as bool?) ?? false;
      }

      return {
        'total_stickers': totalStickers,
        'total_clicks': totalClicks,
        'total_purchases': totalCompleted,
        'gross_revenue': grossRevenue,
        'channel_earnings': channelEarnings,
        'monetization_enabled': monetizationEnabled,
        'conversion_rate': totalClicks > 0
            ? (totalCompleted / totalClicks) * 100
            : 0.0,
      };
    } catch (e) {
      debugPrint('Fetch Channel Earnings Error: $e');
      return {
        'total_stickers': 0,
        'total_clicks': 0,
        'total_purchases': 0,
        'gross_revenue': 0.0,
        'channel_earnings': 0.0,
        'monetization_enabled': false,
        'conversion_rate': 0.0,
      };
    }
  }

  // =========================================================================
  // AD INTEGRATION POINTS
  // =========================================================================

  /// Fetches ad integration config for a channel. Returns default config
  /// if the channel hasn't customized ad settings.
  Future<Map<String, dynamic>> fetchAdSettings(String channelId) async {
    try {
      final conn = await _connect();

      // Ensure ad settings table exists
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mp_channel_ad_settings (
          channel_id TEXT PRIMARY KEY,
          pre_roll_enabled BOOLEAN DEFAULT FALSE,
          mid_roll_enabled BOOLEAN DEFAULT FALSE,
          post_roll_enabled BOOLEAN DEFAULT FALSE,
          ad_frequency_minutes INTEGER DEFAULT 10,
          skip_after_seconds INTEGER DEFAULT 5,
          min_subscribers_for_ads INTEGER DEFAULT 100,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');

      final result = await conn.execute(
        Sql.named('''
          SELECT pre_roll_enabled, mid_roll_enabled, post_roll_enabled,
                 ad_frequency_minutes, skip_after_seconds, min_subscribers_for_ads
          FROM mp_channel_ad_settings
          WHERE channel_id = @cid
        '''),
        parameters: {'cid': channelId},
      );
      await conn.close();

      if (result.isNotEmpty) {
        final row = result.first;
        return {
          'pre_roll_enabled': row[0] ?? false,
          'mid_roll_enabled': row[1] ?? false,
          'post_roll_enabled': row[2] ?? false,
          'ad_frequency_minutes': row[3] ?? 10,
          'skip_after_seconds': row[4] ?? 5,
          'min_subscribers_for_ads': row[5] ?? 100,
        };
      }

      // Defaults
      return {
        'pre_roll_enabled': false,
        'mid_roll_enabled': false,
        'post_roll_enabled': false,
        'ad_frequency_minutes': 10,
        'skip_after_seconds': 5,
        'min_subscribers_for_ads': 100,
      };
    } catch (e) {
      debugPrint('Fetch Ad Settings Error: $e');
      return {
        'pre_roll_enabled': false,
        'mid_roll_enabled': false,
        'post_roll_enabled': false,
        'ad_frequency_minutes': 10,
        'skip_after_seconds': 5,
        'min_subscribers_for_ads': 100,
      };
    }
  }

  /// Updates ad integration settings for a channel.
  Future<bool> updateAdSettings({
    required String channelId,
    required bool preRollEnabled,
    required bool midRollEnabled,
    required bool postRollEnabled,
    int adFrequencyMinutes = 10,
    int skipAfterSeconds = 5,
  }) async {
    try {
      final conn = await _connect();
      await conn.execute(
        Sql.named('''
          INSERT INTO mp_channel_ad_settings
            (channel_id, pre_roll_enabled, mid_roll_enabled,
             post_roll_enabled, ad_frequency_minutes, skip_after_seconds,
             updated_at)
          VALUES (@cid, @pre, @mid, @post, @freq, @skip, NOW())
          ON CONFLICT (channel_id) DO UPDATE SET
            pre_roll_enabled = @pre, mid_roll_enabled = @mid,
            post_roll_enabled = @post, ad_frequency_minutes = @freq,
            skip_after_seconds = @skip, updated_at = NOW()
        '''),
        parameters: {
          'cid': channelId,
          'pre': preRollEnabled,
          'mid': midRollEnabled,
          'post': postRollEnabled,
          'freq': adFrequencyMinutes,
          'skip': skipAfterSeconds,
        },
      );
      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Update Ad Settings Error: $e');
      return false;
    }
  }

  // =========================================================================
  // SUBSCRIPTION / MEMBERSHIP
  // =========================================================================

  /// Creates a membership tier for a channel (e.g. $4.99/month supporter).
  Future<String?> createMembershipTier({
    required String channelId,
    required String tierName,
    required double price,
    String currency = 'USD',
    String description = '',
    List<String> perks = const [],
  }) async {
    try {
      final conn = await _connect();
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mp_channel_membership_tiers (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          channel_id TEXT NOT NULL,
          tier_name TEXT NOT NULL,
          price DECIMAL NOT NULL,
          currency TEXT DEFAULT 'USD',
          description TEXT DEFAULT '',
          perks JSONB DEFAULT '[]',
          is_active BOOLEAN DEFAULT TRUE,
          subscriber_count INTEGER DEFAULT 0,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');

      final result = await conn.execute(
        Sql.named('''
          INSERT INTO mp_channel_membership_tiers
            (channel_id, tier_name, price, currency, description, perks)
          VALUES (@cid, @name, @price, @cur, @desc, @perks)
          RETURNING id
        '''),
        parameters: {
          'cid': channelId,
          'name': tierName,
          'price': price,
          'cur': currency,
          'desc': description,
          'perks': jsonEncode(perks),
        },
      );
      await conn.close();
      if (result.isNotEmpty) {
        return result.first.first?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('Create Membership Tier Error: $e');
      return null;
    }
  }

  /// Fetches all membership tiers for a channel.
  Future<List<Map<String, dynamic>>> fetchMembershipTiers(
      String channelId) async {
    try {
      final conn = await _connect();
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mp_channel_membership_tiers (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          channel_id TEXT NOT NULL,
          tier_name TEXT NOT NULL,
          price DECIMAL NOT NULL,
          currency TEXT DEFAULT 'USD',
          description TEXT DEFAULT '',
          perks JSONB DEFAULT '[]',
          is_active BOOLEAN DEFAULT TRUE,
          subscriber_count INTEGER DEFAULT 0,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');

      final result = await conn.execute(
        Sql.named('''
          SELECT id, tier_name, price, currency, description, perks,
                 subscriber_count, is_active
          FROM mp_channel_membership_tiers
          WHERE channel_id = @cid AND is_active = TRUE
          ORDER BY price ASC
        '''),
        parameters: {'cid': channelId},
      );
      await conn.close();

      final List<Map<String, dynamic>> tiers = [];
      for (final row in result) {
        tiers.add({
          'id': row[0]?.toString() ?? '',
          'tier_name': row[1]?.toString() ?? '',
          'price': (row[2] as num?)?.toDouble() ?? 0.0,
          'currency': row[3]?.toString() ?? 'USD',
          'description': row[4]?.toString() ?? '',
          'perks': _parseJsonb(row[5]),
          'subscriber_count': row[6] ?? 0,
          'is_active': row[7] ?? true,
        });
      }
      return tiers;
    } catch (e) {
      debugPrint('Fetch Membership Tiers Error: $e');
      return [];
    }
  }

  // =========================================================================
  // REVENUE ANALYTICS
  // =========================================================================

  /// Fetches revenue analytics for a channel across a date range.
  Future<Map<String, dynamic>> fetchRevenueAnalytics(
      String channelId, DateTime startDate, DateTime endDate) async {
    try {
      final earningsSummary = await fetchChannelEarnings(channelId);

      // Also fetch per-video sticker breakdown
      final conn = await _connect();
      final videoResult = await conn.execute(
        Sql.named('''
          SELECT uv.id, uv.title,
                 COUNT(spc.id) as sticker_count,
                 COALESCE(SUM(spc.click_count_local), 0) as clicks,
                 COALESCE(SUM(spc.purchase_completed_count), 0) as purchases,
                 COALESCE(SUM(spc.price * spc.purchase_completed_count), 0) as revenue
          FROM mp_videos uv
          LEFT JOIN mp_sticker_products_catalog spc ON spc.video_id = uv.id::text
          WHERE uv.channel_id = @cid AND uv.is_deleted = FALSE
          GROUP BY uv.id, uv.title
          ORDER BY revenue DESC
          LIMIT 10
        '''),
        parameters: {'cid': channelId},
      );
      await conn.close();

      final List<Map<String, dynamic>> topVideos = [];
      for (final row in videoResult) {
        topVideos.add({
          'video_id': row[0]?.toString() ?? '',
          'title': row[1]?.toString() ?? '',
          'sticker_count': row[2] ?? 0,
          'clicks': row[3] ?? 0,
          'purchases': row[4] ?? 0,
          'revenue': (row[5] as num?)?.toDouble() ?? 0.0,
        });
      }

      return {
        ...earningsSummary,
        'top_videos': topVideos,
        'date_range_start': startDate.toIso8601String(),
        'date_range_end': endDate.toIso8601String(),
      };
    } catch (e) {
      debugPrint('Fetch Revenue Analytics Error: $e');
      return {
        'total_stickers': 0,
        'total_clicks': 0,
        'total_purchases': 0,
        'gross_revenue': 0.0,
        'channel_earnings': 0.0,
        'monetization_enabled': false,
        'conversion_rate': 0.0,
        'top_videos': <Map<String, dynamic>>[],
      };
    }
  }

  // =========================================================================
  // SUPABASE SYNC
  // =========================================================================

  /// Syncs the local monetization status to the global Supabase feed so
  /// the network knows the channel has monetization enabled.
  Future<void> syncMonetizationToSupabase(
      String channelId, bool enabled) async {
    try {
      await Supabase.instance.client
          .from('mp_channels')
          .update({'monetization_enabled': enabled})
          .match({'channel_id': channelId});
    } catch (e) {
      debugPrint('Sync Monetization to Supabase Error: $e');
    }
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  dynamic _parseJsonb(dynamic value) {
    if (value == null) return null;
    if (value is String && value.isNotEmpty) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    return value;
  }
}
