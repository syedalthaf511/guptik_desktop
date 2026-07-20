import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import '../../services/external/postgres_service.dart';

/// PlayerWatcherInterestService — Tracks whether a watcher is interested or
/// not interested in a specific video. Persists to the local user-side
/// Postgres `mp_watcher_interest` table.
///
/// This drives the recommendation profile ("Not Interested" feedback loop) and
/// lets us stop surfacing a video the watcher dismissed.
class PlayerWatcherInterestService {
  final String _localDbHost = '127.0.0.1';
  final int _localDbPort = 55432;
  final String _dbName = 'postgres';
  final String _dbUser = 'postgres';
  final String _dbPass = PostgresService.dockerMasterPassword;

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

  /// Ensures the watcher-interest table exists before we query it. The global
  /// init in postgres_service/docker_service may not have run in this session,
  /// so we self-heal to avoid `42P01: relation does not exist`.
  Future<void> _ensureTable(Connection conn) async {
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_watcher_interest (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id TEXT NOT NULL,
        creator_uid TEXT,
        watcher_uid TEXT NOT NULL,
        interest TEXT NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE (video_id, watcher_uid)
      )
    ''');
    await conn.execute(
      'CREATE INDEX IF NOT EXISTS idx_mp_watcher_interest_watcher '
      'ON mp_watcher_interest(watcher_uid)',
    );
  }

  /// Records the watcher's interest level for a video.
  /// [interest] is 'interested' or 'not_interested'. Pass null/empty to clear
  /// the feedback (deletes the row so the watcher has no recorded preference).
  /// Uses upsert (ON CONFLICT) so a watcher can change their mind.
  Future<bool> setInterest({
    required String videoId,
    String? creatorUid,
    required String watcherUid,
    String? interest,
  }) async {
    try {
      final conn = await _connect();
      await _ensureTable(conn);
      if (interest == null || interest.isEmpty) {
        // Clear: remove the row so the watcher has no recorded preference.
        await conn.execute(
          Sql.named('''
            DELETE FROM mp_watcher_interest
            WHERE video_id = @vid AND watcher_uid = @wuid
          '''),
          parameters: {'vid': videoId, 'wuid': watcherUid},
        );
      } else {
        await conn.execute(
          Sql.named('''
            INSERT INTO mp_watcher_interest
              (video_id, creator_uid, watcher_uid, interest)
            VALUES (@vid, @cuid, @wuid, @interest)
            ON CONFLICT (video_id, watcher_uid)
            DO UPDATE SET interest = @interest, created_at = NOW()
          '''),
          parameters: {
            'vid': videoId,
            'cuid': creatorUid,
            'wuid': watcherUid,
            'interest': interest,
          },
        );
      }
      await conn.close();
      return true;
    } catch (e) {
      debugPrint('Set Watcher Interest Error: $e');
      return false;
    }
  }

  /// Marks a video as "not interested" for the watcher.
  Future<bool> markNotInterested({
    required String videoId,
    String? creatorUid,
    required String watcherUid,
  }) async {
    return setInterest(
      videoId: videoId,
      creatorUid: creatorUid,
      watcherUid: watcherUid,
      interest: 'not_interested',
    );
  }

  /// Marks a video as "interested" for the watcher.
  Future<bool> markInterested({
    required String videoId,
    String? creatorUid,
    required String watcherUid,
  }) async {
    return setInterest(
      videoId: videoId,
      creatorUid: creatorUid,
      watcherUid: watcherUid,
      interest: 'interested',
    );
  }

  /// Clears any interest feedback the watcher gave for this video.
  Future<bool> clearInterest({
    required String videoId,
    required String watcherUid,
  }) async {
    return setInterest(
      videoId: videoId,
      watcherUid: watcherUid,
      interest: null,
    );
  }

  /// Fetches the interest record for a given watcher + video.
  /// Returns null if the watcher hasn't expressed any interest yet.
  /// Possible return values: 'interested', 'not_interested'.
  Future<String?> getInterest({
    required String videoId,
    required String watcherUid,
  }) async {
    try {
      final conn = await _connect();
      await _ensureTable(conn);
      final result = await conn.execute(
        Sql.named('''
          SELECT interest FROM mp_watcher_interest
          WHERE video_id = @vid AND watcher_uid = @wuid
          LIMIT 1
        '''),
        parameters: {'vid': videoId, 'wuid': watcherUid},
      );
      await conn.close();
      if (result.isEmpty) return null;
      return result.first.first?.toString();
    } catch (e) {
      debugPrint('Get Watcher Interest Error: $e');
      return null;
    }
  }

  /// Returns all video_ids the watcher marked as not_interested.
  /// Useful to filter them out of the feed locally.
  Future<Set<String>> notInterestedVideoIds(String watcherUid) async {
    try {
      final conn = await _connect();
      await _ensureTable(conn);
      final result = await conn.execute(
        Sql.named('''
          SELECT video_id FROM mp_watcher_interest
          WHERE watcher_uid = @wuid AND interest = 'not_interested'
        '''),
        parameters: {'wuid': watcherUid},
      );
      await conn.close();
      return result.map((row) => row.first.toString()).toSet();
    } catch (e) {
      debugPrint('Fetch Not Interested Error: $e');
      return {};
    }
  }
}