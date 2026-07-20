import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/external/postgres_service.dart';

/// PlayerReportService — Lets a watcher report a video for policy violations
/// (spam, harassment, nudity, etc.).
///
/// Writes the report to the LOCAL user-side `mp_reports` table AND mirrors it
/// to the admin-side Supabase `mp_reports` table so admins can review it in the
/// reports section.
class PlayerReportService {
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

  /// Files a report. [type] is the report category (e.g. 'spam', 'nudity',
  /// 'harassment', 'misinformation', 'copyright', 'other').
  /// Returns true if the local record was created (admin sync is best-effort).
  Future<bool> fileReport({
    required String byUser,
    required String videoId,
    required String type,
    String? description,
    String? imageUrl,
  }) async {
    try {
      // 1. Persist locally so the user can see "My Reports" and we can retry
      // the admin sync if it fails (offline / network error).
      final conn = await _connect();
      await conn.execute(
        Sql.named('''
          INSERT INTO mp_reports
            (by_user, video_id, type, description, image_url, status, synced_to_admin)
          VALUES (@by, @vid, @type, @desc, @img, 'new', FALSE)
          ON CONFLICT DO NOTHING
        '''),
        parameters: {
          'by': byUser,
          'vid': videoId,
          'type': type,
          'desc': description,
          'img': imageUrl,
        },
      );
      await conn.close();

      // 2. Best-effort mirror to admin Supabase. We do NOT block the UI on this;
      // if it fails the local row stays synced_to_admin=FALSE and a later retry
      // can push it up.
      await _syncToAdmin(
        byUser: byUser,
        videoId: videoId,
        type: type,
        description: description,
        imageUrl: imageUrl,
      );

      return true;
    } catch (e) {
      debugPrint('File Report Error: $e');
      return false;
    }
  }

  /// Pushes a report row up to the admin Supabase `mp_reports` table.
  Future<void> _syncToAdmin({
    required String byUser,
    required String videoId,
    required String type,
    String? description,
    String? imageUrl,
  }) async {
    try {
      await Supabase.instance.client.from('mp_reports').insert({
        'by_user': byUser,
        'video_id': videoId,
        'type': type,
        'description': description,
        'image_url': imageUrl,
        'status': 'new',
      });

      // Mark the local row as synced so we don't re-push it later.
      try {
        final conn = await _connect();
        await conn.execute(
          Sql.named('''
            UPDATE mp_reports
            SET synced_to_admin = TRUE, status = 'submitted', updated_at = NOW()
            WHERE by_user = @by AND video_id = @vid AND type = @type
          '''),
          parameters: {'by': byUser, 'vid': videoId, 'type': type},
        );
        await conn.close();
      } catch (_) {}
    } catch (e) {
      debugPrint('Admin report sync (non-fatal): $e');
    }
  }

  /// Fetches all reports filed by this user from the local table.
  Future<List<Map<String, dynamic>>> myReports(String watcherUid) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('''
          SELECT id, video_id, type, description, image_url, status,
                 synced_to_admin, created_at, updated_at
          FROM mp_reports
          WHERE by_user = @by
          ORDER BY created_at DESC
        '''),
        parameters: {'by': watcherUid},
      );
      await conn.close();
      return result.map((row) => row.toColumnMap()).toList();
    } catch (e) {
      debugPrint('Fetch My Reports Error: $e');
      return [];
    }
  }

  /// Retries syncing any locally-stored reports that failed to reach admin.
  /// Useful to call on app start so reports filed while offline get pushed.
  Future<void> retryUnsyncedReports(String watcherUid) async {
    try {
      final conn = await _connect();
      final result = await conn.execute(
        Sql.named('''
          SELECT video_id, type, description, image_url
          FROM mp_reports
          WHERE by_user = @by AND synced_to_admin = FALSE
        '''),
        parameters: {'by': watcherUid},
      );
      await conn.close();

      for (final row in result) {
        await _syncToAdmin(
          byUser: watcherUid,
          videoId: row[0]?.toString() ?? '',
          type: row[1]?.toString() ?? 'other',
          description: row[2]?.toString(),
          imageUrl: row[3]?.toString(),
        );
      }
    } catch (e) {
      debugPrint('Retry Unsynced Reports Error: $e');
    }
  }
}