import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/mediaplayer/player_video_model.dart';

class PlayerApiService {
  // The specific Cloudflare Tunnel URL or Localhost IP for the creator's node
  final String? gatewayUrl;

  PlayerApiService({this.gatewayUrl});

  // =========================================================================
  // 🚀 GLOBAL DIRECTORY: Fetch Feed from Admin Supabase Cloud
  // =========================================================================
  
  /// Fetches the global feed of all published videos across the network.
  /// This talks to the central Supabase database, NOT the individual nodes.
  Future<List<PlayerVideo>> fetchNetworkFeed() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Query the global mp_videos table, sorted by newest first
      final response = await supabase
          .from('mp_videos')
          .select()
          .order('published_at', ascending: false);
      
      // Map the JSON response to our strict PlayerVideo model.
      // We pass 'creator_cloudflare_url' so the UI knows exactly which node to stream from.
      return (response as List)
          .map((v) => PlayerVideo.fromJson(v, v['creator_cloudflare_url']))
          .toList();
    } catch (e) {
      debugPrint("Feed fetch error: $e");
      return [];
    }
  }

  // =========================================================================
  // 🚀 PEER-TO-PEER ENGAGEMENT: Talks directly to Creator's Docker Gateway
  // =========================================================================
  
  // -------------------------------------------------------------------------
  // WRITE OPERATIONS (POST)
  // -------------------------------------------------------------------------

 /// Sends a reaction (Heart, Fire, Clap, etc.) to the creator's local Postgres.
  Future<bool> postReaction(String videoId, String creatorUid, String reactionType) async {
    if (gatewayUrl == null) return false;
    
    try {
      // Ensure the URL is safely formatted (adds https:// if missing from Cloudflare tunnels)
      final safeUrl = gatewayUrl!.startsWith('http') ? gatewayUrl : 'https://$gatewayUrl';
      
      final response = await http.post(
        Uri.parse('$safeUrl/player/video/like'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'video_id': videoId, 
          'creator_uid': creatorUid, 
          'reaction_type': reactionType
        }),
      );

      if (response.statusCode == 200) {
        // 🚀 THE FIX: Read the actual message from Docker!
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'already_liked') {
          debugPrint('✋ Server blocked duplicate like. UI will stay frozen.');
          return false; // Tell Flutter NOT to add a point on the screen
        }
        
        return true; // It was a brand new like, go ahead and update the UI!
      }
      return false;
    } catch (e) { 
      debugPrint('Reaction Error: $e');
      return false; 
    }
  }

  /// Submits a new text comment to the creator's local node.
  Future<bool> postComment(String videoId, String creatorUid, String commentText) async {
    if (gatewayUrl == null) return false;
    try {
      final response = await http.post(
        Uri.parse('$gatewayUrl/player/video/comment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'video_id': videoId, 'creator_uid': creatorUid, 'comment_text': commentText}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  /// Silently logs how much of the video the user watched upon closing the player.
  Future<bool> logWatchHistory(String videoId, String creatorUid, int duration, double percent, String sessionId) async {
    if (gatewayUrl == null) return false;
    try {
      final response = await http.post(
        Uri.parse('$gatewayUrl/player/video/history'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'video_id': videoId,
          'creator_uid': creatorUid,
          'watch_duration_seconds': duration,
          'percent_completed': percent,
          'session_id': sessionId,
        }),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  /// Triggers the node to add this video to the user's saved/bookmarked table.
  Future<bool> saveVideo(String videoId, String creatorUid) async {
    if (gatewayUrl == null) return false;
    try {
      final response = await http.post(
        Uri.parse('$gatewayUrl/player/video/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'video_id': videoId, 'creator_uid': creatorUid}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  // -------------------------------------------------------------------------
  // READ OPERATIONS (GET) - 🚀 ADDED TO COMPLETE SPRINT 3
  // -------------------------------------------------------------------------

  /// Fetches the list of comments for a specific video directly from the node.
  /// Used to populate the Comment Dialog UI.
  Future<List<dynamic>> fetchComments(String videoId) async {
    if (gatewayUrl == null) return [];
    try {
      final response = await http.get(
        Uri.parse('$gatewayUrl/player/video/comments/$videoId'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        // Decode the JSON list of comments returned by the Gateway
        return jsonDecode(response.body) as List<dynamic>;
      }
      return [];
    } catch (e) {
      debugPrint('Fetch Comments Error: $e');
      return [];
    }
  }

  /// Fetches the real-time like, comment, and save counts from the Docker Node
  Future<Map<String, dynamic>?> fetchVideoStats(String videoId) async {
    if (gatewayUrl == null) return null;
    try {
      final response = await http.get(
        Uri.parse('$gatewayUrl/player/video/stats/$videoId'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Fetch Stats Error: $e');
      return null;
    }
  }

  // 🚀 FIXED: Tells Docker who is watching, and syncs to Supabase Home Screen!
  Future<void> addVideoView(String videoId, String viewerUid) async {
    if (gatewayUrl == null) return;
    try {
      final safeUrl = gatewayUrl!.startsWith('http') ? gatewayUrl : 'https://$gatewayUrl';
      
      // 1. Tell Docker about the view and pass the User ID for the Gatekeeper
      final response = await http.post(
        Uri.parse('$safeUrl/player/video/view'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'video_id': videoId,
          'viewer_uid': viewerUid 
        }),
      );

      final data = jsonDecode(response.body);
      
      // 2. If Docker accepted it as a brand new unique view, TELL SUPABASE!
      if (data['status'] == 'view_added') {
         await Supabase.instance.client.rpc('increment_video_view', params: {'vid': videoId});
      }
      
    } catch (e) {
      debugPrint('View Count Error: $e');
    }
  }
  
  // =========================================================================
  // 🚀 CREATOR CHANNEL PROFILE
  // =========================================================================

  /// Fetches the channel bio, name, and subscriber count from a specific node
  Future<Map<String, dynamic>?> fetchChannelProfile(String nodeUrl, String channelId) async {
    try {
      // 🚀 THE FIX: Check if it's missing https:// and add it!
      final safeUrl = nodeUrl.startsWith('http') ? nodeUrl : 'https://$nodeUrl';
      
      final response = await http.get(Uri.parse('$safeUrl/channel/profile/$channelId'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Profile Fetch Error: $e');
      return null;
    }
  }

 /// Fetches all videos hosted on a specific creator's node
  Future<List<PlayerVideo>> fetchChannelVideos(String nodeUrl, String channelId) async {
    try {
      final safeUrl = nodeUrl.startsWith('http') ? nodeUrl : 'https://$nodeUrl';
      
      final response = await http.get(Uri.parse('$safeUrl/channel/videos/$channelId'));
      
      // 🚀 NEW: Print exactly what Docker tells Flutter!
      debugPrint('📡 DOCKER RESPONSE CODE: ${response.statusCode}');
      debugPrint('📡 DOCKER RESPONSE BODY: ${response.body}');
      
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((v) => PlayerVideo.fromJson(v, safeUrl)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Channel Videos Error: $e');
      return [];
    }
 }


// 🚀 NEW: Delete Video Method
  Future<bool> deleteVideo(String videoId, String creatorUid) async {
    if (gatewayUrl == null) return false;
    try {
      final safeUrl = gatewayUrl!.startsWith('http') ? gatewayUrl : 'https://$gatewayUrl';
      final response = await http.post(
        Uri.parse('$safeUrl/player/video/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'video_id': videoId, 'creator_uid': creatorUid}),
      );
      
      if (response.statusCode == 200) {
        // Also wipe it from the Global Supabase Feed so nobody else can see it!
        await Supabase.instance.client.from('mp_videos').delete().match({'video_id': videoId});
        return true;
      }
      return false;
    } catch (e) { return false; }
  }

  

 // -------------------------------------------------------------------------
  // 🚀 NEW: SUBSCRIPTION MANAGEMENT
  // -------------------------------------------------------------------------

  /// Checks if the current user is subscribed to this creator's node
  Future<bool> checkSubscriptionStatus(String nodeUrl, String channelId, String subscriberUid) async {
    try {
      final safeUrl = nodeUrl.startsWith('http') ? nodeUrl : 'https://$nodeUrl';
      final response = await http.get(Uri.parse('$safeUrl/channel/subscribe/status/$channelId/$subscriberUid'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['is_subscribed'] ?? false;
      }
    } catch (e) { 
      debugPrint('Sub Check Error: $e'); 
    }
    return false;
  }

 /// Toggles the subscription on the creator's node AND syncs to Admin Supabase
  Future<bool?> toggleSubscription(String nodeUrl, String channelId, String subscriberUid) async {
    try {
      final safeUrl = nodeUrl.startsWith('http') ? nodeUrl : 'https://$nodeUrl';
      
      // 1. Tell the Local Docker Node
      final response = await http.post(
        Uri.parse('$safeUrl/channel/subscribe/toggle'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'channel_id': channelId, 'subscriber_uid': subscriberUid})
      );

      if (response.statusCode == 200) {
        final isSubscribed = jsonDecode(response.body)['is_subscribed'];
        
        // 2. 🚀 THE FIX: Sync to Global Admin Supabase instantly
        final supabase = Supabase.instance.client;
        if (isSubscribed) {
          await supabase.from('mp_subscriptions').insert({
            'subscriber_uid': subscriberUid,
            'channel_id': channelId
          });
          // Update global channel count
          await supabase.rpc('increment_subscriber_count', params: {'cid': channelId}); 
        } else {
          await supabase.from('mp_subscriptions').delete().match({
            'subscriber_uid': subscriberUid,
            'channel_id': channelId
          });
          // Decrease global channel count
          await supabase.rpc('decrement_subscriber_count', params: {'cid': channelId});
        }
        
        return isSubscribed;
      }
    } catch (e) { 
      debugPrint('Sub Toggle Error: $e'); 
    }
    return null;
  }
}