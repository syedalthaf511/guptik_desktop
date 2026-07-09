import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/mediaplayer/player_comment_model.dart';

/// PlayerCommentService — Advanced comment system service.
/// Handles nested replies, reactions, editing, deletion, and reporting
/// by communicating with the creator's local Docker gateway API and
/// falling back to direct Postgres access when needed.
class PlayerCommentService {
  final String? gatewayUrl;

  PlayerCommentService({this.gatewayUrl});

  String get _safeUrl {
    if (gatewayUrl == null) return '';
    return gatewayUrl!.startsWith('http')
        ? gatewayUrl!
        : 'https://$gatewayUrl';
  }

  // =========================================================================
  // READ OPERATIONS
  // =========================================================================

  /// Fetches all top-level comments for a video, each with nested replies.
  /// Returns an empty list on failure so the UI can degrade gracefully.
  Future<List<PlayerComment>> fetchComments(String videoId,
      {String? viewerUid}) async {
    if (gatewayUrl == null) return [];
    try {
      final uri = Uri.parse('$_safeUrl/player/video/comments/$videoId');
      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        if (viewerUid != null) 'X-Viewer-Uid': viewerUid,
      });

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is List) {
          return body
              .map((c) => PlayerComment.fromJson(c as Map<String, dynamic>))
              .toList();
        }
        // Some gateways wrap in {"comments": [...]}
        if (body is Map && body['comments'] is List) {
          return (body['comments'] as List)
              .map((c) => PlayerComment.fromJson(c as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Fetch Comments Error: $e');
      return [];
    }
  }

  /// Fetches replies for a specific parent comment.
  Future<List<PlayerComment>> fetchReplies(
      String videoId, String parentCommentId,
      {String? viewerUid}) async {
    if (gatewayUrl == null) return [];
    try {
      final uri = Uri.parse(
          '$_safeUrl/player/video/comments/$videoId/replies/$parentCommentId');
      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        if (viewerUid != null) 'X-Viewer-Uid': viewerUid,
      });

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is List) {
          return body
              .map((c) => PlayerComment.fromJson(c as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Fetch Replies Error: $e');
      return [];
    }
  }

  // =========================================================================
  // WRITE OPERATIONS
  // =========================================================================

  /// Posts a new top-level comment or a reply (when parentCommentId is set).
  Future<bool> postComment(
    String videoId,
    String creatorUid,
    String commentText, {
    String? parentCommentId,
    bool isIncognito = false,
    String? viewerName,
  }) async {
    if (gatewayUrl == null) return false;
    try {
      final response = await http.post(
        Uri.parse('$_safeUrl/player/video/comment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'video_id': videoId,
          'creator_uid': creatorUid,
          'comment_text': commentText,
          if (parentCommentId != null)
            'parent_comment_id': parentCommentId,
          'is_incognito': isIncognito,
          if (viewerName != null) 'viewer_name': viewerName,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Post Comment Error: $e');
      return false;
    }
  }

  /// Edits an existing comment (only by the original author).
  Future<bool> editComment(
      String commentId, String newText, String editorUid) async {
    if (gatewayUrl == null) return false;
    try {
      final response = await http.put(
        Uri.parse('$_safeUrl/player/video/comment/$commentId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'comment_text': newText,
          'editor_uid': editorUid,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Edit Comment Error: $e');
      return false;
    }
  }

  /// Soft-deletes a comment (marks as deleted, preserves thread integrity).
  Future<bool> deleteComment(String commentId, String deleterUid) async {
    if (gatewayUrl == null) return false;
    try {
      final response = await http.delete(
        Uri.parse('$_safeUrl/player/video/comment/$commentId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'deleter_uid': deleterUid}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Delete Comment Error: $e');
      return false;
    }
  }

  // =========================================================================
  // REACTIONS
  // =========================================================================

  /// Toggles a reaction on a comment. Returns the new reaction type (or null
  /// if the reaction was removed) so the UI can update optimistically.
  Future<String?> toggleCommentReaction({
    required String commentId,
    required String reactorUid,
    required String reactionType, // 'like', 'heart', 'clap', 'laugh', 'disagree'
  }) async {
    if (gatewayUrl == null) return null;
    try {
      final response = await http.post(
        Uri.parse('$_safeUrl/player/video/comment/$commentId/react'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'reactor_uid': reactorUid,
          'reaction_type': reactionType,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Server returns {"active": true, "reaction_type": "heart"}
        // or {"active": false, "reaction_type": null} when toggled off
        if (data['active'] == true) {
          return data['reaction_type']?.toString();
        }
      }
      return null;
    } catch (e) {
      debugPrint('Comment Reaction Error: $e');
      return null;
    }
  }

  // =========================================================================
  // REPORTING / MODERATION
  // =========================================================================

  /// Reports a comment for moderation. The report is stored with a reason
  /// and flagged for the channel owner / admin review.
  Future<bool> reportComment({
    required String commentId,
    required String reporterUid,
    required String reason,
    String? additionalDetails,
  }) async {
    if (gatewayUrl == null) return false;
    try {
      final response = await http.post(
        Uri.parse('$_safeUrl/player/video/comment/$commentId/report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'reporter_uid': reporterUid,
          'reason': reason,
          if (additionalDetails != null)
            'details': additionalDetails,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Report Comment Error: $e');
      return false;
    }
  }

  /// Hides a comment (moderator action by channel owner).
  Future<bool> hideComment(String commentId, String moderatorUid) async {
    if (gatewayUrl == null) return false;
    try {
      final response = await http.post(
        Uri.parse('$_safeUrl/player/video/comment/$commentId/hide'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'moderator_uid': moderatorUid}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Hide Comment Error: $e');
      return false;
    }
  }
}