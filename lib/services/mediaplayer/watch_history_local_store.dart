import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/mediaplayer/player_video_model.dart';

/// 🚀 LOCAL APPEND-ONLY WATCH HISTORY
///
/// The backend Docker gateway de-duplicates watch history by `video_id`,
/// keeping only the *latest* `watch_timestamp`. That means a video watched
/// yesterday and again today would "move" out of Yesterday and into Today,
/// disappearing from the day it was first watched.
///
/// To preserve the user's mental model ("if I watched it yesterday it stays in
/// yesterday, and if I watch it again today it also shows in today"), we keep
/// our own append-only log on the device. Every watch event is recorded with
/// its own timestamp, so the same video can legitimately appear on multiple
/// days. The home screen merges this local log with the backend history.
class WatchHistoryLocalStore {
  static const String _key = 'guptik_watch_history_log_v1';

  /// Records a watch event for [video] at [timestamp].
  ///
  /// This is purely additive: it never removes or overwrites an earlier entry
  /// for the same video, which is what allows a video to remain in both the
  /// day it was first watched and any later day it is re-watched.
  static Future<void> recordWatch(PlayerVideo video, DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];

      final entry = {
        'video': video.toJson(),
        'watched_at': timestamp.toIso8601String(),
      };
      raw.add(jsonEncode(entry));

      // Bound the log so it can't grow without limit (keep newest 2000 events).
      final trimmed = raw.length > 2000 ? raw.sublist(raw.length - 2000) : raw;
      await prefs.setStringList(_key, trimmed);
    } catch (e) {
      debugPrint('WatchHistoryLocalStore.recordWatch error: $e');
    }
  }

  /// Returns all locally recorded watch events, newest first.
  static Future<List<WatchHistoryEntry>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      final entries = raw.map((s) {
        final map = jsonDecode(s) as Map<String, dynamic>;
        final video = PlayerVideo.fromJson(
          map['video'] as Map<String, dynamic>,
          (map['video'] as Map<String, dynamic>)['creator_url']?.toString() ?? '',
        );
        final ts = DateTime.tryParse(map['watched_at'] as String) ?? DateTime.now();
        return WatchHistoryEntry(video: video, watchedAt: ts);
      }).toList();
      entries.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
      return entries;
    } catch (e) {
      debugPrint('WatchHistoryLocalStore.getAll error: $e');
      return [];
    }
  }

  /// Clears the entire local watch log.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      debugPrint('WatchHistoryLocalStore.clear error: $e');
    }
  }
}

class WatchHistoryEntry {
  final PlayerVideo video;
  final DateTime watchedAt;
  const WatchHistoryEntry({required this.video, required this.watchedAt});
}