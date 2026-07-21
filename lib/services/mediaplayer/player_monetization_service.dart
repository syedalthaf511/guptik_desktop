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
  ///
  /// Stickers are stored in a SHARED Supabase Storage location so that ANY
  /// viewer (not just the creator) can see them — this is what makes a
  /// sticker added by user A appear for user B. We fall back to the creator's
  /// local Postgres node only if the shared store is unavailable.
  Future<List<VideoSticker>> fetchStickers(String videoId) async {
    // 1) Preferred: shared store (visible to every viewer).
    final shared = await fetchStickersShared(videoId);
    if (shared.isNotEmpty) return shared;

    // 2) Fallback: local Postgres (creator-only visibility).
    return _fetchStickersLocal(videoId);
  }

  /// Reads sticker metadata from the shared Supabase Storage JSON blob
  /// (`post_images/sticker_data/<videoId>.json`). Works cross-user because
  /// the bucket is public.
  Future<List<VideoSticker>> fetchStickersShared(String videoId) async {
    try {
      final supabase = Supabase.instance.client;
      final path = 'sticker_data/$videoId.json';
      final bytes = await supabase.storage.from('post_images').download(path);
      if (bytes == null || bytes.isEmpty) return [];
      final jsonStr = utf8.decode(bytes);
      final list = jsonDecode(jsonStr) as List;
      final stickers = list
          .map((e) => VideoSticker.fromJson(e as Map<String, dynamic>))
          .toList();
      stickers.sort((a, b) =>
          a.timestampInVideo.compareTo(b.timestampInVideo));
      return stickers;
    } catch (e) {
      debugPrint('Fetch Shared Stickers Error: $e');
      return [];
    }
  }

  /// Local-only fallback (creator's own node). Kept for offline/legacy support.
  Future<List<VideoSticker>> _fetchStickersLocal(String videoId) async {
    try {
      final conn = await _connect();

      // Ensure the catalog supports the new shoppable columns before we
      // SELECT them. Without this, a video with stickers but a table that
      // lacks `mrp`/`duration_on_screen` throws 42703 and returns no
      // stickers (so nothing shows in the player).
      await conn.execute('''
        ALTER TABLE mp_sticker_products_catalog
          ADD COLUMN IF NOT EXISTS mrp DECIMAL DEFAULT 0,
          ADD COLUMN IF NOT EXISTS duration_on_screen DECIMAL DEFAULT 8
      ''');

      // Products
      final productResult = await conn.execute(
        Sql.named('''
          SELECT id, video_id, product_id, timestamp_in_video, clickable_zone,
                 product_name, price, mrp, currency, description, link_url,
                 image_path, stock_status, sales_count_local,
                 click_count_local, purchase_initiated_count,
                 purchase_completed_count, is_active, created_at, updated_at,
                 duration_on_screen
          FROM mp_sticker_products_catalog
          WHERE video_id::text = @vid AND is_active = TRUE
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
          WHERE video_id::text = @vid AND is_active = TRUE
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
          'mrp': row[7],
          'currency': row[8]?.toString() ?? 'USD',
          'description': row[9]?.toString() ?? '',
          'link_url': row[10]?.toString(),
          'image_path': row[11]?.toString(),
          'stock_status': row[12]?.toString() ?? 'in_stock',
          'sales_count_local': row[13] ?? 0,
          'click_count_local': row[14] ?? 0,
          'purchase_initiated_count': row[15] ?? 0,
          'purchase_completed_count': row[16] ?? 0,
          'is_active': row[17] ?? true,
          'created_at': row[18]?.toString() ?? '',
          'updated_at': row[19]?.toString() ?? '',
          'duration_on_screen': row[20] ?? 8,
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
      debugPrint('Fetch Stickers (local) Error: $e');
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
    double mrp = 0,
    double durationOnScreen = 8,
  }) async {
    try {
      final conn = await _connect();
      // Ensure the catalog supports the new shoppable columns.
      await conn.execute('''
        ALTER TABLE mp_sticker_products_catalog
          ADD COLUMN IF NOT EXISTS mrp DECIMAL DEFAULT 0,
          ADD COLUMN IF NOT EXISTS duration_on_screen DECIMAL DEFAULT 8
      ''');
      final result = await conn.execute(
        Sql.named('''
          INSERT INTO mp_sticker_products_catalog
            (video_id, product_id, timestamp_in_video, duration_on_screen,
             clickable_zone, product_name, price, mrp, currency, description,
             link_url, image_path, stock_status, is_active)
          VALUES (@vid, gen_random_uuid()::text, @ts, @dur, @zone, @name,
                   @price, @mrp, @cur, @desc, @link, @img, 'in_stock', TRUE)
          RETURNING product_id
        '''),
        parameters: {
          'vid': videoId,
          'ts': timestampInVideo,
          'dur': durationOnScreen,
          'zone': clickableZone != null
              ? jsonEncode(clickableZone.toJson())
              : null,
          'name': productName,
          'price': price,
          'mrp': mrp,
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

  /// Adds a product sticker and makes it visible to EVERY viewer (not just the
  /// creator) by storing it in the shared Supabase Storage location. The image
  /// bytes are uploaded to the public `post_images` bucket and the metadata is
  /// written to `sticker_data/<videoId>.json`. We also mirror to the creator's
  /// local Postgres node so existing analytics/dashboards keep working.
  ///
  /// [imageBytes] are the (optionally bg-removed) PNG bytes of the sticker.
  Future<String?> addProductStickerShared({
    required String videoId,
    required String productName,
    required double timestampInVideo,
    required Uint8List? imageBytes,
    double? price,
    String currency = 'USD',
    String description = '',
    String? linkUrl,
    ClickableZone? clickableZone,
    double mrp = 0,
    double durationOnScreen = 8,
  }) async {
    final stickerId = DateTime.now().millisecondsSinceEpoch.toString();

    // 1) Upload image to shared storage (public URL any viewer can load).
    String? imageUrl = await _uploadStickerImage(videoId, imageBytes);

    // 2) Build the sticker record.
    final sticker = VideoSticker(
      id: stickerId,
      videoId: videoId,
      productId: stickerId,
      title: productName,
      timestampInVideo: timestampInVideo,
      durationOnScreen: durationOnScreen,
      salePrice: price ?? 0,
      mrp: mrp,
      currency: currency,
      description: description,
      linkUrl: linkUrl,
      imagePath: imageUrl, // now a public URL, not a local path
      clickableZone: clickableZone,
      isActive: true,
      stickerType: 'product',
    );

    // 3) Persist to the shared JSON blob (append to existing list).
    await _appendSharedSticker(videoId, sticker);

    // 4) Mirror to local Postgres for creator-side analytics (best effort).
    await addProductSticker(
      videoId: videoId,
      productName: productName,
      timestampInVideo: timestampInVideo,
      price: price,
      currency: currency,
      description: description,
      linkUrl: linkUrl,
      imagePath: imageUrl,
      clickableZone: clickableZone,
      mrp: mrp,
      durationOnScreen: durationOnScreen,
    );

    return stickerId;
  }

  /// Uploads sticker image bytes to the public `post_images` bucket and
  /// returns the public URL. Returns null if upload fails.
  Future<String?> _uploadStickerImage(String videoId, Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final supabase = Supabase.instance.client;
      final fileName =
          'sticker_data/$videoId/${DateTime.now().millisecondsSinceEpoch}.png';
      await supabase.storage.from('post_images').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
                upsert: true, contentType: 'image/png'),
          );
      return supabase.storage.from('post_images').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Sticker image upload error: $e');
      return null;
    }
  }

  /// Appends a sticker to the shared `sticker_data/<videoId>.json` blob,
  /// creating it if it doesn't exist.
  Future<void> _appendSharedSticker(String videoId, VideoSticker sticker) async {
    try {
      final supabase = Supabase.instance.client;
      final path = 'sticker_data/$videoId.json';

      // Read existing list (if any).
      List<dynamic> list = [];
      try {
        final existing = await supabase.storage.from('post_images').download(path);
        if (existing != null && existing.isNotEmpty) {
          list = jsonDecode(utf8.decode(existing)) as List;
        }
      } catch (_) {
        // No existing blob yet — start fresh.
      }

      list.add(sticker.toJson());
      final encoded = utf8.encode(jsonEncode(list));
      await supabase.storage.from('post_images').uploadBinary(
            path,
            encoded,
            fileOptions: const FileOptions(
                upsert: true, contentType: 'application/json'),
          );
    } catch (e) {
      debugPrint('Append shared sticker error: $e');
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
          JOIN mp_videos uv ON spc.video_id = uv.id
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
        totalStickers = _toInt(row[0]);
        totalClicks = _toInt(row[1]);
        totalCompleted = _toInt(row[3]);
        grossRevenue = _toDouble(row[4]);
      }

      if (channelResult.isNotEmpty) {
        final chRow = channelResult.first;
        channelEarnings = _toDouble(chRow[0]);
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
          LEFT JOIN mp_sticker_products_catalog spc ON spc.video_id = uv.id
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
          'sticker_count': _toInt(row[2]),
          'clicks': _toInt(row[3]),
          'purchases': _toInt(row[4]),
          'revenue': _toDouble(row[5]),
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

  /// Safely converts a Postgres numeric/int column to int. The `postgres`
  /// package returns DECIMAL/numeric columns as Strings, so a direct
  /// `(value as num)` cast would throw. Handles int, num, and String.
  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  /// Safely converts a Postgres numeric/int column to double. Same rationale
  /// as [_toInt] — numeric columns arrive as Strings from the driver.
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
